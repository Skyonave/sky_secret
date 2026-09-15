import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/ui/search/vault_search_presenter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late search activation cannot revoke a replacement session', () async {
    const native = MethodChannel('mixin.one/desktop_multi_window');
    const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
    const placement = MethodChannel('skysecret/companion');
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final created = Completer<void>();
    final activating = Completer<void>();
    final activation = Completer<bool>();
    var channel = '';
    var epoch = 0;
    var activations = 0;
    final presenter = VaultSearchPresenter(registerWindow: (_) => true);
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'createWindow') {
        final args = jsonDecode((call.arguments as Map)['arguments'] as String) as Map;
        channel = args['channel'] as String;
        created.complete();
        return 'synthetic-search-race';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'invokeMethod') {
        final args = call.arguments as Map;
        if (args['method'] == 'activate') {
          epoch = (args['arguments'] as Map)['epoch'] as int;
          activations++;
          if (activations == 1) {
            activating.complete();
            return activation.future;
          }
        }
      }
      return true;
    });
    messenger.setMockMethodCallHandler(placement, (_) async => true);
    Future<dynamic> invoke(String method, Object? args) {
      final response = Completer<dynamic>();
      messenger.handlePlatformMessage(
        channels.name,
        codec.encodeMethodCall(
          MethodCall('methodCall', {'channel': channel, 'method': method, 'arguments': args}),
        ),
        (data) => response.complete(codec.decodeEnvelope(data!)),
      );
      return response.future;
    }

    Future<String?> open() => presenter.open(
      isValid: () => true,
      find: (query) => [
        {'id': query},
      ],
      activity: () {},
      onBlur: () {},
      copy: (_) async => true,
      clearClipboard: () async {},
    );
    addTearDown(() async {
      presenter.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(channels, null);
      messenger.setMockMethodCallHandler(placement, null);
    });
    final first = open();
    await created.future;
    await invoke('privacy', 123);
    await invoke('ready', null);
    await activating.future;
    presenter.close();
    final second = open();
    activation.complete(true);
    expect(await first, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(activations, 2);
    expect(await invoke('search', {'epoch': epoch, 'query': 'current'}), [
      {'id': 'current'},
    ]);
    expect(await invoke('select', {'epoch': epoch, 'id': 'current'}), isTrue);
    expect(await second, 'current');
  });

  test('hidden search reuses its window and rejects stale selections, locks and unregistered reads', () async {
    const native = MethodChannel('mixin.one/desktop_multi_window');
    const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
    const placement = MethodChannel('skysecret/companion');
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final created = Completer<void>();
    var channel = '';
    var epoch = 0;
    var creations = 0;
    var privacy = false;
    var valid = true;
    var activations = Completer<void>();
    var blur = 0;
    var positions = 0;
    var detaches = 0;
    var copies = 0;
    var clears = 0;
    Completer<bool>? copying;
    final presenter = VaultSearchPresenter(registerWindow: (_) => privacy);
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'createWindow') {
        final config = call.arguments as Map;
        expect(config['hiddenAtLaunch'], isTrue);
        final args = jsonDecode(config['arguments'] as String) as Map;
        expect(args.keys.toSet(), {'type', 'channel', 'locale'});
        expect(args['type'], 'search');
        channel = args['channel'] as String;
        creations++;
        created.complete();
        return 'synthetic-search';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'invokeMethod') {
        final args = call.arguments as Map;
        if (args['method'] == 'activate') {
          epoch = (args['arguments'] as Map)['epoch'] as int;
          activations.complete();
        }
      }
      return true;
    });
    messenger.setMockMethodCallHandler(placement, (call) async {
      if (call.method == 'placeSearch') {
        positions++;
        expect(call.arguments, {'window': 123, 'gap': 12.0});
        return true;
      }
      if (call.method == 'detachSearch') detaches++;
      return null;
    });
    Future<dynamic> invoke(String method, Object? args) {
      final response = Completer<dynamic>();
      messenger.handlePlatformMessage(
        channels.name,
        codec.encodeMethodCall(
          MethodCall('methodCall', {
            'channel': channel,
            'method': method,
            'arguments': args,
          }),
        ),
        (data) => response.complete(codec.decodeEnvelope(data!)),
      );
      return response.future;
    }

    Future<String?> open() => presenter.open(
      isValid: () => valid,
      find: (query) => [
        {'id': query, 'title': query},
      ],
      activity: () {},
      onBlur: () => blur++,
      copy: (_) async {
        copies++;
        return copying == null ? true : await copying.future;
      },
      clearClipboard: () async {
        clears++;
      },
    );
    addTearDown(() async {
      presenter.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(channels, null);
      messenger.setMockMethodCallHandler(placement, null);
    });
    final first = open();
    await created.future;
    expect(await invoke('search', {'epoch': 1, 'query': 'one'}), isNull);
    expect(await invoke('copyQuery', {'epoch': 1, 'text': 'one'}), isNull);
    expect(await invoke('privacy', 123), isFalse);
    privacy = true;
    expect(await invoke('privacy', 123), isTrue);
    expect(await invoke('ready', null), isTrue);
    await activations.future;
    expect(await invoke('copyQuery', {'epoch': epoch, 'text': 'one'}), isTrue);
    expect(await invoke('copyQuery', {'epoch': epoch, 'text': 'a' * 257}), isFalse);
    expect(copies, 1);
    expect(await invoke('search', {'epoch': epoch, 'query': 'one'}), [
      {'id': 'one', 'title': 'one'},
    ]);
    await invoke('search', {'epoch': epoch, 'query': 'two'});
    expect(await invoke('select', {'epoch': epoch, 'id': 'one'}), isFalse);
    expect(await invoke('position', {'epoch': epoch}), isTrue);
    await invoke('blur', {'epoch': epoch});
    expect(blur, 1);
    final oldEpoch = epoch;
    expect(await invoke('select', {'epoch': epoch, 'id': 'two'}), isTrue);
    expect(await first, 'two');
    expect(await invoke('search', {'epoch': oldEpoch, 'query': 'one'}), isNull);
    activations = Completer<void>();
    final second = open();
    await activations.future;
    expect(creations, 1);
    expect(await invoke('position', {'epoch': oldEpoch}), isNull);
    await invoke('search', {'epoch': epoch, 'query': 'one'});
    copying = Completer<bool>();
    final pendingCopy = invoke('copyQuery', {'epoch': epoch, 'text': 'one'});
    await Future<void>.delayed(Duration.zero);
    expect(copies, 2);
    valid = false;
    expect(await invoke('copyQuery', {'epoch': epoch, 'text': 'one'}), isNull);
    expect(copies, 2);
    expect(await invoke('select', {'epoch': epoch, 'id': 'one'}), isNull);
    presenter.close();
    copying.complete(true);
    expect(await pendingCopy, isFalse);
    expect(clears, 1);
    expect(await second, isNull);
    expect(positions, 1);
    expect(detaches, greaterThan(0));
  });
}
