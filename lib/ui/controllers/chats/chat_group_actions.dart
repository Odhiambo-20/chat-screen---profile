part of '../../screens/chats/chat_screen.dart';

extension _ChatGroupActions on _ChatScreenState {
  String _stripMatrixReplyFallbackForDisplay(String body) {
    final candidate = body.startsWith('* > ') ? body.substring(2) : body;
    final blocks = candidate.split(RegExp(r'\r?\n\r?\n'));
    if (candidate.startsWith('> ') && blocks.length > 1) {
      return blocks.sublist(1).join('\n\n').trimLeft();
    }
    return body;
  }

  Future<void> _openGroupMemberProfile(
    String matrixUserId,
    String savedNameHint,
  ) async {
    final userId = matrixUserId.trim();
    if (userId.isEmpty || _isOwnMatrixId(userId)) return;

    final directConversationId = await ChatService().findMatrixConversationId(
      userId,
    );
    final initialAvatar = _groupMemberAvatars[userId];
    await AvatarPreloadService.warm(
      initialAvatar,
      cacheIdentity: 'user:${userId.trim().toLowerCase()}',
    );
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ProfileScreen(
              uid: userId,
              conversationId: directConversationId,
              savedNameHint: savedNameHint,
              initialAvatarUrl: initialAvatar,
            ),
      ),
    );
  }

  Future<void> _showGroupOptions() async {
    final mediaQuery = MediaQuery.of(context);
    final room = MatrixChatService.instance.getRoomById(_activeConversationId);
    final isOwner =
        room != null && MatrixChatService.instance.isGroupOwner(room);
    final items =
        _isReadOnlySuggestedGroup
            ? const [
              (Icons.link_rounded, 'Share link'),
              (Icons.report_gmailerrorred_outlined, 'Report group'),
            ]
            : isOwner
            ? const [
              (Icons.edit_outlined, 'Edit'),
              (Icons.settings_outlined, 'Settings'),
              (Icons.add_circle_outline_rounded, 'Add Story'),
            ]
            : const [
              (Icons.report_gmailerrorred_outlined, 'Report'),
              (Icons.search_rounded, 'Search'),
              (Icons.info_outline_rounded, 'Info'),
            ];
    await showMenu<void>(
      context: context,
      color: WrytteColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 240),
      position: RelativeRect.fromLTRB(
        mediaQuery.size.width - 252,
        mediaQuery.viewPadding.top + kToolbarHeight + 4,
        12,
        0,
      ),
      items:
          items
              .map(
                (item) => PopupMenuItem<void>(
                  enabled: false,
                  height: 58,
                  child: Row(
                    children: [
                      item.$2 == 'Edit'
                          ? wrytteSvgAssetIcon(
                            assetPath: 'assets/svg/Edit pencil icon.svg',
                            canvas: 24,
                            color: Colors.white54,
                          )
                          : Icon(item.$1, color: Colors.white54, size: 24),
                      const SizedBox(width: 16),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }

  // ─── APP BAR ───────────────────────────────────────────────────────────────
}
