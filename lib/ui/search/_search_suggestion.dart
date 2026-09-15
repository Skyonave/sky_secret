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
    final action = kind == 'totp'
        ? t.totpTitle
        : kind == 'file'
        ? t.searchOpenFile
        : kind == 'ssh'
        ? t.sshConnect
        : t.searchCopyPassword;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Icon(
                  kind == 'totp'
                      ? Icons.timer_outlined
                      : kind == 'file'
                      ? Icons.insert_drive_file_outlined
                      : kind == 'ssh'
                      ? Icons.terminal
                      : Icons.key_rounded,
                  size: 17,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(result['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 1),
                      Text(
                        [if (username.isNotEmpty) username, location.isEmpty ? t.vaultRoot : location].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (result['favorite'] == true) ...[
                  Icon(Icons.star_rounded, size: 16, color: colors.primary),
                  const SizedBox(width: 8),
                ],
                DesktopTooltip(message: action, child: const Icon(Icons.keyboard_return_rounded, size: 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
