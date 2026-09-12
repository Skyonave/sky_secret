import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

void main() {
  final generator = PasswordGenerator();
  test('length and selected character groups hold at both boundaries', () {
    for (final length in [12, 24, 64]) {
      for (final symbols in [false, true]) {
        final allowed =
            PasswordGenerator.letters +
            PasswordGenerator.digits +
            (symbols ? PasswordGenerator.punctuation : '');
        for (var i = 0; i < 50; i++) {
          final password = generator.generate(length: length, symbols: symbols);
          expect(password.length, length);
          expect(password.split('').every(allowed.contains), isTrue);
          expect(
            password.split('').any(PasswordGenerator.letters.contains),
            isTrue,
          );
          expect(
            password.split('').any(PasswordGenerator.digits.contains),
            isTrue,
          );
          if (symbols) {
            expect(
              password.split('').any(PasswordGenerator.punctuation.contains),
              isTrue,
            );
          }
        }
      }
    }
  });
  test('rejects invalid lengths instead of silently truncating', () {
    for (final length in [-1, 0, 11, 65, 100000]) {
      expect(() => generator.generate(length: length), throwsRangeError);
    }
  });
}
