import 'package:flutter/material.dart';

import 'package:wrytte/ui/screens/chats/chat_media_editor.dart';

/// Compatibility entry point for gallery videos.
class ChatVideoEditorView extends StatelessWidget {
  const ChatVideoEditorView({
    super.key,
    required this.path,
    this.initialCaption,
  });

  final String path;
  final String? initialCaption;

  @override
  Widget build(BuildContext context) {
    return ChatMediaEditorScreen(
      sourcePath: path,
      attachmentType: 'video',
      recipientLabel: '',
      initialCaption: initialCaption ?? '',
      selectionIndex: null,
      selectedCount: 0,
      showSelectionControl: false,
    );
  }
}
