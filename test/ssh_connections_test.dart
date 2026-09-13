import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/os/windows/ssh_connections.dart';

VaultEntry connection() => VaultEntry.create(
  title: 'Synthetic SSH',
  username: 'synthetic',
  password: 'Synthetic password!',
  ssh: const SshEndpoint(host: 'server.example', port: 2222),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic/ssh');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('rejects shell syntax, options, URLs, invalid ports and truncated passwords', () {
    for (final host in ['server.example', '127.0.0.1', '::1', '2001:db8::1']) {
      expect(SshEndpoint(host: host).isValid, isTrue);
    }
    for (final host in [
      '',
      '-oProxyCommand=x',
      'host & calc',
      'host%PATH%',
      'host!x!',
      'ssh://host',
      'root@host',
      'host\ncommand',
      'host"',
      '[::1]',
      'bad..host',
      'host;cmd',
    ]) {
      expect(SshEndpoint(host: host).isValid, isFalse, reason: host);
    }
    for (final port in [0, -1, 65536]) {
      expect(SshEndpoint(host: 'server.example', port: port).isValid, isFalse);
    }
    for (final user in ['root', 'service_user', r'machine$']) {
      expect(SshEndpoint.validUsername(user), isTrue);
    }
    for (final user in ['', '-root', 'user name', 'user&cmd', 'user%PATH%', 'user\n']) {
      expect(SshEndpoint.validUsername(user), isFalse);
    }
    expect(SshEndpoint.validPassword('пароль'), isTrue);
    for (final password in ['', 'a\nb', 'a\rb', 'a\x00b', 'я' * 501]) {
      expect(SshEndpoint.validPassword(password), isFalse);
    }
  });

  test('SSH metadata survives copies and rejects malformed typed records', () {
    final entry = connection().atPosition('folder', 42).withConflict('source');
    final copy = VaultEntry.fromJson(entry.toJson());
    expect(copy.toJson(), entry.toJson());
    expect(copy.inFolder(null).ssh!.port, 2222);
    expect(copy.atPosition(null, 84).ssh!.host, 'server.example');
    expect(() => VaultEntry.fromJson(entry.toJson(), sshAllowed: false), throwsA(isA<VaultFormatException>()));
    for (final fields in [
      {
        'ssh': {'host': '-oProxyCommand=cmd', 'port': 22},
      },
      {
        'ssh': {'host': 'server.example', 'port': '22'},
      },
      {
        'ssh': {'host': 'server.example', 'port': 22, 'command': 'synthetic'},
      },
      {'username': 'user&cmd'},
      {'password': 'a\nb'},
      {'kind': 'text'},
    ]) {
      expect(() => VaultEntry.fromJson({...entry.toJson(), ...fields}), throwsA(isA<VaultFormatException>()));
    }
  });

  test('encrypted round trip, conflicting endpoints and secret revocation', () async {
    const password = 'Synthetic master phrase 1!';
    final seed = await VaultCipher.create(password);
    addTearDown(seed.lock);
    final entry = connection();
    final bytes = await seed.encrypt([entry]);
    expect(latin1.decode(bytes).contains('server.example'), isFalse);
    final base = await VaultCipher.unlock(bytes, password);
    addTearDown(base.lock);
    final leftEntry = VaultEntry.fromJson({
      ...entry.toJson(),
      'ssh': {'host': 'left.example', 'port': 22},
    });
    final rightEntry = VaultEntry.fromJson({
      ...entry.toJson(),
      'ssh': {'host': 'right.example', 'port': 2222},
    });
    final left = await VaultCipher.unlock(await base.encrypt([leftEntry]), password);
    addTearDown(left.lock);
    final right = await VaultCipher.unlock(await base.encrypt([rightEntry]), password);
    addTearDown(right.lock);
    final merged = await VaultMerge.combine(base, left, right);
    expect(merged.conflicts, 1);
    expect(merged.entries.map((item) => item.ssh!.host).toSet(), {'left.example', 'right.example'});
    final restored = await VaultCipher.unlock(await left.encrypt(merged.entries), password);
    final issued = restored.entries.first;
    expect(issued.password, 'Synthetic password!');
    restored.lock();
    expect(() => issued.password, throwsStateError);
  });

  group('password request lifecycle with a mocked native channel', () {
    late VaultSession session;
    late SshConnections service;
    late VaultEntry entry;
    late List<MethodCall> calls;
    late List<Map<String, Object>> events;
    late String key;
    late List<bool> authorizations;
    Future<bool> Function(String) confirm = (_) async => true;

    setUp(() async {
      session = await VaultCipher.create('Synthetic master phrase 1!');
      entry = connection();
      final saved = await session.encrypt([entry]);
      session.acceptPersisted(saved, [entry], [], null);
      entry = session.entries.single;
      calls = [];
      events = [];
      key = 'synthetic:${entry.id}';
      authorizations = [];
      confirm = (_) async => true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'poll') {
          final result = events.toList();
          events.clear();
          return result;
        }
        return null;
      });
      service = SshConnections(
        channel: channel,
        confirmHost: (prompt) => confirm(prompt),
        onAuthorizationChanged: authorizations.add,
        onExit: (_) {},
      );
    });
    tearDown(() async {
      service.dispose();
      session.lock();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('launch contains no password and sends it once only for a password request', () async {
      await service.start('synthetic', session, entry);
      expect(authorizations, [true]);
      expect(jsonEncode(calls.single.arguments).contains(entry.password), isFalse);
      await expectLater(service.start('synthetic', session, entry), throwsA(isA<PlatformException>()));
      events.add({'key': key, 'type': 'password'});
      await service.poll();
      expect((calls.last.arguments as Map)['answer'], entry.password);
      expect(authorizations, [true]);
      events.add({'key': key, 'type': 'released'});
      await service.poll();
      expect(authorizations, [true, false]);
      events.add({'key': key, 'type': 'password'});
      await service.poll();
      expect((calls.last.arguments as Map)['answer'], '');
      expect(authorizations, [true, false]);
    });

    test('lock prevents issuing a password requested after launch', () async {
      await service.start('synthetic', session, entry);
      session.lock();
      events.add({'key': key, 'type': 'password'});
      await service.poll();
      expect((calls.last.arguments as Map)['answer'], '');
    });

    test('remote trash prevents an outstanding SSH grant from releasing its password', () async {
      await service.start('synthetic', session, entry);
      final removed = entry.inTrash(123);
      final bytes = await session.encrypt([removed]);
      session.acceptPersisted(bytes, [removed], [], null);
      events.add({'key': key, 'type': 'password'});
      await service.poll();
      expect((calls.last.arguments as Map)['answer'], '');
      await expectLater(service.start('other', session, session.entries.single), throwsA(isA<PlatformException>()));
    });

    test('revocation while host confirmation is open prevents later approval and password', () async {
      final confirmation = Completer<bool>();
      final opened = Completer<void>();
      confirm = (_) {
        opened.complete();
        return confirmation.future;
      };
      await service.start('synthetic', session, entry);
      events.add({'key': key, 'type': 'hostKey', 'prompt': 'Synthetic fingerprint'});
      final polling = service.poll();
      await opened.future;
      service.revoke();
      confirmation.complete(true);
      await polling;
      expect((calls.last.arguments as Map)['answer'], '');
      events.add({'key': key, 'type': 'password'});
      await service.poll();
      expect((calls.last.arguments as Map)['answer'], '');
    });

    test('unknown prompts receive no secret and terminal exit permits reconnecting', () async {
      await service.start('synthetic', session, entry);
      events.add({'key': key, 'type': 'otp'});
      await service.poll();
      expect((calls.last.arguments as Map)['answer'], '');
      events.add({'key': key, 'type': 'exit', 'ok': false});
      await service.poll();
      await service.start('synthetic', session, entry);
    });
  });
}
