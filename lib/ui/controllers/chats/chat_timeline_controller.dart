part of '../../screens/chats/chat_screen.dart';

extension _ChatTimelineController on _ChatScreenState {
  void _onScroll() {
    if (_floatingDateScrollActive || _floatingDatePinnedAtVisualTop) {
      _scheduleFloatingDateMeasurement();
    }
    _maybePrefetchOlderMessages();
  }

  void _scheduleOlderHistoryPrefetch() {
    if (_olderHistoryPrefetchScheduled || _disposing) return;
    _olderHistoryPrefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _olderHistoryPrefetchScheduled = false;
      if (!mounted || _disposing) return;
      _maybePrefetchOlderMessages();
    });
  }

  void _maybePrefetchOlderMessages() {
    if (!_scrollCtrl.hasClients || !_hasMoreOlder) return;
    final position = _scrollCtrl.position;
    if (!position.hasContentDimensions) {
      _scheduleOlderHistoryPrefetch();
      return;
    }
    // With a reversed list, maxScrollExtent is the oldest visual edge. Keep a
    // deep runway ahead of a fast fling; a short first window is proactively
    // filled even before it becomes scrollable.
    final distance = ChatTimelineCoordinates.distanceFromOldest(
      pixels: position.pixels,
      minScrollExtent: position.minScrollExtent,
    );
    final prefetchExtent = ChatTimelineCoordinates.olderHistoryPrefetchExtent(
      viewportExtent: position.viewportDimension,
    );
    final closeEnoughForFeedback =
        position.maxScrollExtent <= 0 || distance <= position.viewportDimension;
    if (_loadingOlder) {
      // Deep prefetch remains invisible. If a very fast fling catches the
      // in-flight request, reveal the progress pill promptly at the edge.
      if (closeEnoughForFeedback) {
        _scheduleOlderLoadingIndicator(
          delay: const Duration(milliseconds: 120),
        );
      }
      return;
    }
    if (position.maxScrollExtent <= 0 || distance <= prefetchExtent) {
      unawaited(
        _loadOlderMessages(showLoadingIndicator: closeEnoughForFeedback),
      );
    }
  }

  void _scheduleOlderLoadingIndicator({
    Duration delay = const Duration(milliseconds: 350),
  }) {
    if (_showOlderLoadingIndicator ||
        _olderLoadingIndicatorTimer != null ||
        !_loadingOlder) {
      return;
    }
    _olderLoadingIndicatorTimer = Timer(delay, () {
      _olderLoadingIndicatorTimer = null;
      if (!mounted || _disposing || !_loadingOlder) return;
      _setChatState(() => _showOlderLoadingIndicator = true);
    });
  }

  bool _handleMessageScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || _disposing) return false;
    final nearBottom =
        ChatTimelineCoordinates.distanceFromBottom(
          pixels: notification.metrics.pixels,
          maxScrollExtent: notification.metrics.maxScrollExtent,
        ) <=
        80;
    if (nearBottom != _nearBottom) {
      _setChatState(() {
        _nearBottom = nearBottom;
        if (nearBottom) _pendingNewMessages = 0;
      });
    }
    _floatingDatePinnedAtVisualTop = _isAtVisualTopEdge(notification.metrics);

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      final isUserDriven =
          (notification is ScrollStartNotification &&
              notification.dragDetails != null) ||
          (notification is ScrollUpdateNotification &&
              notification.dragDetails != null) ||
          (notification is OverscrollNotification &&
              notification.dragDetails != null);
      if (!_floatingDateScrollActive && !isUserDriven) return false;

      final isScrollable =
          notification.metrics.maxScrollExtent >
          notification.metrics.minScrollExtent + 0.5;
      if (!isScrollable || _messages.isEmpty) {
        _floatingDateScrollActive = false;
        _floatingDatePinnedAtVisualTop = false;
        _floatingDateHideTimer?.cancel();
        _floatingDateVisibilityController.reverse();
        return false;
      }

      _floatingDateScrollActive = true;
      _floatingDateHideTimer?.cancel();
      _scheduleFloatingDateMeasurement();
      if (_floatingDateVisual.value.hasDate &&
          _floatingDateVisibilityController.status != AnimationStatus.forward &&
          _floatingDateVisibilityController.status !=
              AnimationStatus.completed) {
        _floatingDateVisibilityController.forward();
      }
    } else if (notification is ScrollEndNotification) {
      final wasScrollActive = _floatingDateScrollActive;
      _floatingDateScrollActive = false;
      if (_floatingDatePinnedAtVisualTop) {
        _floatingDateHideTimer?.cancel();
        if (_floatingDateVisibilityController.status !=
                AnimationStatus.completed &&
            _floatingDateVisibilityController.status !=
                AnimationStatus.forward) {
          _floatingDateVisibilityController.forward();
        }
      } else if (wasScrollActive) {
        _scheduleFloatingDateHide();
      }
    }

    return false;
  }

  bool _isAtVisualTopEdge(ScrollMetrics metrics) {
    const tolerance = 0.75;
    switch (metrics.axisDirection) {
      case AxisDirection.up:
        return metrics.pixels >= metrics.maxScrollExtent - tolerance;
      case AxisDirection.down:
        return metrics.pixels <= metrics.minScrollExtent + tolerance;
      case AxisDirection.left:
      case AxisDirection.right:
        return false;
    }
  }

  void _scheduleFloatingDateHide() {
    _floatingDateHideTimer?.cancel();
    if (_floatingDatePinnedAtVisualTop) return;
    _floatingDateHideTimer = Timer(_floatingDateHideDelay, () {
      if (!mounted || _disposing) return;
      if (_floatingDateScrollActive || _floatingDatePinnedAtVisualTop) {
        return;
      }
      _floatingDateVisibilityController.reverse();
    });
  }

  void _scheduleFloatingDateMeasurement() {
    if (_floatingDateMeasurementScheduled || _disposing) return;
    _floatingDateMeasurementScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _floatingDateMeasurementScheduled = false;
      if (!mounted || _disposing) return;
      _measureFloatingDate();
    });
  }

  void _registerDateMarker(_DateViewportMarkerState marker) {
    if (_disposing) return;
    assert(marker.dayKey.isNotEmpty);
    final markers =
        marker.kind == _DateViewportMarkerKind.message
            ? _mountedMessageDateMarkers
            : _mountedDividerDateMarkers;
    markers.add(marker);
    if (_floatingDateScrollActive || _floatingDatePinnedAtVisualTop) {
      _scheduleFloatingDateMeasurement();
    }
  }

  void _unregisterDateMarker(_DateViewportMarkerState marker) {
    if (_disposing) return;
    _mountedMessageDateMarkers.remove(marker);
    _mountedDividerDateMarkers.remove(marker);
    if (_floatingDateScrollActive || _floatingDatePinnedAtVisualTop) {
      _scheduleFloatingDateMeasurement();
    }
  }

  void _measureFloatingDate() {
    if (_messages.isEmpty ||
        (!_floatingDateScrollActive && !_floatingDatePinnedAtVisualTop)) {
      return;
    }

    final viewportObject =
        _messageViewportKey.currentContext?.findRenderObject();
    final stackObject = _screenStackKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox ||
        stackObject is! RenderBox ||
        !viewportObject.attached ||
        !stackObject.attached ||
        !viewportObject.hasSize ||
        !stackObject.hasSize) {
      return;
    }

    final stickyGlobal = stackObject.localToGlobal(Offset(0, _floatingDateTop));
    final stickyBoundaryY = viewportObject.globalToLocal(stickyGlobal).dy;
    if (!stickyBoundaryY.isFinite) return;

    final viewportRect = Offset.zero & viewportObject.size;
    const measurementOverscan =
        _dateHandoffExtent + _dateCrossingHysteresis + 4;
    final measurementRect = Rect.fromLTRB(
      viewportRect.left,
      viewportRect.top - measurementOverscan,
      viewportRect.right,
      viewportRect.bottom + measurementOverscan,
    );
    final messageCandidates = _measureMountedMarkers(
      markers: _mountedMessageDateMarkers,
      viewport: viewportObject,
      viewportRect: measurementRect,
    )..sort((a, b) => a.rect.top.compareTo(b.rect.top));

    final dividerCandidates = _measureMountedMarkers(
      markers: _mountedDividerDateMarkers,
      viewport: viewportObject,
      viewportRect: measurementRect,
    )..sort((a, b) => a.rect.top.compareTo(b.rect.top));

    if (messageCandidates.isEmpty && dividerCandidates.isEmpty) return;

    final layout = StickyDateGeometry.resolve(
      messages: messageCandidates,
      dividers: dividerCandidates,
      stickyTop: stickyBoundaryY,
      chipHeight: _dateChipHeight,
      collisionGap: _dateCollisionGap,
      crossingHysteresis: _dateCrossingHysteresis,
      currentDayKey: _activeFloatingDayKey,
      currentDay: _activeFloatingDay,
    );
    if (layout == null) return;

    _activeFloatingDayKey = layout.activeDayKey;
    _activeFloatingDay = layout.activeDay;
    _publishFloatingDateVisual(layout);

    if ((_floatingDateScrollActive || _floatingDatePinnedAtVisualTop) &&
        _floatingDateVisibilityController.status != AnimationStatus.forward &&
        _floatingDateVisibilityController.status != AnimationStatus.completed) {
      _floatingDateVisibilityController.forward();
    }
  }

  void _publishFloatingDateVisual(StickyDateLayout layout) {
    if (_disposing) return;
    assert(layout.outgoingOffsetY.isFinite);
    assert(layout.incomingOffsetY.isFinite);
    assert(
      layout.outgoingOffsetY <= _dateHandoffExtent + _dateCrossingHysteresis,
    );
    assert(
      layout.incomingOffsetY <= _dateHandoffExtent + _dateCrossingHysteresis,
    );
    final nextVisual = _FloatingDateVisualState(
      activeDayKey: layout.activeDayKey,
      outgoingDayKey: layout.outgoingDayKey,
      outgoingLabel: _formatDateDivider(layout.outgoingDay),
      outgoingOffsetY: layout.outgoingOffsetY,
      incomingDayKey: layout.incomingDayKey,
      incomingLabel:
          layout.incomingDay == null
              ? null
              : _formatDateDivider(layout.incomingDay!),
      incomingOffsetY: layout.incomingOffsetY,
      transitionProgress: layout.transitionProgress,
    );
    final currentVisual = _floatingDateVisual.value;
    final unchanged =
        currentVisual.activeDayKey == nextVisual.activeDayKey &&
        currentVisual.outgoingDayKey == nextVisual.outgoingDayKey &&
        currentVisual.outgoingLabel == nextVisual.outgoingLabel &&
        currentVisual.incomingDayKey == nextVisual.incomingDayKey &&
        currentVisual.incomingLabel == nextVisual.incomingLabel &&
        (currentVisual.outgoingOffsetY - nextVisual.outgoingOffsetY).abs() <
            0.01 &&
        (currentVisual.incomingOffsetY - nextVisual.incomingOffsetY).abs() <
            0.01 &&
        (currentVisual.transitionProgress - nextVisual.transitionProgress)
                .abs() <
            0.001;
    if (!unchanged) _floatingDateVisual.value = nextVisual;
  }

  List<StickyDateMarkerGeometry> _measureMountedMarkers({
    required Set<_DateViewportMarkerState> markers,
    required RenderBox viewport,
    required Rect viewportRect,
  }) {
    final measured = <StickyDateMarkerGeometry>[];
    for (final marker in markers) {
      if (!marker.mounted) continue;
      final markerObject = marker.context.findRenderObject();
      if (markerObject is! RenderBox ||
          !markerObject.attached ||
          !markerObject.hasSize) {
        continue;
      }
      final topLeft = markerObject.localToGlobal(
        Offset.zero,
        ancestor: viewport,
      );
      final rect = topLeft & markerObject.size;
      if (!rect.overlaps(viewportRect)) continue;
      measured.add(
        StickyDateMarkerGeometry(
          day: marker.day,
          dayKey: marker.dayKey,
          rect: rect,
        ),
      );
    }
    return measured;
  }

  Future<void> _loadOlderMessages({bool showLoadingIndicator = false}) async {
    if (_loadingOlder || !_hasMoreOlder) return;
    final conversationId = _resolvedConversationId ?? widget.conversationId;
    if (!conversationId.startsWith('!')) {
      _setChatState(() => _hasMoreOlder = false);
      return;
    }

    final existingIds = _messages.map((message) => message.id).toSet();
    // This flag only suppresses duplicate requests; paging is intentionally
    // kept outside the message list. A delayed overlay gives feedback only
    // when the request is slow enough to be noticeable.
    _loadingOlder = true;
    _olderLoadingIndicatorTimer?.cancel();
    _olderLoadingIndicatorTimer = null;
    if (showLoadingIndicator) _scheduleOlderLoadingIndicator();
    var shouldContinuePrefetch = false;
    try {
      final restored = await _chat.loadOlderMessagePage(conversationId);
      if (!mounted) return;
      final added = restored.any(
        (message) => !existingIds.contains(message.id),
      );
      final hasMore = await _chat.hasMoreOlderMessages(conversationId);
      if (!mounted) return;
      _setChatState(() {
        // Incremental ID merge keeps existing element identity and the visual
        // anchor stable while older rows are inserted beyond the reversed
        // list's current top edge.
        if (restored.isNotEmpty) _mergeMessages(restored);
        _hasMoreOlder = hasMore;
      });
      shouldContinuePrefetch = added && hasMore;
    } catch (error) {
      apkLog(
        'ChatScreen.history',
        'older page failed room_id="$conversationId" error="$error"',
      );
      // A transient network failure is retryable the next time the user
      // reaches the oldest visible message.
      if (mounted) _setChatState(() => _hasMoreOlder = true);
    } finally {
      _loadingOlder = false;
      _olderLoadingIndicatorTimer?.cancel();
      _olderLoadingIndicatorTimer = null;
      if (mounted && _showOlderLoadingIndicator) {
        _setChatState(() => _showOlderLoadingIndicator = false);
      }
      if (shouldContinuePrefetch) _scheduleOlderHistoryPrefetch();
    }
  }
}
