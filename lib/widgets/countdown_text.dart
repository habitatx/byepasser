import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';

/// Live countdown that rebuilds every second when remaining < 1 hour.
/// Uses a simple periodic rebuild via parent or can be used inside animated builders.
class CountdownText extends StatelessWidget {
  final DateTime expiresAt;
  final bool showSeconds;
  final TextStyle? style;
  final Color? color;

  const CountdownText({
    super.key,
    required this.expiresAt,
    required this.showSeconds,
    this.style,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = expiresAt.difference(DateTime.now());
    final text = formatRemaining(remaining, showSeconds: showSeconds);

    final isUrgent = remaining.inMinutes < 60;
    final isCritical = remaining.inMinutes < 10;

    Color effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    if (isCritical) {
      effectiveColor = Theme.of(context).extension<ByepasserColors>()?.danger ?? Colors.redAccent;
    } else if (isUrgent) {
      effectiveColor = Theme.of(context).extension<ByepasserColors>()?.accent ?? effectiveColor;
    }

    return Text(
      text,
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: effectiveColor,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: isUrgent ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}

// Small helper to force periodic rebuilds when used inside a note card grid.
class LiveCountdown extends StatefulWidget {
  final DateTime expiresAt;
  final bool showSeconds;
  final TextStyle? style;

  const LiveCountdown({
    super.key,
    required this.expiresAt,
    required this.showSeconds,
    this.style,
  });

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CountdownText(
      expiresAt: widget.expiresAt,
      showSeconds: widget.showSeconds,
      style: widget.style,
    );
  }
}

class Ticker {
  final void Function(Duration) onTick;
  Timer? _timer;

  Ticker(this.onTick);

  void start() {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      onTick(Duration.zero);
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}
