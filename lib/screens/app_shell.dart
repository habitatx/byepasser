import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'steam_release_screen.dart';

/// Root navigation shell using Cupertino for true iOS feel.
/// Tabs: Board + Puff + Hum + Recycle + Settings
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;
  late final CupertinoTabController _tabController;
  bool _composerOpen = false;
  ValueNotifier<bool>? _composerIsHum;
  VoidCallback? _composerModeListener;

  final List<Widget> _tabs = const [
    HomeScreen(),
    HomeScreen(),
    HomeScreen(),
    HomeScreen(recycleBin: true),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = CupertinoTabController(initialIndex: _currentIndex);
  }

  void _setActiveTab(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
    if (_tabController.index != index) {
      _tabController.index = index;
    }
  }

  void _onTabTapped(int index) {
    if (index == 1 || index == 2) {
      _setActiveTab(index);
      if (_composerOpen) {
        _composerIsHum?.value = index == 2;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _composerOpen) return;
        _composerOpen = true;
        _composerIsHum = ValueNotifier<bool>(index == 2);
        _composerModeListener = () {
          final isHum = _composerIsHum?.value;
          if (!mounted || isHum == null) return;
          final nextIndex = isHum ? 2 : 1;
          _setActiveTab(nextIndex);
        };
        _composerIsHum!.addListener(_composerModeListener!);
        showQuickNoteComposerDialog(
          context,
          isHumListenable: _composerIsHum!,
          onTabSelected: (selectedIndex) {
            if (!mounted) return;
            _setActiveTab(selectedIndex);
          },
        ).whenComplete(() {
          if (!mounted) return;
          if (_composerModeListener != null) {
            _composerIsHum?.removeListener(_composerModeListener!);
          }
          _composerModeListener = null;
          _composerIsHum?.dispose();
          _composerIsHum = null;
          _composerOpen = false;
        });
      });
      return;
    }
    _setActiveTab(index);
  }

  @override
  void dispose() {
    if (_composerModeListener != null) {
      _composerIsHum?.removeListener(_composerModeListener!);
    }
    _composerIsHum?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noteCount = ref.watch(noteCountProvider);
    final recycledNoteCount = ref.watch(recycledNoteCountProvider);
    final settings = ref.watch(settingsProvider);
    final showCount = settings.showNoteCountInTabBar;

    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        border: null,
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        activeColor: Theme.of(context).extension<ByepasserColors>()!.accent,
        inactiveColor: Theme.of(
          context,
        ).extension<ByepasserColors>()!.textSecondary,
        backgroundColor: Theme.of(
          context,
        ).extension<ByepasserColors>()!.background.withValues(alpha: 0.92),
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
            icon: Icon(CupertinoIcons.text_bubble),
            label: 'Hum',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.recycling),
            label: showCount && recycledNoteCount > 0
                ? 'Recycle ($recycledNoteCount)'
                : 'Recycle',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(builder: (context) => _tabs[index]);
      },
    );
  }
}
