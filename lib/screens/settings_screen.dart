import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/article_repository.dart';
import '../services/drive_sync_service.dart';
import '../services/tts_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _BackupSection(),
          Divider(height: 32),
          _ListeningSection(),
          Divider(height: 32),
          _DataSection(),
          Divider(height: 32),
          _AboutSection(),
        ],
      ),
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveSyncService>();
    final repository = context.read<ArticleRepository>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Backup', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Sync your reading list to your own Google Drive. '
          'Backups live in a private "Read Later Backup" folder.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (drive.isSignedIn)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: const Text('Signed in as'),
            subtitle: Text(drive.accountEmail ?? 'Google account'),
            trailing: drive.isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () => drive.signOut(),
                    child: const Text('Sign out'),
                  ),
          )
        else
          FilledButton.icon(
            onPressed: drive.isBusy ? null : drive.signIn,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Sign in with Google'),
          ),
        if (drive.isSignedIn) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: drive.isBusy
                      ? null
                      : () => drive.backup(repository.all),
                  icon: const Icon(Icons.upload),
                  label: const Text('Back up now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: drive.isBusy
                      ? null
                      : () async {
                          final restored =
                              await drive.restore();
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
        ],
        if (drive.statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            drive.statusMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Tip: this needs a Google Cloud OAuth client ID for this app '
          'registered with your signing key — see the README.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
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
        Text('Listening', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Articles are read aloud like a podcast, paragraph by paragraph.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Data', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
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
        Text('About', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Read Later — a Pocket-inspired read-later app.\n'
          'Articles are extracted on-device with Mozilla\'s Readability, '
          'stored locally, and can be listened to like a podcast.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
