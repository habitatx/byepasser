import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/note.dart';
import '../models/app_settings.dart';
import '../services/notification_service.dart';
import '../services/haptics_service.dart';

/// Boxes (overridden at startup)
final notesBoxProvider = Provider<Box<Note>>((ref) {
  throw UnimplementedError('Override in main');
});

final settingsBoxProvider = Provider<Box<AppSettings>>((ref) {
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

/// Derived lists (recomputed when notesProvider changes)
final dyingSoonNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider);
  final now = DateTime.now();
  final cutoff = now.add(const Duration(hours: 6));
  final list = notes.where((n) => n.expiresAt.isBefore(cutoff) && !now.isAfter(n.expiresAt)).toList();
  list.sort((a, b) => a.compareExpiry(b));
  return list;
});

final regularNotesProvider = Provider<List<Note>>((ref) {
  final all = ref.watch(notesProvider);
  final dying = ref.watch(dyingSoonNotesProvider).map((n) => n.id).toSet();
  return all.where((n) => !dying.contains(n.id)).toList();
});

final noteCountProvider = Provider<int>((ref) => ref.watch(notesProvider).length);

/// Services
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError('Override in main');
});

final hapticsProvider = Provider<HapticsService>((ref) => HapticsService(ref));
