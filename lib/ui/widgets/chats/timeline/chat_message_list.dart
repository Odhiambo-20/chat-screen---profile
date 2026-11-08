part of '../../../screens/chats/chat_screen.dart';

extension _ChatMessageList on _ChatScreenState {
  Widget _buildMessageList(
    double topInset, {
    required BuildContext mediaContext,
  }) {
    final alignedDateTopPadding =
        (topInset + _floatingDateTopGap - _dateDividerVerticalPadding).clamp(
          0.0,
          double.infinity,
        );
    final listTopPadding = _showsDirectConversationEncryptionNotice
        ? topInset + _directConversationStartTopGap
        : alignedDateTopPadding;
    final hasComposerContext = _replyingTo != null || _editingMessage != null;
    // Match the composer's SafeArea. viewPadding retains the navigation-bar
    // inset behind an open keyboard and would reserve that space a second time.
    final bottomSafeGap = math.max(
      MediaQuery.paddingOf(mediaContext).bottom,
      12.0,
    );
    const composerControlSize = 42.0;
    final composerReservedHeight =
        8.0 + composerControlSize + bottomSafeGap + 12.0;
    final listBottomPadding =
        composerReservedHeight + (hasComposerContext ? 50.0 : 0.0);
    final showDirectConversationStart =
        _messages.isEmpty &&
        !_loadingInitial &&
        _showsDirectConversationEncryptionNotice;
    final Widget messageList = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focusNode.hasFocus ? _dismissComposerKeyboard : null,
      child: ListView.builder(
        key: const ValueKey<String>('chat-message-list'),
        controller: _scrollCtrl,
        // Render messages chronologically from the top. The composer remains
        // outside this list at the bottom of the chat screen.
        reverse: false,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        padding: EdgeInsets.only(
          top: listTopPadding,
          bottom: listBottomPadding,
        ),
        physics: const ClampingScrollPhysics(),
        itemCount: _messages.length,
        findChildIndexCallback: _findMessageChildIndex,
        itemBuilder: (context, index) {
          return _buildMessageListItem(index, index, mediaContext: context);
        },
      ),
    );

    return Column(
      children: [
        Expanded(
          child: Stack(
            key: _messageViewportKey,
            children: [
              NotificationListener<ScrollNotification>(
                key: const ValueKey<String>(
                  'chat-message-scroll-notifications',
                ),
                onNotification: _handleMessageScrollNotification,
                // Selection must never change the reversed list's viewport or
                // padding. An earlier selection-only SafeArea added 12dp at
                // the physical bottom, which moved every bottom-anchored
                // message vertically when selection began.
                child: messageList,
              ),
              if (_messages.isEmpty && _loadingInitial)
                Positioned.fill(
                  child: _buildInitialTimelineSkeleton(
                    topInset: topInset,
                    bottomPadding: listBottomPadding,
                    mediaContext: mediaContext,
                  ),
                )
              else if (showDirectConversationStart)
                Positioned(
                  left: 0,
                  right: 0,
                  top: listTopPadding + 18,
                  child: IgnorePointer(
                    child: _buildDirectConversationStartNotice(
                      topInset: 0,
                    ),
                  ),
                )
              else if (_messages.isEmpty && !_loadingInitial)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(top: topInset),
                      child: Center(
                        child: Text(
                          'No messages yet.\nSay hello!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: topInset + 9,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    reverseDuration: const Duration(milliseconds: 130),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.94,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _showOlderLoadingIndicator
                        ? _buildOlderHistoryLoadingIndicator()
                        : const SizedBox.shrink(
                            key: ValueKey<String>(
                              'older-history-loading-hidden',
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOlderHistoryLoadingIndicator() {
    return Center(
      key: const ValueKey<String>('older-history-loading-visible'),
      child: Semantics(
        liveRegion: true,
        label: 'Loading earlier messages',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF171A20).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: WrytteColors.primary,
                    backgroundColor: Color(0xFF343A44),
                  ),
                ),
                SizedBox(width: 9),
                Text(
                  'Loading earlier messages',
                  style: TextStyle(
                    color: WrytteColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialTimelineSkeleton({
    required double topInset,
    required double bottomPadding,
    required BuildContext mediaContext,
  }) {
    const bubbleSpecs = <({bool mine, double width, double height})>[
      (mine: true, width: .54, height: 42),
      (mine: false, width: .68, height: 58),
      (mine: false, width: .43, height: 38),
      (mine: true, width: .62, height: 52),
      (mine: false, width: .56, height: 44),
      (mine: true, width: .38, height: 36),
    ];

    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: 'Loading messages',
        child: RepaintBoundary(
          child: ListView.separated(
            key: const ValueKey<String>('initial-message-skeleton'),
            reverse: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              18,
              topInset + 24,
              18,
              bottomPadding + 18,
            ),
            itemCount: bubbleSpecs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final spec = bubbleSpecs[index];
              final width = MediaQuery.sizeOf(mediaContext).width * spec.width;
              return Align(
                alignment: spec.mine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: width,
                  height: spec.height,
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
                  decoration: BoxDecoration(
                    color: spec.mine
                        ? WrytteColors.primary.withValues(alpha: .13)
                        : const Color(0xFF1B1E24),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .035),
                      width: .7,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: FractionallySizedBox(
                      widthFactor: index.isEven ? .72 : .84,
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: .035),
                              Colors.white.withValues(alpha: .105),
                              Colors.white.withValues(alpha: .035),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
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
  }

  int? _findMessageChildIndex(Key key) {
    if (key is! ValueKey<String>) return null;
    const prefix = 'chat-message-row:';
    final value = key.value;
    if (!value.startsWith(prefix)) return null;
    final messageId = value.substring(prefix.length);
    final chronologicalIndex = _messages.indexWhere(
      (message) =>
          message.id == messageId ||
          _messagePopAnimationRowIds[message.id] == messageId,
    );
    if (chronologicalIndex < 0) return null;
    return ChatTimelineCoordinates.builderIndex(
      chronologicalIndex: chronologicalIndex,
      messageCount: _messages.length,
    );
  }

  Widget _buildDirectConversationStartNotice({required double topInset}) {
    return Padding(
      padding: EdgeInsets.only(
        top: topInset,
        left: 20,
        right: 20,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildConversationStartDatePill(),
            const SizedBox(height: _directConversationDateEncryptionGap),
            _buildConversationEncryptionNotice(),
          ],
        ),
      ),
    );
  }

  bool get _showsDirectConversationEncryptionNotice =>
      !_isGroupChat &&
      !_isSelfConversation &&
      !_isReadOnlySuggestedGroup &&
      !_isDeletedConversation;

  Widget _buildConversationStartDatePill() {
    return _buildSharedDateChip(label: _formatDateDivider(DateTime.now()));
  }

  Widget _buildConversationEncryptionNotice() {
    const encryptionFontSize = 14.0;
    const encryptionLineHeight = 1.2;
    final encryptionTextColor = Colors.white.withValues(alpha: 0.52);
    final encryptionTextStyle = TextStyle(
      color: encryptionTextColor,
      fontSize: encryptionFontSize,
      fontWeight: FontWeight.w400,
      height: encryptionLineHeight,
    );

    return Semantics(
      key: const ValueKey('conversation-encryption-notice'),
      label: 'Private messages and calls are end-to-end encrypted.',
      child: ExcludeSemantics(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: Text.rich(
                TextSpan(
                  style: encryptionTextStyle,
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: wrytteSvgAssetIcon(
                          assetPath: 'assets/svg/boxicons--lock-filled.svg',
                          canvas: 13,
                          color: encryptionTextColor,
                          offset: Offset.zero,
                        ),
                      ),
                    ),
                    const TextSpan(text: 'Private messages and calls are\n'),
                    const TextSpan(text: 'end-to-end encrypted.'),
                  ],
                ),
                textAlign: TextAlign.center,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewMessagesBadge() {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    final label = _pendingNewMessages > 99 ? '99+' : '$_pendingNewMessages';
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    const sidePadding = 6.0;
    final diameter = math.max(22.0, painter.width + sidePadding * 2);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: WrytteColors.primary,
        shape: BoxShape.circle,
      ),
      child: Text(label, textAlign: TextAlign.center, style: style),
    );
  }

  Widget _buildScrollToBottomIndicator() {
    if (_messages.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: _nearBottom,
      child: AnimatedOpacity(
        opacity: _nearBottom ? 0 : 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: _nearBottom ? 0.55 : 1,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutBack,
          child: AnimatedSlide(
            offset: _nearBottom ? const Offset(0, 1) : Offset.zero,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: Semantics(
              button: true,
              label: _pendingNewMessages > 0
                  ? '$_pendingNewMessages new messages, scroll to bottom'
                  : 'Scroll to bottom',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _scrollToBottom,
                      borderRadius: BorderRadius.circular(21),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(21),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: DecoratedBox(
                            decoration: wrytteGlassDecoration(radius: 21),
                            child: SizedBox.square(
                              dimension: 42,
                              child: Center(
                                child: RotatedBox(
                                  quarterTurns: -1,
                                  child: wrytteSvgAssetIcon(
                                    assetPath:
                                        'assets/svg/ic--round-arrow-back-ios.svg',
                                    canvas: 28,
                                    color: _chatIconColor,
                                    scale: 1,
                                    offset: Offset.zero,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_pendingNewMessages > 0)
                    Positioned(
                      top: -13,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _buildNewMessagesBadge(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageListItem(
    int msgIndex,
    int visualIndex, {
    required BuildContext mediaContext,
  }) {
    final msg = _messages[msgIndex];
    final rowId = _messagePopAnimationRowIds[msg.id] ?? msg.id;
    if (msg.isDeleted && !_deletingMessageIds.contains(msg.id)) {
      return SizedBox.shrink(key: ValueKey<String>('chat-message-row:$rowId'));
    }
    final albumMessages = _imageAlbumForIndex(msgIndex);
    if (_isImageAlbumFollower(msgIndex)) {
      return SizedBox.shrink(key: ValueKey<String>('chat-message-row:$rowId'));
    }
    final isMine = _isMine(msg);
    final previousChronological = _previousVisibleMessage(msgIndex);
    final albumLastIndex = albumMessages.length > 1
        ? _messages.lastIndexWhere(
            (message) => message.mediaGroupId == msg.mediaGroupId,
          )
        : msgIndex;
    final nextChronological = _nextVisibleMessage(albumLastIndex);
    final showDate =
        previousChronological == null ||
        !_isSameDay(previousChronological.timestamp, msg.timestamp);
    final joinsPrevious =
        previousChronological != null &&
        _sameBubbleAuthor(previousChronological, msg) &&
        _isSameDay(previousChronological.timestamp, msg.timestamp);
    final joinsNext =
        nextChronological != null &&
        _sameBubbleAuthor(nextChronological, msg) &&
        _isSameDay(nextChronological.timestamp, msg.timestamp);
    final effectiveAttachmentType = _effectiveAttachmentType(msg);
    final ambientProgress = _messages.length <= 1
        ? 0.0
        : msgIndex / (_messages.length - 1);
    final selectionMode = _selectedMessageIds.isNotEmpty;
    final isSelected = _selectedMessageIds.contains(msg.id);
    final isRemoving = _deletingMessageIds.contains(msg.id);
    final isHighlightedRow =
        _highlightedMessageId == msg.id ||
        albumMessages.any((message) => _highlightedMessageId == message.id);

    final messageRow = Column(
      key: ValueKey<String>('chat-message-row:$rowId'),
      children: [
        if (showDate)
          _buildDateDivider(
            day: msg.timestamp,
            label: _formatDateDivider(msg.timestamp),
            bottomPadding:
                msgIndex == 0 && _showsDirectConversationEncryptionNotice
                ? _directConversationDateEncryptionGap
                : null,
          ),
        if (msgIndex == 0 && _showsDirectConversationEncryptionNotice)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              0,
              20,
              _directConversationFirstMessageGap,
            ),
            child: _buildConversationEncryptionNotice(),
          ),
        _DateViewportMarker(
          id: msg.id,
          day: msg.timestamp,
          kind: _DateViewportMarkerKind.message,
          onRegister: _registerDateMarker,
          onUnregister: _unregisterDateMarker,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: GestureDetector(
              key: ValueKey(msg.id),
              behavior: HitTestBehavior.opaque,
              onTap: selectionMode
                  ? () => _toggleMessageSelection(msg.id)
                  : null,
              onLongPressStart: selectionMode
                  ? null
                  : (_) => unawaited(_showMessageActions(msg)),
              onSecondaryTapDown: selectionMode
                  ? null
                  : (_) => unawaited(
                      _showMessageActions(msg, longPressFeedback: false),
                    ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                color: isSelected
                    ? WrytteColors.primary.withValues(alpha: 0.13)
                    : Colors.transparent,
                child: Stack(
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: MediaQuery.disableAnimationsOf(mediaContext)
                          ? Duration.zero
                          : Duration(milliseconds: selectionMode ? 110 : 160),
                      curve: Curves.easeOutCubic,
                      tween: Tween<double>(
                        // Only incoming bubbles need to vacate the selector
                        // lane. Outgoing bubbles retain their chat alignment.
                        end: selectionMode && !isMine ? 38 : 0,
                      ),
                      builder: (context, shift, child) {
                        final directionalShift =
                            Directionality.of(context) == TextDirection.rtl
                            ? -shift
                            : shift;
                        // A paint-only translation preserves the bubble's
                        // original constraints, wrapping and row height. Using
                        // padding here makes messages reflow/drop vertically
                        // before they move aside.
                        return Transform.translate(
                          offset: Offset(directionalShift, 0),
                          transformHitTests: true,
                          child: child,
                        );
                      },
                      child: _SwipeMessageAction(
                        key: ValueKey('swipe-message-action-${msg.id}'),
                        messageId: msg.id,
                        coordinator: _messageSwipeCoordinator,
                        enabled:
                            !selectionMode && _contextMenuMessageId != msg.id,
                        onReply: () => _replyToMessageFromSwipe(msg),
                        onForward: () => _forwardMessageFromSwipe(msg),
                        child: AnimatedScale(
                          scale: isHighlightedRow ? 1.01 : 1.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Stack(
                            children: [
                              _buildGroupAwareMessageBubble(
                                msg: msg,
                                albumMessages: albumMessages,
                                isMine: isMine,
                                showTail: !joinsNext,
                                showGroupAvatar:
                                    _isGroupChat && !isMine && !joinsNext,
                                effectiveAttachmentType:
                                    effectiveAttachmentType,
                                ambientProgress: ambientProgress,
                                joinsPrevious: joinsPrevious,
                                joinsNext: joinsNext,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isHighlightedRow)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(
                              'message-highlight-${msg.id}-$_highlightPulse',
                            ),
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 780),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              final peak = value < 0.5
                                  ? Curves.easeOut.transform(value * 2)
                                  : 1 -
                                        Curves.easeIn.transform(
                                          (value - 0.5) * 2,
                                        );
                              return ColoredBox(
                                color: const Color(
                                  0xFF2978FF,
                                ).withValues(alpha: 0.20 * peak),
                              );
                            },
                          ),
                        ),
                      ),
                    if (selectionMode)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 2,
                              ),
                              child: AnimatedSwitcher(
                                duration:
                                    MediaQuery.disableAnimationsOf(mediaContext)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: .82,
                                          end: 1,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: isSelected
                                    ? const SizedBox.square(
                                        key: ValueKey<String>(
                                          'message-selection-selected',
                                        ),
                                        dimension: 24,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: WrytteColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.check_rounded,
                                              size: 17,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      )
                                    : SizedBox.square(
                                        key: const ValueKey<String>(
                                          'message-selection-unselected',
                                        ),
                                        dimension: 24,
                                        child: WrytteGlassSurface(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          blur: 18,
                                          decoration: const BoxDecoration(
                                            color: Color(0xB31B1E24),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const SizedBox.expand(),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInCubic,
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: isRemoving ? 0 : 1,
        child: AnimatedOpacity(
          opacity: isRemoving ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInCubic,
          child: AnimatedScale(
            scale: isRemoving ? 0.92 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInCubic,
            child: messageRow,
          ),
        ),
      ),
    );
  }
}
