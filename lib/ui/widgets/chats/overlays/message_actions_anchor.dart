import 'package:flutter/material.dart';

/// Keeps the message's layout slot while its real, stateful content is promoted
/// to the message-actions route. No image capture or second media player.
class MessageActionsAnchor extends StatefulWidget {
  const MessageActionsAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<MessageActionsAnchor> createState() => MessageActionsAnchorState();
}

class MessageActionsAnchorState extends State<MessageActionsAnchor> {
  final GlobalKey _contentKey = GlobalKey(
    debugLabel: 'message-actions-content',
  );
  MessageActionsSelection? _selection;

  MessageActionsSelection lift() {
    if (_selection != null) return _selection!;
    final box = context.findRenderObject()! as RenderBox;
    final size = box.size;
    final content = InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: MediaQuery.of(context),
        child: Directionality(
          textDirection: Directionality.of(context),
          child: KeyedSubtree(key: _contentKey, child: widget.child),
        ),
      ),
    );
    final selection = MessageActionsSelection._(
      rect: box.localToGlobal(Offset.zero) & size,
      content: content,
      onRelease: () {
        if (mounted) setState(() => _selection = null);
      },
    );
    // The caller pushes the route synchronously, so this GlobalKey is moved
    // (not duplicated or disposed) during the same Flutter build frame.
    setState(() => _selection = selection);
    return selection;
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return RepaintBoundary(
      child:
          selection == null
              ? KeyedSubtree(key: _contentKey, child: widget.child)
              : SizedBox.fromSize(size: selection.rect.size),
    );
  }
}

/// A single-owner transfer of the live bubble into the foreground route.
class MessageActionsSelection extends ChangeNotifier {
  MessageActionsSelection._({
    required this.rect,
    required Widget content,
    required VoidCallback onRelease,
  }) : _content = content,
       _onRelease = onRelease;

  final Rect rect;
  final Widget _content;
  final VoidCallback _onRelease;
  bool _active = true;

  void release() {
    if (!_active) return;
    _active = false;
    _onRelease();
    notifyListeners();
  }

  Widget buildPreview() {
    return ListenableBuilder(
      listenable: this,
      builder:
          (context, child) =>
              _active
                  ? SizedBox.fromSize(size: rect.size, child: _content)
                  : const SizedBox.shrink(),
    );
  }
}
