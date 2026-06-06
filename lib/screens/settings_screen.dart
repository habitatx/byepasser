import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import '../widgets/accent_swatches.dart';
import '../widgets/app_surface.dart';
import '../widgets/lifetime_slider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Settings'),
            backgroundColor: palette.background.withValues(alpha: 0.82),
            border: Border(bottom: BorderSide(color: palette.divider)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
            sliver: SliverList.list(
              children: [
                _SettingsSection(
                  title: 'Appearance',
                  children: [
                    _ThemePicker(settings: settings),
                    _Divider(),
                    _SettingsBlockLabel('Accent color'),
                    const SizedBox(height: 12),
                    AccentSwatches(
                      selectedIndex: settings.accentIndex,
                      onSelected: (index) async {
                        if (index == null) {
                          return;
                        }
                        await ref
                            .read(settingsProvider.notifier)
                            .setAccent(index);
                      },
                    ),
                    _Divider(),
                    _SegmentedSetting(
                      label: 'Card style',
                      value: settings.cardStyle,
                      values: CardStyles.all,
                      labelFor: ByepasserTheme.cardStyleLabel,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .setCardStyle(value);
                      },
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Default Behavior',
                  children: [
                    LifetimeSlider(
                      value: settings.defaultLifetimeMinutes,
                      min: minLifetimeMinutes,
                      max: maxLifetimeMinutes,
                      presets: lifetimePresets,
                      label: 'Default lifetime',
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .setDefaultLifetime(value);
                      },
                    ),
                    _Divider(),
                    LifetimeSlider(
                      value: settings.defaultSteamLifetimeMinutes,
                      min: minSteamLifetimeMinutes,
                      max: maxSteamLifetimeMinutes,
                      presets: steamLifetimePresets,
                      label: 'Default Steam lifetime',
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .setDefaultSteamLifetime(value);
                      },
                    ),
                    _Divider(),
                    _SwitchSetting(
                      label: 'Auto-generate title',
                      value: settings.autoGenerateTitle,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(
                              settings.copyWith(autoGenerateTitle: value),
                            );
                      },
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Expiry Behavior',
                  children: [
                    _SwitchSetting(
                      label: 'Show seconds under 1 hour',
                      value: settings.showSecondsUnderHour,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(
                              settings.copyWith(showSecondsUnderHour: value),
                            );
                      },
                    ),
                    _Divider(),
                    _SwitchSetting(
                      label: 'Gentle expiry notifications',
                      value: settings.gentleNotifications,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(
                              settings.copyWith(gentleNotifications: value),
                            );
                        await ref
                            .read(notesProvider.notifier)
                            .syncNotifications();
                      },
                    ),
                    _Divider(),
                    _SwitchSetting(
                      label: 'Auto-copy 5 min before deletion',
                      value: settings.autoCopyBeforeDeletion,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(
                              settings.copyWith(autoCopyBeforeDeletion: value),
                            );
                      },
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Privacy & Cleanup',
                  children: [
                    _StaticSetting(
                      label: 'Auto-clean expired notes',
                      value: 'Always on',
                    ),
                    _Divider(),
                    _DangerButton(
                      label: 'Nuke all notes',
                      onPressed: () => _confirmNuke(context, ref),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Advanced',
                  children: [
                    _SegmentedSetting(
                      label: 'Haptics',
                      value: settings.hapticIntensity,
                      values: HapticIntensity.all,
                      labelFor: ByepasserTheme.hapticLabel,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(settings.copyWith(hapticIntensity: value));
                        await HapticsService.tap(ref.read(settingsProvider));
                      },
                    ),
                    _Divider(),
                    _SegmentedSetting(
                      label: 'Animation speed',
                      value: settings.animationSpeed,
                      values: AnimationSpeeds.all,
                      labelFor: ByepasserTheme.speedLabel,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(settings.copyWith(animationSpeed: value));
                      },
                    ),
                    _Divider(),
                    _SwitchSetting(
                      label: 'Show note count in tab bar',
                      value: settings.showNoteCountInTabBar,
                      onChanged: (value) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(
                              settings.copyWith(showNoteCountInTabBar: value),
                            );
                      },
                    ),
                    _Divider(),
                    _ActionSetting(
                      icon: CupertinoIcons.square_arrow_up,
                      label: 'Export all notes as JSON',
                      onPressed: () => _export(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Column(
      children: ThemeKeys.all.map((key) {
        final selected = settings.themeKey == key;
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            await ref.read(settingsProvider.notifier).setTheme(key);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ByepasserTheme.themeLabel(key),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  color: selected ? palette.accent : palette.mutedText,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          AppSurface(
            borderRadius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsBlockLabel extends StatelessWidget {
  const _SettingsBlockLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      label,
      style: TextStyle(
        color: palette.text,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        CupertinoSwitch(
          value: value,
          activeTrackColor: palette.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StaticSetting extends StatelessWidget {
  const _StaticSetting({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: palette.mutedText,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SegmentedSetting extends StatelessWidget {
  const _SegmentedSetting({
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final String Function(String) labelFor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsBlockLabel(label),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: value,
            thumbColor: palette.accent,
            backgroundColor: palette.cardStrong,
            children: {
              for (final option in values)
                option: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    labelFor(option),
                    style: TextStyle(
                      color: option == value ? palette.onAccent : palette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            },
            onValueChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ActionSetting extends StatelessWidget {
  const _ActionSetting({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(icon, color: palette.accent, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(
            CupertinoIcons.chevron_forward,
            color: palette.mutedText,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: palette.urgent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.urgent.withValues(alpha: 0.38)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.urgent,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(color: palette.divider, height: 1),
    );
  }
}

Future<void> _confirmNuke(BuildContext context, WidgetRef ref) async {
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) {
      return CupertinoAlertDialog(
        title: const Text('Nuke all notes?'),
        content: const Text('Every local note will be deleted immediately.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Nuke'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    await ref.read(notesProvider.notifier).nukeAll();
    await HapticsService.success(ref.read(settingsProvider));
  }
}

Future<void> _export(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final notes = ref.read(notesProvider);
  final file = await ref
      .read(exportServiceProvider)
      .createJsonExport(notes: notes, settings: settings);

  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      subject: 'Byepasser export',
      text: 'Byepasser JSON export',
    ),
  );
}
