import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:read_later/data/article_repository.dart';
import 'package:read_later/models/article.dart';
import 'package:read_later/services/tts_service.dart';

/// Four paragraphs separated by blank lines; each is short enough to become a
/// single TTS segment, so the chunker yields exactly 4 segments (indices 0-3).
const _sampleText = '''
Paragraph one talks about the first idea in some detail.

Paragraph two continues with the second idea of the article.

Paragraph three introduces a third and quite separate idea.

Paragraph four wraps everything up with a conclusion.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late ArticleRepository repository;
  late Article article;

  setUpAll(() async {
    repository = ArticleRepository(databasePath: inMemoryDatabasePath);
    await repository.init();
    article = Article(
      id: 'article-1',
      url: 'https://example.com/story',
      title: 'A persistent test article',
      siteName: 'Example',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    );
    await repository.mergeBackup([article]);
  });

  tearDownAll(() => repository.clearAll());

  group('TtsService article skipping (previous/next)', () {
    // A dedicated file DB: the shared ':memory:' path is cached by sqflite,
    // so closing it would break the other group's repository.
    const skipDbPath = 'test_skip_articles.db';

    late ArticleRepository skipRepository;
    late Article skipFirst, skipSecond, skipThird;
    late TtsService skipTts;

    setUp(() async {
      // The TTS engine isn't available in tests; stub its platform channel so
      // loading and playing articles never touches the device.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => null,
      );
      SharedPreferences.setMockInitialValues({});

      skipRepository = ArticleRepository(databasePath: skipDbPath);
      await skipRepository.init();
      // savedAt drives the queue order (newest first).
      skipFirst = Article(
        id: 'skip-1',
        url: 'https://example.com/1',
        title: 'First article',
        textContent: 'First article with enough text to listen to.',
        hasContent: true,
        savedAt: 300,
        updatedAt: 300,
      );
      skipSecond = Article(
        id: 'skip-2',
        url: 'https://example.com/2',
        title: 'Second article',
        textContent: 'Second article with enough text to listen to.',
        hasContent: true,
        savedAt: 200,
        updatedAt: 200,
      );
      skipThird = Article(
        id: 'skip-3',
        url: 'https://example.com/3',
        title: 'Third article',
        textContent: 'Third article with enough text to listen to.',
        hasContent: true,
        savedAt: 100,
        updatedAt: 100,
      );
      await skipRepository.mergeBackup([skipThird, skipFirst, skipSecond]);

      skipTts = TtsService();
      await skipTts.loadArticle(skipFirst);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
      await skipRepository.close();
      await databaseFactory.deleteDatabase(skipDbPath);
    });

    test('next article moves down the queue and plays', () async {
      await skipTts.playNextArticle(skipRepository);

      expect(skipTts.article?.id, 'skip-2');
      expect(skipTts.isPlaying, isTrue);
    });

    test('next article wraps from the last back to the first', () async {
      await skipTts.loadArticle(skipThird);

      await skipTts.playNextArticle(skipRepository);

      expect(skipTts.article?.id, 'skip-1');
    });

    test('previous article moves up the queue and plays', () async {
      await skipTts.playPreviousArticle(skipRepository);

      expect(skipTts.article?.id, 'skip-3');
      expect(skipTts.isPlaying, isTrue);
    });

    test('previous article wraps from the first to the last', () async {
      // skipFirst is loaded in setUp; going back lands on the newest-first
      // queue's last entry.
      await skipTts.playPreviousArticle(skipRepository);

      expect(skipTts.article?.id, 'skip-3');
    });

    test('archived and content-less articles are excluded from the queue',
        () async {
      await skipRepository.mergeBackup([
        Article(
          id: 'skip-archived',
          url: 'https://example.com/archived',
          title: 'Archived article',
          textContent: 'Should never play.',
          hasContent: true,
          savedAt: 250, // would sort before skipSecond if included
          updatedAt: 250,
          status: ArticleStatus.archived,
        ),
        Article(
          id: 'skip-empty',
          url: 'https://example.com/empty',
          title: 'Empty article',
          textContent: '',
          hasContent: false,
          savedAt: 150,
          updatedAt: 150,
        ),
      ]);

      // skipFirst -> next should be skipSecond, not the archived article.
      await skipTts.playNextArticle(skipRepository);

      expect(skipTts.article?.id, 'skip-2');
    });
  });

  group('TtsService session persistence', () {
    test('restoreSession loads the saved article and segment without playing',
        () async {
      SharedPreferences.setMockInitialValues({
        'tts_session_article_id': article.id,
        'tts_session_segment': 2,
      });

      final tts = TtsService();
      await tts.restoreSession(repository);

      expect(tts.article?.id, article.id);
      expect(tts.segmentIndex, 2);
      expect(tts.hasContent, isTrue);
      expect(tts.isPlaying, isFalse);
      expect(tts.isPaused, isFalse);
    });

    test('restoreSession clamps an out-of-range segment', () async {
      SharedPreferences.setMockInitialValues({
        'tts_session_article_id': article.id,
        'tts_session_segment': 99,
      });

      final tts = TtsService();
      await tts.restoreSession(repository);

      expect(tts.article?.id, article.id);
      expect(tts.segmentIndex, 3); // last valid segment (4 segments total)
    });

    test('restoreSession clears the session when the article was deleted',
        () async {
      SharedPreferences.setMockInitialValues({
        'tts_session_article_id': 'deleted-article',
        'tts_session_segment': 0,
      });

      final tts = TtsService();
      await tts.restoreSession(repository);

      expect(tts.article, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_session_article_id'), isNull);
      expect(prefs.getInt('tts_session_segment'), isNull);
    });

    test('restoreSession is a no-op when no session was saved', () async {
      SharedPreferences.setMockInitialValues({});

      final tts = TtsService();
      await tts.restoreSession(repository);

      expect(tts.article, isNull);
      expect(tts.hasContent, isFalse);
    });

    test('dismiss unloads the article and forgets the saved session',
        () async {
      SharedPreferences.setMockInitialValues({
        'tts_session_article_id': article.id,
        'tts_session_segment': 1,
      });

      final tts = TtsService();
      await tts.restoreSession(repository);
      expect(tts.article?.id, article.id);

      await tts.dismiss();

      expect(tts.article, isNull);
      expect(tts.hasContent, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_session_article_id'), isNull);
      expect(prefs.getInt('tts_session_segment'), isNull);
    });
  });

  group('TtsService seeking (scrub)', () {
    // The TTS engine isn't available in tests; stub its platform channel so
    // loading and seeking never touches the device.
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    });

    test('seekToChar moves the cursor without playing when idle', () async {
      SharedPreferences.setMockInitialValues({});
      final tts = TtsService();
      await tts.loadArticle(article);
      expect(tts.segmentIndex, 0);

      // Seek into the third segment (index 2).
      final target = tts.segments[2].start + 1;
      await tts.seekToChar(target);

      expect(tts.segmentIndex, 2);
      expect(tts.isPlaying, isFalse);
      expect(tts.isPaused, isFalse);
    });

    test('seekToChar while paused stays paused', () async {
      SharedPreferences.setMockInitialValues({});
      final tts = TtsService();
      await tts.loadArticle(article);
      await tts.play();
      await tts.pause();
      expect(tts.isPaused, isTrue);

      final target = tts.segments[1].start + 1;
      await tts.seekToChar(target);

      expect(tts.segmentIndex, 1);
      expect(tts.isPaused, isTrue);
      expect(tts.isPlaying, isFalse);
    });

    test('seekToChar while playing jumps and keeps playing', () async {
      SharedPreferences.setMockInitialValues({});
      final tts = TtsService();
      await tts.loadArticle(article);
      await tts.play();
      expect(tts.isPlaying, isTrue);

      final target = tts.segments[3].start + 1;
      await tts.seekToChar(target);

      expect(tts.segmentIndex, 3);
      expect(tts.isPlaying, isTrue);
    });

    test('seekToChar past the end clamps to the last segment', () async {
      SharedPreferences.setMockInitialValues({});
      final tts = TtsService();
      await tts.loadArticle(article);

      await tts.seekToChar(article.textContent.length + 500);

      expect(tts.segmentIndex, tts.segments.length - 1);
    });
  });
}
