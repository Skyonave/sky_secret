import 'dart:async';

import 'package:flutter/material.dart';

typedef SensitiveSelectionTransfer = Future<void> Function({required bool cut});

abstract final class SensitiveTextActions {
  static Action<CopySelectionTextIntent> copyAction(SensitiveSelectionTransfer transfer) =>
      CallbackAction<CopySelectionTextIntent>(
        onInvoke: (intent) {
          unawaited(transfer(cut: intent.collapseSelection));
          return null;
        },
      );

  static List<ContextMenuButtonItem> menuItems({
    required List<ContextMenuButtonItem> original,
    required SensitiveSelectionTransfer transfer,
    required VoidCallback hideToolbar,
  }) {
    final items = <ContextMenuButtonItem>[];
    for (final item in original) {
      final copiesText = item.type == ContextMenuButtonType.copy || item.type == ContextMenuButtonType.cut;
      if (copiesText) {
        items.add(
          ContextMenuButtonItem(
            type: item.type,
            label: item.label,
            onPressed: () {
              unawaited(transfer(cut: item.type == ContextMenuButtonType.cut));
              hideToolbar();
            },
          ),
        );
      } else {
        items.add(item);
      }
    }
    return items;
  }
}
