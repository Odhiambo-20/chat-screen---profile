part of '../../../screens/chats/chat_screen.dart';

extension _ChatGroupMembershipBars on _ChatScreenState {
  Widget _buildJoinGroupBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _joiningSuggestedGroup ? null : _joinSuggestedGroup,
            style: FilledButton.styleFrom(
              backgroundColor: WrytteColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: WrytteColors.primary.withValues(
                alpha: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child:
                _joiningSuggestedGroup
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Text(
                      'Join',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeletedGroupBottomBar() {
    final groupName =
        _resolvedHeaderName.trim().isNotEmpty
            ? _resolvedHeaderName.trim()
            : widget.title.trim().isNotEmpty
            ? widget.title.trim()
            : 'This';
    final groupLabel =
        groupName.toLowerCase().endsWith('group')
            ? groupName
            : '$groupName group';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 62),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF15181D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                color: Color(0xFF9A9CA3),
                size: 20,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '$groupLabel\nhas been deleted',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9A9CA3),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _joinSuggestedGroup() async {
    if (_joiningSuggestedGroup) return;
    _setChatState(() => _joiningSuggestedGroup = true);
    try {
      final room = await MatrixChatService.instance.joinGroup(
        widget.groupAlias?.trim().isNotEmpty == true
            ? widget.groupAlias!
            : _activeConversationId,
      );
      if (room != null) {
        _resolvedConversationId = room.id;
      }
      await _chat.saveJoinedGroupShell(
        roomId: room?.id ?? _activeConversationId,
        name: _resolvedHeaderName,
        avatarUrl: _stableHeaderAvatarUrl,
      );
      if (room != null) {
        await _chat.fetchConversations();
        unawaited(_loadGroupMemberProfiles(room.id));
      }
      if (!mounted) return;
      _setChatState(() {
        _joinedSuggestedGroup = true;
        _joiningSuggestedGroup = false;
      });
    } catch (e) {
      if (!mounted) return;
      _setChatState(() => _joiningSuggestedGroup = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not join group: $e')));
    }
  }
}
