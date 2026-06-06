import 'package:hive/hive.dart';

const Object _unset = Object();

class Note {
  const Note({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    required this.lifetimeMinutes,
    this.title,
    this.extended = false,
    this.isSteamMode = false,
    this.colorTag,
  });

  final String id;
  final String? title;
  final String body;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int lifetimeMinutes;
  final bool extended;
  final bool isSteamMode;
  final int? colorTag;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get displayTitle {
    final trimmedTitle = title?.trim();
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      return trimmedTitle;
    }

    final firstLine = body
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      return 'Untitled note';
    }
    return firstLine.length <= 48
        ? firstLine
        : '${firstLine.substring(0, 45)}...';
  }

  String get preview {
    final compact = body
        .replaceAll(RegExp(r'[#*_>`\[\]()]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.isEmpty) {
      return 'Nothing here yet.';
    }
    return compact.length <= 150 ? compact : '${compact.substring(0, 147)}...';
  }

  Duration remainingFrom(DateTime now) => expiresAt.difference(now);

  Note copyWith({
    Object? title = _unset,
    String? body,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? lifetimeMinutes,
    bool? extended,
    bool? isSteamMode,
    Object? colorTag = _unset,
  }) {
    return Note(
      id: id,
      title: identical(title, _unset) ? this.title : title as String?,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lifetimeMinutes: lifetimeMinutes ?? this.lifetimeMinutes,
      extended: extended ?? this.extended,
      isSteamMode: isSteamMode ?? this.isSteamMode,
      colorTag: identical(colorTag, _unset) ? this.colorTag : colorTag as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'lifetimeMinutes': lifetimeMinutes,
      'extended': extended,
      'isSteamMode': isSteamMode,
      'colorTag': colorTag,
    };
  }

  String toShareText() {
    return [
      displayTitle,
      '',
      body,
      '',
      'Expires: ${expiresAt.toLocal()}',
      'Shared from Byepasser - Notes that say bye.',
    ].join('\n');
  }
}

class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 1;

  @override
  Note read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final fieldCount = reader.readByte();
    for (var i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return Note(
      id: fields[0] as String,
      title: fields[1] as String?,
      body: fields[2] as String,
      createdAt: fields[3] as DateTime,
      expiresAt: fields[4] as DateTime,
      lifetimeMinutes: fields[5] as int,
      extended: fields[6] as bool? ?? false,
      isSteamMode: fields[7] as bool? ?? false,
      colorTag: fields[8] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer
      ..writeByte(9)
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
      ..write(obj.colorTag);
  }
}
