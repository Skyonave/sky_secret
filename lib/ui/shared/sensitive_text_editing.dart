import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';
import 'sensitive_text_actions.dart';
import 'sensitive_text_transfer.dart';

class SensitiveClipboardScope extends InheritedTheme {
  final Future<bool> Function(String) copy;

  const SensitiveClipboardScope({
    super.key,
    required this.copy,
    required super.child,
  });

  static Future<bool> copyText(BuildContext context, String text) async {
    final scope = context.dependOnInheritedWidgetOfExactType<SensitiveClipboardScope>();
    return await scope?.copy(text) ?? false;
  }

  @override
  Widget wrap(BuildContext context, Widget child) => SensitiveClipboardScope(copy: copy, child: child);

  @override
  bool updateShouldNotify(SensitiveClipboardScope oldWidget) => oldWidget.copy != copy;
}

class SensitiveTextEditing extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final Future<bool> Function(String)? copy;
  final Widget Function(BuildContext, EditableTextContextMenuBuilder) builder;

  const SensitiveTextEditing({
    super.key,
    required this.controller,
    required this.builder,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.copy,
  });

  @override
  State<SensitiveTextEditing> createState() => _SensitiveTextEditingState();
}

class _SensitiveTextEditingState extends State<SensitiveTextEditing> {
  Future<void> _transfer({required bool cut}) async {
    final controller = widget.controller;
    final copy = widget.copy ?? (text) => SensitiveClipboardScope.copyText(context, text);
    try {
      await SensitiveTextTransfer.copySelection(
        controller: controller,
        copy: copy,
        cut: cut,
        readOnly: widget.readOnly,
        obscureText: widget.obscureText,
        isActive: () =>
            mounted &&
            widget.enabled &&
            widget.controller == controller &&
            widget.obscureText == false &&
            (cut == false || widget.readOnly == false),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.clipboardBusy)));
      }
    }
  }

  Widget _contextMenu(BuildContext context, EditableTextState state) {
    final items = SensitiveTextActions.menuItems(
      original: state.contextMenuButtonItems,
      transfer: _transfer,
      hideToolbar: state.hideToolbar,
    );
    return AdaptiveTextSelectionToolbar.buttonItems(anchors: state.contextMenuAnchors, buttonItems: items);
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      CopySelectionTextIntent: SensitiveTextActions.copyAction(_transfer),
    },
    child: Builder(builder: (context) => widget.builder(context, _contextMenu)),
  );
}
