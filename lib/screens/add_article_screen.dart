import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/article_repository.dart';
import '../widgets/mini_player.dart';

/// Paste-a-URL screen with fetch feedback. Pops with the saved [Article] on
/// success so callers can navigate to it.
class AddArticleScreen extends StatefulWidget {
  final String? initialUrl;

  const AddArticleScreen({super.key, this.initialUrl});

  @override
  State<AddArticleScreen> createState() => _AddArticleScreenState();
}

class _AddArticleScreenState extends State<AddArticleScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a URL.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final article = await context.read<ArticleRepository>().addFromUrl(url);
      if (!mounted) return;
      Navigator.of(context).pop(article);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add article')),
      // Keep playback controls visible while adding a link.
      bottomNavigationBar: const MiniPlayer(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Paste a link to save it for later.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autofocus: widget.initialUrl == null,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                labelText: 'Link',
                hintText: 'https://example.com/article',
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_saving ? 'Fetching article…' : 'Save article'),
            ),
            if (_saving) ...[
              const SizedBox(height: 16),
              Text(
                'Read Later is downloading the page and removing ads, '
                'navigation and clutter…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
