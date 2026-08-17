import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:read_later/models/article.dart';
import 'package:read_later/services/auto_backup_service.dart';

Article _makeArticle(String id, String title) {
  return Article(
    id: id,
    url: 'https://example.com/$id',
    title: title,
    siteName: 'Example',
    textContent: 'Body of $title.',
    hasContent: true,
    savedAt: 1000,
    updatedAt: 1000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AutoBackupService frequency', () {
    test('init with no saved frequency leaves auto backup off', () async {
      final service = AutoBackupService(scheduler: (_) async {});
      await service.init();

      expect(service.frequency, isNull);
      expect(service.isEnabled, isFalse);
    });

    test('init restores a saved frequency', () async {
      SharedPreferences.setMockInitialValues({
        'auto_backup_frequency': AutoBackupFrequency.days15.name,
      });

      final service = AutoBackupService(scheduler: (_) async {});
      await service.init();

      expect(service.frequency, AutoBackupFrequency.days15);
      expect(service.isEnabled, isTrue);
    });

    test('setFrequency schedules the WorkManager task with the duration',
        () async {
      Duration? scheduled;
      final service = AutoBackupService(
        scheduler: (frequency) async => scheduled = frequency,
      );
      await service.init();

      await service.setFrequency(AutoBackupFrequency.hours12);
      expect(scheduled, const Duration(hours: 12));

      // A different frequency re-schedules (update, not keep).
      await service.setFrequency(AutoBackupFrequency.days15);
      expect(scheduled, const Duration(days: 15));

      // Off cancels the schedule.
      await service.setFrequency(null);
      expect(scheduled, isNull);
    });

    test('setFrequency persists the choice across restarts', () async {
      final service = AutoBackupService(scheduler: (_) async {});
      await service.init();
      await service.setFrequency(AutoBackupFrequency.hours24);

      // A fresh instance (same SharedPreferences) sees the saved frequency.
      final reloaded = AutoBackupService(scheduler: (_) async {});
      await reloaded.init();
      expect(reloaded.frequency, AutoBackupFrequency.hours24);
    });
  });

  group('AutoBackupService backup file', () {
    test('backupNow writes a JSON backup and records the result', () async {
      final dir = await Directory.systemTemp.createTemp('auto_backup_test');
      addTearDown(() => dir.delete(recursive: true));

      final service = AutoBackupService(
        scheduler: (_) async {},
        backupDirectory: dir.path,
      );
      await service.init();

      final path = await service.backupNow([
        _makeArticle('a1', 'First'),
        _makeArticle('a2', 'Second'),
      ]);

      expect(path, isNotNull);
      expect(service.lastBackupAt, isNotNull);
      expect(service.lastBackupCount, 2);

      final decoded =
          jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
      expect(decoded['version'], 1);
      final articles = decoded['articles'] as List<dynamic>;
      expect(articles, hasLength(2));
      expect(articles.first['title'], 'First');

      // A fresh instance reads the recorded result back from prefs.
      final reloaded = AutoBackupService(
        scheduler: (_) async {},
        backupDirectory: dir.path,
      );
      await reloaded.init();
      expect(reloaded.lastBackupCount, 2);
      expect(reloaded.lastBackupAt, isNotNull);
    });

    test('the written backup round-trips through Article.fromJson', () async {
      final dir = await Directory.systemTemp.createTemp('auto_backup_test');
      addTearDown(() => dir.delete(recursive: true));
      final source = _makeArticle('a1', 'Round trip');
      source.isFavorite = true;

      final path = await AutoBackupService.writeAutoBackup(
        [source],
        directory: dir.path,
      );
      expect(path, isNotNull);

      final decoded =
          jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
      final restored = Article.fromJson(
        (decoded['articles'] as List<dynamic>).first as Map<String, dynamic>,
      );
      expect(restored.id, source.id);
      expect(restored.title, source.title);
      expect(restored.isFavorite, isTrue);
      expect(restored.textContent, source.textContent);
    });

    test('backupNow with an unwritable directory reports failure', () async {
      final service = AutoBackupService(
        scheduler: (_) async {},
        // A path that cannot exist.
        backupDirectory:
            '/nonexistent-${DateTime.now().microsecondsSinceEpoch}/dir',
      );
      await service.init();

      final path = await service.backupNow([_makeArticle('a1', 'First')]);

      expect(path, isNull);
      expect(service.lastBackupAt, isNull);
      expect(service.lastBackupCount, 0);
    });
  });
}
