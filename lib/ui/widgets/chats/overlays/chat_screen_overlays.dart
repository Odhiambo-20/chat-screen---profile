part of '../../../screens/chats/chat_screen.dart';

extension _ChatScreenOverlays on _ChatScreenState {
  Widget _buildFloatingDateOverlay(double top) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: ExcludeSemantics(
          child: ClipRect(
            key: const ValueKey('date-handoff-clip'),
            child: SizedBox(
              height: _dateHandoffClipHeight,
              child: ValueListenableBuilder<_FloatingDateVisualState>(
                valueListenable: _floatingDateVisual,
                builder: (context, visual, child) {
                  if (!visual.hasDate || _messages.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return FadeTransition(
                    opacity: _floatingDateOpacity,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Transform.translate(
                            offset: Offset(0, visual.outgoingOffsetY),
                            child: Center(
                              child: RepaintBoundary(
                                key: ValueKey(
                                  'date-floating-outgoing-'
                                  '${visual.outgoingDayKey}',
                                ),
                                child: _buildSharedDateChip(
                                  label: visual.outgoingLabel!,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (visual.hasIncoming)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Transform.translate(
                              offset: Offset(0, visual.incomingOffsetY),
                              child: Center(
                                child: RepaintBoundary(
                                  key: ValueKey(
                                    'date-floating-incoming-'
                                    '${visual.incomingDayKey}',
                                  ),
                                  child: _buildSharedDateChip(
                                    label: visual.incomingLabel!,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSharedDateChip({required String label}) {
    return SizedBox(
      height: _dateChipHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_dateChipRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: _dateChipHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: _dateChipHorizontalPadding,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1C222C).withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(_dateChipRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.055),
                width: 0.7,
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              widthFactor: 1,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 10.75,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugOverlay(double topOffset) {
    final lines = _logger.lines;

    return Positioned(
      top: topOffset + 4,
      left: 4,
      right: 4,
      bottom: 140,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orangeAccent, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── header ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: Colors.orangeAccent,
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'APK DEBUG LOG',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  // Copy all logs button
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: lines.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copied to clipboard'),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'COPY',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  // Clear button
                  GestureDetector(
                    onTap: () {
                      _logger.clear();
                      _setChatState(() {});
                    },
                    child: const Text(
                      'CLR',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Close button
                  GestureDetector(
                    onTap: () => _setChatState(() => _showDebug = false),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),

            // ── log lines ────────────────────────────────────────────────────
            Expanded(
              child:
                  lines.isEmpty
                      ? const Center(
                        child: Text(
                          'No logs yet.\nTry sending a message.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      )
                      : ListView.builder(
                        controller: _debugScrollCtrl,
                        padding: const EdgeInsets.all(6),
                        itemCount: lines.length,
                        itemBuilder: (_, i) {
                          final line = lines[i];
                          // Colour-code by severity
                          Color c = Colors.white70;
                          if (line.contains('❌') ||
                              line.contains('🚨') ||
                              line.contains('FAIL') ||
                              line.contains('ERROR') ||
                              line.contains('TIMEOUT')) {
                            c = const Color(0xFFFF6B6B);
                          } else if (line.contains('⚠️') ||
                              line.contains('WARN') ||
                              line.contains('MISMATCH')) {
                            c = const Color(0xFFFFD93D);
                          } else if (line.contains('✅')) {
                            c = const Color(0xFF6BCB77);
                          } else if (line.contains('🔄') ||
                              line.contains('⏳')) {
                            c = WrytteColors.primary;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: SelectableText(
                              line,
                              style: TextStyle(
                                color: c,
                                fontSize: 10,
                                fontFamily: 'monospace',
                                height: 1.35,
                              ),
                            ),
                          );
                        },
                      ),
            ),

            // ── summary bar ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A2E),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(11),
                ),
              ),
              child: Text(
                'convId: ${_resolvedConversationId ?? "not resolved"}  '
                '|  receiver: ${_normaliseId(widget.receiverId)}  '
                '|  msgs: ${_messages.length}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MESSAGE LIST ──────────────────────────────────────────────────────────
}
