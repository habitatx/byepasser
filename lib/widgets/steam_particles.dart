import 'dart:math';
import 'package:flutter/material.dart';

/// Beautiful, calm animated steam / vapor particles.
/// Used both on Puff note cards and in the full "A Puff" mode.
class SteamParticles extends StatefulWidget {
  final double intensity; // 0.6 - 1.4
  final Color tint;
  final bool dense;

  const SteamParticles({
    super.key,
    this.intensity = 1.0,
    this.tint = const Color(0xFF9BA3AF),
    this.dense = false,
  });

  @override
  State<SteamParticles> createState() => _SteamParticlesState();
}

class _SteamParticlesState extends State<SteamParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_Particle> _particles;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (4200 / widget.intensity).round()),
    )..repeat();

    _particles = List.generate(widget.dense ? 26 : 14, (_) => _spawn());
  }

  _Particle _spawn() {
    return _Particle(
      x: _random.nextDouble(),
      y: 0.65 + _random.nextDouble() * 0.35,
      size: 4.0 + _random.nextDouble() * (widget.dense ? 11 : 8),
      speed: 0.018 + _random.nextDouble() * 0.032,
      drift: (_random.nextDouble() - 0.5) * 0.018,
      opacity: 0.12 + _random.nextDouble() * 0.22,
      phase: _random.nextDouble() * pi * 2,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SteamPainter(
            progress: _controller.value,
            particles: _particles,
            tint: widget.tint,
            intensity: widget.intensity,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _Particle {
  double x;
  double y;
  final double size;
  final double speed;
  final double drift;
  final double opacity;
  final double phase;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.drift,
    required this.opacity,
    required this.phase,
  });
}

class _SteamPainter extends CustomPainter {
  final double progress;
  final List<_Particle> particles;
  final Color tint;
  final double intensity;

  _SteamPainter({
    required this.progress,
    required this.particles,
    required this.tint,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.plus;

    for (final p in particles) {
      final t = (progress + (p.phase / (2 * pi))) % 1.0;

      final y = (p.y - (t * p.speed * 1.8 * intensity)) % 1.05;
      final x = (p.x + sin((t + p.phase) * 3.8) * p.drift * 1.6) % 1.0;

      final cx = x * size.width;
      final cy = y * size.height;

      final alpha = (p.opacity * (0.35 + 0.65 * (1 - (t * 0.9)))) * intensity;
      paint.color = tint.withValues(alpha: alpha.clamp(0.0, 0.55));

      final r = p.size * (0.65 + 0.35 * sin(t * 5.5 + p.phase));
      canvas.drawCircle(Offset(cx, cy), r, paint);

      // soft secondary halo
      paint.color = tint.withValues(alpha: alpha * 0.35);
      canvas.drawCircle(Offset(cx, cy), r * 1.7, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SteamPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.intensity != intensity ||
      oldDelegate.tint != tint;
}
