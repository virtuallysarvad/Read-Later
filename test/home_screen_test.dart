import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:read_later/data/article_repository.dart';
import 'package:read_later/models/article.dart';
import 'package:read_later/screens/home_screen.dart';
import 'package:read_later/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Article makeArticle(String id, String title,
      {String status = ArticleStatus.unread}) {
    return Article(
      id: id,
      url: 'https://example.com/$id',
      title: title,
      textContent: 'Some content for $title.',
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
      status: status,
    );
  }

  Future<void> pumpHome(WidgetTester tester, ArticleRepository repository) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repository,
        child: ChangeNotifierProvider.value(
          value: TtsService(),
          child: MaterialApp(
            home: HomeScreen(sharedUrl: ValueNotifier<String?>(null)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('All tab hides archived articles; Archive tab shows them',
      (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    // DB work is real async; run it outside the widget test's fake clock.
    await tester.runAsync(() async {
      await repository.init();
      await repository.mergeBackup([
        makeArticle('a1', 'Fresh article'),
        makeArticle('a2', 'Archived article', status: ArticleStatus.archived),
      ]);
    });

    await pumpHome(tester, repository);

    // All: only the unread article is listed.
    expect(find.text('Fresh article'), findsOneWidget);
    expect(find.text('Archived article'), findsNothing);

    // Archive: only the archived article is listed.
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archived article'), findsOneWidget);
    expect(find.text('Fresh article'), findsNothing);

    // Back to All.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh article'), findsOneWidget);
    expect(find.text('Archived article'), findsNothing);

    // Close so the next test opens a fresh in-memory database (sqflite
    // caches one instance per path, including ':memory:').
    await tester.runAsync(repository.close);
  });

  testWidgets('every article card shows a 3-dot menu with actions',
      (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    await tester.runAsync(() async {
      await repository.init();
      await repository.mergeBackup([makeArticle('a1', 'Menu article')]);
    });

    await pumpHome(tester, repository);

    // Open the overflow menu on the card.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    // Scope to the popup so the home screen's "Archive" tab doesn't match.
    Finder inMenu(String text) => find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text(text),
    );
    expect(inMenu('Add to favorites'), findsOneWidget);
    expect(inMenu('Archive'), findsOneWidget);
    expect(inMenu('Listen'), findsOneWidget);
    expect(inMenu('Open original'), findsOneWidget);
    expect(inMenu('Delete'), findsOneWidget);

    await tester.runAsync(repository.close);
  });

  testWidgets('mini player shows previous/next article buttons that switch '
      'articles', (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    await tester.runAsync(() async {
      await repository.init();
      await repository.mergeBackup([
        makeArticle('a1', 'First article'),
        makeArticle('a2', 'Second article'),
      ]);
    });

    // The TTS engine isn't available in tests; stub its channel so loading
    // and playing articles never touches the device.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => null,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    });

    final tts = TtsService();
    await tester.runAsync(() => tts.loadArticle(repository.byId('a1')!));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repository,
        child: ChangeNotifierProvider.value(
          value: tts,
          child: MaterialApp(
            home: HomeScreen(sharedUrl: ValueNotifier<String?>(null)),
          ),
        ),
      ),
    );
    await tester.pump();

    // The player is visible with previous/next article controls.
    expect(find.text('Listening'), findsOneWidget);
    expect(find.byTooltip('Previous article'), findsOneWidget);
    expect(find.byTooltip('Next article'), findsOneWidget);

    // Next article loads and plays the following article (a1 -> a2 either
    // way, since two articles wrap around).
    await tester.tap(find.byTooltip('Next article'));
    await tester.pump();
    await tester.pump();
    expect(tts.article?.id, 'a2');
    expect(tts.isPlaying, isTrue);

    // Stop playback so the mini player's progress ticker doesn't leak past
    // the end of the test.
    await tester.runAsync(() => tts.stop());
    await tester.pump();

    await tester.runAsync(repository.close);
  });

  testWidgets('tapping the mini player progress bar seeks within the article',
      (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    await tester.runAsync(() async {
      await repository.init();
      // Three short paragraphs → three TTS segments.
      await repository.mergeBackup([
        Article(
          id: 'seek-1',
          url: 'https://example.com/seek',
          title: 'Seekable article',
          textContent: 'First paragraph of the story with detail.\n\n'
              'Second paragraph of the story with detail.\n\n'
              'Third paragraph of the story with detail.',
          hasContent: true,
          savedAt: 0,
          updatedAt: 0,
        ),
      ]);
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => null,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    });

    final tts = TtsService();
    await tester.runAsync(() => tts.loadArticle(repository.byId('seek-1')!));
    expect(tts.segmentIndex, 0);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repository,
        child: ChangeNotifierProvider.value(
          value: tts,
          child: MaterialApp(
            home: HomeScreen(sharedUrl: ValueNotifier<String?>(null)),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tap near the right end of the player's progress bar → last segment.
    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    await tester.tapAt(
      tester.getTopRight(bar) - const Offset(4, 0),
    );
    await tester.pump();
    await tester.pump();

    expect(tts.segmentIndex, tts.segments.length - 1);

    await tester.runAsync(repository.close);
  });

  testWidgets('unarchiving an article brings it back to All', (tester) async {
    final repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    final archived = makeArticle(
      'a1',
      'Returning article',
      status: ArticleStatus.archived,
    );
    await tester.runAsync(() async {
      await repository.init();
      await repository.mergeBackup([archived]);
    });

    await pumpHome(tester, repository);
    expect(find.text('Returning article'), findsNothing);

    // Unarchive via the repository (same path the card menu uses).
    // Real DB I/O must run inside runAsync; awaiting it directly in the
    // widget test's fake-async zone deadlocks.
    await tester.runAsync(
      () => repository.setStatus(archived.id, ArticleStatus.unread),
    );
    await tester.pump();

    expect(find.text('Returning article'), findsOneWidget);

    // Close so a later test opens a fresh in-memory database.
    await tester.runAsync(repository.close);
  });
}
