import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import '../widgets/accent_swatches.dart';

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
    if (mounted) {
      ref.invalidate(settingsProvider);
    }
  }

  Future<void> _nukeAll() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Nuke all notes?'),
        content: const Text(
          'This permanently deletes every note. This action cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All notes deleted.')));
      }
    }
  }

  Future<void> _exportAll() async {
    final store = _SimpleStoreFacade();
    final notes = store.getAllNotesSorted();
    final ok = await ExportService.exportAndShare(notes);
    if (mounted && ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export shared.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text('Settings'),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            _SettingsPanel(
              title: 'Appearance',
              icon: CupertinoIcons.paintbrush,
              children: [
                _ThemePicker(
                  current: _draft.themeKey,
                  onChanged: (k) {
                    setState(() => _draft = _draft.copyWith(themeKey: k));
                    _persist();
                  },
                ),
                _PanelLabel('Accent color'),
                AccentSwatches(
                  selectedIndex: _draft.accentIndex,
                  onSelected: (i) {
                    setState(() => _draft = _draft.copyWith(accentIndex: i));
                    _persist();
                  },
                ),
                _PanelLabel('Card style'),
                _CardStylePicker(
                  current: _draft.cardStyle,
                  onChanged: (style) {
                    setState(() => _draft = _draft.copyWith(cardStyle: style));
                    _persist();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsPanel(
              title: 'Defaults',
              icon: CupertinoIcons.clock,
              children: [
                _CompactLifetimeSetter(
                  title: 'Hum lifetime',
                  valueMinutes: _draft.defaultLifetimeMinutes,
                  isSteamMode: false,
                  onChanged: (v) {
                    setState(
                      () => _draft = _draft.copyWith(defaultLifetimeMinutes: v),
                    );
                    _persist();
                  },
                ),
                const SizedBox(height: 14),
                _CompactLifetimeSetter(
                  title: 'Puff lifetime',
                  valueMinutes: _draft.defaultSteamLifetimeMinutes,
                  isSteamMode: true,
                  onChanged: (v) {
                    setState(
                      () => _draft = _draft.copyWith(
                        defaultSteamLifetimeMinutes: v,
                      ),
                    );
                    _persist();
                  },
                ),
                _SwitchTile(
                  title: 'Auto-title notes',
                  value: _draft.autoGenerateTitle,
                  onChanged: (v) {
                    setState(
                      () => _draft = _draft.copyWith(autoGenerateTitle: v),
                    );
                    _persist();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsPanel(
              title: 'Expiry',
              icon: CupertinoIcons.hourglass,
              children: [
                _SwitchTile(
                  title: 'Show seconds under 1 hour',
                  value: _draft.showSecondsUnderOneHour,
                  onChanged: (v) {
                    setState(
                      () =>
                          _draft = _draft.copyWith(showSecondsUnderOneHour: v),
                    );
                    _persist();
                  },
                ),
                _SwitchTile(
                  title: 'Gentle notifications',
                  subtitle: 'Warn at 24 hours and 1 hour.',
                  value: _draft.gentleNotifications,
                  onChanged: (v) {
                    setState(
                      () => _draft = _draft.copyWith(gentleNotifications: v),
                    );
                    _persist();
                  },
                ),
                _SwitchTile(
                  title: 'Auto-copy before deletion',
                  subtitle: 'Copies notes detected near expiry on launch.',
                  value: _draft.autoCopyBeforeDeletion,
                  onChanged: (v) {
                    setState(
                      () => _draft = _draft.copyWith(autoCopyBeforeDeletion: v),
                    );
                    _persist();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsPanel(
              title: 'Data',
              icon: CupertinoIcons.lock,
              children: [
                _SettingTile(
                  title: 'Export notes as JSON',
                  icon: CupertinoIcons.square_arrow_up,
                  onTap: _exportAll,
                ),
                const SizedBox(height: 8),
                _DangerButton(onPressed: _nukeAll),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsPanel(
              title: 'Advanced',
              icon: CupertinoIcons.slider_horizontal_3,
              children: [
                _SettingTile(
                  title: 'Haptics',
                  trailing: Text(
                    ['Off', 'Light', 'Medium', 'Strong'][_draft.hapticsIntensity
                        .clamp(0, 3)],
                  ),
                  onTap: () async {
                    final i = await _pickHaptics(
                      context,
                      _draft.hapticsIntensity,
                    );
                    if (i != null) {
                      setState(
                        () => _draft = _draft.copyWith(hapticsIntensity: i),
                      );
                      await _persist();
                    }
                  },
                ),
                _SettingTile(
                  title: 'Animation speed',
                  trailing: Text(
                    AnimationSpeeds.labelFor(_draft.animationSpeed),
                  ),
                  onTap: () async {
                    final s = await _pickAnimation(
                      context,
                      _draft.animationSpeed,
                    );
                    if (s != null) {
                      setState(
                        () => _draft = _draft.copyWith(animationSpeed: s),
                      );
                      await _persist();
                    }
                  },
                ),
                _SwitchTile(
                  title: 'Show tab count',
                  value: _draft.showNoteCountInTabBar,
                  onChanged: (v) {
                    setState(
                      () => _draft = _draft.copyWith(showNoteCountInTabBar: v),
                    );
                    _persist();
                  },
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'Byepasser • Notes that say bye.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pickers

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
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Cancel'),
        ),
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
            child: Text(
              AnimationSpeeds.labelFor(s) + (s == current ? '  ✓' : ''),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

// Small presentational helpers

class _SettingsPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsPanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _PanelLabel extends StatelessWidget {
  final String text;

  const _PanelLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CardStylePicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _CardStylePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final itemWidth = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: CardStyles.all.map((style) {
            final selected = style == current;
            return SizedBox(
              width: itemWidth,
              height: 64,
              child: CupertinoButton(
                onPressed: () => onChanged(style),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: _cardStylePreviewDecoration(
                    colors,
                    style,
                    selected,
                  ),
                  child: Center(
                    child: Text(
                      CardStyles.labelFor(style),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? colors.textOnAccent
                            : colors.textPrimary,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

BoxDecoration _cardStylePreviewDecoration(
  ByepasserColors colors,
  String style,
  bool selected,
) {
  final radius = style == CardStyles.minimal ? 10.0 : 14.0;
  final baseColor = selected ? colors.accent : colors.cardAlt;

  if (style == CardStyles.elevated) {
    return BoxDecoration(
      color: baseColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: selected ? colors.accent : colors.divider,
        width: selected ? 1.2 : 0.5,
      ),
      boxShadow: [
        BoxShadow(
          color: colors.shadow.withValues(alpha: selected ? 0.9 : 0.5),
          blurRadius: 14,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  if (style == CardStyles.minimal) {
    return BoxDecoration(
      color: baseColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: selected ? colors.accent : colors.divider,
        width: selected ? 1.2 : 0.8,
      ),
    );
  }

  return BoxDecoration(
    color: baseColor.withValues(alpha: selected ? 1 : 0.76),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: selected ? colors.accent : colors.divider.withValues(alpha: 0.65),
      width: selected ? 1.2 : 0.5,
    ),
    boxShadow: [
      BoxShadow(
        color: colors.shadow.withValues(alpha: 0.35),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
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
            onChanged: (next) => onChanged(steps[next.round()]),
            activeColor: colors.accent,
          ),
          Text(
            formatFullLifetime(valueMinutes),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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

class _DangerButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DangerButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox(
      height: 46,
      child: CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.trash, color: colors.danger, size: 18),
              const SizedBox(width: 8),
              Text(
                'Nuke all notes',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.title,
    this.icon,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: colors.accent, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null)
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
                child: trailing!,
              ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              color: colors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
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
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
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

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final itemWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: ThemeKeys.all.map((k) {
            final selected = k == current;
            return SizedBox(
              width: itemWidth,
              height: 38,
              child: CupertinoButton(
                onPressed: () => onChanged(k),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: selected ? colors.accent : colors.cardAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? colors.accent : colors.divider,
                    ),
                  ),
                  child: Text(
                    ThemeKeys.labelFor(k),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? colors.textOnAccent
                          : colors.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
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
    await notesBox.put(id, note.copyWith(deletedAt: DateTime.now()));
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
