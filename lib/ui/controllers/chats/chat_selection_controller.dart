part of '../../screens/chats/chat_screen.dart';

extension _ChatSelectionController on _ChatScreenState {
  bool _isAlbumImage(ChatMessage message) =>
      !message.isDeleted &&
      message.attachmentType == 'image' &&
      message.attachmentUrl?.trim().isNotEmpty == true &&
      message.mediaGroupId?.trim().isNotEmpty == true;

  List<ChatMessage> _imageAlbumMessages(ChatMessage message) {
    if (!_isAlbumImage(message)) return const <ChatMessage>[];
    final groupId = message.mediaGroupId!.trim();
    final members = _messages
        .where(
          (candidate) =>
              _isAlbumImage(candidate) &&
              candidate.mediaGroupId?.trim() == groupId &&
              candidate.senderId == message.senderId,
        )
        .take(10)
        .toList(growable: false);
    members.sort((a, b) {
      final aIndex = a.mediaGroupIndex;
      final bIndex = b.mediaGroupIndex;
      if (aIndex != null && bIndex != null && aIndex != bIndex) {
        return aIndex.compareTo(bIndex);
      }
      return a.timestamp.compareTo(b.timestamp);
    });
    return members;
  }

  List<ChatMessage> _imageAlbumForIndex(int messageIndex) {
    final message = _messages[messageIndex];
    final members = _imageAlbumMessages(message);
    if (members.length < 2) return const <ChatMessage>[];
    final firstIndex = _messages.indexWhere(
      (candidate) => candidate.id == members.first.id,
    );
    return firstIndex == messageIndex ? members : const <ChatMessage>[];
  }

  bool _isImageAlbumFollower(int messageIndex) {
    final message = _messages[messageIndex];
    final members = _imageAlbumMessages(message);
    if (members.length < 2) return false;
    return members.first.id != message.id;
  }

  ChatMessage? _previousVisibleMessage(int messageIndex) {
    for (var i = messageIndex - 1; i >= 0; i--) {
      final candidate = _messages[i];
      if (candidate.isDeleted) continue;
      if (_isImageAlbumFollower(i)) continue;
      return candidate;
    }
    return null;
  }

  ChatMessage? _nextVisibleMessage(int messageIndex) {
    for (var i = messageIndex + 1; i < _messages.length; i++) {
      final candidate = _messages[i];
      if (candidate.isDeleted) continue;
      if (_isImageAlbumFollower(i)) continue;
      return candidate;
    }
    return null;
  }

  Set<String> _selectionIdsForMessage(ChatMessage message) {
    final groupId = message.mediaGroupId?.trim() ?? '';
    if (groupId.isEmpty) return <String>{message.id};

    final batchIds = <String>{
      for (final candidate in _messages)
        if (candidate.mediaGroupId?.trim() == groupId &&
            candidate.senderId == message.senderId)
          candidate.id,
    };
    return batchIds.length > 1 ? batchIds : <String>{message.id};
  }

  void _toggleMessageSelection(String messageId) {
    unawaited(HapticFeedback.selectionClick());
    final messageIndex = _messages.indexWhere(
      (candidate) => candidate.id == messageId,
    );
    final message = messageIndex < 0 ? null : _messages[messageIndex];
    final messageIds = message == null
        ? <String>{messageId}
        : _selectionIdsForMessage(message);
    _setChatState(() {
      final entireBatchIsSelected = messageIds.every(
        _selectedMessageIds.contains,
      );
      if (entireBatchIsSelected) {
        _selectedMessageIds.removeAll(messageIds);
      } else {
        _selectedMessageIds.addAll(messageIds);
      }
    });
  }

  List<ChatMessage> get _selectedMessages => [
    for (final message in _messages)
      if (_selectedMessageIds.contains(message.id)) message,
  ];

  void _clearMessageSelection() {
    if (_selectedMessageIds.isEmpty) return;
    _setChatState(_selectedMessageIds.clear);
  }

  Future<void> _copySelectedMessages() async {
    final text = _selectedMessages
        .map(_selectionCopyText)
        .where((content) => content.isNotEmpty)
        .join('\n');
    if (text.isEmpty) {
      _showCopyToast('Nothing to copy');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _setChatState(_selectedMessageIds.clear);
    _showCopyToast('Copied to clipboard.');
  }

  String _selectionCopyText(ChatMessage message) {
    final content = message.content.trim();
    if (content.isNotEmpty) return content;

    final fileName = message.attachmentFileName?.trim() ?? '';
    if (fileName.isNotEmpty) return fileName;

    return switch (_effectiveAttachmentType(message)) {
      'image' => 'Photo',
      'video' || 'video_message' => 'Video',
      'voice' || 'audio' => 'Voice message',
      'file' => 'File',
      'contact' => <String>[
        message.contactName?.trim() ?? '',
        message.contactPhone?.trim() ?? '',
      ].where((value) => value.isNotEmpty).join('\n'),
      _ => '',
    };
  }

  Future<void> _forwardSelectedMessages() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;
    final forwardAttempted = await _promptForwardMessages(selected);
    if (mounted && forwardAttempted) {
      _setChatState(_selectedMessageIds.clear);
    }
  }

  Future<void> _showSelectionPinOptions() async {
    final selected = List<ChatMessage>.of(_selectedMessages);
    if (selected.isEmpty) return;

    final choice =
        await _showSelectionCommandPanel(const <_SelectionCommandChoice>[
          _SelectionCommandChoice('Pin for everyone', 'everyone'),
          _SelectionCommandChoice('Pin for me', 'me'),
          _SelectionCommandChoice('Cancel', 'cancel'),
        ]);
    if (!mounted || choice == null || choice == 'cancel') return;

    for (final message in selected) {
      if (choice == 'everyone') {
        await _setMessagePinned(message, pinned: true);
      } else {
        await _setMessagePinnedForMe(message, pinned: true);
      }
    }
    if (mounted) _clearMessageSelection();
  }

  Future<void> _showSelectionDeleteOptions() async {
    final selected = List<ChatMessage>.of(_selectedMessages);
    if (selected.isEmpty) return;
    final deleted = await _deleteMessagesWithPrompt(selected);
    if (mounted && deleted) _clearMessageSelection();
  }

  Future<bool> _deleteMessagesWithPrompt(List<ChatMessage> selected) async {
    if (selected.isEmpty) return false;
    final canDeleteForEveryone = selected.every(_canDeleteForEveryone);
    final choice = await _showSelectionCommandPanel(<_SelectionCommandChoice>[
      if (canDeleteForEveryone)
        const _SelectionCommandChoice(
          'Delete for everyone',
          'everyone',
          destructive: true,
        ),
      const _SelectionCommandChoice('Delete for me', 'me', destructive: true),
      const _SelectionCommandChoice('Cancel', 'cancel'),
    ]);
    if (!mounted || choice == null || choice == 'cancel') return false;

    if (choice == 'everyone') {
      for (final message in selected) {
        await _deleteMessageForEveryone(message);
      }
    } else {
      for (final message in selected) {
        await _deleteMessageForMe(message);
      }
    }
    return true;
  }

  Future<String?> _showSelectionCommandPanel(
    List<_SelectionCommandChoice> choices,
  ) {
    final metrics = WrytteChatControlMetrics.of(context);
    final mediaQuery = MediaQuery.of(context);
    final availableWidth =
        mediaQuery.size.width - (metrics.horizontalPadding * 2);
    final panelWidth = (mediaQuery.size.width * .638)
        .clamp(228.0, math.min(262.0, availableWidth))
        .toDouble();
    const rowHeight = 42.0;
    const verticalPadding = 12.0;
    final panelHeight = (choices.length * rowHeight) + (verticalPadding * 2);
    final naturalPillWidth =
        (6 * metrics.scale) +
        (43 * metrics.scale) +
        (4 * 43 * metrics.scale) +
        (8 * metrics.scale);
    final availablePillWidth =
        mediaQuery.size.width -
        (metrics.horizontalPadding * 2) -
        metrics.controlSize -
        metrics.controlGap;
    final pillWidth = naturalPillWidth
        .clamp(metrics.controlSize, availablePillWidth)
        .toDouble();
    final pillCenter =
        metrics.horizontalPadding +
        metrics.controlSize +
        metrics.controlGap +
        (pillWidth / 2);
    final left = (pillCenter - (panelWidth / 2))
        .clamp(
          metrics.horizontalPadding,
          mediaQuery.size.width - metrics.horizontalPadding - panelWidth,
        )
        .toDouble();
    final top = mediaQuery.padding.top + metrics.headerContentHeight + 4;

    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 190),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(dialogContext),
                ),
              ),
              Positioned(
                top: top,
                left: left,
                width: panelWidth,
                height: panelHeight,
                child: _SelectionCommandPanel(
                  choices: choices,
                  animation: animation,
                  onSelected: (value) => Navigator.pop(dialogContext, value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectionCommandChoice {
  const _SelectionCommandChoice(
    this.label,
    this.value, {
    this.destructive = false,
  });

  final String label;
  final String value;
  final bool destructive;
}

class _SelectionCommandPanel extends StatelessWidget {
  const _SelectionCommandPanel({
    required this.choices,
    required this.animation,
    required this.onSelected,
  });

  final List<_SelectionCommandChoice> choices;
  final Animation<double> animation;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        return AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Opacity(
            opacity: curved.value,
            child: Transform.translate(
              offset: Offset(0, -8 * (1 - curved.value)),
              child: Transform.scale(
                scale: .9 + (.1 * curved.value),
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final radius = math.min(
                constraints.maxWidth * .19,
                constraints.maxHeight * .44,
              );
              final shape = RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(radius),
              );
              return ClipPath.shape(
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: WrytteGlassSurface(
                  borderRadius: BorderRadius.zero,
                  blur: 18,
                  child: Material(
                    type: MaterialType.transparency,
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return InkWell(
                          onTap: () => onSelected(choice.value),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.white.withValues(alpha: .035),
                          child: SizedBox(
                            height: 42,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                              ),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  choice.label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: choice.destructive
                                        ? WrytteColors.destructive
                                        : Colors.white,
                                    fontFamily:
                                        WrytteTypography.primaryFontFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
