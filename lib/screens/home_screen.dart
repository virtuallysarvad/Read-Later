import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';
import '../utils/fuzzy_search.dart';
import '../widgets/article_card.dart';
import '../widgets/mini_player.dart';
import 'add_article_screen.dart';
import 'listening_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, favorites, archive }

/// How far (in logical pixels) the list must scroll before the app bar
/// becomes fully opaque, mirroring Twine's scroll-fading top bar.
const double _appBarFadeDistance = 200;

class HomeScreen extends StatefulWidget {
  final ValueNotifier<String?> sharedUrl;

  const HomeScreen({super.key, required this.sharedUrl});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';
  bool _searching = false;
  final _searchController = TextEditingController();

  /// 0 (fully transparent, at the top) → 0.95 (opaque once scrolled).
  double _appBarAlpha = 0;

  // Captured in initState so dispose() never does an ancestor lookup on a
  // deactivated element (which Flutter forbids while the tree is torn down).
  late final ArticleRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = context.read<ArticleRepository>();
    widget.sharedUrl.addListener(_onSharedUrl);
    // Handle a URL that arrived before the widget was built, and bring back
    // the listening session (mini player) from the previous app run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSharedUrl();
      _restoreListeningSession();
    });
  }

  @override
  void dispose() {
    widget.sharedUrl.removeListener(_onSharedUrl);
    _repository.removeListener(_onRepositoryReady);
    _searchController.dispose();
    super.dispose();
  }

  /// Reloads the last listening session once the repository has loaded, so the
  /// player survives an app restart and can be resumed.
  void _restoreListeningSession() {
    if (_repository.isInitialized) {
      context.read<TtsService>().restoreSession(_repository);
    } else {
      // Repository init is async (fired from the provider); wait for it.
      _repository.addListener(_onRepositoryReady);
    }
  }

  void _onRepositoryReady() {
    if (!_repository.isInitialized) return;
    _repository.removeListener(_onRepositoryReady);
    context.read<TtsService>().restoreSession(_repository);
  }

  void _onSharedUrl() {
    final url = widget.sharedUrl.value;
    if (url == null) return;
    widget.sharedUrl.value = null;
    _saveSharedUrl(url);
  }

  Future<void> _saveSharedUrl(String url) async {
    final repository = context.read<ArticleRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final article = await repository.addFromUrl(url);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added "${article.title}" to Read Later'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openArticle(article.id),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save link: $e')),
      );
    }
  }

  void _openArticle(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(articleId: id)),
    );
  }

  List<Article> _visibleArticles(ArticleRepository repository) {
    final source = switch (_filter) {
      // "All" shows everything that isn't archived; archived articles live
      // under the Archive tab only.
      _Filter.all => repository.all
          .where((a) => a.status != ArticleStatus.archived)
          .toList(),
      _Filter.favorites => repository.favorites,
      _Filter.archive => repository.archived,
    };
    if (_query.trim().isEmpty) return source;

    // Fuzzy match title, excerpt and site name, then rank by relevance
    // (best match first) instead of repository order.
    final matches = <(Article, double)>[];
    for (final article in source) {
      final score = _searchScore(_query, article);
      if (score != null) matches.add((article, score));
    }
    matches.sort((a, b) => a.$2.compareTo(b.$2));
    return matches.map((m) => m.$1).toList();
  }

  /// Best fuzzy score across the article's searchable fields. Title matches
  /// rank above site-name matches above excerpt matches (small offsets).
  double? _searchScore(String query, Article article) {
    final candidates = [
      (article.title, 0.0),
      if (article.siteName != null) (article.siteName!, 0.1),
      if (article.excerpt != null) (article.excerpt!, 0.2),
    ];
    double? best;
    for (final (text, offset) in candidates) {
      final score = fuzzyScore(query, text);
      if (score == null) continue;
      final weighted = score + offset;
      if (best == null || weighted < best) best = weighted;
    }
    return best;
  }

  void _showAddArticle() async {
    final article = await Navigator.of(context).push<Article>(
      MaterialPageRoute(builder: (_) => const AddArticleScreen()),
    );
    if (article != null && mounted) {
      _openArticle(article.id);
    }
  }

  void _onCardAction(String id, String action) {
    final repository = context.read<ArticleRepository>();
    final tts = context.read<TtsService>();
    final article = repository.byId(id);
    if (article == null) return;

    switch (action) {
      case 'favorite':
        repository.setFavorite(id, !article.isFavorite);
      case 'archive':
        repository.setStatus(
          id,
          article.status == ArticleStatus.archived
              ? ArticleStatus.unread
              : ArticleStatus.archived,
        );
      case 'listen':
        tts.loadArticle(article);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ListeningScreen(articleId: article.id),
          ),
        );
      case 'open':
        launchUrl(Uri.parse(article.url), mode: LaunchMode.externalApplication);
      case 'delete':
        _confirmDelete(article);
    }
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
      context.read<ArticleRepository>().deleteArticle(article.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<ArticleRepository>();
    final articles = _visibleArticles(repository);
    final appColors = context.appColors;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis != Axis.vertical) return false;
          final alpha =
              (notification.metrics.pixels / _appBarFadeDistance)
                  .clamp(0.0, 0.95);
          if ((alpha - _appBarAlpha).abs() > 0.01) {
            setState(() => _appBarAlpha = alpha);
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: appColors.backdrop.withValues(alpha: _appBarAlpha),
              surfaceTintColor: Colors.transparent,
              title: _searching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search articles…',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    )
                  : const Text(
                      'Read Later',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
              actions: [
                IconButton(
                  tooltip: _searching ? 'Close search' : 'Search',
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _query = '';
                      _searchController.clear();
                    }
                  }),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
              bottom: repository.all.isEmpty
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(56),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: SegmentedButton<_Filter>(
                          segments: const [
                            ButtonSegment(
                              value: _Filter.all,
                              label: Text('All'),
                              icon: Icon(Icons.list_alt),
                            ),
                            ButtonSegment(
                              value: _Filter.favorites,
                              label: Text('Favorites'),
                              icon: Icon(Icons.star_outline),
                            ),
                            ButtonSegment(
                              value: _Filter.archive,
                              label: Text('Archive'),
                              icon: Icon(Icons.archive_outlined),
                            ),
                          ],
                          selected: {_filter},
                          onSelectionChanged: (selection) =>
                              setState(() => _filter = selection.first),
                        ),
                      ),
                    ),
            ),
            if (repository.all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(onAdd: _showAddArticle),
              )
            else if (articles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NoResults(query: _query),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final article = articles[index];
                      return ArticleCard(
                        article: article,
                        onTap: () => _openArticle(article.id),
                        onAction: (action) => _onCardAction(article.id, action),
                      );
                    },
                    childCount: articles.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add article',
        onPressed: _showAddArticle,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Your reading list is empty',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Share any link to Read Later from another app, '
              'or tap + to paste a URL. Articles are saved ad-free '
              'and can be read or listened to like a podcast.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add an article'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;

  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        query.isEmpty
            ? 'Nothing here yet.'
            : 'No matches for "$query".',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
