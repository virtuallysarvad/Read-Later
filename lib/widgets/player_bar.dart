import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../screens/listening_screen.dart';
import '../services/tts_service.dart';

/// Compact mini-player pinned to the bottom of the reader, Pocket-style.
///
/// If the TTS service isn't playing this article yet, tapping play loads it
/// first. Otherwise the controls drive the current listening session.
class PlayerBar extends StatelessWidget {
  final Article article;

  const PlayerBar({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final theme = Theme.of(context);
    final isCurrent = tts.article?.id == article.id;
    final canControl = isCurrent && tts.hasContent;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: canControl ? tts.progressFraction : 0,
              minHeight: 2,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous paragraph',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: canControl ? tts.skipBackward : null,
                  ),
                  _PlayPauseButton(
                    tts: tts,
                    article: article,
                    isCurrent: isCurrent,
                  ),
                  IconButton(
                    tooltip: 'Next paragraph',
                    icon: const Icon(Icons.skip_next),
                    onPressed: canControl ? tts.skipForward : null,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: tts.cycleSpeed,
                    icon: const Icon(Icons.speed, size: 18),
                    label: Text('${tts.speed.toStringAsFixed(2)}x'
                        .replaceFirst(RegExp(r'0+$'), '')
                        .replaceFirst(RegExp(r'\.$'), '')),
                  ),
                  IconButton(
                    tooltip: 'Listening view',
                    icon: const Icon(Icons.headphones),
                    onPressed: () {
                      final service = context.read<TtsService>();
                      if (service.article?.id != article.id) {
                        service.loadArticle(article);
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ListeningScreen(articleId: article.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final TtsService tts;
  final Article article;
  final bool isCurrent;

  const _PlayPauseButton({
    required this.tts,
    required this.article,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final playing = isCurrent && tts.isPlaying;
    final icon = playing ? Icons.pause_circle_filled : Icons.play_circle_filled;
    return IconButton(
      tooltip: playing ? 'Pause' : 'Play',
      iconSize: 44,
      icon: Icon(icon, color: Theme.of(context).colorScheme.primary),
      onPressed: () {
        if (playing) {
          tts.pause();
        } else if (isCurrent && tts.isPaused) {
          tts.play();
        } else {
          tts.loadArticle(article).then((_) => tts.play());
        }
      },
    );
  }
}
