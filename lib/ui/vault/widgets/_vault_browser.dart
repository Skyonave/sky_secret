part of '../vault_panel.dart';

class _VaultBrowser extends StatelessWidget {
  final VaultSession session;
  final Set<String> pendingIds;
  final List<VaultEntry> pendingEntries;
  final Set<String> collapsed;
  final VoidCallback onCollapsedChanged;
  final Widget tree;
  final Widget Function(VaultEntry) entryCard;

  const _VaultBrowser({
    required this.session,
    required this.pendingIds,
    required this.pendingEntries,
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.tree,
    required this.entryCard,
  });

  @override
  Widget build(BuildContext context) {
    final favorites =
        [
            ...session.entries,
            ...pendingEntries,
          ].where((entry) => entry.isFavorite && (entry.isDeleted == false || pendingIds.contains(entry.id))).toList()
          ..sort((left, right) => left.order.compareTo(right.order));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (favorites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: () {
                if (collapsed.contains('@favorites')) {
                  collapsed.remove('@favorites');
                } else {
                  collapsed.add('@favorites');
                }
                onCollapsedChanged();
              },
              child: Row(
                children: [
                  Icon(
                    collapsed.contains('@favorites') ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.star_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(t.browserFavorites, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (!collapsed.contains('@favorites'))
            for (final entry in favorites) entryCard(entry),
          const SizedBox(height: 6),
        ],
        tree,
      ],
    );
  }
}
