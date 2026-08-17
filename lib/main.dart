import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'services/auto_backup_service.dart';
import 'services/tts_audio_handler.dart';
import 'services/tts_service.dart';

/// Entry point for the WorkManager background isolate. Runs the auto-backup
/// periodically (frequency chosen in Settings), even when the app is closed.
@pragma('vm:entry-point')
void autoBackupDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return AutoBackupService.runScheduledBackup();
  });
}

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
      // A true ongoing media notification: it appears only while playback is
      // active and carries the native media controls (play/pause, skip,
      // seek bar). The service leaves the foreground when paused, so a bare
      // "Read Later is running" foreground-service notification can never
      // linger in the shade.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Monochrome silhouette (same art as the themed launcher icon) so the
      // media notification/status bar icon isn't a tinted blob of the
      // full-color launcher icon. Also required for the seek bar to render.
      androidNotificationIcon: 'mipmap/ic_stat_listening',
      notificationColor: Color(0xFFEF4056),
    ),
  );

  // Periodic background auto-backup (Android WorkManager). The dispatcher
  // must be registered before runApp.
  await Workmanager().initialize(autoBackupDispatcher);

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
