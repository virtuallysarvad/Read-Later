import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../services/tts_service.dart';
import '../utils/text_chunker.dart';

/// Pocket-style "Listen" view: a focused, dark screen where the article is
/// read aloud like a podcast. The current paragraph is highlighted and the
/// view auto-scrolls to keep up with the narration.
class ListeningScreen extends StatefulWidget {
  final String articleId;

  const ListeningScreen({super.key, required this.articleId});

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  final _scrollController = ScrollController();
  final List<GlobalKey> _paragraphKeys = [];
  int _highlightedParagraph = -1;

  static const _bg = Color(0xFF0E1224);
  static const _fg = Color(0xFFE8EAF2);
  static const _muted = Color(0xFF8B90A6);

  @override
  void initState() {
    super.initState();
    _loadArticle();
    // Persist listening progress (also wired from the reader, but this screen
    // can be opened straight from the list).
    final repository = context.read<ArticleRepository>();
    context.read<TtsService>().onProgress =
        (article, position, segment) =>
            repository.setListenProgress(article.id, position, segment);
  }

  Future<void> _loadArticle() async {
    final repository = context.read<ArticleRepository>();
    final tts = context.read<TtsService>();
    final article = repository.byId(widget.articleId);
    if (article == null) return;
    final wasLoaded = tts.article?.id == article.id;
    if (!wasLoaded) {
      await tts.loadArticle(article);
      // Pocket-style: opening Listen starts playback automatically.
      await tts.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onParagraphChanged(int index) {
    if (index == _highlightedParagraph ||
        index < 0 ||
        index >= _paragraphKeys.length) {
      return;
    }
    setState(() => _highlightedParagraph = index);

    final key = _paragraphKeys[index];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.25,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<ArticleRepository>();
    final tts = context.watch<TtsService>();
    final article = repository.byId(widget.articleId);
    if (article == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final paragraphs = TextChunker.paragraphs(article.textContent);
    _paragraphKeys
      ..clear()
      ..addAll(List.generate(paragraphs.length, (_) => GlobalKey()));

    final currentParagraph = tts.article?.id == article.id
        ? tts.currentParagraph
        : -1;
    if (currentParagraph != _highlightedParagraph) {
      // Schedule after the frame so the new keys exist.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onParagraphChanged(currentParagraph);
      });
    }

    final playing = tts.isPlaying && tts.article?.id == article.id;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              article: article,
              onClose: () {
                tts.stop();
                Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: paragraphs.isEmpty
                  ? const Center(
                      child: Text(
                        'Nothing to listen to in this article.',
                        style: TextStyle(color: _muted),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: paragraphs.length,
                      itemBuilder: (context, index) {
                        final paragraph = paragraphs[index];
                        final isCurrent =
                            tts.article?.id == article.id &&
                                index == currentParagraph;
                        return GestureDetector(
                          key: _paragraphKeys[index],
                          onTap: () => tts.playParagraph(index),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Text(
                              paragraph.text,
                              style: TextStyle(
                                fontSize: 17,
                                height: 1.6,
                                color: isCurrent
                                    ? tts.isPlaying
                                        ? const Color(0xFFFF5C6C)
                                        : _fg
                                    : _muted,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            _Controls(
              tts: tts,
              playing: playing,
              paused: tts.isPaused && tts.article?.id == article.id,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Article article;
  final VoidCallback onClose;

  const _Header({required this.article, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: _ListeningScreenState._fg),
            onPressed: onClose,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: _ListeningScreenState._fg.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  article.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ListeningScreenState._fg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final TtsService tts;
  final bool playing;
  final bool paused;

  const _Controls({
    required this.tts,
    required this.playing,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    final active = playing || paused;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161B33),
        border: Border(top: BorderSide(color: Color(0xFF22294A))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            child: Row(
              children: [
                Text(
                  tts.progressLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _ListeningScreenState._muted,
                  ),
                ),
                const Spacer(),
                Text(
                  '${tts.speed.toStringAsFixed(2)}x'
                      .replaceFirst(RegExp(r'0+$'), '')
                      .replaceFirst(RegExp(r'\.$'), ''),
                  style: const TextStyle(
                    fontSize: 12,
                    color: _ListeningScreenState._muted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Previous paragraph',
                  iconSize: 34,
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: _ListeningScreenState._fg,
                  ),
                  onPressed: active ? tts.skipBackward : null,
                ),
                IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  iconSize: 64,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: const Color(0xFFFF5C6C),
                  ),
                  onPressed: () {
                    if (playing) {
                      tts.pause();
                    } else if (paused) {
                      tts.play();
                    } else {
                      tts.play();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Next paragraph',
                  iconSize: 34,
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: _ListeningScreenState._fg,
                  ),
                  onPressed: active ? tts.skipForward : null,
                ),
                TextButton.icon(
                  onPressed: tts.cycleSpeed,
                  icon: const Icon(
                    Icons.speed,
                    size: 18,
                    color: _ListeningScreenState._fg,
                  ),
                  label: const Text(
                    'Speed',
                    style: TextStyle(color: _ListeningScreenState._fg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
