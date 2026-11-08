/// Coordinate conversions for Wrytte's bottom-anchored, reversed chat list.
///
/// Messages stay chronological in application state. The builder reverses
/// only their visual index, which keeps message grouping and persistence
/// simple while making scroll offset zero the newest edge.
abstract final class ChatTimelineCoordinates {
  static int chronologicalIndex({
    required int builderIndex,
    required int messageCount,
  }) => messageCount - 1 - builderIndex;

  static int builderIndex({
    required int chronologicalIndex,
    required int messageCount,
  }) => messageCount - 1 - chronologicalIndex;

  static double distanceFromBottom({
    required double pixels,
    required double maxScrollExtent,
  }) => maxScrollExtent - pixels;

  static double distanceFromOldest({
    required double pixels,
    required double minScrollExtent,
  }) => pixels - minScrollExtent;

  /// Prefetch far enough ahead of the visual top to cover a sustained fast
  /// fling and normal mobile-network latency. Eight viewports remains bounded
  /// to the active chat and prevents ordinary scrolling from meeting I/O.
  static double olderHistoryPrefetchExtent({required double viewportExtent}) {
    final scaled = viewportExtent * 8;
    return scaled > 3200 ? scaled : 3200;
  }

  static double estimatedOffsetForChronologicalIndex({
    required int chronologicalIndex,
    required int messageCount,
    required double maxScrollExtent,
  }) {
    if (messageCount <= 1) return 0;
    return maxScrollExtent *
        (builderIndex(
              chronologicalIndex: chronologicalIndex,
              messageCount: messageCount,
            ) /
            (messageCount - 1));
  }
}
