import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'app.dart';
import 'services/tts_audio_handler.dart';
import 'services/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Shared instance: the UI, the media notification and the audio handler all
  // talk to the same TtsService.
  final tts = TtsService();
  await AudioService.init(
    builder: () => TtsAudioHandler(tts),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.readlater.read_later.playback',
      androidNotificationChannelName: 'Listening',
      // Keep the notification and foreground service while paused so the
      // player is persistent and can be resumed from the shade/lock screen.
      // (audio_service forbids androidNotificationOngoing when the service
      // stays in the foreground while paused.)
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      // Monochrome silhouette (same art as the themed launcher icon) so the
      // media notification/status bar icon isn't a tinted blob of the
      // full-color launcher icon. Also required for the seek bar to render.
      androidNotificationIcon: 'mipmap/ic_stat_listening',
      notificationColor: Color(0xFFEF4056),
    ),
  );
  unawaited(tts.init());

  // Links shared from other apps land here. The stream must be listened to
  // before runApp so no share is missed when the app is already running.
  final sharedUrl = ValueNotifier<String?>(null);

  void handleShared(List<SharedMediaFile> files) {
    for (final file in files) {
      final value = file.path.trim();
      if (file.type == SharedMediaType.url ||
          (file.type == SharedMediaType.text &&
              (value.startsWith('http://') || value.startsWith('https://')))) {
        sharedUrl.value = value;
        return;
      }
    }
  }

  ReceiveSharingIntent.instance.getMediaStream().listen(handleShared);
  ReceiveSharingIntent.instance.getInitialMedia().then(handleShared);

  runApp(ReadLaterApp(sharedUrl: sharedUrl, tts: tts));
}
