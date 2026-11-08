part of '../../../screens/chats/chat_screen.dart';

class _ExclusiveMessageSwipeCoordinator {
  String? _ownerMessageId;

  bool acquire(String messageId) {
    if (_ownerMessageId != null && _ownerMessageId != messageId) {
      return false;
    }

    _ownerMessageId = messageId;
    return true;
  }

  void release(String messageId) {
    if (_ownerMessageId == messageId) {
      _ownerMessageId = null;
    }
  }
}

class _MessageSwipeGeometry {
  // ===========================================================================
  // RAW FINGER MOVEMENT
  // ===========================================================================

  // Match new Wrytte: the bubble follows the finger directly until the
  // threshold, then gains rubber-band resistance.
  static const double normalDragFactor = 1.0;

  static const double overscrollDragFactor = 0.22;

  static const double activationRawDistance = 62;

  static const double deactivationRawDistance = 54;

  static const double maximumRawDistance = 150;

  static const double maximumVisualOffset = 87;

  // ===========================================================================
  // FLING
  // ===========================================================================

  static const double minimumFlingRawDistance = 36;

  static const double minimumFlingVelocity = 950;

  // ===========================================================================
  // ACTION
  // ===========================================================================

  static const double actionRevealVisualDistance = 9;

  static const double actionHideVisualDistance = 6;

  static const double actionDiameter = 30;

  static const double actionIconSize = 17;

  static const double actionEdgeInset = 12;

  static const double actionBubbleInset = 3;

  static const double actionMovementFactor = 0.45;

  static const double actionOvershootScale = 1.0;

  // ===========================================================================
  // OPACITY
  // ===========================================================================

  /// Opacity can start slightly before the full visual pop.
  static const double actionOpacityStartDistance = 8;

  /// By this message displacement the action is allowed to be fully opaque.
  static const double actionOpacityFullDistance = activationRawDistance;

  // ===========================================================================
  // RAW -> VISUAL
  // ===========================================================================

  static double visualOffsetForRaw(double rawOffset) {
    if (rawOffset == 0) {
      return 0;
    }

    final direction = rawOffset.sign;
    final rawDistance = rawOffset.abs();

    final double visualDistance;

    if (rawDistance <= activationRawDistance) {
      visualDistance = rawDistance * normalDragFactor;
    } else {
      final activationVisualDistance = activationRawDistance * normalDragFactor;

      final excessRawDistance = rawDistance - activationRawDistance;

      visualDistance =
          activationVisualDistance + (excessRawDistance * overscrollDragFactor);
    }

    return direction * math.min(visualDistance, maximumVisualOffset);
  }

  // ===========================================================================
  // VISUAL -> RAW
  // ===========================================================================

  static double rawOffsetForVisual(double visualOffset) {
    if (visualOffset == 0) {
      return 0;
    }

    final direction = visualOffset.sign;
    final visualDistance = visualOffset.abs();

    final activationVisualDistance = activationRawDistance * normalDragFactor;

    final double rawDistance;

    if (visualDistance <= activationVisualDistance) {
      rawDistance = visualDistance / normalDragFactor;
    } else {
      rawDistance =
          activationRawDistance +
          ((visualDistance - activationVisualDistance) / overscrollDragFactor);
    }

    return direction * math.min(rawDistance, maximumRawDistance);
  }

  // ===========================================================================
  // POP SCALE
  // ===========================================================================

  static double actionPopScale(double t) {
    final progress = t.clamp(0.0, 1.0).toDouble();

    if (progress <= 0) {
      return 0;
    }

    return Curves.easeOutCubic.transform(progress);
  }

  // ===========================================================================
  // OPACITY
  // ===========================================================================

  static double actionOpacity({
    required double animationProgress,
    required double visualDistance,
  }) {
    // Time-driven fade.
    final timeOpacity = Curves.easeOutCubic.transform(
      (animationProgress / 0.72).clamp(0.0, 1.0).toDouble(),
    );

    // Distance-driven fade.
    final distanceProgress =
        ((visualDistance - actionOpacityStartDistance) /
                (actionOpacityFullDistance - actionOpacityStartDistance))
            .clamp(0.0, 1.0)
            .toDouble();

    final distanceOpacity = Curves.easeOutCubic.transform(distanceProgress);

    // Both must progress.
    return math.min(timeOpacity, distanceOpacity);
  }

  // ===========================================================================
  // SCALE FITTING
  // ===========================================================================

  static double maximumActionScaleForSpace(double visualDistance) {
    final availableWidth = visualDistance - actionEdgeInset - actionBubbleInset;

    if (availableWidth <= 0) {
      return 0;
    }

    return (availableWidth / actionDiameter)
        .clamp(0.0, actionOvershootScale)
        .toDouble();
  }

  // ===========================================================================
  // ACTION POSITION
  // ===========================================================================

  static double actionCenterFromEdge({
    required double visualDistance,
    required double scale,
  }) {
    final scaledRadius = (actionDiameter * scale) / 2;

    final minimumCenter = actionEdgeInset + scaledRadius;

    final maximumCenter = visualDistance - actionBubbleInset - scaledRadius;

    if (maximumCenter <= minimumCenter) {
      return minimumCenter;
    }

    final movementAfterReveal = math.max(
      0.0,
      visualDistance - actionRevealVisualDistance,
    );

    final baseCenter = actionEdgeInset + (actionDiameter / 2);

    final desiredCenter =
        baseCenter + (movementAfterReveal * actionMovementFactor);

    return desiredCenter.clamp(minimumCenter, maximumCenter).toDouble();
  }

  // ===========================================================================
  // RELEASE VELOCITY
  // ===========================================================================

  static double visualVelocityForRelease({
    required double rawDistance,
    required double rawVelocity,
  }) {
    final factor = rawDistance.abs() > activationRawDistance
        ? overscrollDragFactor
        : normalDragFactor;

    return rawVelocity * factor;
  }
}

class _SwipeMessageAction extends StatefulWidget {
  final String messageId;

  final _ExclusiveMessageSwipeCoordinator coordinator;

  final Widget child;

  final VoidCallback onReply;

  final VoidCallback onForward;

  final bool enabled;

  const _SwipeMessageAction({
    super.key,
    required this.messageId,
    required this.coordinator,
    required this.child,
    required this.onReply,
    required this.onForward,
    required this.enabled,
  });

  @override
  State<_SwipeMessageAction> createState() => _SwipeMessageActionState();
}

class _SwipeMessageActionState extends State<_SwipeMessageAction>
    with TickerProviderStateMixin {
  // ===========================================================================
  // HAPTICS
  // ===========================================================================

  static _SwipeHapticCapabilities? _hapticCapabilities;
  static Future<void>? _hapticWarmup;

  // ===========================================================================
  // RETURN SPRING
  // ===========================================================================

  static const SpringDescription _returnSpring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 46,
  );

  // ===========================================================================
  // CONTROLLERS
  // ===========================================================================

  late final AnimationController _offsetController;

  late final AnimationController _actionController;

  // ===========================================================================
  // STATE
  // ===========================================================================

  double _rawDragDistance = 0;

  bool _thresholdArmed = false;

  bool _ownsSwipe = false;

  bool _actionTargetVisible = false;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _offsetController = AnimationController.unbounded(vsync: this);

    _actionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 110),
    );

    _offsetController.addListener(_syncActionVisibility);
    unawaited(_warmHapticCapabilities());
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  @override
  void didUpdateWidget(covariant _SwipeMessageAction oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.messageId != widget.messageId ||
        oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.release(oldWidget.messageId);

      _ownsSwipe = false;
    }

    if (oldWidget.enabled && !widget.enabled) {
      _releaseSwipeOwnership();

      _offsetController.stop();
      _actionController.stop();

      _rawDragDistance = 0;
      _thresholdArmed = false;
      _actionTargetVisible = false;

      _offsetController.value = 0;
      _actionController.value = 0;
    }
  }

  // ===========================================================================
  // ACTION VISIBILITY
  // ===========================================================================

  void _syncActionVisibility() {
    final visualDistance = _offsetController.value.abs();

    if (!_actionTargetVisible &&
        visualDistance >= _MessageSwipeGeometry.actionRevealVisualDistance) {
      _actionTargetVisible = true;

      _actionController.forward();

      return;
    }

    if (_actionTargetVisible &&
        visualDistance <= _MessageSwipeGeometry.actionHideVisualDistance) {
      _actionTargetVisible = false;

      _actionController.reverse();
    }
  }

  // ===========================================================================
  // DRAG START
  // ===========================================================================

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) {
      return;
    }

    _ownsSwipe = widget.coordinator.acquire(widget.messageId);

    if (!_ownsSwipe) {
      return;
    }

    _offsetController.stop();

    _rawDragDistance = _MessageSwipeGeometry.rawOffsetForVisual(
      _offsetController.value,
    );

    _thresholdArmed =
        _rawDragDistance.abs() >= _MessageSwipeGeometry.activationRawDistance;
  }

  // ===========================================================================
  // DRAG UPDATE
  // ===========================================================================

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || !_ownsSwipe) {
      return;
    }

    _rawDragDistance = (_rawDragDistance + details.delta.dx)
        .clamp(
          -_MessageSwipeGeometry.maximumRawDistance,
          _MessageSwipeGeometry.maximumRawDistance,
        )
        .toDouble();

    _offsetController.value = _MessageSwipeGeometry.visualOffsetForRaw(
      _rawDragDistance,
    );

    final rawDistance = _rawDragDistance.abs();

    final isNowArmed = _thresholdArmed
        ? rawDistance >= _MessageSwipeGeometry.deactivationRawDistance
        : rawDistance >= _MessageSwipeGeometry.activationRawDistance;

    if (isNowArmed && !_thresholdArmed) {
      _thresholdArmed = true;

      unawaited(_playThresholdHaptic());
    } else if (!isNowArmed && _thresholdArmed) {
      _thresholdArmed = false;
    }
  }

  // ===========================================================================
  // DRAG END
  // ===========================================================================

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled || !_ownsSwipe) {
      _releaseSwipeOwnership();

      _springBack();

      return;
    }

    final releaseVelocity = details.primaryVelocity ?? 0;

    final rawDistance = _rawDragDistance.abs();

    final rawDirection = _rawDragDistance.sign;

    final isIntentionalFling =
        rawDistance >= _MessageSwipeGeometry.minimumFlingRawDistance &&
        releaseVelocity.abs() >= _MessageSwipeGeometry.minimumFlingVelocity &&
        releaseVelocity.sign == rawDirection;

    final shouldActivate = _thresholdArmed || isIntentionalFling;

    final activateReply = _rawDragDistance > 0;

    if (isIntentionalFling && !_thresholdArmed) {
      unawaited(_playThresholdHaptic());
    }

    final visualReleaseVelocity =
        _MessageSwipeGeometry.visualVelocityForRelease(
          rawDistance: _rawDragDistance,
          rawVelocity: releaseVelocity,
        );

    _rawDragDistance = 0;
    _thresholdArmed = false;

    _releaseSwipeOwnership();

    _springBack(releaseVelocity: visualReleaseVelocity);

    if (!shouldActivate) {
      return;
    }

    if (activateReply) {
      widget.onReply();
    } else {
      widget.onForward();
    }
  }

  // ===========================================================================
  // CANCEL
  // ===========================================================================

  void _handleDragCancel() {
    _rawDragDistance = 0;

    _thresholdArmed = false;

    _releaseSwipeOwnership();

    _springBack();
  }

  // ===========================================================================
  // OWNERSHIP
  // ===========================================================================

  void _releaseSwipeOwnership() {
    if (!_ownsSwipe) {
      return;
    }

    widget.coordinator.release(widget.messageId);

    _ownsSwipe = false;
  }

  // ===========================================================================
  // HAPTIC
  // ===========================================================================

  static Future<void> _warmHapticCapabilities() {
    return _hapticWarmup ??= _loadHapticCapabilities();
  }

  static Future<void> _loadHapticCapabilities() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      _hapticCapabilities = const _SwipeHapticCapabilities(false);
      return;
    }
    try {
      final hasVibrator = await Vibration.hasVibrator();
      _hapticCapabilities = _SwipeHapticCapabilities(hasVibrator);
    } catch (_) {
      _hapticCapabilities = const _SwipeHapticCapabilities(false);
    }
  }

  Future<void> _playThresholdHaptic() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      await HapticFeedback.selectionClick();
      return;
    }
    // Match the native long-press haptic used by Android message actions.
    // If the system effect is unavailable, use a short plain vibration.
    final capabilities = _hapticCapabilities;
    try {
      final performed = await const MethodChannel(
        'com.example.wrytte/gesture_haptics',
      ).invokeMethod<bool>('longPress');
      if (performed == true) return;
    } catch (_) {
      // Fall through to the plugin when the native channel is unavailable.
    }
    if (capabilities == null || !capabilities.hasVibrator) {
      await HapticFeedback.selectionClick();
      return;
    }
    try {
      await Vibration.vibrate(
        duration: 18,
      );
    } catch (_) {
      await HapticFeedback.selectionClick();
    }
  }

  // ===========================================================================
  // SPRING BACK
  // ===========================================================================

  void _springBack({double releaseVelocity = 0}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _actionTargetVisible = false;

      _offsetController.value = 0;
      _actionController.value = 0;

      return;
    }

    final boundedVelocity = releaseVelocity.clamp(-1400.0, 1400.0).toDouble();

    _offsetController.animateWith(
      SpringSimulation(
        _returnSpring,
        _offsetController.value,
        0,
        boundedVelocity,
        snapToEnd: true,
      ),
    );
  }

  // ===========================================================================
  // ACTION
  // ===========================================================================

  Widget _buildAction({
    required bool reply,
    required double visualDistance,
    required double animationProgress,
  }) {
    final desiredScale = _MessageSwipeGeometry.actionPopScale(
      animationProgress,
    );

    final spaceLimitedScale = _MessageSwipeGeometry.maximumActionScaleForSpace(
      visualDistance,
    );

    final scale = math.min(desiredScale, spaceLimitedScale);

    final centerFromEdge = _MessageSwipeGeometry.actionCenterFromEdge(
      visualDistance: visualDistance,
      scale: scale,
    );

    final baseRadius = _MessageSwipeGeometry.actionDiameter / 2;

    final translationFromAlignedEdge = centerFromEdge - baseRadius;

    final opacity = _MessageSwipeGeometry.actionOpacity(
      animationProgress: animationProgress,
      visualDistance: visualDistance,
    );

    return Transform.translate(
      offset: Offset(
        reply ? translationFromAlignedEdge : -translationFromAlignedEdge,
        0,
      ),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Container(
            width: _MessageSwipeGeometry.actionDiameter,
            height: _MessageSwipeGeometry.actionDiameter,
            decoration: BoxDecoration(
              color: WrytteColors.surfaceRaised,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: reply
                  ? Transform.flip(
                      flipX: true,
                      child: wrytteSvgAssetIcon(
                        assetPath: 'assets/svg/Forward and Reply icon fill.svg',
                        canvas: _MessageSwipeGeometry.actionIconSize,
                        scale: 1,
                        color: Colors.white,
                      ),
                    )
                  : wrytteSvgAssetIcon(
                      assetPath: 'assets/svg/Forward and Reply icon fill.svg',
                      canvas: _MessageSwipeGeometry.actionIconSize,
                      scale: 1,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _releaseSwipeOwnership();

    _offsetController.removeListener(_syncActionVisibility);

    _offsetController.dispose();
    _actionController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      onHorizontalDragStart: widget.enabled ? _handleDragStart : null,

      onHorizontalDragUpdate: widget.enabled ? _handleDragUpdate : null,

      onHorizontalDragEnd: widget.enabled ? _handleDragEnd : null,

      onHorizontalDragCancel: widget.enabled ? _handleDragCancel : null,

      child: AnimatedBuilder(
        animation: Listenable.merge([_offsetController, _actionController]),

        child: widget.child,

        builder: (context, child) {
          final offset = _offsetController.value
              .clamp(
                -_MessageSwipeGeometry.maximumVisualOffset,
                _MessageSwipeGeometry.maximumVisualOffset,
              )
              .toDouble();

          final visualDistance = offset.abs();

          final isReply = offset >= 0;

          final actionProgress = _actionController.value;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: isReply
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: _buildAction(
                      reply: isReply,
                      visualDistance: visualDistance,
                      animationProgress: actionProgress,
                    ),
                  ),
                ),
              ),

              Transform.translate(offset: Offset(offset, 0), child: child),
            ],
          );
        },
      ),
    );
  }
}

class _SwipeHapticCapabilities {
  const _SwipeHapticCapabilities(this.hasVibrator);

  final bool hasVibrator;
}
