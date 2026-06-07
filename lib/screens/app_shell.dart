import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'steam_release_screen.dart';

/// Root navigation shell using Cupertino for true iOS feel.
/// Tabs: Board (Home) + Puff (short notes) + Settings
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    HomeScreen(),
    SteamReleaseScreen(embedded: true), // shown inside tab
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final noteCount = ref.watch(noteCountProvider);
    final settings = ref.watch(settingsProvider);
    final showCount = settings.showNoteCountInTabBar;

    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        activeColor: Theme.of(context).extension<ByepasserColors>()!.accent,
        inactiveColor: Theme.of(context).extension<ByepasserColors>()!.textSecondary,
        backgroundColor: Theme.of(context).extension<ByepasserColors>()!.background.withValues(alpha: 0.92),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.square_stack_3d_up),
            label: showCount && noteCount > 0 ? 'Board ($noteCount)' : 'Board',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.wind),
            label: 'Puff',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) => _tabs[index],
        );
      },
    );
  }
}
