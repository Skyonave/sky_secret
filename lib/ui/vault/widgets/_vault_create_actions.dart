part of '../vault_panel.dart';

class _VaultCreateActions extends StatelessWidget {
  final bool busy;
  final VoidCallback onEntry;
  final VoidCallback onSsh;
  final VoidCallback onTotp;
  final VoidCallback onFile;
  final VoidCallback onTextFile;
  final VoidCallback onSearch;

  const _VaultCreateActions({
    required this.busy,
    required this.onEntry,
    required this.onSsh,
    required this.onTotp,
    required this.onFile,
    required this.onTextFile,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (key: 'add-totp', icon: Icons.timer_outlined, label: t.totpAdd, run: onTotp),
      (key: 'add-ssh', icon: Icons.terminal_rounded, label: t.sshAdd, run: onSsh),
      (key: 'add-file', icon: Icons.upload_file_outlined, label: t.vaultAddFile, run: onFile),
      (key: 'new-text-file', icon: Icons.note_add_outlined, label: t.vaultCreateTextFile, run: onTextFile),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Flexible(
            child: FilledButton.icon(
              key: const Key('add-entry'),
              onPressed: busy ? null : onEntry,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(t.vaultAddEntry, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          for (final action in actions) ...[
            DesktopIconButton(
              key: Key(action.key),
              tooltip: action.label,
              onPressed: busy ? null : action.run,
              icon: Icon(action.icon, size: 17),
            ),
            const SizedBox(width: 2),
          ],
          const SizedBox(width: 4),
          DesktopIconButton(
            key: const Key('open-vault-search'),
            tooltip: t.browserSearch,
            onPressed: busy ? null : onSearch,
            icon: const Icon(Icons.search_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
