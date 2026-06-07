import 'package:flutter/material.dart';

import '../theme/byepasser_theme.dart';
import 'steam_particles.dart';

/// Celebratory full-screen-ish dialog shown after a Steam note is "Burned".
/// Features animated steam + nice text.
Future<void> showSteamReleased(BuildContext context) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, _) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            decoration: BoxDecoration(
              color: Theme.of(ctx).extension<ByepasserColors>()!.card,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 92,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const SteamParticles(
                        intensity: 1.35,
                        dense: true,
                        tint: Color(0xFFB8C0CC),
                      ),
                      Icon(
                        Icons.cloud_done_rounded,
                        size: 54,
                        color: Theme.of(ctx).extension<ByepasserColors>()!.success,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Puff released.',
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'There it goes.',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).extension<ByepasserColors>()!.textSecondary,
                      ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                    child: Text('Back to the board'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
