import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

void main() {
  final lineage = 'a' * 32, a = '1' * 32, b = '2' * 32, c = '3' * 32;
  test(
    'causal clocks distinguish descendants, siblings and stale branches',
    () {
      final base = VaultRevision(lineage, {}).advance(a);
      final local = base.advance(a);
      var remote = base;
      for (var i = 0; i < 30; i++) {
        remote = remote.advance(b);
      }
      expect(remote.succeeds(base), isTrue);
      expect(remote.includes(local), isFalse);
      expect(local.includes(remote), isFalse);
      final merged = local.advance(a, merge: remote);
      expect(merged.succeeds(local), isTrue);
      expect(merged.succeeds(remote), isTrue);
      final third = merged.advance(c);
      expect(third.succeeds(merged), isTrue);
      expect(remote.succeeds(third), isFalse);
    },
  );
  test('key rotation preserves lineage and advances a separate key epoch', () {
    final base = VaultRevision(lineage, {}).advance(a);
    final rotated = base.rotate().advance(a);
    expect(rotated.keyEpoch, 1);
    expect(rotated.succeeds(base), isTrue);
    expect(VaultRevision.fromJson(rotated.toJson()).toJson(), rotated.toJson());
    expect(rotated.includes(VaultRevision('b' * 32, {})), isFalse);
  });
  test('malformed, oversized and overflowing clocks fail closed', () {
    for (final clock in [
      {a: -1},
      {a: 0},
      {a: 1.5},
      {'invalid': 1},
      {a: 9007199254740992},
      {for (var i = 0; i < 1025; i++) i.toRadixString(16).padLeft(32, '0'): 1},
    ]) {
      expect(
        () => VaultRevision.fromJson({
          'lineage': lineage,
          'keyEpoch': 0,
          'clock': clock,
        }),
        throwsA(isA<VaultFormatException>()),
      );
    }
    expect(
      () => VaultRevision(lineage, {a: 9007199254740991}).advance(a),
      throwsA(isA<VaultFormatException>()),
    );
    expect(
      () => VaultRevision(
        lineage,
        {},
      ).advance(a, merge: VaultRevision('b' * 32, {})),
      throwsA(isA<VaultFormatException>()),
    );
  });
}
