import 'dart:math';

import 'generator_options.dart';
import 'passphrase_words.dart';

class PasswordGenerator {
  final Random _random = Random.secure();
  static const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const digits = '0123456789';
  static const punctuation = '!@#\$%&*+-=?_';

  String generateWith(GeneratorOptions options, {PassphraseWords? dictionary}) {
    if (!options.valid) throw ArgumentError('Invalid generator options');
    if (options.mode == GeneratorMode.passphrase) {
      if (dictionary == null) throw ArgumentError.notNull('dictionary');
      return List.generate(
        options.wordCount,
        (_) => dictionary.words[_random.nextInt(dictionary.words.length)],
      ).join(options.separator);
    }
    final groups =
        [
              if (options.lowercase) 'abcdefghijklmnopqrstuvwxyz',
              if (options.uppercase) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
              if (options.digits) digits,
              if (options.symbols) punctuation,
            ]
            .map(
              (group) => options.excludeSimilar
                  ? group.split('').where((character) => !'O0oIl1'.contains(character)).join()
                  : group,
            )
            .toList();
    final alphabet = groups.join();
    while (true) {
      final result = List.generate(options.length, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
      if (groups.every((group) => result.split('').any(group.contains))) return result;
    }
  }

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
