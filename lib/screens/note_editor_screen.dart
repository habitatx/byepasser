import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';
import '../widgets/accent_swatches.dart';
import '../widgets/app_surface.dart';
import '../widgets/countdown_text.dart';
import '../widgets/lifetime_slider.dart';
import '../widgets/steam_released_dialog.dart';

class NoteEditorScreen extends HookConsumerWidget {
  const NoteEditorScreen({super.key, this.noteId});

  final String? noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final notes = ref.watch(notesProvider);
    final note = _findNote(notes, noteId);
    final isNew = noteId == null;

    if (!isNew && note == null) {
      return CupertinoPageScaffold(
        backgroundColor: palette.background,
        navigationBar: const CupertinoNavigationBar(middle: Text('Note gone')),
        child: Center(
          child: Text(
            'This note has already said bye.',
            style: TextStyle(color: palette.mutedText, fontSize: 16),
          ),
        ),
      );
    }

    final titleController = useTextEditingController(text: note?.title ?? '');
    final bodyController = useTextEditingController(text: note?.body ?? '');
    useListenable(titleController);
    useListenable(bodyController);

    final previewMode = useState(false);
    final lifetimeMinutes = useState(
      note?.lifetimeMinutes ?? settings.defaultLifetimeMinutes,
    );
    final colorTag = useState<int?>(note?.colorTag);

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      navigationBar: CupertinoNavigationBar(
        middle: Text(isNew ? 'New Note' : 'Edit Note'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _save(
            context: context,
            ref: ref,
            existing: note,
            title: titleController.text,
            body: bodyController.text,
            lifetimeMinutes: lifetimeMinutes.value,
            colorTag: colorTag.value,
          ),
          child: Text(
            'Save',
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
          children: [
            if (note != null) ...[
              _CountdownPanel(note: note),
              const SizedBox(height: 14),
            ],
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CupertinoTextField(
                    controller: titleController,
                    placeholder: settings.autoGenerateTitle
                        ? 'Optional title'
                        : 'Title',
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: const BoxDecoration(),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                    placeholderStyle: TextStyle(
                      color: palette.mutedText.withValues(alpha: 0.7),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CupertinoSlidingSegmentedControl<bool>(
                    groupValue: previewMode.value,
                    thumbColor: palette.accent,
                    backgroundColor: palette.cardStrong,
                    children: {
                      false: _SegmentLabel(
                        label: 'Edit',
                        selected: !previewMode.value,
                      ),
                      true: _SegmentLabel(
                        label: 'Preview',
                        selected: previewMode.value,
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        previewMode.value = value;
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: previewMode.value
                        ? _MarkdownPreview(data: bodyController.text)
                        : CupertinoTextField(
                            key: const ValueKey('editor'),
                            controller: bodyController,
                            minLines: 10,
                            maxLines: 18,
                            placeholder: 'What needs to leave your head?',
                            padding: EdgeInsets.zero,
                            decoration: const BoxDecoration(),
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 17,
                              height: 1.34,
                            ),
                            placeholderStyle: TextStyle(
                              color: palette.mutedText.withValues(alpha: 0.68),
                              fontSize: 17,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (isNew) ...[
              AppSurface(
                child: LifetimeSlider(
                  value: lifetimeMinutes.value,
                  min: minLifetimeMinutes,
                  max: maxLifetimeMinutes,
                  presets: lifetimePresets,
                  onChanged: (value) => lifetimeMinutes.value = value,
                ),
              ),
              const SizedBox(height: 14),
            ],
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
            if (note != null) ...[
              const SizedBox(height: 14),
              _NoteActions(note: note),
            ],
          ],
        ),
      ),
    );
  }

  Note? _findNote(List<Note> notes, String? id) {
    if (id == null) {
      return null;
    }
    for (final note in notes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  Future<void> _save({
    required BuildContext context,
    required WidgetRef ref,
    required Note? existing,
    required String title,
    required String body,
    required int lifetimeMinutes,
    required int? colorTag,
  }) async {
    final trimmedBody = body.trimRight();
    if (trimmedBody.trim().isEmpty) {
      await _showMessage(context, 'A note needs at least a little body.');
      return;
    }

    final controller = ref.read(notesProvider.notifier);
    if (existing == null) {
      await controller.createNote(
        title: title,
        body: trimmedBody,
        lifetimeMinutes: lifetimeMinutes,
        colorTag: colorTag,
      );
    } else {
      await controller.updateNote(
        existing.copyWith(
          title: title.trim().isEmpty ? null : title.trim(),
          body: trimmedBody,
          colorTag: colorTag,
        ),
      );
    }

    await HapticsService.success(ref.read(settingsProvider));
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _CountdownPanel extends ConsumerWidget {
  const _CountdownPanel({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: CountdownText(note: note, huge: true)),
              if (note.isSteamMode)
                Icon(CupertinoIcons.flame, color: palette.urgent, size: 30),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note.extended ? 'Already extended once' : 'until goodbye',
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: note.extended
                ? null
                : () async {
                    await ref.read(notesProvider.notifier).extendOnce(note.id);
                    await HapticsService.success(ref.read(settingsProvider));
                  },
            minimumSize: Size(0, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: note.extended
                    ? palette.cardStrong
                    : palette.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: note.extended ? palette.divider : palette.accent,
                ),
              ),
              child: Text(
                note.extended ? 'Extend used' : 'Extend once',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: note.extended ? palette.mutedText : palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteActions extends ConsumerWidget {
  const _NoteActions({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return AppSurface(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: CupertinoIcons.doc_on_doc,
                  label: 'Copy',
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: note.toShareText()),
                    );
                    await HapticsService.success(ref.read(settingsProvider));
                    if (context.mounted) {
                      await _showMessage(context, 'Copied.');
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: CupertinoIcons.share,
                  label: 'Share',
                  onTap: () async {
                    await SharePlus.instance.share(
                      ShareParams(
                        text: note.toShareText(),
                        subject: note.displayTitle,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _confirmDelete(context, ref, note),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: palette.urgent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.urgent.withValues(alpha: 0.38),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    note.isSteamMode
                        ? CupertinoIcons.flame
                        : CupertinoIcons.trash,
                    color: palette.urgent,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    note.isSteamMode ? 'Burn Now' : 'Delete Now',
                    style: TextStyle(
                      color: palette.urgent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: palette.cardStrong,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: palette.text, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? palette.onAccent : palette.text,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final content = data.trim().isEmpty ? '_Nothing here yet._' : data;
    return ConstrainedBox(
      key: const ValueKey('preview'),
      constraints: const BoxConstraints(minHeight: 240),
      child: MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: TextStyle(color: palette.text, fontSize: 17, height: 1.36),
          h1: TextStyle(
            color: palette.text,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
          h2: TextStyle(
            color: palette.text,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
          blockquote: TextStyle(color: palette.mutedText, fontSize: 17),
          code: TextStyle(
            color: palette.text,
            backgroundColor: palette.cardStrong,
          ),
          a: TextStyle(color: palette.accent),
        ),
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) {
      return CupertinoAlertDialog(
        title: Text(note.isSteamMode ? 'Burn now?' : 'Delete this note?'),
        content: const Text('This removes it from local storage immediately.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(note.isSteamMode ? 'Burn' : 'Delete'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  await ref.read(notesProvider.notifier).deleteNote(note.id);
  await HapticsService.success(ref.read(settingsProvider));
  if (!context.mounted) {
    return;
  }

  if (note.isSteamMode) {
    await showCupertinoDialog<void>(
      context: context,
      builder: (_) => const SteamReleasedDialog(),
    );
  }

  if (context.mounted) {
    Navigator.of(context).pop();
  }
}

Future<void> _showMessage(BuildContext context, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (context) {
      return CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
