import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/article.dart';

/// Backs the article library up to a local JSON file and restores it,
/// using the platform's native file picker (Android/iOS files app, SAF).
///
/// No cloud account or permissions are needed: the user chooses where the
/// backup lives (Downloads, Drive, etc.) through the system UI.
class BackupService extends ChangeNotifier {
  static const String _fileName = 'read_later_backup.json';

  bool _busy = false;
  String? _statusMessage;

  bool get isBusy => _busy;
  String? get statusMessage => _statusMessage;

  /// Opens the system "save file" dialog and writes [articles] as JSON.
  ///
  /// Returns true when the backup was written, false when the user cancelled.
  Future<bool> backup(List<Article> articles) async {
    _setBusy('Preparing backup…');
    try {
      final payload = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().millisecondsSinceEpoch,
        'articles': articles.map((a) => a.toJson()).toList(),
      });

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup',
        fileName: _fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(payload)),
      );
      if (path == null) {
        _statusMessage = null;
        return false; // Cancelled by the user.
      }

      _statusMessage =
          'Backed up ${articles.length} article${articles.length == 1 ? '' : 's'} '
          'to the selected location.';
      return true;
    } catch (e) {
      _statusMessage = 'Backup failed: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Opens the system file picker for a backup JSON and returns its articles
  /// (empty list when the user cancels).
  Future<List<Article>> restore() async {
    _setBusy('Reading backup…');
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a backup',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        _statusMessage = null;
        return const []; // Cancelled by the user.
      }

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw StateError('Could not read the selected file.');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final articles = (decoded['articles'] as List<dynamic>? ?? [])
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _statusMessage =
          'Found ${articles.length} article${articles.length == 1 ? '' : 's'} '
          'in the backup.';
      return articles;
    } catch (e) {
      _statusMessage = 'Restore failed: $e';
      return const [];
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _setBusy(String message) {
    _busy = true;
    _statusMessage = message;
    notifyListeners();
  }
}
