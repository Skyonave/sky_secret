part of 'github_api.dart';

class GitHubUser {
  final int id;
  final String login;

  GitHubUser.fromJson(Map<String, dynamic> json) : id = positiveInt(json['id']), login = string(json['login']);
}

class GitHubRepository {
  final int id, ownerId;
  final String owner, name, branch;
  final bool safe;

  GitHubRepository.fromJson(Map<String, dynamic> json)
    : id = positiveInt(json['id']),
      ownerId = positiveInt(object(json['owner'])['id']),
      owner = string(object(json['owner'])['login']),
      name = string(json['name']),
      branch = string(json['default_branch']),
      safe =
          json['private'] == true &&
          json['fork'] == false &&
          json['archived'] == false &&
          json['disabled'] != true &&
          object(json['permissions'])['push'] == true;

  String get route => '/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(name)}';

  String get label => '$owner/$name';

  void validate(int userId) {
    if (!safe || ownerId != userId) {
      throw const GitHubFailure(GitHubProblem.denied);
    }
  }
}

class RemoteVault {
  final String id, blob;
  final int size;

  const RemoteVault(
    this.id,
    this.blob,
    this.size,
  );
}

class RemoteSnapshot {
  final String commit, tree;
  final Map<String, RemoteVault> vaults;

  const RemoteSnapshot(
    this.commit,
    this.tree,
    this.vaults,
  );
}
