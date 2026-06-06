import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/note.dart';
import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import 'app_surface.dart';
import 'countdown_text.dart';
import 'steam_particles.dart';

class NoteCard extends ConsumerWidget {
  const NoteCard({super.key, required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final now = ref.watch(currentTimeProvider).value ?? DateTime.now();
    final progress = expiryProgress(note.createdAt, note.expiresAt, now);
    final remaining = note.expiresAt.difference(now);
    final urgency = remaining <= const Duration(hours: 1)
        ? palette.urgent
        : remaining <= const Duration(hours: 24)
        ? palette.warning
        : palette.accent;
    final tagColor = note.colorTag == null
        ? null
        : ByepasserTheme.accentFor(note.colorTag!);

    return AppSurface(
      onTap: onTap,
      semanticLabel: '${note.displayTitle}. Expires soon.',
      child: Stack(
        children: [
          if (note.isSteamMode)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: const SteamParticles(opacity: 0.42),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 19,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (tagColor != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        color: tagColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                note.preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 15,
                  height: 1.28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    note.isSteamMode
                        ? CupertinoIcons.flame
                        : CupertinoIcons.clock,
                    color: urgency,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  CountdownText(note: note),
                  const Spacer(),
                  if (note.isSteamMode)
                    _Pill(label: 'Steam', color: palette.steam),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      children: [
                        Container(
                          height: 5,
                          color: palette.divider.withValues(alpha: 0.6),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width:
                              constraints.maxWidth *
                              progress.clamp(0.0, 1.0).toDouble(),
                          height: 5,
                          decoration: BoxDecoration(
                            color: urgency,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.text,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
