import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/board.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
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

    Future<void> addBoard() async {
      final board = Board.create(orderIndex: boards.length);
      await store.updateBoard(board);
      await store.updateSettings(
        store.settings.copyWith(selectedBoardId: board.id),
      );
      ref.invalidate(boardsProvider);
      ref.invalidate(settingsProvider);
    }

    Future<void> deleteBoard(Board board) async {
      if (boards.length <= 1) return;
      await store.deleteBoard(board.id);
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
      final docs = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${docs.path}/board_faces');
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      final extension = picked.path.split('.').last;
      final target = File(
        '${targetDir.path}/${board.id}_${DateTime.now().millisecondsSinceEpoch}.$extension',
      );
      final saved = await File(picked.path).copy(target.path);
      await store.updateBoard(board.copyWith(imagePath: saved.path));
      ref.invalidate(boardsProvider);
      if (!context.mounted) return;
      final annotated = await openImageAnnotator(context, saved.path);
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
          padding: EdgeInsets.zero,
          onPressed: addBoard,
          child: Icon(CupertinoIcons.plus, color: colors.accent),
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
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                childAspectRatio: 0.64,
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
                        width: 110,
                        child: _BoardTile(
                          board: board,
                          messageCount: countsByBoard[board.id] ?? 0,
                          isSelected: selectedBoard.id == board.id,
                          canDelete: false,
                          onSelect: () {},
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
                        isSelected: selectedBoard.id == board.id,
                        canDelete: boards.length > 1,
                        onSelect: () => selectBoard(board),
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
                      isSelected: selectedBoard.id == board.id,
                      canDelete: boards.length > 1,
                      onSelect: () => selectBoard(board),
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

class _BoardTile extends StatelessWidget {
  final Board board;
  final int messageCount;
  final bool isSelected;
  final bool canDelete;
  final VoidCallback onSelect;
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
    required this.onSelect,
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
                onTap: onSelect,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _BoardFace(
                      board: board,
                      accent: accent,
                      onAnnotateImage: onAnnotateImage,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _TinyIconButton(
                        icon: isSelected
                            ? CupertinoIcons.checkmark_alt_circle_fill
                            : CupertinoIcons.circle,
                        color: isSelected ? colors.accent : Colors.white,
                        onPressed: onSelect,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _BoardCountBadge(count: messageCount),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
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
                    const SizedBox(width: 3),
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
    if (imagePath != null && File(imagePath).existsSync()) {
      return GestureDetector(
        onTap: onAnnotateImage,
        child: Image.file(File(imagePath), fit: BoxFit.cover),
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
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
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
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
      onTap: onTap,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.textPrimary : colors.divider,
            width: selected ? 2 : 1,
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
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: colors.cardAlt,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? colors.textPrimary : colors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(
          CupertinoIcons.photo,
          size: 12,
          color: selected ? colors.accent : colors.textSecondary,
        ),
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
      dimension: 24,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: color,
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

  Future<void> deleteBoard(String id) async {
    final remaining = getAllBoardsSorted()
        .where((board) => board.id != id)
        .toList();
    if (remaining.isEmpty) return;
    final fallback = remaining.first.id;
    final notesToMove = notesBox.values
        .where((note) => note.boardId == id)
        .toList();
    for (final note in notesToMove) {
      await notesBox.put(note.id, note.copyWith(boardId: fallback));
    }
    await boardsBox.delete(id);
    for (var i = 0; i < remaining.length; i++) {
      await boardsBox.put(
        remaining[i].id,
        remaining[i].copyWith(orderIndex: i),
      );
    }
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
