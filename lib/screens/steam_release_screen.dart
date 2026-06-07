import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/image_file_store.dart';
import '../theme/byepasser_theme.dart';
import '../utils/lifetime.dart';

const int _kPuffLifetimeMinutes = 15;
const int _kHumLifetimeMinutes = 7 * 24 * 60;
const List<int> _kPuffLifetimeSteps = <int>[5, 10, 15, 20, 25, 30];
const List<int> _kHumLifetimeSteps = <int>[
  15,
  30,
  60,
  2 * 60,
  4 * 60,
  8 * 60,
  12 * 60,
  24 * 60,
  2 * 24 * 60,
  3 * 24 * 60,
  7 * 24 * 60,
  14 * 24 * 60,
  30 * 24 * 60,
];

Future<bool?> showQuickNoteComposerDialog(
  BuildContext context, {
  required ValueListenable<bool> isHumListenable,
  required ValueChanged<int> onTabSelected,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    pageBuilder: (_, _, _) => _QuickNoteComposerDialog(
      isHumListenable: isHumListenable,
      onTabSelected: onTabSelected,
    ),
  );
}

/// Floating quick composer for Puff and Hum creation.
class SteamReleaseScreen extends HookConsumerWidget {
  final bool embedded;
  final bool isHum;

  const SteamReleaseScreen({super.key, this.embedded = false}) : isHum = false;

  const SteamReleaseScreen.hum({super.key, this.embedded = false})
    : isHum = true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyController = useTextEditingController();
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final settings = ref.watch(settingsProvider);
    final selectedBoard = ref.watch(selectedBoardProvider);
    final insertAfterNoteId = ref.watch(boardInsertAfterNoteIdProvider);
    final haptics = ref.read(hapticsProvider);
    final store = useMemoized(() => _QuickNoteStoreFacade(), const []);
    final picker = useMemoized(ImagePicker.new);
    final attachmentPaths = useState<List<String>>(const []);
    final isPickingAttachment = useState(false);
    final label = isHum ? 'Hum' : 'Puff';
    final lifetimeMinutes = useState(
      isHum ? _kHumLifetimeMinutes : _kPuffLifetimeMinutes,
    );

    Future<void> releaseNote() async {
      final body = bodyController.text.trim();
      if (body.isEmpty && attachmentPaths.value.isEmpty) return;

      final note = Note.create(
        body: body,
        title: null,
        lifetimeMinutes: lifetimeMinutes.value,
        isSteamMode: !isHum,
        attachmentPaths: attachmentPaths.value,
        boardId: selectedBoard.id,
      );
      final inserted = await store.insertNote(
        note,
        boardId: selectedBoard.id,
        afterNoteId: insertAfterNoteId,
      );
      await ref
          .read(notificationServiceProvider)
          .scheduleExpiryReminders(inserted, settings);
      ref.invalidate(notesProvider);
      bodyController.clear();
      attachmentPaths.value = const [];
      await haptics.success();
      if (!context.mounted) return;
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label released'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    final content = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 110),
          child: _FloatingComposerPanel(
            isHum: isHum,
            bodyController: bodyController,
            lifetimeMinutes: lifetimeMinutes.value,
            attachmentPaths: attachmentPaths.value,
            isPickingAttachment: isPickingAttachment.value,
            onLifetimeChanged: (value) => lifetimeMinutes.value = value,
            onCamera: () {
              unawaited(
                _pickQuickComposerAttachment(
                  context: context,
                  ref: ref,
                  picker: picker,
                  source: ImageSource.camera,
                  attachmentPaths: attachmentPaths,
                  isPickingAttachment: isPickingAttachment,
                ),
              );
            },
            onImage: () {
              unawaited(
                _pickQuickComposerAttachment(
                  context: context,
                  ref: ref,
                  picker: picker,
                  source: ImageSource.gallery,
                  attachmentPaths: attachmentPaths,
                  isPickingAttachment: isPickingAttachment,
                ),
              );
            },
            onRemoveAttachment: (path) => _removeQuickComposerAttachment(
              attachmentPaths: attachmentPaths,
              path: path,
            ),
            onRelease: releaseNote,
          ),
        ),
      ),
    );

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        border: null,
        middle: Text(label),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: releaseNote,
          child: Icon(CupertinoIcons.paperplane, color: colors.accent),
        ),
      ),
      child: content,
    );
  }
}

class _QuickNoteComposerDialog extends HookConsumerWidget {
  final ValueListenable<bool> isHumListenable;
  final ValueChanged<int> onTabSelected;

  const _QuickNoteComposerDialog({
    required this.isHumListenable,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHum = useValueListenable(isHumListenable);
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final bodyController = useTextEditingController();
    final settings = ref.watch(settingsProvider);
    final selectedBoard = ref.watch(selectedBoardProvider);
    final insertAfterNoteId = ref.watch(boardInsertAfterNoteIdProvider);
    final haptics = ref.read(hapticsProvider);
    final store = useMemoized(() => _QuickNoteStoreFacade(), const []);
    final picker = useMemoized(ImagePicker.new);
    final attachmentPaths = useState<List<String>>(const []);
    final isPickingAttachment = useState(false);
    final didRelease = useRef(false);
    final lifetimeMinutes = useState(
      isHum ? _kHumLifetimeMinutes : _kPuffLifetimeMinutes,
    );

    useEffect(() {
      lifetimeMinutes.value = isHum
          ? _kHumLifetimeMinutes
          : _kPuffLifetimeMinutes;
      return null;
    }, [isHum]);

    useEffect(() {
      return () {
        if (didRelease.value) return;
        for (final path in attachmentPaths.value) {
          unawaited(ImageFileStore.delete(path));
        }
      };
    }, const []);

    Future<void> releaseNote() async {
      final body = bodyController.text.trim();
      if (body.isEmpty && attachmentPaths.value.isEmpty) return;

      final note = Note.create(
        body: body,
        title: null,
        lifetimeMinutes: lifetimeMinutes.value,
        isSteamMode: !isHum,
        attachmentPaths: attachmentPaths.value,
        boardId: selectedBoard.id,
      );
      final inserted = await store.insertNote(
        note,
        boardId: selectedBoard.id,
        afterNoteId: insertAfterNoteId,
      );
      await ref
          .read(notificationServiceProvider)
          .scheduleExpiryReminders(inserted, settings);
      ref.invalidate(notesProvider);
      didRelease.value = true;
      await haptics.success();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(true);
    }

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _composerTabHitZoneHeight(context),
          child: IgnorePointer(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: ColoredBox(
                  color: colors.background.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _composerTabHitZoneHeight(context),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
            child: const SizedBox.expand(),
          ),
        ),
        Center(
          child: Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isHum ? 18 : 28,
              vertical: 24,
            ),
            backgroundColor: colors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                colors.cardStyle == CardStyles.minimal ? 10 : 18,
              ),
            ),
            child: _FloatingComposerPanel(
              isHum: isHum,
              bodyController: bodyController,
              lifetimeMinutes: lifetimeMinutes.value,
              attachmentPaths: attachmentPaths.value,
              isPickingAttachment: isPickingAttachment.value,
              onLifetimeChanged: (value) => lifetimeMinutes.value = value,
              onCamera: () {
                unawaited(
                  _pickQuickComposerAttachment(
                    context: context,
                    ref: ref,
                    picker: picker,
                    source: ImageSource.camera,
                    attachmentPaths: attachmentPaths,
                    isPickingAttachment: isPickingAttachment,
                  ),
                );
              },
              onImage: () {
                unawaited(
                  _pickQuickComposerAttachment(
                    context: context,
                    ref: ref,
                    picker: picker,
                    source: ImageSource.gallery,
                    attachmentPaths: attachmentPaths,
                    isPickingAttachment: isPickingAttachment,
                  ),
                );
              },
              onRemoveAttachment: (path) => _removeQuickComposerAttachment(
                attachmentPaths: attachmentPaths,
                path: path,
              ),
              onRelease: releaseNote,
            ),
          ),
        ),
        _ComposerTabHitZones(
          isHumListenable: isHumListenable,
          onTabSelected: onTabSelected,
        ),
      ],
    );
  }
}

class _ComposerTabHitZones extends StatelessWidget {
  final ValueListenable<bool> isHumListenable;
  final ValueChanged<int> onTabSelected;

  const _ComposerTabHitZones({
    required this.isHumListenable,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: _composerTabHitZoneHeight(context),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _activateTab(0),
              onTap: () => _finishTabSelection(context, 0),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _activateTab(1),
              onTap: () => _finishTabSelection(context, 1),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _activateTab(2),
              onTap: () => _finishTabSelection(context, 2),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _activateTab(3),
              onTap: () => _finishTabSelection(context, 3),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _activateTab(4),
              onTap: () => _finishTabSelection(context, 4),
            ),
          ),
        ],
      ),
    );
  }

  void _activateTab(int index) {
    onTabSelected(index);
    if (index == 1 || index == 2) {
      _setMode(index == 2);
    }
  }

  void _finishTabSelection(BuildContext context, int index) {
    _activateTab(index);
    if (index == 1 || index == 2) return;
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  void _setMode(bool isHum) {
    final listenable = isHumListenable;
    if (listenable is ValueNotifier<bool>) {
      listenable.value = isHum;
    }
  }
}

double _composerTabHitZoneHeight(BuildContext context) {
  return 96 + MediaQuery.paddingOf(context).bottom;
}

Future<void> _pickQuickComposerAttachment({
  required BuildContext context,
  required WidgetRef ref,
  required ImagePicker picker,
  required ImageSource source,
  required ValueNotifier<List<String>> attachmentPaths,
  required ValueNotifier<bool> isPickingAttachment,
}) async {
  if (isPickingAttachment.value) return;
  isPickingAttachment.value = true;
  FocusManager.instance.primaryFocus?.unfocus();

  try {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;

    final picked = await picker.pickImage(
      source: source,
      imageQuality: 86,
      maxWidth: 1800,
      requestFullMetadata: false,
    );
    if (picked == null) return;

    final storedPath = await ImageFileStore.saveNoteAttachment(picked.path);
    attachmentPaths.value = [...attachmentPaths.value, storedPath];
    await ref.read(hapticsProvider).selection();
  } on PlatformException {
    if (!context.mounted) return;
    _showComposerAttachmentMessage(context, 'Could not open image picker');
  } catch (_) {
    if (!context.mounted) return;
    _showComposerAttachmentMessage(context, 'Could not attach image');
  } finally {
    if (context.mounted) {
      isPickingAttachment.value = false;
    }
  }
}

Future<void> _removeQuickComposerAttachment({
  required ValueNotifier<List<String>> attachmentPaths,
  required String path,
}) async {
  attachmentPaths.value = attachmentPaths.value
      .where((existing) => existing != path)
      .toList();
  await ImageFileStore.delete(path);
}

void _showComposerAttachmentMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
  );
}

class _FloatingComposerPanel extends StatelessWidget {
  final bool isHum;
  final TextEditingController bodyController;
  final int lifetimeMinutes;
  final List<String> attachmentPaths;
  final bool isPickingAttachment;
  final ValueChanged<int> onLifetimeChanged;
  final VoidCallback onCamera;
  final VoidCallback onImage;
  final Future<void> Function(String path) onRemoveAttachment;
  final VoidCallback onRelease;

  const _FloatingComposerPanel({
    required this.isHum,
    required this.bodyController,
    required this.lifetimeMinutes,
    required this.attachmentPaths,
    required this.isPickingAttachment,
    required this.onLifetimeChanged,
    required this.onCamera,
    required this.onImage,
    required this.onRemoveAttachment,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final maxWidth = isHum ? 560.0 : 360.0;
    final minHeight = isHum ? 420.0 : 220.0;
    final fieldMinLines = isHum ? 12 : 4;
    final fieldMaxLines = isHum ? 18 : 6;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _opaqueComposerDecoration(colors),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoTextField(
                controller: bodyController,
                autofocus: true,
                minLines: fieldMinLines,
                maxLines: fieldMaxLines,
                textCapitalization: TextCapitalization.sentences,
                placeholder: isHum
                    ? 'Capture an inspiration...'
                    : 'Capture a thought...',
                padding: const EdgeInsets.all(14),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                  height: 1.32,
                ),
                placeholderStyle: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                decoration: BoxDecoration(
                  color: colors.cardAlt.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.divider),
                ),
              ),
              if (attachmentPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ComposerAttachmentStrip(
                  paths: attachmentPaths,
                  onRemove: onRemoveAttachment,
                ),
              ],
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _CompactLifetimeSetter(
                  valueMinutes: lifetimeMinutes,
                  onChanged: onLifetimeChanged,
                  isSteamMode: !isHum,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _ComposerIconButton(
                    tooltip: 'Camera',
                    icon: CupertinoIcons.camera,
                    onPressed: isPickingAttachment ? null : onCamera,
                  ),
                  const SizedBox(width: 4),
                  _ComposerIconButton(
                    tooltip: 'Image',
                    icon: CupertinoIcons.photo,
                    onPressed: isPickingAttachment ? null : onImage,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onRelease,
                    icon: Icon(
                      isHum ? CupertinoIcons.text_bubble : CupertinoIcons.wind,
                      size: 18,
                    ),
                    label: Text(isHum ? 'Hum' : 'Puff'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerAttachmentStrip extends StatelessWidget {
  final List<String> paths;
  final Future<void> Function(String path) onRemove;

  const _ComposerAttachmentStrip({required this.paths, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final path = paths[index];
          return AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    ImageFileStore.resolve(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: colors.cardAlt,
                      child: Icon(
                        CupertinoIcons.photo,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => unawaited(onRemove(path)),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: colors.card.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.divider),
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 15,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

BoxDecoration _opaqueComposerDecoration(ByepasserColors colors) {
  return colors.cardDecoration();
}

class _CompactLifetimeSetter extends StatelessWidget {
  final int valueMinutes;
  final ValueChanged<int> onChanged;
  final bool isSteamMode;

  const _CompactLifetimeSetter({
    required this.valueMinutes,
    required this.onChanged,
    required this.isSteamMode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final steps = isSteamMode ? _kPuffLifetimeSteps : _kHumLifetimeSteps;
    final selectedIndex = _nearestLifetimeStepIndex(valueMinutes, steps);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoSlider(
          value: selectedIndex.toDouble(),
          min: 0,
          max: (steps.length - 1).toDouble(),
          divisions: steps.length - 1,
          onChanged: (next) => onChanged(steps[next.round()]),
          activeColor: colors.accent,
        ),
        const SizedBox(height: 2),
        Text(
          formatFullLifetime(valueMinutes),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

int _nearestLifetimeStepIndex(int minutes, List<int> steps) {
  var nearestIndex = 0;
  var nearestDistance = (minutes - steps.first).abs();
  for (var i = 1; i < steps.length; i++) {
    final distance = (minutes - steps[i]).abs();
    if (distance < nearestDistance) {
      nearestIndex = i;
      nearestDistance = distance;
    }
  }
  return nearestIndex;
}

class _ComposerIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final enabled = onPressed != null;
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: enabled ? colors.accent : colors.textSecondary,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _QuickNoteStoreFacade {
  Box<Note> get notesBox => Hive.box<Note>('notes');
  Box<AppSettings> get settingsBox => Hive.box<AppSettings>('settings');

  Future<Note> updateNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<Note> insertNote(
    Note note, {
    required String boardId,
    String? afterNoteId,
  }) async {
    final ordered = getBoardNotesSorted(boardId);
    final anchorIndex = afterNoteId == null
        ? -1
        : ordered.indexWhere((candidate) => candidate.id == afterNoteId);
    final insertIndex = anchorIndex < 0 ? 0 : anchorIndex + 1;
    final followingIndent = insertIndex < ordered.length
        ? ordered[insertIndex].indentLevel
        : 0;
    final inserted = note.copyWith(
      orderIndex: insertIndex,
      indentLevel: followingIndent,
    );
    final next = <Note>[...ordered]..insert(insertIndex, inserted);
    for (var i = 0; i < next.length; i++) {
      await updateNote(next[i].copyWith(orderIndex: i));
    }
    return inserted.copyWith(orderIndex: insertIndex);
  }

  List<Note> getBoardNotesSorted(String boardId) {
    final list = notesBox.values
        .where((note) => note.isVisibleBoardNote && note.boardId == boardId)
        .toList();
    list.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });
    return list;
  }
}
