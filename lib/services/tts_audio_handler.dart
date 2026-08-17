import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'tts_service.dart';

/// Bridges [TtsService] to Android's media session so that playback shows a
/// media notification with lock-screen controls (play/pause, skip, seek).
///
/// The app's UI keeps talking to [TtsService] directly; this handler only
/// mirrors state out to the system and forwards system commands back in.
///
/// The notification exists only while playback is active (playing or paused).
/// Once the user stops, the processing state drops to idle so audio_service
/// tears down the foreground service and removes the notification — a bare
/// "Read Later is running" foreground-service notification can never linger.
class TtsAudioHandler extends BaseAudioHandler {
  /// Estimated reading speed used to map character positions to durations.
  static const double _charsPerSecond = 18.3; // ~1100 chars/min

  /// How long to wait after playback starts before re-pushing the media item.
  /// The immediate push can race ahead of the foreground service being
  /// created (the service drops the metadata, leaving a title-less
  /// "Read Later is running" notification); by the time this fires the
  /// service exists and the notification is rebuilt with the article title.
  static const Duration _metadataRetryDelay = Duration(milliseconds: 600);

  final TtsService _tts;
  Timer? _positionTimer;

  /// One-shot re-push of the media item scheduled when playback starts.
  Timer? _metadataRetryTimer;

  /// Set while the platform has no media item (e.g. after the foreground
  /// service was stopped), so the next playback re-pushes the metadata even
  /// though the article itself didn't change.
  bool _needsMediaItemResync = false;

  bool _wasActive = false;

  TtsAudioHandler(this._tts) {
    _tts.addListener(_onTtsChanged);
    _onTtsChanged();
  }

  Duration get _position => Duration(
      milliseconds: (_tts.currentPosition / _charsPerSecond * 1000).round());

  Duration get _duration => Duration(
      milliseconds: (_tts.totalLength / _charsPerSecond * 1000).round());

  void _onTtsChanged() {
    _pushState();
    if (_tts.isPlaying) {
      _positionTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pushState(),
      );
    } else {
      _positionTimer?.cancel();
      _positionTimer = null;
    }
  }

  void _pushState({bool forceMediaItem = false}) {
    final article = _tts.article;

    if (article == null) {
      mediaItem.add(null);
    } else if (forceMediaItem ||
        mediaItem.value?.id != article.id ||
        _needsMediaItemResync) {
      _needsMediaItemResync = false;
      mediaItem.add(MediaItem(
        id: article.id,
        title: article.title,
        artist: article.siteName ?? 'Read Later',
        duration: _duration,
        artUri: article.imageUrl != null
            ? Uri.tryParse(article.imageUrl!)
            : null,
      ));
    }

    // Active = playing or paused. When stopped, drop to idle so the
    // foreground service stops and the notification is removed.
    final active = _tts.isPlaying || _tts.isPaused;
    if (!active) {
      _needsMediaItemResync = true;
    }

    // On the transition into playback, re-push the media item once the
    // foreground service has been created (see [_metadataRetryDelay]).
    if (active && !_wasActive) {
      _metadataRetryTimer?.cancel();
      _metadataRetryTimer = Timer(_metadataRetryDelay, () {
        _metadataRetryTimer = null;
        _pushState(forceMediaItem: true);
      });
    } else if (!active) {
      _metadataRetryTimer?.cancel();
      _metadataRetryTimer = null;
    }
    _wasActive = active;

    playbackState.add(playbackState.value.copyWith(
      processingState:
          active ? AudioProcessingState.ready : AudioProcessingState.idle,
      playing: _tts.isPlaying,
      controls: [
        MediaControl.skipToPrevious,
        _tts.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      updatePosition: _position,
      speed: _tts.speed,
    ));
  }

  @override
  Future<void> play() => _tts.play();

  @override
  Future<void> pause() => _tts.pause();

  @override
  Future<void> stop() => _tts.dismiss();

  @override
  Future<void> skipToNext() => _tts.skipForward();

  @override
  Future<void> skipToPrevious() => _tts.skipBackward();

  @override
  Future<void> seek(Duration position) async {
    final chars = (position.inMilliseconds / 1000 * _charsPerSecond).round();
    await _tts.playAtChar(chars);
  }
}
