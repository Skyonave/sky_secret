part of '../vault_panel.dart';

class _VaultUnlockForm extends StatelessWidget {
  final bool exists;
  final bool busy;
  final TextEditingController vaultName;
  final TextEditingController master;
  final TextEditingController confirmation;
  final VoidCallback onOpen;

  const _VaultUnlockForm({
    required this.exists,
    required this.busy,
    required this.vaultName,
    required this.master,
    required this.confirmation,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        exists ? t.vaultUnlockHelp : t.vaultCreateHelp,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      const SizedBox(height: 16),
      if (!exists)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            t.vaultPasswordRequirements,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      if (!exists)
        _VaultField(
          controller: vaultName,
          label: t.vaultNameOptional,
          fieldKey: 'vault-display-name',
          busy: busy,
          textInputAction: TextInputAction.next,
        ),
      _VaultField(
        controller: master,
        label: t.vaultMasterPassword,
        fieldKey: 'vault-master',
        busy: busy,
        secret: true,
        textInputAction: exists ? TextInputAction.done : TextInputAction.next,
        onSubmit: exists ? onOpen : null,
      ),
      if (!exists)
        _VaultField(
          controller: confirmation,
          label: t.vaultConfirmPassword,
          fieldKey: 'vault-confirm',
          busy: busy,
          secret: true,
          textInputAction: TextInputAction.done,
          onSubmit: onOpen,
        ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const Key('open-vault'),
          onPressed: busy ? null : onOpen,
          icon: const Icon(Icons.lock_open_outlined, size: 16),
          label: Text(busy ? t.vaultWorking : (exists ? t.vaultUnlock : t.vaultCreate)),
        ),
      ),
    ],
  );
}
