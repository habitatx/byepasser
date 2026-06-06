import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import '../models/note.dart';

class ExportService {
  Future<XFile> createJsonExport({
    required List<Note> notes,
    required AppSettings settings,
  }) async {
    final export = {
      'app': 'Byepasser',
      'tagline': 'Notes that say bye.',
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings.toJson(),
      'notes': notes.map((note) => note.toJson()).toList(),
    };

    final directory = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/byepasser_export_$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(export),
    );

    return XFile(
      file.path,
      mimeType: 'application/json',
      name: 'byepasser_export_$stamp.json',
    );
  }
}
