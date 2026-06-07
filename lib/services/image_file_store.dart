import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ImageFileStore {
  static const String noteAttachmentsDirName = 'note_attachments';
  static const String boardFacesDirName = 'board_faces';

  static String? _documentsPath;

  static void configureDocumentsPath(String path) {
    _documentsPath = _trimTrailingSeparator(path);
  }

  static Future<String> saveNoteAttachment(String sourcePath) async {
    final directory = await _ensureSubdirectory(noteAttachmentsDirName);
    final fileName =
        'note_attachment_${DateTime.now().millisecondsSinceEpoch}.${_safeExtension(sourcePath)}';
    return _copyInto(sourcePath, directory, fileName);
  }

  static Future<String> saveBoardFace(String boardId, String sourcePath) async {
    final directory = await _ensureSubdirectory(boardFacesDirName);
    final fileName =
        '${boardId}_${DateTime.now().millisecondsSinceEpoch}.${_safeExtension(sourcePath)}';
    return _copyInto(sourcePath, directory, fileName);
  }

  static File resolve(String storedPath) {
    final path = storedPath.trim();
    final documentsPath = _documentsPath;
    if (path.isEmpty || documentsPath == null) {
      return File(path);
    }

    if (!_isAbsolute(path)) {
      return File(_join(documentsPath, path));
    }

    final file = File(path);
    if (file.existsSync()) {
      return file;
    }

    for (final candidate in _legacyCandidates(path, documentsPath)) {
      final candidateFile = File(candidate);
      if (candidateFile.existsSync()) {
        return candidateFile;
      }
    }

    return file;
  }

  static String canonicalStoredPath(String storedPath) {
    final file = resolve(storedPath);
    if (!file.existsSync()) {
      return storedPath;
    }
    return _storedPathForFile(file);
  }

  static Future<void> delete(String storedPath) async {
    final file = resolve(storedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<Directory> _documentsDirectory() async {
    final current = _documentsPath;
    if (current != null) {
      return Directory(current);
    }
    final directory = await getApplicationDocumentsDirectory();
    configureDocumentsPath(directory.path);
    return directory;
  }

  static Future<Directory> _ensureSubdirectory(String name) async {
    final documents = await _documentsDirectory();
    final directory = Directory(_join(documents.path, name));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<String> _copyInto(
    String sourcePath,
    Directory directory,
    String fileName,
  ) async {
    final saved = await File(sourcePath).copy(_join(directory.path, fileName));
    return _storedPathForFile(saved);
  }

  static String _storedPathForFile(File file) {
    final documentsPath = _documentsPath;
    if (documentsPath == null) {
      return file.path;
    }

    final normalizedDocuments = _trimTrailingSeparator(documentsPath);
    final prefix = '$normalizedDocuments${Platform.pathSeparator}';
    if (file.path.startsWith(prefix)) {
      return file.path.substring(prefix.length);
    }
    return file.path;
  }

  static Iterable<String> _legacyCandidates(
    String stalePath,
    String documentsPath,
  ) sync* {
    final suffix = _documentsSuffix(stalePath);
    if (suffix != null && suffix.isNotEmpty) {
      yield _join(documentsPath, suffix);
    }

    final basename = _basename(stalePath);
    if (basename.isEmpty) return;
    yield _join(documentsPath, basename);
    yield _join(_join(documentsPath, noteAttachmentsDirName), basename);
    yield _join(_join(documentsPath, boardFacesDirName), basename);
  }

  static String? _documentsSuffix(String path) {
    const marker = '/Documents/';
    final index = path.lastIndexOf(marker);
    if (index == -1) return null;
    return path.substring(index + marker.length);
  }

  static String _safeExtension(String path) {
    final basename = _basename(path);
    final dot = basename.lastIndexOf('.');
    if (dot == -1 || dot == basename.length - 1) {
      return 'jpg';
    }

    final extension = basename.substring(dot + 1).toLowerCase();
    final safe = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension);
    return safe ? extension : 'jpg';
  }

  static bool _isAbsolute(String path) {
    return path.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    final index = slash > backslash ? slash : backslash;
    return index == -1 ? path : path.substring(index + 1);
  }

  static String _join(String left, String right) {
    if (left.endsWith('/') || left.endsWith(r'\')) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  static String _trimTrailingSeparator(String path) {
    var value = path;
    while (value.endsWith('/') || value.endsWith(r'\')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
