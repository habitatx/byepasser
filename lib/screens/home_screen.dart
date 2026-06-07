import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
import '../theme/byepasser_theme.dart';
import 'note_editor_screen.dart';

/// The main board screen: simple stacked card outliner with drag reorder,
/// swipe indent/outdent, vertical resize handles, collapse toggle, and
/// a rearrangeable "Add Puff" card.
class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompact = useState(false); // compact one-liners vs medium cards
    final forceRebuild = useState(0);

    final settings = ref.watch(settingsProvider);
    final colors = Theme.of(context).extension<ByepasserColors>()!;

    final store = useMemoized(() => _getOrCreateStore(), const []);
    final haptics = ref.read(hapticsProvider);

    final orderedNotes = store.getAllNotesSorted();

    useEffect(() {
      _initialSweepAndLoad(ref, store, settings);
      return null;
    }, const []);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Byepasser'),
        border: null,
        // The only non-card element: toggle between compact (one-liner) and medium card size
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            isCompact.value = !isCompact.value;
            haptics.selection();
          },
          child: Icon(
            isCompact.value
                ? CupertinoIcons.list_bullet
                : CupertinoIcons.rectangle_grid_1x2,
            size: 20,
            color: colors.accent,
          ),
        ),
      ),
      child: SafeArea(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
          itemCount: orderedNotes.length + 1, // real notes + the Add Puff rearrangeable
          onReorder: (oldIndex, newIndex) =>
              _onReorder(ref, store, orderedNotes, oldIndex, newIndex, haptics),
          itemBuilder: (context, index) {
            if (index == orderedNotes.length) {
              // The Add Puff card is a rearrangeable item.
              // Drag it to any position in the stack, then tap it to insert a new puff there.
              return _AddPuffCard(
                key: const ValueKey('add_puff'),
                isCompact: isCompact.value,
                onTap: () => _addPuffAtPosition(
                  ref,
                  store,
                  orderedNotes,
                  orderedNotes.length,
                  haptics,
                ),
              );
            }

            final note = orderedNotes[index];
            return _StackedNoteCard(
              key: ValueKey(note.id),
              note: note,
              isCompact: isCompact.value,
              onTap: () => _openNoteForEdit(context, note, store, ref),
              onVerticalResize: (newHeight) {
                final updated = note.copyWith(cardHeight: newHeight);
                store.updateNote(updated);
                ref.invalidate(notesProvider);
                forceRebuild.value++;
              },
              onSwipeIndent: (delta) {
                _adjustIndent(ref, store, orderedNotes, index, delta);
              },
            );
          },
        ),
      ),
    );
  }

  // ===== Helpers for the new stacked/rearrangeable outliner =====

  void _onReorder(
    WidgetRef ref,
    _SimpleStoreFacade store,
    List<Note> ordered,
    int oldIndex,
    int newIndex,
    HapticsService h,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;

    final isAddMove = oldIndex == ordered.length;

    if (isAddMove) {
      int insertPos = newIndex;
      if (insertPos > ordered.length) insertPos = ordered.length;
      _addPuffAtPosition(ref, store, ordered, insertPos, h);
      return;
    }

    final List<Note> reordered = List.from(ordered);
    final Note moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    for (int i = 0; i < reordered.length; i++) {
      if (reordered[i].orderIndex != i) {
        store.updateNote(reordered[i].copyWith(orderIndex: i));
      }
    }
    ref.invalidate(notesProvider);
    h.light();
  }

  void _addPuffAtPosition(
    WidgetRef ref,
    _SimpleStoreFacade store,
    List<Note> ordered,
    int position,
    HapticsService h,
  ) {
    final int insertIndex = position.clamp(0, ordered.length);
    final Note? prior = insertIndex > 0 ? ordered[insertIndex - 1] : null;
    final int newIndent = prior?.indentLevel ?? 0;
    final int life = store.settings.defaultSteamLifetimeMinutes;

    final newPuff = Note.create(
      body: '',
      lifetimeMinutes: life,
      isSteamMode: true,
      indentLevel: newIndent,
    );

    final List<Note> newOrder = List.from(ordered)..insert(insertIndex, newPuff);
    for (int i = 0; i < newOrder.length; i++) {
      store.updateNote(newOrder[i].copyWith(orderIndex: i));
    }
    ref.invalidate(notesProvider);
    h.medium();
  }

  void _adjustIndent(
    WidgetRef ref,
    _SimpleStoreFacade store,
    List<Note> ordered,
    int index,
    int delta,
  ) {
    final note = ordered[index];
    final Note? prior = index > 0 ? ordered[index - 1] : null;
    int target = note.indentLevel + delta;
    if (delta > 0 && prior != null) {
      target = (prior.indentLevel + 1).clamp(0, 6);
    } else {
      target = target.clamp(0, 6);
    }
    if (target != note.indentLevel) {
      store.updateNote(note.copyWith(indentLevel: target));
      ref.invalidate(notesProvider);
    }
  }

  Future<void> _openNoteForEdit(
    BuildContext context,
    Note note,
    _SimpleStoreFacade store,
    WidgetRef ref,
  ) async {
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => NoteEditorScreen(existingNote: note),
      ),
    );
    ref.invalidate(notesProvider);
  }

  Future<void> _initialSweepAndLoad(
    WidgetRef ref,
    _SimpleStoreFacade store,
    AppSettings settings,
  ) async {
    await store.sweepExpiredNotes();
    ref.invalidate(notesProvider);
  }

  _SimpleStoreFacade _getOrCreateStore() {
    return _SimpleStoreFacade();
  }
}

// ===== New card widgets for the stacked system =====

class _StackedNoteCard extends StatelessWidget {
  final Note note;
  final bool isCompact;
  final VoidCallback onTap;
  final ValueChanged<double> onVerticalResize;
  final ValueChanged<int> onSwipeIndent;

  const _StackedNoteCard({
    required super.key,
    required this.note,
    required this.isCompact,
    required this.onTap,
    required this.onVerticalResize,
    required this.onSwipeIndent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    final h = (note.cardHeight ?? (isCompact ? 42.0 : 105.0)).clamp(
        isCompact ? 36.0 : 70.0, isCompact ? 70.0 : 300.0);

    return GestureDetector(
      onTap: onTap,
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 250) onSwipeIndent(1);
        if ((d.primaryVelocity ?? 0) < -250) onSwipeIndent(-1);
      },
      child: Container(
        height: h,
        margin: EdgeInsets.only(
            left: (note.indentLevel * 18.0).clamp(0.0, 110.0), bottom: 6),
        decoration: colors.cardDecoration(isSteam: note.isSteamMode),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.displayTitle,
                    maxLines: isCompact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!isCompact && note.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        note.body.split('\n').first.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            if (!isCompact)
              Positioned(
                right: 6,
                bottom: 6,
                child: GestureDetector(
                  onVerticalDragUpdate: (d) {
                    final nh = (h + d.delta.dy).clamp(70.0, 300.0);
                    onVerticalResize(nh);
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colors.textSecondary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(CupertinoIcons.line_horizontal_3, size: 11),
                  ),
                ),
              ),
            if (note.isSteamMode)
              const Positioned(
                top: 6,
                right: 8,
                child: Text('PUFF',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddPuffCard extends StatelessWidget {
  final bool isCompact;
  final VoidCallback onTap;

  const _AddPuffCard({
    required super.key,
    required this.isCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isCompact ? 42.0 : 68.0,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border.all(
              color: colors.accent.withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: colors.card.withValues(alpha: 0.5),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.add, color: colors.accent),
              const SizedBox(width: 6),
              Text('Add Puff',
                  style: TextStyle(
                      color: colors.accent, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pragmatic facade for direct Hive access from the screen (talks to boxes opened in main).
class _SimpleStoreFacade {
  Box<Note> get notesBox => Hive.box<Note>('notes');
  Box<AppSettings> get settingsBox => Hive.box<AppSettings>('settings');

  AppSettings get settings => settingsBox.get('user') ?? AppSettings.defaults();

  Future<int> sweepExpiredNotes() async {
    final now = DateTime.now();
    final toRemove = notesBox.values.where((n) => now.isAfter(n.expiresAt)).toList();
    for (final n in toRemove) {
      await notesBox.delete(n.id);
    }
    return toRemove.length;
  }

  Future<Note> addNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<Note> updateNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<void> deleteNote(String id) async => notesBox.delete(id);

  Future<void> deleteAllNotes() async => notesBox.clear();

  List<Note> getAllNotesSorted() {
    final list = notesBox.values.toList();
    list.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });
    return list;
  }

  int get noteCount => notesBox.length;

  Future<void> updateSettings(AppSettings newSettings) async {
    await settingsBox.put('user', newSettings);
  }
}
