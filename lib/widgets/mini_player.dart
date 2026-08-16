import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../screens/listening_screen.dart';
import '../services/tts_service.dart';

/// Sliding mini-player pinned to the bottom of every screen (home, reader,
/// settings, add-article) whenever an article is loaded for listening.
///
/// Spotify/YouTube style: it persists across navigation so playback is always
/// one tap away. Shows the current article with previous/next article,
/// play/pause, speed and progress. Tapping the article opens the full
/// listening view; the close button unloads it.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final article = tts.article;
    final visible =
        article != null &&
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

  /// Progress preview while the user drags the bar (null = show live
  /// progress). The actual seek commits when the gesture ends.
  double? _dragFraction;

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

    // Twine-style bottom bar: a slightly lifted surface with a soft shadow.
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProgressBar(
                value: _dragFraction ?? tts.progressFraction,
                activeColor: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                onSeek: (fraction) {
                  final tts = context.read<TtsService>();
                  tts.seekToChar((fraction * tts.totalLength).round());
                },
                onPreview: (fraction) =>
                    setState(() => _dragFraction = fraction),
                onPreviewEnd: () => setState(() => _dragFraction = null),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _openListening(context),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
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
                    ),
                  ),
                  _compactIconButton(
                    context,
                    tooltip: 'Previous article',
                    icon: Icons.skip_previous_rounded,
                    iconSize: 30,
                    onPressed: () =>
                        tts.playPreviousArticle(context.read<ArticleRepository>()),
                  ),
                  IconButton(
                    tooltip: playing ? 'Pause' : 'Play',
                    iconSize: 38,
                    icon: Icon(
                      playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () {
                      if (playing) {
                        tts.pause();
                      } else {
                        tts.play();
                      }
                    },
                  ),
                  _compactIconButton(
                    context,
                    tooltip: 'Next article',
                    icon: Icons.skip_next_rounded,
                    iconSize: 30,
                    onPressed: () =>
                        tts.playNextArticle(context.read<ArticleRepository>()),
                  ),
                  TextButton(
                    onPressed: tts.cycleSpeed,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _speedLabelOf(tts.speed),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  _compactIconButton(
                    context,
                    tooltip: 'Close player',
                    icon: Icons.close,
                    iconSize: 22,
                    onPressed: tts.dismiss,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _speedLabelOf(double speed) {
    final text = speed.toStringAsFixed(2);
    return '${text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  /// Compact icon button so the transport row fits next to the title.
  Widget _compactIconButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      iconSize: iconSize,
      icon: Icon(icon),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
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

/// Thin progress bar that can be tapped or dragged to seek within the
/// article, with a draggable thumb dot at the current position. The bar shows
/// [value]; while dragging, [onPreview] updates a local preview and [onSeek]
/// commits the position when the gesture ends.
class _ProgressBar extends StatelessWidget {
  static const double _thumbDiameter = 10;
  static const double _thumbRadius = _thumbDiameter / 2;

  final double value;
  final Color activeColor;
  final Color backgroundColor;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onPreview;
  final VoidCallback onPreviewEnd;

  const _ProgressBar({
    required this.value,
    required this.activeColor,
    required this.backgroundColor,
    required this.onSeek,
    required this.onPreview,
    required this.onPreviewEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double fractionAt(double dx) =>
            width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onPreview(fractionAt(d.localPosition.dx)),
          onTapUp: (d) {
            onSeek(fractionAt(d.localPosition.dx));
            onPreviewEnd();
          },
          onHorizontalDragStart: (d) =>
              onPreview(fractionAt(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) =>
              onPreview(fractionAt(d.localPosition.dx)),
          onHorizontalDragEnd: (_) {
            onSeek(value);
            onPreviewEnd();
          },
          // Generous hit area around the 2px bar so it's easy to grab.
          child: SizedBox(
            height: 16,
            child: Stack(
              children: [
                // The thin bar, vertically centered in the hit area.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 7,
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    backgroundColor: backgroundColor,
                  ),
                ),
                // Thumb dot riding the progress position (clamped so it
                // stays fully inside the bar).
                Positioned(
                  left: (value * width - _thumbRadius)
                      .clamp(0.0, math.max(0.0, width - _thumbDiameter)),
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: _thumbDiameter,
                      height: _thumbDiameter,
                      decoration: BoxDecoration(
                        color: activeColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
