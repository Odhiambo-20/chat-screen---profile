import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wrytte/services/matrix/matrix_client.dart';

/// Persists per-room mute state in private Matrix account data.
class MuteRoomsService {
  MuteRoomsService._();
  static final instance = MuteRoomsService._();

  static const accountDataType = 'mute_rooms';
  Future<void> _writeQueue = Future<void>.value();
  Map<String, dynamic>? _localRooms;
  final Set<String> _locallyRemovedRooms = <String>{};

  /// Incremented whenever a room's mute state changes. Screens that display
  /// mute state can listen and rebuild immediately after mute/unmute.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _changed() => revision.value++;

  Future<void> mute(String roomId, Duration duration) {
    final until = DateTime.now().toUtc().add(duration);
    return _enqueue(() => _write(roomId, until));
  }

  Future<void> muteForever(String roomId) =>
      _enqueue(() => _write(roomId, null));

  Future<void> unmute(String roomId) =>
      _enqueue(() => _write(roomId, null, remove: true));

  Future<bool> isMuted(String roomId) async {
    final id = roomId.trim();
    if (id.isEmpty) {
      debugPrint('[MuteRooms] state skipped room="" reason="empty_room_id"');
      return false;
    }
    if (!MatrixClientService.instance.isInitialized) {
      debugPrint(
        '[MuteRooms] state room="$id" muted=false reason="matrix_not_initialized"',
      );
      return false;
    }
    final rooms = _roomsFromAccountData();
    final raw = rooms[id];
    if (raw == null) {
      debugPrint('[MuteRooms] state room="$id" muted=false reason="not_found"');
      return false;
    }
    final rawValue = raw.toString().trim();
    if (rawValue.toLowerCase() == 'forever') {
      debugPrint('[MuteRooms] state room="$id" muted=true permanent=true');
      return true;
    }
    final until = DateTime.tryParse(rawValue);
    if (until != null && until.isAfter(DateTime.now().toUtc())) {
      debugPrint(
        '[MuteRooms] state room="$id" muted=true until="${until.toIso8601String()}"',
      );
      return true;
    }
    debugPrint('[MuteRooms] expired room="$id" value="$raw"');
    await unmute(id);
    return false;
  }

  Future<void> _write(
    String roomId,
    DateTime? until, {
    bool remove = false,
  }) async {
    final id = roomId.trim();
    final client = MatrixClientService.instance.client;
    final userId = client.userID;
    if (id.isEmpty || userId == null || userId.isEmpty) return;
    final rooms = _roomsFromAccountData();
    if (remove) {
      rooms.remove(id);
      _locallyRemovedRooms.add(id);
    } else {
      rooms[id] = until?.toIso8601String() ?? 'forever';
      _locallyRemovedRooms.remove(id);
    }
    await client.setAccountData(userId, accountDataType, {'rooms': rooms});
    _localRooms = rooms;
    _changed();
    debugPrint('[MuteRooms] updated room="$id" muted=${!remove}');
  }

  Map<String, dynamic> _roomsFromAccountData() {
    final event =
        MatrixClientService.instance.client.accountData[accountDataType];
    final raw = event?.content['rooms'];
    // Account data can arrive after the first home-page build. Always prefer
    // the current Matrix event so an initially empty cache cannot hide a
    // persisted mute after sync completes.
    if (raw is Map) {
      final rooms = Map<String, dynamic>.from(raw);
      // A setAccountData response can arrive after a newer local write. Keep
      // pending local values so a stale Matrix snapshot cannot erase another
      // room's mute state.
      final merged = <String, dynamic>{...rooms, ...?_localRooms};
      for (final removed in _locallyRemovedRooms) {
        merged.remove(removed);
      }
      return merged;
    }
    return Map<String, dynamic>.from(_localRooms ?? const <String, dynamic>{});
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeQueue.then((_) => operation());
    _writeQueue = next.catchError((Object error, StackTrace stack) {
      debugPrint('[MuteRooms] account data update failed: $error');
    });
    return next;
  }
}
