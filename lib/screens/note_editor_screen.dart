import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import 'image_annotator_screen.dart';
import '../widgets/steam_released_dialog.dart';

/// Full note creation + editing screen.
/// - Huge live countdown at top
/// - Title + body (markdown supported)
/// - Lifetime slider (or fixed for puff / quick ephemeral note)
/// - Color tag picker (0-7)
/// - Extend once (if not a puff and not already extended)
/// - Prominent Copy + Share (iOS share sheet)
/// - Burn Now for Puff notes
class NoteEditorScreen extends HookConsumerWidget {
  final Note? existingNote;
  final bool isSteamMode;

  const NoteEditorScreen({
    super.key,
    this.existingNote,
    this.isSteamMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNew = existingNote == null;
    final note = existingNote;
    final currentNote = useState<Note?>(note);

    final titleCtrl = useTextEditingController(text: note?.title ?? '');
    final bodyCtrl = useTextEditingController(text: note?.body ?? '');
    final lifetime = useState<int>(
      isSteamMode
          ? ref.read(settingsProvider).defaultSteamLifetimeMinutes
          : (note?.lifetimeMinutes ??
                ref.read(settingsProvider).defaultLifetimeMinutes),
    );
    final selectedTag = useState<int?>(note?.colorTag);
    final attachmentPaths = useState<List<String>>(
      List<String>.from(note?.attachmentPaths ?? const <String>[]),
    );

    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final settings = ref.watch(settingsProvider);
    final selectedBoard = ref.watch(selectedBoardProvider);
    final haptics = ref.read(hapticsProvider);
    final notif = ref.read(notificationServiceProvider);
    final store = _SimpleStoreFacade(); // same pragmatic facade as home
    final picker = useMemoized(ImagePicker.new);

    final canExtend =
        currentNote.value != null &&
        !currentNote.value!.extended &&
        !currentNote.value!.isSteamMode;

    // Auto-generate title preview if setting enabled and title empty
    final effectiveTitle = useMemoized(() {
      if (titleCtrl.text.trim().isNotEmpty) return titleCtrl.text.trim();
      if (!settings.autoGenerateTitle) return '';
      final first = bodyCtrl.text
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      return first.length > 48 ? '${first.substring(0, 45)}...' : first;
    }, [titleCtrl.text, bodyCtrl.text, settings.autoGenerateTitle]);

    // Live remaining
    final expiresAt = useMemoized(() {
      if (note != null && !isNew) {
        return currentNote.value?.expiresAt ?? note.expiresAt;
      }
      return DateTime.now().add(Duration(minutes: lifetime.value));
    }, [lifetime.value, currentNote.value]);

    useEffect(() {
      // If editing existing, lock lifetime slider unless extending
      return null;
    }, const []);

    Future<void> saveAndExit() async {
      final body = bodyCtrl.text.trim();
      if (body.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      final title = titleCtrl.text.trim().isEmpty && settings.autoGenerateTitle
          ? null
          : titleCtrl.text.trim();

      if (isNew) {
        final newNote = Note.create(
          body: body,
          lifetimeMinutes: lifetime.value,
          title: isSteamMode ? null : title,
          isSteamMode: isSteamMode,
          colorTag: selectedTag.value,
          attachmentPaths: attachmentPaths.value,
          boardId: selectedBoard.id,
        );
        await store.addNote(newNote);
        await notif.scheduleExpiryReminders(newNote, settings);
        // box mutated — provider reads live from Hive.
      } else {
        // Update
        var updated = note!.copyWith(
          title: title,
          body: body,
          colorTag: selectedTag.value,
          attachmentPaths: attachmentPaths.value,
        );

        // If user changed lifetime on an existing non-extended note, allow it (treat as first set)
        if (!note.extended && lifetime.value != note.lifetimeMinutes) {
          final diff = lifetime.value - note.lifetimeMinutes;
          updated = updated.copyWith(
            expiresAt: note.expiresAt.add(Duration(minutes: diff)),
            lifetimeMinutes: lifetime.value,
          );
        }

        await store.updateNote(updated);
        await notif.scheduleExpiryReminders(updated, settings);
        // box mutated — provider reads live from Hive.
      }

      // Bump so the home board (and any watchers) immediately see the new/updated note.
      ref.invalidate(notesProvider);

      await haptics.selection();
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> extendOnce() async {
      final baseNote = currentNote.value;
      if (baseNote == null || baseNote.extended || baseNote.isSteamMode) {
        return;
      }
      final extensionMinutes = await _showExtendLifetimeDialog(context);
      if (extensionMinutes == null) return;

      final updated = baseNote.copyWith(
        expiresAt: baseNote.expiresAt.add(Duration(minutes: extensionMinutes)),
        lifetimeMinutes: baseNote.lifetimeMinutes + extensionMinutes,
        extended: true,
      );
      await store.updateNote(updated);
      await notif.scheduleExpiryReminders(updated, settings);
      currentNote.value = updated;
      ref.invalidate(notesProvider);
      await haptics.medium();
    }

    Future<void> burnNow() async {
      if (note == null) return;
      await store.deleteNote(note.id);
      await notif.cancelForNote(note.id);
      ref.invalidate(notesProvider);
      await haptics.success();
      if (context.mounted) {
        Navigator.of(context).pop();
        await showSteamReleased(context);
      }
    }

    Future<void> copyBody() async {
      await ExportService.copyToClipboard(bodyCtrl.text);
      await haptics.light();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }

    Future<void> shareNote() async {
      final text = effectiveTitle.isNotEmpty
          ? '$effectiveTitle\n\n${bodyCtrl.text}'
          : bodyCtrl.text;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: effectiveTitle.isNotEmpty
              ? effectiveTitle
              : 'Byepasser note',
        ),
      );
    }

    Future<void> addAttachment(ImageSource source) async {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1800,
      );
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final safeExt = ext.length <= 5 ? ext : 'jpg';
      final fileName =
          'note_attachment_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final target = File('${dir.path}/$fileName');
      await File(picked.path).copy(target.path);
      attachmentPaths.value = [...attachmentPaths.value, target.path];
      await haptics.selection();
      if (!context.mounted) return;
      final annotated = await openImageAnnotator(context, target.path);
      if (annotated) {
        attachmentPaths.value = [...attachmentPaths.value];
        ref.invalidate(notesProvider);
      }
    }

    void removeAttachment(String path) {
      attachmentPaths.value = attachmentPaths.value
          .where((existing) => existing != path)
          .toList();
      final file = File(path);
      if (file.existsSync()) {
        file.delete().ignore();
      }
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text(isNew ? (isSteamMode ? 'A Puff' : 'New Note') : 'Note'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: saveAndExit,
          child: Text(
            isNew ? 'Save' : 'Done',
            style: TextStyle(color: colors.accent),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 22),
              child: Center(
                child: CountdownHero(
                  expiresAt: expiresAt,
                  showSeconds: settings.showSecondsUnderOneHour,
                  originalLifetimeMinutes: lifetime.value,
                ),
              ),
            ),

            // Editor
            _EditorPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  CupertinoTextField(
                    controller: titleCtrl,
                    placeholder: 'Title (optional)',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    placeholderStyle: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: colors.textSecondary),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: const BoxDecoration(),
                    onChanged: (_) => {}, // triggers rebuilds via hooks
                  ),
                  Divider(height: 1, color: colors.divider),
                  CupertinoTextField(
                    controller: bodyCtrl,
                    placeholder: 'Write something...',
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 8,
                    minLines: 3,
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _EditorPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _AttachmentButton(
                          icon: CupertinoIcons.camera,
                          label: 'Camera',
                          onPressed: () => addAttachment(ImageSource.camera),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AttachmentButton(
                          icon: CupertinoIcons.photo,
                          label: 'Image',
                          onPressed: () => addAttachment(ImageSource.gallery),
                        ),
                      ),
                    ],
                  ),
                  if (attachmentPaths.value.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _AttachmentGrid(
                      paths: attachmentPaths.value,
                      onAnnotate: (path) async {
                        final annotated = await openImageAnnotator(
                          context,
                          path,
                        );
                        if (annotated) {
                          attachmentPaths.value = [...attachmentPaths.value];
                          ref.invalidate(notesProvider);
                        }
                      },
                      onRemove: removeAttachment,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Color tags
            Text(
              'Color tag',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            _ColorTagPicker(
              selected: selectedTag.value,
              onSelected: (i) => selectedTag.value = i,
            ),

            const SizedBox(height: 28),

            // Actions
            if (!isNew) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: copyBody,
                      icon: const Icon(CupertinoIcons.doc_on_clipboard),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: shareNote,
                      icon: const Icon(CupertinoIcons.share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canExtend ? extendOnce : null,
                icon: const Icon(CupertinoIcons.time),
                label: Text(
                  currentNote.value?.extended == true
                      ? 'Lifetime extended'
                      : 'Extend lifetime',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent.withValues(alpha: 0.9),
                ),
              ),
              if (note?.isSteamMode ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.icon(
                    onPressed: burnNow,
                    icon: const Icon(CupertinoIcons.flame),
                    label: const Text('Burn Now'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.danger,
                    ),
                  ),
                ),
            ],

            if (isNew)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  onPressed: saveAndExit,
                  child: Text(isSteamMode ? 'Release a Puff' : 'Create Note'),
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

Future<int?> _showExtendLifetimeDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _ExtendLifetimeDialog(),
  );
}

class _ExtendLifetimeDialog extends StatefulWidget {
  const _ExtendLifetimeDialog();

  @override
  State<_ExtendLifetimeDialog> createState() => _ExtendLifetimeDialogState();
}

class _ExtendLifetimeDialogState extends State<_ExtendLifetimeDialog> {
  int _minutes = 24 * 60;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          colors.cardStyle == CardStyles.minimal ? 10 : 18,
        ),
      ),
      child: _EditorPanel(
        margin: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompactLifetimeSetter(
              title: 'Extend by',
              valueMinutes: _minutes,
              isSteamMode: false,
              onChanged: (value) => setState(() => _minutes = value),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_minutes),
                    child: const Text('Extend time'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const _EditorPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      margin: margin,
      padding: padding,
      decoration: colors.cardDecoration(),
      child: child,
    );
  }
}

class _CompactLifetimeSetter extends StatelessWidget {
  final String title;
  final int valueMinutes;
  final bool isSteamMode;
  final ValueChanged<int> onChanged;

  const _CompactLifetimeSetter({
    required this.title,
    required this.valueMinutes,
    required this.isSteamMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final steps = isSteamMode
        ? const <int>[5, 10, 15, 20, 25, 30]
        : const <int>[
            15,
            30,
            60,
            2 * 60,
            4 * 60,
            8 * 60,
            12 * 60,
            24 * 60,
            2 * 24 * 60,
            3 * 24 * 60,
            7 * 24 * 60,
            14 * 24 * 60,
            30 * 24 * 60,
          ];
    final selectedIndex = _nearestLifetimeStepIndex(valueMinutes, steps);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        CupertinoSlider(
          value: selectedIndex.toDouble(),
          min: 0,
          max: (steps.length - 1).toDouble(),
          divisions: steps.length - 1,
          activeColor: colors.accent,
          onChanged: (next) => onChanged(steps[next.round()]),
        ),
        Text(
          formatFullLifetime(valueMinutes),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

int _nearestLifetimeStepIndex(int minutes, List<int> steps) {
  var nearestIndex = 0;
  var nearestDistance = (minutes - steps.first).abs();
  for (var i = 1; i < steps.length; i++) {
    final distance = (minutes - steps[i]).abs();
    if (distance < nearestDistance) {
      nearestIndex = i;
      nearestDistance = distance;
    }
  }
  return nearestIndex;
}

class CountdownHero extends StatelessWidget {
  final DateTime expiresAt;
  final bool showSeconds;
  final int? originalLifetimeMinutes;

  const CountdownHero({
    super.key,
    required this.expiresAt,
    required this.showSeconds,
    this.originalLifetimeMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = expiresAt.difference(DateTime.now());
    final text = formatRemaining(remaining, showSeconds: showSeconds);
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    final total = (originalLifetimeMinutes ?? 60 * 24).toDouble();
    final elapsed = total - (remaining.inSeconds / 60.0);
    final progress = (1.0 - (elapsed / total)).clamp(0.0, 1.0);

    final isCritical = remaining.inMinutes < 15;
    final isUrgent = remaining.inMinutes < 60;

    final ringColor = isCritical
        ? colors.danger
        : isUrgent
        ? colors.accent
        : colors.success;

    return SizedBox(
      width: 142,
      height: 142,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 24,
              color: ringColor.withValues(alpha: 0.16),
            ),
          ),
          // Progress ring (animated)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: progress, end: progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 24,
                  color: ringColor,
                  strokeCap: StrokeCap.round,
                ),
              );
            },
          ),
          // Center content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: text,
                  style: TextStyle(
                    inherit: false,
                    fontSize: 22,
                    height: 1.0,
                    letterSpacing: 0,
                    color: isCritical ? colors.danger : colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: isCritical
                      ? 'Almost gone'
                      : isUrgent
                      ? 'Running out'
                      : 'Plenty of time',
                  style: TextStyle(
                    inherit: false,
                    fontSize: 10,
                    height: 1.0,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorTagPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onSelected;

  const _ColorTagPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = ByepasserTheme.accentPalette;
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (int i = 0; i < palette.length; i++)
          GestureDetector(
            onTap: () => onSelected(selected == i ? null : i),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: palette[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == i
                      ? colors.textPrimary
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: selected == i
                  ? Icon(Icons.check, size: 16, color: colors.textOnAccent)
                  : null,
            ),
          ),
        GestureDetector(
          onTap: () => onSelected(null),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.divider, width: 1.5),
            ),
            child: Icon(Icons.block, size: 16, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AttachmentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox(
      height: 44,
      child: CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentGrid extends StatelessWidget {
  final List<String> paths;
  final ValueChanged<String> onAnnotate;
  final ValueChanged<String> onRemove;

  const _AttachmentGrid({
    required this.paths,
    required this.onAnnotate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final tileWidth = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final path in paths)
              SizedBox(
                width: tileWidth,
                height: tileWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => onAnnotate(path),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: colors.cardAlt,
                              alignment: Alignment.center,
                              child: Icon(
                                CupertinoIcons.photo,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => onRemove(path),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: colors.card.withValues(alpha: 0.86),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 15,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Pragmatic store facade (duplicated for self-contained file)
class _SimpleStoreFacade {
  Box<Note> get notesBox => Hive.box<Note>('notes');
  Box<AppSettings> get settingsBox => Hive.box<AppSettings>('settings');

  AppSettings get settings => settingsBox.get('user') ?? AppSettings.defaults();

  Future<int> sweepExpiredNotes() async {
    final now = DateTime.now();
    final toRemove = notesBox.values
        .where((n) => !n.isDeleted && now.isAfter(n.expiresAt))
        .toList();
    for (final n in toRemove) {
      await notesBox.delete(n.id);
    }
    return toRemove.length;
  }

  Future<Note> addNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<Note> updateNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<void> deleteNote(String id) async {
    final note = notesBox.get(id);
    if (note == null) return;
    await notesBox.put(
      id,
      note.copyWith(deletedAt: DateTime.now(), orderIndex: 0, indentLevel: 0),
    );
  }

  Future<void> deleteAllNotes() async => notesBox.clear();

  List<Note> getAllNotesSorted() {
    final l = notesBox.values.where((note) => note.isVisibleBoardNote).toList();
    l.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });
    return l;
  }

  List<Note> getDyingSoonNotes({
    Duration threshold = const Duration(hours: 6),
  }) => [];

  int get noteCount =>
      notesBox.values.where((note) => note.isVisibleBoardNote).length;

  Future<void> updateSettings(AppSettings s) async =>
      settingsBox.put('user', s);
}
