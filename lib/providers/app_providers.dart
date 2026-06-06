import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../services/export_service.dart';
import '../services/hive_store.dart';
import '../services/notification_service.dart';
import '../utils/lifetime.dart';

final notesBoxProvider = Provider<Box<Note>>((ref) {
  throw UnimplementedError('notesBoxProvider must be overridden in main.');
});

final settingsBoxProvider = Provider<Box<AppSettings>>((ref) {
  throw UnimplementedError('settingsBoxProvider must be overridden in main.');
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError(
    'notificationServiceProvider must be overridden in main.',
  );
});

final exportServiceProvider = Provider<ExportService>((ref) => ExportService());

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final notesProvider = NotifierProvider<NotesController, List<Note>>(
  NotesController.new,
);

final currentTimeProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

final dyingSoonNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider);
  final now = ref.watch(currentTimeProvider).value ?? DateTime.now();
  return notes.where((note) => isDyingSoon(note.expiresAt, now)).toList();
});

class SettingsController extends Notifier<AppSettings> {
  late Box<AppSettings> _box;

  @override
  AppSettings build() {
    _box = ref.watch(settingsBoxProvider);
    return _box.get(HiveStore.settingsKey) ?? const AppSettings();
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await _box.put(HiveStore.settingsKey, next);
  }

  Future<void> setTheme(String key) => update(state.copyWith(themeKey: key));

  Future<void> setAccent(int index) {
    return update(state.copyWith(accentIndex: index.clamp(0, 7).toInt()));
  }

  Future<void> setCardStyle(String style) {
    return update(state.copyWith(cardStyle: style));
  }

  Future<void> setDefaultLifetime(int minutes) {
    return update(
      state.copyWith(
        defaultLifetimeMinutes: minutes
            .clamp(minLifetimeMinutes, maxLifetimeMinutes)
            .toInt(),
      ),
    );
  }

  Future<void> setDefaultSteamLifetime(int minutes) {
    return update(
      state.copyWith(
        defaultSteamLifetimeMinutes: minutes
            .clamp(minSteamLifetimeMinutes, maxSteamLifetimeMinutes)
            .toInt(),
      ),
    );
  }
}

class NotesController extends Notifier<List<Note>> {
  late Box<Note> _box;
  final Set<String> _autoCopiedIds = {};

  @override
  List<Note> build() {
    _box = ref.watch(notesBoxProvider);
    return _sortedActiveNotes();
  }

  Future<Note> createNote({
    String? title,
    required String body,
    required int lifetimeMinutes,
    bool isSteamMode = false,
    int? colorTag,
  }) async {
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();
    final normalizedTitle = _normalizedTitle(title, body, settings);
    final note = Note(
      id: const Uuid().v4(),
      title: normalizedTitle,
      body: body,
      createdAt: now,
      expiresAt: now.add(Duration(minutes: lifetimeMinutes)),
      lifetimeMinutes: lifetimeMinutes,
      isSteamMode: isSteamMode,
      colorTag: colorTag,
    );

    await _box.put(note.id, note);
    state = _sortedActiveNotes();
    await ref
        .read(notificationServiceProvider)
        .scheduleExpiryReminders(note, enabled: settings.gentleNotifications);
    return note;
  }

  Future<void> updateNote(Note note) async {
    final settings = ref.read(settingsProvider);
    final normalized = note.copyWith(
      title: _normalizedTitle(note.title, note.body, settings),
    );
    await _box.put(normalized.id, normalized);
    state = _sortedActiveNotes();
    await ref
        .read(notificationServiceProvider)
        .scheduleExpiryReminders(
          normalized,
          enabled: settings.gentleNotifications,
        );
  }

  Future<void> extendOnce(String noteId) async {
    final note = _box.get(noteId);
    if (note == null || note.extended) {
      return;
    }

    final settings = ref.read(settingsProvider);
    final extended = note.copyWith(
      expiresAt: DateTime.now().add(Duration(minutes: note.lifetimeMinutes)),
      extended: true,
    );
    await _box.put(noteId, extended);
    state = _sortedActiveNotes();
    await ref
        .read(notificationServiceProvider)
        .scheduleExpiryReminders(
          extended,
          enabled: settings.gentleNotifications,
        );
  }

  Future<void> deleteNote(String noteId) async {
    await ref.read(notificationServiceProvider).cancelForNote(noteId);
    await _box.delete(noteId);
    _autoCopiedIds.remove(noteId);
    state = _sortedActiveNotes();
  }

  Future<void> nukeAll() async {
    await ref.read(notificationServiceProvider).cancelAll();
    await _box.clear();
    _autoCopiedIds.clear();
    state = const [];
  }

  Future<int> deleteExpiredNow() async {
    final now = DateTime.now();
    final expired = _box.values.where((note) => now.isAfter(note.expiresAt));
    final expiredIds = expired.map((note) => note.id).toList();
    for (final id in expiredIds) {
      await ref.read(notificationServiceProvider).cancelForNote(id);
      _autoCopiedIds.remove(id);
    }
    await _box.deleteAll(expiredIds);
    state = _sortedActiveNotes();
    return expiredIds.length;
  }

  Future<void> sweepExpiredAndAutoCopy() async {
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();

    if (settings.autoCopyBeforeDeletion) {
      for (final note in _box.values) {
        final remaining = note.expiresAt.difference(now);
        if (remaining > Duration.zero &&
            remaining <= const Duration(minutes: 5) &&
            !_autoCopiedIds.contains(note.id)) {
          await Clipboard.setData(ClipboardData(text: note.toShareText()));
          _autoCopiedIds.add(note.id);
          break;
        }
      }
    }

    await deleteExpiredNow();
  }

  Future<void> syncNotifications() async {
    final settings = ref.read(settingsProvider);
    if (!settings.gentleNotifications) {
      await ref.read(notificationServiceProvider).cancelAll();
      return;
    }

    for (final note in _sortedActiveNotes()) {
      await ref
          .read(notificationServiceProvider)
          .scheduleExpiryReminders(note, enabled: true);
    }
  }

  Note? noteById(String noteId) => _box.get(noteId);

  List<Note> _sortedActiveNotes() {
    final now = DateTime.now();
    final notes =
        _box.values.where((note) => !now.isAfter(note.expiresAt)).toList()
          ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    return List.unmodifiable(notes);
  }

  String? _normalizedTitle(String? title, String body, AppSettings settings) {
    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if (!settings.autoGenerateTitle) {
      return null;
    }
    final firstLine = body
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      return null;
    }
    return firstLine.length <= 48
        ? firstLine
        : '${firstLine.substring(0, 45)}...';
  }
}
