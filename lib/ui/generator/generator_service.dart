import 'package:flutter/services.dart';

import '../../core/crypto/generator_options.dart';
import '../../core/crypto/passphrase_words.dart';
import '../../core/crypto/password_generator.dart';
import '../../core/settings/generator_preferences.dart';

class GeneratorService {
  final GeneratorPreferences preferences;
  final _generator = PasswordGenerator();
  Future<PassphraseWords>? _dictionary;

  GeneratorService(this.preferences);

  Future<PassphraseWords> _loadDictionary() async {
    try {
      return PassphraseWords.parse(await rootBundle.loadString('assets/wordlists/eff_large_wordlist.txt'));
    } catch (_) {
      _dictionary = null;
      rethrow;
    }
  }

  Future<String> generate(GeneratorOptions options) async {
    final dictionary = options.mode == GeneratorMode.passphrase ? await (_dictionary ??= _loadDictionary()) : null;
    return _generator.generateWith(options, dictionary: dictionary);
  }
}
