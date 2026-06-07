import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';

/// Horizontal scrollable accent color picker used in Settings.
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

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: palette.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = palette[i];
          final isSel = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? colors.textPrimary : Colors.transparent,
                  width: isSel ? 2.5 : 0,
                ),
                boxShadow: isSel
                    ? [
                        BoxShadow(
                          color: c.withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: isSel
                  ? Icon(Icons.check, size: 18, color: colors.textOnAccent)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
