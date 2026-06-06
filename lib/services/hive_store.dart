import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_settings.dart';
import '../models/note.dart';

class HiveStore {
  const HiveStore({required this.notesBox, required this.settingsBox});

  static const notesBoxName = 'notes';
  static const settingsBoxName = 'app_settings';
  static const settingsKey = 'settings';

  final Box<Note> notesBox;
  final Box<AppSettings> settingsBox;

  static Future<HiveStore> open() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(NoteAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }

    final notesBox = await Hive.openBox<Note>(notesBoxName);
    final settingsBox = await Hive.openBox<AppSettings>(settingsBoxName);
    if (!settingsBox.containsKey(settingsKey)) {
      await settingsBox.put(settingsKey, const AppSettings());
    }

    final store = HiveStore(notesBox: notesBox, settingsBox: settingsBox);
    await store.deleteExpiredNotes();
    return store;
  }

  AppSettings get settings {
    return settingsBox.get(settingsKey) ?? const AppSettings();
  }

  Future<int> deleteExpiredNotes() async {
    final now = DateTime.now();
    final expiredKeys = notesBox.keys.where((key) {
      final note = notesBox.get(key);
      return note != null && now.isAfter(note.expiresAt);
    }).toList();
    await notesBox.deleteAll(expiredKeys);
    return expiredKeys.length;
  }
}
