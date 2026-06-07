import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../services/image_file_store.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import 'image_annotator_screen.dart';
import '../widgets/steam_released_dialog.dart';

const Duration _kEditorAutoSaveDelay = Duration(milliseconds: 650);

/// Full note creation + editing screen.
/// - Huge live countdown at top
/// - Title + body (markdown supported)
/// - Lifetime slider (or fixed for puff / quick ephemeral note)
/// - Color tag picker (0-7)
/// - Extend once (if not already extended)
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
    final isPickingAttachment = useState(false);

    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final settings = ref.watch(settingsProvider);
    final selectedBoard = ref.watch(selectedBoardProvider);
    final haptics = ref.read(hapticsProvider);
    final notif = ref.read(notificationServiceProvider);
    final store = _SimpleStoreFacade(); // same pragmatic facade as home
    final picker = useMemoized(ImagePicker.new);
    final autoSaveTimer = useRef<Timer?>(null);
    final autoSaveInFlight = useRef(false);
    final autoSaveCompleter = useRef<Completer<void>?>(null);
    final autoSaveRequested = useRef(false);
    final textEditRevision = useState(0);

    final canExtend = currentNote.value != null && !currentNote.value!.extended;

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

    String? resolvedTitle({required bool savingNewNote}) {
      final trimmedTitle = titleCtrl.text.trim();
      if (savingNewNote && isSteamMode) return null;
      if (trimmedTitle.isEmpty && settings.autoGenerateTitle) return null;
      return trimmedTitle;
    }

    _NoteEditorDraft currentDraft() {
      return _NoteEditorDraft(
        title: resolvedTitle(savingNewNote: false),
        body: bodyCtrl.text.trim(),
        colorTag: selectedTag.value,
        attachmentPaths: List<String>.from(attachmentPaths.value),
        lifetimeMinutes: lifetime.value,
      );
    }

    Note? applyDraftToNote(Note base, _NoteEditorDraft draft) {
      if (draft.body.isEmpty) return null;

      var updated = base.copyWith(
        title: draft.title,
        body: draft.body,
        colorTag: draft.colorTag,
        attachmentPaths: draft.attachmentPaths,
      );

      // If a lifetime control changes this existing note before it has used its
      // extension, preserve the original behavior and shift the expiry by delta.
      if (!base.extended && draft.lifetimeMinutes != base.lifetimeMinutes) {
        final diff = draft.lifetimeMinutes - base.lifetimeMinutes;
        updated = updated.copyWith(
          expiresAt: base.expiresAt.add(Duration(minutes: diff)),
          lifetimeMinutes: draft.lifetimeMinutes,
        );
      }

      return updated;
    }

    Future<Note?> persistExistingDraft({
      _NoteEditorDraft? draft,
      bool updateLocalState = true,
    }) async {
      final baseNote = currentNote.value;
      if (baseNote == null) return null;

      final latest = store.notesBox.get(baseNote.id) ?? baseNote;
      if (latest.isDeleted) return latest;

      final updated = applyDraftToNote(latest, draft ?? currentDraft());
      if (updated == null) return latest;

      if (_sameEditableNoteState(latest, updated)) {
        if (updateLocalState) currentNote.value = latest;
        return latest;
      }

      await store.updateNote(updated);
      await notif.scheduleExpiryReminders(updated, settings);
      if (updateLocalState) {
        currentNote.value = updated;
        ref.invalidate(notesProvider);
      }
      return updated;
    }

    Future<void> flushExistingAutoSave() async {
      autoSaveTimer.value?.cancel();
      autoSaveTimer.value = null;
      if (isNew || currentNote.value == null) return;

      if (autoSaveInFlight.value) {
        autoSaveRequested.value = true;
        await autoSaveCompleter.value?.future;
        return;
      }

      final completer = Completer<void>();
      autoSaveCompleter.value = completer;
      autoSaveInFlight.value = true;
      try {
        do {
          autoSaveRequested.value = false;
          await persistExistingDraft();
        } while (autoSaveRequested.value);
        if (!completer.isCompleted) completer.complete();
      } catch (_) {
        if (!completer.isCompleted) completer.complete();
        rethrow;
      } finally {
        autoSaveInFlight.value = false;
        if (autoSaveCompleter.value == completer) {
          autoSaveCompleter.value = null;
        }
      }
    }

    useEffect(() {
      void markTextChanged() => textEditRevision.value++;

      titleCtrl.addListener(markTextChanged);
      bodyCtrl.addListener(markTextChanged);
      return () {
        titleCtrl.removeListener(markTextChanged);
        bodyCtrl.removeListener(markTextChanged);
      };
    }, [titleCtrl, bodyCtrl]);

    useEffect(
      () {
        if (isNew || currentNote.value == null) return null;

        autoSaveTimer.value?.cancel();
        autoSaveTimer.value = Timer(_kEditorAutoSaveDelay, () {
          unawaited(flushExistingAutoSave().catchError((Object _) {}));
        });

        return () {
          autoSaveTimer.value?.cancel();
          autoSaveTimer.value = null;
        };
      },
      [
        isNew,
        textEditRevision.value,
        selectedTag.value,
        attachmentPaths.value,
        lifetime.value,
        currentNote.value?.id,
        settings.autoGenerateTitle,
      ],
    );

    useEffect(() {
      return () {
        autoSaveTimer.value?.cancel();
        autoSaveTimer.value = null;
        if (!isNew && currentNote.value != null) {
          unawaited(
            persistExistingDraft(
              draft: currentDraft(),
              updateLocalState: false,
            ).catchError((Object _) => null),
          );
        }
      };
    }, const []);

    Future<void> saveAndExit() async {
      final body = bodyCtrl.text.trim();
      if (body.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      if (isNew) {
        final title = resolvedTitle(savingNewNote: true);
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
        await flushExistingAutoSave();
      }

      // Bump so the home board (and any watchers) immediately see the new/updated note.
      ref.invalidate(notesProvider);

      await haptics.selection();
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> extendOnce() async {
      await flushExistingAutoSave();
      if (!context.mounted) return;
      final baseNote = currentNote.value;
      if (baseNote == null || baseNote.extended) {
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
      if (isPickingAttachment.value) return;
      isPickingAttachment.value = true;
      FocusManager.instance.primaryFocus?.unfocus();

      try {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!context.mounted) return;

        final picked = await picker.pickImage(
          source: source,
          imageQuality: 86,
          maxWidth: 1800,
          requestFullMetadata: false,
        );
        if (picked == null) return;

        final storedPath = await ImageFileStore.saveNoteAttachment(picked.path);
        attachmentPaths.value = [...attachmentPaths.value, storedPath];
        await haptics.selection();
        if (!context.mounted) return;
        final annotated = await openImageAnnotator(context, storedPath);
        if (annotated) {
          attachmentPaths.value = [...attachmentPaths.value];
          ref.invalidate(notesProvider);
        }
      } on PlatformException {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open image picker')),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not attach image')));
      } finally {
        if (context.mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          isPickingAttachment.value = false;
        }
      }
    }

    Future<void> removeAttachment(String path) async {
      final nextPaths = attachmentPaths.value
          .where((existing) => existing != path)
          .toList();
      attachmentPaths.value = nextPaths;

      final baseNote = currentNote.value;
      if (baseNote != null) {
        final latest = store.notesBox.get(baseNote.id) ?? baseNote;
        final updated = latest.copyWith(attachmentPaths: nextPaths);
        await store.updateNote(updated);
        currentNote.value = updated;
      }

      await store.removeImageLinks(path);
      await ImageFileStore.delete(path);
      ref.invalidate(notesProvider);
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
                          onPressed: isPickingAttachment.value
                              ? null
                              : () => addAttachment(ImageSource.camera),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AttachmentButton(
                          icon: CupertinoIcons.photo,
                          label: 'Image',
                          onPressed: isPickingAttachment.value
                              ? null
                              : () => addAttachment(ImageSource.gallery),
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
                      ? 'Extension used'
                      : 'One time extension',
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

class _NoteEditorDraft {
  final String? title;
  final String body;
  final int? colorTag;
  final List<String> attachmentPaths;
  final int lifetimeMinutes;

  const _NoteEditorDraft({
    required this.title,
    required this.body,
    required this.colorTag,
    required this.attachmentPaths,
    required this.lifetimeMinutes,
  });
}

bool _sameEditableNoteState(Note left, Note right) {
  return left.title == right.title &&
      left.body == right.body &&
      left.expiresAt == right.expiresAt &&
      left.lifetimeMinutes == right.lifetimeMinutes &&
      left.colorTag == right.colorTag &&
      _sameStringList(left.attachmentPaths, right.attachmentPaths);
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
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
  final VoidCallback? onPressed;

  const _AttachmentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final enabled = onPressed != null;
    final foreground = enabled ? colors.accent : colors.textSecondary;
    return SizedBox(
      height: 44,
      child: CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? colors.accent.withValues(alpha: 0.1)
                : colors.cardAlt.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? colors.accent.withValues(alpha: 0.25)
                  : colors.divider,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
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
                            ImageFileStore.resolve(path),
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

  Future<void> removeImageLinks(String imagePath) async {
    final now = DateTime.now();
    for (final note in notesBox.values.toList()) {
      if (note.isImageCrossReference &&
          note.crossReferenceImagePath != null &&
          _sameImagePath(note.crossReferenceImagePath!, imagePath)) {
        await notesBox.put(
          note.id,
          note.copyWith(
            attachmentPaths: const [],
            deletedAt: now,
            orderIndex: 0,
          ),
        );
        continue;
      }

      final nextAttachments = note.attachmentPaths
          .where((path) => !_sameImagePath(path, imagePath))
          .toList();
      if (nextAttachments.length != note.attachmentPaths.length) {
        await notesBox.put(
          note.id,
          note.copyWith(attachmentPaths: nextAttachments),
        );
      }
    }
  }

  bool _sameImagePath(String left, String right) {
    if (left == right) return true;
    final leftFile = ImageFileStore.resolve(left);
    final rightFile = ImageFileStore.resolve(right);
    if (leftFile.path == rightFile.path) return true;
    return ImageFileStore.canonicalStoredPath(left) ==
        ImageFileStore.canonicalStoredPath(right);
  }

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
