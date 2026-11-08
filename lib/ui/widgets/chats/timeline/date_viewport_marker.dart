part of '../../../screens/chats/chat_screen.dart';

class _DateViewportMarker extends StatefulWidget {
  final String id;
  final DateTime day;
  final _DateViewportMarkerKind kind;
  final ValueChanged<_DateViewportMarkerState> onRegister;
  final ValueChanged<_DateViewportMarkerState> onUnregister;
  final Widget child;

  const _DateViewportMarker({
    required this.id,
    required this.day,
    required this.kind,
    required this.onRegister,
    required this.onUnregister,
    required this.child,
  });

  @override
  State<_DateViewportMarker> createState() => _DateViewportMarkerState();
}

class _DateViewportMarkerState extends State<_DateViewportMarker> {
  String get id => widget.id;
  DateTime get day => widget.day;
  _DateViewportMarkerKind get kind => widget.kind;

  String get dayKey {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final calendarDay = day.day.toString().padLeft(2, '0');
    return '$year-$month-$calendarDay';
  }

  @override
  void initState() {
    super.initState();
    assert(dayKey.isNotEmpty);
    widget.onRegister(this);
  }

  @override
  void didUpdateWidget(covariant _DateViewportMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.id != widget.id ||
        oldWidget.kind != widget.kind ||
        oldWidget.day.year != widget.day.year ||
        oldWidget.day.month != widget.day.month ||
        oldWidget.day.day != widget.day.day ||
        oldWidget.onRegister != widget.onRegister ||
        oldWidget.onUnregister != widget.onUnregister;
    if (!identityChanged) return;
    oldWidget.onUnregister(this);
    widget.onRegister(this);
  }

  @override
  void dispose() {
    widget.onUnregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
