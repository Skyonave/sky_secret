import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

void main() {
  test(
    '50 MiB payload merges in a worker while the caller processes events',
    () async {
      final base = await VaultCipher.create('Synthetic load password 123!');
      VaultSession? local, remote;
      Timer? timer;
      try {
        final files = <VaultEntry>[];
        for (final size in [20, 20, 10]) {
          final bytes = Uint8List(size * 1024 * 1024);
          for (var i = 0; i < bytes.length; i += 4096) {
            bytes[i] = (i ~/ 4096) % 251;
          }
          files.add(
            VaultEntry.file(
              VaultAttachment.create('synthetic-${files.length}.bin', bytes),
            ),
          );
          bytes.fillRange(0, bytes.length, 0);
        }
        final original = await base.encrypt(files);
        base.acceptPersisted(original, files, [], null);
        local = await base.openRevision(original);
        remote = await base.openRevision(original);
        final left = [
          ...local.entries,
          VaultEntry.create(title: 'Synthetic A', password: 'A'),
        ];
        final right = [
          ...remote.entries,
          VaultEntry.create(title: 'Synthetic B', password: 'B'),
        ];
        local.acceptPersisted(await local.encrypt(left), left, [], null);
        remote.acceptPersisted(await remote.encrypt(right), right, [], null);
        var events = 0;
        timer = Timer.periodic(
          const Duration(milliseconds: 5),
          (_) => events++,
        );
        final merged = await VaultMerge.combine(base, local, remote);
        timer.cancel();
        expect(events, greaterThan(0));
        expect(
          merged.entries.where((e) => !e.isFile).map((e) => e.password).toSet(),
          {'A', 'B'},
        );
        expect(
          merged.entries.where((e) => e.isFile).fold<int>(0, (n, e) => n + e.attachments.single.size),
          VaultCipher.maxTotalAttachmentBytes,
        );
        final pending = local.openRevision(original);
        final cancelled = expectLater(pending, throwsStateError);
        local.lock();
        await cancelled;
      } finally {
        timer?.cancel();
        local?.lock();
        remote?.lock();
        base.lock();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
