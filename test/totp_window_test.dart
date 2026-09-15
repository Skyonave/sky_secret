import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/totp_session.dart';
import 'package:skysecret/core/desktop/totp_window_layout.dart';
import 'package:skysecret/core/desktop/windows/totp_window_manager.dart';

import 'vault_collection_test.dart' show collectionPassword, saveRevision;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compact tiles keep a fixed width and grow upward within the work area', () {
    const work = Rect.fromLTWH(-1920, 0, 1920, 1040);
    for (final left in [-1950.0, -1600.0, -1000.0, -500.0]) {
      final size = totpWindowSize(Rect.fromLTWH(left, 350, 454, 602), work);
      expect(size, const Size(230, 56));
    }
    for (final width in [400.0, 460.0, 1600.0, 8000.0]) {
      expect(totpWindowSize(Rect.fromLTWH(-1000, 350, width, 602), work).width, 230);
    }
    final many = totpWindowSize(const Rect.fromLTWH(-500, 350, 454, 602), work, count: 100);
    final tiles = totpTileRects(many);
    expect(tiles.first.bottom, many.height);
    expect(many.height, lessThanOrEqualTo(952));
    for (var i = 1; i < tiles.length; i++) {
      expect(tiles[i - 1].top - tiles[i].bottom, totpTileGap);
    }
    expect(
      totpWindowSize(const Rect.fromLTWH(0, -700, 454, 602), work, count: 100),
      const Size(230, 56),
    );
    expect(
      totpWindowSize(const Rect.fromLTWH(0, 0, 454, 2000), work, count: 100).height,
      lessThanOrEqualTo(work.height),
    );
  });

  test('code window starts hidden and refuses reads and copy before successful privacy registration', () async {
    const native = MethodChannel('mixin.one/desktop_multi_window');
    const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
    const window = MethodChannel('window_manager');
    const placement = MethodChannel('skysecret/companion');
    final placements = <Map>[];
    var detaches = 0;
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final created = Completer<void>();
    var channel = '';
    var creations = 0;
    var epoch = 1;
    Completer<bool>? activation;
    final activating = Completer<void>();
    final locks = <int>[];
    var privacy = false;
    var copies = 0;
    var blurs = 0;
    final vault = await VaultCipher.create(collectionPassword);
    addTearDown(vault.lock);
    await saveRevision(vault, [VaultEntry.authenticator(title: 'Synthetic', totp: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ')]);
    final manager = TotpWindowManager(
      registerWindow: (_) => privacy,
      workArea: (_) => const Rect.fromLTWH(0, 0, 1920, 1040),
    );
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'createWindow') {
        final config = call.arguments as Map;
        expect(config['hiddenAtLaunch'], isTrue);
        final args = jsonDecode(config['arguments'] as String) as Map;
        expect(args.keys.toSet(), {'type', 'channel', 'locale'});
        expect(args['type'], 'totp');
        channel = args['channel'] as String;
        creations++;
        if (!created.isCompleted) created.complete();
        return 'synthetic-totp';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'invokeMethod') {
        final args = call.arguments as Map;
        if (args['method'] == 'lock') locks.add(args['arguments'] as int);
        if (args['method'] == 'activate' && activation != null) {
          if (!activating.isCompleted) activating.complete();
          return activation.future;
        }
      }
      return true;
    });
    messenger.setMockMethodCallHandler(placement, (call) async {
      if (call.method == 'bounds') return {'x': 1408.0, 'y': 400.0, 'width': 454.0, 'height': 602.0};
      if (call.method == 'place') {
        placements.add(call.arguments as Map);
        return true;
      }
      if (call.method == 'detach') detaches++;
      return null;
    });
    messenger.setMockMethodCallHandler(
      window,
      (call) async => switch (call.method) {
        'getBounds' || 'setBounds' => throw StateError('Movement belongs to the native companion'),
        'getId' => 123,
        _ => null,
      },
    );
    Future<dynamic> invoke(String method, [Object? arguments]) {
      final response = Completer<dynamic>();
      messenger.handlePlatformMessage(
        channels.name,
        codec.encodeMethodCall(
          MethodCall('methodCall', {
            'channel': channel,
            'method': method,
            'arguments': ['privacy', 'ready'].contains(method) ? arguments : {'epoch': epoch, 'id': arguments},
          }),
        ),
        (data) => response.complete(codec.decodeEnvelope(data!)),
      );
      return response.future;
    }

    addTearDown(() async {
      manager.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(channels, null);
      messenger.setMockMethodCallHandler(window, null);
      messenger.setMockMethodCallHandler(placement, null);
    });
    final opening = manager.open(
      session: TotpSession(
        vault: vault,
        isValid: () => true,
        activity: () {},
        copy: (_) async {
          copies++;
          return true;
        },
        clearClipboard: () async {},
      ),
      locale: 'en',
      onBlur: () {
        blurs++;
      },
    );
    await created.future;
    expect(await invoke('read'), isNull);
    expect(await invoke('privacy', 123), isFalse);
    expect(await invoke('copy', vault.entries.single.id), isNull);
    privacy = true;
    expect(await invoke('privacy', 123), isTrue);
    expect(await invoke('ready'), isTrue);
    await opening;
    final data = await invoke('read') as Map;
    expect(data['width'], 230.0);
    expect(data['height'], 56.0);
    expect(data.containsKey('x'), isFalse);
    expect(data.containsKey('y'), isFalse);
    expect(await invoke('position'), isTrue);
    expect(placements.single, {'window': 123, 'gap': 12.0});
    expect((data['rows'] as List).length, 1);
    expect(jsonEncode(data).contains('GEZDGNBV'), isFalse);
    expect(await invoke('copy', vault.entries.single.id), isTrue);
    expect(copies, 1);
    await invoke('blur');
    expect(blurs, 1);
    privacy = false;
    expect(await invoke('privacy', 123), isFalse);
    expect(await invoke('read'), isNull);
    expect(await invoke('copy', vault.entries.single.id), isNull);
    manager.close();
    expect(await invoke('read'), isNull);
    expect(await invoke('position'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(detaches, greaterThan(0));
    expect(placements, hasLength(1));
    privacy = true;
    final next = TotpSession(
      vault: vault,
      isValid: () => true,
      activity: () {},
      copy: (_) async => true,
      clearClipboard: () async {},
    );
    await manager.open(session: next, locale: 'en', onBlur: () {});
    expect(creations, 1);
    expect(await invoke('read'), isNull);
    expect(await invoke('copy', vault.entries.single.id), isNull);
    epoch = 3;
    expect(await invoke('privacy', 123), isTrue);
    expect(await invoke('read'), isA<Map>());
    manager.close();
    activation = Completer<bool>();
    final pending = TotpSession(
      vault: vault,
      isValid: () => true,
      activity: () {},
      copy: (_) async => true,
      clearClipboard: () async {},
    );
    final reopening = manager.open(session: pending, locale: 'en', onBlur: () {});
    await activating.future;
    epoch = 5;
    manager.close();
    await Future<void>.delayed(Duration.zero);
    expect(locks, contains(5));
    expect(pending.valid, isFalse);
    expect(await invoke('read'), isNull);
    activation.complete(true);
    await reopening;
    expect(manager.isOpen, isFalse);
    expect(creations, 1);
    vault.lock();
  });

  test('channel registration failure releases the opening session for retry', () async {
    const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final vault = await VaultCipher.create(collectionPassword);
    addTearDown(vault.lock);
    final manager = TotpWindowManager(registerWindow: (_) => true);
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'registerMethodHandler') throw PlatformException(code: 'CHANNEL_LIMIT_REACHED');
      return true;
    });
    addTearDown(() async {
      manager.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(channels, null);
    });
    final session = TotpSession(
      vault: vault,
      isValid: () => true,
      activity: () {},
      copy: (_) async => true,
      clearClipboard: () async {},
    );
    await expectLater(manager.open(session: session, locale: 'en', onBlur: () {}), throwsException);
    expect(manager.isOpen, isFalse);
    expect(session.valid, isFalse);
  });
}
