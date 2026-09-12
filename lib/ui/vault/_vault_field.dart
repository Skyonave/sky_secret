part of 'vault_panel.dart';

class _VaultField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String fieldKey;
  final bool busy;
  final bool secret;
  final int lines;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmit;

  const _VaultField({
    required this.controller,
    required this.label,
    required this.fieldKey,
    required this.busy,
    this.secret = false,
    this.lines = 1,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SensitiveTextEditing(
      controller: controller,
      enabled: !busy,
      readOnly: false,
      obscureText: secret,
      builder: (context, menuBuilder) => TextField(
        contextMenuBuilder: menuBuilder,
        enableIMEPersonalizedLearning: false,
        key: Key(fieldKey),
        controller: controller,
        enabled: !busy,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: textInputAction,
        onEditingComplete: onSubmit == null ? null : controller.clearComposing,
        onSubmitted: onSubmit == null ? null : (_) => onSubmit?.call(),
        maxLength: fieldKey == 'vault-display-name' ? 120 : (fieldKey.startsWith('vault-') ? 1048576 : 65536),
        minLines: 1,
        maxLines: lines,
        decoration: InputDecoration(
          counterText: '',
          suffixIcon: suffixIcon,
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
  );
}
