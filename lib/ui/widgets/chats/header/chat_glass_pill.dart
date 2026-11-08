part of '../../../screens/chats/chat_screen.dart';

extension _ChatGlassPill on _ChatScreenState {
  Widget _glassPill({
    required double width,
    required double height,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: _buildHeaderGlassSurface(
          radius: height / 2,
          child: Center(child: child),
        ),
      ),
    );
  }
}
