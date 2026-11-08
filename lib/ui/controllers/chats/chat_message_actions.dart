part of '../../screens/chats/chat_screen.dart';

extension _ChatMessageActions on _ChatScreenState {
  Future<void> _jumpToReplyTarget(String? messageId) async {
    final targetId = messageId?.trim();
    if (targetId == null || targetId.isEmpty || !mounted) return;

    var targetIndex = -1;
    for (var index = 0; index < _messages.length; index++) {
      if (_messages[index].id == targetId) {
        targetIndex = index;
        break;
      }
    }
    if (targetIndex < 0) return;
    final targetMessage = _messages[targetIndex];
    final albumMembers = _imageAlbumMessages(targetMessage);
    final boundaryMessageId = albumMembers.length > 1
        ? albumMembers.first.id
        : targetId;
    if (albumMembers.length > 1) {
      targetIndex = _messages.indexWhere(
        (message) => message.id == boundaryMessageId,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final boundaryContext = _messageBubbleBoundaryKey(
        boundaryMessageId,
      ).currentContext;
      if (boundaryContext != null) {
        await Scrollable.ensureVisible(
          boundaryContext,
          alignment: 0.24,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollCtrl.hasClients && _messages.length > 1) {
        final maxExtent = _scrollCtrl.position.maxScrollExtent;
        final estimatedOffset =
            ChatTimelineCoordinates.estimatedOffsetForChronologicalIndex(
              chronologicalIndex: targetIndex,
              messageCount: _messages.length,
              maxScrollExtent: maxExtent,
            );
        await _scrollCtrl.animateTo(
          estimatedOffset.clamp(0.0, maxExtent).toDouble(),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );

        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final settledBoundaryContext = _messageBubbleBoundaryKey(
          boundaryMessageId,
        ).currentContext;
        if (settledBoundaryContext != null && settledBoundaryContext.mounted) {
          await Scrollable.ensureVisible(
            settledBoundaryContext,
            alignment: 0.24,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      }
      if (!mounted) return;
      _pulseMessageHighlight(targetId);
    });
  }

  void _pulseMessageHighlight(String messageId) {
    _highlightTimer?.cancel();
    _setChatState(() {
      _highlightedMessageId = messageId;
      _highlightPulse++;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 820), () {
      if (!mounted || _highlightedMessageId != messageId) return;
      _setChatState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _openPinnedMessage(String eventId) async {
    final normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty || !mounted) return;

    if (!_messages.any((message) => message.id == normalizedEventId)) {
      final room = MatrixChatService.instance.getRoomById(
        _activeConversationId,
      );
      final event = await room?.getEventById(normalizedEventId);
      final message = event == null ? null : ChatMessage.fromMatrixEvent(event);
      if (message != null && mounted) {
        _setChatState(() => _upsertMessage(message));
        await WidgetsBinding.instance.endOfFrame;
      }
    }

    await _jumpToReplyTarget(normalizedEventId);
  }

  Future<void> _openPinnedMessagesPage(List<String> eventIds) async {
    if (!mounted || eventIds.isEmpty) return;
    final orderedMessages = <ChatMessage>[];
    for (final eventId in eventIds) {
      for (final message in _messages) {
        if (message.id == eventId && !message.isDeleted) {
          orderedMessages.add(message);
          break;
        }
      }
    }

    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: 'Pinned messages',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) =>
          PinnedMessagesPage(
            messages: orderedMessages,
            pinnedCount: eventIds.length,
            currentUserId: widget.currentUserId,
            onOpenMessage: (eventId) {
              unawaited(_openPinnedMessage(eventId));
            },
            onCopy: _copyMessageText,
            onUnpin: _unpinPinnedMessageFromPage,
            onForward: _promptForward,
            deleteActionsFor: _deleteActionsFor,
            onReaction: _sendMessageReaction,
            onUnpinAll: () => _unpinAllPinnedMessages(eventIds),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            );
        final fade = Tween<double>(begin: .92, end: 1).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    );
  }

  Future<void> _unpinAllPinnedMessages(List<String> eventIds) async {
    final room = MatrixChatService.instance.getRoomById(_activeConversationId);
    final canChangeSharedPins =
        widget.uiPreviewMode ||
        (room?.canChangeStateEvent(mx.EventTypes.RoomPinnedEvents) ?? false);
    var skippedSharedPins = false;

    for (final eventId in List<String>.from(eventIds)) {
      ChatMessage? message;
      for (final candidate in _messages) {
        if (candidate.id == eventId) {
          message = candidate;
          break;
        }
      }
      if (message == null && room != null) {
        final event = await room.getEventById(eventId);
        message = event == null ? null : ChatMessage.fromMatrixEvent(event);
      }
      if (message == null) continue;

      if (_pinnedForMeEventIds.contains(eventId)) {
        await _setMessagePinnedForMe(message, pinned: false);
      }
      if (_pinnedEventIds.contains(eventId)) {
        if (canChangeSharedPins) {
          await _setMessagePinned(message, pinned: false);
        } else {
          skippedSharedPins = true;
        }
      }
    }

    if (skippedSharedPins && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to unpin shared messages.'),
        ),
      );
    }
  }

  Future<bool> _unpinPinnedMessageFromPage(ChatMessage message) async {
    await _unpinAllPinnedMessages([message.id]);
    return !_visiblePinnedEventIds.contains(message.id);
  }

  Future<void> _showMessageActions(
    ChatMessage message, {
    bool longPressFeedback = true,
    String? boundaryMessageId,
  }) async {
    if (_messageActionsActive || !mounted) return;
    _messageActionsActive = true;
    if (longPressFeedback) {
      // Use the platform's native long-press response: Android's LONG_PRESS
      // vibration and the corresponding iOS haptic/click treatment.
      unawaited(Feedback.forLongPress(context));
    }
    final focusedBoundaryId = boundaryMessageId ?? message.id;
    final actions = _messageActionsFor(message);

    MessageActionsOverlayResult? result;
    try {
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus?.hasFocus == true) {
        primaryFocus!.unfocus();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }

      final boundaryKey = _messageBubbleBoundaryKey(focusedBoundaryId);
      var boundary = boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderBox || !boundary.attached || !boundary.hasSize) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        boundary = boundaryKey.currentContext?.findRenderObject();
      }

      if (boundary is! RenderBox || !boundary.attached || !boundary.hasSize) {
        result = await _showMessageActionsFallbackResult(actions);
      } else {
        final bubbleRect = boundary.localToGlobal(Offset.zero) & boundary.size;
        final bubbleAnchor = boundaryKey.currentState;
        if (bubbleRect.isEmpty ||
            !bubbleRect.isFinite ||
            bubbleAnchor is! MessageActionsAnchorState) {
          result = await _showMessageActionsFallbackResult(actions);
        } else {
          // Promote the actual bubble, including its existing media state,
          // above the blur instead of cutting a hole in the background.
          result = await showTelegramMessageActionsOverlay(
            context: context,
            bubbleAnchor: bubbleAnchor,
            isMine: _isMine(message),
            actions: actions,
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[ChatScreen] Could not present message actions: '
        '$error\n$stackTrace',
      );
      // The user's long press was already accepted. Never leave a physical
      // device at "haptic feedback, then nothing" if the anchor disappears;
      // the action sheet remains the reliable interaction path.
      if (mounted) {
        try {
          result = await _showMessageActionsFallbackResult(actions);
        } catch (fallbackError, fallbackStackTrace) {
          debugPrint(
            '[ChatScreen] Could not present fallback message actions: '
            '$fallbackError\n$fallbackStackTrace',
          );
        }
      }
    } finally {
      _messageActionsActive = false;
    }

    await _handleMessageActionsOverlayResult(message, result);
  }

  Future<MessageActionsOverlayResult?> _showMessageActionsFallbackResult(
    List<MessageActionItem> actions,
  ) async {
    if (!mounted) return null;
    final selected = await _showMessageActionsFallback(actions);
    return selected == null
        ? null
        : MessageActionsOverlayResult.action(selected);
  }

  Future<void> _handleMessageActionsOverlayResult(
    ChatMessage message,
    MessageActionsOverlayResult? result,
  ) async {
    if (!mounted || result == null) return;
    final action = result.action;
    if (action != null) {
      if (!result.actionAlreadyHandled) await action.onSelected();
      return;
    }
    final reaction = result.reaction;
    if (reaction != null) {
      await _sendMessageReaction(message, reaction);
    }
  }

  Future<void> _sendMessageReaction(
    ChatMessage message,
    String reaction,
  ) async {
    if (widget.uiPreviewMode) {
      _showCopyToast('Reacted $reaction');
      return;
    }
    if (_isLocalOutgoingEchoId(message.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for the message to finish sending')),
      );
      return;
    }

    final room =
        MatrixChatService.instance.getRoomById(message.conversationId) ??
        MatrixChatService.instance.getRoomById(_activeConversationId);
    if (room == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat is not available')));
      return;
    }

    try {
      await room.sendReaction(message.id, reaction);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reacted $reaction')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add reaction: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<MessageActionItem?> _showMessageActionsFallback(
    List<MessageActionItem> actions,
  ) {
    return showModalBottomSheet<MessageActionItem>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: WrytteColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final fallbackActions = [
          for (final action in actions)
            if (action.submenu.isEmpty) action else ...action.submenu,
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final action in fallbackActions)
                _messageActionTile(
                  icon: action.icon,
                  svgAsset: action.svgAsset,
                  iconScale: action.iconScale,
                  mirrorSvgHorizontally: action.mirrorSvgHorizontally,
                  label: action.label,
                  destructive: action.destructive,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    Navigator.pop(sheetContext, action);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<MessageActionItem> _messageActionsFor(ChatMessage message) {
    final room = MatrixChatService.instance.getRoomById(message.conversationId);
    final currentMatrixUserId = room?.client.userID?.trim() ?? '';
    final isAdminInGroup =
        _isGroupChat &&
        room != null &&
        MatrixChatService.instance.isGroupAdmin(room, currentMatrixUserId);
    final isGroupOwner =
        _isGroupChat &&
        room != null &&
        room.creatorUserIds.contains(currentMatrixUserId);
    final isMessageSenderAdmin =
        _isGroupChat &&
        room != null &&
        MatrixChatService.instance.isGroupAdmin(room, message.senderId);
    final isPinnedForEveryone = _pinnedEventIds.contains(message.id);
    final isPinnedForMe = _pinnedForMeEventIds.contains(message.id);
    final isPinnableEvent =
        (widget.uiPreviewMode || message.id.startsWith(r'$')) &&
        !_pinUpdatesInFlight.contains(message.id) &&
        !message.isDeleted &&
        message.status != MessageStatus.sending &&
        message.status != MessageStatus.failed;
    final canPinForEveryone =
        (widget.uiPreviewMode ||
            (!_isReadOnlySuggestedGroup &&
                room != null &&
                room.canChangeStateEvent(mx.EventTypes.RoomPinnedEvents))) &&
        isPinnableEvent;
    final canPinForMe =
        !_isGroupChat &&
        (widget.uiPreviewMode || room != null) &&
        isPinnableEvent;
    final pinActions = <MessageActionItem>[
      if (!isPinnedForEveryone && !isPinnedForMe && canPinForEveryone)
        MessageActionItem(
          label: _isGroupChat ? 'Pin' : 'Pin for everyone',
          onSelected: () => _setMessagePinned(message, pinned: true),
        ),
      if (!isPinnedForEveryone && !isPinnedForMe && canPinForMe)
        MessageActionItem(
          label: 'Pin for me',
          onSelected: () => _setMessagePinnedForMe(message, pinned: true),
        ),
    ];
    final mediaToSave = _mediaMessagesForSave(message);

    return [
      if (!_isReadOnlySuggestedGroup)
        MessageActionItem(
          svgAsset: 'assets/svg/Forward Icon.svg',
          iconScale: 1.18,
          mirrorSvgHorizontally: true,
          label: 'Reply',
          onSelected: () {
            if (!mounted) return;
            _setChatState(() => _replyingTo = message);
            _focusNode.requestFocus();
          },
        ),
      MessageActionItem(
        svgAsset: 'assets/svg/Copy icon.svg',
        iconScale: 1.03,
        label: 'Copy',
        onSelected: () => _copyMessageText(message),
      ),
      if (mediaToSave.isNotEmpty)
        MessageActionItem(
          svgAsset: 'assets/svg/Download Save icon.svg',
          iconScale: 1.26,
          label: 'Save',
          onSelected: mediaToSave.length > 1
              ? () {}
              : () => _saveMediaAttachments(<ChatMessage>[message]),
          submenu: mediaToSave.length > 1
              ? <MessageActionItem>[
                  MessageActionItem(
                    label: _effectiveAttachmentType(message) == 'video'
                        ? 'Save current video'
                        : 'Save current photo',
                    onSelected: () =>
                        _saveMediaAttachments(<ChatMessage>[message]),
                  ),
                  MessageActionItem(
                    label: 'Save all ${mediaToSave.length}',
                    onSelected: () => _saveMediaAttachments(mediaToSave),
                  ),
                  MessageActionItem(label: 'Cancel', onSelected: () {}),
                ]
              : const <MessageActionItem>[],
        ),
      MessageActionItem(
        svgAsset: 'assets/svg/Forward Icon.svg',
        iconScale: 1.18,
        label: 'Forward',
        onSelected: () => _promptForward(message),
      ),
      if (_canEditMessage(message))
        MessageActionItem(
          svgAsset: 'assets/svg/Edit pencil icon.svg',
          iconScale: 1.02,
          label: 'Edit',
          onSelected: () => _promptEditMessage(message),
        ),
      if (_canEditMediaMessage(message))
        MessageActionItem(
          svgAsset: 'assets/svg/Edit pencil icon.svg',
          iconScale: 1.02,
          label: 'Edit',
          onSelected: () => _promptEditMessage(message),
        ),
      if (isPinnedForEveryone || isPinnedForMe)
        MessageActionItem(
          svgAsset: 'assets/svg/Unpin icon .svg',
          iconScale: 1.12,
          label: 'Unpin',
          onSelected: () => _unpinAllPinnedMessages([message.id]),
        )
      else if (pinActions.isNotEmpty)
        MessageActionItem(
          svgAsset: 'assets/svg/Pin icon .svg',
          iconScale: 1.12,
          label: pinActions.length == 1 ? pinActions.single.label : 'Pin',
          onSelected: pinActions.length == 1
              ? pinActions.single.onSelected
              : () {},
          submenu: pinActions.length == 1
              ? const <MessageActionItem>[]
              : <MessageActionItem>[
                  ...pinActions,
                  MessageActionItem(label: 'Cancel', onSelected: () {}),
                ],
        ),
      if (_isGroupChat &&
          isAdminInGroup &&
          !_isMine(message) &&
          !isMessageSenderAdmin &&
          !message.isDeleted)
        MessageActionItem(
          icon: Icons.person_remove_outlined,
          label: 'Remove from group',
          destructive: true,
          onSelected: () => _removeMessageSenderFromGroup(message),
        ),
      if (_isGroupChat &&
          !isGroupOwner &&
          !_isMine(message) &&
          !message.isDeleted)
        MessageActionItem(
          icon: Icons.report_gmailerrorred_outlined,
          label: 'Report',
          destructive: true,
          onSelected: () => _reportGroupMessage(message),
        ),
      if (!_isReadOnlySuggestedGroup)
        MessageActionItem(
          svgAsset: 'assets/svg/Delete icon.svg',
          iconScale: 1.16,
          label: 'Delete',
          destructive: true,
          onSelected: () {},
          submenu: _deleteActionsFor(message),
        ),
      MessageActionItem(
        svgAsset: 'assets/svg/Select icon.svg',
        iconScale: 1.08,
        label: 'Select',
        selectionAction: true,
        onSelected: () => _selectMessage(message),
      ),
    ];
  }

  bool _canSaveMedia(ChatMessage message) {
    final type = _effectiveAttachmentType(message);
    return !message.isDeleted &&
        message.attachmentUrl?.trim().isNotEmpty == true &&
        (type == 'image' || _isVideoAttachmentType(type));
  }

  List<ChatMessage> _mediaMessagesForSave(ChatMessage message) {
    if (!_canSaveMedia(message)) return const <ChatMessage>[];
    final groupId = message.mediaGroupId?.trim() ?? '';
    if (groupId.isEmpty) return <ChatMessage>[message];

    final grouped = _messages
        .where(
          (candidate) =>
              candidate.mediaGroupId?.trim() == groupId &&
              candidate.senderId == message.senderId &&
              _canSaveMedia(candidate),
        )
        .take(10)
        .toList(growable: false);
    grouped.sort((first, second) {
      final firstIndex = first.mediaGroupIndex;
      final secondIndex = second.mediaGroupIndex;
      if (firstIndex != null &&
          secondIndex != null &&
          firstIndex != secondIndex) {
        return firstIndex.compareTo(secondIndex);
      }
      return first.timestamp.compareTo(second.timestamp);
    });
    return grouped.length > 1 ? grouped : <ChatMessage>[message];
  }

  Future<void> _saveMediaAttachments(List<ChatMessage> messages) async {
    final media = messages.where(_canSaveMedia).toList(growable: false);
    if (media.isEmpty) return;
    if (widget.uiPreviewMode) {
      _showCopyToast(
        media.length > 1
            ? 'Demo: ${media.length} items saved'
            : 'Demo: saved to gallery',
        iconAsset: 'assets/svg/Download Save icon.svg',
      );
      return;
    }
    final groupId = media.first.mediaGroupId?.trim() ?? '';
    final operationKey = media.length > 1 && groupId.isNotEmpty
        ? 'group:$groupId'
        : 'message:${media.first.id}';
    if (!_mediaSavesInFlight.add(operationKey)) return;

    try {
      var savedCount = 0;
      for (final message in media) {
        try {
          await _saveSingleMediaAttachment(message);
          savedCount++;
        } catch (error) {
          debugPrint('[ChatScreen] Could not save media ${message.id}: $error');
        }
      }

      if (!mounted) return;
      if (savedCount == media.length) {
        _showCopyToast(
          media.length > 1
              ? 'Saved ${media.length} items to gallery'
              : 'Saved to gallery',
          iconAsset: 'assets/svg/Download Save icon.svg',
        );
      } else if (savedCount > 0) {
        _showCopyToast(
          'Saved $savedCount of ${media.length} items to gallery',
          iconAsset: 'assets/svg/Download Save icon.svg',
        );
      } else {
        _showCopyToast('Could not save media.');
      }
    } finally {
      _mediaSavesInFlight.remove(operationKey);
    }
  }

  Future<void> _saveSingleMediaAttachment(ChatMessage message) async {
    final type = _effectiveAttachmentType(message)!;
    final fileName = _mediaGalleryFileName(message, type);
    final localCopy = await AttachmentLocalStore.instance.ensureComplete(
      source: message.attachmentUrl!.trim(),
      fileName: fileName,
    );
    if (!localCopy.isComplete || !await localCopy.file.exists()) {
      throw const FileSystemException('Media download is incomplete');
    }

    if (_isVideoAttachmentType(type)) {
      await PhotoManager.editor.saveVideo(localCopy.file, title: fileName);
    } else {
      await PhotoManager.editor.saveImageWithPath(
        localCopy.file.path,
        title: fileName,
      );
    }
  }

  String _mediaGalleryFileName(ChatMessage message, String type) {
    final source = message.attachmentUrl?.trim() ?? '';
    final sourcePath = Uri.tryParse(source)?.path ?? source;
    final sourceExtension = p.extension(sourcePath).toLowerCase();
    final acceptedExtensions = _isVideoAttachmentType(type)
        ? const <String>{'.mp4', '.mov', '.m4v', '.webm', '.mkv', '.3gp'}
        : const <String>{
            '.png',
            '.jpg',
            '.jpeg',
            '.gif',
            '.webp',
            '.bmp',
            '.heic',
            '.heif',
          };
    final extension = acceptedExtensions.contains(sourceExtension)
        ? sourceExtension
        : _isVideoAttachmentType(type)
        ? '.mp4'
        : '.jpg';
    return 'Wrytte_${message.timestamp.toUtc().microsecondsSinceEpoch}$extension';
  }

  Future<void> _copyMessageText(ChatMessage message) async {
    final text = message.content.trim();
    if (text.isEmpty) {
      _showCopyToast('Nothing to copy');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showCopyToast('Copied to clipboard.');
  }

  void _showCopyToast(String message, {String? iconAsset}) {
    if (!mounted) return;
    _copyToastEntry?.remove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final bottomObstruction =
            mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
            ? mediaQuery.viewInsets.bottom
            : mediaQuery.viewPadding.bottom;
        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: 24,
                right: 24,
                bottom: 72 + bottomObstruction,
                child: _CopyToast(
                  message: message,
                  iconAsset: iconAsset,
                  onDismissed: () {
                    if (_copyToastEntry != entry) return;
                    entry.remove();
                    _copyToastEntry = null;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    _copyToastEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Future<void> _setMessagePinnedForMe(
    ChatMessage message, {
    required bool pinned,
  }) async {
    if (_isGroupChat || !_pinUpdatesInFlight.add(message.id)) return;
    final previousIds = List<String>.from(_pinnedForMeEventIds);
    final optimisticIds = List<String>.from(previousIds)
      ..removeWhere((id) => id == message.id);
    if (pinned) optimisticIds.insert(0, message.id);
    _setChatState(() => _pinnedForMeEventIds = optimisticIds);
    if (widget.uiPreviewMode) {
      _pinUpdatesInFlight.remove(message.id);
      return;
    }
    try {
      final ids = await _chat.setMessagePinnedForMe(message, pinned: pinned);
      if (!mounted) return;
      _setChatState(() => _pinnedForMeEventIds = ids);
    } catch (error) {
      if (!mounted) return;
      _setChatState(() => _pinnedForMeEventIds = previousIds);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${pinned ? 'pin' : 'unpin'} message for you: $error',
          ),
        ),
      );
    } finally {
      _pinUpdatesInFlight.remove(message.id);
    }
  }

  Future<void> _setMessagePinned(
    ChatMessage message, {
    required bool pinned,
  }) async {
    final now = DateTime.now();
    final lastUpdate = _lastPinUpdateAt[message.id];
    if (lastUpdate != null &&
        now.difference(lastUpdate) < const Duration(seconds: 1)) {
      return;
    }
    if (!_pinUpdatesInFlight.add(message.id)) return;
    _lastPinUpdateAt[message.id] = now;
    final previousIds = List<String>.from(_pinnedEventIds);
    final optimisticIds = List<String>.from(previousIds)
      ..removeWhere((id) => id == message.id);
    if (pinned) optimisticIds.insert(0, message.id);
    _setChatState(() => _pinnedEventIds = optimisticIds);
    if (widget.uiPreviewMode) {
      _pinUpdatesInFlight.remove(message.id);
      return;
    }
    try {
      final ids = await _chat.setMessagePinnedForEveryone(
        message,
        pinned: pinned,
      );
      if (!mounted) return;
      _setChatState(() => _pinnedEventIds = ids);
    } catch (error) {
      if (!mounted) return;
      _setChatState(() => _pinnedEventIds = previousIds);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${pinned ? 'pin' : 'unpin'} message: $error',
          ),
        ),
      );
    } finally {
      _pinUpdatesInFlight.remove(message.id);
    }
  }

  Future<void> _reportGroupMessage(ChatMessage message) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WrytteColors.surfaceRaised,
        title: const Text(
          'Report message',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Why are you reporting this message?',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    try {
      await MatrixChatService.instance.reportGroupMember(
        roomId: message.conversationId,
        eventId: message.id,
        reportedUserId: message.senderId,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message reported')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not report message: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _removeMessageSenderFromGroup(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WrytteColors.surfaceRaised,
        title: const Text(
          'Remove member',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Remove this member from the group?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: WrytteColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await MatrixChatService.instance.removeGroupMember(
        roomId: message.conversationId,
        userId: message.senderId,
        reason: 'Removed by group admin',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed from the group')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not remove member: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _selectMessage(ChatMessage message) {
    if (!mounted) return;
    final messageIds = _selectionIdsForMessage(message);
    _setChatState(() {
      _selectedMessageIds.addAll(messageIds);
    });
  }

  void _replyToMessageFromSwipe(ChatMessage message) {
    if (!mounted || _selectedMessageIds.isNotEmpty) return;
    _setChatState(() {
      _editingMessage = null;
      _replyingTo = message;
    });
    unawaited(_focusComposerAndShowKeyboard());
  }

  Future<void> _focusComposerAndShowKeyboard() async {
    // Wait until the reply preview has joined the tree before focusing its
    // TextField. A second frame lets EditableText attach its input connection.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _focusNode.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_focusNode.hasFocus) return;

    // On Android the system back button can hide the IME without removing
    // focus. requestFocus() alone is then a no-op, so explicitly restore the
    // existing text-input connection for this user-initiated reply action.
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } on PlatformException catch (error) {
      debugPrint('[ChatScreen] Could not show reply keyboard: $error');
    }
  }

  void _forwardMessageFromSwipe(ChatMessage message) {
    if (!mounted || _selectedMessageIds.isNotEmpty) return;
    unawaited(_promptForward(message));
  }

  bool _canDeleteForEveryone(ChatMessage message) {
    final room = MatrixChatService.instance.getRoomById(message.conversationId);
    final currentUserId = room?.client.userID ?? widget.currentUserId;
    final canModerateGroupMessage =
        _isGroupChat &&
        room != null &&
        room.canRedact &&
        MatrixChatService.instance.isGroupAdmin(room, currentUserId);
    return (_isMine(message) || canModerateGroupMessage) &&
        !message.isDeleted &&
        !message.id.startsWith('blocked_') &&
        message.status != MessageStatus.sending &&
        message.status != MessageStatus.failed &&
        !message.id.startsWith('opt_');
  }

  List<MessageActionItem> _deleteActionsFor(ChatMessage message) {
    return [
      if (_canDeleteForEveryone(message))
        MessageActionItem(
          label: 'Delete for everyone',
          destructive: true,
          onSelected: () => _deleteMessageForEveryone(message),
        ),
      MessageActionItem(
        label: 'Delete for me',
        destructive: true,
        onSelected: () => _deleteMessageForMe(message),
      ),
      MessageActionItem(label: 'Cancel', onSelected: () {}),
    ];
  }

  Future<void> _deleteMessageForMe(ChatMessage message) async {
    final originalIndex = _messages.indexWhere(
      (candidate) => candidate.id == message.id,
    );
    _setChatState(() => _deletingMessageIds.add(message.id));
    if (message.id.startsWith('blocked_')) {
      await BlockStateService.instance.removeBlockedMessage(
        roomId: message.conversationId,
        messageId: message.id,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted) {
      _setChatState(() {
        _messages.removeWhere((candidate) => candidate.id == message.id);
        _deletingMessageIds.remove(message.id);
        _selectedMessageIds.remove(message.id);
      });
    }
    if (widget.uiPreviewMode) return;
    try {
      await _chat.deleteMessageForMe(message);
    } catch (error) {
      if (!mounted) return;
      _setChatState(() {
        _deletingMessageIds.remove(message.id);
        if (!_messages.any((candidate) => candidate.id == message.id)) {
          final insertionIndex = originalIndex.clamp(0, _messages.length);
          _messages.insert(insertionIndex, message);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete message: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _deleteMessageForEveryone(ChatMessage message) async {
    final isOwnMessage = _isMine(message);
    final deletedMessage = message.copyWith(
      content: isOwnMessage
          ? 'This message was deleted'
          : 'This message was deleted by admin',
      isDeletedForEveryone: true,
    );
    _setChatState(() {
      _selectedMessageIds.remove(message.id);
      _deletingMessageIds.add(message.id);
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted) {
      _setChatState(() {
        _deletingMessageIds.remove(message.id);
        _upsertMessage(deletedMessage);
      });
    }
    if (widget.uiPreviewMode) return;
    try {
      await _chat.deleteMessageForEveryone(message);
    } catch (error) {
      if (!mounted) return;
      _setChatState(() {
        _deletingMessageIds.remove(message.id);
        _upsertMessage(message);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete message: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  bool _canEditMessage(ChatMessage message) {
    if (!_isMine(message)) return false;
    if (message.isDeleted) return false;
    if (message.attachmentType?.trim().isNotEmpty == true ||
        message.hasAttachment ||
        message.isVoiceNote) {
      return false;
    }
    if (message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed) {
      return false;
    }
    if (message.id.startsWith('opt_')) return false;
    return message.content.trim().isNotEmpty;
  }

  bool _canEditMediaMessage(ChatMessage message) {
    if (!_isMine(message) || message.isDeleted || message.isVoiceNote) {
      return false;
    }
    final type = _effectiveAttachmentType(message);
    if (type != 'image' && type != 'video') return false;
    if (message.attachmentUrl?.trim().isEmpty != false) return false;
    if (message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed ||
        message.id.startsWith('opt_')) {
      return false;
    }
    return true;
  }

  String _editableMediaCaption(ChatMessage message) {
    final text = message.content.trim();
    final type = _effectiveAttachmentType(message) ?? 'image';
    final placeholder = _attachmentLabelForType(type);
    if (text.isEmpty || text.toLowerCase() == placeholder.toLowerCase()) {
      return '';
    }

    // Matrix uses the uploaded filename as a media event's body when no
    // caption was supplied. It is transport metadata, not editable text.
    final sourceName = p.basename(message.attachmentUrl?.trim() ?? '');
    if (sourceName.isNotEmpty &&
        text.toLowerCase() == sourceName.toLowerCase()) {
      return '';
    }
    final mediaFileName = RegExp(
      type == 'video'
          ? r'^[^/\\]+\.(?:mp4|mov|m4v|webm|mkv|avi|3gp)$'
          : r'^[^/\\]+\.(?:jpe?g|png|gif|webp|heic|heif|bmp)$',
      caseSensitive: false,
    );
    return mediaFileName.hasMatch(text) ? '' : text;
  }

  void _promptEditMessage(ChatMessage message) {
    final initialText = _canEditMediaMessage(message)
        ? _editableMediaCaption(message)
        : message.content;
    _setChatState(() {
      _replyingTo = null;
      _editingMessage = message;
    });
    _controller
      ..text = initialText
      ..selection = TextSelection.collapsed(offset: initialText.length);
    _focusNode.requestFocus();
  }

  Future<void> _editVideoAsNewMedia(ChatMessage message) async {
    final source = message.attachmentUrl?.trim() ?? '';
    if (source.isEmpty || !mounted) return;

    try {
      final localCopy = await AttachmentLocalStore.instance.ensureComplete(
        source: source,
        fileName: _mediaGalleryFileName(message, 'video'),
      );
      if (!localCopy.isComplete || !await localCopy.file.exists() || !mounted) {
        _showCopyToast('Could not open video editor');
        return;
      }

      final result = await Navigator.of(context).push<ChatMediaEditorResult>(
        PageRouteBuilder<ChatMediaEditorResult>(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) =>
              ChatMediaEditorScreen(
                sourcePath: localCopy.file.path,
                attachmentType: 'video',
                recipientLabel: _resolvedHeaderName,
                initialCaption: _editableMediaCaption(message),
                selectionIndex: 1,
                selectedCount: 1,
                showSelectionControl: false,
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(opacity: curved, child: child);
          },
        ),
      );
      if (!mounted || result == null || !result.sendNow) return;

      final editedPath = result.editedFilePath?.trim();
      final outputPath = editedPath?.isNotEmpty == true
          ? editedPath!
          : localCopy.file.path;
      await _sendPickedAttachment(
        outputPath,
        'video',
        caption: result.caption.trim().isEmpty ? null : result.caption.trim(),
      );
    } catch (error) {
      debugPrint('[ChatScreen] Could not edit video as new media: $error');
      if (mounted) _showCopyToast('Could not open video editor');
    }
  }

  Future<void> _editImageAsNewMedia(ChatMessage message) async {
    final source = message.attachmentUrl?.trim() ?? '';
    if (source.isEmpty || !mounted) return;

    try {
      final localCopy = await AttachmentLocalStore.instance.ensureComplete(
        source: source,
        fileName: _mediaGalleryFileName(message, 'image'),
      );
      if (!localCopy.isComplete || !await localCopy.file.exists() || !mounted) {
        _showCopyToast('Could not open photo editor');
        return;
      }

      final result = await Navigator.of(context).push<ChatMediaEditorResult>(
        PageRouteBuilder<ChatMediaEditorResult>(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) =>
              ChatMediaEditorScreen(
                sourcePath: localCopy.file.path,
                attachmentType: 'image',
                recipientLabel: _resolvedHeaderName,
                initialCaption: _editableMediaCaption(message),
                selectionIndex: 1,
                selectedCount: 1,
                showSelectionControl: false,
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(opacity: curved, child: child);
          },
        ),
      );
      if (!mounted || result == null || !result.sendNow) return;

      final editedPath = result.editedFilePath?.trim();
      final outputPath = editedPath?.isNotEmpty == true
          ? editedPath!
          : localCopy.file.path;
      await _sendPickedAttachment(
        outputPath,
        'image',
        caption: result.caption.trim().isEmpty ? null : result.caption.trim(),
      );
    } catch (error) {
      debugPrint('[ChatScreen] Could not edit photo as new media: $error');
      if (mounted) _showCopyToast('Could not open photo editor');
    }
  }

  Future<void> _openImageFullScreen(ChatMessage message) async {
    final source = message.attachmentUrl?.trim() ?? '';
    if (source.isEmpty || !mounted) return;
    await FullScreenImageViewer.open(
      context,
      source,
      caption: _editableMediaCaption(message),
      title: widget.title,
      subtitle: 'Today, ${_formatTime(message.timestamp)}',
      onShare: () => _promptForward(message),
      onDownload: () => _saveMediaAttachments(<ChatMessage>[message]),
      onEdit: () => _editImageAsNewMedia(message),
      onDelete: () => _deleteMessagesWithPrompt(<ChatMessage>[message]),
      onReply: _isReadOnlySuggestedGroup
          ? null
          : () async => _replyToMessageFromSwipe(message),
      onShowInChat: () => _jumpToReplyTarget(message.id),
      onOpenProfile: _isGroupChat ? null : _openRecipientProfileFromVideo,
    );
  }

  Future<void> _openRecipientProfileFromVideo() async {
    if (!mounted || _isGroupChat) return;
    final profileUid = _profilePeerId();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          uid: profileUid,
          conversationId: _resolvedConversationId ?? widget.conversationId,
          savedNameHint: _resolvedHeaderName,
          initialAvatarUrl: _stableHeaderAvatarUrl,
        ),
      ),
    );
    if (mounted) _loadReceiverProfile();
  }

  Future<void> _promptReplaceMedia(ChatMessage message) async {
    if (!_canEditMediaMessage(message) || _isSending) return;
    _focusNode.unfocus();
    final originalCaption = _controller.text.trim();
    final selection = await showChatMediaReplacementPanel(
      context: context,
      recipientLabel: _resolvedHeaderName,
      initialCaption: originalCaption,
    );
    if (!mounted || selection == null || selection.media.isEmpty) return;

    final replacement = selection.media.first;
    final type = replacement.attachmentType.trim().toLowerCase();
    final caption = selection.caption.trim();
    final width = replacement.width ?? message.mediaWidth;
    final height = replacement.height ?? message.mediaHeight;
    final effectiveContent = caption.isEmpty
        ? _attachmentLabelForType(type)
        : caption;

    final optimistic = message.copyWith(
      content: effectiveContent,
      attachmentUrl: replacement.filePath,
      attachmentType: type,
      mediaWidth: width,
      mediaHeight: height,
      status: MessageStatus.sending,
      isEdited: true,
    );
    _setChatState(() {
      _isSending = true;
      _replaceOptimisticMessage(message.id, optimistic);
    });

    try {
      final updated = await _chat.replaceMediaMessage(
        message: message,
        filePath: replacement.filePath,
        attachmentType: type,
        caption: caption,
        mediaWidth: width,
        mediaHeight: height,
      );
      if (!mounted) return;
      _setChatState(() {
        _replaceOptimisticMessage(message.id, updated);
        _editingMessage = null;
      });
      _controller.clear();

      final additionalMedia = selection.media.skip(1).toList(growable: false);
      if (additionalMedia.isNotEmpty) {
        await _sendPickedAttachments(additionalMedia);
      }
      _showCopyToast(type == 'video' ? 'Video replaced' : 'Photo replaced');
    } catch (error) {
      apkLog('ChatScreen._promptReplaceMedia', 'REPLACE FAILED: $error');
      if (!mounted) return;
      _setChatState(() {
        _replaceOptimisticMessage(message.id, message);
        if (_editingMessage?.id == message.id) {
          _editingMessage = message;
        }
      });
      _controller
        ..text = caption
        ..selection = TextSelection.collapsed(offset: caption.length);
      _showCopyToast('Could not replace media');
    } finally {
      if (mounted) _setChatState(() => _isSending = false);
    }
  }
}
