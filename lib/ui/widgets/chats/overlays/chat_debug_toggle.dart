part of '../../../screens/chats/chat_screen.dart';

extension _ChatDebugToggle on _ChatScreenState {
  Widget _buildDebugToggleButton() {
    final metrics = WrytteChatControlMetrics.of(context);
    return Semantics(
      button: true,
      label: _showDebug ? 'Close chat debug panel' : 'Open chat debug panel',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setChatState(() => _showDebug = !_showDebug),
        child: Container(
          width: 36 * metrics.scale,
          height: 36 * metrics.scale,
          decoration: BoxDecoration(
            color:
                _showDebug
                    ? Colors.orangeAccent
                    : Colors.grey.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '\u{1F41B}',
            style: TextStyle(fontSize: 18 * metrics.scale),
          ),
        ),
      ),
    );
  }
}
