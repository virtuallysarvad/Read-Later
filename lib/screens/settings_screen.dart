import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/article_repository.dart';
import '../services/backup_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_variant.dart';
import '../widgets/mini_player.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        // Bottom padding so the last section clears the mini player.
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          _AppearanceSection(),
          Divider(height: 32),
          _BackupSection(),
          Divider(height: 32),
          _ListeningSection(),
          Divider(height: 32),
          _DataSection(),
          Divider(height: 32),
          _AboutSection(),
        ],
      ),
      // The mini player is shared across screens so playback stays visible
      // while changing settings (YouTube/Spotify style).
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String description;

  const _SectionHeader({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme picker: Light, Dark and Dynamic (follows the system).
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Appearance',
          description: 'Light and Dark use the Pocket red palette; '
              'Dynamic follows your system colors and light/dark mode.',
        ),
        for (final variant in ThemeVariant.values)
          _ThemeVariantTile(
            variant: variant,
            selected: controller.variant == variant,
            onTap: () => controller.setVariant(variant),
          ),
        const SizedBox(height: 4),
        Text(
          'Tip: use the theme that makes reading easiest on your eyes.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ThemeVariantTile extends StatelessWidget {
  final ThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeVariantTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lightScheme = AppTheme.schemeFor(variant, false).$1;
    final darkScheme = AppTheme.schemeFor(variant, true).$1;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: lightScheme.primary,
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.transparent,
            foregroundColor: darkScheme.primary,
            child: const Icon(Icons.circle, size: 10),
          ),
        ],
      ),
      title: Text(variant.label),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      onTap: onTap,
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    final backup = context.watch<BackupService>();
    final repository = context.read<ArticleRepository>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Backup',
          description: 'Save your reading list to a file or restore it. '
              'You pick where the file lives using the system files app.',
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: backup.isBusy
                    ? null
                    : () => backup.backup(repository.all),
                icon: backup.isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: const Text('Back up'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: backup.isBusy
                    ? null
                    : () async {
                        final restored = await backup.restore();
                        if (restored.isNotEmpty && context.mounted) {
                          await repository.mergeBackup(restored);
                        }
                      },
                icon: const Icon(Icons.download),
                label: const Text('Restore'),
              ),
            ),
          ],
        ),
        if (backup.statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            backup.statusMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Tip: keep the backup file somewhere safe. Restoring merges '
          'articles by URL, keeping the newer copy of each.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ListeningSection extends StatelessWidget {
  const _ListeningSection();

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Listening',
          description: 'Articles are read aloud like a podcast, '
              'paragraph by paragraph.',
        ),
        DropdownButtonFormField<String>(
          initialValue: tts.language,
          decoration: const InputDecoration(
            labelText: 'Voice language',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option in TtsService.languageOptions)
              DropdownMenuItem(
                value: option.code,
                child: Text(option.label),
              ),
          ],
          onChanged: (code) {
            if (code != null) tts.setLanguage(code);
          },
        ),
        const SizedBox(height: 16),
        Text('Playback speed', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final speed in TtsService.speedOptions)
              ChoiceChip(
                label: Text('${speed}x'),
                selected: (tts.speed - speed).abs() < 0.001,
                onSelected: (_) => tts.setSpeed(speed),
              ),
          ],
        ),
      ],
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ArticleRepository>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Data',
          description: 'Everything is stored locally on this device.',
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline),
          title: const Text('Delete all articles'),
          subtitle: const Text('Removes everything from this device'),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete everything?'),
                content: const Text(
                  'All saved articles will be removed from this device. '
                  'This cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete all'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await repository.clearAll();
            }
          },
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'About',
          description: '',
        ),
        Text(
          'Read Later — a Pocket-inspired read-later app. '
          'Articles are extracted on-device with Mozilla\'s Readability, '
          'stored locally, and can be listened to like a podcast.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'UI inspired by the Twine RSS reader (GPL-3.0, '
          'github.com/msasikanth/twine).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
