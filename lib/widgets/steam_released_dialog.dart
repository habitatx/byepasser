import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/byepasser_theme.dart';
import 'app_surface.dart';
import 'steam_particles.dart';

class SteamReleasedDialog extends HookWidget {
  const SteamReleasedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 620),
    );

    useEffect(() {
      controller.forward();
      return null;
    }, const []);

    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutBack,
    );

    return Center(
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        child: SizedBox(
          width: 304,
          child: AppSurface(
            borderRadius: 28,
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 272,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(28)),
                      child: SteamParticles(dense: true, opacity: 0.76),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: palette.steam.withValues(alpha: 0.28),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.check_mark,
                            color: palette.text,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Steam released',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Gone from this device.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        CupertinoButton.filled(
                          borderRadius: BorderRadius.circular(999),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
