part of 'github_api.dart';

Future<GitHubResponse> githubHttp(
  String method,
  Uri uri,
  Map<String, String> headers,
  Object? body,
  int limit,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    return await (() async {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      if (response.contentLength > limit) {
        throw const GitHubFailure(GitHubProblem.format);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > limit) {
          throw const GitHubFailure(GitHubProblem.format);
        }
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      return GitHubResponse(
        response.statusCode,
        data.isEmpty || response.statusCode >= 300 ? null : jsonDecode(utf8.decode(data)),
        {
          for (final name in [
            'retry-after',
            'x-ratelimit-reset',
            'x-ratelimit-remaining',
            'link',
          ])
            if (response.headers.value(name) != null) name: response.headers.value(name)!,
        },
      );
    })().timeout(const Duration(minutes: 3));
  } on GitHubFailure {
    rethrow;
  } on FormatException {
    throw const GitHubFailure(GitHubProblem.format);
  } catch (_) {
    throw const GitHubFailure(GitHubProblem.network);
  } finally {
    client.close(force: true);
  }
}
