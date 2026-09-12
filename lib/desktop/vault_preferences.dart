import 'dart:convert';
import 'dart:io';

import '../storage/app_data_directory.dart';

class VaultPreferences {
  final File? file;
  bool _autoLockEnabled = true;
  bool _lockWhenHidden = true;
  bool _captureAllowed = false;

  VaultPreferences({this.file});

  factory VaultPreferences.local() => VaultPreferences(
    file: File('${appDataDirectory().path}${Platform.pathSeparator}vault_preferences.json'),
  );

  bool get lockWhenHidden => _lockWhenHidden;

  bool get captureAllowed => _captureAllowed;

  Future<bool> loadAutoLock() async {
    final source = file;
    if (source == null || !await source.exists()) return _autoLockEnabled;
    final data = jsonDecode(await source.readAsString());
    if (data is! Map ||
        data['version'] != 1 ||
        data['autoLockEnabled'] is! bool ||
        (data.containsKey('lockWhenHidden') && data['lockWhenHidden'] is! bool) ||
        (data.containsKey('captureAllowed') && data['captureAllowed'] is! bool)) {
      throw const FormatException('Invalid vault preferences');
    }
    _lockWhenHidden = data['lockWhenHidden'] as bool? ?? true;
    _captureAllowed = data['captureAllowed'] as bool? ?? false;
    return _autoLockEnabled = data['autoLockEnabled'] as bool;
  }

  Future<void> saveAutoLock(bool enabled) => save(enabled, lockWhenHidden: _lockWhenHidden);

  Future<void> save(
    bool enabled, {
    required bool lockWhenHidden,
    bool? captureAllowed,
  }) async {
    final nextCaptureAllowed = captureAllowed ?? _captureAllowed;
    final target = file;
    if (target != null) {
      await target.parent.create(recursive: true);
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'autoLockEnabled': enabled,
          'lockWhenHidden': lockWhenHidden,
          'captureAllowed': nextCaptureAllowed,
        }),
        flush: true,
      );
      await temporary.rename(target.path);
    }
    _autoLockEnabled = enabled;
    _lockWhenHidden = lockWhenHidden;
    _captureAllowed = nextCaptureAllowed;
  }
}
