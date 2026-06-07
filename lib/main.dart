import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'models/app_settings.dart';
import 'models/note.dart';
import 'providers/app_providers.dart';
import 'screens/app_shell.dart';
import 'services/hive_store.dart';
import 'services/notification_service.dart';
import 'theme/byepasser_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open Hive and register everything
  final store = await HiveStore.open();

  // Create notification service (requests iOS permissions)
  final notificationService = await NotificationService.create();

  // Perform initial expiry sweep on every cold launch
  await store.sweepExpiredNotes();

  runApp(
    ProviderScope(
      overrides: [
        // Provide the real boxes so providers/screens can use them if needed
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

    // When user chooses "Follow System", we let the platform decide.
    // Otherwise we force the chosen palette (even the dark ones) as a single ThemeData.
    final followSystem = settings.themeKey == ThemeKeys.followSystem;

    final lightish = ByepasserTheme.dataFor(
      settings.copyWith(themeKey: ThemeKeys.whiteCanvas),
    );

    final darkish = ByepasserTheme.dataFor(
      settings.copyWith(themeKey: ThemeKeys.deepDusk),
    );

    return MaterialApp(
      title: 'Byepasser',
      debugShowCheckedModeBanner: false,
      theme: followSystem
          ? lightish
          : ByepasserTheme.dataFor(settings),
      darkTheme: followSystem ? darkish : null,
      themeMode: followSystem ? ThemeMode.system : ThemeMode.light,
      home: const ExpiryWatcher(child: AppShell()),
      builder: (context, child) {
        // Ensure we always have our custom colors extension available
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

/// Watches for expiry on launch and on a slow periodic timer.
/// Also triggers auto-copy-to-clipboard behavior when notes are very close to death.
class ExpiryWatcher extends ConsumerStatefulWidget {
  final Widget child;

  const ExpiryWatcher({super.key, required this.child});

  @override
  ConsumerState<ExpiryWatcher> createState() => _ExpiryWatcherState();
}

class _ExpiryWatcherState extends ConsumerState<ExpiryWatcher> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _runSweepAndAutoCopy();
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => _runSweepAndAutoCopy());
  }

  Future<void> _runSweepAndAutoCopy() async {
    if (!mounted) return;

    final store = await _getStore();
    await store.sweepExpiredNotes();

    final settings = store.settings;
    final notes = store.getAllNotesSorted();

    // Auto-copy bodies of notes that will die in < 5 minutes (if enabled)
    if (settings.autoCopyBeforeDeletion) {
      final now = DateTime.now();
      for (final note in notes) {
        final secs = note.expiresAt.difference(now).inSeconds;
        if (secs > 0 && secs < 5 * 60) {
          // Copy once per such note by using a simple heuristic (we copy on every sweep while it's in window).
          // In a more advanced version we would track "already copied" per launch.
          await Clipboard.setData(ClipboardData(text: note.body));
          // Only do one per sweep to avoid spamming clipboard
          break;
        }
      }
    }

    // Refresh riverpod state so UI reflects deletions
    if (mounted) {
      // notesProvider reads live from the box; no manual state push needed
    }

    // Re-schedule notifications for whatever remains
    try {
      final notif = ref.read(notificationServiceProvider);
      if (settings.gentleNotifications) {
        for (final n in notes) {
          await notif.scheduleExpiryReminders(n, settings);
        }
      }
    } catch (_) {}
  }

  Future<_MainStoreFacade> _getStore() async {
    return _MainStoreFacade();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Lightweight helper used by the watcher (talks directly to globally open Hive boxes).
class _MainStoreFacade {
  Box<Note> get notesBox => Hive.box<Note>('notes');
  Box<AppSettings> get settingsBox => Hive.box<AppSettings>('settings');

  AppSettings get settings => settingsBox.get('user') ?? AppSettings.defaults();

  Future<int> sweepExpiredNotes() async {
    final now = DateTime.now();
    final doomed = notesBox.values.where((n) => now.isAfter(n.expiresAt)).toList();
    for (final n in doomed) {
      await notesBox.delete(n.id);
    }
    return doomed.length;
  }

  List<Note> getAllNotesSorted() {
    final l = notesBox.values.toList();
    l.sort((a, b) => a.compareExpiry(b));
    return l;
  }
}
