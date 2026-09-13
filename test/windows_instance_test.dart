import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/os/windows/windows_instance.dart';

void main() {
  test(
    'only first claimant owns instance; early and repeated activation works',
    () async {
      final name = 'SkySecret.Test.$pid.${DateTime.now().microsecondsSinceEpoch}';
      final primary = WindowsInstance(name: name);
      addTearDown(primary.dispose);
      expect(primary.isPrimary, isTrue);
      for (var i = 0; i < 8; i++) {
        final secondary = WindowsInstance(name: name);
        expect(secondary.isPrimary, isFalse);
        secondary.dispose();
      }
      var activation = Completer<void>();
      primary.listen(() {
        if (!activation.isCompleted) activation.complete();
      });
      await activation.future.timeout(const Duration(seconds: 2));
      activation = Completer<void>();
      final later = WindowsInstance(name: name);
      expect(later.isPrimary, isFalse);
      later.dispose();
      await activation.future.timeout(const Duration(seconds: 2));
      primary.dispose();
      final restarted = WindowsInstance(name: name);
      expect(restarted.isPrimary, isTrue);
      restarted.dispose();
    },
    skip: !Platform.isWindows,
  );
}
