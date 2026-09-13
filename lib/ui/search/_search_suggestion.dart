part of 'vault_search_window.dart';

class _SearchSuggestion extends StatelessWidget {
  final Map result;
  final bool selected;
  final VoidCallback onSelect;

  const _SearchSuggestion({required this.result, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = result['kind'];
    final location = result['location'] as String;
    final username = result['username'] as String;
    final action = kind == 'file'
        ? t.searchOpenFile
        : kind == 'ssh'
        ? t.sshConnect
        : t.searchCopyPassword;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainer,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  kind == 'file'
                      ? Icons.insert_drive_file_outlined
                      : kind == 'ssh'
                      ? Icons.terminal
                      : Icons.key_rounded,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(result['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        [if (username.isNotEmpty) username, location.isEmpty ? t.vaultRoot : location].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (result['favorite'] == true) ...[
                  Icon(Icons.star_rounded, size: 16, color: colors.primary),
                  const SizedBox(width: 8),
                ],
                Tooltip(message: action, child: const Icon(Icons.keyboard_return_rounded, size: 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
