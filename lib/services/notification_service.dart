import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';
import '../models/app_settings.dart';

/// Handles all local iOS notifications for note expiry warnings.
/// No network, fully on-device.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService._(this._plugin);

  static Future<NotificationService> create() async {
    tz.initializeTimeZones();

    final plugin = FlutterLocalNotificationsPlugin();

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(iOS: iosSettings);

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions explicitly on iOS (required for iOS 15+ in many cases)
    await plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return NotificationService._(plugin);
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // In a more advanced app we could navigate to the specific note using payload.
    // For Byepasser we keep it simple: tapping just opens the app.
  }

  /// Schedule gentle notifications (24h + 1h before) if the setting is enabled.
  /// Idempotent per note id (we cancel previous schedules for the note first).
  Future<void> scheduleExpiryReminders(Note note, AppSettings settings) async {
    if (!settings.gentleNotifications) return;

    final now = DateTime.now();
    if (note.expiresAt.isBefore(now)) return;

    // Cancel any previous for this note
    await cancelForNote(note.id);

    final noteIdHash = note.id.hashCode & 0x7fffffff; // positive 31-bit int

    // 24 hours before
    final reminder24h = note.expiresAt.subtract(const Duration(hours: 24));
    if (reminder24h.isAfter(now)) {
      await _plugin.zonedSchedule(
        noteIdHash,
        'Note expiring soon',
        note.displayTitle,
        tz.TZDateTime.from(reminder24h, tz.local),
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
          ),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: note.id,
      );
    }

    // 1 hour before
    final reminder1h = note.expiresAt.subtract(const Duration(hours: 1));
    if (reminder1h.isAfter(now)) {
      await _plugin.zonedSchedule(
        noteIdHash + 1,
        'Note expiring in one hour',
        note.displayTitle,
        tz.TZDateTime.from(reminder1h, tz.local),
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
          ),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: note.id,
      );
    }
  }

  Future<void> cancelForNote(String noteId) async {
    final hash = noteId.hashCode & 0x7fffffff;
    await _plugin.cancel(hash);
    await _plugin.cancel(hash + 1);
  }

  /// Optional: auto-copy nudge 5 minutes before (we don't actually copy from notification,
  /// the app does the copy when it detects on next launch/sweep if the setting is on).
  /// We can schedule a silent heads-up if desired.
  Future<void> scheduleAutoCopyNudge(Note note) async {
    // Implementation left lightweight — the actual clipboard copy is performed
    // inside the sweep logic in the app when remaining < 5 min on launch.
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
