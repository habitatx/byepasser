import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';

/// Handles exporting all notes to a JSON file and sharing via the native iOS share sheet.
class ExportService {
  /// Exports all notes as pretty-printed JSON and shares it using share_plus.
  /// Returns true if share sheet was presented.
  static Future<bool> exportAndShare(List<Note> notes) async {
    if (notes.isEmpty) return false;

    final payload = notes.map((n) => {
          'id': n.id,
          'title': n.title,
          'body': n.body,
          'createdAt': n.createdAt.toIso8601String(),
          'expiresAt': n.expiresAt.toIso8601String(),
          'lifetimeMinutes': n.lifetimeMinutes,
          'extended': n.extended,
          'isSteamMode': n.isSteamMode,
          'colorTag': n.colorTag,
        }).toList();

    final jsonString = const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toIso8601String(),
      'noteCount': notes.length,
      'notes': payload,
    });

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/byepasser_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonString, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'My Byepasser notes export (${notes.length} notes)',
        subject: 'Byepasser Export',
      ),
    );

    // Best-effort cleanup (non-blocking)
    Future.delayed(const Duration(seconds: 8), () async {
      if (await file.exists()) {
        try { await file.delete(); } catch (_) {}
      }
    });

    return result.status == ShareResultStatus.success || result.status == ShareResultStatus.unavailable;
  }

  /// Quick copy of a single note's body to clipboard.
  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
