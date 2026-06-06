import 'package:flutter/cupertino.dart';

import '../theme/byepasser_theme.dart';

class EmptyBoard extends StatelessWidget {
  const EmptyBoard({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.chat_bubble_2, color: palette.accent, size: 52),
          const SizedBox(height: 18),
          Text(
            'Notes that say bye.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make a note, pick its lifetime, and let it disappear on schedule.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 16,
              height: 1.28,
            ),
          ),
          const SizedBox(height: 22),
          CupertinoButton.filled(
            borderRadius: BorderRadius.circular(999),
            onPressed: onCreate,
            child: const Text('Create a note'),
          ),
        ],
      ),
    );
  }
}
