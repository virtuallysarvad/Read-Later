import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/article_repository.dart';
import 'screens/home_screen.dart';
import 'services/auto_backup_service.dart';
import 'services/backup_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_variant.dart';

/// A URL received from the Android share sheet, surfaced as a ValueNotifier so
/// the UI can react to it (null = nothing pending).
class ReadLaterApp extends StatelessWidget {
  final ValueNotifier<String?> sharedUrl;
  final TtsService tts;

  const ReadLaterApp({
    super.key,
    required this.sharedUrl,
    required this.tts,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ArticleRepository()..init()),
        ChangeNotifierProvider(create: (_) => tts),
        ChangeNotifierProvider(create: (_) => BackupService()),
        // Loads the saved frequency and re-applies the WorkManager schedule.
        ChangeNotifierProvider(create: (_) => AutoBackupService()..init()),
        ChangeNotifierProvider(create: (_) => ThemeController()..load()),
      ],
      // DynamicColorBuilder surfaces the platform's Material You colors
      // (wallpaper on Android 12+, accent color on desktop). It returns null
      // on unsupported platforms, where AppTheme falls back to the brand seed.
      //
      // DynamicColorBuilder's builder receives no BuildContext, so a Builder
      // sits between the MultiProvider and the lookup: the context it captures
      // is a *descendant* of the providers (reading from the widget's own
      // context above them would throw ProviderNotFoundException).
      child: Builder(
        builder: (builderContext) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final themeController = builderContext.watch<ThemeController>();
            final variant = themeController.variant;
            return MaterialApp(
              title: 'Read Later',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(variant, lightDynamic),
              darkTheme: AppTheme.dark(variant, darkDynamic),
              // Light and Dark force the mode; Dynamic follows the system.
              themeMode: switch (variant) {
                ThemeVariant.light => ThemeMode.light,
                ThemeVariant.dark => ThemeMode.dark,
                ThemeVariant.dynamic => ThemeMode.system,
              },
              home: HomeScreen(sharedUrl: sharedUrl),
            );
          },
        ),
      ),
    );
  }
}
