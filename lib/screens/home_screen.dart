import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../models/board.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
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

/// Home now behaves like the Statusgy item-detail personal notes tab:
/// a private board with header controls, reorderable cards, quick note creation,
/// explicit indent/outdent controls, and card minimizing.
class HomeScreen extends HookConsumerWidget {
  final bool recycleBin;

  const HomeScreen({super.key, this.recycleBin = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsMinimized = useState(false);

    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final selectedBoard = ref.watch(selectedBoardProvider);
    final boards = ref.watch(boardsProvider);
    final orderedNotes = recycleBin
        ? ref.watch(recycledNotesProvider)
        : ref.watch(currentBoardNotesProvider);

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
                onDeleteNote: (note) => _deleteNote(ref, store, note, haptics),
                onRestoreNote: (note) =>
                    _restoreNote(ref, store, note, selectedBoard.id, haptics),
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
                onIndentNote: (note, delta) =>
                    _adjustIndent(ref, store, note, delta, haptics),
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
  final VoidCallback? onOpenBoards;
  final VoidCallback? onToggleMinimized;

  const _BoardCapsuleTitle({
    required this.title,
    required this.icon,
    required this.count,
    required this.isMinimized,
    required this.onOpenBoards,
    required this.onToggleMinimized,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return GestureDetector(
      onTap: onOpenBoards,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: colors.cardDecoration(color: colors.card, radius: 999),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: colors.accent),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
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
            const SizedBox(width: 7),
            Text(
              '$count${isMinimized && count > 0 ? ' min' : ''}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
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
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: onPressed == null
            ? colors.textSecondary.withValues(alpha: 0.35)
            : colors.accent,
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
  final bool canMoveNotes;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<Note> onTapNote;
  final ValueChanged<Note> onDeleteNote;
  final ValueChanged<Note> onRestoreNote;
  final ValueChanged<Note> onMoveNote;
  final void Function(Note note, int delta) onIndentNote;

  const _BoardNoteList({
    required this.notes,
    required this.recycleBin,
    required this.isMinimized,
    required this.canMoveNotes,
    required this.onReorder,
    required this.onTapNote,
    required this.onDeleteNote,
    required this.onRestoreNote,
    required this.onMoveNote,
    required this.onIndentNote,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
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
      onReorder: onReorder,
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
        final indentLevel = note.indentLevel
            .clamp(0, _kBoardMaxIndentLevel)
            .toInt();
        final indentOffset = indentLevel * _kBoardIndentWidth;
        return Dismissible(
          key: ValueKey('board-note-${note.id}'),
          direction: recycleBin
              ? DismissDirection.startToEnd
              : DismissDirection.endToStart,
          confirmDismiss: (_) => recycleBin
              ? Future.value(true)
              : _confirmDeleteNote(context, note),
          onDismissed: (_) =>
              recycleBin ? onRestoreNote(note) : onDeleteNote(note),
          background: recycleBin
              ? _SwipeRestoreBackground(
                  isLast: index == notes.length - 1,
                  leftInset: indentOffset,
                )
              : const SizedBox.shrink(),
          secondaryBackground: _SwipeDeleteBackground(
            isLast: index == notes.length - 1,
            leftInset: indentOffset,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: indentOffset,
              bottom: index == notes.length - 1 ? 0 : 10,
            ),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _BoardNoteCard(
                      note: note,
                      isMinimized: isMinimized,
                      onTap: () => onTapNote(note),
                      onDelete: recycleBin ? null : () => onDeleteNote(note),
                      onMove: canMoveNotes ? () => onMoveNote(note) : null,
                      onOutdent: indentLevel <= 0
                          ? null
                          : () => onIndentNote(note, -1),
                      onIndent: indentLevel >= _kBoardMaxIndentLevel
                          ? null
                          : () => onIndentNote(note, 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

class _BoardNoteCard extends StatelessWidget {
  final Note note;
  final bool isMinimized;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onMove;
  final VoidCallback? onOutdent;
  final VoidCallback? onIndent;

  const _BoardNoteCard({
    required this.note,
    required this.isMinimized,
    required this.onTap,
    required this.onDelete,
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
                                color: accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    note.isSteamMode
                                        ? CupertinoIcons.wind
                                        : CupertinoIcons.square_list,
                                    size: 16,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    note.isSteamMode ? 'Puff' : 'Note',
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
                            _BoardCardActionButton(
                              tooltip: 'Outdent',
                              icon: CupertinoIcons.decrease_indent,
                              onPressed: onOutdent,
                            ),
                            _BoardCardActionButton(
                              tooltip: 'Indent',
                              icon: CupertinoIcons.increase_indent,
                              onPressed: onIndent,
                            ),
                            _BoardCardActionButton(
                              tooltip: 'Move to board',
                              icon: CupertinoIcons.square_stack_3d_up,
                              onPressed: onMove,
                            ),
                            _BoardCardActionButton(
                              tooltip: 'Complete',
                              icon: CupertinoIcons.check_mark_circled,
                              onPressed: onDelete,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardCardActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _BoardCardActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox.square(
      dimension: 36,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: colors.textSecondary,
          disabledForegroundColor: colors.textSecondary.withValues(alpha: 0.28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size.square(36),
        ),
        icon: Icon(icon),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: () async {
          final annotated = await openImageAnnotator(context, path);
          if (annotated) {
            ref.invalidate(notesProvider);
          }
        },
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _BoardAttachmentImage(path: path, colors: colors),
        ),
      ),
    );
  }
}

class _BoardAttachmentThumb extends ConsumerWidget {
  final String path;

  const _BoardAttachmentThumb({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        onTap: () async {
          final annotated = await openImageAnnotator(context, path);
          if (annotated) {
            ref.invalidate(notesProvider);
          }
        },
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

  const _BoardAttachmentImage({required this.path, required this.colors});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return _BoardAttachmentFallback(colors: colors);
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
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
