import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

import '../models/note.dart';
import '../models/app_settings.dart';
import '../models/board.dart';
import '../services/notification_service.dart';
import '../services/haptics_service.dart';

/// Boxes (overridden at startup)
final notesBoxProvider = Provider<Box<Note>>((ref) {
  throw UnimplementedError('Override in main');
});

final settingsBoxProvider = Provider<Box<AppSettings>>((ref) {
  throw UnimplementedError('Override in main');
});

final boardsBoxProvider = Provider<Box<Board>>((ref) {
  throw UnimplementedError('Override in main');
});

/// Live settings read from box
final settingsProvider = Provider<AppSettings>((ref) {
  final box = ref.watch(settingsBoxProvider);
  return box.get('user') ?? AppSettings.defaults();
});

/// Notes list read directly from the authoritative Hive box.
/// Callers that mutate the box should call ref.invalidate(notesProvider)
/// (and possibly force a local rebuild for in-place changes) so the UI reflects the latest data.
final notesProvider = Provider<List<Note>>((ref) {
  final box = ref.watch(notesBoxProvider);
  final list = box.values.toList();
  list.sort((a, b) => a.compareExpiry(b));
  return list;
});

final boardsProvider = Provider<List<Board>>((ref) {
  final box = ref.watch(boardsBoxProvider);
  final list = box.values.toList();
  list.sort((a, b) {
    final orderCompare = a.orderIndex.compareTo(b.orderIndex);
    if (orderCompare != 0) return orderCompare;
    return a.createdAt.compareTo(b.createdAt);
  });
  return list;
});

final selectedBoardProvider = Provider<Board>((ref) {
  final settings = ref.watch(settingsProvider);
  final boards = ref.watch(boardsProvider);
  return boards.firstWhere(
    (board) => board.id == settings.selectedBoardId,
    orElse: () => boards.isEmpty ? Board.defaults() : boards.first,
  );
});

final currentBoardNotesProvider = Provider<List<Note>>((ref) {
  final selected = ref.watch(selectedBoardProvider);
  final notes = ref.watch(notesProvider);
  final list = notes
      .where((note) => note.boardId == selected.id && note.isVisibleBoardNote)
      .toList();
  list.sort((a, b) {
    final orderCompare = a.orderIndex.compareTo(b.orderIndex);
    if (orderCompare != 0) return orderCompare;
    return a.compareExpiry(b);
  });
  return list;
});

final recycledNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider);
  final list = notes
      .where((note) => note.isDeleted && !note.isImageCrossReference)
      .toList();
  list.sort((a, b) {
    final orderCompare = a.orderIndex.compareTo(b.orderIndex);
    if (orderCompare != 0) return orderCompare;
    final aDeleted = a.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDeleted = b.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDeleted.compareTo(aDeleted);
  });
  return list;
});

/// Derived lists (recomputed when notesProvider changes)
final dyingSoonNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(currentBoardNotesProvider);
  final now = DateTime.now();
  final cutoff = now.add(const Duration(hours: 6));
  final list = notes
      .where((n) => n.expiresAt.isBefore(cutoff) && !now.isAfter(n.expiresAt))
      .toList();
  list.sort((a, b) => a.compareExpiry(b));
  return list;
});

final regularNotesProvider = Provider<List<Note>>((ref) {
  final all = ref.watch(currentBoardNotesProvider);
  final dying = ref.watch(dyingSoonNotesProvider).map((n) => n.id).toSet();
  return all.where((n) => !dying.contains(n.id)).toList();
});

final noteCountProvider = Provider<int>(
  (ref) => ref.watch(currentBoardNotesProvider).length,
);

final recycledNoteCountProvider = Provider<int>(
  (ref) => ref.watch(recycledNotesProvider).length,
);

final boardInsertAfterNoteIdProvider = StateProvider<String?>((ref) => null);

/// Services
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError('Override in main');
});

final hapticsProvider = Provider<HapticsService>((ref) => HapticsService(ref));
