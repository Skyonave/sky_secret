part of '../vault_panel.dart';

class _VaultCreateActions extends StatelessWidget {
  final bool busy;
  final VoidCallback onEntry;
  final VoidCallback onSsh;
  final VoidCallback onTotp;
  final VoidCallback onFile;
  final VoidCallback onTextFile;

  const _VaultCreateActions({
    required this.busy,
    required this.onEntry,
    required this.onSsh,
    required this.onTotp,
    required this.onFile,
    required this.onTextFile,
  });

  @override
  Widget build(BuildContext context) {
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('add-entry'),
          onPressed: busy ? null : onEntry,
          icon: const Icon(Icons.add_rounded),
          label: Text(t.vaultAddEntry),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-totp'),
          onPressed: busy ? null : onTotp,
          style: outlinedStyle,
          icon: const Icon(Icons.timer_outlined, size: 20),
          label: Text(t.totpAdd),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-ssh'),
          onPressed: busy ? null : onSsh,
          style: outlinedStyle,
          icon: const Icon(Icons.terminal_rounded, size: 20),
          label: Text(t.sshAdd),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-file'),
          onPressed: busy ? null : onFile,
          style: outlinedStyle,
          icon: const Icon(Icons.upload_file_outlined, size: 20),
          label: Text(t.vaultAddFile),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('new-text-file'),
          onPressed: busy ? null : onTextFile,
          style: outlinedStyle,
          icon: const Icon(Icons.note_add_outlined, size: 20),
          label: Text(t.vaultCreateTextFile),
        ),
      ],
    );
  }
}
