import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';

/// Frosted / blurred surface used for the special "A Puff" mode screen and glass cards.
/// Gives that calm iOS blur effect.
class AppSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? tint;

  const AppSurface({
    super.key,
    required this.child,
    this.blur = 22,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The real background color of the theme
        Container(color: colors.background),
        // Subtle blur layer on top for glassmorphic screens
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              color: (tint ?? colors.card).withValues(alpha: colors.isDark ? 0.18 : 0.22),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
