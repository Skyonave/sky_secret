import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/clipboard/sensitive_clipboard.dart';
import 'package:skysecret/core/desktop/clipboard/sensitive_clipboard_controller.dart';

class MemoryClipboard implements SensitiveClipboard {
  String? text;
  int revision = 0;
  int failures = 0;
  Completer<void>? writeGate;

  @override
  Future<int> write(String value) async {
    await writeGate?.future;
    text = value;
    return ++revision;
  }

  @override
  Future<bool> clearIfCurrent(int owned) async {
    if (failures > 0) {
      failures--;
      throw const ClipboardUnavailable();
    }
    if (revision != owned) return false;
    text = null;
    revision++;
    return true;
  }
}

class ScheduledClear implements Timer {
  final Duration delay;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  ScheduledClear(this.delay, this.callback);

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  Future<void> fire() async {
    if (_active == false) return;
    _active = false;
    _tick++;
    callback();
    await Future<void>.value();
    await Future<void>.value();
  }
}

void main() {
  late MemoryClipboard clipboard;
  late SensitiveClipboardController controller;
  late List<ScheduledClear> timers;

  setUp(() {
    clipboard = MemoryClipboard();
    controller = SensitiveClipboardController(clipboard: clipboard, onCleared: () {});
    timers = [];
  });
  tearDown(() => controller.dispose());

  Future<void> withTimers(Future<void> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, delay, callback) {
        final timer = ScheduledClear(delay, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );

  test(
    'hiding preserves a completed copy and its original ten-second deadline',
    () => withTimers(() async {
      expect(await controller.write('Synthetic secret'), isTrue);
      final expiry = timers.single;
      expect(expiry.delay, const Duration(seconds: 10));
      controller.cancelPendingWrites();
      controller.cancelPendingWrites();
      expect(clipboard.text, 'Synthetic secret');
      expect(timers.single, same(expiry));
      expect(expiry.isActive, isTrue);
      await expiry.fire();
      expect(clipboard.text, isNull);
    }),
  );

  test(
    'explicit clearing removes a completed copy immediately',
    () => withTimers(() async {
      await controller.write('Synthetic secret');
      await controller.clear();
      expect(clipboard.text, isNull);
      expect(timers.single.isActive, isFalse);
    }),
  );

  for (final clear in [false, true]) {
    test(
      'copy completed after revocation is rejected: clear=$clear',
      () => withTimers(() async {
        clipboard.writeGate = Completer<void>();
        final copy = controller.write('Synthetic late copy');
        if (clear) {
          await controller.clear();
        } else {
          controller.cancelPendingWrites();
        }
        clipboard.writeGate!.complete();
        expect(await copy, isFalse);
        expect(clipboard.text, isNull);
        expect(timers, isEmpty);
      }),
    );
  }

  test(
    'expiry preserves a newer external copy with identical text',
    () => withTimers(() async {
      await controller.write('Synthetic secret');
      clipboard.revision++;
      await timers.single.fire();
      expect(clipboard.text, 'Synthetic secret');
    }),
  );

  test(
    'recopy replaces the deadline and busy expiry retries',
    () => withTimers(() async {
      await controller.write('Synthetic first');
      final previous = timers.single;
      await controller.write('Synthetic second');
      expect(previous.isActive, isFalse);
      await previous.fire();
      expect(clipboard.text, 'Synthetic second');
      clipboard.failures = 1;
      await timers.last.fire();
      expect(clipboard.text, 'Synthetic second');
      expect(timers.last.delay, const Duration(seconds: 1));
      await timers.last.fire();
      expect(clipboard.text, isNull);
    }),
  );

  test(
    'dispose clears owned data and rejects further writes',
    () => withTimers(() async {
      await controller.write('Synthetic secret');
      controller.dispose();
      expect(await controller.write('Synthetic rejected'), isFalse);
      expect(clipboard.text, isNull);
      expect(timers.single.isActive, isFalse);
    }),
  );
}
