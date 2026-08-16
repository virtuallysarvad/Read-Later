import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../screens/listening_screen.dart';
import '../services/tts_service.dart';

/// Sliding mini-player pinned to the bottom of the home screen whenever an
/// article is loaded for listening.
///
/// Slides in/out (Spotify/Pocket style), shows the current article with
/// play/pause, skip, speed and progress. Tapping the article opens the full
/// listening view; the close button unloads it.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final article = tts.article;
    final visible = article != null &&
        tts.hasContent &&
        context.read<ArticleRepository>().byId(article.id) != null;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: visible
              ? _Bar(article: article)
              : const SizedBox(width: double.infinity),
        ),
      ),
    );
  }
}

class _Bar extends StatefulWidget {
  final Article article;

  const _Bar({required this.article});

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  /// Refreshes the progress bar while playing, since TTS only notifies on
  /// segment boundaries.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final playing = context.read<TtsService>().isPlaying;
    if (playing) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final theme = Theme.of(context);
    final playing = tts.isPlaying;
    _syncTicker();

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: tts.progressFraction,
              minHeight: 2,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            InkWell(
              onTap: () => _openListening(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Listening',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            widget.article.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: playing ? 'Pause' : 'Play',
                      iconSize: 34,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () {
                        if (playing) {
                          tts.pause();
                        } else if (tts.isPaused) {
                          tts.play();
                        } else {
                          tts.play();
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Next paragraph',
                      icon: const Icon(Icons.skip_next),
                      onPressed: tts.skipForward,
                    ),
                    TextButton(
                      onPressed: tts.cycleSpeed,
                      child: Text(
                        _speedLabelOf(tts.speed),
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close player',
                      icon: const Icon(Icons.close),
                      onPressed: tts.dismiss,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _speedLabelOf(double speed) {
    final text = speed.toStringAsFixed(2);
    return '${text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  void _openListening(BuildContext context) {
    final tts = context.read<TtsService>();
    if (tts.article?.id != widget.article.id) {
      tts.loadArticle(widget.article);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListeningScreen(articleId: widget.article.id),
      ),
    );
  }
}
