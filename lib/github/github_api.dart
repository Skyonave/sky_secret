import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'github_credentials.dart';

part '_github_transport.dart';
part '_github_models.dart';

enum GitHubProblem {
  network,
  authorization,
  denied,
  missing,
  conflict,
  repositoryChanged,
  repositorySetup,
  format,
  storage,
  identity,
  cancelled,
  configuration,
}

class GitHubFailure implements Exception {
  final GitHubProblem problem;
  final Duration? retryAfter;

  const GitHubFailure(this.problem, {this.retryAfter});

  @override
  String toString() => 'GitHubFailure(${problem.name})';
}

class GitHubResponse {
  final int status;
  final Object? body;
  final Map<String, String> headers;

  const GitHubResponse(
    this.status,
    this.body, [
    this.headers = const {},
  ]);
}

typedef GitHubTransport = Future<GitHubResponse> Function(
  String method,
  Uri uri,
  Map<String, String> headers,
  Object? body,
  int limit,
);

Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const GitHubFailure(GitHubProblem.format);
  }
  return value;
}

String string(Object? value) {
  if (value is! String || value.isEmpty || value.length > 1024) {
    throw const GitHubFailure(GitHubProblem.format);
  }
  return value;
}

int positiveInt(Object? value) {
  if (value is! int || value <= 0) {
    throw const GitHubFailure(GitHubProblem.format);
  }
  return value;
}

String sha(Object? value) {
  final result = string(value);
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(result)) {
    throw const GitHubFailure(GitHubProblem.format);
  }
  return result;
}

const randomBackupIdPattern = r'^[0-9a-f]{32}$';
String backupId(Object? value) {
  final result = string(value);
  if (!RegExp(randomBackupIdPattern).hasMatch(result)) {
    throw const GitHubFailure(GitHubProblem.format);
  }
  return result;
}

Future<String> gitBlobHash(List<int> bytes) => Isolate.run(() => _gitBlobHash(bytes));

Future<String> _gitBlobHash(List<int> bytes) async {
  final sink = Sha1().newHashSink();
  sink.add(utf8.encode('blob ${bytes.length}\u0000'));
  sink.add(bytes);
  sink.close();
  final hash = await sink.hash();
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class GitHubApi {
  final GitHubTransport transport;
  DateTime? _notBefore;
  static const apiVersion = '2026-03-10';
  static const appId = 'secret-manager-vault';
  static const marker = '{"appId":"secret-manager-vault","version":1}';
  static const maxVaultBytes = 72 * 1024 * 1024;

  GitHubApi({GitHubTransport? transport}) : transport = transport ?? githubHttp;

  Future<Object?> request(
    String method,
    String path, {
    String? token,
    Object? body,
    int limit = 2 * 1024 * 1024,
  }) async {
    if (_notBefore != null && DateTime.now().isBefore(_notBefore!)) {
      throw GitHubFailure(
        GitHubProblem.denied,
        retryAfter: _notBefore!.difference(DateTime.now()),
      );
    }
    final uri = Uri.parse('https://api.github.com$path');
    if (!path.startsWith('/') || uri.userInfo.isNotEmpty || uri.host != 'api.github.com') {
      throw const GitHubFailure(GitHubProblem.configuration);
    }
    final response = await transport(
      method,
      uri,
      {
        'Accept': 'application/json',
        'User-Agent': 'SkySecret',
        'X-GitHub-Api-Version': apiVersion,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body,
      limit,
    );
    if (response.status >= 200 && response.status < 300) return response.body;
    Duration? retry;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    if (seconds != null) retry = Duration(seconds: max(1, seconds));
    if (seconds == null && response.headers['retry-after'] != null) {
      try {
        retry = HttpDate.parse(response.headers['retry-after']!).difference(DateTime.now());
        if (retry.isNegative) retry = const Duration(seconds: 1);
      } on FormatException catch (_) {}
    }
    if (response.headers['x-ratelimit-remaining'] == '0' && reset != null) {
      retry = Duration(
        seconds: (reset - DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1).clamp(1, 1 << 32),
      );
    }
    if (response.status == 403 || response.status == 429) {
      retry ??= const Duration(minutes: 1);
    }
    if (retry != null) _notBefore = DateTime.now().add(retry);
    throw GitHubFailure(
      switch (response.status) {
        401 => GitHubProblem.authorization,
        403 || 429 => GitHubProblem.denied,
        404 => GitHubProblem.missing,
        409 || 422 => GitHubProblem.conflict,
        >= 500 => GitHubProblem.network,
        _ => GitHubProblem.format,
      },
      retryAfter: retry ?? (response.status == 429 ? const Duration(minutes: 1) : null),
    );
  }

  Future<GitHubUser> user(String token) async =>
      GitHubUser.fromJson(object(await request('GET', '/user', token: token)));

  Future<GitHubRepository> repository(
    String token,
    int id,
    int userId,
  ) async {
    final repo = GitHubRepository.fromJson(
      object(await request('GET', '/repositories/$id', token: token)),
    );
    if (repo.id != id) throw const GitHubFailure(GitHubProblem.format);
    repo.validate(userId);
    return repo;
  }

  Future<GitHubRepository> repositoryByAddress(
    String token,
    GitHubRepositoryAddress address,
    int userId,
  ) async {
    final repo = GitHubRepository.fromJson(
      object(await request('GET', address.route, token: token)),
    );
    repo.validate(userId);
    return repo;
  }

  static void validateMarker(List<int> bytes) {
    try {
      if (bytes.length > 4096) throw const FormatException();
      final json = object(jsonDecode(utf8.decode(bytes)));
      if (json['appId'] != appId || json['version'] != 1) {
        throw const FormatException();
      }
    } catch (_) {
      throw const GitHubFailure(GitHubProblem.format);
    }
  }

  Future<Uint8List> blob(
    String token,
    GitHubRepository repo,
    String hash, {
    int limit = maxVaultBytes,
  }) async {
    final response = object(
      await request(
        'GET',
        '${repo.route}/git/blobs/${sha(hash)}',
        token: token,
        limit: (limit * 1.5).ceil() + 8192,
      ),
    );
    if (response['encoding'] != 'base64' ||
        response['size'] is! int ||
        (response['size'] as int) < 0 ||
        (response['size'] as int) > limit ||
        response['content'] is! String) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(
        (response['content'] as String).replaceAll('\n', ''),
      );
    } catch (_) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    if (bytes.length != response['size'] || bytes.length > limit || await gitBlobHash(bytes) != hash) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return bytes;
  }

  Future<RemoteSnapshot> snapshot(
    String token,
    GitHubRepository repo, {
    bool initializing = false,
  }) async {
    final ref = object(
      await request(
        'GET',
        '${repo.route}/git/ref/heads/${Uri.encodeComponent(repo.branch)}',
        token: token,
      ),
    );
    final commit = sha(object(ref['object'])['sha']);
    final detail = object(
      await request('GET', '${repo.route}/git/commits/$commit', token: token),
    );
    final tree = sha(object(detail['tree'])['sha']);
    final root = await _tree(token, repo, tree);
    final markerEntries = root.where((e) => e['path'] == 'vault.json').toList();
    if (markerEntries.isEmpty && initializing) {
      if (root.any(
        (e) => e['path'] != 'README.md' || e['type'] != 'blob' || e['mode'] != '100644',
      )) {
        throw const GitHubFailure(GitHubProblem.repositorySetup);
      }
    } else {
      if (markerEntries.length != 1 ||
          markerEntries.single['type'] != 'blob' ||
          markerEntries.single['mode'] != '100644') {
        throw const GitHubFailure(GitHubProblem.format);
      }
      validateMarker(
        await blob(token, repo, sha(markerEntries.single['sha']), limit: 4096),
      );
    }
    final folders = root.where((e) => e['path'] == 'vaults').toList();
    final vaults = <String, RemoteVault>{};
    if (folders.isNotEmpty) {
      if (folders.length != 1 || folders.single['type'] != 'tree') {
        throw const GitHubFailure(GitHubProblem.format);
      }
      for (final entry in await _tree(
        token,
        repo,
        sha(folders.single['sha']),
      )) {
        final path = string(entry['path']);
        if (!RegExp(r'^[0-9a-f]{32}\.smv$').hasMatch(path) || entry['type'] != 'blob' || entry['mode'] != '100644') {
          throw const GitHubFailure(GitHubProblem.format);
        }
        final size = positiveInt(entry['size']);
        if (size > maxVaultBytes) {
          throw const GitHubFailure(GitHubProblem.format);
        }
        final id = path.substring(0, 32);
        if (vaults.containsKey(id)) {
          throw const GitHubFailure(GitHubProblem.format);
        }
        vaults[id] = RemoteVault(id, sha(entry['sha']), size);
      }
    }
    return RemoteSnapshot(commit, tree, vaults);
  }

  Future<List<Map<String, dynamic>>> _tree(
    String token,
    GitHubRepository repo,
    String hash,
  ) async {
    final json = object(
      await request('GET', '${repo.route}/git/trees/$hash', token: token),
    );
    if (json['truncated'] != false || json['tree'] is! List) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return (json['tree'] as List).map(object).toList();
  }

  Future<String> upload(
    String token,
    GitHubRepository repo,
    Uint8List bytes,
  ) async {
    if (bytes.length > maxVaultBytes) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    final result = object(
      await request(
        'POST',
        '${repo.route}/git/blobs',
        token: token,
        body: {'content': base64.encode(bytes), 'encoding': 'base64'},
      ),
    );
    final hash = sha(result['sha']);
    if (hash != await gitBlobHash(bytes)) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return hash;
  }

  Future<String> commit(
    String token,
    GitHubRepository repo,
    RemoteSnapshot base,
    Map<String, String> updates,
  ) async {
    final tree = object(
      await request(
        'POST',
        '${repo.route}/git/trees',
        token: token,
        body: {
          'base_tree': base.tree,
          'tree': [
            {
              'path': 'vault.json',
              'mode': '100644',
              'type': 'blob',
              'content': marker,
            },
            for (final entry in updates.entries)
              {
                'path': 'vaults/${backupId(entry.key)}.smv',
                'mode': '100644',
                'type': 'blob',
                'sha': sha(entry.value),
              },
          ],
        },
      ),
    );
    final commit = object(
      await request(
        'POST',
        '${repo.route}/git/commits',
        token: token,
        body: {
          'message': 'Encrypted vault backup',
          'tree': sha(tree['sha']),
          'parents': [base.commit],
        },
      ),
    );
    return sha(commit['sha']);
  }

  Future<void> publish(
    String token,
    GitHubRepository repo,
    String commit,
  ) async {
    await request(
      'PATCH',
      '${repo.route}/git/refs/heads/${Uri.encodeComponent(repo.branch)}',
      token: token,
      body: {'sha': sha(commit), 'force': false},
    );
  }
}
