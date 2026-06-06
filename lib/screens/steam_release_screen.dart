import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import '../widgets/accent_swatches.dart';
import '../widgets/app_surface.dart';
import '../widgets/lifetime_slider.dart';
import '../widgets/steam_particles.dart';

class SteamReleaseScreen extends HookConsumerWidget {
  const SteamReleaseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final titleController = useTextEditingController();
    final bodyController = useTextEditingController();
    useListenable(bodyController);
    final lifetime = useState(settings.defaultSteamLifetimeMinutes);
    final colorTag = useState<int?>(settings.accentIndex);

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Steam Mode'),
        backgroundColor: palette.background.withValues(alpha: 0.72),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: SteamParticles(dense: true, opacity: 0.62),
          ),
          SafeArea(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Let Out the Steam',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.02,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A short-lived private note with a clean exit.',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSurface(
                  borderRadius: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CupertinoTextField(
                        controller: titleController,
                        placeholder: 'Optional title',
                        padding: EdgeInsets.zero,
                        decoration: const BoxDecoration(),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        placeholderStyle: TextStyle(
                          color: palette.mutedText.withValues(alpha: 0.72),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoTextField(
                        controller: bodyController,
                        minLines: 8,
                        maxLines: 14,
                        placeholder: 'Vent here.',
                        padding: EdgeInsets.zero,
                        decoration: const BoxDecoration(),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 18,
                          height: 1.32,
                        ),
                        placeholderStyle: TextStyle(
                          color: palette.mutedText.withValues(alpha: 0.72),
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AppSurface(
                  child: LifetimeSlider(
                    label: 'Steam lifetime',
                    value: lifetime.value,
                    min: minSteamLifetimeMinutes,
                    max: maxSteamLifetimeMinutes,
                    presets: steamLifetimePresets,
                    onChanged: (value) => lifetime.value = value
                        .clamp(minSteamLifetimeMinutes, maxSteamLifetimeMinutes)
                        .toInt(),
                  ),
                ),
                const SizedBox(height: 14),
                AppSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Color tag',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AccentSwatches(
                        selectedIndex: colorTag.value,
                        allowNone: true,
                        onSelected: (value) => colorTag.value = value,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: bodyController.text.trim().isEmpty
                      ? null
                      : () => _release(
                          context: context,
                          ref: ref,
                          title: titleController.text,
                          body: bodyController.text,
                          lifetime: lifetime.value,
                          colorTag: colorTag.value,
                        ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: bodyController.text.trim().isEmpty
                          ? palette.cardStrong
                          : palette.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Release Steam',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyController.text.trim().isEmpty
                            ? palette.mutedText
                            : palette.onAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _release({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String body,
    required int lifetime,
    required int? colorTag,
  }) async {
    await ref
        .read(notesProvider.notifier)
        .createNote(
          title: title,
          body: body.trimRight(),
          lifetimeMinutes: lifetime,
          isSteamMode: true,
          colorTag: colorTag,
        );
    await HapticsService.success(ref.read(settingsProvider));
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
