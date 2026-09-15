class VaultDeletionController {
  final _pending = <String, ({int deletedAt, DateTime deadline})>{};

  Set<String> get ids => _pending.keys.toSet();

  void start(String id, int deletedAt, DateTime now) {
    _pending[id] = (deletedAt: deletedAt, deadline: now.add(const Duration(seconds: 10)));
  }

  int remaining(String id, DateTime now) {
    final pending = _pending[id];
    if (pending == null) return 0;
    return (pending.deadline.difference(now).inMilliseconds / 1000).ceil().clamp(0, 10);
  }

  int? timestamp(String id) => _pending[id]?.deletedAt;

  void expire(DateTime now) => _pending.removeWhere((id, _) => remaining(id, now) == 0);

  void remove(String id) => _pending.remove(id);

  void clear() => _pending.clear();
}
