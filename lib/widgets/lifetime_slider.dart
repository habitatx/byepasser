import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';

/// Beautiful continuous slider + smart preset chips for lifetime selection.
/// Used in note creation and settings.
class LifetimeSlider extends StatelessWidget {
  final int valueMinutes;
  final ValueChanged<int> onChanged;
  final bool isSteamMode; // limits range to 5-30 min

  const LifetimeSlider({
    super.key,
    required this.valueMinutes,
    required this.onChanged,
    this.isSteamMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final min = 5;
    final max = isSteamMode ? 30 : 30 * 24 * 60; // 30 days

    final presets = isSteamMode
        ? const [5, 10, 15, 20, 30]
        : lifetimePresets;

    final theme = Theme.of(context);
    final colors = theme.extension<ByepasserColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current value big label
        Row(
          children: [
            Text(
              isSteamMode ? 'Puff lifetime' : 'Lifetime',
              style: theme.textTheme.titleSmall?.copyWith(color: colors.textSecondary),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                formatFullLifetime(valueMinutes),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: colors.accent,
            inactiveTrackColor: colors.divider,
            thumbColor: colors.accent,
          ),
          child: CupertinoSlider(
            // Using CupertinoSlider gives nicer iOS feel even inside Material
            // but we wrap for consistency. Fall back to Slider if issues.
            value: valueMinutes.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: isSteamMode ? 25 : null,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),

        const SizedBox(height: 4),

        // Preset chips
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: presets.map((p) {
            final selected = (valueMinutes - p).abs() < (isSteamMode ? 2 : 30);
            return GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? colors.accent : colors.cardAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? colors.accent : colors.divider,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  formatLifetime(p),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? colors.textOnAccent : colors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}


