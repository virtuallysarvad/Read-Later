import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/article.dart';
import '../services/article_extractor.dart';
import 'app_database.dart';

/// Holds all saved articles in memory and persists them to SQLite.
///
/// Listen to it with `context.watch`/`context.read` via ChangeNotifierProvider.
class ArticleRepository extends ChangeNotifier {
  final ArticleFetcher _fetcher;
  final String? _databasePath;
  final Uuid _uuid = const Uuid();

  Database? _db;
  List<Article> _articles = [];
  bool _initialized = false;

  ArticleRepository({ArticleFetcher? fetcher, String? databasePath})
      : _fetcher = fetcher ?? ArticleExtractor(),
        _databasePath = databasePath;

  /// Articles sorted by save time, newest first.
  List<Article> get all => List.unmodifiable(_articles);

  List<Article> get unread =>
      _articles.where((a) => a.status == ArticleStatus.unread).toList();

  List<Article> get archived =>
      _articles.where((a) => a.status == ArticleStatus.archived).toList();

  List<Article> get favorites =>
      _articles.where((a) => a.isFavorite).toList();

  /// Articles that can be played: non-archived, with extracted text, newest
  /// first. This is the order the mini player's previous/next buttons use.
  List<Article> get listenable => _articles
      .where(
        (a) => a.status != ArticleStatus.archived && a.textContent.isNotEmpty,
      )
      .toList();

  Article? byId(String id) {
    for (final a in _articles) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _db = await AppDatabase.open(path: _databasePath);
    final rows = await _db!.query('articles', orderBy: 'saved_at DESC');
    _articles = rows.map(Article.fromDbMap).toList();
    _initialized = true;
    notifyListeners();
  }

  /// Fetches and extracts [url], then saves it.
  ///
  /// Re-saving an existing URL updates the content and marks it unread again
  /// (Pocket-style), keeping favorites intact.
  Future<Article> addFromUrl(String url) async {
    final result = await _fetcher.fetchAndExtract(url);
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedUrl = ArticleExtractor.normalizeUrl(url);

    final existingIndex = _articles.indexWhere(
      (a) => a.url == normalizedUrl,
    );
    Article article;
    if (existingIndex >= 0) {
      final existing = _articles[existingIndex];
      article = existing.copyWith(
        title: result.title,
        siteName: result.siteName,
        byline: result.byline,
        excerpt: result.excerpt,
        imageUrl: result.imageUrl,
        faviconUrl: result.faviconUrl,
        publishedTime: result.publishedTime,
        contentHtml: result.contentHtml,
        textContent: result.textContent,
        wordCount: _wordCount(result.textContent),
        readingTimeMinutes: _readingTimeMinutes(result.textContent),
        status: ArticleStatus.unread,
        hasContent: result.hasContent,
        readProgress: 0,
        listenPosition: 0,
        listenSegment: 0,
      );
      _articles[existingIndex] = article;
    } else {
      article = Article(
        id: _uuid.v4(),
        url: normalizedUrl,
        title: result.title,
        siteName: result.siteName,
        byline: result.byline,
        excerpt: result.excerpt,
        imageUrl: result.imageUrl,
        faviconUrl: result.faviconUrl,
        publishedTime: result.publishedTime,
        contentHtml: result.contentHtml,
        textContent: result.textContent,
        wordCount: _wordCount(result.textContent),
        readingTimeMinutes: _readingTimeMinutes(result.textContent),
        savedAt: now,
        updatedAt: now,
        hasContent: result.hasContent,
      );
      _articles.insert(0, article);
    }

    await _upsert(article);
    notifyListeners();
    return article;
  }

  Future<void> updateArticle(Article article) async {
    final index = _articles.indexWhere((a) => a.id == article.id);
    if (index >= 0) {
      _articles[index] = article;
      await _upsert(article);
      notifyListeners();
    }
  }

  Future<void> deleteArticle(String id) async {
    await _db?.delete('articles', where: 'id = ?', whereArgs: [id]);
    _articles.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  Future<void> setFavorite(String id, bool value) async {
    final article = byId(id);
    if (article == null) return;
    await updateArticle(article.copyWith(isFavorite: value));
  }

  Future<void> setStatus(String id, String status) async {
    final article = byId(id);
    if (article == null) return;
    await updateArticle(article.copyWith(status: status));
  }

  Future<void> setReadProgress(String id, double fraction) async {
    final article = byId(id);
    if (article == null) return;
    final clamped = fraction.clamp(0.0, 1.0);
    if ((article.readProgress - clamped).abs() < 0.01) return;
    await updateArticle(article.copyWith(readProgress: clamped));
  }

  Future<void> setListenProgress(String id, int position, int segment) async {
    final article = byId(id);
    if (article == null) return;
    await updateArticle(
      article.copyWith(listenPosition: position, listenSegment: segment),
    );
  }

  Future<void> clearAll() async {
    await _db?.delete('articles');
    _articles = [];
    notifyListeners();
  }

  /// Closes the underlying database and resets in-memory state. Useful for
  /// test teardown (sqflite caches one instance per path, so closing lets the
  /// next open of the same path start fresh).
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _initialized = false;
    _articles = [];
  }

  /// Merges a backup (e.g. from Drive) into the local store.
  ///
  /// For each incoming article: if the same URL exists locally, keep whichever
  /// was modified more recently; otherwise insert. Local-only articles are
  /// kept, so a restore never destroys data.
  Future<void> mergeBackup(List<Article> incoming) async {
    final byUrl = <String, Article>{for (final a in _articles) a.url: a};
    final merged = <Article>[];

    for (final remote in incoming) {
      final local = byUrl[remote.url];
      if (local == null) {
        byUrl[remote.url] = remote;
        merged.add(remote);
      } else if (remote.updatedAt > local.updatedAt) {
        byUrl[remote.url] = remote;
        merged.add(remote);
      }
    }

    for (final a in merged) {
      await _upsert(a);
    }
    _articles = byUrl.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    notifyListeners();
  }

  Future<void> _upsert(Article article) async {
    await _db?.insert(
      'articles',
      article.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static int _wordCount(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  static int _readingTimeMinutes(String text) {
    final minutes = (_wordCount(text) / 220).ceil();
    return minutes < 1 ? 1 : minutes;
  }
}
