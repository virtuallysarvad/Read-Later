import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_later/data/article_repository.dart';
import 'package:read_later/models/article.dart';
import 'package:read_later/services/article_extractor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _inMemory = ':memory:';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ArticleRepository repository;

  setUp(() {
    // Each test gets a fresh in-memory database.
    repository = ArticleRepository(
      fetcher: _FakeExtractor(),
      databasePath: _inMemory,
    );
  });

  Article sample(String url, {String id = 'a1', String? title}) => Article(
        id: id,
        url: url,
        title: title ?? 'Sample article',
        contentHtml: '<p>Hello</p>',
        textContent: 'Hello world. This is content.',
        savedAt: 1000,
        updatedAt: 1000,
        hasContent: true,
      );

  test('addFromUrl saves an article', () async {
    await repository.init();
    final article = await repository.addFromUrl('https://example.com/x');

    expect(repository.all, hasLength(1));
    expect(repository.all.first.title, 'Fetched title');
    expect(repository.all.first.hasContent, isTrue);
    expect(repository.all.first.url, 'https://example.com/x');
    expect(article.id, isNotEmpty);
  });

  test('re-saving the same URL updates instead of duplicating', () async {
    await repository.init();
    await repository.addFromUrl('https://example.com/x');
    await repository.addFromUrl('https://example.com/x');

    expect(repository.all, hasLength(1));
    expect(repository.all.first.status, ArticleStatus.unread);
  });

  test('re-saving marks an archived article unread again', () async {
    await repository.init();
    final article = await repository.addFromUrl('https://example.com/x');
    await repository.setStatus(article.id, ArticleStatus.archived);
    expect(repository.all.first.status, ArticleStatus.archived);

    await repository.addFromUrl('https://example.com/x');
    expect(repository.all.first.status, ArticleStatus.unread);
  });

  test('favorite and progress updates persist', () async {
    await repository.init();
    final article = await repository.addFromUrl('https://example.com/x');

    await repository.setFavorite(article.id, true);
    await repository.setReadProgress(article.id, 0.5);
    await repository.setListenProgress(article.id, 1234, 7);

    final updated = repository.byId(article.id)!;
    expect(updated.isFavorite, isTrue);
    expect(updated.readProgress, closeTo(0.5, 0.001));
    expect(updated.listenPosition, 1234);
    expect(updated.listenSegment, 7);
  });

  test('deleteArticle removes the row', () async {
    await repository.init();
    final article = await repository.addFromUrl('https://example.com/x');
    await repository.deleteArticle(article.id);
    expect(repository.all, isEmpty);
  });

  test('mergeBackup merges by URL, keeping newer versions', () async {
    await repository.init();
    await repository.addFromUrl('https://example.com/local'); // local copy

    final older = sample('https://example.com/local',
        id: 'remote', title: 'Old title')
      ..updatedAt = 1; // older than the freshly saved local copy
    final brandNew = sample('https://example.com/new',
        id: 'new', title: 'New article')
      ..updatedAt = 2000;
    final backup = [older, brandNew];

    await repository.mergeBackup(backup);

    expect(repository.all, hasLength(2));
    final localMerged = repository.all
        .firstWhere((a) => a.url == 'https://example.com/local');
    expect(localMerged.title, 'Fetched title',
        reason: 'local copy wins when newer');
    final newArticle = repository.byId('new');
    expect(newArticle, isNotNull);
    expect(newArticle!.title, 'New article');
  });

  test('articles serialize to JSON for Drive backup and back', () {
    final article = sample('https://example.com/x');
    final decoded = Article.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(article.toJson())) as Map,
      ),
    );
    expect(decoded.id, article.id);
    expect(decoded.url, article.url);
    expect(decoded.title, article.title);
    expect(decoded.isFavorite, article.isFavorite);
  });
}

class _FakeExtractor implements ArticleFetcher {
  @override
  Future<ExtractResult> fetchAndExtract(String url) async {
    return ExtractResult(
      title: 'Fetched title',
      contentHtml: '<p>Fetched content</p>',
      textContent: 'Fetched content here.',
      siteName: 'Example',
      hasContent: true,
    );
  }
}
