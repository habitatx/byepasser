import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';

/// Full-width modular accent color picker used in Settings.
class AccentSwatches extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const AccentSwatches({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final palette = ByepasserTheme.accentPalette;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final itemWidth = (constraints.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(palette.length, (i) {
            final c = palette[i];
            final isSel = i == selectedIndex;
            return SizedBox(
              width: itemWidth,
              height: 42,
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSel
                          ? colors.textPrimary
                          : colors.divider.withValues(alpha: 0.5),
                      width: isSel ? 2 : 0.5,
                    ),
                    boxShadow: isSel
                        ? [
                            BoxShadow(
                              color: c.withValues(alpha: 0.45),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: isSel
                      ? Icon(Icons.check, size: 18, color: colors.textOnAccent)
                      : null,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
