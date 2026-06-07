import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'board.dart';

const int noteTypeId = 0;

@HiveType(typeId: noteTypeId)
class Note extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String? title;

  @HiveField(2)
  final String body;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final DateTime expiresAt;

  @HiveField(5)
  final int lifetimeMinutes;

  @HiveField(6)
  final bool extended;

  @HiveField(7)
  final bool isSteamMode;

  @HiveField(8)
  final int? colorTag; // 0-7 optional

  @HiveField(9)
  final int indentLevel;

  @HiveField(10)
  final double? cardHeight; // for vertical stretch via handle

  @HiveField(11)
  final int orderIndex;

  @HiveField(12)
  final List<String> attachmentPaths;

  @HiveField(13)
  final String boardId;

  @HiveField(14)
  final DateTime? deletedAt;

  @HiveField(15)
  final String? crossReferenceImagePath;

  @HiveField(16)
  final int? crossReferencePinNumber;

  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    required this.lifetimeMinutes,
    required this.extended,
    required this.isSteamMode,
    this.colorTag,
    this.indentLevel = 0,
    this.cardHeight,
    this.orderIndex = 0,
    this.attachmentPaths = const [],
    this.boardId = defaultBoardId,
    this.deletedAt,
    this.crossReferenceImagePath,
    this.crossReferencePinNumber,
  });

  /// Create a new note. If title is null/empty, it will be auto-generated on the UI layer from body.
  factory Note.create({
    required String body,
    required int lifetimeMinutes,
    String? title,
    bool isSteamMode = false,
    int? colorTag,
    int indentLevel = 0,
    int orderIndex = 0,
    List<String> attachmentPaths = const [],
    String boardId = defaultBoardId,
    String? crossReferenceImagePath,
    int? crossReferencePinNumber,
  }) {
    final now = DateTime.now();
    final expires = now.add(Duration(minutes: lifetimeMinutes));
    return Note(
      id: const Uuid().v4(),
      title: (title != null && title.trim().isNotEmpty) ? title.trim() : null,
      body: body.trim(),
      createdAt: now,
      expiresAt: expires,
      lifetimeMinutes: lifetimeMinutes,
      extended: false,
      isSteamMode: isSteamMode,
      colorTag: colorTag,
      indentLevel: indentLevel,
      orderIndex: orderIndex,
      cardHeight: null,
      attachmentPaths: attachmentPaths,
      boardId: boardId,
      deletedAt: null,
      crossReferenceImagePath: crossReferenceImagePath,
      crossReferencePinNumber: crossReferencePinNumber,
    );
  }

  Note copyWith({
    Object? title = _unchanged,
    String? body,
    DateTime? expiresAt,
    int? lifetimeMinutes,
    bool? extended,
    bool? isSteamMode,
    Object? colorTag = _unchanged,
    int? indentLevel,
    double? cardHeight,
    int? orderIndex,
    List<String>? attachmentPaths,
    String? boardId,
    Object? deletedAt = _unchanged,
    Object? crossReferenceImagePath = _unchanged,
    Object? crossReferencePinNumber = _unchanged,
  }) {
    return Note(
      id: id,
      title: title == _unchanged ? this.title : title as String?,
      body: body ?? this.body,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lifetimeMinutes: lifetimeMinutes ?? this.lifetimeMinutes,
      extended: extended ?? this.extended,
      isSteamMode: isSteamMode ?? this.isSteamMode,
      colorTag: colorTag == _unchanged ? this.colorTag : colorTag as int?,
      indentLevel: indentLevel ?? this.indentLevel,
      cardHeight: cardHeight ?? this.cardHeight,
      orderIndex: orderIndex ?? this.orderIndex,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      boardId: boardId ?? this.boardId,
      deletedAt: deletedAt == _unchanged
          ? this.deletedAt
          : deletedAt as DateTime?,
      crossReferenceImagePath: crossReferenceImagePath == _unchanged
          ? this.crossReferenceImagePath
          : crossReferenceImagePath as String?,
      crossReferencePinNumber: crossReferencePinNumber == _unchanged
          ? this.crossReferencePinNumber
          : crossReferencePinNumber as int?,
    );
  }

  /// Effective display title: provided title or first non-empty line of body (max ~48 chars)
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final firstLine = body
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'Untitled note');
    final cleaned = firstLine.trim();
    if (cleaned.length <= 48) return cleaned;
    return '${cleaned.substring(0, 45)}...';
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isDeleted => deletedAt != null;

  bool get isImageCrossReference =>
      crossReferenceImagePath != null && crossReferencePinNumber != null;

  bool get isVisibleBoardNote => !isDeleted && !isImageCrossReference;

  Duration get remaining => expiresAt.difference(DateTime.now());

  /// For sorting: soonest to expire first
  int compareExpiry(Note other) => expiresAt.compareTo(other.expiresAt);
}

/// Manual Hive TypeAdapter so we don't require build_runner on first run.
/// This keeps the project immediately buildable and runnable.
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = noteTypeId;

  @override
  Note read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Note(
      id: fields[0] as String,
      title: fields[1] as String?,
      body: fields[2] as String,
      createdAt: fields[3] as DateTime,
      expiresAt: fields[4] as DateTime,
      lifetimeMinutes: fields[5] as int,
      extended: fields[6] as bool,
      isSteamMode: fields[7] as bool,
      colorTag: fields[8] as int?,
      indentLevel: (fields[9] as int?) ?? 0,
      cardHeight: fields[10] as double?,
      orderIndex: (fields[11] as int?) ?? 0,
      attachmentPaths: _readAttachmentPaths(fields[12]),
      boardId: (fields[13] as String?) ?? defaultBoardId,
      deletedAt: fields[14] as DateTime?,
      crossReferenceImagePath: fields[15] as String?,
      crossReferencePinNumber: fields[16] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.expiresAt)
      ..writeByte(5)
      ..write(obj.lifetimeMinutes)
      ..writeByte(6)
      ..write(obj.extended)
      ..writeByte(7)
      ..write(obj.isSteamMode)
      ..writeByte(8)
      ..write(obj.colorTag)
      ..writeByte(9)
      ..write(obj.indentLevel)
      ..writeByte(10)
      ..write(obj.cardHeight)
      ..writeByte(11)
      ..write(obj.orderIndex)
      ..writeByte(12)
      ..write(obj.attachmentPaths)
      ..writeByte(13)
      ..write(obj.boardId)
      ..writeByte(14)
      ..write(obj.deletedAt)
      ..writeByte(15)
      ..write(obj.crossReferenceImagePath)
      ..writeByte(16)
      ..write(obj.crossReferencePinNumber);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

const Object _unchanged = Object();

List<String> _readAttachmentPaths(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const <String>[];
}
