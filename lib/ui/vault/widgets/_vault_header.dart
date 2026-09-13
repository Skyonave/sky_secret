part of '../vault_panel.dart';

class _VaultHeader extends StatelessWidget {
  final String title;
  final bool unlocked;
  final bool renaming;
  final TextEditingController renameName;
  final bool busy;
  final bool renameInvalid;
  final bool savingPreferences;
  final bool showSettings;
  final Widget? switcher;
  final VoidCallback onRename;
  final VoidCallback onStartRename;
  final VoidCallback onCancelRename;
  final VoidCallback onSettings;
  final VoidCallback onLock;

  const _VaultHeader({
    required this.title,
    required this.unlocked,
    required this.renaming,
    required this.renameName,
    required this.busy,
    required this.renameInvalid,
    required this.savingPreferences,
    required this.showSettings,
    required this.switcher,
    required this.onRename,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSettings,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: renaming && unlocked
            ? SensitiveTextEditing(
                controller: renameName,
                enabled: !busy,
                readOnly: false,
                obscureText: false,
                builder: (context, menuBuilder) => TextField(
                  contextMenuBuilder: menuBuilder,
                  enableIMEPersonalizedLearning: false,
                  key: const Key('vault-inline-name'),
                  controller: renameName,
                  autofocus: true,
                  enabled: !busy,
                  maxLength: 120,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: t.vaultName,
                    errorText: renameInvalid ? t.vaultNameRequired : null,
                  ),
                  onSubmitted: (_) => onRename(),
                ),
              )
            : Tooltip(
                message: unlocked == false ? '' : t.vaultRename,
                child: TextButton(
                  key: const Key('vault-heading'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: unlocked == false || busy ? null : onStartRename,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
      ),
      ?switcher,
      if (renaming && unlocked) ...[
        IconButton(
          key: const Key('confirm-vault-name'),
          tooltip: t.save,
          onPressed: busy ? null : onRename,
          icon: const Icon(Icons.check_rounded, size: 20),
        ),
        IconButton(
          key: const Key('cancel-vault-name'),
          tooltip: t.cancel,
          onPressed: busy ? null : onCancelRename,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
      if (showSettings)
        IconButton(
          key: const Key('vault-settings'),
          tooltip: t.vaultSettings,
          onPressed: savingPreferences ? null : onSettings,
          icon: const Icon(Icons.settings_outlined, size: 21),
        ),
      if (unlocked)
        IconButton(
          key: const Key('lock-vault'),
          tooltip: t.vaultLock,
          onPressed: busy ? null : onLock,
          icon: const Icon(Icons.lock_outline_rounded),
        ),
    ],
  );
}
