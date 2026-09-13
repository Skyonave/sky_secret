import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/ui/vault/controllers/vault_browser_controller.dart';
import 'package:skysecret/ui/vault/controllers/vault_entry_controller.dart';
import 'package:skysecret/ui/vault/controllers/vault_session_controller.dart';
import 'package:skysecret/ui/vault/controllers/vault_sync_controller.dart';
import 'package:skysecret/core/sync/github/github_backup.dart';

import 'github_test.dart' show FakeGitHub, MemoryStorage, seed;
import 'vault_sync_test.dart' show RacingGitHub;
import 'vault_collection_test.dart' show collectionPassword, saveRevision;

class DeferredVaultStore extends VaultStore {
  final completion = Completer<VaultSession>();

  DeferredVaultStore() : super(file: File('synthetic-unused.smv'));

  @override
  Future<bool> exists() async => true;

  @override
  Future<VaultSession> unlock(String password) => completion.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('search matches names and locations, excludes secret contents and isolates trash', () async {
    final session = await VaultCipher.create(collectionPassword);
    addTearDown(session.lock);
    final section = VaultFolder.create('Проект');
    final folder = VaultFolder.create('Production', parentId: section.id);
    final active = VaultEntry.create(
      title: 'База данных',
      username: 'Operator',
      password: 'HiddenPasswordNeedle',
      notes: 'HiddenNotesNeedle',
      folderId: folder.id,
    ).withFavorite(true);
    final deleted = VaultEntry.create(title: 'Old database').inTrash(123);
    final file = VaultEntry.file(VaultAttachment.create('settings.txt', 'HiddenFileNeedle'.codeUnits));
    final bytes = await session.encrypt([active, deleted, file], folders: [section, folder]);
    session.acceptPersisted(bytes, [active, deleted, file], [section, folder], null);
    final browser = VaultBrowserController()..query = '  ПРОЕКТ operator production  ';
    expect(browser.results(session).single.entry.id, active.id);
    expect(browser.results(session).single.location, ['Проект', 'Production']);
    for (final hidden in ['HiddenPasswordNeedle', 'HiddenNotesNeedle', 'HiddenFileNeedle', 'Old database']) {
      browser.query = hidden;
      expect(browser.results(session), isEmpty);
    }
    browser.query = '';
    browser.view = VaultView.favorites;
    expect(browser.results(session).single.entry.id, active.id);
    browser.view = VaultView.trash;
    expect(browser.results(session).single.entry.id, deleted.id);
    browser.clear();
    expect(browser.filtering, isFalse);
    expect(browser.suggestions(session, ''), isEmpty);
    expect(browser.suggestions(session, '   '), isEmpty);
    browser.view = VaultView.trash;
    final suggestions = browser.suggestions(session, 'operator');
    expect(suggestions.single.keys.toSet(), {'id', 'title', 'username', 'location', 'kind', 'favorite'});
    expect(suggestions.single['id'], active.id);
    expect(suggestions.single['favorite'], isTrue);
    expect(suggestions.single['location'], 'Проект / Production');
    expect(browser.suggestions(session, 'Old database'), isEmpty);
    expect(browser.suggestions(session, 'HiddenPasswordNeedle'), isEmpty);
    session.lock();
    expect(browser.results(session), isEmpty);
    expect(browser.suggestions(session, 'operator'), isEmpty);
  });

  test('entry controller preserves favorite and location, validates and clears draft secrets', () async {
    final session = await VaultCipher.create(collectionPassword);
    addTearDown(session.lock);
    final entry = VaultEntry.create(
      title: 'Synthetic entry',
      password: 'Synthetic secret',
    ).withFavorite(true).atPosition(null, 123);
    await saveRevision(session, [entry]);
    final editor = VaultEntryController();
    addTearDown(editor.dispose);
    editor.start(entry: session.entries.single);
    editor.title.text = 'Renamed synthetic entry';
    final prepared = editor.prepare(session).entries.single;
    expect(prepared.isFavorite, isTrue);
    expect(prepared.order, 123);
    expect(session.entries.single.title, 'Synthetic entry');
    editor.title.clear();
    expect(() => editor.prepare(session), throwsA(isA<EntryValidationException>()));
    editor.clear();
    expect(editor.active, isFalse);
    expect(editor.password.text, isEmpty);
    expect(editor.id, isNull);
    editor.start(entry: entry.inTrash(123));
    expect(editor.active, isFalse);
  });

  test('locking or disposing rejects and revokes a late unlock', () async {
    for (final dispose in [false, true]) {
      final store = DeferredVaultStore();
      final controller = VaultSessionController(store: store);
      await controller.load();
      final pending = controller.open(collectionPassword);
      if (dispose) {
        controller.dispose();
      } else {
        controller.lock();
      }
      final lateSession = await VaultCipher.create(collectionPassword);
      store.completion.complete(lateSession);
      expect(await pending, isFalse);
      expect(controller.session, isNull);
      expect(lateSession.isLocked, isTrue);
      controller.dispose();
    }
  });

  test('session controller commits state only after successful save and supports vault selection', () async {
    final directory = await Directory.systemTemp.createTemp('sky-controller-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = VaultSessionController(catalog: VaultCatalog(directory: directory));
    addTearDown(controller.dispose);
    await controller.load();
    expect(await controller.open(collectionPassword, name: 'Synthetic vault'), isTrue);
    final id = controller.selectedId;
    expect(await controller.save([VaultEntry.create(title: 'Synthetic entry')]), isTrue);
    expect(controller.names[id], 'Synthetic vault');
    final original = controller.session!;
    await controller.select(null);
    expect(original.isLocked, isTrue);
    expect(controller.session, isNull);
    expect(controller.exists, isFalse);
    await controller.select(id);
    expect(await controller.open(collectionPassword), isTrue);
    expect(controller.session!.entries.single.title, 'Synthetic entry');
  });

  test('a failed controller save keeps the active session unchanged', () async {
    final directory = await Directory.systemTemp.createTemp('sky-controller-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/vault.smv');
    final setup = VaultStore(file: file);
    final created = await setup.create(collectionPassword);
    created.lock();
    final controller = VaultSessionController(
      store: VaultStore(file: file, beforeCommit: () async => throw const FileSystemException('Synthetic failure')),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.open(collectionPassword);
    final before = controller.session!.persistedBytes;
    await expectLater(
      controller.save([VaultEntry.create(title: 'Synthetic failure')]),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.session!.entries, isEmpty);
    expect(controller.session!.persistedBytes, before);
  });

  test('sync controller refuses a locked workspace without contacting GitHub', () async {
    final directory = await Directory.systemTemp.createTemp('sky-sync-controller-');
    addTearDown(() => directory.delete(recursive: true));
    final catalog = VaultCatalog(directory: directory);
    final vault = VaultSessionController(catalog: catalog);
    addTearDown(vault.dispose);
    final api = FakeGitHub();
    final backup = GitHubBackup(api: api, storage: MemoryStorage(null), catalog: catalog);
    addTearDown(backup.dispose);
    final sync = VaultSyncController(vault);
    expect(await sync.synchronize(backup), VaultSyncResult.unavailable);
    expect(sync.busy, isFalse);
    expect(api.publishes, 0);
  });

  test('sync coordinator restores separately, merges trash and refuses a changed remote key', () async {
    final directory = await Directory.systemTemp.createTemp('sky-sync-coordinator-');
    addTearDown(() => directory.delete(recursive: true));
    final firstCatalog = VaultCatalog(directory: Directory('${directory.path}/first'));
    final secondCatalog = VaultCatalog(directory: Directory('${directory.path}/second'));
    final first = VaultSessionController(catalog: firstCatalog);
    final second = VaultSessionController(catalog: secondCatalog);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.load();
    await second.load();
    await first.open(collectionPassword);
    await first.save([VaultEntry.create(title: 'Synthetic shared entry')]);
    final api = RacingGitHub();
    final firstBackup = GitHubBackup(catalog: firstCatalog, storage: MemoryStorage(seed()), api: api);
    final secondBackup = GitHubBackup(catalog: secondCatalog, storage: MemoryStorage(seed()), api: api);
    addTearDown(firstBackup.dispose);
    addTearDown(secondBackup.dispose);
    await firstBackup.initialize(schedule: false);
    await secondBackup.initialize(schedule: false);
    final firstSync = VaultSyncController(first);
    final secondSync = VaultSyncController(second);
    expect(await firstSync.synchronize(firstBackup), VaultSyncResult.done);
    final remote = api.remote.values.single;
    expect(await secondSync.restore(secondBackup, api.blobs[remote.blob]!, collectionPassword, remote: remote), isTrue);
    await second.save([second.session!.entries.single.withFavorite(true).inTrash(123)]);
    expect(await secondSync.synchronize(secondBackup), VaultSyncResult.done);
    expect(await firstSync.synchronize(firstBackup), VaultSyncResult.done);
    expect(first.session!.entries.single.isDeleted, isTrue);
    expect(first.session!.entries.single.isFavorite, isTrue);
    await second.changePassword(collectionPassword, 'Synthetic changed remote passphrase');
    expect(await secondSync.synchronize(secondBackup), VaultSyncResult.done);
    final original = first.session!;
    final originalFile = first.store!.file;
    final originalBytes = original.persistedBytes;
    expect(await firstSync.synchronize(firstBackup), VaultSyncResult.keyChanged);
    expect(first.session, same(original));
    expect(await originalFile.readAsBytes(), originalBytes);
    final changedRemote = api.remote.values.single;
    expect(
      await firstSync.restore(firstBackup, api.blobs[changedRemote.blob]!, 'Synthetic changed remote passphrase'),
      isTrue,
    );
    expect(first.store!.file.path, isNot(originalFile.path));
    expect(await originalFile.readAsBytes(), originalBytes);
    expect(firstBackup.localForRemote(remote.id), 'legacy');
  });

  test('controller deletion revokes its session and returns to an empty selection', () async {
    final directory = await Directory.systemTemp.createTemp('sky-controller-delete-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = VaultSessionController(catalog: VaultCatalog(directory: directory));
    addTearDown(controller.dispose);
    await controller.load();
    await controller.open(collectionPassword);
    final session = controller.session!;
    await controller.deleteSelected();
    expect(session.isLocked, isTrue);
    expect(controller.session, isNull);
    expect(controller.exists, isFalse);
  });
}
