import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';

/// Central theme definition for Byepasser.
/// Supports 5 named themes + "Follow System" (uses light/dark pair).
/// Includes accent colors and card style configuration.
class ByepasserTheme {
  static const List<Color> accentPalette = [
    Color(0xFF6B9BD2), // Soft Sky Blue
    Color(0xFF7BA88F), // Sage Green
    Color(0xFFE07A5F), // Warm Terracotta
    Color(0xFF9B8FC2), // Soft Lavender
    Color(0xFFD4A574), // Muted Gold
    Color(0xFFC38D9E), // Dusty Rose
    Color(0xFF5DA8A8), // Calm Teal
    Color(0xFF7E9DC2), // Periwinkle
  ];

  static String accentName(int index) {
    const names = [
      'Sky',
      'Sage',
      'Terracotta',
      'Lavender',
      'Gold',
      'Rose',
      'Teal',
      'Periwinkle',
    ];
    return names[index.clamp(0, 7)];
  }

  /// Returns the ThemeData for a given settings snapshot.
  /// The app always uses a light-like structure but with deliberately chosen dark palettes
  /// for Deep Dusk and Obsidian (so we don't rely on platform dark mode except for Follow System).
  static ThemeData dataFor(AppSettings settings) {
    final isFollow = settings.themeKey == ThemeKeys.followSystem;
    final key = isFollow ? ThemeKeys.whiteCanvas : settings.themeKey;
    final accent = accentPalette[settings.accentIndex.clamp(0, 7)];
    final cardStyle = settings.cardStyle;

    final palette = _paletteFor(key);
    final brightness =
        (key == ThemeKeys.deepDusk || key == ThemeKeys.obsidianVoid)
        ? Brightness.dark
        : Brightness.light;

    final base = ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: palette.textOnAccent,
        secondary: accent.withValues(alpha: 0.85),
        onSecondary: palette.textOnAccent,
        surface: palette.card,
        onSurface: palette.textPrimary,
        error: const Color(0xFFE07A5F),
        onError: Colors.white,
      ),
      textTheme: _textThemeFor(palette),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _textThemeFor(palette).headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: accent,
        barBackgroundColor: palette.background.withValues(alpha: 0.92),
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(color: palette.textPrimary),
          navLargeTitleTextStyle: _textThemeFor(palette).headlineLarge
              ?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: palette.textPrimary,
              ),
          navTitleTextStyle: _textThemeFor(palette).titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: palette.textPrimary,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: cardStyle == CardStyles.elevated ? 8 : 0,
        shadowColor: palette.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            cardStyle == CardStyles.minimal ? 8 : 16,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: palette.textOnAccent,
        elevation: 4,
      ),
      dividerColor: palette.divider,
      iconTheme: IconThemeData(color: palette.textSecondary),
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        ByepasserColors(
          background: palette.background,
          card: palette.card,
          cardAlt: palette.cardAlt,
          textPrimary: palette.textPrimary,
          textSecondary: palette.textSecondary,
          textOnAccent: palette.textOnAccent,
          accent: accent,
          accentLight: accent.withValues(alpha: 0.15),
          divider: palette.divider,
          shadow: palette.shadow,
          danger: const Color(0xFFE07A5F),
          success: const Color(0xFF7BA88F),
          steamTint: const Color(0xFF9BA3AF),
          cardStyle: cardStyle,
          isDark: brightness == Brightness.dark,
        ),
      ],
    );
  }

  static _ThemePalette _paletteFor(String key) {
    switch (key) {
      case ThemeKeys.whiteCanvas:
        return _ThemePalette(
          background: const Color(0xFFFFFFFF),
          card: const Color(0xFFF8F8F8),
          cardAlt: const Color(0xFFF0F0F0),
          textPrimary: const Color(0xFF111111),
          textSecondary: const Color(0xFF555555),
          textOnAccent: Colors.white,
          divider: const Color(0xFFE5E5E5),
          shadow: Colors.black.withValues(alpha: 0.06),
        );
      case ThemeKeys.softIvory:
        return _ThemePalette(
          background: const Color(0xFFFAF6F0),
          card: const Color(0xFFF0EDE6),
          cardAlt: const Color(0xFFE8E4DC),
          textPrimary: const Color(0xFF2C2C2C),
          textSecondary: const Color(0xFF5F5F5F),
          textOnAccent: Colors.white,
          divider: const Color(0xFFE0D9CC),
          shadow: Colors.black.withValues(alpha: 0.05),
        );
      case ThemeKeys.neutralMist:
        return _ThemePalette(
          background: const Color(0xFFF0F0F0),
          card: Colors.white,
          cardAlt: const Color(0xFFF7F7F7),
          textPrimary: const Color(0xFF1F1F1F),
          textSecondary: const Color(0xFF5A5A5A),
          textOnAccent: Colors.white,
          divider: const Color(0xFFE0E0E0),
          shadow: Colors.black.withValues(alpha: 0.08),
        );
      case ThemeKeys.deepDusk:
        return _ThemePalette(
          background: const Color(0xFF1C1F2E),
          card: const Color(0xFF25293D),
          cardAlt: const Color(0xFF2F334A),
          textPrimary: const Color(0xFFEAEAEA),
          textSecondary: const Color(0xFFB0B5C3),
          textOnAccent: Colors.white,
          divider: const Color(0xFF3A3F55),
          shadow: Colors.black.withValues(alpha: 0.35),
        );
      case ThemeKeys.obsidianVoid:
      default:
        return _ThemePalette(
          background: const Color(0xFF000000),
          card: const Color(0xFF111111),
          cardAlt: const Color(0xFF1A1A1A),
          textPrimary: Colors.white,
          textSecondary: const Color(0xFF9A9A9A),
          textOnAccent: Colors.white,
          divider: const Color(0xFF222222),
          shadow: Colors.black.withValues(alpha: 0.6),
        );
    }
  }

  static TextTheme _textThemeFor(_ThemePalette p) {
    return TextTheme(
      displayLarge: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      displayMedium: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineLarge: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w400,
        height: 1.35,
      ),
      bodyMedium: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      bodySmall: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(
        color: p.textSecondary,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );
  }
}

/// Custom theme extension carrying Byepasser-specific semantic colors and card style.
/// Widgets read this via `Theme.of(context).extension<ByepasserColors>()!`
class ByepasserColors extends ThemeExtension<ByepasserColors> {
  final Color background;
  final Color card;
  final Color cardAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color textOnAccent;
  final Color accent;
  final Color accentLight;
  final Color divider;
  final Color shadow;
  final Color danger;
  final Color success;
  final Color steamTint;
  final String cardStyle;
  final bool isDark;

  const ByepasserColors({
    required this.background,
    required this.card,
    required this.cardAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnAccent,
    required this.accent,
    required this.accentLight,
    required this.divider,
    required this.shadow,
    required this.danger,
    required this.success,
    required this.steamTint,
    required this.cardStyle,
    required this.isDark,
  });

  @override
  ByepasserColors copyWith({
    Color? background,
    Color? card,
    Color? cardAlt,
    Color? textPrimary,
    Color? textSecondary,
    Color? textOnAccent,
    Color? accent,
    Color? accentLight,
    Color? divider,
    Color? shadow,
    Color? danger,
    Color? success,
    Color? steamTint,
    String? cardStyle,
    bool? isDark,
  }) {
    return ByepasserColors(
      background: background ?? this.background,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      accent: accent ?? this.accent,
      accentLight: accentLight ?? this.accentLight,
      divider: divider ?? this.divider,
      shadow: shadow ?? this.shadow,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      steamTint: steamTint ?? this.steamTint,
      cardStyle: cardStyle ?? this.cardStyle,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  ByepasserColors lerp(ThemeExtension<ByepasserColors>? other, double t) {
    if (other is! ByepasserColors) return this;
    return ByepasserColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      steamTint: Color.lerp(steamTint, other.steamTint, t)!,
      cardStyle: cardStyle,
      isDark: isDark,
    );
  }

  /// Helper for card container decoration that respects the chosen card style.
  BoxDecoration cardDecoration({
    bool isSteam = false,
    double blur = 18,
    Color? color,
    double? radius,
  }) {
    final baseColor = color ?? card;
    final resolvedRadius =
        radius ?? (cardStyle == CardStyles.minimal ? 10.0 : 18.0);
    final neutralBorder = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.16),
      width: 1,
    );

    if (cardStyle == CardStyles.glassmorphic) {
      return BoxDecoration(
        color: baseColor.withValues(alpha: isDark ? 0.72 : 0.78),
        borderRadius: BorderRadius.circular(resolvedRadius),
        border: neutralBorder,
        boxShadow: [
          BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 8)),
        ],
      );
    }

    if (cardStyle == CardStyles.elevated) {
      return BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(resolvedRadius),
        border: neutralBorder,
        boxShadow: [
          BoxShadow(color: shadow, blurRadius: 18, offset: const Offset(0, 10)),
          BoxShadow(
            color: shadow.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      );
    }

    // minimal
    return BoxDecoration(
      color: baseColor,
      borderRadius: BorderRadius.circular(resolvedRadius),
      border: neutralBorder,
    );
  }
}

class _ThemePalette {
  final Color background;
  final Color card;
  final Color cardAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color textOnAccent;
  final Color divider;
  final Color shadow;

  _ThemePalette({
    required this.background,
    required this.card,
    required this.cardAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnAccent,
    required this.divider,
    required this.shadow,
  });
}
