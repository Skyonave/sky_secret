import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';

import '../storage/app_data_directory.dart';
import '../storage/local_file.dart';

HotKey defaultShortcut() => HotKey(
  key: PhysicalKeyboardKey.space,
  modifiers: [HotKeyModifier.shift],
  scope: HotKeyScope.system,
);

const supportedModifiers = [
  HotKeyModifier.control,
  HotKeyModifier.alt,
  HotKeyModifier.shift,
  HotKeyModifier.meta,
];

bool validShortcut(HotKey key) {
  try {
    return key.scope == HotKeyScope.system &&
        key.physicalKey.keyCode != null &&
        !HotKeyModifier.values.any(
          (m) => m.physicalKeys.contains(key.physicalKey),
        ) &&
        (key.modifiers ?? []).every(supportedModifiers.contains);
  } catch (_) {
    return false;
  }
}

bool sameShortcut(HotKey a, HotKey b) =>
    a.physicalKey == b.physicalKey &&
    supportedModifiers.every(
      (m) => (a.modifiers ?? []).contains(m) == (b.modifiers ?? []).contains(m),
    );

const modifierLabels = {
  HotKeyModifier.control: 'Ctrl',
  HotKeyModifier.alt: 'Alt',
  HotKeyModifier.shift: 'Shift',
  HotKeyModifier.meta: 'Win',
};

String shortcutLabel(HotKey key) {
  final physical = key.physicalKey;
  final label = physical == PhysicalKeyboardKey.space ? 'Space' : physical.logicalKey?.keyLabel;
  return [
    for (final modifier in supportedModifiers)
      if ((key.modifiers ?? []).contains(modifier)) modifierLabels[modifier]!,
    if (label != null && label.isNotEmpty) label else '0x${physical.usbHidUsage.toRadixString(16)}',
  ].join(' + ');
}

class ShortcutStore {
  final File file;

  ShortcutStore({File? file})
    : file =
          file ??
          File(
            '${appDataDirectory().path}${Platform.pathSeparator}settings.json',
          );

  Future<HotKey?> load() async {
    final bytes = await readBoundedFile(file, maxBytes: 16 * 1024);
    if (bytes == null) return null;
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown settings version');
    }
    final key = HotKey.fromJson(json['shortcut'] as Map<String, dynamic>);
    if (!validShortcut(key)) throw const FormatException('Invalid shortcut');
    return key;
  }

  Future<void> save(HotKey key) async {
    if (!validShortcut(key)) throw const FormatException('Invalid shortcut');
    await writeAtomicFile(
      file,
      utf8.encode(jsonEncode({'version': 1, 'shortcut': key.toJson()})),
    );
  }
}
