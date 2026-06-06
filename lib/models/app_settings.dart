import 'package:hive/hive.dart';

class ThemeKeys {
  static const whiteCanvas = 'whiteCanvas';
  static const softIvory = 'softIvory';
  static const neutralMist = 'neutralMist';
  static const deepDusk = 'deepDusk';
  static const obsidianVoid = 'obsidianVoid';
  static const followSystem = 'followSystem';

  static const all = [
    whiteCanvas,
    softIvory,
    neutralMist,
    deepDusk,
    obsidianVoid,
    followSystem,
  ];
}

class CardStyles {
  static const glassmorphic = 'glassmorphic';
  static const minimal = 'minimal';
  static const elevated = 'elevated';

  static const all = [glassmorphic, minimal, elevated];
}

class HapticIntensity {
  static const off = 'off';
  static const soft = 'soft';
  static const medium = 'medium';
  static const bright = 'bright';

  static const all = [off, soft, medium, bright];
}

class AnimationSpeeds {
  static const subtle = 'subtle';
  static const normal = 'normal';
  static const playful = 'playful';

  static const all = [subtle, normal, playful];
}

class AppSettings {
  const AppSettings({
    this.themeKey = ThemeKeys.whiteCanvas,
    this.accentIndex = 0,
    this.cardStyle = CardStyles.glassmorphic,
    this.defaultLifetimeMinutes = 10080,
    this.defaultSteamLifetimeMinutes = 15,
    this.autoGenerateTitle = true,
    this.showSecondsUnderHour = true,
    this.gentleNotifications = true,
    this.autoCopyBeforeDeletion = false,
    this.hapticIntensity = HapticIntensity.soft,
    this.animationSpeed = AnimationSpeeds.normal,
    this.showNoteCountInTabBar = true,
  });

  final String themeKey;
  final int accentIndex;
  final String cardStyle;
  final int defaultLifetimeMinutes;
  final int defaultSteamLifetimeMinutes;
  final bool autoGenerateTitle;
  final bool showSecondsUnderHour;
  final bool gentleNotifications;
  final bool autoCopyBeforeDeletion;
  final String hapticIntensity;
  final String animationSpeed;
  final bool showNoteCountInTabBar;

  AppSettings copyWith({
    String? themeKey,
    int? accentIndex,
    String? cardStyle,
    int? defaultLifetimeMinutes,
    int? defaultSteamLifetimeMinutes,
    bool? autoGenerateTitle,
    bool? showSecondsUnderHour,
    bool? gentleNotifications,
    bool? autoCopyBeforeDeletion,
    String? hapticIntensity,
    String? animationSpeed,
    bool? showNoteCountInTabBar,
  }) {
    return AppSettings(
      themeKey: themeKey ?? this.themeKey,
      accentIndex: accentIndex ?? this.accentIndex,
      cardStyle: cardStyle ?? this.cardStyle,
      defaultLifetimeMinutes:
          defaultLifetimeMinutes ?? this.defaultLifetimeMinutes,
      defaultSteamLifetimeMinutes:
          defaultSteamLifetimeMinutes ?? this.defaultSteamLifetimeMinutes,
      autoGenerateTitle: autoGenerateTitle ?? this.autoGenerateTitle,
      showSecondsUnderHour: showSecondsUnderHour ?? this.showSecondsUnderHour,
      gentleNotifications: gentleNotifications ?? this.gentleNotifications,
      autoCopyBeforeDeletion:
          autoCopyBeforeDeletion ?? this.autoCopyBeforeDeletion,
      hapticIntensity: hapticIntensity ?? this.hapticIntensity,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      showNoteCountInTabBar:
          showNoteCountInTabBar ?? this.showNoteCountInTabBar,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeKey': themeKey,
      'accentIndex': accentIndex,
      'cardStyle': cardStyle,
      'defaultLifetimeMinutes': defaultLifetimeMinutes,
      'defaultSteamLifetimeMinutes': defaultSteamLifetimeMinutes,
      'autoGenerateTitle': autoGenerateTitle,
      'showSecondsUnderHour': showSecondsUnderHour,
      'gentleNotifications': gentleNotifications,
      'autoCopyBeforeDeletion': autoCopyBeforeDeletion,
      'hapticIntensity': hapticIntensity,
      'animationSpeed': animationSpeed,
      'showNoteCountInTabBar': showNoteCountInTabBar,
    };
  }
}

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 2;

  @override
  AppSettings read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final fieldCount = reader.readByte();
    for (var i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return AppSettings(
      themeKey: fields[0] as String? ?? ThemeKeys.whiteCanvas,
      accentIndex: fields[1] as int? ?? 0,
      cardStyle: fields[2] as String? ?? CardStyles.glassmorphic,
      defaultLifetimeMinutes: fields[3] as int? ?? 10080,
      defaultSteamLifetimeMinutes: fields[4] as int? ?? 15,
      autoGenerateTitle: fields[5] as bool? ?? true,
      showSecondsUnderHour: fields[6] as bool? ?? true,
      gentleNotifications: fields[7] as bool? ?? true,
      autoCopyBeforeDeletion: fields[8] as bool? ?? false,
      hapticIntensity: fields[9] as String? ?? HapticIntensity.soft,
      animationSpeed: fields[10] as String? ?? AnimationSpeeds.normal,
      showNoteCountInTabBar: fields[11] as bool? ?? true,
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
      ..write(obj.showSecondsUnderHour)
      ..writeByte(7)
      ..write(obj.gentleNotifications)
      ..writeByte(8)
      ..write(obj.autoCopyBeforeDeletion)
      ..writeByte(9)
      ..write(obj.hapticIntensity)
      ..writeByte(10)
      ..write(obj.animationSpeed)
      ..writeByte(11)
      ..write(obj.showNoteCountInTabBar);
  }
}
