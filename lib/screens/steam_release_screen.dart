import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';
import '../widgets/app_surface.dart';
import '../widgets/steam_particles.dart';
import 'note_editor_screen.dart';

/// The special "A Puff" mode (friendly short-lived notes).
/// Features frosted glass + animated steam/puff background, quick creation of short-lived notes,
/// and "Burn Now" emphasis.
class SteamReleaseScreen extends ConsumerWidget {
  /// When true, this is embedded as a tab content (no extra scaffold chrome needed).
  final bool embedded;

  const SteamReleaseScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final settings = ref.watch(settingsProvider);

    final content = AppSurface(
      blur: 26,
      tint: colors.card.withValues(alpha: 0.15),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Big title
              Text(
                'A Puff',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 46,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'A friendly 5–30 minute note that disappears like a puff of cloud.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
              const SizedBox(height: 32),

              // Big action
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  await Navigator.of(context, rootNavigator: true).push(
                    CupertinoPageRoute(
                      builder: (_) => NoteEditorScreen(
                        isSteamMode: true,
                      ),
                    ),
                  );
                  // After return, the board will have refreshed via its own watchers.
                },
                icon: const Icon(CupertinoIcons.wind, size: 22),
                label: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('Write a Puff', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 18),

              Text(
                'Default puff lifetime: ${settings.defaultSteamLifetimeMinutes} min',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
              ),

              const Spacer(flex: 3),

              // Decorative steam at bottom
              SizedBox(
                height: 110,
                child: SteamParticles(
                  intensity: 1.0,
                  dense: true,
                  tint: colors.steamTint.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return CupertinoPageScaffold(
        backgroundColor: colors.background,
        child: content,
      );
    }

    return content;
  }
}
