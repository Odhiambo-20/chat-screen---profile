part of '../../screens/chats/chat_screen.dart';

extension _ChatForwardingController on _ChatScreenState {
  Future<void> _promptForward(ChatMessage message) async {
    await _promptForwardMessages([message]);
  }

  Future<bool> _promptForwardMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) return false;
    final targets = widget.uiPreviewMode
        ? const <_ForwardTarget>[
            _ForwardTarget(
              conversationId: 'ui-preview-saved-messages',
              receiverId: 'ui-preview-self',
              title: 'Saved messages',
              subtitle: 'Demo destination',
            ),
            _ForwardTarget(
              conversationId: 'ui-preview-design-review',
              receiverId: 'ui-preview-design-team',
              title: 'Design review',
              subtitle: 'Demo conversation',
            ),
          ]
        : await _buildForwardTargets();
    if (!mounted) return false;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts or recent chats found')),
      );
      return false;
    }

    final selectedTargets = await showWrytteChatForwardSheet(
      context,
      previewText: messages.length == 1
          ? _replyPreviewForMessage(messages.single) ?? 'Message'
          : '${messages.length} messages',
      targets: [
        for (final target in targets)
          ChatForwardTarget(
            id: target.receiverId,
            title: target.title,
            subtitle: target.subtitle ?? '',
            receiverId: target.receiverId,
            conversationId: target.conversationId,
            avatarUrl: target.avatarUrl,
            isSavedContact: target.isSavedContact,
          ),
      ],
    );
    if (selectedTargets == null || selectedTargets.isEmpty) return false;

    if (widget.uiPreviewMode) {
      _showCopyToast(
        messages.length == 1
            ? 'Demo: message forwarded'
            : 'Demo: ${messages.length} messages forwarded',
      );
      return true;
    }

    var sent = 0;
    final expectedSends = selectedTargets.length * messages.length;
    for (final target in selectedTargets) {
      for (final message in messages) {
        try {
          await _chat.forwardMessage(
            original: message,
            receiverId: target.receiverId ?? target.id,
            conversationId: target.conversationId,
          );
          sent++;
        } catch (e) {
          apkLog(
            'ChatScreen.forward',
            'forward FAILED target="${target.receiverId}" error="$e"',
          );
        }
      }
    }

    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent == expectedSends
              ? messages.length == 1
                    ? 'Message forwarded'
                    : '${messages.length} messages forwarded'
              : 'Forwarded $sent of $expectedSends messages',
        ),
        backgroundColor: sent == expectedSends ? null : Colors.redAccent,
      ),
    );
    return true;
  }

  Future<List<_ForwardTarget>> _buildForwardTargets() async {
    final sourceRoom = MatrixChatService.instance.getRoomById(
      _activeConversationId,
    );
    final restrictOwnerGroupTargets =
        _isGroupChat &&
        sourceRoom != null &&
        MatrixChatService.instance.isMatrixGroupRoom(sourceRoom) &&
        MatrixChatService.instance.isGroupOwner(sourceRoom);
    final ownerUserId =
        (await AuthService.instance.getCurrentUserId())?.trim() ??
        widget.currentUserId.trim();
    final identities = ownerUserId.isEmpty
        ? <String, ContactIdentity>{}
        : await ContactIdentityCache.instance.loadAll(ownerUserId: ownerUserId);
    final byKey = <String, _ForwardTarget>{};
    final canonicalKeyByAlias = <String, String>{};
    var order = 0;

    void addTarget(_ForwardTarget target) {
      if (target.receiverId.trim().isEmpty) return;
      if (_isOwnMatrixId(target.receiverId)) return;
      final aliases = _forwardTargetAliases(target.receiverId, target.phone);
      if (aliases.isEmpty) return;
      String? matchedKey;
      for (final alias in aliases) {
        matchedKey ??= canonicalKeyByAlias[alias];
      }
      final key = matchedKey ?? aliases.first;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = target.copyWith(sortOrder: order++);
        for (final alias in aliases) {
          canonicalKeyByAlias[alias] = key;
        }
        return;
      }
      if (existing.conversationId == null && target.conversationId != null) {
        byKey[key] = existing.copyWith(
          conversationId: target.conversationId,
          receiverId: target.receiverId,
          subtitle: existing.subtitle?.trim().isNotEmpty == true
              ? existing.subtitle
              : target.subtitle,
          avatarUrl: existing.avatarUrl?.trim().isNotEmpty == true
              ? existing.avatarUrl
              : target.avatarUrl,
        );
      }
      if (!existing.isSavedContact && target.isSavedContact) {
        byKey[key] = target.copyWith(
          conversationId: existing.conversationId ?? target.conversationId,
          receiverId: existing.conversationId != null
              ? existing.receiverId
              : target.receiverId,
          subtitle: existing.subtitle?.trim().isNotEmpty == true
              ? existing.subtitle
              : target.subtitle,
          avatarUrl: target.avatarUrl?.trim().isNotEmpty == true
              ? target.avatarUrl
              : existing.avatarUrl,
          sortOrder: existing.sortOrder,
        );
      }
      for (final alias in aliases) {
        canonicalKeyByAlias[alias] = key;
      }
    }

    if (ownerUserId.isNotEmpty) {
      final contacts = await ContactLocalDb.loadSavedContacts(
        ownerUserId: ownerUserId,
      );
      for (final contact in contacts) {
        final receiverId = contact.wrytteUserId?.trim().isNotEmpty == true
            ? contact.wrytteUserId!.trim()
            : contact.primaryPhone.trim();
        final name = _cleanDisplayName(contact.displayName);
        final phone = _firstPhoneFrom(contact.phones);
        addTarget(
          _ForwardTarget(
            receiverId: receiverId,
            title: name.isNotEmpty
                ? name
                : phone.isNotEmpty
                ? phone
                : receiverId,
            subtitle: phone,
            avatarUrl: contact.avatarUrl,
            phone: phone,
            isSavedContact: true,
          ),
        );
      }
    }

    for (final conversation in _chat.cachedConversationsSnapshot) {
      if (conversation.isGroupKind || conversation.isChannelKind) continue;
      final receiverId = conversation.otherUserId.trim();
      if (receiverId.isEmpty || receiverId.startsWith('!')) continue;
      if (restrictOwnerGroupTargets) {
        final history = await _chat.loadCachedMessages(conversation.id);
        final hasIncomingMessage = history.any(
          (message) =>
              !message.isDeleted &&
              message.senderId.trim().isNotEmpty &&
              !_isOwnMatrixId(message.senderId),
        );
        if (!hasIncomingMessage) continue;
      }
      final identity = identities[_matrixLocalpart(receiverId).toLowerCase()];
      var phone = _firstPhoneFrom([
        identity?.phone ?? '',
        conversation.otherUserName,
        conversation.otherUserId,
        conversation.lastMessageSenderId,
        ...conversation.participants,
      ]);
      if (phone.isEmpty) {
        phone = _phoneFromMatrixLocalpart(receiverId);
      }
      final name = _cleanDisplayName(
        identity?.savedName ??
            identity?.profileName ??
            conversation.otherUserName,
      );
      addTarget(
        _ForwardTarget(
          conversationId: conversation.id,
          receiverId: receiverId,
          title: name.isNotEmpty
              ? name
              : phone.isNotEmpty
              ? phone
              : _matrixLocalpart(receiverId),
          subtitle: '',
          avatarUrl: identity?.avatarUrl ?? conversation.otherUserAvatar,
          phone: phone,
          isSavedContact: false,
        ),
      );
    }

    final targets = byKey.values.toList()
      ..sort((a, b) {
        if (a.isSavedContact != b.isSavedContact) {
          return a.isSavedContact ? -1 : 1;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
    return targets;
  }

  List<String> _forwardTargetAliases(String receiverId, String? phone) {
    final aliases = <String>[];
    var normalizedPhone = _firstPhoneFrom([phone, receiverId]);
    if (normalizedPhone.isEmpty) {
      normalizedPhone = _phoneFromMatrixLocalpart(receiverId);
    }
    final phoneKey = _forwardPhoneKey(normalizedPhone);
    if (phoneKey.isNotEmpty) aliases.add('ph:$phoneKey');
    final localpart = _matrixLocalpart(receiverId).trim().toLowerCase();
    if (localpart.isNotEmpty &&
        !localpart.startsWith('!') &&
        !localpart.contains(' ')) {
      aliases.add('mx:$localpart');
    }
    return aliases;
  }

  String _phoneFromMatrixLocalpart(String value) {
    final localpart = _matrixLocalpart(value).trim();
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(localpart)) return '';
    return _formatPhone(localpart);
  }

  String _forwardPhoneKey(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 7 && digits.length <= 15 ? digits : '';
  }
}
