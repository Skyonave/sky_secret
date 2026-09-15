import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/file_drag_controller.dart';

void main() {
  VaultAttachment attachment() => VaultAttachment.create('synthetic.txt', List.generate(17001, (index) => index % 251));

  test('a revoked session never prepares or exports', () async {
    final controller = FileDragController(invoke: (_, _) async => fail('Unexpected native call'));
    expect(await controller.start(attachment: attachment(), allowed: () => false), isFalse);
    expect(controller.active, isFalse);
  });

  test('native transfer receives protected bytes and clears its transport copy', () async {
    final original = attachment();
    Uint8List? transport;
    final active = <bool>[];
    final controller = FileDragController(
      onActiveChanged: active.add,
      invoke: (method, arguments) async {
        if (method == 'prepare') return 42;
        final values = arguments as Map;
        expect(values['name'], 'synthetic.txt');
        expect(values['size'], 17001);
        expect(values['epoch'], 42);
        transport = values['data'] as Uint8List;
        expect(transport, original.copyProtectedMemory());
        expect(transport!.length, 17008);
        expect(transport!.take(32), isNot(original.bytes.take(32)));
        return true;
      },
    );
    expect(await controller.start(attachment: original, allowed: () => true), isTrue);
    expect(transport!.every((byte) => byte == 0), isTrue);
    expect(active, [true, false]);
    expect(original.bytes.length, 17001);
  });

  test('locking during preparation prevents a late data transfer', () async {
    final ready = Completer<Object?>();
    var allowed = true;
    final controller = FileDragController(
      invoke: (method, _) {
        expect(method, 'prepare');
        return ready.future;
      },
    );
    final pending = controller.start(attachment: attachment(), allowed: () => allowed);
    allowed = false;
    ready.complete(1);
    expect(await pending, isFalse);
    expect(controller.active, isFalse);
  });

  test('cancelling preparation sends a watermark and prevents start', () async {
    final ready = Completer<Object?>();
    final methods = <String>[];
    final controller = FileDragController(
      invoke: (method, arguments) async {
        methods.add(method);
        if (method == 'prepare') return ready.future;
        expect(method, 'cancel');
        expect(arguments, isA<int>());
        return null;
      },
    );
    final pending = controller.start(attachment: attachment(), allowed: () => true);
    controller.cancel();
    ready.complete(1);
    expect(await pending, isFalse);
    expect(methods, ['prepare', 'cancel']);
  });

  test('a late old completion cannot end a replacement drag', () async {
    final started = Completer<void>();
    final oldResult = Completer<Object?>();
    final newResult = Completer<Object?>();
    var starts = 0;
    final active = <bool>[];
    final controller = FileDragController(
      onActiveChanged: active.add,
      invoke: (method, _) async {
        if (method == 'prepare') return 1;
        if (method == 'cancel') return null;
        if (starts++ == 0) {
          started.complete();
          return oldResult.future;
        }
        return newResult.future;
      },
    );
    final first = controller.start(attachment: attachment(), allowed: () => true);
    await started.future;
    controller.cancel();
    final second = controller.start(attachment: attachment(), allowed: () => true);
    oldResult.complete(true);
    expect(await first, isFalse);
    expect(controller.active, isTrue);
    newResult.complete(true);
    expect(await second, isTrue);
    expect(active, [true, false, true, false]);
  });

  test('native failure releases the active state and wipes the transport buffer', () async {
    Uint8List? transport;
    final controller = FileDragController(
      invoke: (method, arguments) async {
        if (method == 'prepare') return 1;
        transport = (arguments as Map)['data'] as Uint8List;
        throw StateError('Synthetic failure');
      },
    );
    await expectLater(controller.start(attachment: attachment(), allowed: () => true), throwsStateError);
    expect(controller.active, isFalse);
    expect(transport!.every((byte) => byte == 0), isTrue);
  });

  test('dispose cancels a pending preparation and rejects subsequent drags', () async {
    final ready = Completer<Object?>();
    var cancels = 0;
    final controller = FileDragController(
      invoke: (method, _) async {
        if (method == 'prepare') return ready.future;
        expect(method, 'cancel');
        cancels++;
        return null;
      },
    );
    final pending = controller.start(attachment: attachment(), allowed: () => true);
    controller.dispose();
    ready.complete(1);
    expect(await pending, isFalse);
    expect(await controller.start(attachment: attachment(), allowed: () => true), isFalse);
    expect(cancels, 1);
  });

  test('empty text files can be exported', () async {
    final controller = FileDragController(
      invoke: (method, arguments) async {
        if (method == 'prepare') return 1;
        expect((arguments as Map)['size'], 0);
        expect(arguments['data'], isEmpty);
        return true;
      },
    );
    expect(
      await controller.start(attachment: VaultAttachment.create('empty.txt', []), allowed: () => true),
      isTrue,
    );
  });
}
