import 'github_api.dart';

class FineGrainedToken {
  final String value;

  FineGrainedToken(String value) : value = value.trim() {
    if (!RegExp(r'^github_pat_[A-Za-z0-9_]{20,500}$').hasMatch(this.value)) {
      throw const GitHubFailure(GitHubProblem.configuration);
    }
  }
}

class GitHubRepositoryAddress {
  late final String owner, name;

  GitHubRepositoryAddress.parse(String input) {
    var path = input.trim();
    if (path.startsWith('https://')) {
      if (!path.startsWith('https://github.com/')) {
        throw const GitHubFailure(GitHubProblem.configuration);
      }
      path = path.substring('https://github.com/'.length);
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    final parts = path.split('/');
    if (parts.length != 2 ||
        !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$').hasMatch(parts[0]) ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(parts[1]) ||
        parts[1] == '.' ||
        parts[1] == '..') {
      throw const GitHubFailure(GitHubProblem.configuration);
    }
    owner = parts[0];
    name = parts[1];
  }

  String get route => '/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(name)}';

  String get label => '$owner/$name';
}
