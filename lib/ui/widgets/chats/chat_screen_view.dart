part of '../../screens/chats/chat_screen.dart';

extension _ChatScreenView on _ChatScreenState {
  bool get _isBlockedByCurrentUser {
    final peer = _profilePeerId()?.trim() ?? widget.receiverId.trim();
    if (peer.isEmpty || _isGroupChat) return false;
    // The unblock card belongs only to the blocker. If this peer blocked the
    // current user, never present a misleading "Unblock" action even when a
    // stale/independent blocklist entry exists for the same conversation.
    if (BlockStateService.instance.isBlockedByBbb(
      peer,
      roomId: _resolvedConversationId ?? widget.conversationId,
    )) {
      return false;
    }
    return BlockStateService.instance.hasExplicitlyBlockedUser(peer);
  }

  void _onChatBlockStateChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildUnblockBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(48, 12, 48, 12),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _unblockCurrentPeer,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF0D0F12),
            side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            shape: const StadiumBorder(),
          ),
          child: const Text(
            'Unblock',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
          ),
        ),
      ),
    );
  }

  Future<void> _unblockCurrentPeer() async {
    final peer = _profilePeerId()?.trim() ?? widget.receiverId.trim();
    final roomId = (_resolvedConversationId ?? widget.conversationId).trim();
    if (peer.isEmpty || roomId.isEmpty) return;
    await BlockStateService.instance.removeBlock(userId: peer, roomId: roomId);
  }

  bool get _composerKeyboardIsVisible =>
      _focusNode.hasFocus || View.of(context).viewInsets.bottom > 0;

  void _dismissComposerKeyboard() {
    if (_focusNode.hasFocus) _focusNode.unfocus();
  }

  Widget _buildChatScreenView(BuildContext context) {
    final controlMetrics = WrytteChatControlMetrics.of(context);
    final selectionMode = _selectedMessageIds.isNotEmpty;
    final visiblePinnedEventIds = _visiblePinnedEventIds;
    final pinnedStripSignature = visiblePinnedEventIds.join('\u0000');
    final showPinnedStrip =
        visiblePinnedEventIds.isNotEmpty &&
        _dismissedPinnedStripSignature != pinnedStripSignature;
    final activeFileAudioPlayback = _activeFileAudioPlayback;
    final showJoinedPinnedAudio =
        showPinnedStrip && activeFileAudioPlayback != null;
    final double statusBarH = MediaQuery.viewPaddingOf(context).top;
    final double appBarH = statusBarH + controlMetrics.headerContentHeight;
    final double pillHeight = controlMetrics.capsuleHeight;
    final double barContentHeight = controlMetrics.headerContentHeight;

    final double pillTop = statusBarH + ((barContentHeight - pillHeight) / 2.0);

    final double pillBottom = pillTop + pillHeight;
    final double headerScrimHeight = pillBottom + 24.0;

    // Start the timeline below the fixed pin strip so its initial order stays
    // pin -> date -> encryption -> messages. The timeline remains scrollable
    // behind both fixed overlays, while the floating date sticks below the pin.
    final pinnedTopInset = showJoinedPinnedAudio
        ? _joinedPinnedAudioExtent
        : showPinnedStrip
        ? _pinnedStripExtent
        : 0.0;
    final fileAudioPlayerInset =
        showJoinedPinnedAudio || activeFileAudioPlayback == null
        ? 0.0
        : _fileAudioPlayerExtent;
    final messageTopInset = appBarH + pinnedTopInset + fileAudioPlayerInset;
    final floatingDateTop = messageTopInset + _floatingDateTopGap;
    if ((_floatingDateTop - floatingDateTop).abs() > 0.01) {
      _floatingDateTop = floatingDateTop;
      if (_floatingDateScrollActive || _floatingDatePinnedAtVisualTop) {
        _scheduleFloatingDateMeasurement();
      }
    }

    return ListenableBuilder(
      listenable: _focusNode,
      child: Scaffold(
        backgroundColor: WrytteColors.background,
        extendBody: true,
        resizeToAvoidBottomInset: true,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Color(0x00000000),
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0x00000000),
            systemNavigationBarDividerColor: Color(0x00000000),
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarContrastEnforced: false,
          ),
          child: ScrollConfiguration(
            behavior: const _ChatScrollBehavior(),
            child: Stack(
              key: _screenStackKey,
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: WrytteColors.background),
                ),
                RepaintBoundary(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Builder(
                          builder: (timelineContext) => _buildMessageList(
                            messageTopInset,
                            mediaContext: timelineContext,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          reverseDuration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.bottomCenter,
                                clipBehavior: Clip.none,
                                children: [
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: AnimatedBuilder(
                                  animation: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.18),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                  builder: (context, child) => Align(
                                    alignment: Alignment.bottomCenter,
                                    heightFactor: animation.value,
                                    child: child,
                                  ),
                                ),
                              ),
                          child: KeyedSubtree(
                            key: const ValueKey('selection-composer-visible'),
                            child: _isBlockedByCurrentUser
                                ? _buildUnblockBar()
                                : _isReadOnlySuggestedGroup
                                ? _buildJoinGroupBottomBar()
                                : _isDeletedConversation
                                ? _buildDeletedGroupBottomBar()
                                : MigratedMessageInputField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    onSend: _send,
                                    replySender: _replyingTo == null
                                        ? null
                                        : _isMine(_replyingTo!)
                                        ? 'You'
                                        : _resolvedHeaderName,
                                    replyPreview: _replyingTo == null
                                        ? null
                                        : _replyPreviewForMessage(
                                                _replyingTo!,
                                              ) ??
                                              'Message',
                                    onCancelReply: _replyingTo == null
                                        ? null
                                        : () => _setChatState(
                                            () => _replyingTo = null,
                                          ),
                                    isEditing: _editingMessage != null,
                                    editingMediaSource:
                                        _editingMessage != null &&
                                            _canEditMediaMessage(
                                              _editingMessage!,
                                            )
                                        ? _editingMessage!.attachmentUrl
                                        : null,
                                    editingMediaType:
                                        _editingMessage != null &&
                                            _canEditMediaMessage(
                                              _editingMessage!,
                                            )
                                        ? _effectiveAttachmentType(
                                            _editingMessage!,
                                          )
                                        : null,
                                    onReplaceEditingMedia:
                                        _editingMessage != null &&
                                            _canEditMediaMessage(
                                              _editingMessage!,
                                            )
                                        ? () => _promptReplaceMedia(
                                            _editingMessage!,
                                          )
                                        : null,
                                    onCancelEdit: _editingMessage == null
                                        ? null
                                        : () {
                                            _setChatState(
                                              () => _editingMessage = null,
                                            );
                                            _controller.clear();
                                          },
                                    onVoiceMessage: _sendVoiceNote,
                                    onVideoMessageRecorded: _sendVideoNote,
                                    onPickedAttachments: _sendPickedAttachments,
                                    onPickedContacts: _sendPickedContacts,
                                    attachmentRecipientLabel:
                                        _resolvedHeaderName,
                                  ),
                          ),
                        ),
                      ),
                      _ScrollToBottomPositioner(
                        child: _buildScrollToBottomIndicator(),
                      ),
                    ],
                  ),
                ),

                // Keep the lightweight privacy gradient, but avoid blurring
                // the moving chat content across a full-width live backdrop.
                _buildTelegramHeaderScrim(
                  pillBottom: pillBottom,
                  overlayHeight: headerScrimHeight,
                ),
                _buildFloatingDateOverlay(floatingDateTop),
                if (showJoinedPinnedAudio)
                  Positioned(
                    top: appBarH,
                    left: 0,
                    right: 0,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          'joined-${activeFileAudioPlayback.id}',
                        ),
                        child: _buildJoinedPinnedAudioSurface(
                          pinnedEventIds: visiblePinnedEventIds,
                          pinnedStripSignature: pinnedStripSignature,
                          playback: activeFileAudioPlayback,
                        ),
                      ),
                    ),
                  ),
                if (showPinnedStrip && !showJoinedPinnedAudio)
                  Positioned(
                    top: appBarH,
                    left: 0,
                    right: 0,
                    child: PinnedEventsStrip(
                      pinnedEventIds: visiblePinnedEventIds,
                      events: _messages,
                      onOpenEvent: (_) {
                        unawaited(
                          _openPinnedMessagesPage(visiblePinnedEventIds),
                        );
                      },
                      onDismiss: () {
                        // The close control represents removing the pin, not
                        // merely hiding the strip locally. Unpin the complete
                        // represented set so it cannot reappear after the next
                        // room refresh.
                        _setChatState(
                          () => _dismissedPinnedStripSignature = null,
                        );
                        unawaited(
                          _unpinAllPinnedMessages(visiblePinnedEventIds),
                        );
                      },
                      onOpenList: () {
                        unawaited(
                          _openPinnedMessagesPage(visiblePinnedEventIds),
                        );
                      },
                    ),
                  ),
                if (activeFileAudioPlayback != null && !showJoinedPinnedAudio)
                  Positioned(
                    top: appBarH + pinnedTopInset,
                    left: 0,
                    right: 0,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey<String>(activeFileAudioPlayback.id),
                        child: _buildFileAudioPlayerStrip(
                          activeFileAudioPlayback,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    reverseDuration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(
                        selectionMode
                            ? 'message-selection-header'
                            : 'conversation-header',
                      ),
                      child: _buildAppBar(),
                    ),
                  ),
                ),

                if (_showDebug) _buildDebugOverlay(appBarH),
              ],
            ),
          ),
        ),
      ),
      builder: (context, scaffold) => PopScope(
        canPop: !_composerKeyboardIsVisible,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _composerKeyboardIsVisible) {
            _dismissComposerKeyboard();
          }
        },
        child: scaffold!,
      ),
    );
  }
}

/// Keeps the scroll-to-bottom control above the composer and keyboard.
class _ScrollToBottomPositioner extends StatelessWidget {
  const _ScrollToBottomPositioner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final bottomGap = viewPadding.bottom > 0 ? 10.0 : 12.0;
    final bottom = math.max(padding.bottom, bottomGap) + 8.0 + 42.0 + 4.0;
    return PositionedDirectional(end: 12, bottom: bottom, child: child);
  }
}
