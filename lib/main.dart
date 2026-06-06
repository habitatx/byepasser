import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'models/app_settings.dart';
import 'providers/app_providers.dart';
import 'screens/app_shell.dart';
import 'services/hive_store.dart';
import 'services/notification_service.dart';
import 'theme/byepasser_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await HiveStore.open();
  final notificationService = await NotificationService.create();

  runApp(
    ProviderScope(
      overrides: [
        notesBoxProvider.overrideWithValue(store.notesBox),
        settingsBoxProvider.overrideWithValue(store.settingsBox),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const ByepasserApp(),
    ),
  );
}

class ByepasserApp extends ConsumerWidget {
  const ByepasserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final followSystem = settings.themeKey == ThemeKeys.followSystem;

    return MaterialApp(
      title: 'Byepasser',
      debugShowCheckedModeBanner: false,
      theme: followSystem
          ? ByepasserTheme.dataFor(
              settings.copyWith(themeKey: ThemeKeys.whiteCanvas),
            )
          : ByepasserTheme.dataFor(settings),
      darkTheme: followSystem
          ? ByepasserTheme.dataFor(
              settings.copyWith(themeKey: ThemeKeys.deepDusk),
            )
          : null,
      themeMode: followSystem ? ThemeMode.system : ThemeMode.light,
      home: const ExpiryWatcher(child: AppShell()),
    );
  }
}

class ExpiryWatcher extends HookConsumerWidget {
  const ExpiryWatcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      final controller = ref.read(notesProvider.notifier);
      controller.sweepExpiredAndAutoCopy();
      final timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => controller.sweepExpiredAndAutoCopy(),
      );
      return timer.cancel;
    }, const []);

    return child;
  }
}
