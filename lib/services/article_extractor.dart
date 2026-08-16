import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:reader_mode/reader_mode.dart';

/// Result of fetching and extracting a URL.
class ExtractResult {
  final String title;
  final String contentHtml;
  final String textContent;
  final String? excerpt;
  final String? byline;
  final String? siteName;
  final String? imageUrl;
  final String? faviconUrl;
  final String? publishedTime;
  final bool hasContent;

  ExtractResult({
    required this.title,
    required this.contentHtml,
    required this.textContent,
    this.excerpt,
    this.byline,
    this.siteName,
    this.imageUrl,
    this.faviconUrl,
    this.publishedTime,
    required this.hasContent,
  });
}

/// Thrown when a URL cannot be fetched or parsed.
class ExtractException implements Exception {
  final String message;
  ExtractException(this.message);

  @override
  String toString() => message;
}

/// Payload passed to the background isolate (must be plain data).
class _ExtractPayload {
  final String html;
  final String baseUri;
  _ExtractPayload(this.html, this.baseUri);
}

/// Runs Mozilla's Readability (pure Dart port) on raw HTML.
/// Top-level so it can run inside `compute`.
Article? _runReadability(_ExtractPayload payload) {
  try {
    return parse(
      payload.html,
      parser: ParserType.html,
      baseUri: payload.baseUri,
    );
  } catch (_) {
    return null;
  }
}

/// Interface for fetching + extracting articles (implemented by
/// [ArticleExtractor], faked in tests).
abstract class ArticleFetcher {
  Future<ExtractResult> fetchAndExtract(String url);
}

/// Fetches a URL and extracts clean, ad-free article content on-device.
class ArticleExtractor implements ArticleFetcher {
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36 '
      'ReadLater/1.0';

  final http.Client _client;

  ArticleExtractor({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches [url] and extracts readable content.
  ///
  /// Never throws for unreadable pages: it falls back to metadata (title,
  /// site name, image) with `hasContent == false` so the URL can still be
  /// saved, Pocket-style. Throws [ExtractException] for network errors.
  @override
  Future<ExtractResult> fetchAndExtract(String url) async {
    final normalized = normalizeUrl(url);
    final uri = Uri.parse(normalized);

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw ExtractException('Could not reach $normalized. '
          'Check your connection and try again.');
    }

    if (response.statusCode != 200) {
      throw ExtractException(
        'The page returned an error (HTTP ${response.statusCode}).',
      );
    }

    final html = _decodeHtml(response);

    // Readability runs in a background isolate so the UI stays responsive.
    final article = await compute(
      _runReadability,
      _ExtractPayload(html, normalized),
    );

    final textContent = article?.textContent.trim() ?? '';
    if (article != null && textContent.isNotEmpty) {
      final content = _absolutizeUrls(article.content, normalized);
      return ExtractResult(
        title: _cleanTitle(article.title, normalized),
        contentHtml: content,
        textContent: textContent,
        excerpt: _clean(article.excerpt) ?? _excerptFromText(textContent),
        byline: _clean(article.byline),
        siteName: _clean(article.siteName),
        imageUrl: _firstImageUrl(html, normalized),
        faviconUrl: _faviconUrl(html, normalized),
        publishedTime: _clean(article.publishedTime),
        hasContent: true,
      );
    }

    // Fallback: keep the link even if it isn't readable.
    final doc = html_parser.parse(html);
    return ExtractResult(
      title: _fallbackTitle(doc, normalized),
      contentHtml: '',
      textContent: '',
      siteName: _meta(doc, 'og:site_name'),
      excerpt: _meta(doc, 'og:description') ?? _meta(doc, 'description'),
      imageUrl: _meta(doc, 'og:image'),
      faviconUrl: _faviconUrl(html, normalized),
      publishedTime: _meta(doc, 'article:published_time'),
      hasContent: false,
    );
  }

  /// Prepends a scheme when missing so `Uri.parse` always succeeds.
  static String normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ExtractException('Please enter a URL.');
    }
    if (!trimmed.contains('://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  String _decodeHtml(http.Response response) {
    final bytes = response.bodyBytes;
    final charset = _charsetFromHeaders(response.headers);
    if (charset != null) {
      try {
        return _decode(bytes, charset);
      } catch (_) {
        // fall through to sniffing
      }
    }
    final sniffed = _charsetFromHtml(bytes);
    if (sniffed != null) {
      try {
        return _decode(bytes, sniffed);
      } catch (_) {
        // fall through
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _decode(Uint8List bytes, String charset) {
    if (charset.toLowerCase() == 'utf-8' || charset.toLowerCase() == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (charset.toLowerCase() == 'latin-1' ||
        charset.toLowerCase() == 'iso-8859-1') {
      return latin1.decode(bytes);
    }
    // Fall back to UTF-8; most modern pages are UTF-8 even when headers lie.
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _charsetFromHeaders(Map<String, String> headers) {
    final contentType = headers['content-type'];
    if (contentType == null) return null;
    final match = RegExp(r'charset=([^; ]+)', caseSensitive: false)
        .firstMatch(contentType);
    return match?.group(1)?.replaceAll('"', '').replaceAll("'", '');
  }

  String? _charsetFromHtml(Uint8List bytes) {
    final head = utf8.decode(
      bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes,
      allowMalformed: true,
    );
    final match = RegExp(
      r'<meta[^>]+charset=([^ >]+)',
      caseSensitive: false,
    ).firstMatch(head);
    return match?.group(1)?.replaceAll('"', '').replaceAll("'", '');
  }

  String _cleanTitle(String title, String fallback) {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final host = Uri.parse(fallback).host;
    return host.isEmpty ? fallback : host;
  }

  String? _clean(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? _excerptFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= 280) return trimmed;
    final cut = trimmed.substring(0, 277).trimRight();
    return '$cut…';
  }

  String _fallbackTitle(html_dom.Document doc, String url) {
    final og = _meta(doc, 'og:title');
    if (og != null) return og;
    final titleTag = doc.querySelector('title')?.text.trim();
    if (titleTag != null && titleTag.isNotEmpty) return titleTag;
    return Uri.parse(url).host;
  }

  String? _meta(html_dom.Document doc, String property) {
    final el = doc.querySelector(
      'meta[property="$property"], meta[name="$property"]',
    );
    return _clean(el?.attributes['content']);
  }

  String? _firstImageUrl(String html, String base) {
    final doc = html_parser.parse(html);
    final img = doc.querySelector(
      'meta[property="og:image"], img[src]',
    );
    if (img == null) return null;
    final src = img.attributes['content'] ?? img.attributes['src'];
    if (src == null || src.isEmpty) return null;
    return _resolve(src, base);
  }

  String? _faviconUrl(String html, String base) {
    final doc = html_parser.parse(html);
    final icon = doc.querySelector('link[rel~="icon"]');
    final href = icon?.attributes['href'];
    if (href == null || href.isEmpty) return null;
    return _resolve(href, base);
  }

  /// Resolves relative `src`/`href` attributes against the article URL and
  /// strips `srcset`/`picture` sources, since images are rendered from `src`.
  String _absolutizeUrls(String contentHtml, String base) {
    final doc = html_parser.parseFragment(contentHtml);
    for (final img in doc.querySelectorAll('img')) {
      final src = img.attributes['src'];
      if (src != null) {
        img.attributes['src'] = _resolve(src, base);
      }
      img.attributes.remove('srcset');
      img.attributes.remove('data-src');
      img.attributes.remove('data-srcset');
    }
    for (final source in doc.querySelectorAll('source')) {
      source.remove();
    }
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'];
      if (href != null) {
        a.attributes['href'] = _resolve(href, base);
      }
    }
    for (final video in doc.querySelectorAll('video')) {
      final poster = video.attributes['poster'];
      if (poster != null) {
        video.attributes['poster'] = _resolve(poster, base);
      }
    }
    return doc.outerHtml;
  }

  String _resolve(String href, String base) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return href;
    if (trimmed.startsWith('data:') ||
        trimmed.startsWith('javascript:') ||
        trimmed.startsWith('mailto:') ||
        trimmed.startsWith('tel:') ||
        trimmed.startsWith('#')) {
      return trimmed;
    }
    try {
      return Uri.parse(base).resolve(trimmed).toString();
    } catch (_) {
      return trimmed;
    }
  }
}
