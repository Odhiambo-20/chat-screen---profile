part of 'message_bubble.dart';

class _RoundVideoMessageBubble extends StatefulWidget {
  final String videoUrl;
  final int? durationSeconds;
  final String? viewerTitle;
  final String viewerSubtitle;
  final Widget timeWidget;
  final bool isMine;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onDownload;
  final Future<bool> Function()? onDelete;
  final Future<void> Function()? onReply;
  final Future<void> Function()? onShowInChat;
  final Future<void> Function()? onOpenProfile;

  const _RoundVideoMessageBubble({
    required this.videoUrl,
    required this.durationSeconds,
    required this.viewerTitle,
    required this.viewerSubtitle,
    required this.timeWidget,
    required this.isMine,
    required this.onShare,
    required this.onDownload,
    required this.onDelete,
    required this.onReply,
    required this.onShowInChat,
    required this.onOpenProfile,
  });

  @override
  State<_RoundVideoMessageBubble> createState() =>
      _RoundVideoMessageBubbleState();
}

class _RoundVideoMessageBubbleState extends State<_RoundVideoMessageBubble> {
  late int _resolvedDurationSeconds;
  bool _muted = true;
  bool _expanded = false;
  bool _reserveExpandedClearance = false;
  final GlobalKey<_RoundVideoAutoplayFeedState> _feedKey =
      GlobalKey<_RoundVideoAutoplayFeedState>();

  @override
  void initState() {
    super.initState();
    _resolvedDurationSeconds = math.max(0, widget.durationSeconds ?? 0);
  }

  @override
  void didUpdateWidget(covariant _RoundVideoMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.durationSeconds != widget.durationSeconds) {
      _resolvedDurationSeconds = math.max(
        _resolvedDurationSeconds,
        widget.durationSeconds ?? 0,
      );
    }
  }

  void _handleDurationResolved(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 0 || seconds == _resolvedDurationSeconds || !mounted) {
      return;
    }
    setState(() => _resolvedDurationSeconds = seconds);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
  }

  void _collapseExpanded() {
    if (!mounted || !_expanded) return;
    setState(() {
      _expanded = false;
      _reserveExpandedClearance = false;
    });
  }

  void _prepositionForExpandedBubble(double expandedDiameter) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final media = MediaQuery.of(context);
    final bubbleTop = renderObject.localToGlobal(Offset.zero).dy;
    final safeTop = media.padding.top + 92.0;
    final safeBottom = media.size.height - media.viewInsets.bottom - 124.0;
    final targetTop = math.max(safeTop, safeBottom - expandedDiameter - 10.0);

    // Only move content upward before the pop-out. Moving it downward first is
    // the jump the user can see, especially for the last messages above the
    // composer.
    final delta = bubbleTop - targetTop;
    if (delta <= 0.5) return;

    final targetPixels = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((targetPixels - position.pixels).abs() <= 0.5) return;
    position.jumpTo(targetPixels);
  }

  void _handleBubbleTap(double expandedDiameter) {
    if (_expanded) {
      _feedKey.currentState?.togglePlaybackFromBubbleTap();
      return;
    }
    setState(() => _reserveExpandedClearance = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prepositionForExpandedBubble(expandedDiameter);
      setState(() => _expanded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final availableWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : viewportWidth - 28;
        final compactDiameter =
            math
                .min(viewportWidth * 0.58, 244.0)
                .clamp(196.0, 244.0)
                .toDouble();
        final expandedDiameter =
            math
                .min(math.min(availableWidth, viewportWidth * 0.96), 456.0)
                .clamp(compactDiameter, 456.0)
                .toDouble();
        final diameter = _expanded ? expandedDiameter : compactDiameter;
        final outlineColor =
            widget.isMine
                ? MessageBubble._blue.withValues(alpha: 0.78)
                : const Color(0xFF3A3F48);
        final reserveExpandedClearance = _expanded || _reserveExpandedClearance;
        final expandedBottomReserve =
            reserveExpandedClearance
                ? (MediaQuery.paddingOf(context).bottom + 76.0)
                : 0.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              alignment:
                  _expanded
                      ? Alignment.topCenter
                      : widget.isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _expanded ? 1 : 0),
                duration: const Duration(milliseconds: 330),
                curve: Curves.easeOutBack,
                builder: (context, expansion, child) {
                  final scale = _expanded ? 0.965 + (0.035 * expansion) : 1.0;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Align(
                  alignment:
                      _expanded
                          ? Alignment.topCenter
                          : widget.isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label:
                        _expanded
                            ? 'Pause or play video message'
                            : 'Expand video message',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _handleBubbleTap(expandedDiameter),
                      child: SizedBox(
                        width: diameter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: diameter,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Container(
                                      foregroundDecoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: outlineColor,
                                          width: _expanded ? 1.65 : 1.35,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: ColoredBox(
                                          color: Colors.black,
                                          child: _RoundVideoAutoplayFeed(
                                            key: _feedKey,
                                            source: widget.videoUrl,
                                            muted: _muted,
                                            expanded: _expanded,
                                            onExpandedPlaybackCompleted:
                                                _collapseExpanded,
                                            onDurationResolved:
                                                _handleDurationResolved,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!_expanded)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: diameter * 0.055,
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Semantics(
                                          button: true,
                                          label:
                                              _muted
                                                  ? 'Unmute video message'
                                                  : 'Mute video message',
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: _toggleMute,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF05070A,
                                                ).withValues(alpha: 0.34),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: wrytteSvgAssetIcon(
                                                  assetPath:
                                                      _muted
                                                          ? 'assets/svg/Nosound icon.svg'
                                                          : 'assets/svg/Sound icon.svg',
                                                  canvas: 15,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: EdgeInsets.only(
                                left: _expanded ? 11 : 7,
                                right: 3,
                              ),
                              child: Row(
                                key: const ValueKey('round-video-metadata-row'),
                                children: [
                                  _RoundVideoDurationBadge(
                                    durationSeconds: _resolvedDurationSeconds,
                                    showDot: _expanded,
                                  ),
                                  const Spacer(),
                                  _MediaTimeBadge(child: widget.timeWidget),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: expandedBottomReserve),
          ],
        );
      },
    );
  }
}

class _RoundVideoAutoplayFeed extends StatefulWidget {
  final String source;
  final bool muted;
  final bool expanded;
  final VoidCallback onExpandedPlaybackCompleted;
  final ValueChanged<Duration>? onDurationResolved;

  const _RoundVideoAutoplayFeed({
    super.key,
    required this.source,
    required this.muted,
    required this.expanded,
    required this.onExpandedPlaybackCompleted,
    this.onDurationResolved,
  });

  @override
  State<_RoundVideoAutoplayFeed> createState() =>
      _RoundVideoAutoplayFeedState();
}

class _RoundVideoAutoplayFeedState extends State<_RoundVideoAutoplayFeed>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Timer? _retryTimer;
  bool _autoplayKickInFlight = false;
  bool _showCenterPlay = false;
  bool _showVideoSurface = false;
  bool _expandedCompletionDispatched = false;
  int _retryCount = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialise());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _ensureAutoplaying();
    }
  }

  @override
  void didUpdateWidget(covariant _RoundVideoAutoplayFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.muted != widget.muted) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.setVolume(widget.muted ? 0 : 1));
      }
    }
    if (oldWidget.expanded != widget.expanded) {
      _expandedCompletionDispatched = false;
      _syncExpandedPlaybackMode();
      if (oldWidget.expanded && !widget.expanded && _showCenterPlay) {
        _showCenterPlay = false;
      }
    }
    if (oldWidget.source == widget.source) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
    _disposeController();
    _showVideoSurface = false;
    unawaited(_initialise());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  Future<File> _resolvePlaybackFile() async {
    final source = widget.source.trim();
    if (source.isEmpty) throw StateError('Video source is empty');
    debugPrint(
      '[RoundVideo.load] stage=resolve remote=${source.startsWith('http')} '
      'source="$source"',
    );
    final uri = Uri.tryParse(source);
    final localPath = uri?.scheme == 'file' ? uri!.toFilePath() : source;
    if (!source.startsWith('http')) {
      final localFile = File(localPath);
      if (await localFile.exists() && await localFile.length() > 0) {
        debugPrint(
          '[RoundVideo.load] stage=local_file bytes=${await localFile.length()} '
          'path="${localFile.path}"',
        );
        return localFile;
      }
      final copy = await AttachmentLocalStore.instance.ensureComplete(
        source: source,
        fileName: 'video-message.mp4',
      );
      if (copy.isComplete &&
          await copy.file.exists() &&
          await copy.file.length() > 0) {
        debugPrint(
          '[RoundVideo.load] stage=local_store_copy '
          'bytes=${await copy.file.length()} path="${copy.file.path}"',
        );
        return copy.file;
      }
      throw StateError('Local round video is missing: $source');
    }

    final cached = await AttachmentLocalStore.instance.existingComplete(
      source: source,
      fileName: 'video-message.mp4',
    );
    if (cached != null && await cached.exists() && await cached.length() > 0) {
      debugPrint(
        '[RoundVideo.load] stage=cache_hit bytes=${await cached.length()} '
        'path="${cached.path}"',
      );
      return cached;
    }

    final copy = await AttachmentLocalStore.instance.ensureComplete(
      source: source,
      fileName: 'video-message.mp4',
    );
    if (!copy.isComplete ||
        !await copy.file.exists() ||
        await copy.file.length() <= 0) {
      throw StateError('Round video download is incomplete');
    }
    debugPrint(
      '[RoundVideo.load] stage=download_complete bytes=${await copy.file.length()} '
      'path="${copy.file.path}"',
    );
    return copy.file;
  }

  Future<void> _initialise() async {
    final generation = ++_generation;
    VideoPlayerController? controller;
    try {
      _showVideoSurface = false;
      final file = await _resolvePlaybackFile();
      if (!mounted || generation != _generation) return;
      controller = VideoPlayerController.file(file);
      controller.addListener(_handlePlaybackTick);
      await controller.initialize();
      if (!mounted || generation != _generation) {
        controller.removeListener(_handlePlaybackTick);
        await controller.dispose();
        return;
      }
      await controller.setLooping(!widget.expanded);
      await controller.setVolume(widget.muted ? 0 : 1);
      _controller = controller;
      widget.onDurationResolved?.call(controller.value.duration);
      await controller.play();
      _showCenterPlay = false;
      _retryCount = 0;
      debugPrint(
        '[RoundVideo.load] stage=ready '
        'source="${widget.source}" '
        'duration_ms=${controller.value.duration.inMilliseconds} '
        'size=${controller.value.size.width}x${controller.value.size.height} '
        'file="${file.path}"',
      );
      if (mounted) setState(() {});
      _ensureAutoplaying();
    } catch (error) {
      if (controller != null && !identical(controller, _controller)) {
        controller.removeListener(_handlePlaybackTick);
        await controller.dispose();
      }
      debugPrint(
        '[RoundVideo.load] stage=failed source="${widget.source}" error="$error"',
      );
      if (mounted && generation == _generation) {
        setState(() {});
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    if (_retryCount >= 5 || _retryTimer?.isActive == true) return;
    final delayMs = 450 + (_retryCount * 350);
    _retryCount += 1;
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      unawaited(_initialise());
    });
  }

  void _handlePlaybackTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _updateVideoSurfaceVisibility(controller);
    if (widget.expanded && !_showCenterPlay && _expandedPlaybackFinished()) {
      _handleExpandedPlaybackComplete(controller);
      return;
    }
    if (_showCenterPlay) return;
    if (!controller.value.isPlaying && !controller.value.isBuffering) {
      _ensureAutoplaying();
    }
  }

  void _updateVideoSurfaceVisibility(VideoPlayerController controller) {
    if (_showVideoSurface || !mounted) return;
    final value = controller.value;
    final hasAdvanced = value.position >= const Duration(milliseconds: 120);
    if (!hasAdvanced) return;
    debugPrint(
      '[RoundVideo.load] stage=first_frame_ready '
      'position_ms=${value.position.inMilliseconds} '
      'isPlaying=${value.isPlaying} isBuffering=${value.isBuffering}',
    );
    setState(() => _showVideoSurface = true);
  }

  bool _expandedPlaybackFinished() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return false;
    return controller.value.position >=
        duration - const Duration(milliseconds: 90);
  }

  void _handleExpandedPlaybackComplete(VideoPlayerController controller) {
    if (_expandedCompletionDispatched) return;
    _expandedCompletionDispatched = true;
    unawaited(() async {
      try {
        await controller.pause();
        await controller.seekTo(Duration.zero);
        await controller.setLooping(true);
        await controller.play();
      } catch (error) {
        debugPrint(
          '[RoundVideo] expanded completion reset failed source="${widget.source}" '
          'error="$error"',
        );
      } finally {
        widget.onExpandedPlaybackCompleted();
      }
    }());
  }

  void togglePlaybackFromBubbleTap() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      if (mounted) setState(() => _showCenterPlay = true);
      unawaited(controller.pause());
      return;
    }
    setState(() => _showCenterPlay = false);
    unawaited(() async {
      if (_expandedPlaybackFinished()) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }());
  }

  void _syncExpandedPlaybackMode() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(() async {
      try {
        await controller.setLooping(!widget.expanded);
        if (widget.expanded && _expandedPlaybackFinished()) {
          await controller.seekTo(Duration.zero);
        }
        if (!_showCenterPlay) await controller.play();
      } catch (error) {
        debugPrint(
          '[RoundVideo] playback mode sync failed source="${widget.source}" '
          'error="$error"',
        );
      }
    }());
  }

  void _ensureAutoplaying() {
    if (_autoplayKickInFlight) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) return;
    _autoplayKickInFlight = true;
    unawaited(() async {
      try {
        await controller.play();
        if (mounted && _showCenterPlay) {
          setState(() => _showCenterPlay = false);
        }
      } catch (error) {
        debugPrint(
          '[RoundVideo] autoplay resume failed source="${widget.source}" '
          'error="$error"',
        );
      } finally {
        _autoplayKickInFlight = false;
      }
    }());
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _showVideoSurface = false;
    controller?.removeListener(_handlePlaybackTick);
    unawaited(controller?.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final thumbnail = Transform.scale(
      scale: 1.26,
      child: WrytteVideoThumbnail(
        key: ValueKey<String>('round-video-thumbnail-v2:${widget.source}'),
        source: widget.source,
        fit: BoxFit.cover,
      ),
    );
    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          thumbnail,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.72,
                colors: [
                  const Color(0xFF1B222B).withValues(alpha: 0.30),
                  const Color(0xFF050608).withValues(alpha: 0.46),
                ],
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: widget.expanded ? 28 : 22,
              height: widget.expanded ? 28 : 22,
              child: CircularProgressIndicator(
                strokeWidth: widget.expanded ? 2.3 : 2.0,
                color: const Color(0xFFE7ECEF).withValues(alpha: 0.86),
              ),
            ),
          ),
        ],
      );
    }

    final size = controller.value.size;
    final videoLayer = Transform.scale(
      scale: 1.26,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumbnail,
          AnimatedOpacity(
            opacity: _showVideoSurface ? 1 : 0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: videoLayer,
          ),
          if (!_showVideoSurface)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.72,
                  colors: [
                    const Color(0xFF1B222B).withValues(alpha: 0.22),
                    const Color(0xFF050608).withValues(alpha: 0.40),
                  ],
                ),
              ),
            ),
          if (widget.expanded)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder:
                        (context, value, _) => CustomPaint(
                          painter: _RoundVideoInlineProgressPainter(
                            progress: _roundVideoProgress(value),
                            paused: _showCenterPlay,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          if (widget.expanded && _showCenterPlay)
            Center(
              child: AnimatedScale(
                scale: _showCenterPlay ? 1 : 0.86,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: wrytteSvgAssetIcon(
                    assetPath: 'assets/svg/Play icon .svg',
                    canvas: 58,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _roundVideoProgress(VideoPlayerValue value) {
    final durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return 0;
    return (value.position.inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

class _RoundVideoInlineProgressPainter extends CustomPainter {
  final double progress;
  final bool paused;

  const _RoundVideoInlineProgressPainter({
    required this.progress,
    required this.paused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) / 2) - 3.0;
    if (radius <= 0) return;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (paused) {
      final trackPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.2
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFE7ECEF).withValues(alpha: 0.28);
      canvas.drawCircle(center, radius, trackPaint);
    }

    final safeProgress = progress.clamp(0.0, 1.0).toDouble();
    if (safeProgress <= 0) return;
    final activePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = paused ? 5.4 : 4.4
          ..strokeCap = paused ? StrokeCap.round : StrokeCap.butt
          ..color = const Color(0xFFF1F4F5).withValues(alpha: 0.92);
    const startAngle = -math.pi / 2;
    final sweep = math.pi * 2 * safeProgress;
    canvas.drawArc(rect, startAngle, sweep, false, activePaint);

    if (!paused) return;
    final dotAngle = startAngle + sweep;
    final dotCenter = Offset(
      center.dx + math.cos(dotAngle) * radius,
      center.dy + math.sin(dotAngle) * radius,
    );
    canvas.drawCircle(
      dotCenter,
      6.2,
      Paint()..color = const Color(0xFFF1F4F5).withValues(alpha: 0.96),
    );
  }

  @override
  bool shouldRepaint(covariant _RoundVideoInlineProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.paused != paused;
  }
}

class _RoundVideoDurationBadge extends StatelessWidget {
  final int durationSeconds;
  final bool showDot;

  const _RoundVideoDurationBadge({
    required this.durationSeconds,
    this.showDot = false,
  });

  String _format() {
    final safe = math.max(0, durationSeconds);
    final minutes = safe ~/ 60;
    final seconds = safe % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _format(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
            if (showDot) ...[
              const SizedBox(width: 5),
              Container(
                width: 4.5,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
