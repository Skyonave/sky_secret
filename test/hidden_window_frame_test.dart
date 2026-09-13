import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/windows/hidden_window_frame.dart';

class FrameBinding extends BindingBase with SchedulerBinding {
  void hide() => handleAppLifecycleStateChanged(AppLifecycleState.hidden);
}

void main() {
  final binding = FrameBinding();

  test('hidden window preparation completes while ordinary frames are suspended', () async {
    binding.hide();
    expect(binding.framesEnabled, isFalse);
    var completed = false;
    unawaited(binding.endOfFrame.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    await prepareHiddenWindowFrame().timeout(const Duration(seconds: 2));
    expect(completed, isTrue);
    expect(binding.framesEnabled, isFalse);

    await prepareHiddenWindowFrame().timeout(const Duration(seconds: 2));
    expect(binding.framesEnabled, isFalse);
  });
}
