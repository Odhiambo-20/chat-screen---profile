part of '../../screens/chats/chat_screen.dart';

extension _ChatScrollCommands on _ChatScreenState {
  void _jumpToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _isNearTimelineBottom {
    if (!_scrollCtrl.hasClients) return true;
    final position = _scrollCtrl.position;
    return ChatTimelineCoordinates.distanceFromBottom(
          pixels: position.pixels,
          maxScrollExtent: position.maxScrollExtent,
        ) <=
        80;
  }

  // ─── MESSAGE HELPERS ───────────────────────────────────────────────────────
}
