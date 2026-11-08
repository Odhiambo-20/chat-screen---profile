part of '../../../screens/chats/chat_screen.dart';

extension _ChatDateDivider on _ChatScreenState {
  Widget _buildDateDivider({
    required DateTime day,
    required String label,
    double? bottomPadding,
  }) {
    final dividerDayKey = _dayKey(day);
    return Padding(
      padding: EdgeInsets.only(
        top: _dateDividerVerticalPadding,
        bottom: bottomPadding ?? _dateDividerVerticalPadding,
      ),
      child: Center(
        child: _DateViewportMarker(
          id: dividerDayKey,
          day: day,
          kind: _DateViewportMarkerKind.divider,
          onRegister: _registerDateMarker,
          onUnregister: _unregisterDateMarker,
          child: ValueListenableBuilder<_FloatingDateVisualState>(
            valueListenable: _floatingDateVisual,
            builder: (context, visual, child) {
              final isOwnedByOverlay = visual.ownsInlineDay(dividerDayKey);
              return IgnorePointer(
                ignoring: isOwnedByOverlay,
                child: Opacity(
                  opacity: isOwnedByOverlay ? 0 : 1,
                  child: child!,
                ),
              );
            },
            child: RepaintBoundary(
              key: ValueKey('date-inline-$dividerDayKey'),
              child: _buildSharedDateChip(label: label),
            ),
          ),
        ),
      ),
    );
  }
}
