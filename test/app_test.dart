import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:read_later/app.dart';
import 'package:read_later/screens/home_screen.dart';
import 'package:read_later/services/tts_service.dart';
import 'package:read_later/theme/app_theme.dart';
import 'package:read_later/theme/theme_controller.dart';
import 'package:read_later/theme/theme_variant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ReadLaterApp builds without provider errors', (tester) async {
    await tester.pumpWidget(
      ReadLaterApp(
        sharedUrl: ValueNotifier<String?>(null),
        tts: TtsService(),
      ),
    );
    await tester.pump();

    // Regression: the ThemeController lookup used the app widget's own
    // context (an ancestor of the providers), throwing ProviderNotFoundError
    // on every launch.
    expect(tester.takeException(), isNull);
    expect(find.text('Read Later'), findsOneWidget);
  });

  testWidgets('changing the theme variant re-themes the running app',
      (tester) async {
    await tester.pumpWidget(
      ReadLaterApp(
        sharedUrl: ValueNotifier<String?>(null),
        tts: TtsService(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final controller = tester
        .element(find.byType(HomeScreen))
        .read<ThemeController>();
    await controller.setVariant(ThemeVariant.dark);
    // MaterialApp animates theme changes, so let the transition finish.
    await tester.pumpAndSettle();

    // Dark forces dark mode with the brand palette.
    final scaffoldContext = tester.element(find.byType(Scaffold));
    expect(
      Theme.of(scaffoldContext).colorScheme.brightness,
      Brightness.dark,
    );
    expect(
      Theme.of(scaffoldContext).colorScheme.primary,
      AppTheme.dark(ThemeVariant.dark).colorScheme.primary,
    );
  });
}
