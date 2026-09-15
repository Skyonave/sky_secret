import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../settings/shortcut_settings.dart';

abstract class DesktopActions extends ChangeNotifier {
  VoidCallback? onBeforeHide;
  VoidCallback? onAfterShow;

  String? get notice;

  Future<void> hide();

  Future<void> drag();

  HotKey get shortcut => defaultShortcut();
  HotKey get searchShortcut => defaultSearchShortcut();

  void setSearchHandler(VoidCallback? handler) {}

  Future<String?> updateSearchShortcut(HotKey candidate) async => null;

  Future<String?> updateShortcut(HotKey shortcut);

  void setShortcutCapture(bool capturing) {}

  void setFileDragHover(bool hovering) {}

  void setFileDragActive(bool active) {}

  void setSshAuthenticationPending(bool pending) {}

  void onCompanionBlur() {}

  Future<bool> focusFileDrop() async => true;
}
