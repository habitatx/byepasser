import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../models/app_settings.dart';
import '../models/board.dart';

/// Central local storage manager using Hive.
/// All data stays 100% on device.
class HiveStore {
  static const String notesBoxName = 'notes';
  static const String settingsBoxName = 'settings';
  static const String boardsBoxName = 'boards';

  late final Box<Note> notesBox;
  late final Box<AppSettings> settingsBox;
  late final Box<Board> boardsBox;

  HiveStore._();

  static Future<HiveStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);

    // Register manual adapters (no build_runner required)
    if (!Hive.isAdapterRegistered(noteTypeId)) {
      Hive.registerAdapter(NoteAdapter());
    }
    if (!Hive.isAdapterRegistered(settingsTypeId)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(boardTypeId)) {
      Hive.registerAdapter(BoardAdapter());
    }

    final store = HiveStore._();

    store.notesBox = await Hive.openBox<Note>(notesBoxName);
    store.settingsBox = await Hive.openBox<AppSettings>(settingsBoxName);
    store.boardsBox = await Hive.openBox<Board>(boardsBoxName);

    // Ensure we have at least default settings
    if (store.settingsBox.isEmpty) {
      await store.settingsBox.put('user', AppSettings.defaults());
    }
    if (!store.boardsBox.containsKey(defaultBoardId)) {
      await store.boardsBox.put(defaultBoardId, Board.defaults());
    }
    await store._ensureBoardState();

    return store;
  }

  AppSettings get settings => settingsBox.get('user') ?? AppSettings.defaults();

  Future<void> updateSettings(AppSettings newSettings) async {
    await settingsBox.put('user', newSettings);
  }

  Future<void> _ensureBoardState() async {
    final boards = getAllBoardsSorted();
    if (boards.isEmpty) {
      await boardsBox.put(defaultBoardId, Board.defaults());
    }

    final currentSettings = settings;
    if (!boardsBox.containsKey(currentSettings.selectedBoardId)) {
      await updateSettings(
        currentSettings.copyWith(selectedBoardId: defaultBoardId),
      );
    }

    for (final note in notesBox.values) {
      if (!boardsBox.containsKey(note.boardId)) {
        await notesBox.put(note.id, note.copyWith(boardId: defaultBoardId));
      }
    }
  }

  /// Called on launch (and periodically). Deletes notes past their expiresAt.
  /// Returns number of notes removed.
  Future<int> sweepExpiredNotes() async {
    final now = DateTime.now();
    final toDelete = <Note>[];

    for (final note in notesBox.values) {
      if (!note.isDeleted && now.isAfter(note.expiresAt)) {
        toDelete.add(note);
      }
    }

    for (final note in toDelete) {
      await notesBox.delete(note.id);
    }
    return toDelete.length;
  }

  Future<Note> addNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<Note> updateNote(Note note) async {
    await notesBox.put(note.id, note);
    return note;
  }

  Future<void> deleteNote(String id) async {
    final note = notesBox.get(id);
    if (note == null) return;
    await notesBox.put(id, note.copyWith(deletedAt: DateTime.now()));
  }

  Future<void> deleteAllNotes() async {
    await notesBox.clear();
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

  List<Note> getAllNotesSorted() {
    final notes = notesBox.values
        .where((note) => note.isVisibleBoardNote)
        .toList();
    // Primary sort by user orderIndex for the new stacked/reorderable UI.
    // Fallback to expiry for any notes without explicit order yet.
    notes.sort((a, b) {
      final orderCompare = a.orderIndex.compareTo(b.orderIndex);
      if (orderCompare != 0) return orderCompare;
      return a.compareExpiry(b);
    });
    return notes;
  }

  List<Note> getDyingSoonNotes({
    Duration threshold = const Duration(hours: 6),
  }) {
    final now = DateTime.now();
    final cutoff = now.add(threshold);
    return notesBox.values
        .where(
          (n) =>
              n.isVisibleBoardNote &&
              !now.isAfter(n.expiresAt) &&
              n.expiresAt.isBefore(cutoff),
        )
        .toList()
      ..sort((a, b) => a.compareExpiry(b));
  }

  int get noteCount =>
      notesBox.values.where((note) => note.isVisibleBoardNote).length;
}
