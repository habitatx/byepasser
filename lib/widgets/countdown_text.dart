import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/note.dart';
import '../providers/app_providers.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';

class CountdownText extends ConsumerWidget {
  const CountdownText({super.key, required this.note, this.huge = false});

  final Note note;
  final bool huge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(currentTimeProvider).value ?? DateTime.now();
    final palette = context.palette;
    final remaining = note.remainingFrom(now);
    final showSeconds =
        settings.showSecondsUnderHour && remaining < const Duration(hours: 1);
    final color = remaining <= const Duration(hours: 1)
        ? palette.urgent
        : remaining <= const Duration(hours: 24)
        ? palette.warning
        : palette.mutedText;

    return Semantics(
      label: 'Expires in ${formatCountdown(remaining, showSeconds: true)}',
      child: Text(
        formatCountdown(remaining, showSeconds: showSeconds, huge: huge),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: huge ? 46 : 15,
          fontWeight: huge ? FontWeight.w800 : FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
