import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../theme/byepasser_theme.dart';
import '../widgets/accent_swatches.dart';
import '../widgets/lifetime_slider.dart';

/// Comprehensive Settings screen.
/// Appearance, Default Behavior, Expiry Behavior, Privacy & Cleanup, Advanced.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late AppSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(settingsProvider);
  }

  Future<void> _persist() async {
    // Persist to Hive (settingsProvider reads directly from the box)
    final store = _SimpleStoreFacade();
    await store.updateSettings(_draft);

    // Re-schedule notifications based on new gentle setting
    final notif = ref.read(notificationServiceProvider);
    if (_draft.gentleNotifications) {
      for (final n in store.getAllNotesSorted()) {
        await notif.scheduleExpiryReminders(n, _draft);
      }
    } else {
      await notif.cancelAll();
    }

    setState(() {}); // refresh local draft view
  }

  Future<void> _nukeAll() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Nuke all notes?'),
        content: const Text('This permanently deletes every note. This action cannot be undone.'),
        actions: [
          CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.of(ctx).pop(false)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Nuke Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final store = _SimpleStoreFacade();
      await store.deleteAllNotes();
      await ref.read(notificationServiceProvider).cancelAll();
      // Invalidate so any screen watching the notes list (e.g. the board) picks up the change.
      ref.invalidate(notesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All notes deleted.')));
      }
    }
  }

  Future<void> _exportAll() async {
    final store = _SimpleStoreFacade();
    final notes = store.getAllNotesSorted();
    final ok = await ExportService.exportAndShare(notes);
    if (mounted && ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export shared.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _SectionHeader('Appearance'),

            _ThemePicker(
              current: _draft.themeKey,
              onChanged: (k) {
                setState(() => _draft = _draft.copyWith(themeKey: k));
                _persist();
              },
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Accent color', style: Theme.of(context).textTheme.labelLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: AccentSwatches(
                selectedIndex: _draft.accentIndex,
                onSelected: (i) {
                  setState(() => _draft = _draft.copyWith(accentIndex: i));
                  _persist();
                },
              ),
            ),

            _SettingTile(
              title: 'Card style',
              trailing: Text(CardStyles.labelFor(_draft.cardStyle)),
              onTap: () async {
                final choice = await _pickCardStyle(context, _draft.cardStyle);
                if (choice != null) {
                  setState(() => _draft = _draft.copyWith(cardStyle: choice));
                  await _persist();
                }
              },
            ),

            const SizedBox(height: 16),
            _SectionHeader('Default Behavior'),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LifetimeSlider(
                valueMinutes: _draft.defaultLifetimeMinutes,
                onChanged: (v) {
                  setState(() => _draft = _draft.copyWith(defaultLifetimeMinutes: v));
                },
                isSteamMode: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                onPressed: _persist,
                child: const Text('Save as default lifetime'),
              ),
            ),

            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: LifetimeSlider(
                valueMinutes: _draft.defaultSteamLifetimeMinutes,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(defaultSteamLifetimeMinutes: v)),
                isSteamMode: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                onPressed: _persist,
                child: const Text('Save as default Puff lifetime'),
              ),
            ),

            _SwitchTile(
              title: 'Auto-generate title from first line',
              value: _draft.autoGenerateTitle,
              onChanged: (v) {
                setState(() => _draft = _draft.copyWith(autoGenerateTitle: v));
                _persist();
              },
            ),

            const SizedBox(height: 16),
            _SectionHeader('Expiry Behavior'),

            _SwitchTile(
              title: 'Show seconds when < 1 hour',
              value: _draft.showSecondsUnderOneHour,
              onChanged: (v) {
                setState(() => _draft = _draft.copyWith(showSecondsUnderOneHour: v));
                _persist();
              },
            ),
            _SwitchTile(
              title: 'Gentle notifications (24h + 1h before)',
              value: _draft.gentleNotifications,
              onChanged: (v) {
                setState(() => _draft = _draft.copyWith(gentleNotifications: v));
                _persist();
              },
            ),
            _SwitchTile(
              title: 'Auto-copy to clipboard 5 min before deletion',
              subtitle: 'Copies the note body when the app launches and detects a note is about to expire.',
              value: _draft.autoCopyBeforeDeletion,
              onChanged: (v) {
                setState(() => _draft = _draft.copyWith(autoCopyBeforeDeletion: v));
                _persist();
              },
            ),

            const SizedBox(height: 16),
            _SectionHeader('Privacy & Cleanup'),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: _nukeAll,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.trash, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Nuke all notes', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Emergency button. Deletes every note immediately.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),

            const SizedBox(height: 8),
            _SettingTile(
              title: 'Export all notes as JSON',
              onTap: _exportAll,
            ),

            const SizedBox(height: 16),
            _SectionHeader('Advanced'),

            _SettingTile(
              title: 'Haptic feedback intensity',
              trailing: Text(['Off', 'Light', 'Medium', 'Strong'][_draft.hapticsIntensity.clamp(0, 3)]),
              onTap: () async {
                final i = await _pickHaptics(context, _draft.hapticsIntensity);
                if (i != null) {
                  setState(() => _draft = _draft.copyWith(hapticsIntensity: i));
                  await _persist();
                }
              },
            ),

            _SettingTile(
              title: 'Animation speed',
              trailing: Text(AnimationSpeeds.labelFor(_draft.animationSpeed)),
              onTap: () async {
                final s = await _pickAnimation(context, _draft.animationSpeed);
                if (s != null) {
                  setState(() => _draft = _draft.copyWith(animationSpeed: s));
                  await _persist();
                }
              },
            ),

            _SwitchTile(
              title: 'Show note count in tab bar',
              value: _draft.showNoteCountInTabBar,
              onChanged: (v) {
                setState(() => _draft = _draft.copyWith(showNoteCountInTabBar: v));
                _persist();
              },
            ),

            const SizedBox(height: 60),
            Center(
              child: Text(
                'Byepasser • Notes that say bye.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.textSecondary.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // Pickers

  Future<String?> _pickCardStyle(BuildContext ctx, String current) async {
    return showCupertinoModalPopup<String>(
      context: ctx,
      builder: (c) => Container(
        color: Theme.of(ctx).extension<ByepasserColors>()!.card,
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in CardStyles.all)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(c).pop(s),
                child: Text(CardStyles.labelFor(s) + (s == current ? '  ✓' : '')),
              ),
          ],
        ),
      ),
    );
  }

  Future<int?> _pickHaptics(BuildContext ctx, int current) async {
    return showCupertinoModalPopup<int>(
      context: ctx,
      builder: (c) => CupertinoActionSheet(
        actions: List.generate(4, (i) {
          final labels = ['Off', 'Light', 'Medium', 'Strong'];
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.of(c).pop(i),
            child: Text(labels[i] + (i == current ? '  ✓' : '')),
          );
        }),
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
      ),
    );
  }

  Future<String?> _pickAnimation(BuildContext ctx, String current) async {
    return showCupertinoModalPopup<String>(
      context: ctx,
      builder: (c) => CupertinoActionSheet(
        actions: AnimationSpeeds.all.map((s) {
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.of(c).pop(s),
            child: Text(AnimationSpeeds.labelFor(s) + (s == current ? '  ✓' : '')),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
      ),
    );
  }
}

// Small presentational helpers

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingTile({required this.title, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(title),
      trailing: trailing ?? const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: CupertinoListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
        trailing: CupertinoSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _ThemePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: ThemeKeys.all.map((k) {
          final selected = k == current;
          return GestureDetector(
            onTap: () => onChanged(k),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? colors.accent : colors.cardAlt,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? colors.accent : colors.divider),
              ),
              child: Text(
                ThemeKeys.labelFor(k),
                style: TextStyle(
                  color: selected ? colors.textOnAccent : colors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Pragmatic facade for direct Hive access in Settings.
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
