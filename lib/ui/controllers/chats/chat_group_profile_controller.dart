part of '../../screens/chats/chat_screen.dart';

extension _ChatGroupProfileController on _ChatScreenState {
  int _groupMemberCount() {
    if (_isDeletedConversation) return 0;
    if (_isReadOnlySuggestedGroup &&
        widget.initialMemberCount != null &&
        widget.initialMemberCount! > 0) {
      return widget.initialMemberCount!;
    }
    final room = MatrixChatService.instance.getRoomById(_activeConversationId);
    final roomCount =
        _groupMembers.isNotEmpty
            ? _groupMembers.length
            : room == null
            ? 0
            : MatrixChatService.instance.groupMemberCount(room);
    if (roomCount > 0) return roomCount;

    final cachedConversation = _chat.cachedConversationsSnapshot.firstWhere(
      (conversation) =>
          conversation.id == _activeConversationId ||
          conversation.id == widget.conversationId,
      orElse:
          () => ChatConversation(
            id: '',
            participants: const [],
            otherUserId: '',
            lastMessage: '',
            lastMessageSenderId: '',
            lastMessageTime: DateTime.fromMillisecondsSinceEpoch(0),
            unreadCount: 0,
            lastMessageType: 'group',
          ),
    );
    if (cachedConversation.participants.length > 1) {
      return cachedConversation.participants.length;
    }

    final ids = <String>{};
    for (final message in _messages) {
      final sender = message.senderId.trim();
      if (sender.isNotEmpty) ids.add(sender);
      final receiver = message.receiverId.trim();
      if (receiver.isNotEmpty && !receiver.startsWith('!')) ids.add(receiver);
    }
    final current = widget.currentUserId.trim();
    if (current.isNotEmpty) ids.add(current);
    return ids.length.clamp(1, 999999).toInt();
  }

  String _groupSubtitle() {
    final count = _groupMemberCount();
    return count == 1 ? '1 member' : '$count members';
  }

  bool get _isGroupChat {
    final kind = ConversationKind.normalize(widget.conversationKind);
    if (kind == ConversationKind.group || kind == ConversationKind.channel) {
      return true;
    }
    if (kind == ConversationKind.direct) return false;
    return widget.readOnlyUntilJoin ||
        _isKnownGroupConversationId(widget.receiverId) ||
        _isKnownGroupConversationId(widget.conversationId) ||
        _cachedConversationIsGroup(widget.conversationId) ||
        (_resolvedConversationId != null &&
            _cachedConversationIsGroup(_resolvedConversationId!));
  }

  String? _initialStableHeaderAvatarUrl() {
    if (_isKnownGroupConversationId(widget.conversationId) ||
        _isKnownGroupConversationId(widget.receiverId) ||
        widget.readOnlyUntilJoin) {
      final room =
          MatrixChatService.instance.getRoomById(widget.conversationId) ??
          MatrixChatService.instance.getRoomById(widget.receiverId);
      return _safeGroupRoomAvatarUrl(room);
    }
    return _safePersonHeaderAvatar(widget.avatarUrl);
  }

  bool _isKnownGroupConversationId(String value) {
    final id = value.trim();
    if (id.isEmpty || !id.startsWith('!')) return false;
    final room = MatrixChatService.instance.getRoomById(id);
    if (room != null) {
      return MatrixChatService.instance.isMatrixGroupRoom(room);
    }
    return _cachedConversationIsGroup(id);
  }

  String? _safeGroupRoomAvatarUrl(mx.Room? room) {
    final raw = room?.getState(mx.EventTypes.RoomAvatar)?.content['url'];
    final stateAvatar = raw is String ? raw.trim() : '';
    // Unjoined suggested rooms are not present in the client's synced room
    // list. Their public-directory avatar is still room-owned and arrives
    // already scoped to widget.conversationId by the discovery result.
    final avatar =
        stateAvatar.isNotEmpty
            ? stateAvatar
            : _isReadOnlySuggestedGroup
            ? widget.avatarUrl?.trim() ?? ''
            : '';
    if (avatar.isEmpty || _matchesGroupParticipantAvatar(room, avatar)) {
      return null;
    }
    return avatar;
  }

  bool _matchesGroupParticipantAvatar(mx.Room? room, String avatarUrl) {
    if (room == null) return false;
    final normalizedAvatar = _normaliseAvatarIdentity(avatarUrl);
    if (normalizedAvatar.isEmpty) return false;
    for (final member in room.getParticipants(_groupMemberships)) {
      if (member.id == MatrixClientService.instance.userId) continue;
      final memberAvatar = _normaliseAvatarIdentity(
        member.avatarUrl?.toString(),
      );
      if (memberAvatar.isNotEmpty && memberAvatar == normalizedAvatar) {
        return true;
      }
    }
    return false;
  }

  String _normaliseAvatarIdentity(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    if (uri.scheme == 'mxc') {
      return 'mxc://${uri.host}${uri.path}';
    }
    final segments = uri.pathSegments;
    final mediaIndex = segments.indexOf('media');
    if (mediaIndex >= 1 &&
        mediaIndex + 4 < segments.length &&
        segments[mediaIndex - 1] == '_matrix' &&
        segments[mediaIndex + 1] == 'v3' &&
        (segments[mediaIndex + 2] == 'download' ||
            segments[mediaIndex + 2] == 'thumbnail')) {
      final serverName = segments[mediaIndex + 3];
      final mediaId = segments.sublist(mediaIndex + 4).join('/');
      if (serverName.isNotEmpty && mediaId.isNotEmpty) {
        return 'mxc://$serverName/$mediaId';
      }
    }
    return trimmed;
  }

  String? _safePersonHeaderAvatar(String? avatarUrl) {
    final clean = avatarUrl?.trim() ?? '';
    // A person and a group may legitimately use the same image. Direct-chat
    // identity is already established by ConversationKind and receiver ID, so
    // rejecting a URL merely because it also appears on a room hides valid
    // contact avatars (for example in the header and profile entry point).
    if (clean.isEmpty) return null;
    return clean;
  }

  bool _cachedConversationIsGroup(String conversationId) {
    final room = MatrixChatService.instance.getRoomById(conversationId);
    if (room != null) {
      return MatrixChatService.instance.isMatrixGroupRoom(room);
    }
    final conversation = _chat.cachedConversationsSnapshot
        .where((item) => item.id == conversationId)
        .cast<ChatConversation?>()
        .firstWhere((item) => item != null, orElse: () => null);
    if (conversation == null) return false;
    if (conversation.hasExplicitKind) {
      return conversation.isGroupKind || conversation.isChannelKind;
    }
    if (conversation.lastMessageType == 'group' ||
        conversation.lastMessageType == ChatService.groupDeletedMessageType ||
        ChatService.isGroupDeletedPreview(conversation.lastMessage)) {
      return true;
    }
    return conversation.id.startsWith('!') &&
        conversation.participants.length > 2;
  }

  Future<void> _loadGroupMemberProfiles(String roomId) async {
    final room = MatrixChatService.instance.getRoomById(roomId);
    final members = room?.getParticipants(_groupMemberships) ?? const [];
    _setGroupMembers(members);
    final resolutions = <Future<void>>[];
    for (final member in members) {
      final fallback = _cleanDisplayName(member.calcDisplayname());
      if (fallback.isNotEmpty && !_groupMemberNames.containsKey(member.id)) {
        _groupMemberNames[member.id] = fallback;
      }
      resolutions.add(_loadGroupMemberProfileName(member.id));
    }
    await Future.wait(resolutions);
    if (room != null) {
      unawaited(_requestFullGroupMemberList(room));
    }
    if (mounted) _setChatState(() {});
  }

  Future<void> _primeGroupMemberProfiles(String roomId) async {
    await _loadGroupMemberProfiles(roomId);
    final senders = <String, ChatMessage>{};
    for (final message in _messages.followedBy(_initialStreamBuffer)) {
      final senderId = message.senderId.trim();
      if (senderId.isEmpty || senderId.startsWith('!') || _isMine(message)) {
        continue;
      }
      senders.putIfAbsent(senderId, () => message);
    }
    await Future.wait(
      senders.entries.map(
        (entry) => _loadGroupMemberProfileName(
          entry.key,
          phoneHint: entry.value.senderPhone,
        ),
      ),
    );
  }

  Future<void> _requestFullGroupMemberList(mx.Room room) async {
    try {
      final members = await room.requestParticipants(
        _groupMemberships,
        true,
        true,
      );
      if (!mounted) return;
      _setGroupMembers(members);
      for (final member in members) {
        final fallback = _cleanDisplayName(member.calcDisplayname());
        if (fallback.isNotEmpty && !_groupMemberNames.containsKey(member.id)) {
          _groupMemberNames[member.id] = fallback;
        }
        unawaited(_loadGroupMemberProfileName(member.id));
      }
      _setChatState(() {});
    } catch (_) {
      // Keep the local Matrix member snapshot if the full request is unavailable.
    }
  }

  void _setGroupMembers(List<mx.User> members) {
    final seen = <String>{};
    final unique = <mx.User>[];
    for (final member in members) {
      if (seen.add(member.id)) unique.add(member);
    }
    _groupMembers = unique;
  }

  String _groupSenderName(String matrixId) {
    final resolved = _cleanDisplayName(_groupMemberNames[matrixId]);
    if (resolved.isNotEmpty) return resolved;
    for (final member in _groupMembers) {
      if (member.id != matrixId) continue;
      final fallback = _cleanDisplayName(member.calcDisplayname());
      if (fallback.isNotEmpty) return fallback;
    }
    return 'Group member';
  }

  Future<void> _loadGroupMemberProfileName(
    String matrixId, {
    String? phoneHint,
  }) async {
    final senderId = matrixId.trim();
    if (senderId.isEmpty ||
        senderId.startsWith('!') ||
        !_groupSenderProfilesInFlight.add(senderId)) {
      return;
    }
    try {
      final localpart = _matrixLocalpart(senderId);
      if (localpart.isEmpty) return;
      final current = await AuthService.instance.getCurrentUserId();
      final isMe = _matrixLocalpart(current ?? '') == localpart;
      if (isMe) return;

      final ownerUserId = current?.trim() ?? '';
      final savedContact =
          ownerUserId.isEmpty
              ? null
              : await _findSavedContact(
                ownerUserId,
                senderId,
                phone: phoneHint,
              );
      if (savedContact != null) {
        final name = _cleanDisplayName(savedContact.formattedName);
        final avatar = savedContact.avatarUrl?.trim() ?? '';
        if (!mounted) return;
        _setChatState(() {
          if (name.isNotEmpty) _groupMemberNames[senderId] = name;
          if (avatar.isNotEmpty) _groupMemberAvatars[senderId] = avatar;
        });
        return;
      }

      final localProfile1 =
          ownerUserId.isEmpty
              ? null
              : await ContactIdentityCache.instance.findByMatrixId(
                ownerUserId: ownerUserId,
                matrixUserId: senderId,
              );
      if (localProfile1 != null) {
        final name = _cleanDisplayName(localProfile1.profileName);
        final avatar = localProfile1.avatarUrl?.trim() ?? '';
        if (!mounted) return;
        _setChatState(() {
          if (name.isNotEmpty) _groupMemberNames[senderId] = name;
          if (avatar.isNotEmpty) _groupMemberAvatars[senderId] = avatar;
        });
        return;
      }

      final profile = await UserProfileService.instance.getProfileByUid(
        localpart,
        phone: phoneHint,
        forceRefresh: false,
      );
      final name = _cleanDisplayName(profile?.displayName);
      final avatar = profile?.profileImage.trim() ?? '';
      if (profile != null && ownerUserId.isNotEmpty) {
        await ContactIdentityCache.instance.upsert(
          ownerUserId: ownerUserId,
          matrixUserId: senderId,
          phone: profile.phone,
          profileName: name,
          avatarUrl: avatar,
          bio: profile.bio,
        );
      }
      if (!mounted) return;
      if (name.isEmpty && avatar.isEmpty) return;
      _setChatState(() {
        if (name.isNotEmpty) _groupMemberNames[senderId] = name;
        if (avatar.isNotEmpty) _groupMemberAvatars[senderId] = avatar;
      });
    } catch (_) {
      // Matrix display names are kept as fallback.
    } finally {
      _groupSenderProfilesInFlight.remove(senderId);
    }
  }
}
