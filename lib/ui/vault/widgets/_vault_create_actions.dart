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
    final actions = [
      (key: 'add-entry', icon: Icons.add_rounded, label: t.vaultAddEntry, run: onEntry),
      (key: 'add-totp', icon: Icons.timer_outlined, label: t.totpAdd, run: onTotp),
      (key: 'add-ssh', icon: Icons.terminal_rounded, label: t.sshAdd, run: onSsh),
      (key: 'add-file', icon: Icons.upload_file_outlined, label: t.vaultAddFile, run: onFile),
      (key: 'new-text-file', icon: Icons.note_add_outlined, label: t.vaultCreateTextFile, run: onTextFile),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 56).floor().clamp(1, 5);
          final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  height: 40,
                  child: IconButton.filledTonal(
                    key: Key(action.key),
                    tooltip: action.label,
                    onPressed: busy ? null : action.run,
                    padding: const EdgeInsets.all(10),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(action.icon, size: 20),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
