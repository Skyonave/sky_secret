import '../../../core/crypto/crypto.dart';

enum VaultView { all, favorites, trash }

class VaultSearchResult {
  final VaultEntry entry;
  final List<String> location;

  const VaultSearchResult(this.entry, this.location);
}

class VaultBrowserController {
  String query = '';
  VaultView view = VaultView.all;

  bool get filtering => query.trim().isNotEmpty || view != VaultView.all;

  List<Map<String, Object>> suggestions(VaultSession session, String query) {
    if (query.trim().isEmpty || query.length > 256) return [];
    final search = VaultBrowserController()..query = query;
    return search.results(session).take(50).map((result) {
      final entry = result.entry;
      return <String, Object>{
        'id': entry.id,
        'title': entry.title,
        'username': entry.username,
        'location': result.location.join(' / '),
        'kind': entry.isFile
            ? 'file'
            : entry.isSsh
            ? 'ssh'
            : 'secret',
        'favorite': entry.isFavorite,
      };
    }).toList();
  }

  List<VaultSearchResult> results(VaultSession session) {
    if (session.isLocked) return [];
    final folders = {for (final folder in session.folders) folder.id: folder};
    final words = query.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    final found = <VaultSearchResult>[];
    for (final entry in session.entries) {
      if (entry.isDeleted != (view == VaultView.trash)) continue;
      if (view == VaultView.favorites && entry.isFavorite == false) continue;
      final folder = folders[entry.folderId];
      final parent = folders[folder?.parentId];
      final location = [if (parent != null) parent.name, if (folder != null) folder.name];
      final searchable = [entry.title, entry.username, entry.ssh?.host ?? '', ...location].join(' ').toLowerCase();
      if (words.every(searchable.contains)) found.add(VaultSearchResult(entry, location));
    }
    found.sort((left, right) {
      if (view == VaultView.trash) {
        final deleted = right.entry.deletedAt!.compareTo(left.entry.deletedAt!);
        if (deleted != 0) return deleted;
      }
      final order = left.entry.order.compareTo(right.entry.order);
      return order == 0 ? left.entry.id.compareTo(right.entry.id) : order;
    });
    return found;
  }

  void clear() {
    query = '';
    view = VaultView.all;
  }
}
