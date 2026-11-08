part of 'message_bubble.dart';

String? _visibleVideoCaptionText(String rawCaption) {
  final value = rawCaption.trim();
  if (value.isEmpty) return null;
  final normalized = value.toLowerCase();
  if (const <String>{
    'video',
    'attachment',
    'video message',
  }.contains(normalized)) {
    return null;
  }
  if (RegExp(
    r'^[^/\\]+\.(?:mp4|mov|m4v|webm|mkv|avi|3gp)$',
    caseSensitive: false,
  ).hasMatch(value)) {
    return null;
  }
  return _normalizeMessageForDisplay(value);
}

class _VideoMessageBubble extends StatefulWidget {
  final String videoUrl;
  final int? durationSeconds;
  final String? viewerTitle;
  final String viewerSubtitle;
  final Widget timeWidget;
  final bool isForwarded;
  final bool isMine;
  final bool showTail;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? senderName;
  final bool showAdminLabel;
  final String caption;
  final bool isStarred;
  final double trailingWidth;
  final double trailingHeight;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final Future<void> Function()? onReply;
  final Future<void> Function()? onShowInChat;
  final Future<void> Function()? onOpenProfile;

  const _VideoMessageBubble({
    required this.videoUrl,
    required this.durationSeconds,
    required this.viewerTitle,
    required this.viewerSubtitle,
    required this.timeWidget,
    required this.isForwarded,
    required this.isMine,
    required this.showTail,
    required this.mediaWidth,
    required this.mediaHeight,
    required this.senderName,
    required this.showAdminLabel,
    required this.caption,
    required this.isStarred,
    required this.trailingWidth,
    required this.trailingHeight,
    required this.onShare,
    required this.onDownload,
    required this.onEdit,
    required this.onDelete,
    required this.onReply,
    required this.onShowInChat,
    required this.onOpenProfile,
  });

  @override
  State<_VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<_VideoMessageBubble> {
  static _VideoMessageBubbleState? _activeInlinePlayer;

  double? _resolvedAspectRatio;
  VideoPlayerController? _controller;
  bool _startingPlayback = false;
  bool _muted = true;
  int _controllerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolvedAspectRatio = _metadataAspectRatio;
  }

  @override
  void didUpdateWidget(covariant _VideoMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl == widget.videoUrl &&
        oldWidget.mediaWidth == widget.mediaWidth &&
        oldWidget.mediaHeight == widget.mediaHeight) {
      return;
    }
    unawaited(_releaseInlinePlayer(rebuild: false));
    _resolvedAspectRatio = _metadataAspectRatio;
  }

  @override
  void dispose() {
    _controllerGeneration++;
    if (identical(_activeInlinePlayer, this)) {
      _activeInlinePlayer = null;
    }
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    super.dispose();
  }

  double? get _metadataAspectRatio {
    final width = widget.mediaWidth;
    final height = widget.mediaHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  Future<String> _resolvePlaybackSource() async {
    final source = widget.videoUrl.trim();
    if (source.isEmpty) throw StateError('Video is unavailable');
    if (!source.startsWith('http')) return source;
    final copy = await AttachmentLocalStore.instance.ensureComplete(
      source: source,
      fileName: 'video.mp4',
    );
    if (!copy.isComplete || !await copy.file.exists()) {
      throw StateError('Video download is incomplete');
    }
    return copy.file.path;
  }

  Future<void> _startInlinePlayback() async {
    if (_startingPlayback || _controller?.value.isInitialized == true) return;
    final previous = _activeInlinePlayer;
    if (previous != null && !identical(previous, this)) {
      await previous._releaseInlinePlayer();
    }
    if (!mounted) return;
    setState(() => _startingPlayback = true);
    final generation = ++_controllerGeneration;
    VideoPlayerController? controller;
    try {
      final path = await _resolvePlaybackSource();
      if (!mounted || generation != _controllerGeneration) return;
      controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (!mounted || generation != _controllerGeneration) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      _controller = controller;
      _activeInlinePlayer = this;
      final size = controller.value.size;
      if (!size.isEmpty) _resolvedAspectRatio = size.aspectRatio;
      await controller.play();
      if (mounted) setState(() => _startingPlayback = false);
    } catch (error) {
      if (controller != null && !identical(controller, _controller)) {
        await controller.dispose();
      }
      if (mounted && generation == _controllerGeneration) {
        setState(() => _startingPlayback = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not play this video')),
        );
      }
    }
  }

  Future<void> _releaseInlinePlayer({bool rebuild = true}) async {
    _controllerGeneration++;
    final controller = _controller;
    _controller = null;
    _startingPlayback = false;
    if (identical(_activeInlinePlayer, this)) _activeInlinePlayer = null;
    if (controller != null) {
      await controller.pause();
      await controller.dispose();
    }
    if (rebuild && mounted) setState(() {});
  }

  void _toggleInlineMute() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _muted = !_muted);
    unawaited(controller.setVolume(_muted ? 0 : 1));
  }

  Future<void> _openFullScreen() async {
    final inlineController = _controller;
    if (inlineController == null || !inlineController.value.isInitialized) {
      return;
    }
    await inlineController.pause();
    final actionTaken = await FullScreenVideoViewer.open(
      context,
      widget.videoUrl,
      title: widget.viewerTitle,
      subtitle: widget.viewerSubtitle,
      onShare: widget.onShare,
      onDownload: widget.onDownload,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onReply: widget.onReply,
      onShowInChat: widget.onShowInChat,
      onOpenProfile: widget.onOpenProfile,
    );
    if (!mounted || !identical(_controller, inlineController)) return;
    if (actionTaken == true) {
      await _releaseInlinePlayer();
    } else {
      await inlineController.setVolume(_muted ? 0 : 1);
      await inlineController.play();
    }
  }

  String? get _visibleCaption => _visibleVideoCaptionText(widget.caption);

  Size _resolveBodySize(BuildContext context, BoxConstraints constraints) {
    final mediaSize = MediaQuery.sizeOf(context);
    final tailExtent = widget.showTail ? _MessageBubbleSurface.tailExtent : 0.0;
    final constraintWidth =
        constraints.hasBoundedWidth
            ? (constraints.maxWidth - tailExtent).clamp(0.0, double.infinity)
            : mediaSize.width * 0.65;
    final maxWidth = math.min(
      constraintWidth.toDouble(),
      math.min(mediaSize.width * 0.65, 300.0),
    );
    final maxHeight = math.min(mediaSize.height * 0.42, 360.0);
    final aspect =
        (_resolvedAspectRatio ?? (4 / 3)).clamp(0.45, 2.4).toDouble();
    var width = maxWidth;
    var height = width / aspect;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }
    final minimumWidth = math.min(148.0, maxWidth);
    if (width < minimumWidth) {
      width = minimumWidth;
      height = math.min(maxHeight, width / aspect);
    }
    final captionWidth = _captionRequiredWidth(context, maxWidth);
    if (captionWidth > width) width = captionWidth;
    return Size(width, height);
  }

  double _captionRequiredWidth(BuildContext context, double maxWidth) {
    final caption = _visibleCaption;
    if (caption == null) return 0;
    final painter = TextPainter(
      text: TextSpan(
        text: caption.replaceAll('\n', ' '),
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.18,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final naturalWidth = painter.width + 20 + widget.trailingWidth + 12;
    painter.dispose();
    return naturalWidth.clamp(0.0, maxWidth).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(18));
    final bubbleColor =
        widget.isMine ? MessageBubble._blue : WrytteColors.surfaceRaised;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodySize = _resolveBodySize(context, constraints);
        final tailExtent =
            widget.showTail ? _MessageBubbleSurface.tailExtent : 0.0;
        final surfaceWidth = bodySize.width + tailExtent;
        final caption = _visibleCaption;
        final hasCaption = caption?.isNotEmpty == true;

        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment:
              widget.isMine ? Alignment.bottomRight : Alignment.bottomLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                _controller?.value.isInitialized == true
                    ? _openFullScreen
                    : _startInlinePlayback,
            child: CustomPaint(
              foregroundPainter: _MessageBubbleBorderPainter(
                isMine: widget.isMine,
                showTail: widget.showTail,
                borderRadius: borderRadius,
                color: bubbleColor,
                strokeWidth: 0.6,
              ),
              child: ClipPath(
                clipBehavior: Clip.antiAliasWithSaveLayer,
                clipper: _MessageBubbleShapeClipper(
                  isMine: widget.isMine,
                  showTail: widget.showTail,
                  borderRadius: borderRadius,
                ),
                child: SizedBox(
                  width: surfaceWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: surfaceWidth,
                        height: bodySize.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildVideoCanvas(),
                            if (widget.isForwarded ||
                                widget.senderName?.trim().isNotEmpty == true ||
                                widget.showAdminLabel)
                              Positioned(
                                left:
                                    !widget.isMine && widget.showTail
                                        ? tailExtent + 10
                                        : 10,
                                right:
                                    widget.isMine && widget.showTail
                                        ? tailExtent + 10
                                        : 10,
                                top: 9,
                                child: _MediaMessageHeader(
                                  isForwarded: widget.isForwarded,
                                  senderName: widget.senderName,
                                  showAdminLabel: widget.showAdminLabel,
                                ),
                              ),
                            if (_controller?.value.isInitialized != true)
                              Center(
                                child: _VideoPlayOverlay(
                                  loading: _startingPlayback,
                                ),
                              ),
                            if (_controller?.value.isInitialized == true)
                              Positioned(
                                left:
                                    !widget.isMine && widget.showTail
                                        ? tailExtent + 7
                                        : 7,
                                top: 7,
                                child: _InlineVideoDurationBadge(
                                  controller: _controller!,
                                  fallbackDurationSeconds:
                                      widget.durationSeconds,
                                  muted: _muted,
                                  onMuteTap: _toggleInlineMute,
                                ),
                              ),
                            if (!hasCaption)
                              Positioned(
                                right:
                                    widget.isMine && widget.showTail
                                        ? tailExtent + 6
                                        : 6,
                                bottom: 5,
                                child: _MediaTimeBadge(
                                  child: widget.timeWidget,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (hasCaption)
                        ColoredBox(
                          color: bubbleColor,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              !widget.isMine && widget.showTail
                                  ? tailExtent + 10
                                  : 10,
                              8,
                              widget.isMine && widget.showTail
                                  ? tailExtent + 10
                                  : 10,
                              8,
                            ),
                            child: _LinkedMessageText(
                              text: caption!,
                              isDeleted: false,
                              isStarred: widget.isStarred,
                              trailingWidget: widget.timeWidget,
                              trailingWidth: widget.trailingWidth,
                              trailingHeight: widget.trailingHeight,
                              expandToMaxWidth: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoCanvas() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      return ColoredBox(
        color: Colors.black,
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
    }
    return ColoredBox(
      color: Colors.black,
      child: WrytteVideoThumbnail(
        key: ValueKey<String>('message-video-thumbnail-v4:${widget.videoUrl}'),
        source: widget.videoUrl,
        fit: BoxFit.cover,
        onIntrinsicSize: _handleThumbnailSize,
      ),
    );
  }

  void _handleThumbnailSize(Size size) {
    if (!mounted || size.isEmpty) return;
    final aspectRatio = size.aspectRatio;
    final current = _resolvedAspectRatio;
    if (current != null && (current - aspectRatio).abs() < 0.001) return;
    setState(() => _resolvedAspectRatio = aspectRatio);
  }
}

class _InlineVideoDurationBadge extends StatelessWidget {
  final VideoPlayerController controller;
  final int? fallbackDurationSeconds;
  final bool muted;
  final VoidCallback onMuteTap;

  const _InlineVideoDurationBadge({
    required this.controller,
    required this.fallbackDurationSeconds,
    required this.muted,
    required this.onMuteTap,
  });

  String _format(Duration duration) {
    final totalSeconds = math.max(0, duration.inSeconds);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration =
            value.duration > Duration.zero
                ? value.duration
                : Duration(seconds: fallbackDurationSeconds ?? 0);
        final displayedDuration =
            value.position > Duration.zero ? value.position : Duration.zero;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: WrytteColors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _format(
                    displayedDuration > duration ? duration : displayedDuration,
                  ),
                  style: const TextStyle(
                    color: WrytteColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 2),
                Semantics(
                  button: true,
                  label: muted ? 'Unmute video' : 'Mute video',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onMuteTap,
                    child: SizedBox.square(
                      dimension: 24,
                      child: Center(
                        child: wrytteSvgAssetIcon(
                          assetPath:
                              muted
                                  ? 'assets/svg/Nosound icon.svg'
                                  : 'assets/svg/Sound icon.svg',
                          canvas: 13,
                          color: WrytteColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VideoPlayOverlay extends StatelessWidget {
  final bool loading;

  const _VideoPlayOverlay({required this.loading});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: loading ? 0.94 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF17191F).withValues(alpha: 0.84),
          shape: BoxShape.circle,
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: loading ? 0.46 : 1,
          child: wrytteSvgAssetIcon(
            assetPath: 'assets/svg/Play icon .svg',
            canvas: 26,
            color: WrytteColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
