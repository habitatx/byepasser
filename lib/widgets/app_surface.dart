import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';

class AppSurface extends ConsumerWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.borderRadius = 22,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final palette = context.palette;
    final radius = BorderRadius.circular(borderRadius);

    final decoration = BoxDecoration(
      color: switch (settings.cardStyle) {
        CardStyles.minimal => palette.card,
        CardStyles.elevated => palette.card,
        _ => palette.card.withValues(alpha: palette.isDark ? 0.58 : 0.72),
      },
      borderRadius: radius,
      border: Border.all(
        color: settings.cardStyle == CardStyles.glassmorphic
            ? palette.divider.withValues(alpha: 0.55)
            : palette.divider.withValues(alpha: 0.35),
      ),
      boxShadow: settings.cardStyle == CardStyles.elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: palette.isDark ? 0.35 : 0.09,
                ),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ]
          : const [],
    );

    final content = ClipRRect(
      borderRadius: radius,
      child: settings.cardStyle == CardStyles.glassmorphic
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: DecoratedBox(
                decoration: decoration,
                child: Padding(padding: padding, child: child),
              ),
            )
          : DecoratedBox(
              decoration: decoration,
              child: Padding(padding: padding, child: child),
            ),
    );

    final semantic = Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: content,
    );

    if (onTap == null) {
      return semantic;
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: radius,
      onPressed: onTap,
      child: semantic,
    );
  }
}
