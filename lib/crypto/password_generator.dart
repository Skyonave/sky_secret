import 'dart:math';

class PasswordGenerator {
  final Random _random = Random.secure();
  static const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const digits = '0123456789';
  static const punctuation = '!@#\$%&*+-=?_';

  String generate({int length = 24, bool symbols = true}) {
    if (length < 12 || length > 64) {
      throw RangeError.range(length, 12, 64, 'length');
    }
    final groups = [letters, digits, if (symbols) punctuation];
    final alphabet = groups.join();
    while (true) {
      final result = List.generate(
        length,
        (_) => alphabet[_random.nextInt(alphabet.length)],
      ).join();
      if (groups.every((group) => result.split('').any(group.contains))) {
        return result;
      }
    }
  }
}
