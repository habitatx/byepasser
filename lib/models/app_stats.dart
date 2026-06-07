import 'dart:math' as math;

import 'package:hive/hive.dart';

const int appStatsTypeId = 3;
const String appStatsKey = 'user';
const String defaultScoreSetId = 'default';
const String defaultScoreSetName = 'Puff & Hum';

class PuffHumScoreSet {
  final String id;
  final String name;
  final int points;
  final int puffs;
  final int hums;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PuffHumScoreSet({
    required this.id,
    required this.name,
    required this.points,
    required this.puffs,
    required this.hums,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PuffHumScoreSet.defaults({DateTime? at}) {
    final now = at ?? DateTime.now();
    return PuffHumScoreSet(
      id: _scoreSetId(now),
      name: defaultScoreSetName,
      points: 0,
      puffs: 0,
      hums: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory PuffHumScoreSet.seed({
    required int points,
    required int puffs,
    required int hums,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    return PuffHumScoreSet(
      id: defaultScoreSetId,
      name: defaultScoreSetName,
      points: math.max(0, points),
      puffs: math.max(0, puffs),
      hums: math.max(0, hums),
      createdAt: now,
      updatedAt: now,
    );
  }

  int get releases => puffs + hums;

  int get level => (points ~/ 100) + 1;

  int get pointsIntoLevel => points % 100;

  PuffHumScoreSet copyWith({
    String? id,
    String? name,
    int? points,
    int? puffs,
    int? hums,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PuffHumScoreSet(
      id: id ?? this.id,
      name: name ?? this.name,
      points: points ?? this.points,
      puffs: puffs ?? this.puffs,
      hums: hums ?? this.hums,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  PuffHumScoreSet award({
    int points = 0,
    int puffs = 0,
    int hums = 0,
    DateTime? at,
  }) {
    return copyWith(
      points: math.max(0, this.points + points),
      puffs: this.puffs + puffs,
      hums: this.hums + hums,
      updatedAt: at ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'points': points,
      'puffs': puffs,
      'hums': hums,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  static PuffHumScoreSet? fromDynamic(dynamic value) {
    if (value is! Map) return null;
    final id = value['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final now = DateTime.now();
    final name = (value['name'] as String?)?.trim();
    return PuffHumScoreSet(
      id: id,
      name: name == null || name.isEmpty ? defaultScoreSetName : name,
      points: math.max(0, (value['points'] as int?) ?? 0),
      puffs: math.max(0, (value['puffs'] as int?) ?? 0),
      hums: math.max(0, (value['hums'] as int?) ?? 0),
      createdAt: (value['createdAt'] as DateTime?) ?? now,
      updatedAt: (value['updatedAt'] as DateTime?) ?? now,
    );
  }
}

@HiveType(typeId: appStatsTypeId)
class AppStats extends HiveObject {
  @HiveField(0)
  final int lifetimePuffs;

  @HiveField(1)
  final int lifetimeHums;

  @HiveField(2)
  final int totalPoints;

  @HiveField(3)
  final int attachmentsAdded;

  @HiveField(4)
  final int notesExtended;

  @HiveField(5)
  final int notesMoved;

  @HiveField(6)
  final int notesRecycled;

  @HiveField(7)
  final int notesRestored;

  @HiveField(8)
  final int notesDiscarded;

  @HiveField(9)
  final int notesExpired;

  @HiveField(10)
  final DateTime firstTrackedAt;

  @HiveField(11)
  final DateTime? lastActivityAt;

  @HiveField(12)
  final List<String> releaseDays;

  @HiveField(13)
  final int longestStreakDays;

  @HiveField(14)
  final String activeScoreSetId;

  @HiveField(15)
  final List<PuffHumScoreSet> scoreSets;

  AppStats({
    required this.lifetimePuffs,
    required this.lifetimeHums,
    required this.totalPoints,
    required this.attachmentsAdded,
    required this.notesExtended,
    required this.notesMoved,
    required this.notesRecycled,
    required this.notesRestored,
    required this.notesDiscarded,
    required this.notesExpired,
    required this.firstTrackedAt,
    required this.lastActivityAt,
    required this.releaseDays,
    required this.longestStreakDays,
    required this.activeScoreSetId,
    required this.scoreSets,
  });

  factory AppStats.defaults() {
    final now = DateTime.now();
    final defaultScore = PuffHumScoreSet.defaults(at: now);
    return AppStats(
      lifetimePuffs: 0,
      lifetimeHums: 0,
      totalPoints: 0,
      attachmentsAdded: 0,
      notesExtended: 0,
      notesMoved: 0,
      notesRecycled: 0,
      notesRestored: 0,
      notesDiscarded: 0,
      notesExpired: 0,
      firstTrackedAt: now,
      lastActivityAt: null,
      releaseDays: const [],
      longestStreakDays: 0,
      activeScoreSetId: defaultScore.id,
      scoreSets: [defaultScore],
    );
  }

  factory AppStats.seed({
    required int lifetimePuffs,
    required int lifetimeHums,
    required int totalPoints,
  }) {
    final now = DateTime.now();
    final hasReleases = lifetimePuffs + lifetimeHums > 0;
    final releaseDays = hasReleases ? <String>[_dayKey(now)] : <String>[];
    final defaultScore = PuffHumScoreSet.seed(
      points: totalPoints,
      puffs: lifetimePuffs,
      hums: lifetimeHums,
      at: now,
    );
    return AppStats.defaults().copyWith(
      lifetimePuffs: lifetimePuffs,
      lifetimeHums: lifetimeHums,
      totalPoints: totalPoints,
      lastActivityAt: hasReleases ? now : null,
      releaseDays: releaseDays,
      longestStreakDays: hasReleases ? 1 : 0,
      activeScoreSetId: defaultScore.id,
      scoreSets: [defaultScore],
    );
  }

  int get lifetimeReleases => lifetimePuffs + lifetimeHums;

  PuffHumScoreSet get activeScoreSet {
    for (final scoreSet in scoreSets) {
      if (scoreSet.id == activeScoreSetId) return scoreSet;
    }
    return scoreSets.isEmpty ? PuffHumScoreSet.defaults() : scoreSets.first;
  }

  List<PuffHumScoreSet> get topScoreSets {
    final sorted = List<PuffHumScoreSet>.from(scoreSets);
    sorted.sort((a, b) {
      final pointCompare = b.points.compareTo(a.points);
      if (pointCompare != 0) return pointCompare;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted.take(10).toList();
  }

  int get level => (totalPoints ~/ 100) + 1;

  int get pointsIntoLevel => totalPoints % 100;

  int get currentStreakDays => _currentReleaseStreak(releaseDays);

  AppStats copyWith({
    int? lifetimePuffs,
    int? lifetimeHums,
    int? totalPoints,
    int? attachmentsAdded,
    int? notesExtended,
    int? notesMoved,
    int? notesRecycled,
    int? notesRestored,
    int? notesDiscarded,
    int? notesExpired,
    DateTime? firstTrackedAt,
    Object? lastActivityAt = _unchanged,
    List<String>? releaseDays,
    int? longestStreakDays,
    String? activeScoreSetId,
    List<PuffHumScoreSet>? scoreSets,
  }) {
    return AppStats(
      lifetimePuffs: lifetimePuffs ?? this.lifetimePuffs,
      lifetimeHums: lifetimeHums ?? this.lifetimeHums,
      totalPoints: totalPoints ?? this.totalPoints,
      attachmentsAdded: attachmentsAdded ?? this.attachmentsAdded,
      notesExtended: notesExtended ?? this.notesExtended,
      notesMoved: notesMoved ?? this.notesMoved,
      notesRecycled: notesRecycled ?? this.notesRecycled,
      notesRestored: notesRestored ?? this.notesRestored,
      notesDiscarded: notesDiscarded ?? this.notesDiscarded,
      notesExpired: notesExpired ?? this.notesExpired,
      firstTrackedAt: firstTrackedAt ?? this.firstTrackedAt,
      lastActivityAt: lastActivityAt == _unchanged
          ? this.lastActivityAt
          : lastActivityAt as DateTime?,
      releaseDays: releaseDays ?? this.releaseDays,
      longestStreakDays: longestStreakDays ?? this.longestStreakDays,
      activeScoreSetId: activeScoreSetId ?? this.activeScoreSetId,
      scoreSets: scoreSets ?? this.scoreSets,
    );
  }

  AppStats award({
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
    DateTime? at,
  }) {
    final activityAt = at ?? DateTime.now();
    final nextReleaseDays = List<String>.from(releaseDays);
    if (puffs + hums > 0) {
      final key = _dayKey(activityAt);
      if (!nextReleaseDays.contains(key)) {
        nextReleaseDays.add(key);
      }
    }
    final nextScoreSets = _awardActiveScoreSet(
      scoreSets,
      activeScoreSetId,
      points: points,
      puffs: puffs,
      hums: hums,
      at: activityAt,
    );

    return copyWith(
      lifetimePuffs: lifetimePuffs + puffs,
      lifetimeHums: lifetimeHums + hums,
      totalPoints: math.max(0, totalPoints + points),
      attachmentsAdded: attachmentsAdded + attachments,
      notesExtended: notesExtended + extended,
      notesMoved: notesMoved + moved,
      notesRecycled: notesRecycled + recycled,
      notesRestored: notesRestored + restored,
      notesDiscarded: notesDiscarded + discarded,
      notesExpired: notesExpired + expired,
      lastActivityAt: activityAt,
      releaseDays: nextReleaseDays,
      longestStreakDays: math.max(
        longestStreakDays,
        _longestReleaseStreak(nextReleaseDays),
      ),
      activeScoreSetId: _resolveActiveScoreSetId(
        nextScoreSets,
        activeScoreSetId,
      ),
      scoreSets: nextScoreSets,
    );
  }

  AppStats setActiveScoreSet(String id) {
    if (!scoreSets.any((scoreSet) => scoreSet.id == id)) return this;
    return copyWith(activeScoreSetId: id);
  }

  AppStats createScoreSet({required String name}) {
    final now = DateTime.now();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return this;
    final nextActive = PuffHumScoreSet.defaults(
      at: now,
    ).copyWith(name: trimmed);
    return copyWith(
      activeScoreSetId: nextActive.id,
      scoreSets: [...scoreSets, nextActive],
    );
  }

  AppStats renameScoreSet(String id, {required String name}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return this;
    var renamed = false;
    final nextScoreSets = [
      for (final scoreSet in scoreSets)
        if (scoreSet.id == id)
          scoreSet.copyWith(name: trimmed, updatedAt: DateTime.now())
        else
          scoreSet,
    ];
    renamed = scoreSets.any((scoreSet) => scoreSet.id == id);
    if (!renamed) return this;
    return copyWith(scoreSets: nextScoreSets);
  }

  AppStats deleteScoreSet(String id) {
    final remaining = scoreSets.where((scoreSet) => scoreSet.id != id).toList();
    if (remaining.isEmpty) {
      final replacement = PuffHumScoreSet.defaults();
      return copyWith(
        activeScoreSetId: replacement.id,
        scoreSets: [replacement],
      );
    }
    final nextActiveId = activeScoreSetId == id
        ? remaining.reduce((a, b) => a.points >= b.points ? a : b).id
        : activeScoreSetId;
    return copyWith(activeScoreSetId: nextActiveId, scoreSets: remaining);
  }
}

const Object _unchanged = Object();

String _dayKey(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _parseDay(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

int _currentReleaseStreak(List<String> days) {
  if (days.isEmpty) return 0;
  final keys = days.toSet();
  final today = DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!keys.contains(_dayKey(cursor))) {
    final yesterday = cursor.subtract(const Duration(days: 1));
    if (!keys.contains(_dayKey(yesterday))) return 0;
    cursor = yesterday;
  }

  var streak = 0;
  while (keys.contains(_dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

int _longestReleaseStreak(List<String> days) {
  final parsed = days.map(_parseDay).whereType<DateTime>().toList()..sort();
  if (parsed.isEmpty) return 0;

  var longest = 1;
  var current = 1;
  for (var i = 1; i < parsed.length; i++) {
    final gap = parsed[i].difference(parsed[i - 1]).inDays;
    if (gap == 1) {
      current++;
      longest = math.max(longest, current);
    } else if (gap > 1) {
      current = 1;
    }
  }
  return longest;
}

List<String> _readStringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}

String _scoreSetId(DateTime at) {
  return 'score-${at.microsecondsSinceEpoch}';
}

String _resolveActiveScoreSetId(
  List<PuffHumScoreSet> scoreSets,
  String activeScoreSetId,
) {
  if (scoreSets.any((scoreSet) => scoreSet.id == activeScoreSetId)) {
    return activeScoreSetId;
  }
  return scoreSets.isEmpty ? PuffHumScoreSet.defaults().id : scoreSets.first.id;
}

List<PuffHumScoreSet> _awardActiveScoreSet(
  List<PuffHumScoreSet> scoreSets,
  String activeScoreSetId, {
  required int points,
  required int puffs,
  required int hums,
  required DateTime at,
}) {
  final normalized = scoreSets.isEmpty
      ? <PuffHumScoreSet>[PuffHumScoreSet.defaults(at: at)]
      : List<PuffHumScoreSet>.from(scoreSets);
  final resolvedId = _resolveActiveScoreSetId(normalized, activeScoreSetId);
  return [
    for (final scoreSet in normalized)
      scoreSet.id == resolvedId
          ? scoreSet.award(points: points, puffs: puffs, hums: hums, at: at)
          : scoreSet,
  ];
}

List<PuffHumScoreSet> _readScoreSets(
  dynamic value, {
  required int fallbackPoints,
  required int fallbackPuffs,
  required int fallbackHums,
}) {
  final scoreSets = <PuffHumScoreSet>[];
  if (value is List) {
    for (final item in value) {
      final scoreSet = PuffHumScoreSet.fromDynamic(item);
      if (scoreSet != null) scoreSets.add(scoreSet);
    }
  }
  if (scoreSets.isNotEmpty) return scoreSets;
  return [
    PuffHumScoreSet.seed(
      points: fallbackPoints,
      puffs: fallbackPuffs,
      hums: fallbackHums,
    ),
  ];
}

class AppStatsAdapter extends TypeAdapter<AppStats> {
  @override
  final int typeId = appStatsTypeId;

  @override
  AppStats read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final now = DateTime.now();
    final lifetimePuffs = (fields[0] as int?) ?? 0;
    final lifetimeHums = (fields[1] as int?) ?? 0;
    final totalPoints = (fields[2] as int?) ?? 0;
    final scoreSets = _readScoreSets(
      fields[15],
      fallbackPoints: totalPoints,
      fallbackPuffs: lifetimePuffs,
      fallbackHums: lifetimeHums,
    );
    final activeScoreSetId = (fields[14] as String?) ?? scoreSets.first.id;
    return AppStats(
      lifetimePuffs: lifetimePuffs,
      lifetimeHums: lifetimeHums,
      totalPoints: totalPoints,
      attachmentsAdded: (fields[3] as int?) ?? 0,
      notesExtended: (fields[4] as int?) ?? 0,
      notesMoved: (fields[5] as int?) ?? 0,
      notesRecycled: (fields[6] as int?) ?? 0,
      notesRestored: (fields[7] as int?) ?? 0,
      notesDiscarded: (fields[8] as int?) ?? 0,
      notesExpired: (fields[9] as int?) ?? 0,
      firstTrackedAt: (fields[10] as DateTime?) ?? now,
      lastActivityAt: fields[11] as DateTime?,
      releaseDays: _readStringList(fields[12]),
      longestStreakDays: (fields[13] as int?) ?? 0,
      activeScoreSetId: _resolveActiveScoreSetId(scoreSets, activeScoreSetId),
      scoreSets: scoreSets,
    );
  }

  @override
  void write(BinaryWriter writer, AppStats obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.lifetimePuffs)
      ..writeByte(1)
      ..write(obj.lifetimeHums)
      ..writeByte(2)
      ..write(obj.totalPoints)
      ..writeByte(3)
      ..write(obj.attachmentsAdded)
      ..writeByte(4)
      ..write(obj.notesExtended)
      ..writeByte(5)
      ..write(obj.notesMoved)
      ..writeByte(6)
      ..write(obj.notesRecycled)
      ..writeByte(7)
      ..write(obj.notesRestored)
      ..writeByte(8)
      ..write(obj.notesDiscarded)
      ..writeByte(9)
      ..write(obj.notesExpired)
      ..writeByte(10)
      ..write(obj.firstTrackedAt)
      ..writeByte(11)
      ..write(obj.lastActivityAt)
      ..writeByte(12)
      ..write(obj.releaseDays)
      ..writeByte(13)
      ..write(obj.longestStreakDays)
      ..writeByte(14)
      ..write(obj.activeScoreSetId)
      ..writeByte(15)
      ..write(obj.scoreSets.map((scoreSet) => scoreSet.toMap()).toList());
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppStatsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
