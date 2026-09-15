import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/generator_options.dart';
import 'package:skysecret/core/crypto/passphrase_words.dart';
import 'package:skysecret/core/crypto/password_generator.dart';

void main() {
  final generator = PasswordGenerator();
  final source = File('assets/wordlists/eff_large_wordlist.txt').readAsStringSync();
  final dictionary = PassphraseWords.parse(source);

  test('every nonempty group combination obeys length, inclusion and exclusions', () {
    for (var mask = 1; mask < 16; mask++) {
      for (final length in [12, 64]) {
        for (final exclude in [false, true]) {
          final groups = [
            if (mask & 1 != 0) 'abcdefghijklmnopqrstuvwxyz',
            if (mask & 2 != 0) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            if (mask & 4 != 0) PasswordGenerator.digits,
            if (mask & 8 != 0) PasswordGenerator.punctuation,
          ].map((group) => exclude ? group.split('').where((c) => !'O0oIl1'.contains(c)).join() : group).toList();
          final options = GeneratorOptions(
            length: length,
            lowercase: mask & 1 != 0,
            uppercase: mask & 2 != 0,
            digits: mask & 4 != 0,
            symbols: mask & 8 != 0,
            excludeSimilar: exclude,
          );
          for (var attempt = 0; attempt < 20; attempt++) {
            final value = generator.generateWith(options);
            expect(value.length, length);
            expect(value.split('').every(groups.join().contains), isTrue);
            for (final group in groups) {
              expect(value.split('').any(group.contains), isTrue);
            }
          }
        }
      }
    }
  });

  test('rejects empty alphabet, invalid bounds and separator before generating', () {
    for (final options in [
      const GeneratorOptions(lowercase: false, uppercase: false, digits: false, symbols: false),
      const GeneratorOptions(length: 11),
      const GeneratorOptions(length: 65),
      const GeneratorOptions(wordCount: 5),
      const GeneratorOptions(wordCount: 11),
      const GeneratorOptions(separator: '\n'),
    ]) {
      expect(() => generator.generateWith(options, dictionary: dictionary), throwsArgumentError);
    }
    expect(() => generator.generateWith(const GeneratorOptions(mode: GeneratorMode.passphrase)), throwsArgumentError);
  });

  test('phrases use the complete bundled dictionary with exact counts and separators', () {
    expect(dictionary.words.length, 7776);
    expect(dictionary.words.first, 'abacus');
    expect(dictionary.words.last, 'zoom');
    for (final count in [6, 8, 10]) {
      for (final separator in [' ', '_', '.']) {
        final value = generator.generateWith(
          GeneratorOptions(mode: GeneratorMode.passphrase, wordCount: count, separator: separator),
          dictionary: dictionary,
        );
        final words = value.split(separator);
        expect(words.length, count);
        expect(words.every(dictionary.words.contains), isTrue);
      }
    }
    final dashed = generator.generateWith(
      const GeneratorOptions(mode: GeneratorMode.passphrase),
      dictionary: dictionary,
    );
    expect(RegExp(r'^[a-z]+(?:-[a-z]+){5,11}$').hasMatch(dashed), isTrue);
  });

  test('malformed, incomplete and duplicate dictionaries are rejected', () {
    for (final invalid in [
      source.replaceFirst('11111', '71111'),
      source.replaceFirst('11112', '11111'),
      source.replaceFirst('abacus', 'abdomen'),
      source.split('\n').skip(1).join('\n'),
      '$source\n11111\tabacus',
    ]) {
      expect(() => PassphraseWords.parse(invalid), throwsFormatException);
    }
  });

  test('malformed preferences never relax the generator policy', () {
    final defaults = const GeneratorOptions().toJson();
    for (final entry in <String, Object>{
      'version': 2,
      'mode': 'unknown',
      'length': 24.5,
      'wordCount': 100,
      'symbols': 'false',
      'excludeSimilar': 1,
      'separator': '',
    }.entries) {
      expect(() => GeneratorOptions.fromJson({...defaults, entry.key: entry.value}), throwsFormatException);
    }
    expect(() => GeneratorOptions.fromJson(null), throwsFormatException);
  });
}
