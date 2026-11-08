part of 'message_input.dart';

class _RoundVideoProgressPainter extends CustomPainter {
  const _RoundVideoProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const startAngle = -math.pi / 2;
    const sweepSpan = math.pi * 2;
    final rect = Offset.zero & size;
    final center = rect.center;
    // Inset the arc so even the outside half of the stroke stays inside the
    // video circle. There is intentionally no inactive/gray track.
    final radius = (math.min(size.width, size.height) / 2) - 4.5;

    final progressPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.butt
          ..color = const Color(0xFFB7BDC6);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepSpan * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RoundVideoProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _LoopingTranslation extends StatefulWidget {
  final Widget child;
  final Offset begin;
  final Offset end;
  final Duration duration;

  const _LoopingTranslation({
    required this.child,
    required this.begin,
    required this.end,
    required this.duration,
  });

  @override
  State<_LoopingTranslation> createState() => _LoopingTranslationState();
}

class _LoopingTranslationState extends State<_LoopingTranslation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _configureAnimation();
  }

  @override
  void didUpdateWidget(covariant _LoopingTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.begin != widget.begin || oldWidget.end != widget.end) {
      _configureAnimation();
    }
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  void _configureAnimation() {
    _offset = Tween<Offset>(begin: widget.begin, end: widget.end).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder:
          (context, child) =>
              Transform.translate(offset: _offset.value, child: child),
    );
  }
}

class _RecordingModeHint extends StatefulWidget {
  final String message;
  final VoidCallback onDismissed;

  const _RecordingModeHint({required this.message, required this.onDismissed});

  @override
  State<_RecordingModeHint> createState() => _RecordingModeHintState();
}

class _RecordingModeHintState extends State<_RecordingModeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 170),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _scale = Tween<double>(begin: 0.9, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(curved);

    _controller.forward();
    _dismissTimer = Timer(const Duration(milliseconds: 1750), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: wrytteGlassDecoration(radius: 20),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.message,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: WrytteColors.textMuted,
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 13.5,
                        height: 1.18,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveRecordingWaveform extends StatefulWidget {
  final List<double> levels;

  const _LiveRecordingWaveform({required this.levels});

  @override
  State<_LiveRecordingWaveform> createState() => _LiveRecordingWaveformState();
}

class _LiveRecordingWaveformState extends State<_LiveRecordingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scrollController;
  late List<double> _previousLevels;
  double _incomingLevel = 0.02;
  bool _hasReceivedSample = false;

  @override
  void initState() {
    super.initState();
    _previousLevels = List<double>.of(widget.levels);
    if (widget.levels.isNotEmpty) _incomingLevel = widget.levels.last;
    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 125),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _LiveRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.levels, widget.levels) || widget.levels.isEmpty) {
      return;
    }
    _previousLevels = List<double>.of(oldWidget.levels);
    _incomingLevel = widget.levels.last.clamp(0.02, 1.0).toDouble();
    _hasReceivedSample = true;
    _scrollController.forward(from: 0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: ClipRect(
        child: CustomPaint(
          painter: _LiveRecordingWaveformPainter(
            previousLevels: _previousLevels,
            incomingLevel: _incomingLevel,
            progress: _scrollController,
            animateIncomingSample: _hasReceivedSample,
          ),
        ),
      ),
    );
  }
}

class _LiveRecordingWaveformPainter extends CustomPainter {
  static const double _barWidth = 2.4;
  static const double _targetPitch = 4.8;
  static const Color _barColor = WrytteColors.textSecondary;

  final List<double> previousLevels;
  final double incomingLevel;
  final Animation<double> progress;
  final bool animateIncomingSample;

  _LiveRecordingWaveformPainter({
    required this.previousLevels,
    required this.incomingLevel,
    required this.progress,
    required this.animateIncomingSample,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final barCount = (size.width / _targetPitch).floor().clamp(8, 64).toInt();
    final pitch =
        barCount > 1 ? (size.width - _barWidth) / (barCount - 1) : 0.0;
    final animationProgress = animateIncomingSample ? progress.value : 0.0;
    final visibleSampleCount = math.min(previousLevels.length, barCount);
    final firstSample = previousLevels.length - visibleSampleCount;
    final firstSlot = barCount - visibleSampleCount;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < visibleSampleCount; index++) {
      final sampleIndex = firstSample + index;
      final level = previousLevels[sampleIndex].clamp(0.02, 1.0).toDouble();
      final slot = firstSlot + index;
      final x =
          (slot * pitch) -
          (animateIncomingSample ? pitch * animationProgress : 0);
      _paintRoundedBar(canvas, paint, size, x, level);
    }

    if (animateIncomingSample) {
      final incomingX =
          ((barCount - 1) * pitch) + (pitch * (1 - animationProgress));
      _paintRoundedBar(canvas, paint, size, incomingX, incomingLevel);
    }
  }

  void _paintRoundedBar(
    Canvas canvas,
    Paint paint,
    Size size,
    double x,
    double level,
  ) {
    if (x + _barWidth < 0 || x > size.width) return;
    final normalizedLevel = level.clamp(0.02, 1.0).toDouble();
    final barHeight = 2.4 + (normalizedLevel * 17.0);
    final top = (size.height - barHeight) / 2;
    paint.color = _barColor.withValues(alpha: 0.70 + (normalizedLevel * 0.28));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, _barWidth, barHeight),
        const Radius.circular(_barWidth / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveRecordingWaveformPainter oldDelegate) {
    return !identical(previousLevels, oldDelegate.previousLevels) ||
        incomingLevel != oldDelegate.incomingLevel ||
        animateIncomingSample != oldDelegate.animateIncomingSample;
  }
}

enum _TrimTimelineGesture { startHandle, endHandle, scrub }

class _VoiceTrimTimeline extends StatefulWidget {
  final List<double> levels;
  final double startFraction;
  final double endFraction;
  final double playbackFraction;
  final Duration totalDuration;
  final String durationLabel;
  final void Function(double start, double end) onRangeChanged;
  final void Function(double fraction, bool commit) onSeek;
  final ValueChanged<bool> onInteractionChanged;

  const _VoiceTrimTimeline({
    required this.levels,
    required this.startFraction,
    required this.endFraction,
    required this.playbackFraction,
    required this.totalDuration,
    required this.durationLabel,
    required this.onRangeChanged,
    required this.onSeek,
    required this.onInteractionChanged,
  });

  @override
  State<_VoiceTrimTimeline> createState() => _VoiceTrimTimelineState();
}

class _VoiceTrimTimelineState extends State<_VoiceTrimTimeline> {
  static const double _handleInset = 12;
  static const double _handleTouchRadius = 24;
  _TrimTimelineGesture? _gesture;
  double? _interactionFraction;

  double _fractionForPosition(double dx, double width) {
    final trackWidth = math.max(1.0, width - (_handleInset * 2));
    return ((dx - _handleInset) / trackWidth).clamp(0.0, 1.0).toDouble();
  }

  String _formatPrecisePosition(double fraction) {
    final totalMilliseconds = widget.totalDuration.inMilliseconds;
    final milliseconds = (totalMilliseconds * fraction.clamp(0.0, 1.0)).round();
    final minutes = milliseconds ~/ Duration.millisecondsPerMinute;
    final seconds =
        (milliseconds ~/ Duration.millisecondsPerSecond) %
        Duration.secondsPerMinute;
    final tenths = (milliseconds % Duration.millisecondsPerSecond) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  void _startTimelineDrag(DragStartDetails details, double width) {
    final trackWidth = math.max(1.0, width - (_handleInset * 2));
    final startX = _handleInset + (trackWidth * widget.startFraction);
    final endX = _handleInset + (trackWidth * widget.endFraction);
    final pointerX = details.localPosition.dx;
    final startDistance = (pointerX - startX).abs();
    final endDistance = (pointerX - endX).abs();
    final closestDistance = math.min(startDistance, endDistance);
    final pointerFraction = _fractionForPosition(pointerX, width);
    final nextGesture =
        closestDistance <= _handleTouchRadius
            ? (startDistance <= endDistance
                ? _TrimTimelineGesture.startHandle
                : _TrimTimelineGesture.endHandle)
            : pointerFraction >= widget.startFraction &&
                pointerFraction <= widget.endFraction
            ? _TrimTimelineGesture.scrub
            : null;
    if (nextGesture == null) return;
    setState(() {
      _gesture = nextGesture;
      _interactionFraction =
          nextGesture == _TrimTimelineGesture.startHandle
              ? widget.startFraction
              : nextGesture == _TrimTimelineGesture.endHandle
              ? widget.endFraction
              : pointerFraction;
    });
    widget.onInteractionChanged(true);
    if (nextGesture != _TrimTimelineGesture.scrub) {
      unawaited(HapticFeedback.selectionClick());
    } else {
      widget.onSeek(pointerFraction, false);
    }
  }

  void _updateTimelineDrag(DragUpdateDetails details, double width) {
    final gesture = _gesture;
    if (gesture == null) return;
    final fraction = _fractionForPosition(details.localPosition.dx, width);
    if (gesture == _TrimTimelineGesture.startHandle) {
      final nextStart = math.min(fraction, widget.endFraction - 0.02);
      setState(() => _interactionFraction = nextStart);
      widget.onRangeChanged(nextStart, widget.endFraction);
    } else if (gesture == _TrimTimelineGesture.endHandle) {
      final nextEnd = math.max(fraction, widget.startFraction + 0.02);
      setState(() => _interactionFraction = nextEnd);
      widget.onRangeChanged(widget.startFraction, nextEnd);
    } else {
      final nextPosition =
          fraction.clamp(widget.startFraction, widget.endFraction).toDouble();
      setState(() => _interactionFraction = nextPosition);
      widget.onSeek(nextPosition, false);
    }
  }

  void _finishTimelineDrag() {
    final gesture = _gesture;
    final interactionFraction = _interactionFraction;
    if (gesture == null) return;
    if (gesture == _TrimTimelineGesture.scrub && interactionFraction != null) {
      widget.onSeek(interactionFraction, true);
    } else {
      unawaited(HapticFeedback.lightImpact());
    }
    widget.onInteractionChanged(false);
    setState(() {
      _gesture = null;
      _interactionFraction = null;
    });
  }

  void _cancelTimelineDrag() {
    if (_gesture == null) return;
    widget.onInteractionChanged(false);
    setState(() {
      _gesture = null;
      _interactionFraction = null;
    });
  }

  String get _displayLabel {
    final fraction = _interactionFraction;
    if (fraction == null) return widget.durationLabel;
    switch (_gesture) {
      case _TrimTimelineGesture.startHandle:
      case _TrimTimelineGesture.endHandle:
        return widget.durationLabel;
      case _TrimTimelineGesture.scrub:
        return _formatPrecisePosition(fraction);
      case null:
        return widget.durationLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart:
                      (details) => _startTimelineDrag(details, width),
                  onHorizontalDragUpdate:
                      (details) => _updateTimelineDrag(details, width),
                  onHorizontalDragEnd: (_) => _finishTimelineDrag(),
                  onHorizontalDragCancel: _cancelTimelineDrag,
                  onTapUp: (details) {
                    final fraction = _fractionForPosition(
                      details.localPosition.dx,
                      width,
                    );
                    if (fraction < widget.startFraction ||
                        fraction > widget.endFraction) {
                      return;
                    }
                    widget.onSeek(fraction, true);
                    unawaited(HapticFeedback.selectionClick());
                  },
                  child: CustomPaint(
                    painter: _VoiceTrimTimelinePainter(
                      levels: widget.levels,
                      startFraction: widget.startFraction,
                      endFraction: widget.endFraction,
                      playbackFraction: widget.playbackFraction,
                      handleInset: _handleInset,
                      activeGesture: _gesture,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18212C).withValues(alpha: 0.56),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 130),
                        transitionBuilder:
                            (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.18),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                        child: Text(
                          _displayLabel,
                          key: ValueKey(_displayLabel),
                          style: const TextStyle(
                            color: Color(0xFFE0E3E8),
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 15,
                            height: 1,
                            fontWeight: FontWeight.w400,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceTrimTimelinePainter extends CustomPainter {
  static const double _barWidth = 2.2;
  static const double _targetPitch = 4.5;
  final List<double> levels;
  final double startFraction;
  final double endFraction;
  final double playbackFraction;
  final double handleInset;
  final _TrimTimelineGesture? activeGesture;

  const _VoiceTrimTimelinePainter({
    required this.levels,
    required this.startFraction,
    required this.endFraction,
    required this.playbackFraction,
    required this.handleInset,
    required this.activeGesture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final capsule = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(capsule, Paint()..color = const Color(0xFF202329));
    canvas.save();
    canvas.clipRRect(capsule);

    final trackWidth = math.max(1.0, size.width - (handleInset * 2));
    final startX = handleInset + (trackWidth * startFraction);
    final endX = handleInset + (trackWidth * endFraction);
    // Keep each handle inset inside its rounded blue end-cap. The cap and
    // handle therefore track the drag as one continuous control.
    final selectionLeft = (startX - handleInset).clamp(0.0, size.width);
    final selectionRight = (endX + handleInset).clamp(0.0, size.width);
    final selectionRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(selectionLeft, 1, selectionRight, size.height - 1),
      Radius.circular((size.height - 2) / 2),
    );
    final selectionPaint =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF4D8FFF), WrytteColors.primary],
          ).createShader(selectionRect.outerRect);
    canvas.drawRRect(selectionRect, selectionPaint);
    canvas.drawRRect(
      selectionRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    final safePlayback = playbackFraction.clamp(startFraction, endFraction);
    final playbackX = handleInset + (trackWidth * safePlayback);

    final barCount = (trackWidth / _targetPitch).floor().clamp(12, 96);
    final pitch =
        barCount > 1 ? (trackWidth - _barWidth) / (barCount - 1) : 0.0;
    final barPaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < barCount; index++) {
      var level = 0.02;
      if (levels.isNotEmpty) {
        final sourceStart = ((index * levels.length) / barCount).floor();
        final sourceEnd = math.max(
          sourceStart + 1,
          (((index + 1) * levels.length) / barCount).ceil(),
        );
        var peak = 0.02;
        var energy = 0.0;
        var sampleCount = 0;
        for (
          var sourceIndex = sourceStart;
          sourceIndex < math.min(sourceEnd, levels.length);
          sourceIndex++
        ) {
          final sample = levels[sourceIndex].clamp(0.02, 1.0).toDouble();
          peak = math.max(peak, sample);
          energy += sample * sample;
          sampleCount++;
        }
        final rms = sampleCount == 0 ? 0.02 : math.sqrt(energy / sampleCount);
        level = ((peak * 0.68) + (rms * 0.32)).clamp(0.02, 1.0).toDouble();
      }
      final x = handleInset + (index * pitch);
      final barCenter = x + (_barWidth / 2);
      final selected = barCenter >= startX && barCenter <= endX;
      final played =
          selected &&
          safePlayback > startFraction + 0.001 &&
          barCenter <= playbackX;
      final barHeight = 2.5 + (level * (size.height - 17));
      final top = (size.height - barHeight) / 2;
      barPaint.color =
          !selected
              ? const Color(0xFFADB0B6).withValues(alpha: 0.82)
              : played
              ? WrytteColors.textPrimary.withValues(alpha: 0.98)
              : WrytteColors.textSecondary.withValues(alpha: 0.58);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, _barWidth, barHeight),
          const Radius.circular(_barWidth / 2),
        ),
        barPaint,
      );
    }

    const handleWidth = 4.0;
    final handleHeight = (size.height * 0.76).clamp(25.0, 27.0).toDouble();
    for (final handle in <({double x, bool active})>[
      (x: startX, active: activeGesture == _TrimTimelineGesture.startHandle),
      (x: endX, active: activeGesture == _TrimTimelineGesture.endHandle),
    ]) {
      final activeHeight = handleHeight;
      final activeWidth = handleWidth;
      final handleTop = (size.height - activeHeight) / 2;
      final handleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          handle.x - (activeWidth / 2),
          handleTop,
          activeWidth,
          activeHeight,
        ),
        Radius.circular(activeWidth / 2),
      );
      canvas.saveLayer(handleRect.outerRect.inflate(6), Paint());
      canvas.drawRRect(
        handleRect,
        Paint()
          ..color = Colors.white.withValues(alpha: handle.active ? 0.46 : 0.22)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            handle.active ? 5.0 : 3.0,
          ),
      );
      canvas.drawRRect(handleRect, Paint()..color = WrytteColors.textPrimary);
      final cutoutWidth = math.min(2.0, activeWidth * 0.50);
      const cutoutHeight = 7.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(handle.x, size.height / 2),
            width: cutoutWidth,
            height: cutoutHeight,
          ),
          Radius.circular(cutoutWidth / 2),
        ),
        Paint()..blendMode = BlendMode.clear,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VoiceTrimTimelinePainter oldDelegate) {
    return !identical(levels, oldDelegate.levels) ||
        startFraction != oldDelegate.startFraction ||
        endFraction != oldDelegate.endFraction ||
        playbackFraction != oldDelegate.playbackFraction ||
        handleInset != oldDelegate.handleInset ||
        activeGesture != oldDelegate.activeGesture;
  }
}

class _PulsingDot extends StatefulWidget {
  final int second;

  const _PulsingDot({required this.second});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.second != widget.second) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 12,
      child: AnimatedBuilder(
        animation: _controller,
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: WrytteColors.destructive,
            shape: BoxShape.circle,
          ),
        ),
        builder: (context, child) {
          final progress = _controller.value.clamp(0.0, 1.0);
          // The elapsed-second update restarts this at zero, so the dot is
          // fully red on the same frame that the displayed number changes.
          final opacity = 1 - Curves.easeInOutCubic.transform(progress);
          return Center(child: Opacity(opacity: opacity, child: child));
        },
      ),
    );
  }
}
