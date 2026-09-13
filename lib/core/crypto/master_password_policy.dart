import 'package:characters/characters.dart';

abstract final class MasterPasswordPolicy {
  static const minimumLength = 16;
  static final _separators = RegExp(r'[\s\p{P}\p{S}]', unicode: true);
  static final _controls = RegExp(r'\p{Cc}', unicode: true);
  static const _common = {
    'password',
    'пароль',
    'qwerty',
    'admin',
    'administrator',
    'letmein',
    'welcome',
    'iloveyou',
    'skysecret',
    'correcthorsebatterystaple',
  };

  static bool accepts(String password) {
    if (password.length > 1024 * 1024 ||
        password.characters.take(minimumLength).length < minimumLength ||
        password.trim().isEmpty ||
        _controls.hasMatch(password)) {
      return false;
    }
    final lower = password.toLowerCase();
    final compact = lower.replaceAll(_separators, '');
    final base = compact.replaceAll(RegExp(r'[0-9]+$'), '');
    if (_common.contains(base)) return false;
    for (final sequence in ['0123456789', '1234567890', 'abcdefghijklmnopqrstuvwxyz', 'qwertyuiop']) {
      if (compact.isNotEmpty && _repeats(compact, sequence)) return false;
    }
    for (var width = 1; width <= 8 && width * 2 <= lower.length; width++) {
      if (_repeats(lower, lower.substring(0, width))) return false;
    }
    return true;
  }

  static bool _repeats(String value, String pattern) {
    for (var index = 0; index < value.length; index++) {
      if (value.codeUnitAt(index) != pattern.codeUnitAt(index % pattern.length)) return false;
    }
    return true;
  }

  static void validate(String password) {
    if (!accepts(password)) throw const MasterPasswordPolicyException();
  }
}

class MasterPasswordPolicyException implements Exception {
  const MasterPasswordPolicyException();
}
