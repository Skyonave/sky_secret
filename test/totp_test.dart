import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/totp_session.dart';
import 'package:skysecret/ui/vault/controllers/vault_entry_controller.dart';

import 'vault_collection_test.dart' show collectionPassword, saveRevision;
import 'vault_sections_test.dart' show fixture;

String base32(String text) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final output = StringBuffer();
  for (final byte in ascii.encode(text)) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output.write(alphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) output.write(alphabet[(buffer << (5 - bits)) & 31]);
  return output.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secret = base32('12345678901234567890');

  test('RFC 6238 vectors for all algorithms, including dates beyond 2038', () async {
    const times = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000];
    const vectors = {
      'SHA1': ['94287082', '07081804', '14050471', '89005924', '69279037', '65353130'],
      'SHA256': ['46119246', '68084774', '67062674', '91819424', '90698825', '77737706'],
      'SHA512': ['90693936', '25091201', '99943326', '93441116', '38618901', '47863826'],
    };
    const seeds = {
      'SHA1': '12345678901234567890',
      'SHA256': '12345678901234567890123456789012',
      'SHA512': '1234567890123456789012345678901234567890123456789012345678901234',
    };
    for (final algorithm in vectors.keys) {
      final config = TotpConfiguration.parse(
        'otpauth://totp/Example?secret=${base32(seeds[algorithm]!)}&algorithm=$algorithm&digits=8',
      );
      for (var index = 0; index < times.length; index++) {
        expect(
          await config.codeAt(DateTime.fromMillisecondsSinceEpoch(times[index] * 1000)),
          vectors[algorithm]![index],
        );
      }
    }
  });

  test('raw keys normalize; time boundary and nondefault period remain correct', () async {
    final raw = TotpConfiguration.parse('  ${secret.toLowerCase()}  ');
    final before = DateTime.fromMillisecondsSinceEpoch(59000);
    final after = DateTime.fromMillisecondsSinceEpoch(60000);
    expect(await raw.codeAt(before), '287082');
    expect(raw.remainingSeconds(before), 1);
    expect(raw.remainingSeconds(after), 30);
    expect(await raw.codeAt(after), '359152');
    final configured = TotpConfiguration.parse('otpauth://totp/Test?secret=$secret&digits=8&period=60');
    expect(await configured.codeAt(DateTime.fromMillisecondsSinceEpoch(119000)), '94287082');
    expect(TotpConfiguration.parse(configured.uri).period, 60);
  });

  test('Google key URI example matches an independent binary-key HMAC calculation', () async {
    final raw = TotpConfiguration.parse('JBSWY3DPEHPK3PXP');
    final restored = TotpConfiguration.parse(raw.uri);
    const expected = {59: '996554', 1111111111: '358462', 2000000000: '890699'};
    for (final entry in expected.entries) {
      final time = DateTime.fromMillisecondsSinceEpoch(entry.key * 1000);
      expect(await raw.codeAt(time), entry.value);
      expect(await restored.codeAt(time), entry.value);
    }
  });

  test('malformed keys, unsupported types and ambiguous parameters fail without echoing secrets', () {
    for (final input in [
      '',
      '123456',
      '$secret!',
      '$secret=',
      '${secret}A',
      'A' * 4097,
      'otpauth://hotp/Test?secret=$secret&counter=0',
      'otpauth-migration://offline?data=synthetic',
      'https://example.invalid/?secret=$secret',
      'otpauth://totp/Test?secret=$secret&secret=$secret',
      'otpauth://totp/Test?secret=$secret&algorithm=MD5',
      'otpauth://totp/Test?secret=$secret&digits=7',
      'otpauth://totp/Test?secret=$secret&period=0',
      'otpauth://totp/Test?secret=$secret&period=301',
      'otpauth://totp/Test?secret=$secret&unexpected=1',
    ]) {
      try {
        TotpConfiguration.parse(input);
        fail('Accepted invalid synthetic configuration');
      } on FormatException catch (error) {
        expect(error.toString().contains(secret), isFalse);
      }
    }
  });

  test('TOTP survives entry metadata copies and is rejected in older schemas and file entries', () {
    final entry = VaultEntry.authenticator(title: 'Synthetic', totp: secret).withFavorite(true).inTrash(123);
    for (final copy in [
      entry.inFolder(null),
      entry.atPosition(null, 12),
      entry.withConflict('fork'),
      VaultEntry.fromJson(entry.toJson()),
    ]) {
      expect(copy.totp, entry.totp);
      expect(copy.isFavorite, isTrue);
      expect(copy.deletedAt, 123);
    }
    expect(() => VaultEntry.fromJson(entry.toJson(), totpAllowed: false), throwsA(isA<VaultFormatException>()));
    expect(() => VaultEntry.fromJson({...entry.toJson(), 'totp': 42}), throwsA(isA<VaultFormatException>()));
    final file = VaultEntry.file(VaultAttachment.create('synthetic.txt', [1]));
    expect(() => VaultEntry.fromJson({...file.toJson(), 'totp': entry.totp}), throwsA(isA<VaultFormatException>()));
  });

  test('authenticators require their own type and reject mixed or missing secrets', () {
    final entry = VaultEntry.authenticator(title: 'Synthetic', totp: secret);
    expect(entry.kind, VaultEntryKind.totp);
    expect(entry.hasPassword, isFalse);
    for (final json in [
      {...entry.toJson(), 'kind': 'unknown'},
      {...entry.toJson()}..remove('totp'),
      {...entry.toJson(), 'password': 'synthetic'},
      {...entry.toJson(), 'username': 'synthetic'},
      {...entry.toJson(), 'notes': 'synthetic'},
    ]) {
      expect(() => VaultEntry.fromJson(json), throwsA(isA<VaultFormatException>()));
    }
    expect(() => VaultEntry.authenticator(title: 'Synthetic', totp: ''), throwsA(isA<VaultFormatException>()));
  });

  test('schema 8 remains readable; TOTP encrypts, reopens and revokes with the vault', () async {
    final old = await fixture({
      'schemaVersion': 8,
      'name': null,
      'folders': [],
      'entries': [],
      'revision': VaultRevision(VaultRevision.randomId(), {}).toJson(),
    });
    final legacy = await VaultCipher.unlock(old, 'synthetic legacy password');
    legacy.lock();
    final vault = await VaultCipher.create(collectionPassword);
    addTearDown(vault.lock);
    final entry = VaultEntry.authenticator(title: 'Synthetic', totp: secret);
    await saveRevision(vault, [entry]);
    final encoded = vault.persistedBytes;
    expect(latin1.decode(encoded).contains(secret), isFalse);
    final reopened = await VaultCipher.unlock(encoded, collectionPassword);
    expect(reopened.entries.single.totp, entry.totp);
    final retained = reopened.entries.single.inFolder(null);
    reopened.lock();
    expect(() => retained.totp, throwsStateError);
    vault.lock();
    expect(() => entry.totp, throwsStateError);
  });

  test('editor preserves TOTP, rejects invalid input and clears draft secrets', () async {
    final vault = await VaultCipher.create(collectionPassword);
    addTearDown(vault.lock);
    final entry = VaultEntry.authenticator(title: 'Synthetic', totp: secret);
    await saveRevision(vault, [entry]);
    final editor = VaultEntryController()..start(entry: vault.entries.single);
    addTearDown(editor.dispose);
    expect(editor.prepare(vault).entries.single.totp, entry.totp);
    editor.totp.text = 'invalid';
    expect(() => editor.prepare(vault), throwsA(isA<EntryValidationException>()));
    editor.totp.clear();
    expect(() => editor.prepare(vault), throwsA(isA<EntryValidationException>()));
    editor.start(entry: vault.entries.single);
    editor.clear();
    expect(editor.totp.text, isEmpty);
  });

  test('manual Google example key survives editor, encryption and code window snapshot', () async {
    final vault = await VaultCipher.create(collectionPassword);
    addTearDown(vault.lock);
    final editor = VaultEntryController()..start(authenticator: true);
    addTearDown(editor.dispose);
    editor.title.text = 'Synthetic authenticator diagnostic';
    editor.totp.text = 'jbsw y3dp ehpk 3pxp';
    final organization = editor.prepare(vault);
    await saveRevision(vault, organization.entries);
    final reopened = await VaultCipher.unlock(vault.persistedBytes, collectionPassword);
    addTearDown(reopened.lock);
    final session = TotpSession(
      vault: reopened,
      isValid: () => true,
      copy: (_) async => true,
      clearClipboard: () async {},
      activity: () {},
    );
    final rows = await session.snapshot(DateTime.fromMillisecondsSinceEpoch(59000));
    expect(rows.single['code'], '996554');
    expect(TotpConfiguration.parse(reopened.entries.single.totp).secret, 'JBSWY3DPEHPK3PXP');
  });

  test('merge keeps independent TOTP changes and preserves both conflicting keys', () async {
    final base = await VaultCipher.create(collectionPassword);
    addTearDown(base.lock);
    final entry = VaultEntry.authenticator(title: 'Synthetic', totp: secret);
    await saveRevision(base, [entry]);
    final local = await VaultCipher.unlock(base.persistedBytes, collectionPassword);
    final remote = await VaultCipher.unlock(base.persistedBytes, collectionPassword);
    addTearDown(local.lock);
    addTearDown(remote.lock);
    final localKey = base32('local synthetic seed');
    final remoteKey = base32('remote synthetic seed');
    await saveRevision(local, [
      VaultEntry.fromJson({...entry.toJson(), 'totp': localKey}),
    ]);
    final merged = await VaultMerge.combine(base, local, remote);
    expect(TotpConfiguration.parse(merged.entries.single.totp).secret, localKey);
    await saveRevision(remote, [
      VaultEntry.fromJson({...entry.toJson(), 'totp': remoteKey}),
    ]);
    final conflict = await VaultMerge.combine(base, local, remote);
    expect(conflict.conflicts, 1);
    expect(conflict.entries.map((entry) => TotpConfiguration.parse(entry.totp).secret).toSet(), {localKey, remoteKey});
  });

  test('code session excludes trash, never sends seeds and revokes late clipboard writes', () async {
    final vault = await VaultCipher.create(collectionPassword);
    addTearDown(vault.lock);
    final active = VaultEntry.authenticator(title: 'Synthetic', totp: secret);
    final deleted = VaultEntry.authenticator(title: 'Deleted', totp: secret).inTrash(123);
    await saveRevision(vault, [active, deleted]);
    var clears = 0;
    String? copied;
    final entered = Completer<void>();
    final pending = Completer<bool>();
    final session = TotpSession(
      vault: vault,
      isValid: () => true,
      activity: () {},
      copy: (value) {
        copied = value;
        entered.complete();
        return pending.future;
      },
      clearClipboard: () async {
        clears++;
      },
    );
    final time = DateTime.fromMillisecondsSinceEpoch(59000);
    final rows = await session.snapshot(time);
    expect(rows.single['code'], '287082');
    expect(jsonEncode(rows).contains(secret), isFalse);
    expect(rows.single.keys.toSet(), {'id', 'title', 'username', 'code', 'period', 'expires'});
    expect(await session.copyCode(deleted.id, time), isFalse);
    expect(await session.copyCode('missing', time), isFalse);
    final copying = session.copyCode(active.id, time);
    await entered.future;
    session.close();
    pending.complete(true);
    expect(await copying, isFalse);
    expect(copied, '287082');
    expect(clears, 1);
    expect(await session.snapshot(time), isEmpty);
  });
}
