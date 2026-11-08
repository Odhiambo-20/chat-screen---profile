import 'dart:ui';

/// The measured position of a message or date divider in the chat viewport.
class StickyDateMarkerGeometry {
  final DateTime day;
  final String dayKey;
  final Rect rect;

  const StickyDateMarkerGeometry({
    required this.day,
    required this.dayKey,
    required this.rect,
  });
}

/// A complete, frame-local description of the sticky date chip.
class StickyDateLayout {
  final DateTime activeDay;
  final String activeDayKey;
  final DateTime outgoingDay;
  final String outgoingDayKey;
  final double outgoingOffsetY;
  final DateTime? incomingDay;
  final String? incomingDayKey;
  final double incomingOffsetY;

  /// Canonical progress from the day above a boundary to the day below it.
  /// This is measured from divider geometry, not advanced with time.
  final double transitionProgress;

  const StickyDateLayout({
    required this.activeDay,
    required this.activeDayKey,
    required this.outgoingDay,
    required this.outgoingDayKey,
    required this.outgoingOffsetY,
    this.incomingDay,
    this.incomingDayKey,
    this.incomingOffsetY = 0,
    this.transitionProgress = 0,
  });

  bool get hasIncoming => incomingDay != null && incomingDayKey != null;

  bool ownsInlineDay(String dayKey) =>
      outgoingDayKey == dayKey || incomingDayKey == dayKey;
}

class _StickyDateBoundary {
  final StickyDateMarkerGeometry dayAbove;
  final StickyDateMarkerGeometry dayBelow;
  final double dividerOffsetFromSticky;

  const _StickyDateBoundary({
    required this.dayAbove,
    required this.dayBelow,
    required this.dividerOffsetFromSticky,
  });
}

/// Resolves sticky-date ownership and collision displacement from current
/// viewport geometry. There are deliberately no time-based position values in
/// this calculation: if content moves by one pixel, the chip moves by one pixel.
abstract final class StickyDateGeometry {
  static StickyDateLayout? resolve({
    required List<StickyDateMarkerGeometry> messages,
    required List<StickyDateMarkerGeometry> dividers,
    required double stickyTop,
    required double chipHeight,
    required double collisionGap,
    required double crossingHysteresis,
    String? currentDayKey,
    DateTime? currentDay,
  }) {
    assert(stickyTop.isFinite);
    assert(chipHeight > 0 && chipHeight.isFinite);
    assert(collisionGap >= 0 && collisionGap.isFinite);
    assert(crossingHysteresis >= 0 && crossingHysteresis.isFinite);

    final transitionExtent = chipHeight + collisionGap;
    final geometricDay = _dayAtBoundary(
      messages: messages,
      dividers: dividers,
      stickyTop: stickyTop,
    );
    final currentMarker =
        currentDayKey != null && currentDay != null
            ? StickyDateMarkerGeometry(
              day: currentDay,
              dayKey: currentDayKey,
              rect: Rect.zero,
            )
            : null;
    var active = geometricDay ?? currentMarker;
    if (active == null) return null;

    final boundary = _findBoundary(
      messages: messages,
      dividers: dividers,
      stickyTop: stickyTop,
      transitionExtent: transitionExtent,
      crossingHysteresis: crossingHysteresis,
      current: currentMarker,
      geometricDay: geometricDay,
    );

    if (boundary != null && currentMarker != null) {
      final currentIsAbove = currentMarker.dayKey == boundary.dayAbove.dayKey;
      final currentIsBelow = currentMarker.dayKey == boundary.dayBelow.dayKey;
      if (currentIsAbove) {
        active =
            boundary.dividerOffsetFromSticky <= -crossingHysteresis
                ? boundary.dayBelow
                : currentMarker;
      } else if (currentIsBelow) {
        active =
            boundary.dividerOffsetFromSticky >=
                    transitionExtent + crossingHysteresis
                ? boundary.dayAbove
                : currentMarker;
      }
    }

    final boundaryIsVisible =
        boundary != null &&
        boundary.dividerOffsetFromSticky >= -crossingHysteresis &&
        boundary.dividerOffsetFromSticky <=
            transitionExtent + crossingHysteresis &&
        (active.dayKey == boundary.dayAbove.dayKey ||
            active.dayKey == boundary.dayBelow.dayKey);
    if (!boundaryIsVisible) {
      return StickyDateLayout(
        activeDay: active.day,
        activeDayKey: active.dayKey,
        outgoingDay: active.day,
        outgoingDayKey: active.dayKey,
        outgoingOffsetY: 0,
      );
    }

    final dividerOffset = boundary.dividerOffsetFromSticky;
    final progress =
        ((transitionExtent - dividerOffset) / transitionExtent)
            .clamp(0.0, 1.0)
            .toDouble();
    final dayAboveOffset =
        dividerOffset - transitionExtent < 0
            ? dividerOffset - transitionExtent
            : 0.0;
    final dayBelowOffset = dividerOffset > 0 ? dividerOffset : 0.0;

    final activeIsAbove = active.dayKey == boundary.dayAbove.dayKey;
    final outgoing = activeIsAbove ? boundary.dayAbove : boundary.dayBelow;
    final incoming = activeIsAbove ? boundary.dayBelow : boundary.dayAbove;
    final outgoingOffset = activeIsAbove ? dayAboveOffset : dayBelowOffset;
    final incomingOffset = activeIsAbove ? dayBelowOffset : dayAboveOffset;

    assert(progress >= 0 && progress <= 1);
    assert(outgoingOffset.isFinite);
    assert(incomingOffset.isFinite);
    return StickyDateLayout(
      activeDay: active.day,
      activeDayKey: active.dayKey,
      outgoingDay: outgoing.day,
      outgoingDayKey: outgoing.dayKey,
      outgoingOffsetY: outgoingOffset,
      incomingDay: incoming.day,
      incomingDayKey: incoming.dayKey,
      incomingOffsetY: incomingOffset,
      transitionProgress: progress,
    );
  }

  static _StickyDateBoundary? _findBoundary({
    required List<StickyDateMarkerGeometry> messages,
    required List<StickyDateMarkerGeometry> dividers,
    required double stickyTop,
    required double transitionExtent,
    required double crossingHysteresis,
    required StickyDateMarkerGeometry? current,
    required StickyDateMarkerGeometry? geometricDay,
  }) {
    _StickyDateBoundary? best;
    var bestScore = double.infinity;
    for (final divider in dividers) {
      var dayAbove = _dayBeforeDivider(
        divider: divider,
        messages: messages,
        dividers: dividers,
      );
      if (dayAbove == null &&
          current != null &&
          current.dayKey != divider.dayKey) {
        dayAbove = current;
      }
      if (dayAbove == null || dayAbove.dayKey == divider.dayKey) continue;

      final containsCurrent =
          current != null &&
          (current.dayKey == dayAbove.dayKey ||
              current.dayKey == divider.dayKey);
      final containsGeometricDay =
          geometricDay != null &&
          (geometricDay.dayKey == dayAbove.dayKey ||
              geometricDay.dayKey == divider.dayKey);
      if (!containsCurrent && !containsGeometricDay) continue;

      if (current != null &&
          geometricDay != null &&
          current.dayKey != geometricDay.dayKey) {
        final containsBoth =
            (current.dayKey == dayAbove.dayKey ||
                current.dayKey == divider.dayKey) &&
            (geometricDay.dayKey == dayAbove.dayKey ||
                geometricDay.dayKey == divider.dayKey);
        if (!containsBoth) continue;
      }

      final offset = divider.rect.top - stickyTop;
      final distanceToTransition = switch (offset) {
        < 0 => -offset,
        _ when offset > transitionExtent => offset - transitionExtent,
        _ => 0.0,
      };
      if (current?.dayKey == geometricDay?.dayKey &&
          distanceToTransition > crossingHysteresis) {
        continue;
      }
      final centreDistance = (offset - (transitionExtent / 2)).abs();
      final score = distanceToTransition * 1000 + centreDistance;
      if (score >= bestScore) continue;
      bestScore = score;
      best = _StickyDateBoundary(
        dayAbove: dayAbove,
        dayBelow: divider,
        dividerOffsetFromSticky: offset,
      );
    }
    return best;
  }

  static StickyDateMarkerGeometry? _dayAtBoundary({
    required List<StickyDateMarkerGeometry> messages,
    required List<StickyDateMarkerGeometry> dividers,
    required double stickyTop,
  }) {
    StickyDateMarkerGeometry? dividerAbove;
    for (final divider in dividers) {
      if (divider.rect.top > stickyTop) break;
      dividerAbove = divider;
    }
    if (dividerAbove != null) return dividerAbove;

    for (final message in messages) {
      if (message.rect.top <= stickyTop && message.rect.bottom > stickyTop) {
        return message;
      }
    }

    StickyDateMarkerGeometry? messageAbove;
    for (final message in messages) {
      if (message.rect.top >= stickyTop) break;
      messageAbove = message;
    }
    if (messageAbove != null) return messageAbove;
    if (messages.isNotEmpty) return messages.first;
    if (dividers.isNotEmpty) return dividers.first;
    return null;
  }

  static StickyDateMarkerGeometry? _dayBeforeDivider({
    required StickyDateMarkerGeometry divider,
    required List<StickyDateMarkerGeometry> messages,
    required List<StickyDateMarkerGeometry> dividers,
  }) {
    StickyDateMarkerGeometry? before;
    for (final candidate in dividers) {
      if (candidate.rect.top >= divider.rect.top) break;
      if (candidate.dayKey != divider.dayKey) before = candidate;
    }
    if (before != null) return before;

    for (final message in messages) {
      if (message.rect.top >= divider.rect.top) break;
      if (message.dayKey != divider.dayKey) before = message;
    }
    return before;
  }
}
