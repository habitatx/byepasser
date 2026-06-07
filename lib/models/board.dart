import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

const int boardTypeId = 2;
const String defaultBoardId = 'default-board';
const int maxBoardTitleLength = 20;

String normalizeBoardTitle(String title) {
  final trimmed = title.trim();
  final value = trimmed.isEmpty ? 'Unnamed' : trimmed;
  return value.length <= maxBoardTitleLength
      ? value
      : value.substring(0, maxBoardTitleLength);
}

@HiveType(typeId: boardTypeId)
class Board extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  final int orderIndex;

  @HiveField(4)
  final int colorTag;

  @HiveField(5)
  final String? imagePath;

  Board({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.orderIndex,
    required this.colorTag,
    this.imagePath,
  });

  factory Board.defaults() {
    return Board(
      id: defaultBoardId,
      title: normalizeBoardTitle('Board'),
      createdAt: DateTime.now(),
      orderIndex: 0,
      colorTag: 0,
    );
  }

  factory Board.create({required int orderIndex}) {
    return Board(
      id: const Uuid().v4(),
      title: normalizeBoardTitle('Board'),
      createdAt: DateTime.now(),
      orderIndex: orderIndex,
      colorTag: orderIndex % 8,
    );
  }

  Board copyWith({
    String? title,
    int? orderIndex,
    int? colorTag,
    Object? imagePath = _unchanged,
  }) {
    return Board(
      id: id,
      title: title == null ? this.title : normalizeBoardTitle(title),
      createdAt: createdAt,
      orderIndex: orderIndex ?? this.orderIndex,
      colorTag: colorTag ?? this.colorTag,
      imagePath: imagePath == _unchanged
          ? this.imagePath
          : imagePath as String?,
    );
  }
}

const Object _unchanged = Object();

class BoardAdapter extends TypeAdapter<Board> {
  @override
  final int typeId = boardTypeId;

  @override
  Board read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Board(
      id: (fields[0] as String?) ?? defaultBoardId,
      title: normalizeBoardTitle((fields[1] as String?) ?? ''),
      createdAt: (fields[2] as DateTime?) ?? DateTime.now(),
      orderIndex: (fields[3] as int?) ?? 0,
      colorTag: (fields[4] as int?) ?? 0,
      imagePath: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Board obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.orderIndex)
      ..writeByte(4)
      ..write(obj.colorTag)
      ..writeByte(5)
      ..write(obj.imagePath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
