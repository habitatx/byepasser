import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import '../theme/byepasser_theme.dart';
import 'countdown_text.dart';
import 'steam_particles.dart';

/// The beautiful, calm, responsive card used on the home board.
/// Supports glassmorphic / minimal / elevated per user setting.
/// Shows live countdown, color tag, steam treatment, and subtle interactions.
class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ByepasserColors>()!;
    final isSteam = note.isSteamMode;
    final remaining = note.remaining;
    final isDying = remaining.inMinutes < 60 * 6;
    final isCritical = remaining.inMinutes < 15;

    final cardDeco = colors.cardDecoration(isSteam: isSteam);

    final accentForTag = note.colorTag != null
        ? ByepasserTheme.accentPalette[note.colorTag!.clamp(0, 7)]
        : colors.accent;

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        HapticFeedback.selectionClick();
        onLongPress?.call();
      },
      child: Container(
        decoration: cardDeco,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Subtle steam layer for Steam notes
            if (isSteam)
              Positioned.fill(
                child: Opacity(
                  opacity: colors.isDark ? 0.55 : 0.38,
                  child: SteamParticles(
                    intensity: 0.85,
                    tint: colors.steamTint,
                    dense: false,
                  ),
                ),
              ),

            // Main content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header row: color dot + countdown
                  Row(
                    children: [
                      if (note.colorTag != null)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(right: 7),
                          decoration: BoxDecoration(
                            color: accentForTag,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: LiveCountdown(
                          expiresAt: note.expiresAt,
                          showSeconds: remaining.inHours < 1,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      if (isSteam)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.steamTint.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PUFF',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.steamTint,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              fontSize: 9,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 9),

                  // Title
                  Text(
                    note.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: colors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Body preview (first ~2 lines)
                  if (note.body.trim().isNotEmpty)
                    Text(
                      _preview(note.body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.32,
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Footer: created + urgency hint
                  Row(
                    children: [
                      Text(
                        _relativeCreated(note.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                      const Spacer(),
                      if (isDying && !isCritical)
                        Icon(Icons.schedule, size: 13, color: colors.accent.withValues(alpha: 0.7)),
                      if (isCritical)
                        Icon(Icons.warning_amber_rounded, size: 14, color: colors.danger),
                    ],
                  ),
                ],
              ),
            ),

            // Subtle top accent line for color tags
            if (note.colorTag != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 2.5,
                child: Container(color: accentForTag.withValues(alpha: 0.65)),
              ),
          ],
        ),
      ),
    );
  }

  String _preview(String body) {
    final lines = body.trim().split('\n');
    final first = lines.first.trim();
    if (first.length > 92) return '${first.substring(0, 89)}...';
    return first;
  }

  String _relativeCreated(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
