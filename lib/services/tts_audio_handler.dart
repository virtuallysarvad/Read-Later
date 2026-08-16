import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'tts_service.dart';

/// Bridges [TtsService] to Android's media session so that playback shows a
/// media notification with lock-screen controls (play/pause, skip, seek).
///
/// The app's UI keeps talking to [TtsService] directly; this handler only
/// mirrors state out to the system and forwards system commands back in.
class TtsAudioHandler extends BaseAudioHandler {
  /// Estimated reading speed used to map character positions to durations.
  static const double _charsPerSecond = 18.3; // ~1100 chars/min

  final TtsService _tts;
  Timer? _positionTimer;

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

  void _pushState() {
    final article = _tts.article;

    if (article == null) {
      mediaItem.add(null);
    } else if (mediaItem.value?.id != article.id) {
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

    playbackState.add(playbackState.value.copyWith(
      processingState:
          _tts.hasContent ? AudioProcessingState.ready : AudioProcessingState.idle,
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
