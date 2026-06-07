import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';

/// Calm, friendly empty state for when there are no notes (or no dying soon notes).
class EmptyBoard extends StatelessWidget {
  final bool isFiltered; // true = Dying Soon is empty
  final VoidCallback? onCreatePuff;

  const EmptyBoard({
    super.key,
    this.isFiltered = false,
    this.onCreatePuff,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered ? Icons.hourglass_bottom_rounded : Icons.note_alt_outlined,
              size: 52,
              color: colors.textSecondary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 18),
            Text(
              isFiltered ? 'Nothing dying soon' : 'Your board is clear',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'All your notes have comfortable lifetimes ahead.'
                  : 'What do you want to remember — or forget?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary.withValues(alpha: 0.8),
                height: 1.35,
              ),
            ),

            if (!isFiltered) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _PromptChip('A thought I want to forget', onCreatePuff),
                  _PromptChip('Something that made me smile', onCreatePuff),
                  _PromptChip('An idea I\'m not ready to share', onCreatePuff),
                ],
              ),
            ],

            if (!isFiltered && onCreatePuff != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onCreatePuff,
                icon: const Icon(Icons.auto_awesome),
                label: const Text(
                  'Write a Puff',
                  style: TextStyle(decoration: TextDecoration.none),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.accent,
                  side: BorderSide(color: colors.accent.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const _PromptChip(this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: colors.cardAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.divider),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
