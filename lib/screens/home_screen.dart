import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/article_repository.dart';
import '../models/article.dart';
import '../services/tts_service.dart';
import '../widgets/article_card.dart';
import '../widgets/mini_player.dart';
import 'add_article_screen.dart';
import 'listening_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, favorites, archive }

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

  @override
  void initState() {
    super.initState();
    widget.sharedUrl.addListener(_onSharedUrl);
    // Handle a URL that arrived before the widget was built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedUrl());
  }

  @override
  void dispose() {
    widget.sharedUrl.removeListener(_onSharedUrl);
    _searchController.dispose();
    super.dispose();
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
      _Filter.all => repository.all,
      _Filter.favorites => repository.favorites,
      _Filter.archive => repository.archived,
    };
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source
        .where((a) =>
            a.title.toLowerCase().contains(q) ||
            (a.excerpt?.toLowerCase().contains(q) ?? false) ||
            (a.siteName?.toLowerCase().contains(q) ?? false))
        .toList();
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

    return Scaffold(
      appBar: AppBar(
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
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add article',
        onPressed: _showAddArticle,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: repository.all.isEmpty
          ? _EmptyState(onAdd: _showAddArticle)
          : articles.isEmpty
              ? _NoResults(query: _query)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: articles.length,
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    return ArticleCard(
                      article: article,
                      onTap: () => _openArticle(article.id),
                      onAction: (action) =>
                          _onCardAction(article.id, action),
                    );
                  },
                ),
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
