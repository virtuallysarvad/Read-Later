import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/article_repository.dart';
import '../models/article.dart';

/// Periodic, hands-off backups of the article library.
///
/// The user picks a frequency in Settings; [AutoBackupService] schedules a
/// WorkManager periodic task that writes a JSON backup of every article to
/// the app's external files directory (no permissions, no file picker), so a
/// backup exists even if the app isn't opened again before the next interval.
/// Manual backup/restore to a user-chosen location is unchanged.
class AutoBackupService extends ChangeNotifier {
  /// The frequencies offered in Settings, in order: 12 hours, 24 hours,
  /// 1 day and 15 days (as requested). "Every 24 hours" and "Every day" have
  /// the same duration but are kept as separate, named choices.
  static const List<({AutoBackupFrequency value, String label})>
      frequencyOptions = [
    (value: AutoBackupFrequency.hours12, label: 'Every 12 hours'),
    (value: AutoBackupFrequency.hours24, label: 'Every 24 hours'),
    (value: AutoBackupFrequency.daily, label: 'Every day'),
    (value: AutoBackupFrequency.days15, label: 'Every 15 days'),
  ];

  static const String _frequencyKey = 'auto_backup_frequency';
  static const String _lastBackupAtKey = 'auto_backup_last_at';
  static const String _lastBackupCountKey = 'auto_backup_last_count';
  static const String _taskName = 'readLaterAutoBackup';
  static const String _fileName = 'read_later_auto_backup.json';

  /// Injectable scheduler so tests can observe frequency changes without the
  /// WorkManager platform channel. Receives the new frequency (null = off).
  final Future<void> Function(Duration? frequency)? _scheduler;

  /// Injectable destination so tests can write backups without the
  /// path_provider platform channel.
  final String? _backupDirectory;

  AutoBackupFrequency? _frequency;
  DateTime? _lastBackupAt;
  int _lastBackupCount = 0;

  AutoBackupService({
    Future<void> Function(Duration? frequency)? scheduler,
    String? backupDirectory,
  })  : _scheduler = scheduler,
        _backupDirectory = backupDirectory;

  /// The selected frequency, or null when auto backup is off.
  AutoBackupFrequency? get frequency => _frequency;

  bool get isEnabled => _frequency != null;

  /// When the most recent auto backup ran (null if none yet).
  DateTime? get lastBackupAt => _lastBackupAt;

  /// How many articles the most recent auto backup contained.
  int get lastBackupCount => _lastBackupCount;

  /// Loads persisted state and (re)applies the schedule. Safe to call once at
  /// startup; scheduling failures (e.g. unsupported platform) are ignored.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_frequencyKey);
    AutoBackupFrequency? saved;
    for (final f in AutoBackupFrequency.values) {
      if (f.name == name) {
        saved = f;
        break;
      }
    }
    _frequency = saved;
    final lastAt = prefs.getInt(_lastBackupAtKey);
    _lastBackupAt =
        lastAt == null ? null : DateTime.fromMillisecondsSinceEpoch(lastAt);
    _lastBackupCount = prefs.getInt(_lastBackupCountKey) ?? 0;
    await _schedule(_frequency?.duration);
    notifyListeners();
  }

  /// Turns auto backup on with [frequency], or off when null. Persists the
  /// choice and re-schedules the periodic task.
  Future<void> setFrequency(AutoBackupFrequency? frequency) async {
    _frequency = frequency;
    final prefs = await SharedPreferences.getInstance();
    if (frequency == null) {
      await prefs.remove(_frequencyKey);
    } else {
      await prefs.setString(_frequencyKey, frequency.name);
    }
    await _schedule(frequency?.duration);
    notifyListeners();
  }

  /// Re-registers (or cancels) the periodic WorkManager task. Falls back to
  /// the injected scheduler in tests.
  Future<void> _schedule(Duration? frequency) async {
    final scheduler = _scheduler;
    if (scheduler != null) {
      await scheduler(frequency);
      return;
    }
    try {
      final workmanager = Workmanager();
      if (frequency == null) {
        await workmanager.cancelByUniqueName(_taskName);
      } else {
        await workmanager.registerPeriodicTask(
          _taskName,
          _taskName,
          frequency: frequency,
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
      }
    } catch (_) {
      // Unsupported platform or unregistered plugin — the app keeps working;
      // backups just won't be scheduled in the background.
    }
  }

  /// Writes a backup of [articles] immediately and records the result.
  /// Returns the file path, or null on failure.
  Future<String?> backupNow(List<Article> articles) async {
    final path = await writeAutoBackup(articles, directory: _backupDirectory);
    if (path != null) {
      await _recordSuccess(articles.length);
    }
    return path;
  }

  /// Exported so the WorkManager background task (which has no UI service)
  /// can write a backup. Returns the file path, or null on failure.
  ///
  /// [directory] overrides the destination (used by tests); by default the
  /// backup lands in the app's external files directory.
  static Future<String?> writeAutoBackup(
    List<Article> articles, {
    String? directory,
  }) async {
    try {
      final dirPath =
          directory ?? (await getExternalStorageDirectory())?.path;
      if (dirPath == null) return null;
      final payload = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().millisecondsSinceEpoch,
        'articles': articles.map((a) => a.toJson()).toList(),
      });
      final file = File('$dirPath${Platform.pathSeparator}$_fileName');
      await file.writeAsString(payload);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Runs the scheduled background backup: opens the database from scratch,
  /// writes the backup file and records the timestamp. Called by the
  /// WorkManager dispatcher in a headless isolate.
  static Future<bool> runScheduledBackup() async {
    try {
      final repository = ArticleRepository();
      await repository.init();
      final articles = repository.all;
      final path = await writeAutoBackup(articles);
      await repository.close();
      if (path == null) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastBackupAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setInt(_lastBackupCountKey, articles.length);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordSuccess(int count) async {
    _lastBackupAt = DateTime.now();
    _lastBackupCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastBackupAtKey,
      _lastBackupAt!.millisecondsSinceEpoch,
    );
    await prefs.setInt(_lastBackupCountKey, count);
    notifyListeners();
  }
}

/// The available auto-backup frequencies.
enum AutoBackupFrequency {
  hours12(Duration(hours: 12)),
  hours24(Duration(hours: 24)),
  daily(Duration(hours: 24)),
  days15(Duration(days: 15));

  const AutoBackupFrequency(this.duration);

  final Duration duration;
}
