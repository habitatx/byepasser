import 'package:hive/hive.dart';

const int settingsTypeId = 1;

/// All user-configurable settings. Persisted in a dedicated Hive box.
@HiveType(typeId: settingsTypeId)
class AppSettings extends HiveObject {
  @HiveField(0)
  final String themeKey; // e.g. "whiteCanvas", "deepDusk", or "followSystem"

  @HiveField(1)
  final int accentIndex; // 0-7

  @HiveField(2)
  final String cardStyle; // "glassmorphic", "minimal", "elevated"

  @HiveField(3)
  final int defaultLifetimeMinutes; // 5 - 43200

  @HiveField(4)
  final int defaultSteamLifetimeMinutes; // 5 - 30

  @HiveField(5)
  final bool autoGenerateTitle;

  @HiveField(6)
  final bool showSecondsUnderOneHour;

  @HiveField(7)
  final bool gentleNotifications;

  @HiveField(8)
  final bool autoCopyBeforeDeletion;

  @HiveField(9)
  final int hapticsIntensity; // 0 = off, 1 = light, 2 = medium, 3 = strong

  @HiveField(10)
  final String animationSpeed; // "subtle", "normal", "playful"

  @HiveField(11)
  final bool showNoteCountInTabBar;

  AppSettings({
    required this.themeKey,
    required this.accentIndex,
    required this.cardStyle,
    required this.defaultLifetimeMinutes,
    required this.defaultSteamLifetimeMinutes,
    required this.autoGenerateTitle,
    required this.showSecondsUnderOneHour,
    required this.gentleNotifications,
    required this.autoCopyBeforeDeletion,
    required this.hapticsIntensity,
    required this.animationSpeed,
    required this.showNoteCountInTabBar,
  });

  factory AppSettings.defaults() => AppSettings(
        themeKey: ThemeKeys.whiteCanvas,
        accentIndex: 0,
        cardStyle: CardStyles.glassmorphic,
        defaultLifetimeMinutes: 7 * 24 * 60, // 7 days
        defaultSteamLifetimeMinutes: 15,
        autoGenerateTitle: true,
        showSecondsUnderOneHour: true,
        gentleNotifications: true,
        autoCopyBeforeDeletion: true,
        hapticsIntensity: 2,
        animationSpeed: AnimationSpeeds.normal,
        showNoteCountInTabBar: true,
      );

  AppSettings copyWith({
    String? themeKey,
    int? accentIndex,
    String? cardStyle,
    int? defaultLifetimeMinutes,
    int? defaultSteamLifetimeMinutes,
    bool? autoGenerateTitle,
    bool? showSecondsUnderOneHour,
    bool? gentleNotifications,
    bool? autoCopyBeforeDeletion,
    int? hapticsIntensity,
    String? animationSpeed,
    bool? showNoteCountInTabBar,
  }) {
    return AppSettings(
      themeKey: themeKey ?? this.themeKey,
      accentIndex: accentIndex ?? this.accentIndex,
      cardStyle: cardStyle ?? this.cardStyle,
      defaultLifetimeMinutes: defaultLifetimeMinutes ?? this.defaultLifetimeMinutes,
      defaultSteamLifetimeMinutes:
          defaultSteamLifetimeMinutes ?? this.defaultSteamLifetimeMinutes,
      autoGenerateTitle: autoGenerateTitle ?? this.autoGenerateTitle,
      showSecondsUnderOneHour:
          showSecondsUnderOneHour ?? this.showSecondsUnderOneHour,
      gentleNotifications: gentleNotifications ?? this.gentleNotifications,
      autoCopyBeforeDeletion: autoCopyBeforeDeletion ?? this.autoCopyBeforeDeletion,
      hapticsIntensity: hapticsIntensity ?? this.hapticsIntensity,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      showNoteCountInTabBar: showNoteCountInTabBar ?? this.showNoteCountInTabBar,
    );
  }
}

class ThemeKeys {
  static const String followSystem = 'followSystem';
  static const String whiteCanvas = 'whiteCanvas';
  static const String softIvory = 'softIvory';
  static const String neutralMist = 'neutralMist';
  static const String deepDusk = 'deepDusk';
  static const String obsidianVoid = 'obsidianVoid';

  static const List<String> all = [
    followSystem,
    whiteCanvas,
    softIvory,
    neutralMist,
    deepDusk,
    obsidianVoid,
  ];

  static String labelFor(String key) {
    switch (key) {
      case followSystem:
        return 'Follow System';
      case whiteCanvas:
        return 'White Canvas';
      case softIvory:
        return 'Soft Ivory';
      case neutralMist:
        return 'Neutral Mist';
      case deepDusk:
        return 'Deep Dusk';
      case obsidianVoid:
        return 'Obsidian Void';
      default:
        return 'White Canvas';
    }
  }
}

class CardStyles {
  static const String glassmorphic = 'glassmorphic';
  static const String minimal = 'minimal';
  static const String elevated = 'elevated';

  static const List<String> all = [glassmorphic, minimal, elevated];

  static String labelFor(String style) {
    switch (style) {
      case glassmorphic:
        return 'Glassmorphic';
      case minimal:
        return 'Minimal';
      case elevated:
        return 'Elevated';
      default:
        return 'Glassmorphic';
    }
  }
}

class AnimationSpeeds {
  static const String subtle = 'subtle';
  static const String normal = 'normal';
  static const String playful = 'playful';

  static const List<String> all = [subtle, normal, playful];

  static String labelFor(String speed) {
    switch (speed) {
      case subtle:
        return 'Subtle';
      case normal:
        return 'Normal';
      case playful:
        return 'Playful';
      default:
        return 'Normal';
    }
  }

  static double getScale(String speed) {
    switch (speed) {
      case subtle:
        return 0.7;
      case playful:
        return 1.35;
      default:
        return 1.0;
    }
  }
}

/// Manual adapter for AppSettings (no codegen dependency)
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = settingsTypeId;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      themeKey: fields[0] as String,
      accentIndex: fields[1] as int,
      cardStyle: fields[2] as String,
      defaultLifetimeMinutes: fields[3] as int,
      defaultSteamLifetimeMinutes: fields[4] as int,
      autoGenerateTitle: fields[5] as bool,
      showSecondsUnderOneHour: fields[6] as bool,
      gentleNotifications: fields[7] as bool,
      autoCopyBeforeDeletion: fields[8] as bool,
      hapticsIntensity: fields[9] as int,
      animationSpeed: fields[10] as String,
      showNoteCountInTabBar: fields[11] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.themeKey)
      ..writeByte(1)
      ..write(obj.accentIndex)
      ..writeByte(2)
      ..write(obj.cardStyle)
      ..writeByte(3)
      ..write(obj.defaultLifetimeMinutes)
      ..writeByte(4)
      ..write(obj.defaultSteamLifetimeMinutes)
      ..writeByte(5)
      ..write(obj.autoGenerateTitle)
      ..writeByte(6)
      ..write(obj.showSecondsUnderOneHour)
      ..writeByte(7)
      ..write(obj.gentleNotifications)
      ..writeByte(8)
      ..write(obj.autoCopyBeforeDeletion)
      ..writeByte(9)
      ..write(obj.hapticsIntensity)
      ..writeByte(10)
      ..write(obj.animationSpeed)
      ..writeByte(11)
      ..write(obj.showNoteCountInTabBar);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
