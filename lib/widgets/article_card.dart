import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/article.dart';

/// A card in the home list: thumbnail, title, site + age, and a menu.
class ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  final void Function(String action) onAction;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateFormat('MMM d').format(
      DateTime.fromMillisecondsSinceEpoch(article.savedAt),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(article: article),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (article.excerpt?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Text(
                        article.excerpt!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (article.isFavorite) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            article.subtitle.isNotEmpty
                                ? '${article.subtitle} · $age'
                                : age,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (article.readProgress > 0.02 &&
                        article.readProgress < 0.99) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: article.readProgress,
                          minHeight: 3,
                          backgroundColor: theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: onAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(article.isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(article.status == ArticleStatus.archived
                        ? 'Unarchive'
                        : 'Archive'),
                  ),
                  const PopupMenuItem(value: 'listen', child: Text('Listen')),
                  const PopupMenuItem(value: 'open', child: Text('Open original')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Article article;

  const _Thumbnail({required this.article});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);

    if (article.imageUrl != null && article.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          article.imageUrl!,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              _Placeholder(scheme: scheme, radius: radius),
        ),
      );
    }
    return _Placeholder(scheme: scheme, radius: radius);
  }
}

class _Placeholder extends StatelessWidget {
  final ColorScheme scheme;
  final BorderRadius radius;

  const _Placeholder({required this.scheme, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: scheme.surfaceContainerHighest,
      ),
      child: Icon(Icons.article_outlined, color: scheme.onSurfaceVariant),
    );
  }
}
