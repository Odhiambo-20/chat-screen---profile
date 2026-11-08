part of 'message_bubble.dart';

String? _visibleImageCaptionText(String rawCaption) {
  final value = rawCaption.trim();
  if (value.isEmpty) return null;
  final normalized = value.toLowerCase();
  if (const <String>{
    'photo',
    'image',
    'attachment',
    'photo message',
  }.contains(normalized)) {
    return null;
  }
  if (RegExp(
    r'^[^/\\]+\.(?:jpe?g|png|webp|gif|bmp|heic|heif)$',
    caseSensitive: false,
  ).hasMatch(value)) {
    return null;
  }
  return _normalizeMessageForDisplay(value);
}

class _MediaAlbumMessageBubble extends StatefulWidget {
  final List<MediaAlbumItem> items;
  final Widget timeWidget;
  final bool isForwarded;
  final bool isMine;
  final bool showTail;
  final String? senderName;
  final bool showAdminLabel;

  const _MediaAlbumMessageBubble({
    required this.items,
    required this.timeWidget,
    required this.isForwarded,
    required this.isMine,
    required this.showTail,
    required this.senderName,
    required this.showAdminLabel,
  });

  @override
  State<_MediaAlbumMessageBubble> createState() =>
      _MediaAlbumMessageBubbleState();
}

class _MediaAlbumMessageBubbleState extends State<_MediaAlbumMessageBubble> {
  final Map<String, Size> _resolvedMediaSizes = <String, Size>{};
  int _dimensionRequest = 0;

  List<MediaAlbumItem> get items => widget.items;
  Widget get timeWidget => widget.timeWidget;
  bool get isForwarded => widget.isForwarded;
  bool get isMine => widget.isMine;
  bool get showTail => widget.showTail;
  String? get senderName => widget.senderName;
  bool get showAdminLabel => widget.showAdminLabel;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMissingMediaSizes());
  }

  @override
  void didUpdateWidget(covariant _MediaAlbumMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
      oldWidget.items.map((item) => item.imageUrl).toList(growable: false),
      widget.items.map((item) => item.imageUrl).toList(growable: false),
    )) {
      unawaited(_resolveMissingMediaSizes());
    }
  }

  Future<void> _resolveMissingMediaSizes() async {
    final request = ++_dimensionRequest;
    final resolved = <String, Size>{};
    for (final item in widget.items) {
      if ((item.width ?? 0) > 0 && (item.height ?? 0) > 0) continue;
      if (_resolvedMediaSizes.containsKey(item.id)) continue;
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      try {
        final copy = await AttachmentLocalStore.instance.ensureComplete(
          source: item.imageUrl,
          fileName: 'album_photo.jpg',
        );
        buffer = await ui.ImmutableBuffer.fromUint8List(
          await copy.file.readAsBytes(),
        );
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 0 && descriptor.height > 0) {
          resolved[item.id] = Size(
            descriptor.width.toDouble(),
            descriptor.height.toDouble(),
          );
        }
      } catch (_) {
        // A neutral ratio remains available while unavailable media retries.
      } finally {
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
    if (!mounted || request != _dimensionRequest || resolved.isEmpty) return;
    setState(() => _resolvedMediaSizes.addAll(resolved));
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(18));
    final bubbleColor =
        isMine ? MessageBubble._blue : WrytteColors.surfaceRaised;
    final albumItems = items.take(10).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final tailExtent = showTail ? _MessageBubbleSurface.tailExtent : 0.0;
        final availableWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth - tailExtent
                : screenSize.width * 0.65;
        final bodyWidth = math.min(
          availableWidth.clamp(220.0, double.infinity).toDouble(),
          math.min(screenSize.width * 0.65, 300.0),
        );
        final surfaceWidth = bodyWidth + tailExtent;
        final albumLayout = _buildAlbumLayout(surfaceWidth, albumItems);
        final collageHeight = albumLayout.height;
        final rects = albumLayout.rects;

        return CustomPaint(
          foregroundPainter: _MessageBubbleBorderPainter(
            isMine: isMine,
            showTail: showTail,
            borderRadius: borderRadius,
            color: bubbleColor,
            strokeWidth: 0.6,
          ),
          child: ClipPath(
            clipBehavior: Clip.antiAliasWithSaveLayer,
            clipper: _MessageBubbleShapeClipper(
              isMine: isMine,
              showTail: showTail,
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
                    height: collageHeight,
                    child: ColoredBox(
                      color: bubbleColor,
                      child: Stack(
                        children: [
                          for (
                            var index = 0;
                            index < albumItems.length;
                            index++
                          )
                            Positioned.fromRect(
                              rect: rects[index],
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap:
                                    albumItems[index].onTap ??
                                    () => FullScreenImageViewer.open(
                                      context,
                                      albumItems[index].imageUrl,
                                      caption: albumItems[index].caption,
                                    ),
                                onLongPressStart:
                                    albumItems[index].onLongPress == null
                                        ? null
                                        : (_) =>
                                            albumItems[index].onLongPress!(),
                                onSecondaryTap:
                                    albumItems[index].onSecondaryTap,
                                child: ClipRect(
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.20),
                                    child: WryttePersistentImage(
                                      source: albumItems[index].imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder:
                                          const _MediaLoadingPlaceholder(),
                                      errorWidget: const _AttachmentPlaceholder(
                                        icon: Icons.broken_image_outlined,
                                        label: 'Photo',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (isForwarded ||
                              senderName?.trim().isNotEmpty == true ||
                              showAdminLabel)
                            Positioned(
                              left: !isMine && showTail ? tailExtent + 10 : 10,
                              right: isMine && showTail ? tailExtent + 10 : 10,
                              top: 9,
                              child: _MediaMessageHeader(
                                isForwarded: isForwarded,
                                senderName: senderName,
                                showAdminLabel: showAdminLabel,
                              ),
                            ),
                          Positioned(
                            right: isMine && showTail ? tailExtent + 6 : 6,
                            bottom: 5,
                            child: _MediaTimeBadge(child: timeWidget),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _MediaAlbumLayout _buildAlbumLayout(
    double width,
    List<MediaAlbumItem> albumItems,
  ) {
    const gap = 2.0;
    final count = albumItems.length;
    if (count == 0) {
      return const _MediaAlbumLayout(height: 0, rects: <Rect>[]);
    }

    // Telegram bases grouped-media geometry on the source proportions. Keep
    // extreme panoramas and portraits useful without forcing unrelated media
    // into identical cells.
    final sourceRatios = <double>[
      for (final item in albumItems)
        _albumItemAspectRatio(item).clamp(0.68, 1.70).toDouble(),
    ];
    final averageRatio =
        sourceRatios.fold<double>(0, (sum, value) {
          return sum + value;
        }) /
        count;
    final ratios = <double>[
      for (final ratio in sourceRatios)
        (averageRatio > 1.1 ? math.max(1.0, ratio) : math.min(1.0, ratio))
            .clamp(0.68, 1.70)
            .toDouble(),
    ];
    final rowCounts = _chooseAlbumRows(width, ratios, averageRatio, gap);

    final rects = <Rect>[];
    var top = 0.0;
    var start = 0;
    for (final configuredRowCount in rowCounts) {
      if (start >= count) break;
      final rowCount = configuredRowCount.clamp(1, count - start).toInt();
      final availableWidth = width - (gap * (rowCount - 1));
      final ratioSum = ratios
          .skip(start)
          .take(rowCount)
          .fold<double>(0, (sum, ratio) => sum + ratio);
      final rowHeight = availableWidth / ratioSum;
      var left = 0.0;
      for (var offset = 0; offset < rowCount; offset++) {
        final isLast = offset == rowCount - 1;
        final cellWidth =
            isLast ? width - left : ratios[start + offset] * rowHeight;
        rects.add(Rect.fromLTWH(left, top, cellWidth, rowHeight));
        left += cellWidth + gap;
      }
      top += rowHeight;
      start += rowCount;
      if (start < count) top += gap;
    }

    return _MediaAlbumLayout(height: top, rects: rects);
  }

  List<int> _chooseAlbumRows(
    double width,
    List<double> ratios,
    double averageRatio,
    double gap,
  ) {
    final count = ratios.length;
    if (count <= 1) return const <int>[1];

    // Telegram treats two similarly wide images as a vertical pair and other
    // pairs as a proportional horizontal row.
    if (count == 2) {
      final similarlyWide =
          ratios.every((ratio) => ratio > 1.2) &&
          (ratios.first - ratios.last).abs() < 0.2;
      return similarlyWide ? const <int>[1, 1] : const <int>[2];
    }

    final attempts = <List<int>>[];

    void buildAttempts(int remaining, List<int> rows) {
      if (remaining == 0) {
        attempts.add(List<int>.of(rows));
        return;
      }
      if (rows.length >= 4) return;

      final rowIndex = rows.length;
      final maximumInRow = rowIndex == 1 && averageRatio < 0.85 ? 4 : 3;
      for (
        var inRow = 1;
        inRow <= maximumInRow && inRow <= remaining;
        inRow++
      ) {
        rows.add(inRow);
        buildAttempts(remaining - inRow, rows);
        rows.removeLast();
      }
    }

    buildAttempts(count, <int>[]);
    final targetHeight = width * 4 / 3;
    List<int>? bestRows;
    var bestScore = double.infinity;

    for (final rows in attempts) {
      var itemIndex = 0;
      var totalHeight = gap * (rows.length - 1);
      var minimumRowHeight = double.infinity;
      for (final rowCount in rows) {
        final ratioSum = ratios
            .skip(itemIndex)
            .take(rowCount)
            .fold<double>(0, (sum, ratio) => sum + ratio);
        final rowHeight = (width - (gap * (rowCount - 1))) / ratioSum;
        totalHeight += rowHeight;
        minimumRowHeight = math.min(minimumRowHeight, rowHeight);
        itemIndex += rowCount;
      }

      var score = (totalHeight - targetHeight).abs();
      for (var index = 0; index < rows.length - 1; index++) {
        if (rows[index] > rows[index + 1]) score *= 1.2;
      }
      if (minimumRowHeight < 78) score *= 1.5;
      if (rows.length == 1 && count > 3) score *= 1.4;

      if (score < bestScore) {
        bestScore = score;
        bestRows = rows;
      }
    }

    return bestRows ?? <int>[count];
  }

  double _albumItemAspectRatio(MediaAlbumItem item) {
    final resolved = _resolvedMediaSizes[item.id];
    final width =
        (item.width ?? 0) > 0 ? item.width!.toDouble() : resolved?.width;
    final height =
        (item.height ?? 0) > 0 ? item.height!.toDouble() : resolved?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 1;
    }
    return width / height;
  }
}

class _MediaAlbumLayout {
  final double height;
  final List<Rect> rects;

  const _MediaAlbumLayout({required this.height, required this.rects});
}

class _ImageMessageBubble extends StatefulWidget {
  final String imageUrl;
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
  final VoidCallback? onTap;

  const _ImageMessageBubble({
    required this.imageUrl,
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
    this.onTap,
  });

  @override
  State<_ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends State<_ImageMessageBubble> {
  double? _naturalAspectRatio;
  Size? _naturalPixelSize;
  late double _layoutAspectRatio;
  int _aspectRequest = 0;

  @override
  void initState() {
    super.initState();
    _naturalPixelSize = _metadataPixelSize();
    _naturalAspectRatio = _naturalPixelSize?.aspectRatio;
    _layoutAspectRatio = _naturalAspectRatio ?? (4 / 3);
    if (_naturalAspectRatio == null) unawaited(_resolveAspectRatio());
  }

  @override
  void didUpdateWidget(covariant _ImageMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl == widget.imageUrl &&
        (oldWidget.mediaWidth == widget.mediaWidth &&
            oldWidget.mediaHeight == widget.mediaHeight)) {
      return;
    }
    _aspectRequest++;
    _naturalPixelSize = _metadataPixelSize();
    _naturalAspectRatio = _naturalPixelSize?.aspectRatio;
    if (oldWidget.imageUrl != widget.imageUrl) {
      _layoutAspectRatio = _naturalAspectRatio ?? (4 / 3);
    }
    if (_naturalAspectRatio == null) unawaited(_resolveAspectRatio());
  }

  Size? _metadataPixelSize() {
    final width = widget.mediaWidth;
    final height = widget.mediaHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }

  Future<void> _resolveAspectRatio() async {
    final request = ++_aspectRequest;
    try {
      final copy = await AttachmentLocalStore.instance.ensureComplete(
        source: widget.imageUrl,
        fileName: 'photo.jpg',
      );
      final bytes = await copy.file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      descriptor.dispose();
      buffer.dispose();
      if (!mounted || request != _aspectRequest || width <= 0 || height <= 0) {
        return;
      }
      setState(() {
        _naturalPixelSize = Size(width.toDouble(), height.toDouble());
        _naturalAspectRatio = width / height;
      });
    } catch (_) {
      // Retain a neutral preview ratio when old messages have no media info.
    }
  }

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

    // Telegram-style media sizing preserves normal photo ratios, while
    // bounding extreme panoramas/portraits so controls remain usable.
    // The decoded image may arrive long after this row is visible. Keep the
    // original layout ratio so loading pixels can never resize the bubble and
    // push neighboring messages around.
    final aspect = _layoutAspectRatio.clamp(0.45, 2.4).toDouble();
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

    final tentativeSize = Size(width, height);
    if (_isUndersizedForDisplay(context, tentativeSize)) {
      width = maxWidth;
      height = math.min(maxHeight, math.max(190.0, width / aspect));
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

  bool _isUndersizedForDisplay(BuildContext context, Size displaySize) {
    final pixels = _naturalPixelSize;
    if (pixels == null || pixels.isEmpty) return false;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final requestedWidth = displaySize.width * pixelRatio;
    final requestedHeight = displaySize.height * pixelRatio;
    return pixels.width < requestedWidth * 0.85 ||
        pixels.height < requestedHeight * 0.85;
  }

  bool _needsBlurredCanvas(BuildContext context, Size displaySize) {
    if (_isUndersizedForDisplay(context, displaySize)) return true;
    final aspect = _naturalAspectRatio;
    if (aspect == null || displaySize.height <= 0) return false;
    return (displaySize.aspectRatio - aspect).abs() > 0.03;
  }

  String? get _visibleCaption => _visibleImageCaptionText(widget.caption);

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
        final useBlurredCanvas = _needsBlurredCanvas(context, bodySize);

        return GestureDetector(
          onTap:
              widget.onTap ??
              () => FullScreenImageViewer.open(context, widget.imageUrl),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment:
                widget.isMine ? Alignment.bottomRight : Alignment.bottomLeft,
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
                            _buildImageCanvas(
                              useBlurredCanvas: useBlurredCanvas,
                            ),
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

  Widget _buildImageCanvas({required bool useBlurredCanvas}) {
    if (useBlurredCanvas) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Transform.scale(
              scale: 1.16,
              child: _attachmentImage(widget.imageUrl, fit: BoxFit.cover),
            ),
          ),
          ColoredBox(color: Colors.black.withOpacity(0.10)),
          Center(child: _attachmentImage(widget.imageUrl, fit: BoxFit.contain)),
        ],
      );
    }

    return ColoredBox(
      color: Colors.black.withOpacity(0.18),
      child: Transform.scale(
        scale: 1.025,
        alignment: widget.isMine ? Alignment.bottomRight : Alignment.bottomLeft,
        child: SizedBox.expand(
          child: _attachmentImage(widget.imageUrl, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _attachmentImage(String url, {required BoxFit fit}) {
    return WryttePersistentImage(
      source: url,
      fit: fit,
      placeholder: const _MediaLoadingPlaceholder(),
      errorWidget: const _AttachmentPlaceholder(
        icon: Icons.broken_image_outlined,
        label: 'Photo',
      ),
    );
  }
}

class _MediaMessageHeader extends StatelessWidget {
  final bool isForwarded;
  final String? senderName;
  final bool showAdminLabel;

  const _MediaMessageHeader({
    required this.isForwarded,
    required this.senderName,
    required this.showAdminLabel,
  });

  @override
  Widget build(BuildContext context) {
    final sender = senderName?.trim();
    const shadow = Shadow(color: Color(0xB3000000), blurRadius: 3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isForwarded)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shortcut_rounded,
                color: Color(0xE6FFFFFF),
                size: 15,
                shadows: [shadow],
              ),
              const SizedBox(width: 4),
              Text(
                'Forwarded',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.90),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  shadows: const [shadow],
                ),
              ),
            ],
          ),
        if (sender?.isNotEmpty == true || showAdminLabel)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sender?.isNotEmpty == true)
                Flexible(
                  child: Text(
                    sender!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFC861),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      shadows: [shadow],
                    ),
                  ),
                ),
              if (showAdminLabel) ...[
                if (sender?.isNotEmpty == true) const SizedBox(width: 8),
                const Text(
                  'Admin',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    shadows: [shadow],
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _MediaTimeBadge extends StatelessWidget {
  final Widget child;

  const _MediaTimeBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.44),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class _FileMessageBubble extends StatefulWidget {
  final String fileName;
  final String fileUrl;
  final int? totalBytes;
  final int? durationSeconds;
  final String? audioTitle;
  final String? audioArtist;
  final String? audioArtworkUrl;
  final VoidCallback? onCancelTransfer;
  final ValueChanged<FileAudioPlaybackUiState?>? onPlaybackChanged;
  final String caption;
  final Widget timeWidget;
  final double timeWidth;
  final bool isForwarded;
  final bool isMine;
  final MessageStatus? status;

  const _FileMessageBubble({
    required this.fileName,
    required this.fileUrl,
    required this.totalBytes,
    required this.durationSeconds,
    required this.audioTitle,
    required this.audioArtist,
    required this.audioArtworkUrl,
    required this.onCancelTransfer,
    required this.onPlaybackChanged,
    required this.caption,
    required this.timeWidget,
    required this.timeWidth,
    required this.isForwarded,
    required this.isMine,
    required this.status,
  });

  @override
  State<_FileMessageBubble> createState() => _FileMessageBubbleState();
}

class _FileMessageBubbleState extends State<_FileMessageBubble>
    with AutomaticKeepAliveClientMixin<_FileMessageBubble> {
  bool _opening = false;
  bool _downloadingFile = false;
  int? _fileSize;
  File? _downloadedFile;
  int _fileStateGeneration = 0;
  audio_players.AudioPlayer? _audioPlayer;
  StreamSubscription<audio_players.PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioDurationSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  bool _audioPlaying = false;
  bool _playbackUiClosed = false;
  bool _playbackUiVisible = false;
  Duration _audioDuration = Duration.zero;
  final ValueNotifier<double> _audioProgress = ValueNotifier<double>(0);
  final ValueNotifier<bool> _audioPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> _audioDurationNotifier =
      ValueNotifier<Duration>(Duration.zero);
  String? _preparedAudioPath;
  Future<File?>? _ownAudioCacheFuture;

  @override
  void initState() {
    super.initState();
    _fileSize = widget.totalBytes;
    final source = widget.fileUrl.trim();
    if (source.isNotEmpty && !source.startsWith('http')) {
      _downloadedFile = File(source);
    }
    if ((widget.durationSeconds ?? 0) > 0) {
      _audioDuration = Duration(seconds: widget.durationSeconds!);
      _audioDurationNotifier.value = _audioDuration;
    }
    _scheduleFileStateRefresh();
  }

  @override
  void didUpdateWidget(covariant _FileMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.fileUrl != widget.fileUrl ||
        oldWidget.fileName != widget.fileName;
    if (sourceChanged) {
      _fileStateGeneration++;
      _fileSize = widget.totalBytes;
      _downloadedFile = null;
      _downloadingFile = false;
      _opening = false;
      _preparedAudioPath = null;
      _ownAudioCacheFuture = null;
      _audioPlaying = false;
      _audioPlayingNotifier.value = false;
      _playbackUiVisible = false;
      updateKeepAlive();
      _audioDuration = Duration(
        seconds: math.max(0, widget.durationSeconds ?? 0),
      );
      _audioDurationNotifier.value = _audioDuration;
      unawaited(_audioPlayer?.stop());
      _scheduleFileStateRefresh();
    } else if (oldWidget.totalBytes != widget.totalBytes &&
        widget.totalBytes != null) {
      _fileSize = widget.totalBytes;
    }
  }

  @override
  void dispose() {
    _fileStateGeneration++;
    unawaited(_audioStateSubscription?.cancel());
    unawaited(_audioDurationSubscription?.cancel());
    unawaited(_audioPositionSubscription?.cancel());
    unawaited(_audioPlayer?.dispose());
    _audioProgress.dispose();
    _audioPlayingNotifier.dispose();
    _audioDurationNotifier.dispose();
    super.dispose();
  }

  void _scheduleFileStateRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshFileState());
    });
  }

  Future<void> _refreshFileState() async {
    final source = widget.fileUrl.trim();
    if (source.isEmpty) return;
    final expectedSource = source;
    try {
      if (!source.startsWith('http')) {
        final local = File(source);
        if (await local.exists()) {
          final bytes = await local.length();
          if (!mounted || widget.fileUrl.trim() != expectedSource) return;
          setState(() {
            _downloadedFile = local;
            _fileSize ??= bytes;
          });
          if (_isAudioFile) unawaited(_prepareAudio(local));
        }
        return;
      }

      final persistent = await AttachmentLocalStore.instance.existingComplete(
        source: source,
        fileName: widget.fileName,
      );
      if (persistent != null && await persistent.exists()) {
        final bytes = await persistent.length();
        if (!mounted || widget.fileUrl.trim() != expectedSource) return;
        setState(() {
          _downloadedFile = persistent;
          _fileSize ??= bytes;
        });
        if (_isAudioFile) unawaited(_prepareAudio(persistent));
        return;
      }

      if (widget.isMine && _isAudioFile) {
        final restored = await _ensureOwnAudioLocalCopy();
        if (restored != null) return;
      }

      if (_fileSize != null) return;
      final client = http.Client();
      try {
        final response = await client
            .head(Uri.parse(source))
            .timeout(const Duration(seconds: 12));
        final bytes =
            response.statusCode >= 200 && response.statusCode < 300
                ? int.tryParse(response.headers['content-length'] ?? '')
                : null;
        if (!mounted || widget.fileUrl.trim() != expectedSource) return;
        setState(() => _fileSize = bytes);
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  Future<void> _handleFileTap() async {
    if (_downloadingFile ||
        (widget.isMine && widget.status == MessageStatus.sending)) {
      return;
    }
    final source = widget.fileUrl.trim();
    if (!widget.isMine &&
        source.startsWith('http') &&
        _downloadedFile == null) {
      await _downloadRemoteFile();
      return;
    }
    if (_isAudioFile) {
      await _toggleAudioPlayback();
      return;
    }
    await _openDownloadedFile();
  }

  Future<void> _downloadRemoteFile() async {
    if (_opening || _downloadingFile) return;
    final source = widget.fileUrl.trim();
    if (source.isEmpty || !source.startsWith('http')) return;
    final generation = ++_fileStateGeneration;
    setState(() {
      _opening = true;
      _downloadingFile = true;
    });
    try {
      final copy = await AttachmentLocalStore.instance.ensureComplete(
        source: source,
        fileName: widget.fileName,
      );
      final bytes = await copy.file.length();
      if (!mounted ||
          generation != _fileStateGeneration ||
          widget.fileUrl.trim() != source) {
        return;
      }
      setState(() {
        _downloadedFile = copy.file;
        _fileSize ??= bytes;
      });
      if (_isAudioFile) unawaited(_prepareAudio(copy.file));
    } catch (error) {
      if (!mounted || generation != _fileStateGeneration) return;
      _showFileError(error);
    } finally {
      if (mounted && generation == _fileStateGeneration) {
        setState(() {
          _opening = false;
          _downloadingFile = false;
        });
      }
    }
  }

  void _cancelFileDownload() {
    if (!_downloadingFile) return;
    _fileStateGeneration++;
    setState(() {
      _opening = false;
      _downloadingFile = false;
    });
  }

  Future<void> _openDownloadedFile() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final source = widget.fileUrl.trim();
      if (source.isEmpty) throw StateError('File URL is unavailable');

      File sourceFile;
      if (_downloadedFile != null) {
        sourceFile = _downloadedFile!;
      } else if (!source.startsWith('http')) {
        sourceFile = File(source);
      } else {
        if (mounted) setState(() => _downloadingFile = true);
        sourceFile =
            (await AttachmentLocalStore.instance.ensureComplete(
              source: source,
              fileName: widget.fileName,
            )).file;
      }
      if (!await sourceFile.exists()) {
        throw const FileSystemException('Downloaded file is unavailable');
      }
      _downloadedFile = sourceFile;
      _fileSize ??= await sourceFile.length();

      final result = await OpenFilex.open(sourceFile.path);
      if (result.type != ResultType.done) {
        throw StateError(result.message);
      }
    } catch (error) {
      if (!mounted) return;
      _showFileError(error);
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _downloadingFile = false;
        });
      }
    }
  }

  void _showFileError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open file: $error'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  bool get _isAudioFile {
    final extension =
        p.extension(widget.fileName).replaceFirst('.', '').toUpperCase();
    return _isAudioExtension(extension);
  }

  Future<audio_players.AudioPlayer> _ensureAudioPlayer() async {
    final existing = _audioPlayer;
    if (existing != null) return existing;
    final player = audio_players.AudioPlayer();
    _audioStateSubscription = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      final playing = state == audio_players.PlayerState.playing;
      if (_audioPlaying != playing) {
        setState(() => _audioPlaying = playing);
        _audioPlayingNotifier.value = playing;
        if (!_playbackUiClosed) _notifyPlaybackUi();
      }
    });
    _audioDurationSubscription = player.onDurationChanged.listen((duration) {
      if (!mounted || duration <= Duration.zero) return;
      if (_audioDuration != duration) {
        setState(() => _audioDuration = duration);
        _audioDurationNotifier.value = duration;
      }
    });
    _audioPositionSubscription = player.onPositionChanged.listen((position) {
      final durationMs = _audioDuration.inMilliseconds;
      final progress =
          durationMs <= 0
              ? 0.0
              : (position.inMilliseconds / durationMs)
                  .clamp(0.0, 1.0)
                  .toDouble();
      if ((_audioProgress.value - progress).abs() > 0.002) {
        _audioProgress.value = progress;
      }
    });
    _audioPlayer = player;
    return player;
  }

  Future<void> _prepareAudio(File file) async {
    if (!_isAudioFile || !await file.exists()) return;
    final path = file.path;
    if (_preparedAudioPath == path) return;
    try {
      final player = await _ensureAudioPlayer();
      await player.setSource(audio_players.DeviceFileSource(path));
      final duration = await player.getDuration();
      if (!mounted) return;
      setState(() {
        _preparedAudioPath = path;
        if (duration != null && duration > Duration.zero) {
          _audioDuration = duration;
          _audioDurationNotifier.value = duration;
        }
      });
    } catch (_) {
      // Unsupported/corrupt audio remains a normal openable file bubble.
    }
  }

  Future<void> _toggleAudioPlayback() async {
    _playbackUiClosed = false;
    debugPrint(
      '[AudioAttachment] tap source="${widget.fileUrl}" '
      'fileName="${widget.fileName}" cached=${_downloadedFile?.path ?? ''}',
    );
    var file = _downloadedFile;
    if ((file == null || !await file.exists()) && widget.isMine) {
      file = await _ensureOwnAudioLocalCopy();
    }
    if (file == null || !await file.exists()) {
      final source = widget.fileUrl.trim();
      if (source.isEmpty) {
        _showFileError(StateError('Audio URL is unavailable'));
        return;
      }
      try {
        setState(() {
          _opening = true;
          _downloadingFile = true;
        });
        final localSource = Uri.tryParse(source);
        if (localSource?.scheme == 'file') {
          file = File(localSource!.toFilePath());
        } else if (!source.startsWith('http')) {
          file = File(source);
        } else {
          file = (await AttachmentLocalStore.instance.ensureComplete(
            source: source,
            fileName: widget.fileName,
          )).file;
        }
        if (file == null || !await file.exists()) {
          throw const FileSystemException('Downloaded audio is unavailable');
        }
        _downloadedFile = file;
        debugPrint(
          '[AudioAttachment] local_ready path="${file?.path ?? ''}" '
          'bytes=${file == null ? 0 : await file.length()}',
        );
      } catch (error) {
        debugPrint('[AudioAttachment] download_failed error="$error"');
        _showFileError(error);
        return;
      } finally {
        if (mounted) {
          setState(() {
            _opening = false;
            _downloadingFile = false;
          });
        }
      }
    }
    final audioFile = file;
    if (audioFile == null || !await audioFile.exists()) {
      _showFileError(const FileSystemException('Audio file is unavailable'));
      return;
    }
    try {
      final player = await _ensureAudioPlayer();
      if (_audioPlaying) {
        await player.pause();
        return;
      }
      if (_preparedAudioPath != audioFile.path) {
        await _prepareAudio(audioFile);
      }
      final state = player.state;
      if (state == audio_players.PlayerState.paused) {
        await player.resume();
      } else {
        await player.play(audio_players.DeviceFileSource(audioFile.path));
      }
    } catch (error) {
      _showFileError(error);
    }
  }

  Future<void> _seekAudioPlayback(double progress) async {
    final player = _audioPlayer;
    final duration = _audioDuration;
    if (player == null || duration <= Duration.zero) return;
    final value = progress.clamp(0.0, 1.0).toDouble();
    await player.seek(
      Duration(milliseconds: (duration.inMilliseconds * value).round()),
    );
    _audioProgress.value = value;
  }

  Future<File?> _ensureOwnAudioLocalCopy() {
    final existingOperation = _ownAudioCacheFuture;
    if (existingOperation != null) return existingOperation;
    final operation = _restoreOwnAudioLocalCopy();
    _ownAudioCacheFuture = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_ownAudioCacheFuture, operation)) {
          _ownAudioCacheFuture = null;
        }
      }),
    );
    return operation;
  }

  Future<File?> _restoreOwnAudioLocalCopy() async {
    if (!widget.isMine || !_isAudioFile) return null;
    final source = widget.fileUrl.trim();
    if (source.isEmpty) return null;

    if (!source.startsWith('http')) {
      final local = File(source);
      if (!await local.exists()) return null;
      if (mounted && widget.fileUrl.trim() == source) {
        setState(() => _downloadedFile = local);
        unawaited(_prepareAudio(local));
      }
      return local;
    }

    try {
      final copy = await AttachmentLocalStore.instance.ensureComplete(
        source: source,
        fileName: widget.fileName,
      );
      if (!copy.isComplete || !await copy.file.exists()) return null;
      if (!mounted || widget.fileUrl.trim() != source) return copy.file;
      final bytes = await copy.file.length();
      setState(() {
        _downloadedFile = copy.file;
        _fileSize ??= bytes;
      });
      unawaited(_prepareAudio(copy.file));
      return copy.file;
    } catch (_) {
      return null;
    }
  }

  void _notifyPlaybackUi() {
    final callback = widget.onPlaybackChanged;
    if (callback == null || !_isAudioFile) return;
    if (!_playbackUiVisible) {
      _playbackUiVisible = true;
      updateKeepAlive();
    }
    callback(
      FileAudioPlaybackUiState(
        id: widget.fileUrl,
        title: _audioTitle,
        artist: _audioArtist,
        artworkUrl: widget.audioArtworkUrl,
        isPlaying: _audioPlaying,
        playing: _audioPlayingNotifier,
        progress: _audioProgress,
        duration: _audioDurationNotifier,
        togglePlayback: _toggleAudioPlayback,
        seek: _seekAudioPlayback,
        close: _closeAudioPlayback,
      ),
    );
  }

  Future<void> _closeAudioPlayback() async {
    _playbackUiClosed = true;
    _playbackUiVisible = false;
    updateKeepAlive();
    await _audioPlayer?.stop();
    _audioPlayingNotifier.value = false;
    _audioProgress.value = 0;
    widget.onPlaybackChanged?.call(null);
  }

  bool get _showDownloadingVisual =>
      _downloadingFile ||
      (widget.isMine && widget.status == MessageStatus.sending);

  String? get _fileDetailsText {
    final total = _fileSize;
    if (_showDownloadingVisual) {
      return total == null
          ? _formatFileBytes(0)
          : '${_formatFileBytes(0)} / ${_formatFileBytes(total)}';
    }
    return total == null ? null : _formatFileBytes(total);
  }

  Widget _buildFileActionControl({
    required String extension,
    required Color iconBackground,
    required Color iconForeground,
    required bool showDownload,
    required bool showDownloading,
    required File? downloadedFile,
  }) {
    if (showDownloading) {
      final loadingForeground = iconForeground;
      final loadingControl = SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(
              child: RepaintBoundary(
                child: SizedBox.square(
                  dimension: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    strokeCap: StrokeCap.round,
                    color: loadingForeground,
                    backgroundColor: loadingForeground.withOpacity(0.20),
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(
                Icons.close_rounded,
                color: loadingForeground,
                size: 23,
              ),
            ),
          ],
        ),
      );
      final onCancel =
          widget.onCancelTransfer ??
          (_downloadingFile ? _cancelFileDownload : null);
      if (onCancel == null) return loadingControl;
      return Semantics(
        button: true,
        label:
            widget.onCancelTransfer == null
                ? 'Cancel download'
                : 'Cancel upload',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancel,
          child: loadingControl,
        ),
      );
    }
    if (showDownload) {
      if (_isAudioExtension(extension) &&
          widget.audioArtworkUrl?.trim().isNotEmpty == true) {
        return SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildDownloadedFileVisual(
                extension: extension,
                iconBackground: iconBackground,
                iconForeground: iconForeground,
                downloadedFile: downloadedFile,
                showAudioPlayback: false,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.34),
                  shape: BoxShape.circle,
                ),
              ),
              const Center(
                child: Icon(
                  Icons.file_download_outlined,
                  color: WrytteColors.textPrimary,
                  size: 27,
                ),
              ),
            ],
          ),
        );
      }
      return Icon(
        Icons.file_download_outlined,
        color: iconForeground,
        size: 26,
      );
    }
    return _buildDownloadedFileVisual(
      extension: extension,
      iconBackground: iconBackground,
      iconForeground: iconForeground,
      downloadedFile: downloadedFile,
    );
  }

  Widget _buildDownloadedFileVisual({
    required String extension,
    required Color iconBackground,
    required Color iconForeground,
    required File? downloadedFile,
    bool showVideoPlay = true,
    bool showAudioPlayback = true,
  }) {
    if (_isAudioExtension(extension)) {
      final hasArtwork = widget.audioArtworkUrl?.trim().isNotEmpty == true;
      return SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color:
                    hasArtwork
                        ? Colors.black.withValues(alpha: 0.18)
                        : iconBackground,
                shape: BoxShape.circle,
              ),
            ),
            if (hasArtwork)
              ClipOval(
                child: _buildAudioArtwork(widget.audioArtworkUrl!.trim()),
              ),
            if (hasArtwork)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
              ),
            if (showAudioPlayback)
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 170),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  child: Icon(
                    _audioPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey<bool>(_audioPlaying),
                    color:
                        hasArtwork ? WrytteColors.textPrimary : iconForeground,
                    size: 29,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (downloadedFile != null && _isImageExtension(extension)) {
      return ClipOval(
        child: SizedBox.expand(
          child: Image.file(
            downloadedFile,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            gaplessPlayback: true,
            errorBuilder:
                (context, error, stackTrace) => _buildFileTypeIcon(
                  extension: extension,
                  iconBackground: iconBackground,
                  iconForeground: iconForeground,
                ),
          ),
        ),
      );
    }
    if (_isVideoExtension(extension)) {
      final previewSource =
          downloadedFile?.path ??
          (widget.isMine && widget.fileUrl.trim().isNotEmpty
              ? widget.fileUrl.trim()
              : null);
      if (previewSource != null) {
        return ClipOval(
          child: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                WrytteVideoThumbnail(
                  key: ValueKey<String>('file-video-preview:$previewSource'),
                  source: previewSource,
                  fit: BoxFit.cover,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                ),
                if (showVideoPlay)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(left: 1.5),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 29,
                        color: WrytteColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }
    return _buildFileTypeIcon(
      extension: extension,
      iconBackground: iconBackground,
      iconForeground: iconForeground,
    );
  }

  Widget _buildAudioArtwork(String source) {
    final cleanSource = source.trim();
    final uri = Uri.tryParse(cleanSource);
    final isRemote =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mxc');
    if (!isRemote) {
      final localPath = uri?.scheme == 'file' ? uri!.toFilePath() : cleanSource;
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    return WryttePersistentImage(
      source: cleanSource,
      fit: BoxFit.cover,
      errorWidget: const SizedBox.shrink(),
    );
  }

  Widget _buildFileTypeIcon({
    required String extension,
    required Color iconBackground,
    required Color iconForeground,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.insert_drive_file_rounded, color: iconForeground, size: 34),
        if (extension.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              extension.length > 4 ? extension.substring(0, 4) : extension,
              style: TextStyle(
                color: iconBackground,
                fontSize: 7.5,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }

  bool _isImageExtension(String extension) => const <String>{
    'JPG',
    'JPEG',
    'PNG',
    'WEBP',
    'GIF',
    'BMP',
    'HEIC',
    'HEIF',
  }.contains(extension);

  bool _isVideoExtension(String extension) => const <String>{
    'MP4',
    'MOV',
    'M4V',
    'WEBM',
    'MKV',
    '3GP',
  }.contains(extension);

  bool _isAudioExtension(String extension) => const <String>{
    'MP3',
    'M4A',
    'AAC',
    'WAV',
    'OGG',
    'OPUS',
    'FLAC',
    'WMA',
    'AMR',
  }.contains(extension);

  String get _audioTitle {
    final metadataTitle = widget.audioTitle?.trim() ?? '';
    if (metadataTitle.isNotEmpty) return metadataTitle;
    final fallback = p.basenameWithoutExtension(
      _cleanFileNameForDisplay(widget.fileName),
    );
    return fallback.isEmpty ? 'Audio file' : fallback;
  }

  String get _audioFileNameForDisplay {
    final originalName = _cleanFileNameForDisplay(widget.fileName);
    final extension = p.extension(originalName);
    final title = _cleanFileNameForDisplay(_audioTitle);
    if (extension.toLowerCase() == '.mp3') {
      return title.toLowerCase().endsWith('.mp3')
          ? title.substring(0, title.length - 4).trimRight()
          : title;
    }
    if (extension.isEmpty ||
        title.toLowerCase().endsWith(extension.toLowerCase())) {
      return title;
    }
    return '$title$extension';
  }

  String? get _audioArtist {
    final artist = widget.audioArtist?.trim() ?? '';
    return artist.isEmpty ? null : artist;
  }

  String? get _audioDurationLabel {
    final seconds =
        _audioDuration > Duration.zero
            ? _audioDuration.inSeconds
            : math.max(0, widget.durationSeconds ?? 0);
    if (seconds <= 0) return null;
    final minutes = seconds ~/ 60;
    final remainder = seconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  Widget _buildAudioMetadataLine() {
    final duration = _audioDurationLabel;
    final size = _fileDetailsText;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Row(
        key: ValueKey<String>('audio-meta:$duration:$size'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/svg/Audio icon.svg',
            width: 15,
            height: 15,
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(
              Color(0xBFC6C6C6),
              BlendMode.srcIn,
            ),
          ),
          if (duration != null) ...[const SizedBox(width: 3), Text(duration)],
          if (duration != null && size != null) ...[
            const SizedBox(width: 7),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0x99C6C6C6),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
          ],
          if (size != null) Text(size),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sourceFileName = _cleanFileNameForDisplay(widget.fileName);
    final extension =
        p.extension(sourceFileName).replaceFirst('.', '').toUpperCase();
    final isAudioFile = _isAudioExtension(extension);
    final iconBackground =
        widget.isMine ? WrytteColors.textPrimary : WrytteColors.primary;
    final iconForeground =
        widget.isMine ? WrytteColors.primary : WrytteColors.textPrimary;
    final isRemoteFile = widget.fileUrl.trim().startsWith('http');
    final isSendingFile =
        widget.isMine && widget.status == MessageStatus.sending;
    final showDownloadingVisual = _showDownloadingVisual;
    final showDownloadState =
        !widget.isMine &&
        isRemoteFile &&
        _downloadedFile == null &&
        !_downloadingFile;
    final hasCaption = widget.caption.trim().isNotEmpty;
    const fileNameStyle = TextStyle(
      color: WrytteColors.textPrimary,
      fontSize: 17.5,
      fontWeight: FontWeight.w500,
      height: 1,
    );
    const audioArtistStyle = TextStyle(
      color: Color(0xBFC6C6C6),
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
      height: 1,
    );
    const audioMetadataStyle = TextStyle(
      color: Color(0xBFC6C6C6),
      fontSize: 11,
      fontWeight: FontWeight.w400,
      height: 1,
    );
    final effectiveFileNameStyle = DefaultTextStyle.of(
      context,
    ).style.merge(fileNameStyle);
    final fileNameForDisplay =
        isAudioFile ? _audioFileNameForDisplay : sourceFileName;
    final displayedTitle = fileNameForDisplay;
    final titleForWidth =
        extension == 'MP3'
            ? _mp3TitleUsedForWidth(displayedTitle)
            : displayedTitle;
    final hasAudioArtist = isAudioFile && _audioArtist != null;

    // Contacts, files, audio artwork and every download state share one circle.
    const previewSize = _sharedAttachmentCircleSize;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    double measuredTextWidth(String? text, TextStyle style) {
      if (text == null || text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final nameWidth = measuredTextWidth(titleForWidth, effectiveFileNameStyle);
    final artistWidth = measuredTextWidth(_audioArtist, audioArtistStyle);
    final duration = isAudioFile ? _audioDurationLabel : null;
    final size = _fileDetailsText;
    var metadataWidth = isAudioFile ? 15.0 : 0.0;
    if (duration != null) {
      metadataWidth += 3 + measuredTextWidth(duration, audioMetadataStyle);
    }
    if (duration != null && size != null) metadataWidth += 7 + 4 + 7;
    if (size != null) {
      metadataWidth += measuredTextWidth(size, audioMetadataStyle);
    }
    // Both metadata and the measured timestamp/checkmarks occupy the lower row.
    const metadataToTimestampGap = 12.0;
    final lowerRowWidth =
        metadataWidth + metadataToTimestampGap + widget.timeWidth;
    const fileNameRightInset = 4.0;
    final safeNameWidth =
        nameWidth + fileNameRightInset + _fileNamePaintSafetyWidth;
    final requiredTextWidth = math.max(
      safeNameWidth,
      math.max(artistWidth, lowerRowWidth),
    );
    final baseMinimumFileWidth = hasCaption ? 226.0 : 190.0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final responsiveMaximum = math.min(342.0, viewportWidth - 72);
    final maximumFileWidth = math.max(baseMinimumFileWidth, responsiveMaximum);
    final fileBubbleWidth =
        math
            .max(baseMinimumFileWidth, 58 + requiredTextWidth)
            .clamp(baseMinimumFileWidth, maximumFileWidth)
            .toDouble();
    return GestureDetector(
      onTap: _handleFileTap,
      child: SizedBox(
        key: const ValueKey<String>('file-bubble-content'),
        width: fileBubbleWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isForwarded) const _ForwardedLabel(),
            SizedBox(
              height: isAudioFile ? (hasAudioArtist ? 66 : 56) : 52,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Container(
                      key: const ValueKey<String>('file-preview-circle'),
                      width: previewSize,
                      height: previewSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final scale = Tween<double>(
                            begin: 0.88,
                            end: 1,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(
                            showDownloadingVisual
                                ? 'downloading'
                                : showDownloadState
                                ? 'download'
                                : isAudioFile
                                ? 'audio:$_audioPlaying'
                                : 'file',
                          ),
                          child: _buildFileActionControl(
                            extension: extension,
                            iconBackground: iconBackground,
                            iconForeground: iconForeground,
                            showDownload: showDownloadState,
                            showDownloading: showDownloadingVisual,
                            downloadedFile: _downloadedFile,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: LayoutBuilder(
                      builder:
                          (context, constraints) => Stack(
                            // No-author compact files use the extra outer bottom
                            // padding as metadata space, so let the timestamp sit
                            // lower without changing the bubble/tail geometry.
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: 0,
                                top: isAudioFile ? 3 : 3,
                                right: 4,
                                child: _ExtensionSafeFileName(
                                  key: const ValueKey<String>('file-name'),
                                  fileName: fileNameForDisplay,
                                  maxCharacters:
                                      extension == 'MP3'
                                          ? _mp3UntruncatedCharacterLimit
                                          : null,
                                  style: effectiveFileNameStyle,
                                  maxWidth: math.max(
                                    0,
                                    constraints.maxWidth - 4,
                                  ),
                                ),
                              ),
                              if (hasAudioArtist)
                                Positioned(
                                  left: 0,
                                  top: 29,
                                  right: 4,
                                  child: Text(
                                    _audioArtist!,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: audioArtistStyle,
                                  ),
                                ),
                              Positioned(
                                left: 0,
                                right: null,
                                top:
                                    isAudioFile && !hasAudioArtist
                                        ? 29
                                        : !isAudioFile
                                        ? 28
                                        : null,
                                bottom:
                                    hasAudioArtist
                                        // The metadata row is 15 px tall due
                                        // to the Sound SVG, while the time
                                        // label has a shorter text box. This
                                        // offset aligns their visual baselines.
                                        ? -2
                                        : null,
                                child: DefaultTextStyle(
                                  style: audioMetadataStyle,
                                  child:
                                      isAudioFile
                                          ? Align(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: 1,
                                            child: _buildAudioMetadataLine(),
                                          )
                                          : AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            switchInCurve: Curves.easeOut,
                                            switchOutCurve: Curves.easeIn,
                                            child:
                                                _fileDetailsText == null
                                                    ? const SizedBox(
                                                      key: ValueKey(
                                                        'file-size-empty',
                                                      ),
                                                      height: 13,
                                                    )
                                                    : Text(
                                                      _fileDetailsText!,
                                                      key: const ValueKey(
                                                        'file-size',
                                                      ),
                                                    ),
                                          ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                // Files without an author/artist deliberately use
                                // extra vertical bubble padding. Drop the timestamp
                                // into that reserved lower space so it sits where it
                                // would if an author row were present.
                                bottom: hasAudioArtist ? 0 : -8,
                                child: widget.timeWidget,
                              ),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.only(top: 7, left: 2, right: 2),
                child: Text(
                  widget.caption.trim(),
                  style: const TextStyle(
                    color: WrytteColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => _playbackUiVisible;

  String _formatFileBytes(int bytes) {
    final safeBytes = math.max(0, bytes);
    if (safeBytes < 1024 * 1024) {
      if (safeBytes == 0) return '0 KB';
      final kilobytes = safeBytes / 1024;
      return '${kilobytes.toStringAsFixed(kilobytes < 10 ? 1 : 0)} KB';
    }
    if (safeBytes < 1024 * 1024 * 1024) {
      final megabytes = safeBytes / (1024 * 1024);
      return '${megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1)} MB';
    }
    final gigabytes = safeBytes / (1024 * 1024 * 1024);
    return '${gigabytes.toStringAsFixed(gigabytes >= 10 ? 0 : 1)} GB';
  }
}

class _ExtensionSafeFileName extends StatelessWidget {
  final String fileName;
  final int? maxCharacters;
  final TextStyle style;
  final double maxWidth;

  const _ExtensionSafeFileName({
    super.key,
    required this.fileName,
    this.maxCharacters,
    required this.style,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final cleanFileName = _cleanFileNameForDisplay(fileName);
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    double textWidth(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        maxLines: 1,
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final safeMaxWidth = math.max(0.0, maxWidth - _fileNamePaintSafetyWidth);
    final exceedsCharacterLimit =
        maxCharacters != null &&
        cleanFileName.characters.length > maxCharacters!;
    if (!exceedsCharacterLimit && textWidth(cleanFileName) <= safeMaxWidth) {
      return Text(cleanFileName, maxLines: 1, softWrap: false, style: style);
    }
    if (maxCharacters != null && !exceedsCharacterLimit) {
      // A short MP3 title should stay complete. Scale it down only when the
      // parent width is tighter than the requested adaptive bubble width.
      return SizedBox(
        width: safeMaxWidth,
        height: textScaler.scale(style.fontSize ?? 14) * (style.height ?? 1.2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            cleanFileName,
            maxLines: 1,
            softWrap: false,
            style: style,
          ),
        ),
      );
    }

    final extension = p.extension(cleanFileName);
    final extensionLabel =
        extension.startsWith('.') ? extension.substring(1) : extension;
    final suffix =
        extensionLabel.isEmpty
            ? _fileNameTruncationMarker
            : '$_fileNameTruncationMarker$extensionLabel';
    final rawStem =
        extension.isEmpty
            ? cleanFileName
            : cleanFileName
                .substring(0, cleanFileName.length - extension.length)
                .trimRight();
    final stemCharacters = rawStem.characters;
    var low = 0;
    var high = math.min(
      stemCharacters.length,
      maxCharacters ?? stemCharacters.length,
    );
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      final candidate =
          '${stemCharacters.take(middle).toString().trimRight()}$suffix';
      if (textWidth(candidate) <= safeMaxWidth) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    // Drop one additional whole grapheme so the final fitted character never
    // sits on the paint boundary. The extension remains untouched.
    final safeStemLength = math.max(0, low - 1);
    final visibleStem =
        stemCharacters.take(safeStemLength).toString().trimRight();
    return Text(
      '$visibleStem$suffix',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: style,
    );
  }
}

const String _fileNameTruncationMarker = '...';
const double _fileNamePaintSafetyWidth = 14.0;
const int _mp3UntruncatedCharacterLimit = 18;

String _mp3TitleUsedForWidth(String value) {
  final characters = value.characters;
  if (characters.length <= _mp3UntruncatedCharacterLimit) return value;
  final visibleTitle =
      characters.take(_mp3UntruncatedCharacterLimit).toString().trimRight();
  return '$visibleTitle$_fileNameTruncationMarker';
}

String _cleanFileNameForDisplay(String value) {
  final normalizedSeparators = value.trim().replaceAll('\\', '/');
  final baseName = p.basename(normalizedSeparators).trim();
  final singleLine = baseName.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  return singleLine.isEmpty ? 'File' : singleLine;
}

class _MediaLoadingPlaceholder extends StatefulWidget {
  const _MediaLoadingPlaceholder();

  @override
  State<_MediaLoadingPlaceholder> createState() =>
      _MediaLoadingPlaceholderState();
}

class _MediaLoadingPlaceholderState extends State<_MediaLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF242A34),
                    Color(0xFF151A22),
                    Color(0xFF07090D),
                  ],
                  stops: [0, 0.56, 1],
                ),
              ),
            ),
            LayoutBuilder(
              builder:
                  (context, constraints) => AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final width =
                          constraints.hasBoundedWidth
                              ? constraints.maxWidth
                              : 220.0;
                      final offset = (width * 1.8 * _controller.value) - width;
                      return Transform.translate(
                        offset: Offset(offset, 0),
                        child: FractionallySizedBox(
                          widthFactor: 0.32,
                          alignment: Alignment.centerLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.08),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AttachmentPlaceholder({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 34),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ForwardedLabel extends StatelessWidget {
  const _ForwardedLabel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shortcut_rounded,
            color: Colors.white.withOpacity(0.62),
            size: 15,
          ),
          const SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
