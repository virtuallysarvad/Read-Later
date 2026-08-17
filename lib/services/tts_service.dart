import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../utils/text_chunker.dart';

/// Podcast-style playback of article text using the Android TTS engine.
///
/// Text is split into segments; each segment is spoken, then the next one
/// starts, mirroring how Pocket's "Listen" feature plays articles. Position,
/// speed and language are persisted.
class TtsService extends ChangeNotifier {
  static const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const String defaultLanguage = 'en-US';

  /// SharedPreferences keys for the persisted listening session, so the
  /// player survives an app restart and can be resumed where it left off.
  static const String _sessionArticleKey = 'tts_session_article_id';
  static const String _sessionSegmentKey = 'tts_session_segment';

  static const List<({String code, String label})> languageOptions = [
    (code: 'en-US', label: 'English (US)'),
    (code: 'en-GB', label: 'English (UK)'),
    (code: 'hi-IN', label: 'Hindi'),
    (code: 'es-ES', label: 'Spanish'),
    (code: 'fr-FR', label: 'French'),
    (code: 'de-DE', label: 'German'),
    (code: 'pt-BR', label: 'Portuguese (BR)'),
    (code: 'it-IT', label: 'Italian'),
    (code: 'ja-JP', label: 'Japanese'),
    (code: 'zh-CN', label: 'Chinese (Simplified)'),
  ];

  final FlutterTts _tts = FlutterTts();

  Article? _article;
  List<TtsSegment> _segments = [];
  int _segmentIndex = 0;
  bool _playing = false;
  bool _paused = false;
  double _speed = 1.0;
  String _language = defaultLanguage;
  bool _ready = false;

  /// Called whenever listening progress should be persisted.
  Future<void> Function(Article article, int position, int segment)?
      onProgress;

  Article? get article => _article;
  List<TtsSegment> get segments => _segments;
  int get segmentIndex => _segmentIndex;
  int get currentParagraph =>
      _segments.isEmpty ? 0 : _segments[_segmentIndex].paragraphIndex;
  bool get isPlaying => _playing;
  bool get isPaused => _paused;
  bool get hasContent => _segments.isNotEmpty;
  double get speed => _speed;
  String get language => _language;

  /// Character offset into the article text.
  int get currentPosition =>
      _segments.isEmpty ? 0 : _segments[_segmentIndex].start;

  int get totalLength => _article?.textContent.length ?? 0;

  double get progressFraction =>
      totalLength == 0 ? 0 : (currentPosition / totalLength).clamp(0.0, 1.0);

  /// Rough time estimate based on ~1100 characters of speech per minute.
  String get progressLabel {
    final total = totalLength;
    if (total == 0) return '';
    String fmt(int seconds) {
      final m = (seconds ~/ 60).toString();
      final s = (seconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    const cps = 18.3; // characters per second at normal reading speed
    final elapsed = (currentPosition / cps).round();
    final duration = (total / cps).round();
    return '${fmt(elapsed)} / ${fmt(duration)}';
  }

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    final prefs = await SharedPreferences.getInstance();
    _speed = (prefs.getDouble('tts_speed') ?? 1.0).clamp(0.5, 2.0);
    _language = prefs.getString('tts_language') ?? defaultLanguage;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_engineRate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(_onSegmentComplete);
    _tts.setErrorHandler((msg) {
      _playing = false;
      _paused = false;
      notifyListeners();
    });
  }

  /// Loads [article] for listening. If an article was already loaded, stops
  /// playback first. Does not auto-play.
  Future<void> loadArticle(Article article) async {
    await init();
    if (_playing || _paused) {
      await stop();
    }
    _article = article;
    _segments = TextChunker.chunk(article.textContent);
    _segmentIndex = _clampSegment(article.listenSegment);
    notifyListeners();
  }

  Future<void> play() async {
    await init();
    if (_article == null || _segments.isEmpty) return;
    if (_playing) return;
    _playing = true;
    _paused = false;
    // Update the play/pause buttons immediately; don't wait for the engine.
    notifyListeners();
    // Android 13+ needs runtime permission for the media notification. Fire
    // the request without blocking playback start (no-op if already granted).
    if (Platform.isAndroid) {
      unawaited(Permission.notification.request());
    }
    // Android's pause/resume is unreliable across engines; restart the
    // current segment for a consistent experience.
    await _speakSegment(_segmentIndex);
  }

  Future<void> pause() async {
    if (!_playing) return;
    _playing = false;
    _paused = true;
    // Flip the buttons before the engine acknowledges the pause.
    notifyListeners();
    try {
      await _tts.pause();
    } catch (_) {
      // Some TTS engines don't support pause; stop as a fallback.
      await _tts.stop();
    }
    await _saveProgress();
  }

  Future<void> stop() async {
    final wasActive = _playing || _paused;
    _playing = false;
    _paused = false;
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore engine errors while stopping.
    }
    if (wasActive) {
      await _saveProgress();
    }
    notifyListeners();
  }

  /// Skips to the next segment (or stops at the end).
  Future<void> skipForward() async {
    if (_segments.isEmpty) return;
    if (_segmentIndex + 1 < _segments.length) {
      await _speakSegment(_segmentIndex + 1);
      notifyListeners();
    } else if (_playing) {
      await stop();
    }
  }

  Future<void> skipBackward() async {
    if (_segments.isEmpty) return;
    if (_segmentIndex > 0) {
      await _speakSegment(_segmentIndex - 1);
    } else {
      await _speakSegment(0);
    }
    notifyListeners();
  }

  /// Jumps to the segment containing character offset [char] and plays it
  /// (used by the media notification's seek bar).
  Future<void> playAtChar(int char) async {
    if (_segments.isEmpty) return;
    final target = _segmentAtChar(char);
    _playing = true;
    _paused = false;
    await _speakSegment(target);
    notifyListeners();
  }

  /// Jumps to the segment containing character offset [char] without changing
  /// the play/pause state (used by the scrub bars). Playback continues if it
  /// was playing; stays paused or idle otherwise.
  Future<void> seekToChar(int char) async {
    if (_segments.isEmpty) return;
    final target = _segmentAtChar(char);
    if (_playing) {
      // Keep playing from the new position.
      await _speakSegment(target);
    } else {
      // Paused or idle: move the cursor without starting the engine.
      try {
        await _tts.stop();
      } catch (_) {
        // Ignore engine errors while seeking.
      }
      _segmentIndex = target;
      await _saveProgress();
    }
    notifyListeners();
  }

  /// The index of the segment containing character offset [char] (clamped to
  /// the last segment when [char] is past the end of the text).
  int _segmentAtChar(int char) {
    var target = 0;
    for (var i = 0; i < _segments.length; i++) {
      if (_segments[i].start <= char) {
        target = i;
      } else {
        break;
      }
    }
    return target;
  }

  /// Jumps to the first segment of [paragraphIndex] (used when tapping a
  /// paragraph in the listening view).
  Future<void> playParagraph(int paragraphIndex) async {
    if (_segments.isEmpty) return;
    final index = _segments.indexWhere(
      (s) => s.paragraphIndex >= paragraphIndex,
    );
    final target = index < 0 ? _segments.length - 1 : index;
    _playing = true;
    _paused = false;
    await _speakSegment(target);
    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 2.0);
    await _tts.setSpeechRate(_engineRate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_speed', _speed);
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    _language = language;
    await _tts.setLanguage(language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_language', language);
    notifyListeners();
  }

  /// Cycles through the available speeds.
  Future<void> cycleSpeed() async {
    final next = speedOptions[
        (speedOptions.indexOf(_speed) + 1) % speedOptions.length];
    await setSpeed(next);
  }

  /// Loads and plays the next article in the library, wrapping around to the
  /// first (Spotify-style). Archived articles and articles without text are
  /// excluded from the queue; each article resumes from where it left off.
  Future<void> playNextArticle(ArticleRepository repository) =>
      _playSiblingArticle(repository, 1);

  /// Loads and plays the previous article in the library, wrapping around to
  /// the last.
  Future<void> playPreviousArticle(ArticleRepository repository) =>
      _playSiblingArticle(repository, -1);

  Future<void> _playSiblingArticle(
    ArticleRepository repository,
    int delta,
  ) async {
    final queue = repository.listenable;
    if (queue.isEmpty) return;
    final current = _article;
    var index = current == null
        ? -1
        : queue.indexWhere((a) => a.id == current.id);
    if (index < 0) {
      // The current article isn't in the queue (e.g. it was archived while
      // listening); start from the top or the bottom of the queue.
      index = delta > 0 ? -1 : queue.length;
    }
    // Double-mod keeps the index positive when wrapping backwards.
    final target =
        queue[((index + delta) % queue.length + queue.length) % queue.length];
    await loadArticle(target);
    await play();
    notifyListeners();
  }

  /// Stops playback and unloads the article so the mini player hides.
  Future<void> dismiss() async {
    await stop();
    _article = null;
    _segments = [];
    _segmentIndex = 0;
    // The session is over; forget it so it isn't restored on the next launch.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionArticleKey);
    await prefs.remove(_sessionSegmentKey);
    notifyListeners();
  }

  /// flutter_tts maps its rate so that Android's normal speed (1.0) equals a
  /// flutter_tts value of 0.5 (its Android plugin multiplies by 2). Halve the
  /// user-facing speed so 1.0x really means normal speed.
  double get _engineRate => _speed / 2;

  Future<void> _speakSegment(int index) async {
    if (index < 0 || index >= _segments.length) return;
    _segmentIndex = index;
    await _tts.speak(_segments[index].text);
    await _saveProgress();
  }

  void _onSegmentComplete() {
    if (!_playing) return;
    if (_segmentIndex + 1 < _segments.length) {
      _speakSegment(_segmentIndex + 1);
    } else {
      // Reached the end of the article. Rewind the saved session to the start
      // (YouTube-style): the next launch offers the article from the beginning
      // instead of resuming at the very end.
      _playing = false;
      _paused = false;
      _segmentIndex = 0;
      _saveProgress();
    }
    notifyListeners();
  }

  Future<void> _saveProgress() async {
    final article = _article;
    if (article == null) return;

    // Persist the listening session so it can be resumed after a restart,
    // even if no screen has wired an onProgress callback yet.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionArticleKey, article.id);
    await prefs.setInt(_sessionSegmentKey, _segmentIndex);

    final progress = onProgress;
    if (progress == null) return;
    TtsSegment? segment;
    if (_segments.isNotEmpty) {
      segment = _segments[_segmentIndex % _segments.length];
    }
    final position = segment?.start ?? 0;
    await progress(article, position, _segmentIndex);
  }

  /// Restores the last listening session (article + position) after an app
  /// restart, so the mini player reappears and playback can be resumed.
  ///
  /// Loads the article and seeks to the saved segment without auto-playing.
  /// Does nothing when a session is already active or nothing was saved.
  Future<void> restoreSession(ArticleRepository repository) async {
    if (_segments.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final articleId = prefs.getString(_sessionArticleKey);
    if (articleId == null) return;

    final article = repository.byId(articleId);
    if (article == null || article.textContent.isEmpty) {
      // The article was deleted or can't be listened to; drop the stale session.
      await prefs.remove(_sessionArticleKey);
      await prefs.remove(_sessionSegmentKey);
      return;
    }

    _article = article;
    _segments = TextChunker.chunk(article.textContent);
    _segmentIndex = _clampSegment(
      prefs.getInt(_sessionSegmentKey) ?? article.listenSegment,
    );
    notifyListeners();
  }

  int _clampSegment(int segment) {
    if (_segments.isEmpty) return 0;
    return min(max(segment, 0), _segments.length - 1);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
