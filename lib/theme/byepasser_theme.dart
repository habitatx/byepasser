import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';

class ByepasserPalette extends ThemeExtension<ByepasserPalette> {
  const ByepasserPalette({
    required this.key,
    required this.name,
    required this.background,
    required this.card,
    required this.cardStrong,
    required this.text,
    required this.mutedText,
    required this.divider,
    required this.accent,
    required this.onAccent,
    required this.urgent,
    required this.warning,
    required this.success,
    required this.steam,
    required this.isDark,
  });

  final String key;
  final String name;
  final Color background;
  final Color card;
  final Color cardStrong;
  final Color text;
  final Color mutedText;
  final Color divider;
  final Color accent;
  final Color onAccent;
  final Color urgent;
  final Color warning;
  final Color success;
  final Color steam;
  final bool isDark;

  @override
  ByepasserPalette copyWith({
    String? key,
    String? name,
    Color? background,
    Color? card,
    Color? cardStrong,
    Color? text,
    Color? mutedText,
    Color? divider,
    Color? accent,
    Color? onAccent,
    Color? urgent,
    Color? warning,
    Color? success,
    Color? steam,
    bool? isDark,
  }) {
    return ByepasserPalette(
      key: key ?? this.key,
      name: name ?? this.name,
      background: background ?? this.background,
      card: card ?? this.card,
      cardStrong: cardStrong ?? this.cardStrong,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      urgent: urgent ?? this.urgent,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      steam: steam ?? this.steam,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  ByepasserPalette lerp(ThemeExtension<ByepasserPalette>? other, double t) {
    if (other is! ByepasserPalette) {
      return this;
    }

    return ByepasserPalette(
      key: t < 0.5 ? key : other.key,
      name: t < 0.5 ? name : other.name,
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardStrong: Color.lerp(cardStrong, other.cardStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      urgent: Color.lerp(urgent, other.urgent, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      steam: Color.lerp(steam, other.steam, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

class ByepasserTheme {
  static const accentColors = [
    Color(0xFF6BA6FF),
    Color(0xFFFF8FA3),
    Color(0xFF8BCB88),
    Color(0xFFE8B86D),
    Color(0xFFB795FF),
    Color(0xFF5FCFC2),
    Color(0xFFFFA36C),
    Color(0xFFA7C7E7),
  ];

  static Color accentFor(int index) {
    final clamped = index.clamp(0, accentColors.length - 1).toInt();
    return accentColors[clamped];
  }

  static ThemeData dataFor(
    AppSettings settings, {
    Brightness platformBrightness = Brightness.light,
  }) {
    final palette = paletteFor(
      settings.themeKey,
      settings.accentIndex,
      platformBrightness: platformBrightness,
    );
    final base = palette.isDark ? ThemeData.dark() : ThemeData.light();
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: palette.isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: palette.accent,
          onPrimary: palette.onAccent,
          secondary: palette.steam,
          surface: palette.card,
          onSurface: palette.text,
          error: palette.urgent,
        );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      dividerColor: palette.divider,
      extensions: [palette],
      textTheme: base.textTheme.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: palette.isDark ? Brightness.dark : Brightness.light,
        primaryColor: palette.accent,
        scaffoldBackgroundColor: palette.background,
        barBackgroundColor: palette.background.withValues(alpha: 0.86),
        textTheme: CupertinoTextThemeData(
          primaryColor: palette.accent,
          textStyle: TextStyle(color: palette.text),
          navTitleTextStyle: TextStyle(
            color: palette.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          navLargeTitleTextStyle: TextStyle(
            color: palette.text,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  static ByepasserPalette paletteFor(
    String key,
    int accentIndex, {
    Brightness platformBrightness = Brightness.light,
  }) {
    final effectiveKey = key == ThemeKeys.followSystem
        ? (platformBrightness == Brightness.dark
              ? ThemeKeys.deepDusk
              : ThemeKeys.whiteCanvas)
        : key;
    final accent = accentFor(accentIndex);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF101014);

    switch (effectiveKey) {
      case ThemeKeys.softIvory:
        return ByepasserPalette(
          key: effectiveKey,
          name: 'Soft Ivory',
          background: const Color(0xFFFAF6F0),
          card: const Color(0xFFF0EDE6),
          cardStrong: const Color(0xFFE8E1D7),
          text: const Color(0xFF25221E),
          mutedText: const Color(0xFF777067),
          divider: const Color(0xFFDCD3C6),
          accent: accent,
          onAccent: onAccent,
          urgent: const Color(0xFFE06969),
          warning: const Color(0xFFD79A38),
          success: const Color(0xFF5BA86D),
          steam: const Color(0xFFB7D7D6),
          isDark: false,
        );
      case ThemeKeys.neutralMist:
        return ByepasserPalette(
          key: effectiveKey,
          name: 'Neutral Mist',
          background: const Color(0xFFF0F0F0),
          card: const Color(0xFFFFFFFF),
          cardStrong: const Color(0xFFE7E9EC),
          text: const Color(0xFF1F2933),
          mutedText: const Color(0xFF68727D),
          divider: const Color(0xFFD8DDE3),
          accent: accent,
          onAccent: onAccent,
          urgent: const Color(0xFFD95F6A),
          warning: const Color(0xFFD19936),
          success: const Color(0xFF56A66E),
          steam: const Color(0xFFA7D8E8),
          isDark: false,
        );
      case ThemeKeys.deepDusk:
        return ByepasserPalette(
          key: effectiveKey,
          name: 'Deep Dusk',
          background: const Color(0xFF1C1F2E),
          card: const Color(0xFF25293D),
          cardStrong: const Color(0xFF30364F),
          text: const Color(0xFFF5F7FF),
          mutedText: const Color(0xFFAEB6CC),
          divider: const Color(0xFF3B415C),
          accent: accent,
          onAccent: onAccent,
          urgent: const Color(0xFFFF7E87),
          warning: const Color(0xFFECC477),
          success: const Color(0xFF82D49A),
          steam: const Color(0xFFA9CBE8),
          isDark: true,
        );
      case ThemeKeys.obsidianVoid:
        return ByepasserPalette(
          key: effectiveKey,
          name: 'Obsidian Void',
          background: const Color(0xFF000000),
          card: const Color(0xFF0B0B0F),
          cardStrong: const Color(0xFF17171D),
          text: const Color(0xFFFFFFFF),
          mutedText: const Color(0xFFB5B6C1),
          divider: const Color(0xFF24242B),
          accent: accent,
          onAccent: onAccent,
          urgent: const Color(0xFFFF5D71),
          warning: const Color(0xFFFFC75E),
          success: const Color(0xFF76E39B),
          steam: const Color(0xFF7CC7FF),
          isDark: true,
        );
      case ThemeKeys.whiteCanvas:
      default:
        return ByepasserPalette(
          key: effectiveKey,
          name: 'White Canvas',
          background: const Color(0xFFFFFFFF),
          card: const Color(0xFFF8F8F8),
          cardStrong: const Color(0xFFEFEFEF),
          text: const Color(0xFF101010),
          mutedText: const Color(0xFF696969),
          divider: const Color(0xFFE0E0E0),
          accent: accent,
          onAccent: onAccent,
          urgent: const Color(0xFFD95765),
          warning: const Color(0xFFC98C25),
          success: const Color(0xFF4D9E66),
          steam: const Color(0xFFAEDCE4),
          isDark: false,
        );
    }
  }

  static String themeLabel(String key) {
    switch (key) {
      case ThemeKeys.softIvory:
        return 'Soft Ivory';
      case ThemeKeys.neutralMist:
        return 'Neutral Mist';
      case ThemeKeys.deepDusk:
        return 'Deep Dusk';
      case ThemeKeys.obsidianVoid:
        return 'Obsidian Void';
      case ThemeKeys.followSystem:
        return 'Follow System';
      case ThemeKeys.whiteCanvas:
      default:
        return 'White Canvas';
    }
  }

  static String cardStyleLabel(String key) {
    switch (key) {
      case CardStyles.minimal:
        return 'Minimal';
      case CardStyles.elevated:
        return 'Elevated';
      case CardStyles.glassmorphic:
      default:
        return 'Glassmorphic';
    }
  }

  static String speedLabel(String key) {
    switch (key) {
      case AnimationSpeeds.subtle:
        return 'Subtle';
      case AnimationSpeeds.playful:
        return 'Playful';
      case AnimationSpeeds.normal:
      default:
        return 'Normal';
    }
  }

  static String hapticLabel(String key) {
    switch (key) {
      case HapticIntensity.off:
        return 'Off';
      case HapticIntensity.medium:
        return 'Medium';
      case HapticIntensity.bright:
        return 'Bright';
      case HapticIntensity.soft:
      default:
        return 'Soft';
    }
  }
}

extension ByepasserPaletteLookup on BuildContext {
  ByepasserPalette get palette {
    return Theme.of(this).extension<ByepasserPalette>()!;
  }
}
