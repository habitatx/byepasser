import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';

class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static Future<NotificationService> create() async {
    final plugin = FlutterLocalNotificationsPlugin();
    timezone_data.initializeTimeZones();

    const initializationSettings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await plugin.initialize(initializationSettings);

    return NotificationService(plugin);
  }

  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }

  Future<void> scheduleExpiryReminders(
    Note note, {
    required bool enabled,
  }) async {
    await cancelForNote(note.id);
    if (!enabled) {
      return;
    }

    await requestPermissions();
    await _scheduleOne(
      note,
      offset: const Duration(hours: 24),
      slot: 24,
      body: '"${note.displayTitle}" says bye in about 24 hours.',
    );
    await _scheduleOne(
      note,
      offset: const Duration(hours: 1),
      slot: 1,
      body: '"${note.displayTitle}" says bye in about 1 hour.',
    );
  }

  Future<void> cancelForNote(String noteId) async {
    await _plugin.cancel(_notificationId(noteId, 24));
    await _plugin.cancel(_notificationId(noteId, 1));
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> _scheduleOne(
    Note note, {
    required Duration offset,
    required int slot,
    required String body,
  }) async {
    final fireAt = note.expiresAt.subtract(offset);
    if (!fireAt.isAfter(DateTime.now())) {
      return;
    }

    await _plugin.zonedSchedule(
      _notificationId(note.id, slot),
      'Byepasser',
      body,
      tz.TZDateTime.from(fireAt, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
          interruptionLevel: InterruptionLevel.passive,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: note.id,
    );
  }

  int _notificationId(String noteId, int slot) {
    var hash = slot * 1000003;
    for (final unit in noteId.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    return hash & 0x7fffffff;
  }
}
