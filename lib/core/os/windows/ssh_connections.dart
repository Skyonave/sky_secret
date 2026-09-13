import 'dart:async';

import 'package:flutter/services.dart';

import '../../crypto/crypto.dart';

class SshConnections {
  final Future<bool> Function(String prompt) confirmHost;
  final void Function(bool success) onExit;
  final void Function(bool pending)? onAuthorizationChanged;
  final MethodChannel channel;
  final _grants = <String, ({VaultSession session, VaultEntry entry})>{};
  final _active = <String>{};
  final _awaitingDelivery = <String>{};
  final _deadlines = <String, Timer>{};
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  bool _authorizationPending = false;
  int _epoch = 0;

  SshConnections({
    required this.confirmHost,
    required this.onExit,
    this.onAuthorizationChanged,
    this.channel = const MethodChannel('skysecret/ssh'),
  });

  Future<void> start(
    String vaultId,
    VaultSession session,
    VaultEntry entry,
  ) async {
    final endpoint = entry.ssh;
    if (_disposed ||
        session.isLocked ||
        entry.isDeleted ||
        endpoint == null ||
        !endpoint.isValid ||
        !SshEndpoint.validUsername(entry.username) ||
        !SshEndpoint.validPassword(entry.password)) {
      throw PlatformException(code: 'invalid');
    }
    final key = '$vaultId:${entry.id}';
    if (_active.contains(key)) throw PlatformException(code: 'active');
    final epoch = _epoch;
    _active.add(key);
    _grants[key] = (session: session, entry: entry);
    _deadlines[key] = Timer(const Duration(minutes: 2), () {
      _grants.remove(key);
      _awaitingDelivery.remove(key);
      _notifyAuthorization();
    });
    _notifyAuthorization();
    try {
      await channel.invokeMethod<void>('start', {
        'key': key,
        'host': endpoint.host.toLowerCase(),
        'port': endpoint.port.toString(),
        'user': entry.username,
      });
      if (_disposed || epoch != _epoch || session.isLocked) {
        _grants.remove(key);
        await channel.invokeMethod<void>('revoke');
      }
      if (!_disposed) {
        _timer ??= Timer.periodic(
          const Duration(milliseconds: 150),
          (_) => poll(),
        );
      }
    } catch (_) {
      _active.remove(key);
      _grants.remove(key);
      _notifyAuthorization();
      rethrow;
    }
  }

  Future<void> poll() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      final events = await channel.invokeListMethod<dynamic>('poll') ?? [];
      for (final event in events.cast<Map>()) {
        final key = event['key'] as String;
        final type = event['type'] as String;
        if (type == 'exit') {
          _active.remove(key);
          _grants.remove(key);
          _awaitingDelivery.remove(key);
          if (!_disposed) onExit(event['ok'] == true);
          continue;
        }
        if (type == 'released') {
          _awaitingDelivery.remove(key);
          continue;
        }
        final grant = _grants[key];
        final epoch = _epoch;
        var answer = '';
        if (grant != null && _canUseGrant(grant) && !_disposed) {
          if (type == 'hostKey') {
            final accepted = await confirmHost(event['prompt'] as String);
            if (accepted && epoch == _epoch && _canUseGrant(grant) && !_disposed) {
              answer = 'yes';
            }
          } else if (type == 'password') {
            _grants.remove(key);
            _awaitingDelivery.add(key);
            answer = grant.entry.password;
          }
        }
        if (epoch != _epoch || _disposed || grant?.session.isLocked == true) {
          answer = '';
        }
        await channel.invokeMethod<void>('reply', {
          'key': key,
          'answer': answer,
        });
      }
    } catch (_) {
      revoke();
    } finally {
      _polling = false;
      _notifyAuthorization();
      if (_active.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  bool _canUseGrant(({VaultSession session, VaultEntry entry}) grant) {
    if (grant.session.isLocked || grant.entry.isDeleted) return false;
    final current = grant.session.entries.where((entry) => entry.id == grant.entry.id).firstOrNull;
    if (current == null || current.isDeleted) return false;
    return current.ssh?.host == grant.entry.ssh?.host &&
        current.ssh?.port == grant.entry.ssh?.port &&
        current.username == grant.entry.username &&
        current.password == grant.entry.password;
  }

  void revoke() {
    _epoch++;
    _grants.clear();
    _awaitingDelivery.clear();
    _notifyAuthorization();
    unawaited(channel.invokeMethod<void>('revoke').catchError((Object _) {}));
  }

  void dispose() {
    _disposed = true;
    revoke();
    _timer?.cancel();
  }

  void _notifyAuthorization() {
    for (final key in _deadlines.keys.toList()) {
      if (!_grants.containsKey(key) && !_awaitingDelivery.contains(key)) {
        _deadlines.remove(key)?.cancel();
      }
    }
    final pending = _grants.isNotEmpty || _awaitingDelivery.isNotEmpty;
    if (pending == _authorizationPending) return;
    _authorizationPending = pending;
    onAuthorizationChanged?.call(pending);
  }
}
