import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:read_later/data/article_repository.dart';
import 'package:read_later/screens/settings_screen.dart';
import 'package:read_later/services/auto_backup_service.dart';
import 'package:read_later/services/backup_service.dart';
import 'package:read_later/services/tts_service.dart';
import 'package:read_later/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('settings_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('Settings shows file backup buttons and no Google sign-in',
      (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    await tester.runAsync(repository.init);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repository),
          ChangeNotifierProvider(create: (_) => TtsService()),
          ChangeNotifierProvider(create: (_) => BackupService()),
          ChangeNotifierProvider(
            create: (_) => AutoBackupService(
              scheduler: (_) async {},
              backupDirectory: tempDir.path,
            ),
          ),
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    // The Appearance section (theme tiles) is tall, so scroll down to the
    // Backup section.
    await tester.scrollUntilVisible(
      find.text('Back up'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Back up'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    // The Google Drive flow is gone.
    expect(find.textContaining('Sign in with Google'), findsNothing);
    expect(find.textContaining('Google Drive'), findsNothing);

    await tester.runAsync(repository.close);
  });

  testWidgets('Settings offers the four auto-backup frequencies',
      (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    await tester.runAsync(repository.init);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repository),
          ChangeNotifierProvider(create: (_) => TtsService()),
          ChangeNotifierProvider(create: (_) => BackupService()),
          ChangeNotifierProvider(
            create: (_) => AutoBackupService(
              scheduler: (_) async {},
              backupDirectory: tempDir.path,
            ),
          ),
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    // Scroll to the auto-backup frequency dropdown.
    await tester.scrollUntilVisible(
      find.text('Auto backup frequency'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Auto backup frequency'), findsOneWidget);
    // "Back up now" triggers an immediate auto backup (no file picker).
    expect(find.text('Back up now'), findsOneWidget);

    // Open the dropdown and check every offered frequency.
    final dropdown = find.byType(DropdownButtonFormField<AutoBackupFrequency?>);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    for (final label in [
      'Every 12 hours',
      'Every 24 hours',
      'Every day',
      'Every 15 days',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // Pick one; the choice is applied (no exception).
    await tester.tap(find.text('Every 12 hours').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // "Back up now" is wired to an immediate auto backup (no file picker);
    // the file-writing behavior itself is covered by the service tests.
    await tester.scrollUntilVisible(
      find.text('Back up now'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(find.text('Back up now'));
    await tester.pumpAndSettle();
    // Tap inside runAsync so the fire-and-forget backup's real file I/O
    // completes (and its handle closes) instead of parking in the fake
    // async zone and locking the temp directory on teardown.
    await tester.runAsync(() async {
      await tester.tap(find.text('Back up now'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.runAsync(repository.close);
  });
}
