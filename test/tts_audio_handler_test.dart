import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:read_later/models/article.dart';
import 'package:read_later/services/tts_audio_handler.dart';
import 'package:read_later/services/tts_service.dart';

const _sampleText = '''
Paragraph one talks about the first idea in some detail.

Paragraph two continues with the second idea of the article.

Paragraph three introduces a third and quite separate idea.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TtsService tts;
  late TtsAudioHandler handler;

  setUp(() {
    // The TTS engine isn't available in tests; stub its platform channel so
    // loading and playing never touches the device.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    tts = TtsService();
    handler = TtsAudioHandler(tts);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  test('idle service reports an idle processing state and no media item',
      () async {
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('a loaded-but-stopped article stays idle (no lingering notification)',
      () async {
    await tts.loadArticle(Article(
      id: 'a1',
      url: 'https://example.com/a',
      title: 'Loaded article',
      siteName: 'Example',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    ));

    // Not playing and not paused → idle, so audio_service keeps the
    // foreground service off and no notification is shown.
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    expect(handler.mediaItem.value?.title, 'Loaded article');
  });

  test('playing maps to ready with native media controls', () async {
    await tts.loadArticle(Article(
      id: 'a1',
      url: 'https://example.com/a',
      title: 'Playing article',
      siteName: 'Example',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    ));
    await tts.play();

    final state = handler.playbackState.value;
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.playing, isTrue);
    expect(state.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
    ]);
    expect(handler.mediaItem.value?.title, 'Playing article');
    expect(handler.mediaItem.value?.artist, 'Example');

    await tts.stop();
  });

  test('pausing keeps the session ready so the notification can persist',
      () async {
    await tts.loadArticle(Article(
      id: 'a1',
      url: 'https://example.com/a',
      title: 'Pausing article',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    ));
    await tts.play();
    await tts.pause();

    expect(handler.playbackState.value.processingState,
        AudioProcessingState.ready);
    expect(handler.playbackState.value.playing, isFalse);

    await tts.stop();
  });

  test('stopping drops to idle so the notification is removed', () async {
    await tts.loadArticle(Article(
      id: 'a1',
      url: 'https://example.com/a',
      title: 'Stopping article',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    ));
    await tts.play();
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.ready);

    await tts.stop();

    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('the media item is re-pushed after a stop so a restarted service '
      'still has the metadata', () async {
    await tts.loadArticle(Article(
      id: 'a1',
      url: 'https://example.com/a',
      title: 'Resync article',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    ));

    // Collect every media item emission. The stream replays the current
    // value on listen (delivered asynchronously), so wait for that replay
    // and then start counting from a clean slate.
    final emissions = <MediaItem?>[];
    final sub = handler.mediaItem.listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    emissions.clear();

    await tts.play();
    await tts.stop();
    await tts.play();

    // Initial listen replay + 2 re-pushes: one per play() after the first.
    final rePushes = emissions.where((m) => m?.id == 'a1').length;
    expect(rePushes, 2, reason: 'expected a media item push per play()');

    sub.cancel();
    await tts.stop();
  });

  test('the media item is re-pushed shortly after playback starts so the '
      'notification never shows without a title', () async {
    await tts.loadArticle(Article(
      id: 'a1',
      url: 'https://example.com/a',
      title: 'Retry article',
      textContent: _sampleText,
      hasContent: true,
      savedAt: 0,
      updatedAt: 0,
    ));

    final emissions = <MediaItem?>[];
    final sub = handler.mediaItem.listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    emissions.clear();

    await tts.play();
    final pushesImmediately = emissions.length;
    // Wait past the metadata retry delay.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final pushesAfterRetry = emissions.length;

    // One push from play() itself, then the scheduled retry re-pushes the
    // same article's metadata once the (re)created service exists.
    expect(pushesImmediately, 1);
    expect(pushesAfterRetry, 2);
    expect(emissions.last?.title, 'Retry article');

    sub.cancel();
    await tts.stop();
  });
}
