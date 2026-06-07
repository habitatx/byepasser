import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import '../widgets/lifetime_slider.dart';
import '../widgets/steam_particles.dart';
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

    final titleCtrl = useTextEditingController(text: note?.title ?? '');
    final bodyCtrl = useTextEditingController(text: note?.body ?? '');
    final lifetime = useState<int>(
      isSteamMode
          ? ref.read(settingsProvider).defaultSteamLifetimeMinutes
          : (note?.lifetimeMinutes ?? ref.read(settingsProvider).defaultLifetimeMinutes),
    );
    final selectedTag = useState<int?>(note?.colorTag);
    final showMarkdownPreview = useState<bool>(false);

    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final settings = ref.watch(settingsProvider);
    final haptics = ref.read(hapticsProvider);
    final notif = ref.read(notificationServiceProvider);
    final store = _SimpleStoreFacade(); // same pragmatic facade as home

    final canExtend = note != null && !note.extended && !note.isSteamMode;

    // Auto-generate title preview if setting enabled and title empty
    final effectiveTitle = useMemoized(() {
      if (titleCtrl.text.trim().isNotEmpty) return titleCtrl.text.trim();
      if (!settings.autoGenerateTitle) return '';
      final first = bodyCtrl.text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      return first.length > 48 ? '${first.substring(0, 45)}...' : first;
    }, [titleCtrl.text, bodyCtrl.text, settings.autoGenerateTitle]);

    // Live remaining
    final expiresAt = useMemoized(() {
      if (note != null && !isNew) {
        return note.expiresAt;
      }
      return DateTime.now().add(Duration(minutes: lifetime.value));
    }, [lifetime.value, note]);

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
          title: title,
          isSteamMode: isSteamMode,
          colorTag: selectedTag.value,
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
      if (note == null) return;
      final updated = note.copyWith(
        expiresAt: note.expiresAt.add(const Duration(minutes: 60 * 24)), // +1 day reasonable extension
        lifetimeMinutes: note.lifetimeMinutes + 60 * 24,
        extended: true,
      );
      await store.updateNote(updated);
      await notif.scheduleExpiryReminders(updated, settings);
      ref.invalidate(notesProvider);
      await haptics.medium();
      if (context.mounted) Navigator.of(context).pop();
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
          const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
        );
      }
    }

    Future<void> shareNote() async {
      final text = effectiveTitle.isNotEmpty
          ? '$effectiveTitle\n\n${bodyCtrl.text}'
          : bodyCtrl.text;
      await SharePlus.instance.share(ShareParams(text: text, subject: effectiveTitle.isNotEmpty ? effectiveTitle : 'Byepasser note'));
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        middle: Text(isNew ? (isSteamMode ? 'A Puff' : 'New Note') : 'Note'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: saveAndExit,
          child: Text(isNew ? 'Save' : 'Done', style: TextStyle(color: colors.accent)),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // Huge countdown
            Center(
              child: Column(
                children: [
                  Text(
                    'Expires in',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                  ),
                  const SizedBox(height: 4),
                  CountdownHero(
                    expiresAt: expiresAt,
                    showSeconds: settings.showSecondsUnderOneHour,
                    originalLifetimeMinutes: lifetime.value,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Puff / ephemeral visual treatment (steam particles)
            if (isSteamMode || (note?.isSteamMode ?? false))
              Container(
                height: 78,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: colors.card.withValues(alpha: 0.6),
                ),
                clipBehavior: Clip.antiAlias,
                child: const SteamParticles(intensity: 1.1, dense: true),
              ),

            // Title field
            CupertinoTextField(
              controller: titleCtrl,
              placeholder: 'Title (optional)',
              style: Theme.of(context).textTheme.titleLarge,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider),
              ),
              onChanged: (_) => {}, // triggers rebuilds via hooks
            ),

            const SizedBox(height: 12),

            // Body editor / preview
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        // Constrain the segmented control to avoid right overflow on narrow screens.
                        Flexible(
                          child: CupertinoSegmentedControl<bool>(
                            groupValue: showMarkdownPreview.value,
                            // Explicit colors to prevent theme leakage (e.g. unwanted yellow borders/highlights)
                            // and ensure it looks correct across all 5 Byepasser themes.
                            selectedColor: colors.accent,
                            unselectedColor: colors.cardAlt,
                            borderColor: colors.divider,
                            pressedColor: colors.accent.withValues(alpha: 0.2),
                            children: {
                              false: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                child: Text(
                                  'Edit',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: showMarkdownPreview.value ? colors.textSecondary : colors.textOnAccent,
                                      ),
                                ),
                              ),
                              true: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                child: Text(
                                  'Preview',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: showMarkdownPreview.value ? colors.textOnAccent : colors.textSecondary,
                                      ),
                                ),
                              ),
                            },
                            onValueChanged: (v) => showMarkdownPreview.value = v,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (showMarkdownPreview.value)
                          Text('Markdown', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.textSecondary)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (!showMarkdownPreview.value)
                    CupertinoTextField(
                      controller: bodyCtrl,
                      placeholder: 'Write something…\n\nSupports *italic*, **bold**, and simple lists.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 12,
                      minLines: 6,
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(),
                    )
                  else
                    Container(
                      height: 220,
                      padding: const EdgeInsets.all(14),
                      alignment: Alignment.topLeft,
                      child: Markdown(
                        data: bodyCtrl.text.isEmpty ? '_Nothing to preview yet._' : bodyCtrl.text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          p: Theme.of(context).textTheme.bodyLarge,
                          listBullet: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Smart lifetime suggestion (local heuristics — feels AI-powered)
            if (!isSteamMode && (note?.isSteamMode ?? false) == false)
              _SmartLifetimeSuggestion(
                body: bodyCtrl.text,
                current: lifetime.value,
                onApply: (suggested) {
                  lifetime.value = suggested;
                  haptics.selection();
                },
              ),

            // Lifetime
            LifetimeSlider(
              valueMinutes: lifetime.value,
              onChanged: (v) => lifetime.value = v,
              isSteamMode: isSteamMode || (note?.isSteamMode ?? false),
            ),

            const SizedBox(height: 22),

            // Color tags
            Text('Color tag', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.textSecondary)),
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
              if (canExtend)
                FilledButton.icon(
                  onPressed: extendOnce,
                  icon: const Icon(CupertinoIcons.time),
                  label: const Text('Extend once (1 day)'),
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
            : colors.textSecondary.withValues(alpha: 0.4);

    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 5,
              color: colors.divider,
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
                  strokeWidth: 5,
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
              Text(
                text,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 28,
                      letterSpacing: -1.0,
                      color: isCritical ? colors.danger : colors.textPrimary,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                isCritical ? 'Almost gone' : isUrgent ? 'Running out' : 'Plenty of time',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  letterSpacing: 0.5,
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
                  color: selected == i ? colors.textPrimary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: selected == i ? Icon(Icons.check, size: 16, color: colors.textOnAccent) : null,
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

class _SmartLifetimeSuggestion extends StatelessWidget {
  final String body;
  final int current;
  final ValueChanged<int> onApply;

  const _SmartLifetimeSuggestion({
    required this.body,
    required this.current,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final suggested = suggestLifetimeMinutes(body);
    final reason = getSuggestionReason(body);

    if ((suggested - current).abs() < 5) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => onApply(suggested),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 15, color: colors.accent),
              const SizedBox(width: 6),
              Text(
                'Smart: ${formatFullLifetime(suggested)}',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '• $reason',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final toRemove = notesBox.values.where((n) => now.isAfter(n.expiresAt)).toList();
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

  Future<void> deleteNote(String id) async => notesBox.delete(id);

  Future<void> deleteAllNotes() async => notesBox.clear();

  List<Note> getAllNotesSorted() {
    final l = notesBox.values.toList();
    l.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });
    return l;
  }

  List<Note> getDyingSoonNotes({Duration threshold = const Duration(hours: 6)}) => [];

  int get noteCount => notesBox.length;

  Future<void> updateSettings(AppSettings s) async => settingsBox.put('user', s);
}
