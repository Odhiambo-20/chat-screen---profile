part of 'message_bubble.dart';

class _ContactMessageBubble extends StatelessWidget {
  final String? name;
  final String? phone;
  final String? avatarUrl;
  final String? userId;
  final Widget timeWidget;
  final bool isMine;
  final bool isForwarded;
  final String? replyPreview;
  final String? replySender;
  final VoidCallback? onReplyTap;
  final Future<void> Function()? onMessage;
  final Future<void> Function()? onAddContact;

  const _ContactMessageBubble({
    required this.name,
    required this.phone,
    required this.avatarUrl,
    required this.userId,
    required this.timeWidget,
    required this.isMine,
    required this.isForwarded,
    required this.replyPreview,
    required this.replySender,
    required this.onReplyTap,
    required this.onMessage,
    required this.onAddContact,
  });

  @override
  Widget build(BuildContext context) {
    final cleanName =
        name?.trim().isNotEmpty == true ? name!.trim() : 'Contact';
    final cleanPhone = phone?.trim() ?? '';
    final cleanAvatarUrl = avatarUrl?.trim() ?? '';
    debugPrint(
      '[ContactMessageBubble] build name="$cleanName" user_id="${userId ?? ''}" '
      'avatar=${cleanAvatarUrl.isNotEmpty} url="$cleanAvatarUrl"',
    );
    final subtitle = cleanPhone.isNotEmpty ? cleanPhone : 'Contact';
    final actionColor = isMine ? Colors.white : WrytteColors.primary;
    final dividerColor = Colors.white.withOpacity(isMine ? 0.26 : 0.12);
    const metadataColor = Color(0xBFC6C6C6);
    final hasReplyPreview = replyPreview?.trim().isNotEmpty == true;
    final secondaryLabel = isMine ? 'View profile' : 'Add contact';
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final preferredContentWidth =
        (viewportWidth * 0.65).clamp(210.0, 250.0).toDouble();

    return SizedBox(
      key: const ValueKey<String>('contact-bubble-content'),
      width: preferredContentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isForwarded) ...[
            const _ForwardedLabel(),
            const SizedBox(height: 6),
          ],
          if (hasReplyPreview) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReplyTap,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(isMine ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: Colors.white.withOpacity(isMine ? 0.16 : 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color:
                            isMine
                                ? Colors.white.withOpacity(0.62)
                                : WrytteColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (replySender?.trim().isNotEmpty == true)
                            Text(
                              replySender!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color:
                                    isMine
                                        ? Colors.white.withOpacity(0.86)
                                        : const Color(0xFFB8DCFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Text(
                            replyPreview!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.68),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          Row(
            key: const ValueKey<String>('contact-header-row'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipOval(
                child: SizedBox.square(
                  key: const ValueKey<String>('contact-avatar'),
                  dimension: _sharedAttachmentCircleSize,
                  child:
                      cleanAvatarUrl.isNotEmpty
                          ? UserAvatar(
                            size: _sharedAttachmentCircleSize,
                            imageUrl: cleanAvatarUrl,
                            name: cleanName,
                            cacheIdentity: userId?.trim().isNotEmpty == true
                                ? 'contact:${userId!.trim().toLowerCase()}'
                                : 'contact:${cleanName.toLowerCase()}:$cleanPhone',
                          )
                          : UserAvatar(
                            size: _sharedAttachmentCircleSize,
                            name: cleanName,
                            cacheIdentity: userId?.trim().isNotEmpty == true
                                ? 'contact:${userId!.trim().toLowerCase()}'
                                : 'contact:${cleanName.toLowerCase()}:$cleanPhone',
                          ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cleanName,
                      key: const ValueKey<String>('contact-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Align(
                      key: const ValueKey<String>('contact-metadata-row'),
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          subtitle,
                          key: const ValueKey<String>('contact-phone'),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            color: metadataColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Align(
                      key: const ValueKey<String>('contact-time-row'),
                      alignment: AlignmentDirectional.centerEnd,
                      child: SizedBox(
                        height: 14,
                        child: Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: timeWidget,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: dividerColor),
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        onMessage == null
                            ? null
                            : () => unawaited(onMessage!.call()),
                    style: TextButton.styleFrom(
                      foregroundColor: actionColor,
                      disabledForegroundColor: Colors.white.withOpacity(0.32),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Message',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed:
                        onAddContact == null
                            ? null
                            : () => unawaited(onAddContact!.call()),
                    style: TextButton.styleFrom(
                      foregroundColor: actionColor,
                      disabledForegroundColor: Colors.white.withOpacity(0.32),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        secondaryLabel,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleWidthBudget {
  final double maxBodyWidth;
  final double tailExtent;
  final double surfaceEdgeInset;

  const _BubbleWidthBudget({
    required this.maxBodyWidth,
    required this.tailExtent,
    required this.surfaceEdgeInset,
  });

  double get maxSurfaceWidth => maxBodyWidth + tailExtent;

  factory _BubbleWidthBudget.resolve({
    required double viewportWidth,
    required double? requestedMaxBodyWidth,
    required double screenEdgeMargin,
    required bool showTail,
  }) {
    final safeViewportWidth =
        viewportWidth.clamp(0.0, double.infinity).toDouble();
    final availableBodyWidth =
        (safeViewportWidth - (screenEdgeMargin * 2))
            .clamp(0.0, double.infinity)
            .toDouble();
    final responsiveBodyWidth = safeViewportWidth * 0.80;
    final allowedBodyWidth = availableBodyWidth.clamp(0.0, 420.0).toDouble();
    final maxBodyWidth =
        (requestedMaxBodyWidth ?? responsiveBodyWidth)
            .clamp(0.0, allowedBodyWidth)
            .toDouble();
    final tailExtent = showTail ? _MessageBubbleSurface.tailExtent : 0.0;

    return _BubbleWidthBudget(
      maxBodyWidth: maxBodyWidth,
      tailExtent: tailExtent,
      // The rounded body keeps the normal screen inset; only the tail extends
      // into the edge gutter.
      surfaceEdgeInset: screenEdgeMargin - tailExtent,
    );
  }
}

class _IncomingBubbleSurface extends StatelessWidget {
  final BorderRadius borderRadius;
  final bool showTail;
  final bool useRRectTail;
  final EdgeInsets padding;
  final Widget child;

  const _IncomingBubbleSurface({
    required this.borderRadius,
    required this.showTail,
    this.useRRectTail = false,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _MessageBubbleSurface(
      isMine: false,
      showTail: showTail,
      useRRectTail: useRRectTail,
      borderRadius: borderRadius,
      padding: padding,
      gradient: const LinearGradient(
        colors: [WrytteColors.surfaceRaised, WrytteColors.surfaceRaised],
      ),
      child: child,
    );
  }
}

class _MessageBubbleSurface extends StatelessWidget {
  // Preserve Wrytte's original 8px layout reserve. Bubble widths, padding and
  // per-message corner-radius rules stay untouched; the tail geometry itself
  // is generated as part of the same path as the body.
  static const double tailExtent = 8.0;

  final bool isMine;
  final bool showTail;
  final bool useRRectTail;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final Gradient gradient;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry? margin;
  final Widget child;

  const _MessageBubbleSurface({
    required this.isMine,
    required this.showTail,
    this.useRRectTail = false,
    required this.borderRadius,
    required this.padding,
    required this.gradient,
    required this.child,
    this.borderColor,
    this.borderWidth = 0,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceExtension =
        showTail
            ? EdgeInsets.only(
              left: isMine ? 0 : tailExtent,
              right: isMine ? tailExtent : 0,
            )
            : EdgeInsets.zero;
    final body = Padding(
      key: const ValueKey('message-bubble-body'),
      padding: padding,
      child: child,
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: CustomPaint(
        key: const ValueKey('message-bubble-surface'),
        painter: _MessageBubbleShapePainter(
          isMine: isMine,
          showTail: showTail,
          useRRectTail: useRRectTail,
          borderRadius: borderRadius,
          gradient: gradient,
          borderColor: borderColor,
          borderWidth: borderWidth,
        ),
        // The tail extends the painted surface. It never reduces the width
        // offered to the padded bubble body.
        child: Padding(padding: surfaceExtension, child: body),
      ),
    );
  }
}

class _MessageBubbleShapePainter extends CustomPainter {
  final bool isMine;
  final bool showTail;
  final bool useRRectTail;
  final BorderRadius borderRadius;
  final Gradient gradient;
  final Color? borderColor;
  final double borderWidth;

  const _MessageBubbleShapePainter({
    required this.isMine,
    required this.showTail,
    this.useRRectTail = false,
    required this.borderRadius,
    required this.gradient,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final path = _MessageBubblePath.create(
      size: size,
      isMine: isMine,
      showTail: showTail,
      useRRectTail: useRRectTail,
      borderRadius: borderRadius,
      strokeInset: borderWidth / 2,
    );
    final bounds = Offset.zero & size;
    final fillPaint =
        Paint()
          ..isAntiAlias = true
          ..shader = gradient.createShader(bounds);
    canvas.drawPath(path, fillPaint);

    if (borderColor != null && borderWidth > 0) {
      final borderPaint =
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth
            ..color = borderColor!;
      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MessageBubbleShapePainter oldDelegate) {
    return oldDelegate.isMine != isMine ||
        oldDelegate.showTail != showTail ||
        oldDelegate.useRRectTail != useRRectTail ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.gradient != gradient ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}

class _MessageBubbleShapeClipper extends CustomClipper<Path> {
  final bool isMine;
  final bool showTail;
  final BorderRadius borderRadius;

  const _MessageBubbleShapeClipper({
    required this.isMine,
    required this.showTail,
    required this.borderRadius,
  });

  @override
  Path getClip(Size size) {
    return _MessageBubblePath.create(
      size: size,
      isMine: isMine,
      showTail: showTail,
      useRRectTail: false,
      borderRadius: borderRadius,
      strokeInset: 0,
    );
  }

  @override
  bool shouldReclip(covariant _MessageBubbleShapeClipper oldClipper) {
    return oldClipper.isMine != isMine ||
        oldClipper.showTail != showTail ||
        oldClipper.borderRadius != borderRadius;
  }
}

class _MessageBubbleBorderPainter extends CustomPainter {
  final bool isMine;
  final bool showTail;
  final BorderRadius borderRadius;
  final Color color;
  final double strokeWidth;

  const _MessageBubbleBorderPainter({
    required this.isMine,
    required this.showTail,
    required this.borderRadius,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || strokeWidth <= 0) return;
    final path = _MessageBubblePath.create(
      size: size,
      isMine: isMine,
      showTail: showTail,
      useRRectTail: false,
      borderRadius: borderRadius,
      strokeInset: strokeWidth / 2,
    );
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MessageBubbleBorderPainter oldDelegate) {
    return oldDelegate.isMine != isMine ||
        oldDelegate.showTail != showTail ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _MessageBubblePath {
  // Telegram iOS builds the tail into the bubble mask itself. The rounded body
  // is kept exactly as supplied by Wrytte, then a fixed lower lobe is added and
  // an overlapping oval is removed to carve the smooth inward swoosh.
  //
  // The 33pt construction is the starting geometry. The horizontal lobe and
  // clear-ellipse values below are lightly tuned to the supplied reference so
  // the scoop is wider/shallower and the tip finishes with the same soft taper.
  // Only the tail area uses them; the caller's bubble radius is never replaced.
  static const double _templateDiameter = 33.0;
  static const double _bottomEllipseLeftInset = 10.5;
  static const double _bottomEllipseWidth = 30.0;
  static const double _bottomEllipseHeight = 17.0;
  static const double _innerEllipseWidth = 22.0;
  static const double _innerEllipseHeight = 20.0;
  static const double _bridgeWidth = 18.0;
  static const double _bridgeTopInset = 17.0;
  static const double _bridgeBottomInset = 8.0;

  // Every bubble that actually shows a tail uses the same rounding on the
  // upper corner of the tail side. This is applied centrally in the shared
  // bubble path, so text, voice, file, contact and media tails cannot drift
  // apart. No-tail bubbles keep their original per-type corner radii.
  static const Radius _tailSideTopRadius = Radius.circular(18);

  static Path create({
    required Size size,
    required bool isMine,
    required bool showTail,
    required bool useRRectTail,
    required BorderRadius borderRadius,
    required double strokeInset,
  }) {
    if (size.isEmpty) return Path();

    // No tail means no tail logic at all: return the caller's exact rounded
    // bubble. This preserves every existing Wrytte no-tail style.
    if (!showTail) {
      final rect = Rect.fromLTRB(
        strokeInset,
        strokeInset,
        size.width - strokeInset,
        size.height - strokeInset,
      );
      if (rect.width <= 0 || rect.height <= 0) return Path();
      return _roundedBody(rect, borderRadius);
    }

    // A visible tail has one shared top-side radius, regardless of message type.
    // Outgoing/right-tail bubbles normalize only topRight. Incoming/left-tail
    // bubbles normalize only topLeft. Every other corner remains owned by the
    // caller, so this cannot turn square-ish large bubbles into capsules.
    final tailNormalizedRadius =
        isMine
            ? BorderRadius.only(
              topLeft: borderRadius.topLeft,
              topRight: _tailSideTopRadius,
              bottomLeft: borderRadius.bottomLeft,
              bottomRight: borderRadius.bottomRight,
            )
            : BorderRadius.only(
              topLeft: _tailSideTopRadius,
              topRight: borderRadius.topRight,
              bottomLeft: borderRadius.bottomLeft,
              bottomRight: borderRadius.bottomRight,
            );

    // Build one canonical outgoing/right-tail bubble. Incoming messages mirror
    // that finished shape, so both directions get precisely the same tail.
    // Swap radii before mirroring so each message keeps its original left/right
    // corner styling.
    final rightTailRadius =
        isMine
            ? tailNormalizedRadius
            : BorderRadius.only(
              topLeft: tailNormalizedRadius.topRight,
              topRight: tailNormalizedRadius.topLeft,
              bottomLeft: tailNormalizedRadius.bottomRight,
              bottomRight: tailNormalizedRadius.bottomLeft,
            );

    final outgoingPath = _createRightTailBubble(
      size: size,
      borderRadius: rightTailRadius,
      strokeInset: strokeInset,
    );
    if (isMine) return outgoingPath;

    final horizontalMirror = Float64List.fromList(<double>[
      -1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      size.width,
      0,
      0,
      1,
    ]);
    return outgoingPath.transform(horizontalMirror);
  }

  static Path _createRightTailBubble({
    required Size size,
    required BorderRadius borderRadius,
    required double strokeInset,
  }) {
    final availableWidth =
        math.max(0.0, size.width - strokeInset * 2.0).toDouble();
    final availableHeight =
        math.max(0.0, size.height - strokeInset * 2.0).toDouble();
    if (availableWidth <= 0 || availableHeight <= 0) return Path();

    // Keep the full Telegram corner geometry on normal bubbles, but scale only
    // the tail on unusually short messages. The bubble body's own radii are
    // never scaled by this value.
    final tailScale =
        math.min(1.0, availableHeight / _templateDiameter).toDouble();

    // Preserve Wrytte's existing 8px width budget. The Telegram-style visible
    // tip naturally occupies only part of that reserve after the inner oval is
    // cut out, which keeps the body edge and existing screen spacing stable.
    final reservedTail =
        math
            .min(
              _MessageBubbleSurface.tailExtent,
              math.max(0.0, availableWidth - 1.0),
            )
            .toDouble();

    final bodyRect = Rect.fromLTRB(
      strokeInset,
      strokeInset,
      size.width - strokeInset - reservedTail,
      size.height - strokeInset,
    );
    if (bodyRect.width <= 0 || bodyRect.height <= 0) return Path();

    // This is the important separation: Wrytte still owns the bubble body.
    // Text/voice/file/contact/media keep their own radii. Some of Wrytte's
    // capsule bubbles intentionally pass Radius.zero on the tail corner because
    // the old procedural tail used to own that corner. Telegram's unified tail
    // needs a rounded base corner to form the swoosh, so only for that zero tail
    // corner we borrow the existing top-right radius. No other corner changes.
    final effectiveBottomRight =
        borderRadius.bottomRight == Radius.zero
            ? borderRadius.topRight
            : borderRadius.bottomRight;
    final tailAwareBorderRadius = BorderRadius.only(
      topLeft: borderRadius.topLeft,
      topRight: borderRadius.topRight,
      bottomLeft: borderRadius.bottomLeft,
      bottomRight: effectiveBottomRight,
    );
    final bodyPath = _roundedBody(bodyRect, tailAwareBorderRadius);
    final bodyRight = bodyRect.right;
    final bottom = bodyRect.bottom;

    // Lower tail lobe. It keeps the same 17pt vertical construction, but is
    // slightly wider and begins a little earlier so the reference's sweep does
    // not collapse into a narrow triangular-looking tip.
    final bottomEllipse = Rect.fromLTWH(
      bodyRight - (_bottomEllipseLeftInset * tailScale),
      bottom - (_bottomEllipseHeight * tailScale),
      _bottomEllipseWidth * tailScale,
      _bottomEllipseHeight * tailScale,
    );

    final lowerLobe =
        Path()
          ..moveTo(bottomEllipse.left, bottomEllipse.center.dy)
          ..quadraticBezierTo(
            bottomEllipse.left,
            bottomEllipse.bottom,
            bottomEllipse.center.dx,
            bottomEllipse.bottom,
          )
          ..quadraticBezierTo(
            bottomEllipse.right,
            bottomEllipse.bottom,
            bottomEllipse.right,
            bottomEllipse.center.dy,
          )
          ..close();

    // The bridge is part of the same mask. It guarantees that the lobe grows
    // out of the existing bubble instead of behaving like an attached sticker.
    final bridge =
        Path()..addRect(
          Rect.fromLTRB(
            bodyRight - (_bridgeWidth * tailScale),
            bottom - (_bridgeTopInset * tailScale),
            bodyRight,
            bottom - (_bridgeBottomInset * tailScale),
          ),
        );

    var combined = Path.combine(PathOperation.union, bodyPath, lowerLobe);
    combined = Path.combine(PathOperation.union, combined, bridge);

    // Reference-tuned clear ellipse. Start the cutout exactly at bodyRight.
    // This removes the tiny exposed upper spur at the body/tail join while
    // preserving the bubble body, the lower sweep, and the 8px tail reserve.
    final innerCutout =
        Path()..addOval(
          Rect.fromLTWH(
            bodyRight,
            bottom - (19.0 * tailScale),
            _innerEllipseWidth * tailScale,
            _innerEllipseHeight * tailScale,
          ),
        );

    return Path.combine(PathOperation.difference, combined, innerCutout);
  }

  static Path _roundedBody(Rect rect, BorderRadius borderRadius) {
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: _fitRadius(borderRadius.topLeft, rect),
        topRight: _fitRadius(borderRadius.topRight, rect),
        bottomLeft: _fitRadius(borderRadius.bottomLeft, rect),
        bottomRight: _fitRadius(borderRadius.bottomRight, rect),
      ),
    );
  }

  static Radius _fitRadius(Radius radius, Rect rect) {
    final maxX = math.max(0.0, rect.width / 2.0);
    final maxY = math.max(0.0, rect.height / 2.0);
    return Radius.elliptical(
      math.min(radius.x, maxX).toDouble(),
      math.min(radius.y, maxY).toDouble(),
    );
  }
}
