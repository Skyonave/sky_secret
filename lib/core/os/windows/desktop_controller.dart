import 'dart:async';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:uni_platform/uni_platform.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

import '../../../i18n/translations.g.dart';
import '../../desktop/desktop_actions.dart';
import '../../desktop/focus_dismissal.dart';
import '../../desktop/system_shortcut.dart';
import '../../settings/shortcut_settings.dart';
import '../../settings/vault_preferences.dart';
import 'window_privacy.dart';
import 'window_work_area.dart';

class DesktopController extends DesktopActions with WindowListener, TrayListener {
  static const _managerWidth = 460.0;
  final _ready = Completer<void>();
  final ShortcutStore _settings;
  final void Function()? onExit;
  HotKey _shortcut = defaultShortcut();
  HotKey _searchShortcut = defaultSearchShortcut();
  final _searchSettings = ShortcutStore.search();
  void Function()? _searchHandler;
  bool _managerVisible = false;
  bool _searchRegistered = false;
  Future<void> _searchTransition = Future.value();

  @override
  HotKey get searchShortcut => _searchShortcut;

  @override
  void setSearchHandler(void Function()? handler) {
    if (_searchHandler == handler) return;
    _searchHandler = handler;
    _syncSearchShortcut();
  }

  void _syncSearchShortcut() {
    _searchTransition = _searchTransition
        .then((_) async {
          final enabled = _managerVisible && _searchHandler != null && !_capturingShortcut && !_exiting;
          if (enabled == _searchRegistered) return;
          if (_searchRegistered) {
            await hotKeyManager.unregister(_searchShortcut);
            _searchRegistered = false;
          } else if (enabled) {
            const probeId = 0x5350;
            final available = win32.RegisterHotKey(
              null,
              probeId,
              _nativeModifiers(_searchShortcut),
              _searchShortcut.physicalKey.keyCode!,
            );
            if (!available.value) throw StateError('Search shortcut unavailable');
            win32.UnregisterHotKey(null, probeId);
            await registerSystemShortcut(
              _searchShortcut,
              keyDownHandler: (_) {
                if (_managerVisible && !_capturingShortcut && !_exiting) _searchHandler?.call();
              },
            );
            _searchRegistered = true;
          }
        })
        .catchError((_) {
          _notice = t.shortcutUnavailable(shortcut: shortcutLabel(_searchShortcut));
          notifyListeners();
        });
  }

  @override
  Future<String?> updateSearchShortcut(HotKey candidate) async {
    if (!validShortcut(candidate)) return t.unsupportedShortcut;
    if (sameShortcut(candidate, _shortcut)) return t.shortcutBusy;
    if (sameShortcut(candidate, _searchShortcut)) return null;
    await _searchTransition;
    if (_searchRegistered) {
      await hotKeyManager.unregister(_searchShortcut);
      _searchRegistered = false;
    }
    try {
      const probeId = 0x534F;
      if (!win32.RegisterHotKey(null, probeId, _nativeModifiers(candidate), candidate.physicalKey.keyCode!).value) {
        return t.shortcutBusy;
      }
      win32.UnregisterHotKey(null, probeId);
      await _searchSettings.save(candidate);
      _searchShortcut = candidate;
      notifyListeners();
      return null;
    } catch (_) {
      return t.saveSettingsFailed;
    } finally {
      _syncSearchShortcut();
    }
  }

  bool _capturingShortcut = false;
  bool _changingShortcut = false;
  String? _notice;
  bool _registered = false;
  bool _exiting = false;
  bool _transitioning = false;
  bool _hotkeyHeld = false;
  bool _windowFocused = false;
  Timer? _releaseTimer;
  bool _fileDragHover = false;
  bool _fileDragActive = false;
  bool _focusingDrop = false;
  bool _trayMenuOpen = false;
  bool _sshAuthenticationPending = false;
  late final _blurDismissal = FocusDismissal(
    readState: _readDismissalState,
    dismiss: hide,
  );

  DesktopController({ShortcutStore? settings, this.onExit}) : _settings = settings ?? ShortcutStore();

  @override
  HotKey get shortcut => _shortcut;

  @override
  void setShortcutCapture(bool capturing) {
    _capturingShortcut = capturing;
    _syncSearchShortcut();
  }

  @override
  void setSshAuthenticationPending(bool pending) {
    _sshAuthenticationPending = pending;
    if (pending) {
      _blurDismissal.cancel();
    } else if (!_windowFocused && !_exiting && _ready.isCompleted) {
      _blurDismissal.request();
    }
  }

  bool _keyDown(int key) => (win32.GetAsyncKeyState(key) & 0x8000) != 0;

  @override
  void setFileDragHover(bool hovering) => _fileDragHover = hovering;

  @override
  void setFileDragActive(bool active) {
    _fileDragActive = active;
    if (active) {
      _blurDismissal.cancel();
    } else if (_managerVisible && !_windowFocused) {
      onCompanionBlur();
    }
  }

  @override
  Future<bool> focusFileDrop() async {
    _blurDismissal.cancel();
    _fileDragHover = false;
    _focusingDrop = true;
    try {
      if (_exiting || !await windowManager.isVisible()) return false;
      await windowManager.focus();
      return true;
    } finally {
      _focusingDrop = false;
    }
  }

  @override
  String? get notice => _notice;

  Future<void> initialize() async {
    try {
      final saved = await _settings.load() ?? defaultShortcut();
      _searchShortcut = await _searchSettings.load() ?? defaultSearchShortcut();
      _shortcut = HotKey(
        key: saved.physicalKey,
        modifiers: saved.modifiers ?? [],
      );
    } catch (_) {
      _notice = t.readSettingsFailed;
    }
    await windowManager.ensureInitialized();
    var captureAllowed = false;
    try {
      final preferences = VaultPreferences.local();
      await preferences.loadAutoLock();
      captureAllowed = preferences.captureAllowed;
    } catch (_) {
      _notice = t.vaultPreferencesReadFailed;
    }
    if (!await WindowPrivacy.initialize(captureAllowed: captureAllowed)) _notice = t.captureSettingFailed;
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(_managerWidth, 600),
        minimumSize: Size(_managerWidth, 520),
        maximumSize: Size(_managerWidth, 600),
        center: false,
        skipTaskbar: true,
        title: t.appName,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
    );
    await windowManager.setPreventClose(true);
    await windowManager.hide();

    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip(
        t.trayTooltip(shortcut: shortcutLabel(_shortcut)),
      );
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show',
              label: t.openManager(shortcut: shortcutLabel(_shortcut)),
            ),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: t.exit),
          ],
        ),
      );
      final bounds = await trayManager.getBounds();
      if (bounds == null || bounds.isEmpty) {
        throw StateError('Tray icon was not registered');
      }
    } catch (_) {
      _notice = t.trayFailed;
      _ready.complete();
      notifyListeners();
      await windowManager.setPreventClose(false);
      await windowManager.setSkipTaskbar(false);
      await show();
      return;
    }

    const probeId = 0x534D;
    final probe = win32.RegisterHotKey(
      null,
      probeId,
      _nativeModifiers(_shortcut),
      _shortcut.physicalKey.keyCode!,
    );
    if (probe.value) {
      win32.UnregisterHotKey(null, probeId);
      try {
        await registerSystemShortcut(
          _shortcut,
          keyDownHandler: (_) => _onHotkey(),
        );
        _registered = true;
      } catch (_) {
        _notice = t.shortcutUnavailable(shortcut: shortcutLabel(_shortcut));
      }
    } else {
      _notice = t.shortcutTaken(shortcut: shortcutLabel(_shortcut));
    }
    _ready.complete();
    notifyListeners();
  }

  void _onHotkey() {
    if (_hotkeyHeld || _exiting || (_capturingShortcut && _windowFocused)) {
      return;
    }
    _hotkeyHeld = true;
    _releaseTimer?.cancel();
    _releaseTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if ((win32.GetAsyncKeyState(_shortcut.physicalKey.keyCode!) & 0x8000) == 0) {
        _hotkeyHeld = false;
        timer.cancel();
      }
    });
    unawaited(toggle());
  }

  win32.HOT_KEY_MODIFIERS _nativeModifiers(HotKey key) {
    var flags = win32.MOD_NOREPEAT;
    for (final modifier in key.modifiers ?? <HotKeyModifier>[]) {
      flags |= switch (modifier) {
        HotKeyModifier.control => win32.MOD_CONTROL,
        HotKeyModifier.alt => win32.MOD_ALT,
        HotKeyModifier.shift => win32.MOD_SHIFT,
        HotKeyModifier.meta => win32.MOD_WIN,
        _ => const win32.HOT_KEY_MODIFIERS(0),
      };
    }
    return flags;
  }

  @override
  Future<String?> updateShortcut(HotKey candidate) async {
    await _ready.future;
    if (_changingShortcut || _exiting) return t.retry;
    if (!validShortcut(candidate)) return t.unsupportedShortcut;
    if (_registered && sameShortcut(candidate, _shortcut)) return null;
    if (sameShortcut(candidate, _searchShortcut)) return t.shortcutBusy;
    _changingShortcut = true;
    final next = HotKey(
      key: candidate.physicalKey,
      modifiers: candidate.modifiers ?? [],
    );
    var nextRegistered = false;
    try {
      const probeId = 0x534E;
      final probe = win32.RegisterHotKey(
        null,
        probeId,
        _nativeModifiers(next),
        next.physicalKey.keyCode!,
      );
      if (!probe.value) {
        return t.shortcutBusy;
      }
      win32.UnregisterHotKey(null, probeId);
      await registerSystemShortcut(next, keyDownHandler: (_) => _onHotkey());
      nextRegistered = true;
      try {
        await _settings.save(next);
      } catch (_) {
        return t.saveSettingsFailed;
      }
      if (_registered) await hotKeyManager.unregister(_shortcut);
      _shortcut = next;
      _registered = true;
      nextRegistered = false;
      _hotkeyHeld = false;
      _releaseTimer?.cancel();
      _notice = null;
      try {
        await trayManager.setToolTip(
          t.trayTooltip(shortcut: shortcutLabel(next)),
        );
        await trayManager.setContextMenu(
          Menu(
            items: [
              MenuItem(
                key: 'show',
                label: t.openManager(shortcut: shortcutLabel(next)),
              ),
              MenuItem.separator(),
              MenuItem(key: 'exit', label: t.exit),
            ],
          ),
        );
      } catch (_) {
        _notice = t.trayUpdateFailed;
      }
      notifyListeners();
      return null;
    } catch (_) {
      return t.shortcutFailed;
    } finally {
      if (nextRegistered) await hotKeyManager.unregister(next);
      _changingShortcut = false;
    }
  }

  Future<void> toggle() async {
    await _ready.future;
    if (_transitioning || _exiting) return;
    _transitioning = true;
    try {
      if (await windowManager.isVisible() && await windowManager.isFocused()) {
        await hide();
      } else {
        await _showWindow(preserveDragFocus: _keyDown(0x01));
      }
    } finally {
      _transitioning = false;
    }
  }

  Future<void> show() async {
    await _ready.future;
    if (!_exiting) await _showWindow();
  }

  Future<void> _showWindow({bool preserveDragFocus = false}) async {
    _blurDismissal.cancel();
    if (await windowManager.isMinimized()) await windowManager.restore();
    final work = windowWorkArea(await windowManager.getId());
    final height = (work.height - 100).clamp(360.0, 600.0);
    await windowManager.setMinimumSize(Size(_managerWidth, height < 520 ? height : 520));
    await windowManager.setMaximumSize(Size(_managerWidth, height));
    final size = await windowManager.getSize();
    if (size.width != _managerWidth || size.height > height) {
      await windowManager.setSize(Size(_managerWidth, size.height.clamp(0.0, height)));
    }
    final corner = await calcWindowPosition(
      await windowManager.getSize(),
      Alignment.bottomRight,
    );
    await windowManager.setPosition(corner - const Offset(12, 12));
    await windowManager.show(inactive: preserveDragFocus);
    if (preserveDragFocus) {
      _blurDismissal.request();
    } else {
      await windowManager.focus();
    }
    onAfterShow?.call();
    _managerVisible = true;
    _syncSearchShortcut();
  }

  @override
  Future<void> hide() {
    _managerVisible = false;
    _syncSearchShortcut();
    _blurDismissal.cancel();
    _fileDragHover = false;
    onBeforeHide?.call();
    return windowManager.hide();
  }

  @override
  void onWindowFocus() {
    _blurDismissal.cancel();
    _windowFocused = true;
  }

  @override
  void onWindowBlur() {
    _windowFocused = false;
    if (!_exiting && _ready.isCompleted) {
      _blurDismissal.request();
    }
  }

  Future<DismissalState> _readDismissalState() async {
    final focused = await windowManager.isFocused();
    final ownDialog = using((arena) {
      final processId = arena<Uint32>();
      win32.GetWindowThreadProcessId(win32.GetForegroundWindow(), processId);
      return processId.value == win32.GetCurrentProcessId();
    });
    return (
      protectedFocus: _exiting || _focusingDrop || _fileDragActive || _sshAuthenticationPending || focused || ownDialog,
      leftDown: _keyDown(0x01),
      cancelDrag: _keyDown(0x02) || _keyDown(0x04) || _keyDown(0x1B),
      fileOver: _fileDragHover,
    );
  }

  @override
  void onCompanionBlur() {
    if (!_exiting && _ready.isCompleted) _blurDismissal.request();
  }

  @override
  Future<void> drag() => windowManager.startDragging();

  @override
  void onWindowClose() {
    if (!_exiting) unawaited(hide());
  }

  @override
  void onWindowMinimize() => unawaited(hide());

  @override
  void onTrayIconMouseDown() => unawaited(show());

  @override
  void onTrayIconRightMouseDown() => unawaited(_showTrayMenu());

  Future<void> _showTrayMenu() async {
    if (_exiting || _trayMenuOpen) return;
    _trayMenuOpen = true;
    try {
      final id = await windowManager.getId();
      if (id == 0 || _exiting) return;
      final owner = win32.HWND(Pointer.fromAddress(id));
      try {
        win32.SetForegroundWindow(owner);
        await trayManager.popUpContextMenu();
      } finally {
        win32.PostMessage(
          owner,
          win32.WM_NULL,
          const win32.WPARAM(0),
          const win32.LPARAM(0),
        );
      }
    } finally {
      _trayMenuOpen = false;
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') unawaited(show());
    if (menuItem.key == 'exit') unawaited(quit());
  }

  Future<void> quit() async {
    if (_exiting) return;
    await releaseResources();
    await windowManager.destroy();
    onExit?.call();
  }

  Future<void> releaseResources() async {
    if (_exiting) return;
    _exiting = true;
    _managerVisible = false;
    _searchHandler = null;
    _syncSearchShortcut();
    await _searchTransition;
    _blurDismissal.cancel();
    _releaseTimer?.cancel();
    if (_registered) await hotKeyManager.unregister(_shortcut);
    trayManager.removeListener(this);
    await trayManager.destroy();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
  }
}
