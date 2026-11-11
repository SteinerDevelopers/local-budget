import 'package:flutter/material.dart';

import 'help_articles.dart';

/// The Help section: a searchable list plus one reading page per article.
/// Full-screen instead of a sheet because reading beats scrolling a modal,
/// and search needs a stable field that survives rotation (E2 §7).
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final found = searchHelpArticles(_query);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search help',
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: found.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Nothing found. Try “total”, “PDF” or '
                          '“highlight”.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: found.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => ListTile(
                        leading: Icon(found[index].icon),
                        title: Text(found[index].title),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                HelpArticlePage(article: found[index]),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One article, plain readable column. Public so the golden harness can
/// render exactly this page.
class HelpArticlePage extends StatelessWidget {
  const HelpArticlePage({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(article.title)),
      body: SafeArea(
        // Reading measure on wide surfaces (T2, tablet audit 2026-11-10:
        // at sw800 the paragraphs ran past 110 characters a line). The
        // body caps at 640 dp and centers; phone columns never reach
        // the cap, so they paint exactly as before.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Icon(
                  article.icon,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                for (final paragraph in article.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      paragraph,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
