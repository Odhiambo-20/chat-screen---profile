part of '../../../screens/chats/chat_screen.dart';

extension _ChatMessageBuilder on _ChatScreenState {
  Widget _buildGroupAwareMessageBubble({
    required ChatMessage msg,
    List<ChatMessage> albumMessages = const <ChatMessage>[],
    required bool isMine,
    required bool showTail,
    required bool showGroupAvatar,
    required String? effectiveAttachmentType,
    required double ambientProgress,
    required bool joinsPrevious,
    required bool joinsNext,
  }) {
    final displayMessage = albumMessages.length > 1 ? albumMessages.last : msg;
    final senderName = _isGroupChat && !isMine
        ? _groupSenderName(msg.senderId)
        : null;
    final room = MatrixChatService.instance.getRoomById(msg.conversationId);
    final senderIsAdmin =
        _isGroupChat &&
        !isMine &&
        room != null &&
        MatrixChatService.instance.isGroupAdmin(room, msg.senderId);
    final rawDisplayedContent =
        msg.isDeletedForEveryone &&
            !msg.content.toLowerCase().startsWith('this message was deleted')
        ? (isMine
              ? 'This message was deleted'
              : 'This message was deleted by admin')
        : msg.content;
    // Defensively clean legacy SQLite rows written before edited Matrix reply
    // fallbacks (`* > <@user:server> ...`) were handled by the model parser.
    // This also prevents the quoted homeserver from becoming a link preview.
    final displayedContent = _stripMatrixReplyFallbackForDisplay(
      rawDisplayedContent,
    );
    final isOpenedIncomingVoice =
        msg.isVoiceNote &&
        !msg.isDeleted &&
        !isMine &&
        _openedVoiceMessageStateReady &&
        _isVoiceMessageOpened(msg);
    final isUnopenedIncomingVoice =
        msg.isVoiceNote &&
        !msg.isDeleted &&
        !isMine &&
        _openedVoiceMessageStateReady &&
        !_isVoiceMessageOpened(msg);
    final voicePlaybackController = msg.isVoiceNote
        ? _voicePlaybackControllerFor(msg)
        : null;
    final sendAnimationId = isMine ? _messagePopAnimationRowIds[msg.id] : null;
    final shouldStartSendAnimation =
        sendAnimationId != null &&
        _pendingMessagePopAnimationIds.contains(msg.id);
    final sharedContact = effectiveAttachmentType == 'contact' && !msg.isDeleted
        ? _sharedContactData(msg)
        : null;
    if (sharedContact != null &&
        (sharedContact.phone.isNotEmpty ||
            sharedContact.userId?.trim().isNotEmpty == true ||
            (sharedContact.name.trim().isNotEmpty &&
                sharedContact.name.trim().toLowerCase() != 'contact')) &&
        (sharedContact.phone.isEmpty ||
            (sharedContact.userId?.trim().isEmpty ?? true) ||
            (sharedContact.avatarUrl?.trim().isEmpty ?? true))) {
      unawaited(_resolveSharedContactData(msg));
    }
    final isRoundVideoMessage = _isRoundVideoMessageType(
      msg,
      effectiveAttachmentType,
    );
    if (isRoundVideoMessage) {
      unawaited(_repairMissingRoundVideoSource(msg));
    }

    final bubble = MessageBubble(
      content: displayedContent,
      time: _formatTime(displayMessage.timestamp),
      dateLabel: _formatDateDivider(displayMessage.timestamp),
      isMine: isMine,
      senderName: senderName,
      showAdminLabel: senderIsAdmin,
      showTail: showTail,
      status: isMine ? displayMessage.status : null,
      isVoiceNote: msg.isVoiceNote,
      isVoiceListened: msg.isVoiceListened,
      onVoiceListened: !_isGroupChat && !isMine
          ? () => unawaited(_chat.markVoiceMessageListened(msg))
          : null,
      isVideoNote: isRoundVideoMessage,
      voiceDuration: msg.voiceDuration,
      audioUrl: msg.attachmentUrl,
      showUnopenedVoiceIndicator: isUnopenedIncomingVoice,
      isVoiceOpened: isMine || isOpenedIncomingVoice,
      onVoiceOpened: isMine ? null : () => _markVoiceMessageOpened(msg),
      onVoicePlaybackStarted: msg.isVoiceNote
          ? () => _handleVoicePlaybackStarted(msg)
          : null,
      onVoicePlaybackCompleted: msg.isVoiceNote
          ? () => unawaited(_handleVoicePlaybackCompleted(msg))
          : null,
      voicePlaybackController: voicePlaybackController,
      attachmentType: effectiveAttachmentType,
      attachmentUrl: msg.attachmentUrl,
      attachmentFileName: msg.attachmentFileName,
      attachmentSize: msg.attachmentSize,
      contactName: sharedContact?.name,
      contactPhone: sharedContact?.phone,
      contactAvatarUrl: sharedContact?.avatarUrl,
      contactUserId: sharedContact?.userId,
      onContactMessage: sharedContact == null
          ? null
          : widget.uiPreviewMode
          ? () async => _showCopyToast('Demo: contact messaging is available')
          : () => _openSharedContactChat(msg),
      onContactAdd: sharedContact == null
          ? null
          : widget.uiPreviewMode
          ? () async => _showCopyToast('Demo: contact profile is available')
          : () => isMine
                ? _openSharedContactProfile(msg)
                : _addSharedContactPage(msg),
      audioTitle: msg.audioTitle,
      audioArtist: msg.audioArtist,
      audioArtworkUrl: msg.audioArtworkUrl,
      onFileAudioPlaybackChanged: effectiveAttachmentType == 'file'
          ? (playback) => _handleFileAudioPlaybackChanged(msg, playback)
          : null,
      onCancelFileTransfer:
          isMine &&
              effectiveAttachmentType == 'file' &&
              msg.status == MessageStatus.sending
          ? () => _cancelOutgoingAttachment(msg.id)
          : null,
      mediaWidth: msg.mediaWidth,
      mediaHeight: msg.mediaHeight,
      videoViewerTitle: widget.title,
      mediaAlbumItems: albumMessages
          .map(
            (message) => MediaAlbumItem(
              id: message.id,
              imageUrl: message.attachmentUrl ?? '',
              caption: _editableMediaCaption(message),
              width: message.mediaWidth,
              height: message.mediaHeight,
              onTap: _selectedMessageIds.isNotEmpty
                  ? () => _toggleMessageSelection(message.id)
                  : () => unawaited(_openImageFullScreen(message)),
              onLongPress: _selectedMessageIds.isEmpty
                  ? () => unawaited(
                      _showMessageActions(message, boundaryMessageId: msg.id),
                    )
                  : null,
              onSecondaryTap: _selectedMessageIds.isEmpty
                  ? () => unawaited(
                      _showMessageActions(
                        message,
                        longPressFeedback: false,
                        boundaryMessageId: msg.id,
                      ),
                    )
                  : null,
            ),
          )
          .toList(growable: false),
      isForwarded: msg.isForwarded,
      isStarred: msg.isStarred,
      isPinned:
          _visiblePinnedEventIds.contains(msg.id) ||
          albumMessages.any(
            (message) => _visiblePinnedEventIds.contains(message.id),
          ),
      isHighlighted:
          _highlightedMessageId == msg.id ||
          albumMessages.any((message) => _highlightedMessageId == message.id),
      isDeleted: msg.isDeleted,
      isEdited: msg.isEdited,
      replyPreview: _replyPreviewDisplayText(msg.replyPreview),
      replySender: _replySenderDisplayName(msg),
      onReplyTap: msg.replyToMessageId == null
          ? null
          : () => unawaited(_jumpToReplyTarget(msg.replyToMessageId)),
      onImageTap: effectiveAttachmentType == 'image'
          ? () => unawaited(_openImageFullScreen(msg))
          : null,
      onVideoShare: _isVideoAttachmentType(effectiveAttachmentType)
          ? () => _promptForward(msg)
          : null,
      onVideoDownload: _isVideoAttachmentType(effectiveAttachmentType)
          ? () => _saveMediaAttachments(<ChatMessage>[msg])
          : null,
      onVideoEdit: effectiveAttachmentType == 'video'
          ? () => _editVideoAsNewMedia(msg)
          : null,
      onVideoDelete: _isVideoAttachmentType(effectiveAttachmentType)
          ? () => _deleteMessagesWithPrompt(<ChatMessage>[msg])
          : null,
      onVideoReply:
          _isVideoAttachmentType(effectiveAttachmentType) &&
              !_isReadOnlySuggestedGroup
          ? () async => _replyToMessageFromSwipe(msg)
          : null,
      onVideoShowInChat: _isVideoAttachmentType(effectiveAttachmentType)
          ? () => _jumpToReplyTarget(msg.id)
          : null,
      onVideoOpenProfile:
          _isVideoAttachmentType(effectiveAttachmentType) && !_isGroupChat
          ? _openRecipientProfileFromVideo
          : null,
      // Loaded history should appear immediately. Animating every existing
      // row on chat entry made the first frames expensive on slower phones.
      // Keep the entrance animation on the optimistic outgoing message only.
      animateOnMount: shouldStartSendAnimation,
      animatePopOnMount: shouldStartSendAnimation,
      sendAnimationId: sendAnimationId,
      onSendAnimationConsumed: shouldStartSendAnimation
          ? () => _pendingMessagePopAnimationIds.remove(msg.id)
          : null,
      ambientProgress: ambientProgress,
      joinsPrevious: joinsPrevious,
      joinsNext: joinsNext,
      contextMenuBoundaryKey: _messageBubbleBoundaryKey(msg.id),
      hideForContextMenu: _contextMenuMessageId == msg.id,
      maxWidth: _isGroupChat && !isMine
          ? MediaQuery.sizeOf(context).width - 94
          : null,
    );

    if (!_isGroupChat || isMine) return bubble;

    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showGroupAvatar)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openGroupMemberProfile(
                msg.senderId,
                senderName ?? msg.senderId,
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: UserAvatar(
                  size: 36,
                  imageUrl: _groupMemberAvatars[msg.senderId],
                  cacheIdentity:
                      'account:${widget.currentUserId.trim().toLowerCase()}'
                      '|user:${msg.senderId.trim().toLowerCase()}',
                  name: senderName ?? msg.senderId,
                ),
              ),
            )
          else
            const SizedBox(width: 40),
          const SizedBox(width: 6),
          Expanded(child: bubble),
        ],
      ),
    );
  }
}
