import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_stats.dart';
import '../providers/app_providers.dart';

class GamificationPoints {
  static const int puffReleased = 18;
  static const int humReleased = 14;
  static const int attachmentAdded = 4;
  static const int noteExtended = 9;
  static const int noteMoved = 5;
  static const int noteRecycled = 3;
  static const int noteRestored = 4;
  static const int noteDiscarded = 2;
  static const int noteExpired = 6;
  static const int settingsChanged = 2;
  static const int navigation = 1;
}

class GamificationService {
  const GamificationService._();

  static Future<void> recordRelease(
    WidgetRef ref, {
    required bool isHum,
    int attachmentCount = 0,
  }) {
    return _award(
      ref,
      points:
          (isHum
              ? GamificationPoints.humReleased
              : GamificationPoints.puffReleased) +
          attachmentCount * GamificationPoints.attachmentAdded,
      puffs: isHum ? 0 : 1,
      hums: isHum ? 1 : 0,
      attachments: attachmentCount,
    );
  }

  static Future<void> recordAttachment(WidgetRef ref, {int count = 1}) {
    if (count <= 0) return Future<void>.value();
    return _award(
      ref,
      points: count * GamificationPoints.attachmentAdded,
      attachments: count,
    );
  }

  static Future<void> recordExtension(WidgetRef ref) {
    return _award(ref, points: GamificationPoints.noteExtended, extended: 1);
  }

  static Future<void> recordMove(WidgetRef ref) {
    return _award(ref, points: GamificationPoints.noteMoved, moved: 1);
  }

  static Future<void> recordRecycle(WidgetRef ref, {int count = 1}) {
    if (count <= 0) return Future<void>.value();
    return _award(
      ref,
      points: count * GamificationPoints.noteRecycled,
      recycled: count,
    );
  }

  static Future<void> recordRestore(WidgetRef ref) {
    return _award(ref, points: GamificationPoints.noteRestored, restored: 1);
  }

  static Future<void> recordDiscard(WidgetRef ref, {int count = 1}) {
    if (count <= 0) return Future<void>.value();
    return _award(
      ref,
      points: count * GamificationPoints.noteDiscarded,
      discarded: count,
    );
  }

  static Future<void> recordExpired(WidgetRef ref, {required int count}) {
    if (count <= 0) return Future<void>.value();
    return _award(
      ref,
      points: count * GamificationPoints.noteExpired,
      expired: count,
    );
  }

  static Future<void> recordSettingsChange(WidgetRef ref) {
    return _award(ref, points: GamificationPoints.settingsChanged);
  }

  static Future<void> recordNavigation(WidgetRef ref) {
    return _award(ref, points: GamificationPoints.navigation);
  }

  static Future<void> setActiveScoreSet(WidgetRef ref, String id) {
    return _updateStats(ref, (stats) => stats.setActiveScoreSet(id));
  }

  static Future<void> createScoreSet(WidgetRef ref, {required String name}) {
    return _updateStats(ref, (stats) => stats.createScoreSet(name: name));
  }

  static Future<void> renameScoreSet(
    WidgetRef ref,
    String id, {
    required String name,
  }) {
    return _updateStats(ref, (stats) => stats.renameScoreSet(id, name: name));
  }

  static Future<void> deleteScoreSet(WidgetRef ref, String id) {
    return _updateStats(ref, (stats) => stats.deleteScoreSet(id));
  }

  static Future<void> _award(
    WidgetRef ref, {
    int points = 0,
    int puffs = 0,
    int hums = 0,
    int attachments = 0,
    int extended = 0,
    int moved = 0,
    int recycled = 0,
    int restored = 0,
    int discarded = 0,
    int expired = 0,
  }) async {
    return _updateStats(
      ref,
      (stats) => stats.award(
        points: points,
        puffs: puffs,
        hums: hums,
        attachments: attachments,
        extended: extended,
        moved: moved,
        recycled: recycled,
        restored: restored,
        discarded: discarded,
        expired: expired,
      ),
    );
  }

  static Future<void> _updateStats(
    WidgetRef ref,
    AppStats Function(AppStats stats) update,
  ) async {
    final box = ref.read(statsBoxProvider);
    final current = box.get(appStatsKey) ?? AppStats.defaults();
    await box.put(appStatsKey, update(current));
    ref.invalidate(appStatsProvider);
  }
}
