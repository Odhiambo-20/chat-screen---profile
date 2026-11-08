part of 'message_bubble.dart';

class _BubbleContent extends StatelessWidget {
  final String content;
  final Widget timeWidget;
  final bool isForwarded;
  final bool isStarred;
  final bool isDeleted;
  final bool isEdited;
  final String? replyPreview;
  final String? replySender;
  final VoidCallback? onReplyTap;
  final bool isMine;
  final double trailingWidth;
  final double trailingHeight;

  const _BubbleContent({
    required this.content,
    required this.timeWidget,
    required this.isMine,
    required this.trailingWidth,
    required this.trailingHeight,
    this.isForwarded = false,
    this.isStarred = false,
    this.isDeleted = false,
    this.isEdited = false,
    this.replyPreview,
    this.replySender,
    this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final link = isDeleted ? null : firstLinkInText(content);
    final hasReplyPreview = replyPreview?.trim().isNotEmpty == true;
    final displayText =
        isDeleted
            ? 'This message was deleted'
            : _normalizeMessageForDisplay(linkDisplayText(content));
    final contentColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isForwarded)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shortcut_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(0.48),
                ),
                const SizedBox(width: 4),
                Text(
                  'Forwarded',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.48),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        if (hasReplyPreview)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onReplyTap,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(isMine ? 0.12 : 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(isMine ? 0.16 : 0.08),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors:
                            isMine
                                ? [
                                  Colors.white.withOpacity(0.78),
                                  Colors.white.withOpacity(0.38),
                                ]
                                : const [
                                  Color(0xFF82C4FF),
                                  WrytteColors.primary,
                                ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (replySender != null && replySender!.isNotEmpty)
                          Text(
                            replySender!,
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
                          replyPreview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.68),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (link != null) ...[
          WrytteLinkPreview(url: link, stableLayout: true),
          const SizedBox(height: 6),
        ],
        _LinkedMessageText(
          text: displayText,
          isDeleted: isDeleted,
          isStarred: isStarred,
          trailingWidget: timeWidget,
          trailingWidth: trailingWidth,
          trailingHeight: trailingHeight,
          expandToMaxWidth: hasReplyPreview,
        ),
      ],
    );

    if (!hasReplyPreview) return contentColumn;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth.clamp(0.0, double.infinity).toDouble()
                : MediaQuery.sizeOf(context).width * 0.80;
        return SizedBox(
          width: _replyContentWidth(
            context,
            availableWidth: availableWidth,
            displayText: displayText,
          ),
          child: contentColumn,
        );
      },
    );
  }

  double _replyContentWidth(
    BuildContext context, {
    required double availableWidth,
    required String displayText,
  }) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    double measure(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final previewWidth = measure(
      replyPreview!.replaceAll('\n', ' '),
      const TextStyle(fontSize: 12, height: 1.25),
    );
    final senderWidth =
        replySender?.trim().isNotEmpty == true
            ? measure(
              replySender!.trim(),
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            )
            : 0.0;
    final messageWidth = measure(
      displayText.replaceAll('\n', ' '),
      const TextStyle(fontSize: 17, height: 1.18),
    );
    final previewContentWidth = math.max(previewWidth, senderWidth) + 32;
    final messageContentWidth = messageWidth + trailingWidth + 12;
    final desiredWidth = math.max(previewContentWidth, messageContentWidth);
    final minimumWidth = math.min(190.0, availableWidth);
    return desiredWidth.clamp(minimumWidth, availableWidth).toDouble();
  }
}

class _LinkedMessageText extends StatefulWidget {
  final String text;
  final bool isDeleted;
  final bool isStarred;
  final Widget trailingWidget;
  final double trailingWidth;
  final double trailingHeight;
  final bool expandToMaxWidth;

  const _LinkedMessageText({
    required this.text,
    required this.isDeleted,
    required this.isStarred,
    required this.trailingWidget,
    required this.trailingWidth,
    required this.trailingHeight,
    this.expandToMaxWidth = false,
  });

  @override
  State<_LinkedMessageText> createState() => _LinkedMessageTextState();
}

class _TextLayoutMeasurement {
  final int lineCount;
  final double widestLineWidth;
  final double finalLineWidth;

  const _TextLayoutMeasurement({
    required this.lineCount,
    required this.widestLineWidth,
    required this.finalLineWidth,
  });

  factory _TextLayoutMeasurement.from(TextPainter painter) {
    final lines = painter.computeLineMetrics();
    var widestLineWidth = 0.0;
    for (final line in lines) {
      if (line.width > widestLineWidth) {
        widestLineWidth = line.width;
      }
    }
    return _TextLayoutMeasurement(
      lineCount: lines.length,
      widestLineWidth: widestLineWidth,
      finalLineWidth: lines.isEmpty ? 0 : lines.last.width,
    );
  }
}

class _ResolvedTextLayout {
  final double bodyWidth;
  final bool trailingIsInline;

  const _ResolvedTextLayout.inline(this.bodyWidth) : trailingIsInline = true;

  const _ResolvedTextLayout.fallback(this.bodyWidth) : trailingIsInline = false;
}

class _LinkedMessageTextState extends State<_LinkedMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  static const double _inlineGap = 12;
  static const Size _starPlaceholderSize = Size(19, 15);
  static const double _layoutTolerance = 0.01;

  static final RegExp _urlPattern = RegExp(
    r'((?:https?:\/\/|www\.)[^\s]+|(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:\/[^\s]*)?)',
  );

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final baseStyle = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        color: Colors.white.withOpacity(widget.isDeleted ? 0.65 : 1),
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.18,
        fontStyle: widget.isDeleted ? FontStyle.italic : FontStyle.normal,
      ),
    );

    final spans = <InlineSpan>[
      if (widget.isStarred)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.star_rounded,
              size: 15,
              color: Colors.white.withOpacity(0.72),
            ),
          ),
        ),
    ];

    if (widget.isDeleted) {
      spans.add(TextSpan(text: widget.text, style: baseStyle));
    } else {
      var cursor = 0;
      for (final match in _urlPattern.allMatches(widget.text)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
        }
        final raw = match.group(0) ?? '';
        final clean = _trimUrlPunctuation(raw);
        if (_looksLikeAttachmentFileName(clean)) {
          spans.add(TextSpan(text: raw));
          cursor = match.end;
          continue;
        }
        final trailing = raw.substring(clean.length);
        final recognizer =
            TapGestureRecognizer()..onTap = () => _openLink(clean);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: clean,
            style: baseStyle.copyWith(
              color: const Color(0xFFB9DDFF),
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFFB9DDFF),
            ),
            recognizer: recognizer,
          ),
        );
        if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
        cursor = match.end;
      }
      if (cursor < widget.text.length) {
        spans.add(TextSpan(text: widget.text.substring(cursor)));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final locale = Localizations.maybeLocaleOf(context);
        final maxBodyWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth.clamp(0.0, double.infinity).toDouble()
                : MediaQuery.sizeOf(context).width;
        final plainTextSpan = TextSpan(style: baseStyle, children: spans);
        final trailingReservationWidth = _inlineGap + widget.trailingWidth;
        final plainPainter = _createTextPainter(
          span: plainTextSpan,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        );
        plainPainter.setPlaceholderDimensions([
          if (widget.isStarred) _starPlaceholderDimensions,
        ]);

        final layout = _resolveTextLayout(
          plainPainter: plainPainter,
          maxBodyWidth: maxBodyWidth,
          trailingReservationWidth: trailingReservationWidth,
        );
        plainPainter.dispose();

        if (!layout.trailingIsInline) {
          return SizedBox(
            key: const ValueKey('message-time-fallback'),
            width: widget.expandToMaxWidth ? maxBodyWidth : layout.bodyWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  widget.expandToMaxWidth
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.end,
              children: [
                Text.rich(
                  plainTextSpan,
                  key: const ValueKey('message-body-text'),
                  textDirection: textDirection,
                  textScaler: textScaler,
                  locale: locale,
                  textWidthBasis: TextWidthBasis.longestLine,
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 3),
                if (widget.expandToMaxWidth)
                  Align(
                    alignment: Alignment.centerRight,
                    child: widget.trailingWidget,
                  )
                else
                  widget.trailingWidget,
              ],
            ),
          );
        }

        return SizedBox(
          width: widget.expandToMaxWidth ? maxBodyWidth : layout.bodyWidth,
          child: Stack(
            key: const ValueKey('message-time-inline'),
            clipBehavior: Clip.none,
            children: [
              Text.rich(
                plainTextSpan,
                key: const ValueKey('message-body-text'),
                textDirection: textDirection,
                textScaler: textScaler,
                locale: locale,
                textWidthBasis: TextWidthBasis.longestLine,
                textAlign: TextAlign.start,
              ),
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Transform.translate(
                  offset: const Offset(0, 2),
                  child: widget.trailingWidget,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PlaceholderDimensions get _starPlaceholderDimensions =>
      const PlaceholderDimensions(
        size: _starPlaceholderSize,
        alignment: PlaceholderAlignment.middle,
      );

  TextPainter _createTextPainter({
    required TextSpan span,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    return TextPainter(
      text: span,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      textWidthBasis: TextWidthBasis.longestLine,
    );
  }

  _TextLayoutMeasurement _measureText(TextPainter painter, double maxWidth) {
    painter.layout(maxWidth: maxWidth);
    return _TextLayoutMeasurement.from(painter);
  }

  bool _inlineFits(
    TextPainter painter, {
    required double width,
    required int plainLineCount,
    required double trailingReservationWidth,
  }) {
    final measurement = _measureText(painter, width);
    return measurement.lineCount == plainLineCount &&
        measurement.widestLineWidth <= width + _layoutTolerance &&
        measurement.finalLineWidth + trailingReservationWidth <=
            width + _layoutTolerance;
  }

  _ResolvedTextLayout _resolveTextLayout({
    required TextPainter plainPainter,
    required double maxBodyWidth,
    required double trailingReservationWidth,
  }) {
    final plain = _measureText(plainPainter, maxBodyWidth);
    final minimumFallbackWidth =
        plain.widestLineWidth > widget.trailingWidth
            ? plain.widestLineWidth
            : widget.trailingWidth;
    final fallbackWidth =
        minimumFallbackWidth.clamp(0.0, maxBodyWidth).toDouble();

    if (plain.lineCount == 0 ||
        !_inlineFits(
          plainPainter,
          width: maxBodyWidth,
          plainLineCount: plain.lineCount,
          trailingReservationWidth: trailingReservationWidth,
        )) {
      return _ResolvedTextLayout.fallback(fallbackWidth);
    }

    final finalLineWithTrailing =
        plain.finalLineWidth + trailingReservationWidth;
    final preferredInlineWidth =
        (plain.widestLineWidth > finalLineWithTrailing
                ? plain.widestLineWidth
                : finalLineWithTrailing)
            .clamp(0.0, maxBodyWidth)
            .toDouble();

    // Do not binary-search for the narrowest technically valid width. That can
    // redistribute words while preserving the line count, leaving a short
    // first line and unnaturally dense later lines. The naturally measured
    // longest line is Flutter's chat-bubble width basis; only expand to the
    // available maximum if adding metadata changes those line breaks.
    if (_inlineFits(
      plainPainter,
      width: preferredInlineWidth,
      plainLineCount: plain.lineCount,
      trailingReservationWidth: trailingReservationWidth,
    )) {
      return _ResolvedTextLayout.inline(preferredInlineWidth);
    }
    return _ResolvedTextLayout.inline(maxBodyWidth);
  }

  String _trimUrlPunctuation(String value) {
    return value.replaceFirst(RegExp(r'[),.;:!?]+$'), '');
  }

  bool _looksLikeAttachmentFileName(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return false;
    }
    return RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|heic|heif|mp4|mov|m4v|webm|mkv|3gp|pdf|docx?|pptx?|xlsx?|txt|csv|zip|rar|7z|apk)$',
    ).hasMatch(trimmed);
  }

  Future<void> _openLink(String value) async {
    final url =
        value.startsWith('http://') || value.startsWith('https://')
            ? value
            : 'https://$value';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
