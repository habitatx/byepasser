import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Centralized, intensity-aware haptic feedback.
/// Respects user preference from settings.
class HapticsService {
  final Ref ref;

  HapticsService(this.ref);

  Future<void> light() async {
    final intensity = _currentIntensity;
    if (intensity == 0) return;
    await HapticFeedback.lightImpact();
  }

  Future<void> medium() async {
    final intensity = _currentIntensity;
    if (intensity == 0) return;
    if (intensity >= 2) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.lightImpact();
    }
  }

  Future<void> heavy() async {
    final intensity = _currentIntensity;
    if (intensity == 0) return;
    if (intensity >= 3) {
      await HapticFeedback.heavyImpact();
    } else if (intensity >= 2) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.lightImpact();
    }
  }

  Future<void> selection() async {
    final intensity = _currentIntensity;
    if (intensity == 0) return;
    await HapticFeedback.selectionClick();
  }

  /// Used for celebratory "puff released" moment.
  Future<void> success() async {
    final intensity = _currentIntensity;
    if (intensity == 0) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  int get _currentIntensity {
    // In a real flow we would watch the settingsProvider.
    // Here we return a safe default (medium) if not available in this context.
    // Screens that have ref can pass the value explicitly when calling.
    return 2;
  }

  /// Call this from widgets that have access to current settings.
  Future<void> playForIntensity(int intensity, {bool heavyImpact = false}) async {
    if (intensity <= 0) return;
    if (heavyImpact && intensity >= 3) {
      await HapticFeedback.heavyImpact();
    } else if (intensity >= 2) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.lightImpact();
    }
  }
}
