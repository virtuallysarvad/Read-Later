import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';

/// A card in the home list, styled after Twine's feed items: a flat,
/// rounded block on the backdrop with a 2-line title, 2-line excerpt and a
/// rounded thumbnail on the right. Read articles fade out.
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
    final appColors = context.appColors;
    final age = DateFormat('MMM d').format(
      DateTime.fromMillisecondsSinceEpoch(article.savedAt),
    );
    final read = article.readProgress >= 0.9;

    return Opacity(
      // Fully-read cards stay legible; 0.7 keeps the fade cue without
      // washing the text out.
      opacity: read ? 0.7 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: appColors.backdrop,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (article.excerpt?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            article.excerpt!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
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
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (article.readProgress > 0.02 &&
                            article.readProgress < 0.99) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: article.readProgress,
                              minHeight: 3,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHigh,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (article.imageUrl?.isNotEmpty ?? false) ...[
                    const SizedBox(width: 16),
                    _Thumbnail(article: article),
                  ],
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: onAction,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    iconSize: 20,
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
                      const PopupMenuItem(
                        value: 'listen',
                        child: Text('Listen'),
                      ),
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('Open original'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
    final appColors = context.appColors;
    final radius = BorderRadius.circular(16);

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        article.imageUrl!,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _Placeholder(
          scheme: scheme,
          appColors: appColors,
          radius: radius,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final ColorScheme scheme;
  final AppColors appColors;
  final BorderRadius radius;

  const _Placeholder({
    required this.scheme,
    required this.appColors,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: appColors.translucentFill(scheme),
      ),
      child: Icon(Icons.article_outlined, color: scheme.onSurfaceVariant),
    );
  }
}
