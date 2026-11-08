part of '../../screens/chats/chat_screen.dart';

extension _ChatMessageCommands on _ChatScreenState {
  Future<void> _send() async {
    final text = _controller.text.trim();
    final editing = _editingMessage;
    apkLog(
      'ChatScreen._send',
      'text="${text.length > 40 ? text.substring(0, 40) : text}"  '
          'isSending=$_isSending  '
          'textEmpty=${text.isEmpty}',
    );

    if ((text.isEmpty && editing == null) || _isSending) return;
    if (_isDeletedConversation) return;
    if (editing != null) {
      await _sendEditedMessage(editing, text);
      return;
    }
    if (_isSelfConversation) {
      _logSelfConversationBlocked('send');
      _showSelfConversationError();
      return;
    }

    _controller.clear();
    final reply = _replyingTo;
    _setChatState(() {
      _isSending = true;
      _replyingTo = null;
      _editingMessage = null;
    });

    final normalisedReceiverId = _normaliseId(widget.receiverId);

    final optimistic = ChatMessage(
      id: 'opt_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: _resolvedConversationId ?? widget.conversationId,
      senderId: widget.currentUserId,
      receiverId: normalisedReceiverId,
      content: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyToMessageId: reply?.id,
      replyToSenderId: _replySenderIdForOutgoingReply(reply),
      replyPreview: reply == null ? null : _replyPreviewForMessage(reply),
    );

    _registerMessagePopAnimation(optimistic.id);
    _setChatState(() => _messages.add(optimistic));
    _optimisticIdByContent['${normalisedReceiverId}_$text'] = optimistic.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());

    if (widget.uiPreviewMode) {
      final localDemoMessage = optimistic.copyWith(status: MessageStatus.read);
      _setChatState(() {
        _replaceOptimisticMessage(optimistic.id, localDemoMessage);
        _isSending = false;
      });
      return;
    }

    final realConvId = await _resolveMatrixConversationIdForSend();

    apkLog(
      'ChatScreen._send',
      'realConvId="$realConvId"  '
          'normalisedReceiver="$normalisedReceiverId"',
    );

    final outbound = optimistic.copyWith(
      conversationId: realConvId ?? optimistic.conversationId,
    );

    if (!_matrixAvailable || realConvId == null) {
      final local = outbound.copyWith(status: MessageStatus.failed);
      await _saveLocalMessage(local);
      if (mounted) {
        _setChatState(() {
          _replaceOptimisticMessage(optimistic.id, local);
        });
      }
      if (mounted) _setChatState(() => _isSending = false);
      return;
    }

    // If the recipient has blocked this account, do not publish a Matrix
    // event. Keep the message locally with one-check status and persist its
    // content in the sender's private blocked-message account data instead.
    final blockedByRecipient =
        BlockStateService.instance.isBlockedByBbb(
          normalisedReceiverId,
          roomId: realConvId,
        );
    if (blockedByRecipient) {
      final blocked = outbound.copyWith(
        id: 'blocked_${DateTime.now().microsecondsSinceEpoch}',
        status: MessageStatus.sent,
      );
      await BlockStateService.instance.recordBlockedMessage(
        roomId: realConvId,
        eventId: blocked.id,
        text: blocked.content,
        time: blocked.timestamp,
      );
      await _saveLocalMessage(blocked);
      if (mounted) {
        _setChatState(() => _replaceOptimisticMessage(optimistic.id, blocked));
      }
      if (mounted) _setChatState(() => _isSending = false);
      return;
    }

    try {
      apkLog('ChatScreen._send', 'calling chat.sendMessage…');
      final sent = await _chat.sendMessage(outbound);
      apkLog('ChatScreen._send', ' sent  id=${sent.id}  status=${sent.status}');

      await _saveCanonicalSentMessage(sent);
      if (mounted) {
        _setChatState(() => _replaceOptimisticMessage(optimistic.id, sent));
      }
    } catch (e) {
      apkLog('ChatScreen._send', ' SEND FAILED: $e');
      final local = outbound.copyWith(status: MessageStatus.failed);
      await _saveLocalMessage(local);
      if (mounted) {
        _setChatState(() {
          final idx = _messages.indexWhere((m) => m.id == optimistic.id);
          if (idx != -1) {
            _messages[idx] = local;
          }
        });
      }
    } finally {
      if (mounted) _setChatState(() => _isSending = false);
    }
  }

  Future<void> _sendEditedMessage(ChatMessage message, String text) async {
    final isMediaEdit = _canEditMediaMessage(message);
    final originalText = isMediaEdit
        ? _editableMediaCaption(message)
        : message.content.trim();
    if (text.trim() == originalText) {
      _controller.clear();
      _setChatState(() => _editingMessage = null);
      return;
    }
    if (_isSending) return;

    _controller.clear();
    _setChatState(() {
      _isSending = true;
      _editingMessage = null;
    });

    final effectiveContent = isMediaEdit && text.trim().isEmpty
        ? _attachmentLabelForType(_effectiveAttachmentType(message)!)
        : text.trim();
    final optimistic = message.copyWith(
      content: effectiveContent,
      status: MessageStatus.sending,
      isEdited: true,
    );
    _setChatState(() => _replaceOptimisticMessage(message.id, optimistic));

    if (widget.uiPreviewMode) {
      _setChatState(() {
        _replaceOptimisticMessage(
          message.id,
          optimistic.copyWith(status: MessageStatus.read),
        );
        _isSending = false;
      });
      return;
    }

    try {
      final ChatMessage updated;
      if (isMediaEdit) {
        updated = await _chat.editMediaCaption(message: message, caption: text);
      } else {
        updated = await _chat.editMessage(message: message, newContent: text);
      }
      if (mounted) {
        _setChatState(() => _replaceOptimisticMessage(message.id, updated));
      }
    } catch (e) {
      apkLog('ChatScreen._sendEditedMessage', 'EDIT FAILED: $e');
      if (mounted) {
        _setChatState(() => _replaceOptimisticMessage(message.id, message));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Edit failed: $e')));
      }
    } finally {
      if (mounted) _setChatState(() => _isSending = false);
    }
  }

  // ─── SEND VOICE ────────────────────────────────────────────────────────────

  Future<void> _saveLocalMessage(ChatMessage message) async {
    await ChatLocalDb.instance.saveMessage(message);
    await ChatLocalDb.instance.saveConversations([
      ChatConversation.fromMessage(message, widget.currentUserId).copyWith(
        otherUserName: widget.title,
        otherUserAvatar: _isGroupChat ? null : widget.avatarUrl,
        conversationKind: _isGroupChat
            ? ConversationKind.group
            : ConversationKind.direct,
        otherUserId: _isGroupChat ? message.conversationId : null,
        lastMessageType: _isGroupChat ? 'group' : null,
      ),
    ]);
  }

  Future<void> _saveCanonicalSentMessage(ChatMessage message) async {
    await ChatLocalDb.instance.deleteDuplicateOutgoingEchoesFor(message);
    await _saveLocalMessage(message);
  }

  Future<void> _sendVoiceNote(String filePath, int durationSeconds) async {
    if (_isSelfConversation) {
      _logSelfConversationBlocked('send voice note');
      _showSelfConversationError();
      return;
    }
    if (_isDeletedConversation) return;

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    final realConvId = await _resolveMatrixConversationIdForSend();
    apkLog(
      'ChatScreen._sendVoice',
      'duration=${durationSeconds}s  receiver="$normalisedReceiverId"',
    );

    if (realConvId == null) {
      apkLog('ChatScreen._sendVoice', 'Matrix room unavailable');
      return;
    }
    if (!mounted || _disposing) return;

    final placeholderId = 'voice_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = ChatMessage(
      id: placeholderId,
      conversationId: realConvId,
      senderId: widget.currentUserId,
      receiverId: normalisedReceiverId,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      attachmentUrl: filePath,
      attachmentType: 'voice',
      voiceDuration: durationSeconds,
    );

    _registerMessagePopAnimation(placeholder.id);
    _setChatState(() => _upsertMessage(placeholder));
    _optimisticIdByContent['${normalisedReceiverId}_${placeholder.content}_$filePath'] =
        placeholder.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());

    try {
      await _chat.sendVoiceMessage(
        receiverID: normalisedReceiverId,
        filePath: filePath,
        durationSeconds: durationSeconds,
        conversationId: realConvId,
      );
      if (mounted) {
        _setChatState(
          () => _messages.removeWhere((m) => m.id == placeholderId),
        );
        _discardMessagePopAnimation(placeholderId);
      }
    } catch (e) {
      apkLog('ChatScreen._sendVoice', ' ERROR: $e');
      if (mounted) {
        _setChatState(
          () => _messages.removeWhere((m) => m.id == placeholderId),
        );
        _discardMessagePopAnimation(placeholderId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice note: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _recordAndSendVideoMessage() async {
    if (_isDeletedConversation) return;
    final result = await Navigator.of(context).push<VideoMessageResult>(
      MaterialPageRoute(
        builder: (_) => const VideoMessageRecorderScreen(
          maxDuration: Duration(seconds: 60),
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _sendVideoNote(result.filePath, result.durationSeconds);
  }

  Future<void> _sendVideoNote(String filePath, int durationSeconds) async {
    if (_isSelfConversation) {
      _logSelfConversationBlocked('send video note');
      _showSelfConversationError();
      return;
    }
    if (_isDeletedConversation) return;

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    final realConvId = await _resolveMatrixConversationIdForSend();
    apkLog(
      'ChatScreen._sendVideo',
      'duration=${durationSeconds}s  receiver="$normalisedReceiverId"',
    );

    if (realConvId == null) {
      apkLog('ChatScreen._sendVideo', 'Matrix room unavailable');
      return;
    }

    final sourceFile = File(filePath);
    if (!await sourceFile.exists() || await sourceFile.length() <= 0) {
      apkLog('ChatScreen._sendVideo', 'source unavailable path="$filePath"');
      return;
    }

    final persistentCopy = await AttachmentLocalStore.instance.ensureComplete(
      source: filePath,
      fileName: p.basename(filePath).trim().isEmpty
          ? 'video-message.mp4'
          : p.basename(filePath),
    );
    final localVideoPath =
        persistentCopy.isComplete && await persistentCopy.file.exists()
        ? persistentCopy.file.path
        : filePath;
    final localVideoBytes = await File(localVideoPath).exists()
        ? await File(localVideoPath).length()
        : 0;
    apkLog(
      'ChatScreen._sendVideo',
      'local_source="$localVideoPath" bytes=$localVideoBytes',
    );

    final placeholderId = 'video_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = ChatMessage(
      id: placeholderId,
      conversationId: realConvId,
      senderId: widget.currentUserId,
      receiverId: normalisedReceiverId,
      content: chatVideoMessageContent,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      attachmentUrl: localVideoPath,
      attachmentType: chatAttachmentTypeVideoMessage,
      voiceDuration: durationSeconds,
    );

    _registerMessagePopAnimation(placeholder.id);
    _setChatState(() => _upsertMessage(placeholder));
    _optimisticIdByContent['${normalisedReceiverId}_${placeholder.content}_$filePath'] =
        placeholder.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());

    try {
      final sent = await _chat.sendVideoMessage(
        receiverID: normalisedReceiverId,
        filePath: filePath,
        durationSeconds: durationSeconds,
        conversationId: realConvId,
      );
      if (mounted) {
        _setChatState(() => _replaceOptimisticMessage(placeholderId, sent));
      }
    } catch (e) {
      apkLog('ChatScreen._sendVideo', ' ERROR: $e');
      if (mounted) {
        _setChatState(
          () => _messages.removeWhere((m) => m.id == placeholderId),
        );
        _discardMessagePopAnimation(placeholderId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send video message: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickCameraAttachment() async {
    if (_isDeletedConversation) return;
    final cameraGranted = await AppPermissionService.instance
        .ensureCameraGranted();
    if (!mounted || !cameraGranted) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (!mounted || picked == null) return;
    await _sendPickedAttachment(picked.path, 'image');
  }

  Future<void> _pickGalleryAttachment() async {
    if (_isDeletedConversation) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WrytteColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _messageActionTile(
              icon: Icons.image_outlined,
              label: 'Photo',
              onTap: () => Navigator.pop(context, 'image'),
            ),
            _messageActionTile(
              icon: Icons.videocam_outlined,
              label: 'Video',
              onTap: () => Navigator.pop(context, 'video'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    final picker = ImagePicker();
    final picked = choice == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (!mounted || picked == null) return;
    await _sendPickedAttachment(picked.path, choice);
  }

  Future<void> _pickFileAttachment() async {
    if (_isDeletedConversation) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result.isEmpty) return;

      final pickedFile = result.single;
      final path = pickedFile.path?.trim() ?? '';
      if (path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access the selected file'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      final audioMetadata = await readAudioFileMetadata(
        filePath: path,
        fallbackFileName: pickedFile.name,
      );
      await _sendPickedAttachment(
        path,
        'file',
        audioTitle: audioMetadata?.title,
        audioArtist: audioMetadata?.artist,
        audioArtworkPath: audioMetadata?.artworkPath,
        audioDurationSeconds: audioMetadata?.durationSeconds,
      );
    } catch (error) {
      apkLog('ChatScreen._pickFileAttachment', 'ERROR: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select file: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _sendPickedAttachment(
    String filePath,
    String type, {
    String? caption,
    String? mediaGroupId,
    int? mediaGroupIndex,
    int? mediaGroupCount,
    int? mediaWidth,
    int? mediaHeight,
    String? audioTitle,
    String? audioArtist,
    String? audioArtworkPath,
    int? audioDurationSeconds,
  }) async {
    if (type.trim().toLowerCase() == chatAttachmentTypeVideoMessage) {
      await _sendVideoNote(filePath, audioDurationSeconds ?? 1);
      return;
    }
    if (_isSelfConversation) {
      _logSelfConversationBlocked('send attachment');
      _showSelfConversationError();
      return;
    }
    if (_isDeletedConversation) return;
    if (!await File(filePath).exists()) return;

    AudioFileMetadata? extractedAudioMetadata;
    if (type == 'file' && isAudioMetadataFile(filePath)) {
      extractedAudioMetadata = await readAudioFileMetadata(
        filePath: filePath,
        fallbackFileName: p.basename(filePath),
      );
    }
    final resolvedAudioTitle = audioTitle?.trim().isNotEmpty == true
        ? audioTitle!.trim()
        : extractedAudioMetadata?.title;
    final resolvedAudioArtist = audioArtist?.trim().isNotEmpty == true
        ? audioArtist!.trim()
        : extractedAudioMetadata?.artist;
    final resolvedAudioArtworkPath = audioArtworkPath?.trim().isNotEmpty == true
        ? audioArtworkPath!.trim()
        : extractedAudioMetadata?.artworkPath;
    final resolvedAudioDurationSeconds =
        audioDurationSeconds != null && audioDurationSeconds > 0
        ? audioDurationSeconds
        : extractedAudioMetadata?.durationSeconds;

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    final realConvId = await _resolveMatrixConversationIdForSend();
    if (realConvId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send attachment: room unavailable'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      await _chat.validateAttachmentUpload(
        filePath: filePath,
        attachmentType: type,
      );
      await _chat.removeFailedAttachmentAttempts(
        conversationId: realConvId,
        filePath: filePath,
      );
    } catch (e) {
      await _chat.removeFailedAttachmentAttempts(
        conversationId: realConvId,
        filePath: filePath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot send attachment: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final placeholderId =
        'attach_${DateTime.now().microsecondsSinceEpoch}_${mediaGroupIndex ?? 0}';
    final attachmentSize = await File(filePath).length();
    final placeholder = ChatMessage(
      id: placeholderId,
      conversationId: realConvId,
      senderId: widget.currentUserId,
      receiverId: normalisedReceiverId,
      content: caption?.trim().isNotEmpty == true
          ? caption!.trim()
          : type == 'file'
          ? p.basename(filePath)
          : _attachmentLabelForType(type),
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      attachmentUrl: filePath,
      attachmentFileName: p.basename(filePath),
      attachmentType: type,
      attachmentSize: attachmentSize,
      audioTitle: resolvedAudioTitle,
      audioArtist: resolvedAudioArtist,
      audioArtworkUrl: resolvedAudioArtworkPath,
      voiceDuration: resolvedAudioDurationSeconds,
      mediaGroupId: mediaGroupId,
      mediaGroupIndex: mediaGroupIndex,
      mediaGroupCount: mediaGroupCount,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
    );

    _registerMessagePopAnimation(placeholder.id);
    _setChatState(() => _messages.add(placeholder));
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());

    try {
      final sent = await _chat.sendAttachmentMessage(
        receiverID: normalisedReceiverId,
        filePath: filePath,
        attachmentType: type,
        conversationId: realConvId,
        caption: caption,
        mediaGroupId: mediaGroupId,
        mediaGroupIndex: mediaGroupIndex,
        mediaGroupCount: mediaGroupCount,
        mediaWidth: mediaWidth,
        mediaHeight: mediaHeight,
        audioTitle: resolvedAudioTitle,
        audioArtist: resolvedAudioArtist,
        audioArtworkPath: resolvedAudioArtworkPath,
        audioDurationSeconds: resolvedAudioDurationSeconds,
      );
      if (_cancelledAttachmentPlaceholderIds.remove(placeholderId)) {
        try {
          await _chat.deleteMessageForEveryone(sent);
        } catch (error) {
          apkLog(
            'ChatScreen._cancelAttachmentUpload',
            'late upload retraction failed: $error',
          );
        }
        try {
          await _chat.cancelLocalMessage(sent);
        } catch (error) {
          apkLog(
            'ChatScreen._cancelAttachmentUpload',
            'local cleanup failed: $error',
          );
        }
        return;
      }
      await _saveCanonicalSentMessage(sent);
      if (mounted) {
        _setChatState(() => _replaceOptimisticMessage(placeholderId, sent));
      }
    } catch (e) {
      final wasCancelled = _cancelledAttachmentPlaceholderIds.remove(
        placeholderId,
      );
      apkLog('ChatScreen._sendAttachment', 'ERROR: $e');
      if (mounted) {
        _setChatState(() {
          _messages.removeWhere((message) => message.id == placeholderId);
          _optimisticIdByContent.removeWhere((_, id) => id == placeholderId);
        });
        _discardMessagePopAnimation(placeholderId);
        if (!wasCancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send attachment: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  void _cancelOutgoingAttachment(String placeholderId) {
    if (!_cancelledAttachmentPlaceholderIds.add(placeholderId)) return;
    HapticFeedback.selectionClick();
    if (!mounted) return;
    _setChatState(() {
      _messages.removeWhere((message) => message.id == placeholderId);
      _optimisticIdByContent.removeWhere((_, id) => id == placeholderId);
    });
    _discardMessagePopAnimation(placeholderId);
  }

  // ─── CALL ──────────────────────────────────────────────────────────────────

  Future<void> _sendPickedAttachments(
    List<ChatPickedAttachment> media, {
    String? caption,
  }) async {
    final attachments = media.toList(growable: false);
    if (attachments.isEmpty) return;

    const albumLimit = 10;
    for (
      var batchStart = 0;
      batchStart < attachments.length;
      batchStart += albumLimit
    ) {
      final batchEnd = math.min(batchStart + albumLimit, attachments.length);
      final batch = attachments.sublist(batchStart, batchEnd);
      final hasAlbum = batch.length > 1;
      final mediaGroupId = hasAlbum
          ? 'album_${DateTime.now().microsecondsSinceEpoch}_${widget.currentUserId.hashCode}_${batchStart ~/ albumLimit}'
          : null;
      await Future.wait([
        for (var index = 0; index < batch.length; index++)
          _sendPickedAttachment(
            batch[index].filePath,
            batch[index].attachmentType,
            caption: batchStart == 0 && index == 0 ? caption : null,
            mediaGroupId: mediaGroupId,
            mediaGroupIndex: hasAlbum ? index : null,
            mediaGroupCount: hasAlbum ? batch.length : null,
            mediaWidth: batch[index].width,
            mediaHeight: batch[index].height,
            audioTitle: batch[index].audioTitle,
            audioArtist: batch[index].audioArtist,
            audioArtworkPath: batch[index].audioArtworkPath,
            audioDurationSeconds: batch[index].audioDurationSeconds,
          ),
      ]);
    }
  }

  Future<void> _sendPickedContacts(
    List<Contact> contacts, {
    String? caption,
  }) async {
    final selectedContacts = contacts.toList(growable: false);
    if (selectedContacts.isEmpty || _isSending) return;
    if (_isSelfConversation) {
      _logSelfConversationBlocked('send contact');
      _showSelfConversationError();
      return;
    }
    if (_isDeletedConversation) return;

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    final realConvId = await _resolveMatrixConversationIdForSend();
    if (realConvId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send contact: room unavailable'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final reply = _replyingTo;
    if (mounted) {
      _setChatState(() {
        _isSending = true;
        _replyingTo = null;
        _editingMessage = null;
      });
    }

    var failedCount = 0;
    try {
      var directoryMatches = <String, WrytteContactResolution>{};
      try {
        directoryMatches = await ContactDirectoryService.instance.resolvePhones(
          selectedContacts.map((contact) => contact.primaryPhone),
        );
      } catch (error) {
        apkLog(
          'ChatScreen.contact',
          'pre-send directory resolution failed error="$error"',
        );
      }

      for (var index = 0; index < selectedContacts.length; index++) {
        final contact = selectedContacts[index];
        final name = _cleanDisplayName(contact.formattedName).isNotEmpty
            ? _cleanDisplayName(contact.formattedName)
            : 'Contact';
        final rawPhone = contact.primaryPhone.trim();
        final formattedPhone = _firstPhoneFrom([rawPhone]);
        final phone = formattedPhone.isNotEmpty ? formattedPhone : rawPhone;
        final localContact = _SharedContactData(
          name: name,
          phone: phone,
          avatarUrl: contact.avatarUrl?.trim(),
          userId: contact.wrytteUserId?.trim(),
        );
        final resolvedContact = await _enrichSharedContactData(
          _mergeDirectoryContact(
            localContact,
            _directoryContactForPhone(directoryMatches, phone),
          ),
        );
        final avatarUrl = resolvedContact.avatarUrl?.trim();
        final contactUserId = resolvedContact.userId?.trim();
        final resolvedPhone = resolvedContact.phone.trim();
        final body = resolvedPhone.isEmpty
            ? resolvedContact.name
            : '${resolvedContact.name}\n$resolvedPhone';
        final placeholderId =
            'contact_${DateTime.now().microsecondsSinceEpoch}_$index';
        final placeholder = ChatMessage(
          id: placeholderId,
          conversationId: realConvId,
          senderId: widget.currentUserId,
          receiverId: normalisedReceiverId,
          content: body,
          timestamp: DateTime.now(),
          status: MessageStatus.sending,
          attachmentType: 'contact',
          contactName: resolvedContact.name,
          contactPhone: resolvedPhone.isEmpty ? null : resolvedPhone,
          contactAvatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
          contactUserId: contactUserId?.isNotEmpty == true
              ? contactUserId
              : null,
          replyToMessageId: index == 0 ? reply?.id : null,
          replyToSenderId: index == 0
              ? _replySenderIdForOutgoingReply(reply)
              : null,
          replyPreview: index == 0 && reply != null
              ? _replyPreviewForMessage(reply)
              : null,
        );

        if (mounted) {
          _registerMessagePopAnimation(placeholder.id);
          _setChatState(() => _messages.add(placeholder));
          _optimisticIdByContent['${normalisedReceiverId}_contact_${placeholder.timestamp.microsecondsSinceEpoch}_$index'] =
              placeholder.id;
          WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
        }

        try {
          final sent = await _chat.sendMessage(placeholder);
          await _saveCanonicalSentMessage(sent);
          if (mounted) {
            _setChatState(
              () => _replaceOptimisticMessage(placeholder.id, sent),
            );
          }
        } catch (error) {
          failedCount += 1;
          apkLog(
            'ChatScreen.contact',
            'send failed name="$name" error="$error"',
          );
          final failed = placeholder.copyWith(status: MessageStatus.failed);
          await _saveLocalMessage(failed);
          if (mounted) {
            _setChatState(
              () => _replaceOptimisticMessage(placeholder.id, failed),
            );
          }
        }
      }
    } finally {
      if (mounted) _setChatState(() => _isSending = false);
    }

    if (failedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedCount == 1
                ? 'Failed to send one contact'
                : 'Failed to send $failedCount contacts',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    final captionText = caption?.trim() ?? '';
    if (captionText.isNotEmpty && mounted) {
      _controller.value = TextEditingValue(
        text: captionText,
        selection: TextSelection.collapsed(offset: captionText.length),
      );
      await _send();
    }
  }

  Future<void> _startCall(CallType type) async {
    if (_isSelfConversation) {
      _logSelfConversationBlocked('start call');
      _showSelfConversationError();
      return;
    }

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    final displayName = widget.title;

    try {
      await _call.makeCall(
        receiverId: normalisedReceiverId,
        type: type,
        callerName: widget.currentUserId,
        callerAvatar: '',
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            remoteUserId: normalisedReceiverId,
            remoteUserName: displayName,
            remoteUserAvatar: _receiverProfile?.hasProfileImage == true
                ? _receiverProfile!.profileImage
                : widget.avatarUrl,
            type: type,
            isCaller: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start call: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
