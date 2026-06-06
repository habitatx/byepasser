import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final count = ref.watch(notesProvider).length;

    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: palette.card.withValues(alpha: 0.92),
        activeColor: palette.accent,
        inactiveColor: palette.mutedText,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.square_grid_2x2),
            label: settings.showNoteCountInTabBar ? 'Board ($count)' : 'Board',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            return index == 0 ? const HomeScreen() : const SettingsScreen();
          },
        );
      },
    );
  }
}
