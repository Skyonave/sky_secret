import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../settings/shortcut_settings.dart';

abstract class DesktopActions extends ChangeNotifier {
  VoidCallback? onBeforeHide;

  String? get notice;

  Future<void> hide();

  Future<void> drag();

  HotKey get shortcut => defaultShortcut();

  Future<String?> updateShortcut(HotKey shortcut);

  void setShortcutCapture(bool capturing) {}

  void setFileDragHover(bool hovering) {}

  void setSshAuthenticationPending(bool pending) {}

  Future<bool> focusFileDrop() async => true;
}
