import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:read_later/data/article_repository.dart';
import 'package:read_later/screens/settings_screen.dart';
import 'package:read_later/services/backup_service.dart';
import 'package:read_later/services/tts_service.dart';
import 'package:read_later/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
