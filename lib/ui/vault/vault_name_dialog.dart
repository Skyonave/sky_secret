import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';
import '../shared/sensitive_text_editing.dart';

class VaultNameDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initialValue;
  final List<String> existingNames;

  const VaultNameDialog({
    super.key,
    required this.title,
    required this.label,
    this.initialValue = '',
    this.existingNames = const [],
  });

  @override
  State<VaultNameDialog> createState() => _VaultNameDialogState();
}

class _VaultNameDialogState extends State<VaultNameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  final _form = GlobalKey<FormState>();

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    scrollable: true,
    content: Form(
      key: _form,
      child: SensitiveTextEditing(
        controller: _controller,
        enabled: true,
        readOnly: false,
        obscureText: false,
        builder: (context, menuBuilder) => TextFormField(
          contextMenuBuilder: menuBuilder,
          enableIMEPersonalizedLearning: false,
          key: const Key('vault-name-input'),
          controller: _controller,
          autofocus: true,
          maxLength: 120,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: widget.label, counterText: ''),
          validator: (value) {
            final name = (value ?? '').trim();
            if (name.isEmpty || name.length > 120) return t.vaultNameRequired;
            if (widget.existingNames.any(
              (n) => n.toLowerCase() == name.toLowerCase(),
            )) {
              return t.vaultFolderNameTaken;
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t.cancel),
      ),
      FilledButton(
        key: const Key('confirm-name'),
        onPressed: _submit,
        child: Text(t.save),
      ),
    ],
  );
}
