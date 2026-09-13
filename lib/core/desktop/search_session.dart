class VaultSearchSession {
  final bool Function() isValid;
  final List<Map<String, Object>> Function(String) find;
  final void Function() activity;
  bool _closed = false;
  List<Map<String, Object>> _results = [];

  VaultSearchSession({required this.isValid, required this.find, required this.activity});

  bool get valid => !_closed && isValid();

  List<Map<String, Object>> search(String query) {
    _results = [];
    if (!valid || query.trim().isEmpty || query.length > 256) return [];
    activity();
    _results = find(query).take(50).toList();
    return List.unmodifiable(_results);
  }

  bool accepts(String? id) => valid && id != null && _results.any((result) => result['id'] == id);

  void close() {
    _closed = true;
    _results = [];
  }
}
