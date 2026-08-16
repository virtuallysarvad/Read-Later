/// Status of a saved article, mirroring Pocket's list model.
class ArticleStatus {
  static const String unread = 'unread';
  static const String archived = 'archived';
}

/// A saved article with extracted, ad-free content.
///
/// Immutable by design; use [copyWith] to produce updated instances.
class Article {
  final String id;
  final String url;

  String title;
  String? siteName;
  String? byline;
  String? excerpt;
  String? imageUrl;
  String? faviconUrl;
  String? publishedTime;

  /// Clean, readability-processed HTML (no ads / navigation).
  String contentHtml;

  /// Plain text version of the article, used for podcast-style listening.
  String textContent;

  int wordCount;
  int readingTimeMinutes;

  /// Epoch milliseconds when the article was first saved.
  final int savedAt;

  /// Epoch milliseconds of the last modification.
  int updatedAt;

  /// One of [ArticleStatus].
  String status;

  bool isFavorite;

  /// Whether extraction produced readable content.
  bool hasContent;

  /// Fraction (0..1) of the article scrolled while reading.
  double readProgress;

  /// Character offset into [textContent] where listening left off.
  int listenPosition;

  /// Index of the last TTS segment played.
  int listenSegment;

  Article({
    required this.id,
    required this.url,
    required this.title,
    this.siteName,
    this.byline,
    this.excerpt,
    this.imageUrl,
    this.faviconUrl,
    this.publishedTime,
    this.contentHtml = '',
    this.textContent = '',
    this.wordCount = 0,
    this.readingTimeMinutes = 0,
    required this.savedAt,
    required this.updatedAt,
    this.status = ArticleStatus.unread,
    this.isFavorite = false,
    this.hasContent = false,
    this.readProgress = 0,
    this.listenPosition = 0,
    this.listenSegment = 0,
  });

  Article copyWith({
    String? title,
    String? siteName,
    String? byline,
    String? excerpt,
    String? imageUrl,
    String? faviconUrl,
    String? publishedTime,
    String? contentHtml,
    String? textContent,
    int? wordCount,
    int? readingTimeMinutes,
    int? updatedAt,
    String? status,
    bool? isFavorite,
    bool? hasContent,
    double? readProgress,
    int? listenPosition,
    int? listenSegment,
  }) {
    return Article(
      id: id,
      url: url,
      title: title ?? this.title,
      siteName: siteName ?? this.siteName,
      byline: byline ?? this.byline,
      excerpt: excerpt ?? this.excerpt,
      imageUrl: imageUrl ?? this.imageUrl,
      faviconUrl: faviconUrl ?? this.faviconUrl,
      publishedTime: publishedTime ?? this.publishedTime,
      contentHtml: contentHtml ?? this.contentHtml,
      textContent: textContent ?? this.textContent,
      wordCount: wordCount ?? this.wordCount,
      readingTimeMinutes: readingTimeMinutes ?? this.readingTimeMinutes,
      savedAt: savedAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      hasContent: hasContent ?? this.hasContent,
      readProgress: readProgress ?? this.readProgress,
      listenPosition: listenPosition ?? this.listenPosition,
      listenSegment: listenSegment ?? this.listenSegment,
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'site_name': siteName,
      'byline': byline,
      'excerpt': excerpt,
      'image_url': imageUrl,
      'favicon_url': faviconUrl,
      'published_time': publishedTime,
      'content_html': contentHtml,
      'text_content': textContent,
      'word_count': wordCount,
      'reading_time_minutes': readingTimeMinutes,
      'saved_at': savedAt,
      'updated_at': updatedAt,
      'status': status,
      'is_favorite': isFavorite ? 1 : 0,
      'has_content': hasContent ? 1 : 0,
      'read_progress': readProgress,
      'listen_position': listenPosition,
      'listen_segment': listenSegment,
    };
  }

  factory Article.fromDbMap(Map<String, Object?> map) {
    return Article(
      id: map['id'] as String,
      url: map['url'] as String,
      title: map['title'] as String,
      siteName: map['site_name'] as String?,
      byline: map['byline'] as String?,
      excerpt: map['excerpt'] as String?,
      imageUrl: map['image_url'] as String?,
      faviconUrl: map['favicon_url'] as String?,
      publishedTime: map['published_time'] as String?,
      contentHtml: (map['content_html'] as String?) ?? '',
      textContent: (map['text_content'] as String?) ?? '',
      wordCount: (map['word_count'] as int?) ?? 0,
      readingTimeMinutes: (map['reading_time_minutes'] as int?) ?? 0,
      savedAt: map['saved_at'] as int,
      updatedAt: map['updated_at'] as int,
      status: (map['status'] as String?) ?? ArticleStatus.unread,
      // Backups store real booleans; the DB stores 0/1 ints.
      isFavorite: map['is_favorite'] is bool
          ? map['is_favorite'] as bool
          : (map['is_favorite'] as int?) == 1,
      hasContent: map['has_content'] is bool
          ? map['has_content'] as bool
          : (map['has_content'] as int?) == 1,
      readProgress: (map['read_progress'] as num?)?.toDouble() ?? 0,
      listenPosition: (map['listen_position'] as int?) ?? 0,
      listenSegment: (map['listen_segment'] as int?) ?? 0,
    );
  }

  /// JSON used by the Google Drive backup file.
  Map<String, dynamic> toJson() {
    final map = toDbMap();
    // Convert booleans back to real booleans for a readable backup file.
    map['is_favorite'] = isFavorite;
    map['has_content'] = hasContent;
    return map;
  }

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article.fromDbMap(Map<String, Object?>.from(json));
  }

  /// Plain-text preview used on cards.
  String get subtitle {
    final parts = <String>[
      if (siteName != null && siteName!.isNotEmpty) siteName!,
      if (readingTimeMinutes > 0) '$readingTimeMinutes min read',
    ];
    return parts.join(' · ');
  }
}
