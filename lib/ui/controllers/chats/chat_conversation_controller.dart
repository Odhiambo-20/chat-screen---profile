part of '../../screens/chats/chat_screen.dart';

extension _ChatConversationController on _ChatScreenState {
  Future<void> _loadInitialSafely() async {
    try {
      await _loadInitial();
    } catch (error, stackTrace) {
      // A profile lookup, read-marker write, or malformed remote room must not
      // leave an otherwise usable local chat behind an endless skeleton.
      apkLog(
        'ChatScreen._loadInitial',
        'non-fatal startup failure conversation_id="${widget.conversationId}" '
            'error="$error" stack="$stackTrace"',
      );
      if (!mounted) return;
      _setChatState(() {
        _mergeMessages(_initialStreamBuffer);
        _initialStreamBuffer.clear();
        _groupProfilesReady = true;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadInitial() async {
    _matrixAvailable = false;
    _hasMoreOlder = false;
    if (_suppliedRoomMatchesScreenKind) {
      await _hydrateAndSubscribe(widget.conversationId);
    }

    apkLog('ChatScreen._loadInitial', 'calling chat.connect()…');

    try {
      await _chat.connect();
      _matrixAvailable = true;
      _resolvedConversationId = null;
    } catch (e) {
      _matrixAvailable = false;
      apkLog('ChatScreen._loadInitial', ' connect() FAILED: $e');
      if (mounted) {
        _setChatState(() => _loadingInitial = false);
      }
      return; // Matrix unavailable; keep the chat usable with local messages.
    }

    apkLog(
      'ChatScreen._loadInitial',
      'connect() done  isConnected=${_chat.isConnected}',
    ); // use actual flag

    final realConvId = await _resolveConversationId();
    _chat.activateConversationRead(realConvId);
    _pinnedEventIds = _chat.pinnedEventIdsForRoom(realConvId);
    _pinnedForMeEventIds = _isGroupChat
        ? <String>[]
        : _chat.pinnedForMeEventIdsForRoom(realConvId);
    apkLog('ChatScreen._loadInitial', 'realConvId="$realConvId"');
    if (realConvId != widget.conversationId) {
      if (widget.conversationId.startsWith('!')) {
        // A different Matrix room can never be migrated into this one. In
        // particular, never move group history into a newly resolved DM.
        if (!mounted) return;
        _setChatState(() => _messages.clear());
      } else {
        await _migrateLocalConversationToRoom(realConvId, const []);
        if (!mounted) return;
        _setChatState(() => _normaliseMessagesToConversation(realConvId));
      }
    }

    if (realConvId.startsWith('!') && !_isReadOnlySuggestedGroup) {
      final restored = await _chat.loadInitialMessageWindow(realConvId);
      if (!mounted) return;
      _setChatState(() {
        _replaceMessagesFromSharedCache(restored);
      });
      _hasMoreOlder = await _chat.hasMoreOlderMessages(realConvId);
    }

    // Receiver identity is refreshed in the background. The chat must not
    // block its first render on profile/network work.
    unawaited(_loadReceiverProfile());

    if (_isKnownGroupConversationId(realConvId) || _isGroupChat) {
      await _primeGroupMemberProfiles(realConvId);
    }

    await _chat.markConversationAsRead(realConvId);
    await NotificationService.instance.clearConversationNotifications(
      realConvId,
    );
    if (realConvId != widget.conversationId) {
      await NotificationService.instance.clearConversationNotifications(
        widget.conversationId,
      );
    }

    if (!mounted) return;
    _setChatState(() {
      _mergeMessages(_initialStreamBuffer);
      _initialStreamBuffer.clear();
      _groupProfilesReady = true;
      _loadingInitial = false;
    });
    _scheduleOlderHistoryPrefetch();

    await _hydrateAndSubscribe(realConvId);
  }

  bool get _suppliedRoomMatchesScreenKind {
    if (!widget.conversationId.startsWith('!')) return true;
    if (widget.conversationKind != ConversationKind.direct) return true;
    final room = MatrixChatService.instance.getRoomById(widget.conversationId);
    if (room != null) {
      return _chat.isVerifiedDirectConversation(
        widget.conversationId,
        widget.receiverId,
      );
    }
    if (_cachedConversationIsGroup(widget.conversationId)) return false;
    // The screen kind comes from the account-scoped persisted conversation
    // row. A Matrix client may remain "logged in" while the device is offline,
    // even though no live room state is available to verify the DM again.
    // Requiring that transient verification made a cached timeline disappear
    // after closing and reopening the same chat.
    // Once a live Matrix connection is available, however, a missing room is
    // stale and must be resolved again by peer ID. Otherwise an old local room
    // shell can trap this screen on an ID the current account cannot open.
    return !_matrixAvailable;
  }

  Future<List<ChatMessage>> _hydrateAndSubscribe(
    String convId, {
    bool publishHydrated = true,
  }) async {
    final msgs = await _chat.hydrateConversation(convId);
    apkLog(
      'ChatScreen._hydrateAndSubscribe',
      'hydrated ${msgs.length} msgs for "$convId"',
    );
    if (mounted && (msgs.isNotEmpty || _messages.isEmpty)) {
      _publishHydratedMessages(msgs);
      if (publishHydrated &&
          !_loadingInitial &&
          _receiverProfile == null &&
          _receiverIdentity == null) {
        unawaited(_loadReceiverProfile(forceRefresh: false));
      }
    }

    if (_messagesSub != null && _messagesSubscriptionConversationId == convId) {
      return msgs;
    }
    await _messagesSub?.cancel();
    _messagesSubscriptionConversationId = convId;
    _lastRoomStreamFingerprint = null;
    _messagesSub = _chat.messagesStreamFor(convId).listen((messages) {
      if (!mounted) return;
      final fingerprint = _messageSnapshotFingerprint(messages);
      if (_lastRoomStreamFingerprint == fingerprint) return;
      _lastRoomStreamFingerprint = fingerprint;
      apkLog('ChatScreen.roomStream', 'room="$convId" msgs=${messages.length}');
      if (messages.isEmpty &&
          _messages.isNotEmpty &&
          !_chat.isConversationDeleted(convId)) {
        return;
      }
      if (_loadingInitial) {
        _initialStreamBuffer
          ..clear()
          ..addAll(messages);
        return;
      }
      final shouldFollowLatest = _isNearTimelineBottom;
      final oldIds = _messages.map((message) => message.id).toSet();
      final latestKnownMessage = _messages.isEmpty ? null : _messages.last;
      var newIncoming = 0;
      if (!shouldFollowLatest && latestKnownMessage != null) {
        newIncoming = messages
            .where(
              (message) =>
                  !oldIds.contains(message.id) &&
                  !_isMine(message) &&
                  !message.isDeleted &&
                  _compareMessagesByTimeline(message, latestKnownMessage) > 0,
            )
            .length;
      }
      _setChatState(() {
        if (_loadingOlder) {
          _mergeMessages(messages);
        } else {
          _replaceMessagesFromSharedCache(messages);
        }
        if (newIncoming > 0) _pendingNewMessages += newIncoming;
        if (shouldFollowLatest) _pendingNewMessages = 0;
      });
      if (shouldFollowLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
      final currentConv = _resolvedConversationId ?? widget.conversationId;
      if (convId == currentConv && messages.any((m) => !_isMine(m))) {
        unawaited(_chat.markConversationAsRead(convId));
        unawaited(
          NotificationService.instance.clearConversationNotifications(convId),
        );
      }
    });
    return msgs;
  }

  String _messageSnapshotFingerprint(List<ChatMessage> messages) {
    return messages
        .map(
          (message) =>
              '${message.id}:${message.status.name}:${message.isEdited}:'
              '${message.isDeletedForMe}:${message.isDeletedForEveryone}:'
              '${message.isVoiceListened}:'
              '${message.content.hashCode}:${message.attachmentUrl?.hashCode}:'
              '${message.contactName?.hashCode}:${message.contactPhone?.hashCode}:'
              '${message.contactAvatarUrl?.hashCode}:${message.contactUserId?.hashCode}',
        )
        .join('|');
  }

  void _publishHydratedMessages(List<ChatMessage> messages) {
    // During the first boot pass, _loadInitial() publishes one final setState
    // after Matrix connect/profile/read-state work is complete. Once the
    // timeline is visible, every hydration replacement must be inside setState;
    // otherwise the list can keep showing stale cached rows until the stream
    // emits again, which looks like messages loaded out of order.
    if (_loadingInitial) {
      _replaceMessagesFromSharedCache(messages);
      return;
    }

    final shouldFollowLatest = _isNearTimelineBottom;
    _setChatState(() => _replaceMessagesFromSharedCache(messages));
    if (shouldFollowLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  Future<void> _migrateLocalConversationToRoom(
    String roomId,
    List<ChatMessage> roomCached,
  ) async {
    if (roomId == widget.conversationId) return;
    final combined = <ChatMessage>[..._messages, ...roomCached]
      ..sort(_compareMessagesByTimeline);
    final latest = combined.isNotEmpty
        ? combined.last
        : ChatMessage(
            id: 'empty_$roomId',
            conversationId: roomId,
            senderId: '',
            receiverId: widget.receiverId,
            content: '',
            timestamp: DateTime.now(),
            status: MessageStatus.sent,
          );
    final roomConversation =
        ChatConversation.fromMessage(
          latest.copyWith(conversationId: roomId),
          widget.currentUserId,
        ).copyWith(
          otherUserName: widget.title,
          otherUserAvatar: widget.avatarUrl,
          conversationKind: _isGroupChat
              ? ConversationKind.group
              : ConversationKind.direct,
          otherUserId: _isGroupChat ? roomId : null,
          lastMessageType: _isGroupChat ? 'group' : null,
        );

    await ChatLocalDb.instance.migrateConversationId(
      oldConversationId: widget.conversationId,
      roomConversation: roomConversation,
    );
    apkLog(
      'ChatScreen._loadInitial',
      'migrated local conversation "${widget.conversationId}" -> "$roomId"',
    );
  }

  Future<void> _loadReceiverProfile({
    bool publish = true,
    bool forceRefresh = true,
  }) async {
    // A group has no receiver profile. Its identity is the room ID and its
    // avatar may only come from the room's m.room.avatar state event. Looking
    // through message peers here can otherwise select a member as "receiver".
    if (_isGroupChat) return;
    final ownerUserId = await AuthService.instance.getCurrentUserId();
    final profileUid = _profilePeerId();
    if (profileUid == null) return;
    final fallbackPhone = _firstPhoneFrom([profileUid, widget.title]);
    final profileFuture = UserProfileService.instance.getProfileByUid(
      profileUid,
      phone: fallbackPhone,
      forceRefresh: forceRefresh,
    );
    final matrixProfileFuture = _loadMatrixProfile(profileUid);
    var profile = await profileFuture;
    final matrixProfile = await matrixProfileFuture;
    final moduleProfile = matrixProfile?.$3;
    if (profile != null && moduleProfile != null) {
      profile = profile.copyWith(
        bio: moduleProfile.bioValue?.trim().isNotEmpty == true
            ? moduleProfile.bioValue!.trim()
            : profile.bio,
        links: moduleProfile.linkValue?.trim().isNotEmpty == true
            ? [moduleProfile.linkValue!.trim()]
            : profile.links,
        channelAlias: moduleProfile.channelAliasValue?.trim().isNotEmpty == true
            ? moduleProfile.channelAliasValue!.trim()
            : profile.channelAlias,
        groupAlias: moduleProfile.groupAliasValue?.trim().isNotEmpty == true
            ? moduleProfile.groupAliasValue!.trim()
            : profile.groupAlias,
        visibilitySettings: moduleProfile.visibilitySettings.isNotEmpty
            ? moduleProfile.visibilitySettings
            : profile.visibilitySettings,
      );
    }
    final saved = ownerUserId == null || ownerUserId.isEmpty
        ? null
        : await _findSavedContact(
            ownerUserId,
            profileUid,
            phone: fallbackPhone,
          );
    var identity = ownerUserId == null || ownerUserId.isEmpty
        ? null
        : await ContactIdentityCache.instance.findByMatrixId(
            ownerUserId: ownerUserId,
            matrixUserId: profileUid,
          );

    final hasCachedSavedName = _cleanDisplayName(
      identity?.savedName,
    ).isNotEmpty;
    if (ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        saved == null &&
        !hasCachedSavedName) {
      await ContactIdentityCache.instance.clearSavedName(
        ownerUserId: ownerUserId,
        matrixUserId: profileUid,
      );
      identity = await ContactIdentityCache.instance.findByMatrixId(
        ownerUserId: ownerUserId,
        matrixUserId: profileUid,
      );
    }

    if (ownerUserId != null && ownerUserId.isNotEmpty) {
      if (saved != null && profile != null) {
        final nextAvatar = profile.hasProfileImage
            ? profile.profileImage
            : matrixProfile?.$2 ?? widget.avatarUrl;
        if (nextAvatar?.trim().isNotEmpty == true &&
            nextAvatar?.trim() != widget.avatarUrl?.trim()) {
          unawaited(
            AvatarPreloadService.replace(
              oldUrl: widget.avatarUrl,
              newUrl: nextAvatar,
            ),
          );
        }
        final refreshedContact =
            await ContactLocalDb.refreshPublicProfileFields(
              ownerUserId: ownerUserId,
              wrytteUserId: profileUid,
              phone: profile.phone.isNotEmpty ? profile.phone : fallbackPhone,
              avatarUrl: nextAvatar,
              bio: profile.bio,
            );
        if (refreshedContact != null) {
          await ChatService().applySavedContact(refreshedContact);
        }
      }
      await ContactIdentityCache.instance.upsert(
        ownerUserId: ownerUserId,
        matrixUserId: profileUid,
        phone: profile?.phone ?? fallbackPhone,
        profileName: _cleanDisplayName(profile?.displayName).isNotEmpty
            ? profile?.displayName
            : matrixProfile?.$1,
        savedName: saved?.formattedName,
        avatarUrl: profile?.hasProfileImage == true
            ? profile!.profileImage
            : matrixProfile?.$2 ?? widget.avatarUrl,
        bio: profile?.bio,
      );
      identity = await ContactIdentityCache.instance.findByMatrixId(
        ownerUserId: ownerUserId,
        matrixUserId: profileUid,
      );
    }

    final nextAvatar = profile?.hasProfileImage == true
        ? profile!.profileImage
        : identity?.avatarUrl ?? widget.avatarUrl;
    await AvatarPreloadService.warm(
      nextAvatar,
      cacheIdentity: 'user:${profileUid.trim().toLowerCase()}',
    );

    apkLog(
      'Identity.display',
      'surface="conversation_header" phase="resolved" '
          'user_id="${_matrixLocalpart(profileUid)}" saved=${saved != null} '
          'profile="${saved != null ? 'profile2' : 'profile1'}" '
          'name_source="${saved != null ? 'saved_contact' : 'wrytte_id'}" '
          'name="${_resolvedHeaderName}" '
          'phone="${profile?.phone ?? fallbackPhone}" '
          'avatar=${(nextAvatar ?? '').trim().isNotEmpty} avatar_url="${nextAvatar ?? ''}" '
          'bio=${profile?.bio.trim().isNotEmpty == true}',
    );

    if (!mounted) return;
    if (publish) {
      _setChatState(() {
        _receiverProfile = profile;
        _receiverIdentity = identity;
        _receiverIsSavedContact = saved != null;
        _stableHeaderAvatarUrl = _safePersonHeaderAvatar(nextAvatar);
      });
    } else {
      _receiverProfile = profile;
      _receiverIdentity = identity;
      _receiverIsSavedContact = saved != null;
    }
    await _persistResolvedReceiverInfo();
  }

  Future<void> _seedReceiverIdentityFromCache() async {
    if (_isGroupChat || _receiverIdentity != null) return;
    final peerId = _profilePeerId();
    if (peerId == null) return;
    var ownerUserId = widget.currentUserId.trim();
    if (ownerUserId.isEmpty) {
      ownerUserId = await AuthService.instance.getCurrentUserId() ?? '';
    }
    if (ownerUserId.isEmpty || !mounted) return;
    final identity = await ContactIdentityCache.instance.findByMatrixId(
      ownerUserId: ownerUserId,
      matrixUserId: peerId,
    );
    if (identity == null || !mounted || _receiverIdentity != null) return;
    _setChatState(() {
      _receiverIdentity = identity;
      _receiverIsSavedContact = _cleanDisplayName(
        identity.savedName,
      ).isNotEmpty;
    });
  }

  String? _profilePeerId() {
    if (_isGroupChat) return null;
    final room = MatrixChatService.instance.getRoomById(_activeConversationId);
    final directPeer = room?.directChatMatrixID?.trim();

    for (final candidate in [
      _receiverIdentity?.matrixUserId,
      widget.receiverId,
      directPeer,
      ..._messagePeerIdentifiers(),
      ..._roomPeerIdentifiers(),
    ]) {
      final value = candidate?.trim() ?? '';
      if (value.isEmpty) continue;
      if (value.startsWith('!') || value.startsWith('@!')) continue;
      if (_matrixLocalpart(value) == _matrixLocalpart(widget.currentUserId)) {
        continue;
      }
      if (_isValidMatrixUserId(value) || _looksLikeMatrixId(value)) {
        return value;
      }
    }
    return null;
  }

  Future<Contact?> _findSavedContact(
    String ownerUserId,
    String uid, {
    String? phone,
  }) async {
    final targetLocalpart = _matrixLocalpart(uid);
    String normalizedPhone(String? value) {
      final parsed = _phoneFromIdentifier(value);
      if (parsed.isEmpty) return '';
      return _formatPhone(parsed).replaceAll(RegExp(r'[^\d]'), '');
    }

    final targetPhone = normalizedPhone(phone);
    final contacts = await ContactService().getMatrixContactsCached(
      ownerUserId,
    );
    for (final contact in contacts) {
      final contactId = contact.wrytteUserId;
      final sameWrytteId =
          contactId != null &&
          contactId.isNotEmpty &&
          _matrixLocalpart(contactId) == targetLocalpart;
      final samePhone =
          targetPhone.isNotEmpty &&
          contact.phones.map(normalizedPhone).contains(targetPhone);
      if (sameWrytteId || samePhone) return contact;
    }
    return null;
  }

  Future<(String?, String?, WrytteProfile?)?> _loadMatrixProfile(
    String uid,
  ) async {
    try {
      final moduleProfile = await MatrixProfileService.instance.getProfile(uid);
      final moduleName = moduleProfile.displayName?.trim() ?? '';
      if (moduleName.isNotEmpty) {
        return (moduleName, moduleProfile.avatarUrl, moduleProfile);
      }
      if (!MatrixClientService.instance.isLoggedIn) return null;
      final matrixUserId = _toMatrixUserId(uid);
      final profile = await MatrixClientService.instance.client
          .getProfileFromUserId(
            matrixUserId,
            timeout: const Duration(seconds: 5),
          );
      return (profile.displayName, profile.avatarUrl?.toString(), null);
    } catch (_) {
      return null;
    }
  }

  String get _resolvedHeaderName {
    if (_isGroupChat) {
      final room = MatrixChatService.instance.getRoomById(
        _activeConversationId,
      );
      for (final candidate in [room?.name, widget.title]) {
        final groupName = _cleanDisplayName(candidate);
        if (groupName.isNotEmpty && !groupName.startsWith('gr.@')) {
          return groupName;
        }
      }
      return 'Group';
    }

    final savedName = _cleanDisplayName(_receiverIdentity?.savedName);
    if (savedName.isNotEmpty && _phoneFromIdentifier(savedName).isEmpty) {
      return savedName;
    }

    // The chat header intentionally shows the canonical identifier for an
    // unsaved peer. This is not a profile display name; the profile screen
    // keeps the identifier in its dedicated ID/phone row.
    if (!_receiverIsSavedContact) {
      final receiverWrytteId = WrytteId.forDisplay(widget.receiverId);
      if (receiverWrytteId != null) return receiverWrytteId;
      final unsavedPhone = _firstPhoneFrom([
        _receiverIdentity?.phone,
        _receiverProfile?.phone,
        widget.receiverId,
        widget.title,
      ]);
      if (unsavedPhone.isNotEmpty) return _formatPhone(unsavedPhone);
    }

    // A phone number/Wrytte ID is an identifier, never a display name.
    // Signup requires every user to have a real name, so keep the header
    // empty until that name is available rather than showing an identifier.
    for (final candidate in [
      _receiverIdentity?.profileName,
      _receiverProfile?.displayName,
      widget.title,
    ]) {
      final name = _cleanDisplayName(candidate);
      final isWrytteId = RegExp(r'^w\d+$', caseSensitive: false).hasMatch(
        name.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''),
      );
      if (name.isNotEmpty &&
          !isWrytteId &&
          _phoneFromIdentifier(name).isEmpty) {
        return name;
      }
    }
    return '';
  }

  Future<void> _persistResolvedReceiverInfo() async {
    final name = _resolvedHeaderName.trim();
    final avatar = _isGroupChat
        ? _safeGroupRoomAvatarUrl(
            MatrixChatService.instance.getRoomById(_activeConversationId),
          )
        : _receiverProfile?.hasProfileImage == true
        ? _receiverProfile!.profileImage
        : _receiverIdentity?.avatarUrl ?? widget.avatarUrl;
    if (name.isEmpty && (avatar ?? '').trim().isEmpty) return;
    try {
      await ChatLocalDb.instance.updateConversationUserInfo(
        conversationId: _resolvedConversationId ?? widget.conversationId,
        name: name,
        avatar: avatar,
      );
    } catch (e) {
      debugPrint('[ChatScreen] receiver info persist skipped: $e');
    }
  }

  Iterable<String> _messagePeerIdentifiers() sync* {
    for (final message in _messages.reversed) {
      if (_isMine(message)) {
        yield message.receiverId;
      } else {
        yield message.senderId;
      }
    }
  }

  Iterable<String> _roomPeerIdentifiers() sync* {
    final room = MatrixChatService.instance.getRoomById(_activeConversationId);
    if (room == null) return;
    final currentLocalpart = _matrixLocalpart(widget.currentUserId);
    for (final member in room.getParticipants(_groupMemberships)) {
      final id = member.id.trim();
      if (id.isEmpty || id.startsWith('!') || id.startsWith('@!')) continue;
      if (_matrixLocalpart(id) == currentLocalpart) continue;
      yield id;
    }
  }

  String _cleanDisplayName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || _looksLikePhone(trimmed)) return '';
    final lowered = trimmed.toLowerCase();
    if (lowered == 'user' || lowered == 'uder' || lowered == 'unknown') {
      return '';
    }
    if (trimmed.startsWith('@') && trimmed.contains(':')) return '';
    if (trimmed.startsWith('!') && trimmed.contains(':')) return '';
    if (RegExp(r'^[a-f0-9]{24,}$', caseSensitive: false).hasMatch(trimmed)) {
      return '';
    }
    return trimmed;
  }
}
