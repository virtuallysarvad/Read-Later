import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_later/services/article_extractor.dart';

const _readableHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Deep Work Review</title>
  <meta property="og:site_name" content="Example News"/>
  <meta name="description" content="A thoughtful review of the book."/>
  <link rel="icon" href="/favicon.ico"/>
</head>
<body>
  <nav><a href="/">Home</a> <a href="/ads">Sponsored</a></nav>
  <div class="ad-banner">BUY NOW</div>
  <article>
    <h1>Deep Work: a review</h1>
    <p>Deep work is the ability to focus without distraction.</p>
    <p>Cal Newport argues that <a href="/related">focus</a> is a superpower.
       <img src="/img/cover.jpg" srcset="/img/cover.jpg 1x, /img/cover2x.jpg 2x"/></p>
    <p>This is a third paragraph with plenty of readable text to extract.</p>
  </article>
  <footer>Copyright stuff and links.</footer>
</body>
</html>
''';

void main() {
  group('fetchAndExtract', () {
    test('extracts clean content and strips ads/navigation', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/article');
        return http.Response.bytes(
          utf8.encode(_readableHtml),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final extractor = ArticleExtractor(client: client);

      final result =
          await extractor.fetchAndExtract('example.com/article');

      expect(result.hasContent, isTrue);
      expect(result.title, contains('Deep Work'));
      expect(result.siteName, 'Example News');
      expect(result.contentHtml, isNot(contains('BUY NOW')));
      expect(result.contentHtml, isNot(contains('Sponsored')));
      expect(result.textContent, contains('focus without distraction'));
      // Relative image URLs are absolutized against the article URL.
      expect(result.contentHtml, contains('https://example.com/img/cover.jpg'));
      expect(result.imageUrl, 'https://example.com/img/cover.jpg');
      expect(result.faviconUrl, 'https://example.com/favicon.ico');
      // srcset is stripped.
      expect(result.contentHtml, isNot(contains('cover2x')));
    });

    test('falls back to metadata when the page is not readable', () async {
      final client = MockClient((request) async => http.Response(
          '<html><head><title>Just a page</title></head>'
          '<body></body></html>',
          200));
      final extractor = ArticleExtractor(client: client);

      final result = await extractor.fetchAndExtract('https://example.com/x');

      expect(result.hasContent, isFalse);
      expect(result.title, 'Just a page');
      expect(result.contentHtml, isEmpty);
    });

    test('throws a friendly error for network failures', () async {
      final client = MockClient((request) async => throw http.ClientException(
          'Connection refused', request.url));
      final extractor = ArticleExtractor(client: client);

      expect(
        () => extractor.fetchAndExtract('https://example.com/x'),
        throwsA(isA<ExtractException>()),
      );
    });

    test('throws a friendly error for HTTP errors', () async {
      final client = MockClient(
          (request) async => http.Response('gone', 404));
      final extractor = ArticleExtractor(client: client);

      expect(
        () => extractor.fetchAndExtract('https://example.com/x'),
        throwsA(isA<ExtractException>()),
      );
    });
  });

  group('normalizeUrl', () {
    test('adds https scheme when missing', () {
      expect(ArticleExtractor.normalizeUrl('example.com/a'),
          'https://example.com/a');
      expect(ArticleExtractor.normalizeUrl('  example.com/a  '),
          'https://example.com/a');
    });

    test('keeps existing schemes', () {
      expect(ArticleExtractor.normalizeUrl('http://example.com/a'),
          'http://example.com/a');
      expect(ArticleExtractor.normalizeUrl('https://example.com/a'),
          'https://example.com/a');
    });

    test('rejects empty input', () {
      expect(() => ArticleExtractor.normalizeUrl(''),
          throwsA(isA<ExtractException>()));
    });
  });
}
