part of '../../../screens/chats/chat_screen.dart';

extension _ChatHeader on _ChatScreenState {
  Widget _buildTelegramHeaderScrim({
    required double pillBottom,
    required double overlayHeight,
  }) {
    const pillBottomFactors = <double>[
      0.00,
      0.07,
      0.14,
      0.21,
      0.28,
      0.35,
      0.42,
      0.49,
      0.56,
      0.63,
      0.70,
      0.77,
      0.83,
      0.89,
      0.94,
      1.00,
    ];
    final stops = <double>[
      for (final factor in pillBottomFactors)
        (pillBottom * factor) / overlayHeight,
      1.0,
    ];

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: overlayHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: stops,
              colors: const [
                Color.fromRGBO(2, 3, 5, 0.985),
                Color.fromRGBO(2, 3, 5, 0.982),
                Color.fromRGBO(3, 4, 6, 0.975),
                Color.fromRGBO(3, 4, 7, 0.960),
                Color.fromRGBO(4, 5, 8, 0.940),
                Color.fromRGBO(4, 6, 9, 0.910),
                Color.fromRGBO(5, 7, 10, 0.870),
                Color.fromRGBO(5, 7, 11, 0.820),
                Color.fromRGBO(6, 8, 12, 0.750),
                Color.fromRGBO(6, 8, 12, 0.650),
                Color.fromRGBO(6, 8, 12, 0.535),
                Color.fromRGBO(6, 8, 12, 0.400),
                Color.fromRGBO(6, 8, 12, 0.270),
                Color.fromRGBO(6, 8, 12, 0.150),
                Color.fromRGBO(6, 8, 12, 0.060),
                Color.fromRGBO(6, 8, 12, 0.0),
                Color.fromRGBO(6, 8, 12, 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderGlassSurface({
    required double radius,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(
          sigmaX: 10.0,
          sigmaY: 10.0,
          tileMode: TileMode.clamp,
        ),
        blendMode: BlendMode.srcOver,
        child: DecoratedBox(
          decoration: wrytteGlassDecoration(radius: radius),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSelectionAppBar() {
    final metrics = WrytteChatControlMetrics.of(context);
    final selectedCount = _selectedMessageIds.length;
    final naturalPillWidth =
        (6 * metrics.scale) +
        (43 * metrics.scale) +
        (4 * 43 * metrics.scale) +
        (8 * metrics.scale);
    final availablePillWidth =
        MediaQuery.sizeOf(context).width -
        (metrics.horizontalPadding * 2) -
        metrics.controlSize -
        metrics.controlGap;
    final pillWidth = naturalPillWidth
        .clamp(metrics.controlSize, availablePillWidth)
        .toDouble();

    return BackdropGroup(
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: metrics.headerContentHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.horizontalPadding,
            ),
            child: Row(
              children: [
                _glassPill(
                  width: metrics.controlSize,
                  height: metrics.controlSize,
                  child: Icon(
                    Icons.close_rounded,
                    color: _chatIconColor,
                    size: 27 * metrics.scale,
                  ),
                  onTap: _clearMessageSelection,
                ),
                SizedBox(width: metrics.controlGap),
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 190),
                  curve: Curves.easeOutCubic,
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: pillWidth,
                    height: metrics.capsuleHeight,
                    child: _buildHeaderGlassSurface(
                      radius: metrics.capsuleRadius,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          metrics.capsuleRadius,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: naturalPillWidth > availablePillWidth
                              ? const ClampingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: naturalPillWidth,
                            height: metrics.capsuleHeight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 6 * metrics.scale),
                                SizedBox(
                                  width: 43 * metrics.scale,
                                  height: metrics.capsuleHeight,
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 170),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      child: Text(
                                        '$selectedCount',
                                        key: ValueKey(selectedCount),
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: WrytteTypography
                                              .primaryFontFamily,
                                          fontSize: 17 * metrics.scale,
                                          fontWeight: FontWeight.w600,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                _selectionHeaderAction(
                                  label: 'Pin',
                                  assetPath: 'assets/svg/Pin icon .svg',
                                  iconScale: 1.02,
                                  onTap: () =>
                                      unawaited(_showSelectionPinOptions()),
                                ),
                                _selectionHeaderAction(
                                  label: 'Copy',
                                  assetPath: 'assets/svg/Copy icon.svg',
                                  iconScale: .96,
                                  onTap: () =>
                                      unawaited(_copySelectedMessages()),
                                ),
                                _selectionHeaderAction(
                                  label: 'Forward',
                                  assetPath: 'assets/svg/Forward Icon.svg',
                                  iconScale: 1.05,
                                  color: Colors.white,
                                  onTap: () =>
                                      unawaited(_forwardSelectedMessages()),
                                ),
                                _selectionHeaderAction(
                                  label: 'Delete',
                                  assetPath: 'assets/svg/Delete icon.svg',
                                  color: WrytteColors.destructive,
                                  iconScale: .98,
                                  onTap: () =>
                                      unawaited(_showSelectionDeleteOptions()),
                                ),
                                SizedBox(width: 8 * metrics.scale),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionHeaderAction({
    required String label,
    required String assetPath,
    required VoidCallback onTap,
    bool mirrorHorizontally = false,
    double iconScale = 1,
    Color color = _chatIconColor,
  }) {
    final metrics = WrytteChatControlMetrics.of(context);
    Widget icon = wrytteSvgAssetIcon(
      assetPath: assetPath,
      canvas: 24 * metrics.scale,
      color: color,
      scale: iconScale,
    );
    if (mirrorHorizontally) {
      icon = Transform.flip(flipX: true, child: icon);
    }
    return SizedBox(
      width: 43 * metrics.scale,
      height: metrics.capsuleHeight,
      child: Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: InkResponse(
            onTap: onTap,
            radius: 23 * metrics.scale,
            child: SizedBox.expand(child: Center(child: icon)),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    if (_selectedMessageIds.isNotEmpty) {
      return _buildSelectionAppBar();
    }
    final isGroupChat = _isGroupChat;
    final metrics = WrytteChatControlMetrics.of(context);
    final displayName = _resolvedHeaderName;
    final suppressPeerAvatar =
        !isGroupChat &&
        BlockStateService.instance.isRedactedForViewer(
          _profilePeerId() ?? widget.receiverId,
          roomId: _resolvedConversationId ?? widget.conversationId,
        );
    final avatarUrl = isGroupChat
        ? _stableHeaderAvatarUrl
        : _safePersonHeaderAvatar(
            _receiverProfile?.hasProfileImage == true
                ? _receiverProfile!.profileImage
                : _receiverIdentity?.avatarUrl ?? _stableHeaderAvatarUrl,
          );
    final localAvatarPath = isGroupChat
        ? null
        : _receiverProfile?.localProfileImagePath.trim().isNotEmpty == true
        ? _receiverProfile!.localProfileImagePath.trim()
        : widget.localAvatarPath?.trim().isNotEmpty == true
        ? widget.localAvatarPath!.trim()
        : null;
    return BackdropGroup(
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: metrics.headerContentHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.horizontalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _glassPill(
                  width: metrics.controlSize,
                  height: metrics.controlSize,
                  child: wrytteSvgAssetIcon(
                    assetPath: 'assets/svg/ic--round-arrow-back-ios.svg',
                    canvas: _chatBackCanvas * metrics.scale,
                    color: _chatIconColor,
                    scale: _chatBackOpticalScale,
                    offset: _chatBackOffset,
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                SizedBox(width: metrics.controlGap),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      if (isGroupChat) {
                        if (_isDeletedConversation) return;
                        final groupResult = await Navigator.push<Object?>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupProfileScreen(
                              roomId:
                                  _resolvedConversationId ??
                                  widget.conversationId,
                              groupName: displayName,
                              avatarUrl: avatarUrl,
                              alias: widget.groupAlias,
                              initialDescription: widget.groupDescription,
                              initialMemberCount: widget.initialMemberCount,
                              initiallyJoined: !_isReadOnlySuggestedGroup,
                            ),
                          ),
                        );
                        if (groupResult is GroupExitRequest && mounted) {
                          Navigator.pop(context, groupResult);
                        }
                        return;
                      }
                      if (_receiverIdentity == null) {
                        await _seedReceiverIdentityFromCache();
                        if (!mounted) return;
                      }
                      final profileUid = _profilePeerId();
                      final cachedPublicProfile = profileUid == null
                          ? null
                          : UserProfileService.instance
                                .cachedPublicProfileByUid(profileUid);
                      final cachedMatrixProfile = profileUid == null
                          ? null
                          : MatrixProfileService.instance.cachedProfile(
                              profileUid,
                            );
                      final cachedProfileName = _cleanDisplayName(
                        cachedPublicProfile?.displayName ??
                            cachedMatrixProfile?.displayName,
                      );
                      final initialProfileName = _receiverIsSavedContact
                          ? _resolvedHeaderName
                          : _cleanDisplayName(
                              _receiverIdentity?.profileName,
                            ).isNotEmpty
                          ? _cleanDisplayName(_receiverIdentity?.profileName)
                          : cachedProfileName.isNotEmpty
                          ? cachedProfileName
                          : null;
                      final profileResult = await Navigator.push<Object?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            uid: profileUid,
                            conversationId:
                                _resolvedConversationId ??
                                widget.conversationId,
                            savedNameHint: _receiverIsSavedContact
                                ? _resolvedHeaderName
                                : null,
                            initialProfileName: initialProfileName,
                            initialProfile:
                                _receiverProfile ?? cachedPublicProfile,
                            initialIdentity: _receiverIdentity,
                            contactStatus: _receiverIsSavedContact
                                ? ProfileContactStatus.saved
                                : ProfileContactStatus.unsaved,
                            initialAvatarUrl: _safePersonHeaderAvatar(
                              _receiverProfile?.hasProfileImage == true
                                  ? _receiverProfile!.profileImage
                                  : _receiverIdentity?.avatarUrl ?? avatarUrl,
                            ),
                            initialLocalAvatarPath: localAvatarPath,
                          ),
                        ),
                      );
                      if (mounted) {
                        if (profileResult == true) {
                          // The room stream intentionally ignores transient
                          // empty snapshots while a chat is open. Clearing
                          // from ProfileScreen is an explicit empty snapshot,
                          // so remove the rendered timeline directly.
                          _setChatState(() {
                            _messages.clear();
                            _initialStreamBuffer.clear();
                          });
                        }
                        _loadReceiverProfile();
                      }
                    },
                    child: SizedBox(
                      height: metrics.capsuleHeight,
                      child: _buildHeaderGlassSurface(
                        radius: metrics.capsuleRadius,
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: metrics.capsuleHeight,
                              child: ClipOval(
                                child: UserAvatar(
                                  size: metrics.capsuleHeight,
                                  imageUrl: suppressPeerAvatar
                                      ? null
                                      : avatarUrl,
                                  cacheIdentity: isGroupChat
                                      ? MatrixChatService.instance
                                            .roomProfileCacheIdentity(
                                              accountId: widget.currentUserId,
                                              roomId:
                                                  _resolvedConversationId ??
                                                  widget.conversationId,
                                              avatarUrl: avatarUrl,
                                              room: MatrixChatService.instance
                                                  .getRoomById(
                                                    _resolvedConversationId ??
                                                        widget.conversationId,
                                                  ),
                                              profileVersion: widget
                                                  .initialRoomProfileVersion,
                                            )
                                      : 'user:${(_profilePeerId() ?? widget.receiverId).trim().toLowerCase()}',
                                  localImagePath: suppressPeerAvatar
                                      ? null
                                      : localAvatarPath,
                                  name: displayName,
                                  isDeleted: _isDeletedConversation,
                                  suppressAvatar: suppressPeerAvatar,
                                ),
                              ),
                            ),
                            SizedBox(width: 10 * metrics.scale),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  SizedBox(height: 3 * metrics.scale),
                                  Text(
                                    isGroupChat
                                        ? _groupSubtitle()
                                        : _directPresenceLabel(),
                                    style: TextStyle(
                                      color: const Color(0xFFB0B3B8),
                                      fontSize: 13,
                                      height: 1,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 4 * metrics.scale),
                            const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: metrics.controlGap),
                if (isGroupChat)
                  _glassPill(
                    width: metrics.controlSize,
                    height: metrics.controlSize,
                    child: Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 20 * metrics.scale,
                    ),
                    onTap: _showGroupOptions,
                  )
                else ...[
                  _glassPill(
                    width: metrics.controlSize,
                    height: metrics.controlSize,
                    child: Transform.translate(
                      offset: _chatCallCompositionOffset * metrics.scale,
                      child: SizedBox(
                        width: _chatCallCompositionWidth * metrics.scale,
                        height: _chatCallCompositionHeight * metrics.scale,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: _chatCallPhoneLeft * metrics.scale,
                              top: _chatCallPhoneTop * metrics.scale,
                              child: wrytteSvgAssetIcon(
                                assetPath: 'assets/svg/solar--phone-linear.svg',
                                canvas: _chatPhoneCanvas * metrics.scale,
                                color: _chatIconColor,
                                scale: _chatPhoneOpticalScale,
                              ),
                            ),
                            Positioned(
                              left: _chatCallDropdownLeft * metrics.scale,
                              top: _chatCallDropdownTop * metrics.scale,
                              child: Transform.rotate(
                                angle: -4 * 3.141592653589793 / 180,
                                child: wrytteSvgAssetIcon(
                                  assetPath: 'assets/svg/Chevron down icon.svg',
                                  canvas: _chatDropdownCanvas * metrics.scale,
                                  color: Colors.white,
                                  scale: _chatCallDropdownOpticalScale,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    onTap: () => _startCall(CallType.voice),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _directPresenceLabel() {
    final peerId = _profilePeerId()?.trim() ?? '';
    if (peerId.isEmpty) return '';

    // Presence is private profile data. A peer who blocked the current user
    // must not leak online/last-seen information through the chat header.
    if (BlockStateService.instance.isRedactedForViewer(
      peerId,
      roomId: _resolvedConversationId ?? widget.conversationId,
    )) {
      return '';
    }

    final visibility =
        _receiverProfile?.visibilitySettings[WrytteProfile
            .onlineVisibilitySetting] ??
        'everyone';
    final canView = MatrixPresenceVisibility.canView(
      visibility,
      isContact: _receiverIsSavedContact,
      // Approved users are represented by the current saved/accepted-contact
      // relationship in this workspace.
      isApproved: _receiverIsSavedContact,
    );
    if (!canView) return '';

    final clientService = MatrixClientService.instance;
    if (!clientService.isInitialized) {
      debugPrint('[Matrix.presence] label_empty reason=client_not_initialized peer="$peerId"');
      return '';
    }
    final presence = clientService.client.presences[peerId];
    if (presence == null) {
      debugPrint('[Matrix.presence] label_empty reason=no_cached_presence peer="$peerId"');
      return '';
    }
    final label = MatrixPresenceFormatter.label(
      online: presence.presence == mx.PresenceType.online,
      lastSeen: presence.lastActiveTimestamp,
    );
    debugPrint(
      '[Matrix.presence] label peer="$peerId" value="$label" '
      'state="${presence.presence.name}" '
      'currently_active="${presence.currentlyActive}" '
      'last_seen="${presence.lastActiveTimestamp}"',
    );
    return label;
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────
}
