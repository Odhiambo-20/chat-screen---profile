part of '../../screens/chats/chat_screen.dart';

extension _ChatMessageStore on _ChatScreenState {
  void _registerMessagePopAnimation(String messageId) {
    _messagePopAnimationRowIds[messageId] = messageId;
    _pendingMessagePopAnimationIds.add(messageId);
  }

  void _discardMessagePopAnimation(String messageId) {
    _messagePopAnimationRowIds.remove(messageId);
    _pendingMessagePopAnimationIds.remove(messageId);
  }

  int _compareMessagesByTimeline(ChatMessage a, ChatMessage b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    if (byTime != 0) return byTime;

    final aGroup = a.mediaGroupId?.trim() ?? '';
    final bGroup = b.mediaGroupId?.trim() ?? '';
    if (aGroup.isNotEmpty && aGroup == bGroup) {
      final aIndex = a.mediaGroupIndex;
      final bIndex = b.mediaGroupIndex;
      if (aIndex != null && bIndex != null && aIndex != bIndex) {
        return aIndex.compareTo(bIndex);
      }
    }

    final byConversation = a.conversationId.compareTo(b.conversationId);
    if (byConversation != 0) return byConversation;

    // Matrix/cache streams can occasionally contain messages with identical
    // timestamps. Dart's List.sort is not stable, so using the id as a final
    // tie-breaker keeps reloads deterministic instead of letting equal-time
    // rows randomly swap places between cache hydration and live stream.
    return a.id.compareTo(b.id);
  }

  void _mergeMessages(List<ChatMessage> incoming) {
    for (final msg in incoming) {
      _upsertMessage(msg);
    }
    _removeDuplicateOutgoingEchoes();
    _messages.sort(_compareMessagesByTimeline);
    _resolveGroupMessageSenders(incoming);
  }

  void _replaceMessagesFromSharedCache(List<ChatMessage> incoming) {
    final optimistic = _messages.where(_isLocalOutgoingEcho).toList();
    _messages
      ..clear()
      ..addAll(incoming)
      ..addAll(
        optimistic.where(
          (candidate) =>
              !incoming.any((m) => _isDuplicateOutgoingEcho(candidate, m)),
        ),
      );
    _removeDuplicateOutgoingEchoes();
    _messages.sort(_compareMessagesByTimeline);
    _resolveGroupMessageSenders(incoming);
  }

  void _resolveGroupMessageSenders(Iterable<ChatMessage> messages) {
    if (!_isGroupChat) return;
    final senders = <String, ChatMessage>{};
    for (final message in messages) {
      final senderId = message.senderId.trim();
      if (senderId.isEmpty || senderId.startsWith('!') || _isMine(message)) {
        continue;
      }
      senders.putIfAbsent(senderId, () => message);
      final localpart = _matrixLocalpart(senderId);
      final savedName = _cleanDisplayName(_groupMemberNames[localpart]);
      final savedAvatar = _groupMemberAvatars[localpart]?.trim() ?? '';
      if (savedName.isNotEmpty) _groupMemberNames[senderId] = savedName;
      if (savedAvatar.isNotEmpty) _groupMemberAvatars[senderId] = savedAvatar;
      final eventName = _cleanDisplayName(message.senderName);
      if (eventName.isNotEmpty && !_groupMemberNames.containsKey(senderId)) {
        _groupMemberNames[senderId] = eventName;
      }
    }
    if (_loadingInitial || !_groupProfilesReady) return;
    for (final entry in senders.entries) {
      unawaited(
        _loadGroupMemberProfileName(
          entry.key,
          phoneHint: entry.value.senderPhone,
        ),
      );
    }
  }

  void _seedGroupProfile2FromMemory() {
    if (!_isGroupChat) return;
    final contacts = ContactService.matrixContactsSnapshot(
      widget.currentUserId,
    );
    for (final contact in contacts) {
      final localpart = _matrixLocalpart(contact.wrytteUserId ?? '');
      final name = _cleanDisplayName(contact.formattedName);
      final avatar = contact.avatarUrl?.trim() ?? '';
      if (localpart.isEmpty || name.isEmpty) continue;
      _groupMemberNames[localpart] = name;
      if (avatar.isNotEmpty) _groupMemberAvatars[localpart] = avatar;
    }
  }

  bool _isLocalOutgoingEcho(ChatMessage message) =>
      _isMine(message) && _isLocalOutgoingEchoId(message.id);

  void _normaliseMessagesToConversation(String conversationId) {
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.conversationId != widget.conversationId) continue;
      _messages[i] = message.copyWith(conversationId: conversationId);
    }
  }

  void _upsertMessage(ChatMessage msg) {
    final exactIdx = _messages.indexWhere((m) => m.id == msg.id);
    if (exactIdx != -1) {
      _messages[exactIdx] = msg;
      for (var index = _messages.length - 1; index >= 0; index--) {
        if (index != exactIdx && _messages[index].id == msg.id) {
          _messages.removeAt(index);
        }
      }
      return;
    }
    final optimisticId = _matchingOptimisticId(msg);
    if (optimisticId != null) {
      _replaceOptimisticMessage(optimisticId, msg);
      return;
    }
    final duplicateVideoNoteId = _matchingOutgoingVideoNoteId(msg);
    if (duplicateVideoNoteId != null) {
      _replaceMessageById(duplicateVideoNoteId, msg);
      return;
    }
    _messages.add(msg);
  }

  String? _matchingOutgoingVideoNoteId(ChatMessage msg) {
    if (!_isOutgoingVideoNote(msg)) return null;
    if (msg.status == MessageStatus.sending) return null;
    for (final existing in _messages) {
      if (_isDuplicateOutgoingVideoNote(existing, msg)) return existing.id;
    }
    return null;
  }

  String? _matchingOptimisticId(ChatMessage msg) {
    for (final entry in _optimisticIdByContent.entries) {
      final optimistic = _messages.firstWhere(
        (m) => m.id == entry.value,
        orElse: () => msg,
      );
      if (optimistic.id != entry.value) continue;
      if (optimistic.status != MessageStatus.sending) continue;
      if (!_isMine(optimistic)) continue;
      final sameMediaGroupSlot = _isSameMediaGroupSlot(optimistic, msg);
      final sameContent =
          sameMediaGroupSlot && optimistic.content == msg.content;
      final sameAttachment =
          sameMediaGroupSlot &&
          optimistic.attachmentType?.isNotEmpty == true &&
          optimistic.attachmentType == msg.attachmentType;
      final sameConversation =
          optimistic.conversationId == msg.conversationId ||
          optimistic.conversationId == widget.conversationId ||
          optimistic.conversationId == _resolvedConversationId;
      final sameReceiver =
          optimistic.receiverId == msg.receiverId ||
          optimistic.receiverId == msg.senderId ||
          _matrixLocalpart(optimistic.receiverId) ==
              _matrixLocalpart(msg.receiverId) ||
          _matrixLocalpart(optimistic.receiverId) ==
              _matrixLocalpart(msg.senderId);
      final closeInTime =
          msg.timestamp.difference(optimistic.timestamp).inSeconds.abs() < 60;
      final ownMatrixEcho =
          _isMine(msg) &&
          (sameContent || sameAttachment) &&
          sameConversation &&
          closeInTime;
      if (((sameContent || sameAttachment) && sameReceiver && closeInTime) ||
          ownMatrixEcho) {
        apkLog(
          'ChatScreen.reconcile',
          'replace optimistic id=${optimistic.id} with Matrix id=${msg.id}',
        );
        return optimistic.id;
      }
    }
    return null;
  }

  String _matrixLocalpart(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('@') && trimmed.contains(':')) {
      return trimmed.substring(1, trimmed.indexOf(':'));
    }
    return trimmed;
  }

  String _toMatrixUserId(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('@') && trimmed.contains(':')) return trimmed;
    return '@${_matrixLocalpart(trimmed)}:${MatrixConfig.serverName}';
  }

  void _replaceOptimisticMessage(String optimisticId, ChatMessage sent) {
    _replaceMessageById(optimisticId, sent);
    final rowId = _messagePopAnimationRowIds.remove(optimisticId);
    if (rowId != null) {
      _messagePopAnimationRowIds[sent.id] = rowId;
      if (_pendingMessagePopAnimationIds.remove(optimisticId)) {
        _pendingMessagePopAnimationIds.add(sent.id);
      }
    }
    _optimisticIdByContent.removeWhere((_, id) => id == optimisticId);
  }

  void _replaceMessageById(String existingId, ChatMessage replacement) {
    _messages.removeWhere((m) => m.id == replacement.id && m.id != existingId);
    final idx = _messages.indexWhere((m) => m.id == existingId);
    if (idx != -1) {
      _messages[idx] = replacement;
    } else {
      _messages.add(replacement);
    }
    _messages.removeWhere(
      (m) =>
          _isDuplicateOutgoingEcho(m, replacement) ||
          _isDuplicateOutgoingVideoNote(m, replacement),
    );
    _messages.sort(_compareMessagesByTimeline);
  }

  void _removeDuplicateOutgoingEchoes() {
    final canonicalOutgoing = _messages
        .where((m) => _isMine(m) && !_isLocalOutgoingEchoId(m.id))
        .toList();
    if (canonicalOutgoing.isNotEmpty) {
      _messages.removeWhere(
        (candidate) => canonicalOutgoing.any(
          (sent) =>
              _isDuplicateOutgoingEcho(candidate, sent) ||
              _shouldDropDuplicateOutgoingVideoNote(candidate, sent),
        ),
      );
    }
    _removeDuplicateMessageIds();
  }

  void _removeDuplicateMessageIds() {
    final seen = <String>{};
    for (var index = _messages.length - 1; index >= 0; index--) {
      final id = _messages[index].id.trim();
      if (id.isEmpty) continue;
      if (!seen.add(id)) _messages.removeAt(index);
    }
    // Keep boundary GlobalKeys stable for the lifetime of this ChatScreen.
    // Stream/cache reconciliations can remove and re-add the same event before
    // Flutter has unmounted the previous row. Dropping the key here would then
    // create a second GlobalKey for that event during the same frame and can
    // corrupt the inactive-element bookkeeping (`_elements.contains`). The map
    // is owned by this State and is released with it, so retaining these small
    // key objects is both safe and deterministic.
  }

  bool _isDuplicateOutgoingEcho(ChatMessage candidate, ChatMessage sent) {
    if (candidate.id == sent.id) return false;
    if (!_isMine(candidate) || !_isMine(sent)) return false;
    if (!_isLocalOutgoingEchoId(candidate.id)) return false;
    if (!_isSameMediaGroupSlot(candidate, sent)) return false;
    final sameContent = candidate.content == sent.content;
    final sameAttachment =
        candidate.attachmentType?.isNotEmpty == true &&
        candidate.attachmentType == sent.attachmentType;
    if (!sameContent && !sameAttachment) return false;
    final sameConversation =
        candidate.conversationId == sent.conversationId ||
        candidate.conversationId == widget.conversationId ||
        candidate.conversationId == _resolvedConversationId;
    if (!sameConversation) return false;
    final closeInTime =
        candidate.timestamp.difference(sent.timestamp).inSeconds.abs() < 60;
    return closeInTime;
  }

  bool _isDuplicateOutgoingVideoNote(
    ChatMessage candidate,
    ChatMessage canonical,
  ) {
    if (candidate.id == canonical.id) return false;
    if (!_isOutgoingVideoNote(candidate) || !_isOutgoingVideoNote(canonical)) {
      return false;
    }
    if (!_isSameMediaGroupSlot(candidate, canonical)) return false;
    if (!_isSameOutgoingConversation(candidate, canonical)) return false;

    final candidateUrl = candidate.attachmentUrl?.trim() ?? '';
    final canonicalUrl = canonical.attachmentUrl?.trim() ?? '';
    if (candidateUrl.isNotEmpty &&
        canonicalUrl.isNotEmpty &&
        candidateUrl == canonicalUrl) {
      return true;
    }
    if (candidate.status == MessageStatus.sending ||
        canonical.status == MessageStatus.sending) {
      return false;
    }

    final sameDuration =
        candidate.voiceDuration == null ||
        canonical.voiceDuration == null ||
        (candidate.voiceDuration! - canonical.voiceDuration!).abs() <= 1;
    final sameLabel =
        candidate.content == canonical.content ||
        candidate.content == chatVideoMessageContent ||
        canonical.content == chatVideoMessageContent;
    final closeInTime =
        candidate.timestamp.difference(canonical.timestamp).inSeconds.abs() <
        90;
    return sameDuration && sameLabel && closeInTime;
  }

  bool _shouldDropDuplicateOutgoingVideoNote(
    ChatMessage candidate,
    ChatMessage canonical,
  ) {
    if (!_isDuplicateOutgoingVideoNote(candidate, canonical)) return false;
    final candidateIsMatrixEvent = candidate.id.trim().startsWith(r'$');
    final canonicalIsMatrixEvent = canonical.id.trim().startsWith(r'$');
    if (canonicalIsMatrixEvent != candidateIsMatrixEvent) {
      return canonicalIsMatrixEvent;
    }

    final candidateIsLocal = _isLocalOutgoingEchoId(candidate.id);
    final canonicalIsLocal = _isLocalOutgoingEchoId(canonical.id);
    if (canonicalIsLocal != candidateIsLocal) return !canonicalIsLocal;

    return candidate.timestamp.isBefore(canonical.timestamp);
  }

  bool _isOutgoingVideoNote(ChatMessage message) {
    if (!_isMine(message)) return false;
    return message.isVideoMessage;
  }

  bool _isSameOutgoingConversation(ChatMessage first, ChatMessage second) {
    return first.conversationId == second.conversationId ||
        first.conversationId == widget.conversationId ||
        first.conversationId == _resolvedConversationId ||
        second.conversationId == widget.conversationId ||
        second.conversationId == _resolvedConversationId;
  }

  bool _isSameMediaGroupSlot(ChatMessage first, ChatMessage second) {
    final firstGroupId = first.mediaGroupId?.trim() ?? '';
    final secondGroupId = second.mediaGroupId?.trim() ?? '';
    if (firstGroupId.isEmpty && secondGroupId.isEmpty) return true;
    if (firstGroupId.isEmpty || secondGroupId.isEmpty) return false;
    return firstGroupId == secondGroupId &&
        first.mediaGroupIndex != null &&
        first.mediaGroupIndex == second.mediaGroupIndex;
  }

  bool _isLocalOutgoingEchoId(String id) {
    return id.startsWith('opt_') ||
        id.startsWith('attach_') ||
        id.startsWith('voice_') ||
        id.startsWith('video_') ||
        id.startsWith('Wrytte-');
  }

  GlobalKey _messageBubbleBoundaryKey(String messageId) {
    return _messageBubbleBoundaryKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'message-bubble-$messageId'),
    );
  }
}
