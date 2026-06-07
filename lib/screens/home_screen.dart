import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import '../models/board.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
import '../services/image_file_store.dart';
import '../theme/byepasser_theme.dart';
import '../widgets/centered_page_route.dart';
import '../widgets/countdown_text.dart';
import 'boards_screen.dart';
import 'image_annotator_screen.dart';
import 'note_editor_screen.dart';
import 'steam_release_screen.dart';

const double _kBoardCollapsedCardHeight = 92;
const int _kBoardMaxIndentLevel = 1;
const double _kBoardIndentWidth = 36;

enum _BoardOrderMode { stored, time }

/// Home now behaves like the Statusgy item-detail personal notes tab:
/// a private board with header controls, reorderable cards, quick note creation,
/// explicit indent/outdent controls, and card minimizing.
class HomeScreen extends HookConsumerWidget {
  final bool recycleBin;

  const HomeScreen({super.key, this.recycleBin = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsMinimized = useState(false);
    final orderMode = useState(_BoardOrderMode.stored);

    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final selectedBoard = ref.watch(selectedBoardProvider);
    final boards = ref.watch(boardsProvider);
    final insertAfterNoteId = ref.watch(boardInsertAfterNoteIdProvider);
    final storedNotes = recycleBin
        ? ref.watch(recycledNotesProvider)
        : ref.watch(currentBoardNotesProvider);
    final orderedNotes = useMemoized(() {
      final list = List<Note>.from(storedNotes);
      if (!recycleBin && orderMode.value == _BoardOrderMode.time) {
        list.sort((a, b) {
          final expiryCompare = a.compareExpiry(b);
          if (expiryCompare != 0) return expiryCompare;
          return a.orderIndex.compareTo(b.orderIndex);
        });
      }
      return list;
    }, [storedNotes, recycleBin, orderMode.value]);
    final preserveIndents =
        recycleBin || orderMode.value == _BoardOrderMode.stored;

    final store = useMemoized(() => _getOrCreateStore(), const []);
    final haptics = ref.read(hapticsProvider);

    useEffect(() {
      _initialSweepAndLoad(ref, store);
      return null;
    }, const []);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        border: null,
        middle: _BoardCapsuleTitle(
          title: recycleBin ? 'Recycle' : selectedBoard.title,
          icon: recycleBin
              ? Icons.recycling
              : CupertinoIcons.square_stack_3d_up,
          count: orderedNotes.length,
          isMinimized: cardsMinimized.value,
          isTimeSorted: !recycleBin && orderMode.value == _BoardOrderMode.time,
          onOpenBoards: recycleBin
              ? () => _discardCompletedTasks(
                  context,
                  ref,
                  store,
                  orderedNotes.length,
                  haptics,
                )
              : () async {
                  await Navigator.of(context).push(
                    CenteredPageRoute(builder: (_) => const BoardsScreen()),
                  );
                  ref.invalidate(boardsProvider);
                  ref.invalidate(settingsProvider);
                  ref.invalidate(notesProvider);
                },
          onToggleMinimized: orderedNotes.isEmpty
              ? null
              : () async {
                  cardsMinimized.value = !cardsMinimized.value;
                  await haptics.selection();
                },
          onToggleOrder: recycleBin
              ? null
              : () async {
                  orderMode.value = orderMode.value == _BoardOrderMode.stored
                      ? _BoardOrderMode.time
                      : _BoardOrderMode.stored;
                  ref.read(boardInsertAfterNoteIdProvider.notifier).state =
                      null;
                  await haptics.selection();
                },
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            if (orderedNotes.isEmpty)
              recycleBin
                  ? const _RecycleEmptyCard()
                  : _BoardEmptyCard(
                      onAddNote: () {
                        final isHum = ValueNotifier<bool>(false);
                        showQuickNoteComposerDialog(
                          context,
                          isHumListenable: isHum,
                          onTabSelected: (_) {},
                        ).whenComplete(isHum.dispose);
                      },
                    )
            else
              _BoardNoteList(
                notes: orderedNotes,
                recycleBin: recycleBin,
                isMinimized: cardsMinimized.value,
                preserveIndents: preserveIndents,
                canReorder: preserveIndents,
                selectedInsertAfterNoteId: preserveIndents && !recycleBin
                    ? insertAfterNoteId
                    : null,
                canMoveNotes: !recycleBin && boards.length > 1,
                onReorder: (oldIndex, newIndex) => _onReorder(
                  ref,
                  store,
                  orderedNotes,
                  oldIndex,
                  newIndex,
                  haptics,
                ),
                onTapNote: (note) => _openNoteForEdit(context, note, ref),
                onSelectTopInsert: preserveIndents && !recycleBin
                    ? () async {
                        ref
                                .read(boardInsertAfterNoteIdProvider.notifier)
                                .state =
                            null;
                        await haptics.selection();
                      }
                    : null,
                onToggleInsertAfterNote: preserveIndents && !recycleBin
                    ? (note) async {
                        final notifier = ref.read(
                          boardInsertAfterNoteIdProvider.notifier,
                        );
                        notifier.state = notifier.state == note.id
                            ? null
                            : note.id;
                        await haptics.selection();
                      }
                    : null,
                onDeleteNote: (note) => _deleteNote(ref, store, note, haptics),
                onRestoreNote: (note) =>
                    _restoreNote(ref, store, note, selectedBoard.id, haptics),
                onDiscardNote: (note) =>
                    _discardRecycledNote(ref, store, note, haptics),
                onMoveNote: (note) async {
                  final target = await _showMoveToBoardSelector(
                    context,
                    boards,
                    note.boardId,
                  );
                  if (target == null || target.id == note.boardId) return;
                  await store.moveNoteToBoard(note, target.id);
                  ref.invalidate(notesProvider);
                  await haptics.selection();
                  if (!context.mounted) return;
                  final shouldSwitch = await _showMoveConfirmationDialog(
                    context,
                    target,
                  );
                  if (shouldSwitch != true) return;
                  await store.selectBoard(target.id);
                  ref.invalidate(settingsProvider);
                  ref.invalidate(notesProvider);
                  ref.invalidate(boardsProvider);
                },
                onIndentNote: preserveIndents
                    ? (note, delta) =>
                          _adjustIndent(ref, store, note, delta, haptics)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onReorder(
    WidgetRef ref,
    _SimpleStoreFacade store,
    List<Note> ordered,
    int oldIndex,
    int newIndex,
    HapticsService haptics,
  ) async {
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (targetIndex < 0 || targetIndex >= ordered.length) return;

    final reordered = List<Note>.from(ordered);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    for (var i = 0; i < reordered.length; i++) {
      if (reordered[i].orderIndex != i) {
        await store.updateNote(reordered[i].copyWith(orderIndex: i));
      }
    }
    if (moved.isImageCrossReference) {
      final imagePath = moved.crossReferenceImagePath;
      if (imagePath != null) {
        await store.renumberCrossReferenceNotes(imagePath);
      }
    }
    ref.invalidate(notesProvider);
    await haptics.light();
  }

  Future<void> _adjustIndent(
    WidgetRef ref,
    _SimpleStoreFacade store,
    Note note,
    int delta,
    HapticsService haptics,
  ) async {
    final target = (note.indentLevel + delta)
        .clamp(0, _kBoardMaxIndentLevel)
        .toInt();
    if (target == note.indentLevel) return;
    await store.updateNote(note.copyWith(indentLevel: target));
    ref.invalidate(notesProvider);
    await haptics.selection();
  }

  Future<void> _deleteNote(
    WidgetRef ref,
    _SimpleStoreFacade store,
    Note note,
    HapticsService haptics,
  ) async {
    await store.recycleNote(note);
    await ref.read(notificationServiceProvider).cancelForNote(note.id);
    ref.invalidate(notesProvider);
    await haptics.light();
  }

  Future<void> _restoreNote(
    WidgetRef ref,
    _SimpleStoreFacade store,
    Note note,
    String activeBoardId,
    HapticsService haptics,
  ) async {
    await store.restoreNote(note, activeBoardId);
    ref.invalidate(notesProvider);
    await haptics.success();
  }

  Future<void> _discardCompletedTasks(
    BuildContext context,
    WidgetRef ref,
    _SimpleStoreFacade store,
    int completedCount,
    HapticsService haptics,
  ) async {
    final confirmed = await _confirmDiscardCompletedTasks(
      context,
      completedCount,
    );
    if (confirmed != true) return;
    await store.discardRecycledNotes();
    ref.invalidate(notesProvider);
    await haptics.medium();
  }

  Future<void> _discardRecycledNote(
    WidgetRef ref,
    _SimpleStoreFacade store,
    Note note,
    HapticsService haptics,
  ) async {
    await store.discardRecycledNote(note.id);
    ref.invalidate(notesProvider);
    await haptics.medium();
  }

  Future<void> _openNoteForEdit(
    BuildContext context,
    Note note,
    WidgetRef ref,
  ) async {
    await Navigator.of(context).push(
      CenteredPageRoute(builder: (_) => NoteEditorScreen(existingNote: note)),
    );
    ref.invalidate(notesProvider);
  }

  Future<void> _initialSweepAndLoad(
    WidgetRef ref,
    _SimpleStoreFacade store,
  ) async {
    await store.sweepExpiredNotes();
    ref.invalidate(notesProvider);
  }

  _SimpleStoreFacade _getOrCreateStore() {
    return _SimpleStoreFacade();
  }
}

class _BoardCapsuleTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final bool isMinimized;
  final bool isTimeSorted;
  final VoidCallback? onOpenBoards;
  final VoidCallback? onToggleMinimized;
  final VoidCallback? onToggleOrder;

  const _BoardCapsuleTitle({
    required this.title,
    required this.icon,
    required this.count,
    required this.isMinimized,
    required this.isTimeSorted,
    required this.onOpenBoards,
    required this.onToggleMinimized,
    required this.onToggleOrder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return GestureDetector(
      onTap: onOpenBoards,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: colors.cardDecoration(color: colors.card, radius: 999),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: colors.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: Text(
                title.trim().isEmpty ? 'Board' : title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count${isMinimized && count > 0 ? ' min' : ''}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onToggleOrder != null) ...[
              const SizedBox(width: 8),
              _CapsuleIconButton(
                tooltip: isTimeSorted
                    ? 'Sort by stored order'
                    : 'Sort by expiry time',
                onPressed: onToggleOrder,
                icon: isTimeSorted
                    ? CupertinoIcons.clock
                    : CupertinoIcons.line_horizontal_3_decrease,
              ),
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 8),
            _CapsuleIconButton(
              tooltip: isMinimized
                  ? 'Expand board cards'
                  : 'Minimize board cards',
              onPressed: onToggleMinimized,
              icon: isMinimized
                  ? CupertinoIcons.arrow_up_left_arrow_down_right
                  : CupertinoIcons.arrow_down_right_arrow_up_left,
            ),
          ],
        ),
      ),
    );
  }
}

class _CapsuleIconButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  const _CapsuleIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox(
      width: 42,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 18,
        color: onPressed == null
            ? colors.textSecondary.withValues(alpha: 0.35)
            : colors.accent,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(42, 34),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _BoardEmptyCard extends StatelessWidget {
  final VoidCallback onAddNote;

  const _BoardEmptyCard({required this.onAddNote});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return _BoardPanel(
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 320),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onAddNote,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.11),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.wind,
                      color: colors.accent,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Nothing to carry.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drop a thought here and let it expire on your terms.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onAddNote,
                    icon: const Icon(CupertinoIcons.plus),
                    label: const Text('Start'),
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

class _RecycleEmptyCard extends StatelessWidget {
  const _RecycleEmptyCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return _BoardPanel(
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 320),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.recycling, color: colors.accent, size: 42),
            ),
            const SizedBox(height: 22),
            Text(
              'Recycle',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Deleted notes will wait here until you bring them back.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardNoteList extends StatelessWidget {
  final List<Note> notes;
  final bool recycleBin;
  final bool isMinimized;
  final bool preserveIndents;
  final bool canReorder;
  final String? selectedInsertAfterNoteId;
  final bool canMoveNotes;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<Note> onTapNote;
  final VoidCallback? onSelectTopInsert;
  final ValueChanged<Note>? onToggleInsertAfterNote;
  final ValueChanged<Note> onDeleteNote;
  final ValueChanged<Note> onRestoreNote;
  final ValueChanged<Note> onDiscardNote;
  final ValueChanged<Note> onMoveNote;
  final void Function(Note note, int delta)? onIndentNote;

  const _BoardNoteList({
    required this.notes,
    required this.recycleBin,
    required this.isMinimized,
    required this.preserveIndents,
    required this.canReorder,
    required this.selectedInsertAfterNoteId,
    required this.canMoveNotes,
    required this.onReorder,
    required this.onTapNote,
    required this.onSelectTopInsert,
    required this.onToggleInsertAfterNote,
    required this.onDeleteNote,
    required this.onRestoreNote,
    required this.onDiscardNote,
    required this.onMoveNote,
    required this.onIndentNote,
  });

  @override
  Widget build(BuildContext context) {
    final showInsertBars =
        !recycleBin &&
        onSelectTopInsert != null &&
        onToggleInsertAfterNote != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showInsertBars)
          _BoardInsertRail(
            selected:
                onSelectTopInsert != null && selectedInsertAfterNoteId == null,
            enabled: onSelectTopInsert != null,
            onTap: onSelectTopInsert,
          ),
        ReorderableListView.builder(
          key: PageStorageKey(
            recycleBin
                ? 'byepasser-recycle-card-list'
                : 'byepasser-board-card-list',
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          itemCount: notes.length,
          onReorder: canReorder ? onReorder : (_, _) {},
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final lift = Curves.easeOut.transform(animation.value);
                return Transform.scale(
                  scale: 1 + lift * 0.02,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 10 * lift,
                    borderRadius: BorderRadius.circular(18),
                    child: child,
                  ),
                );
              },
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final note = notes[index];
            final indentLevel = preserveIndents
                ? note.indentLevel.clamp(0, _kBoardMaxIndentLevel).toInt()
                : 0;
            final indentOffset = indentLevel * _kBoardIndentWidth;
            return Dismissible(
              key: ValueKey('board-note-${note.id}'),
              direction: recycleBin
                  ? DismissDirection.horizontal
                  : DismissDirection.endToStart,
              confirmDismiss: (_) => recycleBin
                  ? Future.value(true)
                  : _confirmDeleteNote(context, note),
              onDismissed: (direction) {
                if (!recycleBin) {
                  onDeleteNote(note);
                  return;
                }
                if (direction == DismissDirection.startToEnd) {
                  onRestoreNote(note);
                } else {
                  onDiscardNote(note);
                }
              },
              background: recycleBin
                  ? _SwipeRestoreBackground(
                      isLast: index == notes.length - 1,
                      leftInset: indentOffset,
                    )
                  : const SizedBox.shrink(),
              secondaryBackground: recycleBin
                  ? _SwipeDiscardBackground(
                      isLast: index == notes.length - 1,
                      leftInset: indentOffset,
                    )
                  : _SwipeDeleteBackground(
                      isLast: index == notes.length - 1,
                      leftInset: indentOffset,
                    ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: indentOffset,
                  bottom: index == notes.length - 1 ? 0 : 10,
                ),
                child: _MaybeReorderableCard(
                  index: index,
                  enabled: canReorder,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BoardNoteCard(
                        note: note,
                        isMinimized: isMinimized,
                        onTap: () => onTapNote(note),
                        onMove: canMoveNotes ? () => onMoveNote(note) : null,
                        onOutdent: onIndentNote == null || indentLevel <= 0
                            ? null
                            : () => onIndentNote!(note, -1),
                        onIndent:
                            onIndentNote == null ||
                                indentLevel >= _kBoardMaxIndentLevel
                            ? null
                            : () => onIndentNote!(note, 1),
                      ),
                      if (showInsertBars)
                        _BoardInsertRail(
                          selected: selectedInsertAfterNoteId == note.id,
                          enabled: true,
                          onTap: () => onToggleInsertAfterNote!(note),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MaybeReorderableCard extends StatelessWidget {
  final int index;
  final bool enabled;
  final Widget child;

  const _MaybeReorderableCard({
    required this.index,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ReorderableDelayedDragStartListener(index: index, child: child);
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  final bool isLast;
  final double leftInset;

  const _SwipeDeleteBackground({required this.isLast, required this.leftInset});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: EdgeInsets.only(left: leftInset, bottom: isLast ? 0 : 10),
      child: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(
            colors.cardStyle == CardStyles.minimal ? 10 : 18,
          ),
        ),
        child: const Icon(
          CupertinoIcons.check_mark_circled_solid,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _SwipeRestoreBackground extends StatelessWidget {
  final bool isLast;
  final double leftInset;

  const _SwipeRestoreBackground({
    required this.isLast,
    required this.leftInset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: EdgeInsets.only(left: leftInset, bottom: isLast ? 0 : 10),
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 22),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(
            colors.cardStyle == CardStyles.minimal ? 10 : 18,
          ),
        ),
        child: const Icon(
          CupertinoIcons.arrow_uturn_left,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _SwipeDiscardBackground extends StatelessWidget {
  final bool isLast;
  final double leftInset;

  const _SwipeDiscardBackground({
    required this.isLast,
    required this.leftInset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Padding(
      padding: EdgeInsets.only(left: leftInset, bottom: isLast ? 0 : 10),
      child: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(
            colors.cardStyle == CardStyles.minimal ? 10 : 18,
          ),
        ),
        child: const Icon(
          CupertinoIcons.trash_fill,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _BoardInsertRail extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _BoardInsertRail({
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final activeColor = selected ? colors.accent : colors.textSecondary;
    return Tooltip(
      message: selected ? 'Clear insert point' : 'Insert after this note',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 18,
          width: 108,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: 60,
                    height: selected ? 7 : 5,
                    decoration: BoxDecoration(
                      color: activeColor.withValues(
                        alpha: selected ? 0.95 : (enabled ? 0.28 : 0.12),
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? colors.card.withValues(alpha: 0.9)
                            : colors.textSecondary.withValues(alpha: 0.16),
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: colors.accent.withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : const [],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 120),
                    child: selected
                        ? Padding(
                            key: const ValueKey('insert-label'),
                            padding: const EdgeInsets.only(left: 5),
                            child: Text(
                              'insert',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.accent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('insert-label-empty'),
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

class _BoardNoteCard extends StatelessWidget {
  final Note note;
  final bool isMinimized;
  final VoidCallback onTap;
  final VoidCallback? onMove;
  final VoidCallback? onOutdent;
  final VoidCallback? onIndent;

  const _BoardNoteCard({
    required this.note,
    required this.isMinimized,
    required this.onTap,
    required this.onMove,
    required this.onOutdent,
    required this.onIndent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final theme = Theme.of(context);
    final accent = note.colorTag == null
        ? colors.accent
        : ByepasserTheme.accentPalette[note.colorTag!.clamp(0, 7)];
    final radius = colors.cardStyle == CardStyles.minimal ? 10.0 : 18.0;
    final cardRadius = BorderRadius.circular(radius);
    final title = note.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final attachmentPaths = note.attachmentPaths;
    final hasAttachments = attachmentPaths.isNotEmpty;

    return Container(
      decoration: colors.cardDecoration(radius: radius),
      child: ClipRRect(
        borderRadius: cardRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: isMinimized ? _kBoardCollapsedCardHeight : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                        child: Row(
                          children: [
                            Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.34),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    note.isSteamMode
                                        ? CupertinoIcons.wind
                                        : CupertinoIcons.text_bubble,
                                    size: 16,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    note.isSteamMode ? 'Puff' : 'Hum',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LiveCountdown(
                                expiresAt: note.expiresAt,
                                showSeconds: note.remaining.inHours < 1,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _BoardCardActionCapsule(
                              actions: [
                                _BoardCardAction(
                                  tooltip: 'Outdent',
                                  icon: CupertinoIcons.decrease_indent,
                                  onPressed: onOutdent,
                                ),
                                _BoardCardAction(
                                  tooltip: 'Indent',
                                  icon: CupertinoIcons.increase_indent,
                                  onPressed: onIndent,
                                ),
                                _BoardCardAction(
                                  tooltip: 'Move to board',
                                  icon: CupertinoIcons.square_stack_3d_up,
                                  onPressed: onMove,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          isMinimized ? 8 : 12,
                          14,
                          isMinimized ? 10 : 18,
                        ),
                        child: isMinimized
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      hasTitle ? title : note.body.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  if (hasAttachments) ...[
                                    const SizedBox(width: 8),
                                    _BoardAttachmentThumb(
                                      path: attachmentPaths.first,
                                    ),
                                  ],
                                ],
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (hasTitle) ...[
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              color: colors.textPrimary,
                                              fontWeight: FontWeight.w600,
                                              height: 1.22,
                                            ),
                                      ),
                                      if (note.body.trim().isNotEmpty ||
                                          hasAttachments)
                                        const SizedBox(height: 10),
                                    ],
                                    if (note.body.trim().isNotEmpty) ...[
                                      Text(
                                        note.body.trim(),
                                        maxLines: 12,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              color: colors.textPrimary,
                                              height: 1.28,
                                            ),
                                      ),
                                      if (hasAttachments)
                                        const SizedBox(height: 12),
                                    ],
                                    if (hasAttachments)
                                      _BoardFirstAttachmentPreview(
                                        path: attachmentPaths.first,
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _CardEdgeTapGuard(height: 10),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _CardEdgeTapGuard(height: isMinimized ? 10 : 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardEdgeTapGuard extends StatelessWidget {
  final double height;

  const _CardEdgeTapGuard({required this.height});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: SizedBox(height: height),
    );
  }
}

class _BoardCardAction {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _BoardCardAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
}

class _BoardCardActionCapsule extends StatelessWidget {
  final List<_BoardCardAction> actions;

  const _BoardCardActionCapsule({required this.actions});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: colors.isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.textPrimary.withValues(
            alpha: colors.isDark ? 0.2 : 0.16,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _BoardCardActionButton(action: actions[i]),
            if (i != actions.length - 1)
              Container(
                width: 1,
                height: 22,
                color: colors.textPrimary.withValues(alpha: 0.1),
              ),
          ],
        ],
      ),
    );
  }
}

class _BoardCardActionButton extends StatelessWidget {
  final _BoardCardAction action;

  const _BoardCardActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final enabled = action.onPressed != null;
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        tooltip: action.tooltip,
        onPressed: action.onPressed ?? () {},
        padding: EdgeInsets.zero,
        iconSize: 19,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: enabled
              ? colors.textPrimary.withValues(alpha: 0.78)
              : colors.textSecondary.withValues(alpha: 0.38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size.square(40),
        ),
        icon: Icon(action.icon),
      ),
    );
  }
}

Future<Board?> _showMoveToBoardSelector(
  BuildContext context,
  List<Board> boards,
  String currentBoardId,
) {
  final colors = Theme.of(context).extension<ByepasserColors>()!;
  if (boards.length <= 1) {
    return Future.value(null);
  }
  return showCupertinoModalPopup<Board>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: const Text('Move to board'),
      actions: [
        for (final board in boards)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(board),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (board.id == currentBoardId) ...[
                  Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 17,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    board.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: const Text('Cancel'),
      ),
    ),
  );
}

Future<bool?> _showMoveConfirmationDialog(BuildContext context, Board target) {
  return showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Poof'),
      content: Text('Switch to ${target.title}?'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Stay here'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Switch'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmDeleteNote(BuildContext context, Note note) async {
  final preview = note.title?.trim().isNotEmpty == true
      ? note.title!.trim()
      : note.body.trim();
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Completed your task?'),
      content: Text(
        preview.isEmpty
            ? 'You can restore it from Recycle.'
            : '"${preview.length > 72 ? '${preview.substring(0, 69)}...' : preview}"\n\nYou can restore it from Recycle.',
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Complete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool?> _confirmDiscardCompletedTasks(
  BuildContext context,
  int completedCount,
) {
  if (completedCount <= 0) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Recycle'),
        content: const Text('No completed tasks to discard.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  final label = completedCount == 1 ? 'completed task' : 'completed tasks';
  return showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Discard completed tasks?'),
      content: Text(
        'This will permanently remove $completedCount $label from Recycle.',
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
}

String _renumberCrossReferenceBody(int pinNumber, String body) {
  final text = body.trim();
  final withoutExistingNumber = text.replaceFirst(RegExp(r'^\d+\.\s*'), '');
  return withoutExistingNumber.isEmpty
      ? '$pinNumber.'
      : '$pinNumber. $withoutExistingNumber';
}

class _BoardFirstAttachmentPreview extends ConsumerWidget {
  final String path;

  const _BoardFirstAttachmentPreview({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final file = ImageFileStore.resolve(path);

    Future<void> editImage() async {
      final annotated = await openImageAnnotator(context, path);
      if (annotated) {
        ref.invalidate(notesProvider);
      }
    }

    Future<void> shareImage() async {
      if (!file.existsSync()) {
        _showAttachmentMessage(context, 'Image file is missing');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Byepasser image'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              Positioned.fill(
                child: _BoardAttachmentImage(
                  path: path,
                  colors: colors,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: _AttachmentImageActions(
                  colors: colors,
                  onEdit: editImage,
                  onShare: shareImage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAttachmentMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
  );
}

class _AttachmentImageActions extends StatelessWidget {
  final ByepasserColors colors;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  const _AttachmentImageActions({
    required this.colors,
    required this.onEdit,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentImageActionButton(
            tooltip: 'Edit',
            icon: CupertinoIcons.pencil,
            onPressed: onEdit,
          ),
          Container(
            width: 1,
            height: 20,
            color: Colors.white.withValues(alpha: 0.22),
          ),
          _AttachmentImageActionButton(
            tooltip: 'Share',
            icon: CupertinoIcons.share,
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

class _AttachmentImageActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _AttachmentImageActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: CupertinoButton(
        onPressed: onPressed,
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        child: Icon(
          icon,
          size: 20,
          color: Colors.white.withValues(alpha: onPressed == null ? 0.35 : 1),
        ),
      ),
    );
  }
}

class _BoardAttachmentThumb extends StatelessWidget {
  final String path;

  const _BoardAttachmentThumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: SizedBox.square(
          dimension: 42,
          child: _BoardAttachmentImage(path: path, colors: colors),
        ),
      ),
    );
  }
}

class _BoardAttachmentImage extends StatelessWidget {
  final String path;
  final ByepasserColors colors;
  final BoxFit fit;

  const _BoardAttachmentImage({
    required this.path,
    required this.colors,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final file = ImageFileStore.resolve(path);
    if (!file.existsSync()) {
      return _BoardAttachmentFallback(colors: colors);
    }
    return Image.file(
      file,
      fit: fit,
      errorBuilder: (_, _, _) => _BoardAttachmentFallback(colors: colors),
    );
  }
}

class _BoardAttachmentFallback extends StatelessWidget {
  final ByepasserColors colors;

  const _BoardAttachmentFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.cardAlt,
      alignment: Alignment.center,
      child: Icon(CupertinoIcons.photo, color: colors.textSecondary),
    );
  }
}

class _BoardPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _BoardPanel({required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return Container(
      padding: padding,
      decoration: colors.cardDecoration(),
      child: child,
    );
  }
}

/// Pragmatic facade for direct Hive access from the screen.
class _SimpleStoreFacade {
  Box<Note> get notesBox => Hive.box<Note>('notes');
  Box<AppSettings> get settingsBox => Hive.box<AppSettings>('settings');

  AppSettings get settings => settingsBox.get('user') ?? AppSettings.defaults();

  Future<void> selectBoard(String boardId) async {
    await settingsBox.put('user', settings.copyWith(selectedBoardId: boardId));
  }

  Future<int> sweepExpiredNotes() async {
    final now = DateTime.now();
    final toRemove = notesBox.values
        .where((n) => !n.isDeleted && now.isAfter(n.expiresAt))
        .toList();
    for (final note in toRemove) {
      await notesBox.delete(note.id);
    }
    return toRemove.length;
  }

  Future<Note> updateNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<void> moveNoteToBoard(Note note, String boardId) async {
    final targetNotes = notesBox.values
        .where(
          (candidate) =>
              candidate.isVisibleBoardNote &&
              candidate.boardId == boardId &&
              candidate.id != note.id,
        )
        .toList();
    targetNotes.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });

    await updateNote(
      note.copyWith(boardId: boardId, orderIndex: 0, indentLevel: 0),
    );
    for (var i = 0; i < targetNotes.length; i++) {
      await updateNote(targetNotes[i].copyWith(orderIndex: i + 1));
    }
  }

  Future<void> recycleNote(Note note) async {
    final recycledNotes =
        notesBox.values
            .where(
              (candidate) =>
                  candidate.isDeleted &&
                  !candidate.isImageCrossReference &&
                  candidate.id != note.id,
            )
            .toList()
          ..sort((a, b) {
            final orderCompare = a.orderIndex.compareTo(b.orderIndex);
            if (orderCompare != 0) return orderCompare;
            final aDeleted =
                a.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDeleted =
                b.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDeleted.compareTo(aDeleted);
          });

    await updateNote(
      note.copyWith(deletedAt: DateTime.now(), orderIndex: 0, indentLevel: 0),
    );
    for (var i = 0; i < recycledNotes.length; i++) {
      await updateNote(recycledNotes[i].copyWith(orderIndex: i + 1));
    }
    final imagePath = note.crossReferenceImagePath;
    if (imagePath != null) {
      await renumberCrossReferenceNotes(imagePath);
    }
  }

  Future<void> restoreNote(Note note, String activeBoardId) async {
    final targetNotes =
        notesBox.values
            .where(
              (candidate) =>
                  candidate.isVisibleBoardNote &&
                  candidate.boardId == activeBoardId &&
                  candidate.id != note.id,
            )
            .toList()
          ..sort((a, b) {
            final orderCompare = a.orderIndex.compareTo(b.orderIndex);
            if (orderCompare != 0) return orderCompare;
            return a.compareExpiry(b);
          });

    await updateNote(
      note.copyWith(
        boardId: activeBoardId,
        deletedAt: null,
        orderIndex: 0,
        indentLevel: 0,
      ),
    );
    for (var i = 0; i < targetNotes.length; i++) {
      await updateNote(targetNotes[i].copyWith(orderIndex: i + 1));
    }
    final imagePath = note.crossReferenceImagePath;
    if (imagePath != null) {
      await renumberCrossReferenceNotes(imagePath);
    }
  }

  Future<void> deleteNote(String id) async {
    final note = notesBox.get(id);
    if (note == null) return;
    await recycleNote(note);
  }

  Future<void> discardRecycledNotes() async {
    final recycled = notesBox.values
        .where((note) => note.isDeleted && !note.isImageCrossReference)
        .toList();
    for (final note in recycled) {
      await notesBox.delete(note.id);
    }
  }

  Future<void> discardRecycledNote(String id) async {
    final note = notesBox.get(id);
    if (note == null || !note.isDeleted || note.isImageCrossReference) return;
    await notesBox.delete(id);
  }

  Future<void> renumberCrossReferenceNotes(String imagePath) async {
    final references =
        notesBox.values
            .where(
              (note) =>
                  !note.isDeleted && note.crossReferenceImagePath == imagePath,
            )
            .toList()
          ..sort((a, b) {
            final orderCompare = a.orderIndex.compareTo(b.orderIndex);
            if (orderCompare != 0) return orderCompare;
            final pinCompare = (a.crossReferencePinNumber ?? 0).compareTo(
              b.crossReferencePinNumber ?? 0,
            );
            if (pinCompare != 0) return pinCompare;
            return a.createdAt.compareTo(b.createdAt);
          });

    for (var i = 0; i < references.length; i++) {
      final number = i + 1;
      await updateNote(
        references[i].copyWith(
          title: null,
          body: _renumberCrossReferenceBody(number, references[i].body),
          crossReferencePinNumber: number,
          orderIndex: references[i].orderIndex,
        ),
      );
    }
  }

  List<Note> getAllNotesSorted() {
    final list = notesBox.values
        .where((note) => note.isVisibleBoardNote)
        .toList();
    list.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });
    return list;
  }
}
