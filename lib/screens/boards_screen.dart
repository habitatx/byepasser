import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_settings.dart';
import '../models/board.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/image_file_store.dart';
import '../theme/byepasser_theme.dart';
import 'image_annotator_screen.dart';

class BoardsScreen extends HookConsumerWidget {
  const BoardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(boardsProvider);
    final selectedBoard = ref.watch(selectedBoardProvider);
    final notes = ref.watch(notesProvider);
    final countsByBoard = <String, int>{};
    for (final note in notes) {
      if (!note.isVisibleBoardNote) continue;
      countsByBoard[note.boardId] = (countsByBoard[note.boardId] ?? 0) + 1;
    }
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final picker = useMemoized(ImagePicker.new);
    final store = useMemoized(_BoardsStoreFacade.new);
    final pendingBoardId = useState(selectedBoard.id);

    useEffect(() {
      if (boards.every((board) => board.id != pendingBoardId.value)) {
        pendingBoardId.value = selectedBoard.id;
      }
      return null;
    }, [boards, selectedBoard.id]);

    Future<void> addBoard() async {
      final board = Board.create(orderIndex: boards.length);
      await store.updateBoard(board);
      await store.updateSettings(
        store.settings.copyWith(selectedBoardId: board.id),
      );
      pendingBoardId.value = board.id;
      ref.invalidate(boardsProvider);
      ref.invalidate(settingsProvider);
    }

    Future<void> deleteBoard(Board board) async {
      if (boards.length <= 1) return;
      final confirmed = await _confirmDeleteBoard(context, board);
      if (confirmed != true) return;
      final recycledNotes = await store.deleteBoard(board.id);
      final notifications = ref.read(notificationServiceProvider);
      for (final note in recycledNotes) {
        await notifications.cancelForNote(note.id);
      }
      if (selectedBoard.id == board.id) {
        final remaining = store.getAllBoardsSorted();
        final next = remaining.isEmpty ? defaultBoardId : remaining.first.id;
        await store.updateSettings(
          store.settings.copyWith(selectedBoardId: next),
        );
      }
      ref.invalidate(boardsProvider);
      ref.invalidate(settingsProvider);
      ref.invalidate(notesProvider);
    }

    Future<void> selectBoard(Board board) async {
      await store.updateSettings(
        store.settings.copyWith(selectedBoardId: board.id),
      );
      ref.invalidate(settingsProvider);
      ref.invalidate(notesProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    void highlightBoard(Board board) {
      pendingBoardId.value = board.id;
    }

    Future<void> swapBoards(Board source, Board target) async {
      if (source.id == target.id) return;
      await store.updateBoard(source.copyWith(orderIndex: target.orderIndex));
      await store.updateBoard(target.copyWith(orderIndex: source.orderIndex));
      ref.invalidate(boardsProvider);
    }

    Future<void> updateTitle(Board board, String title) async {
      await store.updateBoard(board.copyWith(title: title));
      ref.invalidate(boardsProvider);
    }

    Future<void> updateColor(Board board, int index) async {
      await store.updateBoard(board.copyWith(colorTag: index, imagePath: null));
      ref.invalidate(boardsProvider);
    }

    Future<void> pickImage(Board board) async {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final savedPath = await ImageFileStore.saveBoardFace(
        board.id,
        picked.path,
      );
      await store.updateBoard(board.copyWith(imagePath: savedPath));
      ref.invalidate(boardsProvider);
      if (!context.mounted) return;
      final annotated = await openImageAnnotator(context, savedPath);
      if (annotated) {
        ref.invalidate(boardsProvider);
        ref.invalidate(notesProvider);
      }
    }

    Future<void> clearImage(Board board) async {
      await store.updateBoard(board.copyWith(imagePath: null));
      ref.invalidate(boardsProvider);
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('Boards'),
        trailing: CupertinoButton(
          minimumSize: const Size.square(44),
          padding: EdgeInsets.zero,
          onPressed: addBoard,
          child: Icon(CupertinoIcons.plus, color: colors.accent, size: 26),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 34),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1,
                crossAxisSpacing: 0,
                mainAxisSpacing: 14,
                childAspectRatio: 16 / 9,
              ),
              itemCount: boards.length,
              itemBuilder: (context, index) {
                final board = boards[index];
                return _BoardGridDropTarget(
                  board: board,
                  onSwap: swapBoards,
                  child: LongPressDraggable<Board>(
                    data: board,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: 280,
                        child: _BoardTile(
                          board: board,
                          messageCount: countsByBoard[board.id] ?? 0,
                          isSelected: pendingBoardId.value == board.id,
                          canDelete: false,
                          onHighlight: () {},
                          onCommitSelect: () {},
                          onDelete: () {},
                          onTitleChanged: (_) {},
                          onColorSelected: (_) {},
                          onPickImage: () {},
                          onAnnotateImage: () {},
                          onClearImage: () {},
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.42,
                      child: _BoardTile(
                        board: board,
                        messageCount: countsByBoard[board.id] ?? 0,
                        isSelected: pendingBoardId.value == board.id,
                        canDelete: boards.length > 1,
                        onHighlight: () => highlightBoard(board),
                        onCommitSelect: () => selectBoard(board),
                        onDelete: () => deleteBoard(board),
                        onTitleChanged: (title) => updateTitle(board, title),
                        onColorSelected: (color) => updateColor(board, color),
                        onPickImage: () => pickImage(board),
                        onAnnotateImage: () async {
                          final imagePath = board.imagePath;
                          if (imagePath == null) return;
                          final annotated = await openImageAnnotator(
                            context,
                            imagePath,
                          );
                          if (annotated) {
                            ref.invalidate(boardsProvider);
                            ref.invalidate(notesProvider);
                          }
                        },
                        onClearImage: () => clearImage(board),
                      ),
                    ),
                    child: _BoardTile(
                      board: board,
                      messageCount: countsByBoard[board.id] ?? 0,
                      isSelected: pendingBoardId.value == board.id,
                      canDelete: boards.length > 1,
                      onHighlight: () => highlightBoard(board),
                      onCommitSelect: () => selectBoard(board),
                      onDelete: () => deleteBoard(board),
                      onTitleChanged: (title) => updateTitle(board, title),
                      onColorSelected: (color) => updateColor(board, color),
                      onPickImage: () => pickImage(board),
                      onAnnotateImage: () async {
                        final imagePath = board.imagePath;
                        if (imagePath == null) return;
                        final annotated = await openImageAnnotator(
                          context,
                          imagePath,
                        );
                        if (annotated) {
                          ref.invalidate(boardsProvider);
                          ref.invalidate(notesProvider);
                        }
                      },
                      onClearImage: () => clearImage(board),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardGridDropTarget extends StatelessWidget {
  final Board board;
  final Widget child;
  final Future<void> Function(Board source, Board target) onSwap;

  const _BoardGridDropTarget({
    required this.board,
    required this.child,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Board>(
      onWillAcceptWithDetails: (details) => details.data.id != board.id,
      onAcceptWithDetails: (details) => onSwap(details.data, board),
      builder: (context, candidates, rejected) {
        return AnimatedScale(
          scale: candidates.isEmpty ? 1 : 0.96,
          duration: const Duration(milliseconds: 120),
          child: child,
        );
      },
    );
  }
}

Future<bool?> _confirmDeleteBoard(BuildContext context, Board board) {
  final title = board.title.trim().isEmpty ? 'this board' : board.title.trim();
  return showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Delete board?'),
      content: Text('Notes on $title will move to Recycle.'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

class _BoardTile extends StatelessWidget {
  final Board board;
  final int messageCount;
  final bool isSelected;
  final bool canDelete;
  final VoidCallback onHighlight;
  final VoidCallback onCommitSelect;
  final VoidCallback onDelete;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<int> onColorSelected;
  final VoidCallback onPickImage;
  final VoidCallback onAnnotateImage;
  final VoidCallback onClearImage;

  const _BoardTile({
    required this.board,
    required this.messageCount,
    required this.isSelected,
    required this.canDelete,
    required this.onHighlight,
    required this.onCommitSelect,
    required this.onDelete,
    required this.onTitleChanged,
    required this.onColorSelected,
    required this.onPickImage,
    required this.onAnnotateImage,
    required this.onClearImage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final accent = ByepasserTheme.accentPalette[board.colorTag.clamp(0, 7)];
    return Container(
      decoration: colors.cardDecoration(radius: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onHighlight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _BoardFace(
                      board: board,
                      accent: accent,
                      onAnnotateImage: onAnnotateImage,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _BoardSelectButton(
                        selected: isSelected,
                        onPressed: onCommitSelect,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _BoardCountBadge(count: messageCount),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Row(
                        children: [
                          _TinyIconButton(
                            icon: CupertinoIcons.photo,
                            color: Colors.white,
                            onPressed: onPickImage,
                          ),
                          if (board.imagePath != null)
                            _TinyIconButton(
                              icon: CupertinoIcons.xmark,
                              color: Colors.white,
                              onPressed: onClearImage,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 4),
              child: _BoardTitleField(board: board, onChanged: onTitleChanged),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 0, 7, 6),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    _BoardColorDot(
                      color: ByepasserTheme
                          .accentPalette[(board.colorTag + i) % 8],
                      selected: i == 0 && board.imagePath == null,
                      onTap: () => onColorSelected((board.colorTag + i) % 8),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _BoardImageSwatch(
                    selected: board.imagePath != null,
                    onTap: onPickImage,
                  ),
                  const Spacer(),
                  _TinyIconButton(
                    icon: CupertinoIcons.trash,
                    color: canDelete
                        ? colors.textSecondary
                        : colors.textSecondary.withValues(alpha: 0.28),
                    onPressed: canDelete ? onDelete : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardFace extends StatelessWidget {
  final Board board;
  final Color accent;
  final VoidCallback onAnnotateImage;

  const _BoardFace({
    required this.board,
    required this.accent,
    required this.onAnnotateImage,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = board.imagePath;
    final imageFile = imagePath == null
        ? null
        : ImageFileStore.resolve(imagePath);
    if (imageFile != null && imageFile.existsSync()) {
      return GestureDetector(
        onTap: onAnnotateImage,
        child: Image.file(imageFile, fit: BoxFit.cover),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.78)),
      child: Center(
        child: Icon(
          CupertinoIcons.square_stack_3d_up,
          color: Colors.white.withValues(alpha: 0.86),
          size: 30,
        ),
      ),
    );
  }
}

class _BoardCountBadge extends StatelessWidget {
  final int count;

  const _BoardCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1,
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
      ),
    );
  }
}

class _BoardTitleField extends HookWidget {
  final Board board;
  final ValueChanged<String> onChanged;

  const _BoardTitleField({required this.board, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final controller = useTextEditingController(text: board.title);
    final focusNode = useFocusNode();
    useEffect(() {
      if (!focusNode.hasFocus && controller.text != board.title) {
        controller.text = board.title;
      }
      return null;
    }, [board.id, board.title, focusNode.hasFocus]);

    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.center,
      maxLines: 1,
      maxLength: maxBoardTitleLength,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      placeholder: 'Board',
      decoration: BoxDecoration(
        color: colors.cardAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      onChanged: (value) {
        if (value.trim().isEmpty) return;
        onChanged(value);
      },
      onSubmitted: onChanged,
      onEditingComplete: () => onChanged(controller.text),
    );
  }
}

class _BoardColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _BoardColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 34,
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.textPrimary : colors.divider,
                width: selected ? 2.5 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardImageSwatch extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _BoardImageSwatch({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 38,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.cardAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? colors.textPrimary : colors.divider,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Icon(
              CupertinoIcons.photo,
              size: 17,
              color: selected ? colors.accent : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardSelectButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onPressed;

  const _BoardSelectButton({required this.selected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox.square(
      dimension: 38,
      child: IconButton(
        tooltip: selected ? 'Selected board' : 'Select board',
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 21,
        color: selected ? colors.card : Colors.white,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size.square(38),
          backgroundColor: selected
              ? colors.accent
              : Colors.black.withValues(alpha: 0.24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Colors.white.withValues(alpha: selected ? 0.0 : 0.82),
              width: 1.8,
            ),
          ),
        ),
        icon: const Icon(CupertinoIcons.checkmark),
      ),
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _TinyIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 22,
        color: color,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size.square(40),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _BoardsStoreFacade {
  Box<Board> get boardsBox => Hive.box<Board>('boards');
  Box<Note> get notesBox => Hive.box<Note>('notes');
  Box<AppSettings> get settingsBox => Hive.box<AppSettings>('settings');

  AppSettings get settings => settingsBox.get('user') ?? AppSettings.defaults();

  Future<void> updateSettings(AppSettings settings) async {
    await settingsBox.put('user', settings);
  }

  Future<void> updateBoard(Board board) async {
    await boardsBox.put(board.id, board);
  }

  Future<List<Note>> deleteBoard(String id) async {
    final remaining = getAllBoardsSorted()
        .where((board) => board.id != id)
        .toList();
    if (remaining.isEmpty) return const [];
    final now = DateTime.now();
    final notesToRecycle = notesBox.values
        .where((note) => note.boardId == id && !note.isDeleted)
        .toList();
    for (final note in notesToRecycle) {
      await notesBox.put(
        note.id,
        note.copyWith(deletedAt: now, orderIndex: 0, indentLevel: 0),
      );
    }
    await boardsBox.delete(id);
    for (var i = 0; i < remaining.length; i++) {
      await boardsBox.put(
        remaining[i].id,
        remaining[i].copyWith(orderIndex: i),
      );
    }
    return notesToRecycle;
  }

  List<Board> getAllBoardsSorted() {
    final boards = boardsBox.values.toList();
    boards.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
    return boards;
  }
}
