import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop/search_session.dart';
import 'vault_search_window.dart';

class VaultSearchPresenter {
  Route<String>? _route;
  VaultSearchSession? _session;
  bool _opening = false;
  int _epoch = 0;

  Future<String?> open({
    required BuildContext context,
    required bool Function() isValid,
    required List<Map<String, Object>> Function(String) find,
    required void Function() activity,
    required Future<bool> Function(String) copy,
    required Future<void> Function() clearClipboard,
    required Future<void> Function() hide,
  }) async {
    if (_opening) return null;
    _opening = true;
    final epoch = ++_epoch;
    Rect? bounds;
    try {
      bounds = await windowManager.getBounds();
      if (!context.mounted || !isValid() || epoch != _epoch) return null;
      final session = VaultSearchSession(isValid: isValid, find: find, activity: activity);
      _session = session;
      final route = PageRouteBuilder<String>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => VaultSearchWindow(
          session: session,
          copy: (text) async {
            if (!session.valid) return false;
            final copied = await copy(text);
            if (!session.valid) await clearClipboard();
            return session.valid && copied;
          },
        ),
      );
      _route = route;
      final result = Navigator.of(context).push(route);
      await windowManager.setMinimumSize(const Size(440, 320));
      if (session.valid && epoch == _epoch) {
        await windowManager.setSize(const Size(640, 460));
        final position = await calcWindowPosition(const Size(640, 460), Alignment.center);
        if (session.valid && epoch == _epoch) await windowManager.setPosition(position);
      } else {
        close();
      }
      final id = await result;
      final selected = session.accepts(id) ? id : null;
      if (selected == null) await hide();
      return selected;
    } finally {
      close();
      try {
        if (bounds != null) {
          await windowManager.setMinimumSize(const Size(400, 520));
          await windowManager.setBounds(bounds);
        }
      } finally {
        _opening = false;
      }
    }
  }

  void close() {
    _epoch++;
    _session?.close();
    _session = null;
    final route = _route;
    _route = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  void dispose() => close();
}
