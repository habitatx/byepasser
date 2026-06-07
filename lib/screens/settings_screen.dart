import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../models/app_stats.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../services/gamification_service.dart';
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
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(settingsProvider);
  }

  Future<void> _persist() async {
    // Persist to Hive (settingsProvider reads directly from the box)
    final store = _SimpleStoreFacade();
    await store.updateSettings(_draft);
    await GamificationService.recordSettingsChange(ref);

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
    final stats = ref.watch(appStatsProvider);
    final notes = ref.watch(notesProvider);
    final now = DateTime.now();
    final soon = now.add(const Duration(hours: 6));
    final visibleNotes = notes
        .where((note) => note.isVisibleBoardNote)
        .toList();
    final activePuffs = visibleNotes.where((note) => note.isSteamMode).length;
    final activeHums = visibleNotes.length - activePuffs;
    final dyingSoonCount = visibleNotes
        .where(
          (note) =>
              note.expiresAt.isBefore(soon) && !now.isAfter(note.expiresAt),
        )
        .length;
    final recycledCount = notes
        .where((note) => note.isDeleted && !note.isImageCrossReference)
        .length;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: _SettingsTopCapsule(
          selectedIndex: _selectedTab,
          onChanged: (index) => setState(() => _selectedTab = index),
        ),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            if (_selectedTab == 1) ...[
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
                      setState(
                        () => _draft = _draft.copyWith(cardStyle: style),
                      );
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
                        () =>
                            _draft = _draft.copyWith(defaultLifetimeMinutes: v),
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
                        () => _draft = _draft.copyWith(
                          showSecondsUnderOneHour: v,
                        ),
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
                        () =>
                            _draft = _draft.copyWith(autoCopyBeforeDeletion: v),
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
                      ['Off', 'Light', 'Medium', 'Strong'][_draft
                          .hapticsIntensity
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
                        () =>
                            _draft = _draft.copyWith(showNoteCountInTabBar: v),
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
            ] else ...[
              _PuffHumDashboard(
                stats: stats,
                activePuffs: activePuffs,
                activeHums: activeHums,
                dyingSoonCount: dyingSoonCount,
                recycledCount: recycledCount,
              ),
            ],
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

class _SettingsTopCapsule extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SettingsTopCapsule({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: colors.appBarCapsuleDecoration(color: colors.card),
      child: Row(
        children: [
          Expanded(
            child: _SettingsTopTab(
              label: 'Puff & Hum',
              icon: CupertinoIcons.sparkles,
              selected: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SettingsTopTab(
              label: 'Settings',
              icon: CupertinoIcons.settings,
              selected: selectedIndex == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTopTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsTopTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? colors.textOnAccent : colors.textSecondary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? colors.textOnAccent : colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PuffHumDashboard extends StatelessWidget {
  final AppStats stats;
  final int activePuffs;
  final int activeHums;
  final int dyingSoonCount;
  final int recycledCount;

  const _PuffHumDashboard({
    required this.stats,
    required this.activePuffs,
    required this.activeHums,
    required this.dyingSoonCount,
    required this.recycledCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashboardHeroCard(stats: stats),
        const SizedBox(height: 12),
        _ScoreboardCard(stats: stats),
        const SizedBox(height: 12),
        _ReleaseBalanceCard(
          stats: stats,
          activePuffs: activePuffs,
          activeHums: activeHums,
        ),
        const SizedBox(height: 12),
        _LifetimeReleaseCard(stats: stats),
        const SizedBox(height: 12),
        _InsightCard(
          insight: _dashboardInsight(
            stats,
            activePuffs: activePuffs,
            activeHums: activeHums,
            dyingSoonCount: dyingSoonCount,
            recycledCount: recycledCount,
          ),
          dyingSoonCount: dyingSoonCount,
          recycledCount: recycledCount,
        ),
        const SizedBox(height: 12),
        _StatsGrid(
          stats: stats,
          activePuffs: activePuffs,
          activeHums: activeHums,
        ),
        const SizedBox(height: 12),
        const _PointRulesCard(),
      ],
    );
  }
}

class _DashboardHeroCard extends StatelessWidget {
  final AppStats stats;

  const _DashboardHeroCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final score = stats.activeScoreSet;
    final progress = score.pointsIntoLevel / 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActiveScoreboardStrip(score: score),
          const SizedBox(height: 12),
          _BadgeTrophyCase(stats: stats, score: score),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _levelName(score.level),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_compactNumber(score.points)} points',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${score.level}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      'level',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: colors.cardAlt),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                    child: ColoredBox(color: colors.accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${100 - score.pointsIntoLevel} points to level ${score.level + 1}',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveScoreboardStrip extends StatelessWidget {
  final PuffHumScoreSet score;

  const _ActiveScoreboardStrip({required this.score});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.chart_bar_alt_fill,
            color: colors.accent,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              score.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _compactNumber(score.points),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeTrophyCase extends StatelessWidget {
  final AppStats stats;
  final PuffHumScoreSet score;

  const _BadgeTrophyCase({required this.stats, required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _BadgeChip(
            icon: CupertinoIcons.rosette,
            value: 'L${score.level}',
            color: _dashboardColor(3),
          ),
          const SizedBox(width: 8),
          _BadgeChip(
            icon: CupertinoIcons.flame,
            value: '${stats.currentStreakDays}d',
            color: _dashboardColor(2),
          ),
          const SizedBox(width: 8),
          _BadgeChip(
            icon: CupertinoIcons.wind,
            value: _compactNumber(score.puffs),
            color: _dashboardColor(0),
          ),
          const SizedBox(width: 8),
          _BadgeChip(
            icon: CupertinoIcons.text_bubble,
            value: _compactNumber(score.hums),
            color: _dashboardColor(1),
          ),
          const SizedBox(width: 8),
          _BadgeChip(
            icon: CupertinoIcons.bolt,
            value: _compactNumber(score.points),
            color: _dashboardColor(4),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _BadgeChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreboardCard extends ConsumerWidget {
  final AppStats stats;

  const _ScoreboardCard({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final topScores = stats.topScoreSets.take(5).toList();
    final activeScore = stats.activeScoreSet;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.chart_bar_alt_fill, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'Scoreboard',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              CupertinoButton(
                onPressed: () => _showScoreboardDialog(context, ref),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                child: Text(
                  'Manage',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < topScores.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            _LeaderboardRow(
              score: topScores[i],
              rank: i + 1,
              active: topScores[i].id == activeScore.id,
              bandIndex: i,
            ),
          ],
          if (topScores.isEmpty)
            _LeaderboardRow(
              score: activeScore,
              rank: 1,
              active: true,
              bandIndex: 0,
            ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final PuffHumScoreSet score;
  final int rank;
  final bool active;
  final int bandIndex;

  const _LeaderboardRow({
    required this.score,
    required this.rank,
    required this.active,
    required this.bandIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final bandColor = bandIndex.isEven
        ? colors.accent.withValues(alpha: colors.isDark ? 0.13 : 0.09)
        : colors.cardAlt.withValues(alpha: colors.isDark ? 0.48 : 0.58);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: bandColor,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _scoreboardDisplayName(score.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            Text(
              'active',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            _compactNumber(score.points),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showScoreboardDialog(BuildContext context, WidgetRef ref) {
  final nameController = TextEditingController();
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Consumer(
        builder: (context, ref, _) {
          final stats = ref.watch(appStatsProvider);
          final colors = Theme.of(context).extension<ByepasserColors>()!;
          final scores = stats.topScoreSets;
          return CupertinoAlertDialog(
            title: const Text('Top Score History'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  CupertinoTextField(
                    controller: nameController,
                    placeholder: defaultScoreSetName,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.cardAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.divider),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: nameController,
                      builder: (context, value, _) {
                        final canCreate = value.text.trim().isNotEmpty;
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          color: colors.accent,
                          disabledColor: colors.cardAlt,
                          borderRadius: BorderRadius.circular(14),
                          onPressed: canCreate
                              ? () async {
                                  await GamificationService.createScoreSet(
                                    ref,
                                    name: nameController.text.trim(),
                                  );
                                  nameController.clear();
                                }
                              : null,
                          child: Text(
                            'New Scoreboard',
                            style: TextStyle(
                              color: canCreate
                                  ? colors.textOnAccent
                                  : colors.textSecondary.withValues(
                                      alpha: 0.55,
                                    ),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 290,
                    child: scores.isEmpty
                        ? Center(
                            child: Text(
                              'No scores yet.',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: scores.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final score = scores[index];
                              return Dismissible(
                                key: ValueKey(score.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 14),
                                  decoration: BoxDecoration(
                                    color: colors.danger,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.trash,
                                    color: colors.textOnAccent,
                                    size: 20,
                                  ),
                                ),
                                confirmDismiss: (_) async {
                                  final confirmed =
                                      await _confirmDeleteScoreSet(
                                        context,
                                        score.name,
                                      );
                                  if (!confirmed) return false;
                                  await GamificationService.deleteScoreSet(
                                    ref,
                                    score.id,
                                  );
                                  return false;
                                },
                                child: _ScoreSetTile(
                                  score: score,
                                  rank: index + 1,
                                  selected: score.id == stats.activeScoreSet.id,
                                  onTap: () =>
                                      GamificationService.setActiveScoreSet(
                                        ref,
                                        score.id,
                                      ),
                                  onLongPress: () => _showRenameScoreSetDialog(
                                    context,
                                    ref,
                                    score,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Done'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(nameController.dispose);
}

Future<bool> _confirmDeleteScoreSet(BuildContext context, String name) async {
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('Delete scoreboard?'),
      content: Text(
        'Delete "$name" from top score history? This cannot be undone.',
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<void> _showRenameScoreSetDialog(
  BuildContext context,
  WidgetRef ref,
  PuffHumScoreSet score,
) {
  final controller = TextEditingController(text: score.name);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(context).extension<ByepasserColors>()!;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final name = controller.text.trim();
          final canRename = name.isNotEmpty && name != score.name.trim();
          return CupertinoAlertDialog(
            title: const Text('Rename scoreboard'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: controller,
                autofocus: true,
                placeholder: defaultScoreSetName,
                onChanged: (_) => setDialogState(() {}),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.divider),
                ),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              CupertinoDialogAction(
                onPressed: canRename
                    ? () async {
                        await GamificationService.renameScoreSet(
                          ref,
                          score.id,
                          name: name,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      }
                    : null,
                child: const Text('Rename'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

class _ScoreSetTile extends StatelessWidget {
  final PuffHumScoreSet score;
  final int rank;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ScoreSetTile({
    required this.score,
    required this.rank,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return GestureDetector(
      onLongPress: onLongPress,
      child: CupertinoButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.14)
                : colors.cardAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colors.accent.withValues(alpha: 0.5)
                  : colors.divider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : colors.background,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colors.textOnAccent
                        : colors.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  score.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _compactNumber(score.points),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected ? colors.accent : colors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    selected ? 'active' : 'points',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseBalanceCard extends StatelessWidget {
  final AppStats stats;
  final int activePuffs;
  final int activeHums;

  const _ReleaseBalanceCard({
    required this.stats,
    required this.activePuffs,
    required this.activeHums,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.chart_bar_alt_fill, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'Active',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReleaseMetric(
                  icon: CupertinoIcons.wind,
                  label: 'Active puffs',
                  value: activePuffs,
                ),
              ),
              Container(width: 1, height: 56, color: colors.divider),
              Expanded(
                child: _ReleaseMetric(
                  icon: CupertinoIcons.text_bubble,
                  label: 'Active hums',
                  value: activeHums,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SplitChart(puffs: activePuffs, hums: activeHums),
        ],
      ),
    );
  }
}

class _LifetimeReleaseCard extends StatelessWidget {
  final AppStats stats;

  const _LifetimeReleaseCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final score = stats.activeScoreSet;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.infinite, color: colors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Lifetime',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReleaseMetric(
                  icon: CupertinoIcons.wind,
                  label: 'Puffs',
                  value: score.puffs,
                ),
              ),
              Container(width: 1, height: 56, color: colors.divider),
              Expanded(
                child: _ReleaseMetric(
                  icon: CupertinoIcons.text_bubble,
                  label: 'Hums',
                  value: score.hums,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SplitChart(puffs: score.puffs, hums: score.hums),
        ],
      ),
    );
  }
}

class _SplitChart extends StatelessWidget {
  final int puffs;
  final int hums;

  const _SplitChart({required this.puffs, required this.hums});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final total = puffs + hums;
    final puffPercent = total == 0 ? 0 : (puffs / total * 100).round();
    final humPercent = total == 0 ? 0 : 100 - puffPercent;
    final puffRatio = total == 0 ? 0.0 : puffs / total;
    final puffColor = colors.accent;
    final humColor = _themeComplementaryColor(colors.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final puffWidth = total == 0 ? 0.0 : barWidth * puffRatio;
            final humWidth = total == 0 ? 0.0 : barWidth - puffWidth;
            final showSplit = puffs > 0 && hums > 0;
            final splitLeft = barWidth <= 2
                ? 0.0
                : (puffWidth - 1).clamp(0.0, barWidth - 2).toDouble();
            return Container(
              height: 54,
              decoration: BoxDecoration(
                color: colors.cardAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.75),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: total == 0
                  ? ColoredBox(color: colors.cardAlt)
                  : Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: puffWidth,
                          child: ColoredBox(color: puffColor),
                        ),
                        Positioned(
                          left: puffWidth,
                          top: 0,
                          bottom: 0,
                          width: humWidth,
                          child: ColoredBox(color: humColor),
                        ),
                        if (showSplit)
                          Positioned(
                            left: splitLeft,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 2,
                              color: colors.background.withValues(alpha: 0.62),
                            ),
                          ),
                      ],
                    ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SplitLegend(
                color: puffColor,
                label: 'Puff',
                percent: puffPercent,
              ),
            ),
            Expanded(
              child: _SplitLegend(
                color: humColor,
                label: 'Hum',
                percent: humPercent,
                alignEnd: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitLegend extends StatelessWidget {
  final Color color;
  final String label;
  final int percent;
  final bool alignEnd;

  const _SplitLegend({
    required this.color,
    required this.label,
    required this.percent,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $percent%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ReleaseMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _ReleaseMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: colors.accent, size: 20),
          const SizedBox(height: 8),
          Text(
            _compactNumber(value),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String insight;
  final int dyingSoonCount;
  final int recycledCount;

  const _InsightCard({
    required this.insight,
    required this.dyingSoonCount,
    required this.recycledCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.sparkles, color: colors.accent, size: 19),
              const SizedBox(width: 8),
              Text(
                'Read',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
              height: 1.28,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _InlineSignal(
                  icon: CupertinoIcons.hourglass,
                  label: 'Soon',
                  value: dyingSoonCount,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InlineSignal(
                  icon: CupertinoIcons.arrow_counterclockwise,
                  label: 'Recycle',
                  value: recycledCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineSignal extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _InlineSignal({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Row(
      children: [
        Icon(icon, color: colors.textSecondary, size: 16),
        const SizedBox(width: 6),
        Text(
          '$label $value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final AppStats stats;
  final int activePuffs;
  final int activeHums;

  const _StatsGrid({
    required this.stats,
    required this.activePuffs,
    required this.activeHums,
  });

  @override
  Widget build(BuildContext context) {
    final score = stats.activeScoreSet;
    final tiles = [
      _StatItem(
        icon: CupertinoIcons.flame,
        label: 'Streak',
        value: '${stats.currentStreakDays}d',
        color: _dashboardColor(2),
      ),
      _StatItem(
        icon: CupertinoIcons.rosette,
        label: 'Best',
        value: '${stats.longestStreakDays}d',
        color: _dashboardColor(3),
      ),
      _StatItem(
        icon: CupertinoIcons.photo,
        label: 'Images',
        value: _compactNumber(stats.attachmentsAdded),
        color: _dashboardColor(5),
      ),
      _StatItem(
        icon: CupertinoIcons.sparkles,
        label: 'Releases',
        value: _compactNumber(score.releases),
        color: _dashboardColor(4),
      ),
      _StatItem(
        icon: CupertinoIcons.wind,
        label: 'Active puffs',
        value: _compactNumber(activePuffs),
        color: _dashboardColor(0),
      ),
      _StatItem(
        icon: CupertinoIcons.text_bubble,
        label: 'Active hums',
        value: _compactNumber(activeHums),
        color: _dashboardColor(1),
      ),
      _StatItem(
        icon: CupertinoIcons.time,
        label: 'Extended',
        value: _compactNumber(stats.notesExtended),
        color: _dashboardColor(7),
      ),
      _StatItem(
        icon: CupertinoIcons.square_stack_3d_up,
        label: 'Moved',
        value: _compactNumber(stats.notesMoved),
        color: _dashboardColor(6),
      ),
      _StatItem(
        icon: CupertinoIcons.arrow_counterclockwise,
        label: 'Recycled',
        value: _compactNumber(stats.notesRecycled),
        color: _dashboardColor(2),
      ),
      _StatItem(
        icon: CupertinoIcons.check_mark_circled,
        label: 'Expired',
        value: _compactNumber(stats.notesExpired),
        color: _dashboardColor(1),
      ),
      _StatItem(
        icon: CupertinoIcons.arrow_uturn_left,
        label: 'Restored',
        value: _compactNumber(stats.notesRestored),
        color: _dashboardColor(3),
      ),
      _StatItem(
        icon: CupertinoIcons.trash,
        label: 'Cleared',
        value: _compactNumber(stats.notesDiscarded),
        color: _dashboardColor(0),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        const gap = 10.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: _StatTile(item: tile),
              ),
          ],
        );
      },
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _StatTile extends StatelessWidget {
  final _StatItem item;

  const _StatTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      height: 88,
      padding: const EdgeInsets.all(12),
      decoration: colors.cardDecoration(
        color: Color.alphaBlend(
          item.color.withValues(alpha: colors.isDark ? 0.16 : 0.08),
          colors.card,
        ),
        radius: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(item.icon, color: item.color, size: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: item.color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointRulesCard extends StatelessWidget {
  const _PointRulesCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final rows = const [
      _PointRule(CupertinoIcons.wind, 'Puff', GamificationPoints.puffReleased),
      _PointRule(
        CupertinoIcons.text_bubble,
        'Hum',
        GamificationPoints.humReleased,
      ),
      _PointRule(
        CupertinoIcons.photo,
        'Image',
        GamificationPoints.attachmentAdded,
      ),
      _PointRule(
        CupertinoIcons.time,
        'Extend',
        GamificationPoints.noteExtended,
      ),
      _PointRule(
        CupertinoIcons.square_stack_3d_up,
        'Move',
        GamificationPoints.noteMoved,
      ),
      _PointRule(
        CupertinoIcons.arrow_counterclockwise,
        'Recycle',
        GamificationPoints.noteRecycled,
      ),
      _PointRule(
        CupertinoIcons.arrow_uturn_left,
        'Restore',
        GamificationPoints.noteRestored,
      ),
      _PointRule(
        CupertinoIcons.check_mark_circled,
        'Expire',
        GamificationPoints.noteExpired,
      ),
      _PointRule(
        CupertinoIcons.trash,
        'Clear',
        GamificationPoints.noteDiscarded,
      ),
      _PointRule(
        CupertinoIcons.settings,
        'Vibe',
        GamificationPoints.settingsChanged,
      ),
      _PointRule(
        CupertinoIcons.arrow_turn_up_right,
        'Navigate',
        GamificationPoints.navigation,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: colors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.bolt, color: colors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Points',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final row in rows)
                _PointChip(
                  icon: row.icon,
                  label: row.label,
                  points: row.points,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointRule {
  final IconData icon;
  final String label;
  final int points;

  const _PointRule(this.icon, this.label, this.points);
}

class _PointChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int points;

  const _PointChip({
    required this.icon,
    required this.label,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.accent, size: 15),
          const SizedBox(width: 6),
          Text(
            '$label +$points',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _dashboardInsight(
  AppStats stats, {
  required int activePuffs,
  required int activeHums,
  required int dyingSoonCount,
  required int recycledCount,
}) {
  final score = stats.activeScoreSet;
  if (score.releases == 0) {
    return 'No pattern yet. The first release sets the tone.';
  }
  if (dyingSoonCount > 0) {
    return '$dyingSoonCount note${dyingSoonCount == 1 ? '' : 's'} close to leaving. Nice moment to skim, save, or let the timer do its work.';
  }
  if (stats.currentStreakDays >= 3) {
    return '${stats.currentStreakDays} days in a row. That is a real little ritual now.';
  }
  if (score.puffs > score.hums * 2) {
    return 'Puffs are leading. Short thoughts, clean exits, low drag.';
  }
  if (score.hums > score.puffs * 2) {
    return 'Hums are carrying the weight. Longer captures seem to be your current lane.';
  }
  if (recycledCount > 0) {
    return 'A few notes are waiting in recycle. The board is clean, but nothing has to be final yet.';
  }
  if (activePuffs + activeHums == 0) {
    return 'All clear right now. Quiet boards count too.';
  }
  return 'Balanced rhythm: quick Puffs for release, Hums for thoughts that need a little room.';
}

String _levelName(int level) {
  if (level >= 20) return 'Clear-Minded Master';
  if (level >= 14) return 'Ritual Keeper';
  if (level >= 9) return 'Pattern Finder';
  if (level >= 5) return 'Lightener';
  if (level >= 2) return 'Release Scout';
  return 'First Release';
}

String _scoreboardDisplayName(String name) {
  final trimmed = name.trim();
  final withoutSuffix = trimmed.replaceFirst(
    RegExp(r'\s+Scoreboard$', caseSensitive: false),
    '',
  );
  return withoutSuffix.isEmpty ? defaultScoreSetName : withoutSuffix;
}

Color _dashboardColor(int index) {
  return ByepasserTheme.accentPalette[index %
      ByepasserTheme.accentPalette.length];
}

Color _themeComplementaryColor(Color base) {
  final baseHue = HSLColor.fromColor(base).hue;
  final targetHue = (baseHue + 180) % 360;
  var bestColor = ByepasserTheme.accentPalette.first;
  var bestDistance = double.infinity;

  for (final candidate in ByepasserTheme.accentPalette) {
    final candidateHue = HSLColor.fromColor(candidate).hue;
    if (_hueDistance(candidateHue, baseHue) < 1) continue;
    final distance = _hueDistance(candidateHue, targetHue);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestColor = candidate;
    }
  }
  return bestColor;
}

double _hueDistance(double a, double b) {
  final diff = (a - b).abs() % 360;
  return diff > 180 ? 360 - diff : diff;
}

String _compactNumber(int value) {
  if (value >= 1000000) {
    final compact = value / 1000000;
    return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}m';
  }
  if (value >= 1000) {
    final compact = value / 1000;
    return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}k';
  }
  return value.toString();
}

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
