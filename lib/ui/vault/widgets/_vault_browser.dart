part of '../vault_panel.dart';

class _VaultBrowser extends StatelessWidget {
  final VaultSession session;
  final VaultBrowserController browser;
  final bool busy;
  final VoidCallback onSearch;
  final ValueChanged<VaultView> onView;
  final VoidCallback onEmptyTrash;
  final Widget tree;
  final Widget Function(VaultEntry) entryCard;

  const _VaultBrowser({
    required this.session,
    required this.browser,
    required this.busy,
    required this.onSearch,
    required this.onView,
    required this.onEmptyTrash,
    required this.tree,
    required this.entryCard,
  });

  @override
  Widget build(BuildContext context) {
    final trashCount = session.entries.where((entry) => entry.isDeleted).length;
    final results = browser.filtering ? browser.results(session) : const <VaultSearchResult>[];
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final view in VaultView.values)
                ChoiceChip(
                  label: Text(switch (view) {
                    VaultView.all => t.browserAll,
                    VaultView.favorites => t.browserFavorites,
                    VaultView.trash => t.browserTrash(count: trashCount),
                  }),
                  selected: browser.view == view,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: busy ? null : (_) => onView(view),
                ),
              IconButton(
                tooltip: t.browserSearch,
                padding: const EdgeInsets.all(10),
                onPressed: busy ? null : onSearch,
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
        ),
        if (browser.view == VaultView.trash) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t.browserTrashHelp, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ),
          if (trashCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: busy ? null : onEmptyTrash,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                label: Text(t.browserEmptyTrash),
              ),
            ),
        ],
        if (browser.filtering) ...[
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              child: Text(switch (browser.view) {
                VaultView.all => t.browserNoResults,
                VaultView.favorites => browser.query.trim().isEmpty ? t.browserNoFavorites : t.browserNoResults,
                VaultView.trash => browser.query.trim().isEmpty ? t.browserTrashEmpty : t.browserNoResults,
              }),
            ),
          for (final result in results)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    result.location.isEmpty ? t.vaultRoot : result.location.join(' / '),
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ),
                entryCard(result.entry),
              ],
            ),
        ] else
          tree,
      ],
    );
  }
}
