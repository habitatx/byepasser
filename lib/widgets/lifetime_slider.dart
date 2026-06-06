import 'package:flutter/cupertino.dart';

import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';

class LifetimeSlider extends StatelessWidget {
  const LifetimeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.presets,
    this.label = 'Lifetime',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final List<LifetimePreset> presets;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sliderValue = minutesToSlider(value, min: min, max: max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              formatLifetime(value),
              style: TextStyle(
                color: palette.accent,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '$label ${formatLifetime(value)}',
          child: CupertinoSlider(
            value: sliderValue,
            min: 0,
            max: 1,
            activeColor: palette.accent,
            onChanged: (next) {
              onChanged(sliderToMinutes(next, min: min, max: max));
            },
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final selected = preset.minutes == value;
            return CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => onChanged(preset.minutes),
              minimumSize: Size(0, 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? palette.accent
                      : palette.cardStrong.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? palette.accent
                        : palette.divider.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  preset.label,
                  style: TextStyle(
                    color: selected ? palette.onAccent : palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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
