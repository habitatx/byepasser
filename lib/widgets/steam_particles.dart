import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';

class SteamParticles extends HookConsumerWidget {
  const SteamParticles({super.key, this.dense = false, this.opacity = 0.55});

  final bool dense;
  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final palette = context.palette;
    final duration = switch (settings.animationSpeed) {
      AnimationSpeeds.subtle => const Duration(seconds: 12),
      AnimationSpeeds.playful => const Duration(seconds: 5),
      _ => const Duration(seconds: 8),
    };
    final controller = useAnimationController(duration: duration);

    useEffect(() {
      controller.repeat();
      return null;
    }, [duration]);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SteamPainter(
              progress: controller.value,
              color: palette.steam.withValues(alpha: opacity),
              count: dense ? 34 : 16,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _SteamPainter extends CustomPainter {
  _SteamPainter({
    required this.progress,
    required this.color,
    required this.count,
  });

  final double progress;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final seed = i * 19.31;
      final phase = (progress + i / count) % 1.0;
      final sideDrift = math.sin((phase * math.pi * 2) + seed) * 18;
      final xBase = ((math.sin(seed) + 1) / 2) * size.width;
      final x = (xBase + sideDrift).clamp(0.0, size.width);
      final y = size.height - (phase * size.height * 1.12);
      final swell = math.sin(phase * math.pi);
      final radius = 4 + swell * (i.isEven ? 12 : 8);
      paint.color = color.withValues(
        alpha: (1 - phase).clamp(0.0, 1.0).toDouble() * 0.45,
      );
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SteamPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.count != count;
  }
}
