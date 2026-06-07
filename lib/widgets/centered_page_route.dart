import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CenteredPageRoute<T> extends PageRouteBuilder<T> {
  CenteredPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 190),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
              alignment: Alignment.center,
              child: child,
            ),
          );
        },
      );
}
