import 'package:flutter/material.dart';

import '../../../core/crypto/crypto.dart';
import '../../../i18n/translations.g.dart';
import '../../shared/input/sensitive_text_editing.dart';

typedef VaultPasswords = ({String current, String password});

class VaultPasswordDialog extends StatefulWidget {
  final bool change;

  const VaultPasswordDialog({
    super.key,
    this.change = false,
  });

  @override
  State<VaultPasswordDialog> createState() => _VaultPasswordDialogState();
}

class _VaultPasswordDialogState extends State<VaultPasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final field in [_current, _password, _confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty || (widget.change && _current.text.isEmpty)) {
      setState(() => _error = t.vaultPasswordRequired);
    } else if (widget.change && _password.text != _confirm.text) {
      setState(() => _error = t.vaultPasswordMismatch);
    } else if (widget.change && !MasterPasswordPolicy.accepts(_password.text)) {
      setState(() => _error = t.vaultPasswordRequirements);
    } else {
      final result = (current: _current.text, password: _password.text);
      for (final field in [_current, _password, _confirm]) {
        field.clear();
      }
      Navigator.pop(context, result);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SensitiveTextEditing(
      controller: controller,
      enabled: true,
      readOnly: false,
      obscureText: true,
      builder: (context, menuBuilder) => TextField(
        contextMenuBuilder: menuBuilder,
        enableIMEPersonalizedLearning: false,
        key: Key(key),
        controller: controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 1048576,
        decoration: InputDecoration(labelText: label, counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.change ? t.vaultChangePassword : t.vaultImport,
    ),
    scrollable: true,
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.change ? t.vaultChangePasswordHelp : t.vaultImportHelp,
          ),
          if (widget.change) ...[
            const SizedBox(height: 8),
            Text(t.vaultPasswordRequirements),
            const SizedBox(height: 12),
            Text(t.vaultPasswordBackupWarning),
          ],
          if (widget.change) _field(_current, t.vaultCurrentPassword, 'current-master'),
          _field(
            _password,
            widget.change ? t.vaultNewPassword : t.vaultMasterPassword,
            'transfer-master',
          ),
          if (widget.change) _field(_confirm, t.vaultConfirmPassword, 'transfer-confirm'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t.cancel),
      ),
      FilledButton(
        key: const Key('confirm-password-action'),
        onPressed: _submit,
        child: Text(widget.change ? t.save : t.vaultImport),
      ),
    ],
  );
}
