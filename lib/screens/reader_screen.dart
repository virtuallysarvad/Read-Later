import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player_bar.dart';
import 'listening_screen.dart';

/// Pocket-style clean reading view: ad-free extracted content, scroll-progress
/// tracking, and a mini player to start podcast-style listening.
class ReaderScreen extends StatefulWidget {
  final String articleId;

  const ReaderScreen({super.key, required this.articleId});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _scrollController = ScrollController();
  Timer? _progressDebounce;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Persist listening progress into the article's row.
    final repository = context.read<ArticleRepository>();
    context.read<TtsService>().onProgress =
        (article, position, segment) =>
            repository.setListenProgress(article.id, position, segment);
  }

  @override
  void dispose() {
    _progressDebounce?.cancel();
    _saveReadProgress(force: true);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveReadProgress();
    });
  }

  void _saveReadProgress({bool force = false}) {
    if (_deleted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = (position.pixels / max).clamp(0.0, 1.0);
    if (force || fraction > 0.02) {
      context
          .read<ArticleRepository>()
          .setReadProgress(widget.articleId, fraction);
    }
  }

  void _openListening(Article article) {
    final tts = context.read<TtsService>();
    if (tts.article?.id != article.id) {
      tts.loadArticle(article);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListeningScreen(articleId: article.id),
      ),
    );
  }

  Future<void> _confirmDelete(Article article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete article?'),
        content: Text('"${article.title}" will be removed from Read Later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _deleted = true;
      await context.read<ArticleRepository>().deleteArticle(article.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<ArticleRepository>();
    final article = repository.byId(widget.articleId);
    if (article == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final canListen = article.hasContent && article.textContent.isNotEmpty;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            // Title lives in the pinned toolbar so it never overlaps the
            // action buttons while scrolling.
            title: Text(
              article.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                tooltip: article.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  article.isFavorite ? Icons.star_rounded : Icons.star_border,
                ),
                onPressed: () => repository.setFavorite(
                  article.id,
                  !article.isFavorite,
                ),
              ),
              if (canListen)
                IconButton(
                  tooltip: 'Listen',
                  icon: const Icon(Icons.headphones),
                  onPressed: () => _openListening(article),
                ),
              IconButton(
                tooltip: 'Open original',
                icon: const Icon(Icons.open_in_new),
                onPressed: () =>
                    launchUrl(Uri.parse(article.url),
                        mode: LaunchMode.externalApplication),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (action) {
                  if (action == 'archive') {
                    repository.setStatus(
                      article.id,
                      article.status == ArticleStatus.archived
                          ? ArticleStatus.unread
                          : ArticleStatus.archived,
                    );
                  } else if (action == 'delete') {
                    _confirmDelete(article);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(article.status == ArticleStatus.archived
                        ? 'Unarchive'
                        : 'Archive'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.35),
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (article.siteName != null &&
                              article.siteName!.isNotEmpty) ...[
                            Text(
                              article.siteName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (article.byline != null &&
                              article.byline!.isNotEmpty)
                            Text(
                              article.byline!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            sliver: SliverToBoxAdapter(
              child: article.hasContent
                  ? HtmlWidget(
                      article.contentHtml,
                      textStyle: readerTextStyle,
                      onTapUrl: (url) {
                        launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                        return true;
                      },
                      customStylesBuilder: (element) {
                        final name = element.localName;
                        if (name == 'img' ||
                            name == 'figure' ||
                            name == 'video' ||
                            name == 'iframe') {
                          return const {
                            'border-radius': '10px',
                            'max-width': '100%',
                          };
                        }
                        if (name == 'blockquote') {
                          return const {'font-style': 'italic'};
                        }
                        if (name == 'a') {
                          return {
                            'color':
                                '#${(theme.colorScheme.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                          };
                        }
                        return null;
                      },
                    )
                  : _ExtractionFailed(article: article),
            ),
          ),
        ],
      ),
      bottomNavigationBar: canListen ? PlayerBar(article: article) : null,
    );
  }
}

class _ExtractionFailed extends StatelessWidget {
  final Article article;

  const _ExtractionFailed({required this.article});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.find_in_page_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'This page could not be extracted',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The article is saved, but Read Later couldn\'t '
              'pull out a clean copy. Open it in your browser instead.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(article.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }
}
