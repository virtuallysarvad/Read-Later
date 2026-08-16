import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/article_repository.dart';
import 'screens/home_screen.dart';
import 'services/drive_sync_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';

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
        ChangeNotifierProvider(create: (_) => DriveSyncService()..init()),
      ],
      child: MaterialApp(
        title: 'Read Later',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: HomeScreen(sharedUrl: sharedUrl),
      ),
    );
  }
}
