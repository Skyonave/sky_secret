import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../os/windows/windows_dpapi.dart';
import '../../storage/local_file.dart';
import 'github_api.dart';

abstract interface class GitHubStorage {
  Future<Map<String, dynamic>?> read();

  Future<void> write(Map<String, dynamic> value);
}

class WindowsGitHubStorage implements GitHubStorage {
  final File file;

  WindowsGitHubStorage(this.file);

  @override
  Future<Map<String, dynamic>?> read() async {
    try {
      final encrypted = await readBoundedFile(file, maxBytes: 4 * 1024 * 1024);
      if (encrypted == null) return null;
      final clear = protectGitHubState(encrypted, decrypt: true);
      try {
        return object(jsonDecode(utf8.decode(clear)));
      } finally {
        clear.fillRange(0, clear.length, 0);
      }
    } catch (_) {
      throw const GitHubFailure(GitHubProblem.storage);
    }
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    Directory? staging;
    final clear = utf8.encode(jsonEncode(value));
    try {
      final encrypted = protectGitHubState(clear);
      await file.parent.create(recursive: true);
      staging = await file.parent.createTemp('github-staging-');
      final pending = File('${staging.path}/state');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
        throw const GitHubFailure(GitHubProblem.storage);
      }
      await pending.writeAsBytes(encrypted, flush: true);
      using((arena) {
        if (!MoveFileEx(
          PCWSTR(pending.path.toNativeUtf16(allocator: arena)),
          PCWSTR(file.path.toNativeUtf16(allocator: arena)),
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        ).value) {
          throw const GitHubFailure(GitHubProblem.storage);
        }
      });
    } catch (_) {
      throw const GitHubFailure(GitHubProblem.storage);
    } finally {
      clear.fillRange(0, clear.length, 0);
      if (staging != null) {
        try {
          final pending = File('${staging.path}/state');
          if (await pending.exists()) await pending.delete();
          await staging.delete();
        } on FileSystemException catch (_) {}
      }
    }
  }
}

Uint8List protectGitHubState(List<int> bytes, {bool decrypt = false}) {
  try {
    return protectDeviceData(bytes, decrypt: decrypt);
  } catch (_) {
    throw const GitHubFailure(GitHubProblem.storage);
  }
}
