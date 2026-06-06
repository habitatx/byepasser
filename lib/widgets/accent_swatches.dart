import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';

class AccentSwatches extends StatelessWidget {
  const AccentSwatches({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.allowNone = false,
  });

  final int? selectedIndex;
  final ValueChanged<int?> onSelected;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final entries = <Widget>[];

    if (allowNone) {
      entries.add(
        _SwatchButton(
          selected: selectedIndex == null,
          label: 'No color',
          child: Icon(
            CupertinoIcons.slash_circle,
            color: palette.mutedText,
            size: 22,
          ),
          onTap: () => onSelected(null),
        ),
      );
    }

    for (var i = 0; i < ByepasserTheme.accentColors.length; i++) {
      final color = ByepasserTheme.accentColors[i];
      entries.add(
        _SwatchButton(
          selected: selectedIndex == i,
          label: 'Color ${i + 1}',
          onTap: () => onSelected(i),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: const SizedBox(width: 28, height: 28),
          ),
        ),
      );
    }

    return Wrap(spacing: 10, runSpacing: 10, children: entries);
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.selected,
    required this.label,
    required this.child,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        minimumSize: Size(0, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: selected ? 2.4 : 1,
              color: selected ? palette.accent : palette.divider,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
