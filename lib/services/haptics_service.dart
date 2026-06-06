import 'package:flutter/services.dart';

import '../models/app_settings.dart';

class HapticsService {
  const HapticsService._();

  static Future<void> tap(AppSettings settings) async {
    switch (settings.hapticIntensity) {
      case HapticIntensity.off:
        return;
      case HapticIntensity.medium:
        return HapticFeedback.mediumImpact();
      case HapticIntensity.bright:
        return HapticFeedback.heavyImpact();
      case HapticIntensity.soft:
      default:
        return HapticFeedback.lightImpact();
    }
  }

  static Future<void> success(AppSettings settings) async {
    if (settings.hapticIntensity == HapticIntensity.off) {
      return;
    }
    return HapticFeedback.selectionClick();
  }
}
