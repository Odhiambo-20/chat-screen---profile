import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wrytte/models/chat_models/chat_message.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/ui/widgets/chats/messages/message_bubble.dart';
import 'package:wrytte/ui/widgets/chats/overlays/message_actions_overlay.dart';

class PinnedMessagesPage extends StatefulWidget {
  final List<ChatMessage> messages;
  final int pinnedCount;
  final String currentUserId;
  final ValueChanged<String> onOpenMessage;
  final FutureOr<void> Function(ChatMessage) onCopy;
  final Future<bool> Function(ChatMessage) onUnpin;
  final FutureOr<void> Function(ChatMessage) onForward;
  final List<MessageActionItem> Function(ChatMessage) deleteActionsFor;
  final FutureOr<void> Function(ChatMessage, String) onReaction;
  final FutureOr<void> Function() onUnpinAll;

  const PinnedMessagesPage({
    super.key,
    required this.messages,
    required this.pinnedCount,
    required this.currentUserId,
    required this.onOpenMessage,
    required this.onCopy,
    required this.onUnpin,
    required this.onForward,
    required this.deleteActionsFor,
    required this.onReaction,
    required this.onUnpinAll,
  });

  @override
  State<PinnedMessagesPage> createState() => _PinnedMessagesPageState();
}

class _PinnedMessagesPageState extends State<PinnedMessagesPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, GlobalKey> _bubbleBoundaryKeys = {};
  final Set<String> _removedMessageIds = {};
  bool _searching = false;
  bool _unpinning = false;
  bool _messageActionsActive = false;
  String? _contextMenuMessageId;

  List<ChatMessage> get _visibleMessages {
    final query = _searchController.text.trim().toLowerCase();
    final availableMessages = widget.messages.where(
      (message) => !_removedMessageIds.contains(message.id),
    );
    if (query.isEmpty) return availableMessages.toList(growable: false);
    return availableMessages
        .where((message) {
          final preview = _preview(message).toLowerCase();
          return preview.contains(query) ||
              message.senderId.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  String _preview(ChatMessage message) {
    final type = message.attachmentType?.trim().toLowerCase() ?? '';
    if (message.isVoiceNote || type == 'audio') return 'Voice message';
    if (type == 'image') return 'Photo';
    if (type == 'video') return 'Video';
    if (type.isNotEmpty) return 'File';
    final text = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.isEmpty ? 'Message' : text;
  }

  String _time(ChatMessage message) {
    final value = message.timestamp.toLocal();
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String _dateLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    if (difference > 1 && difference < 7) {
      return weekdays[value.weekday - 1];
    }

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  Widget _dateChip(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11.5),
      child: Center(
        child: SizedBox(
          height: 23,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.5),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: 23,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C222C).withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(11.5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.055),
                    width: 0.7,
                  ),
                ),
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1,
                  child: Text(
                    _dateLabel(date),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 10.75,
                      fontWeight: FontWeight.w600,
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

  bool _isMine(ChatMessage message) {
    final current = widget.currentUserId.trim();
    final sender = message.senderId.trim();
    if (sender == current) return true;
    if (sender.startsWith('@') && sender.contains(':')) {
      return sender.substring(1, sender.indexOf(':')) == current;
    }
    return false;
  }

  String? _effectiveAttachmentType(ChatMessage message) {
    final explicit = message.attachmentType?.trim().toLowerCase();
    if (explicit?.isNotEmpty == true) return explicit;

    final value = [
      message.attachmentUrl,
      message.content,
    ].whereType<String>().join(' ').toLowerCase();
    if (value.isEmpty) return null;
    if (RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|heic|heif)(?:$|[?#\s])',
    ).hasMatch(value)) {
      return 'image';
    }
    if (RegExp(r'\.(mp4|mov|m4v|webm|mkv|3gp)(?:$|[?#\s])').hasMatch(value)) {
      return 'video';
    }
    if (RegExp(
      r'\.(pdf|docx?|pptx?|xlsx?|txt|csv|zip|rar|7z|apk)(?:$|[?#\s])',
    ).hasMatch(value)) {
      return 'file';
    }
    return null;
  }

  Widget _messageBubble(ChatMessage message) {
    final isMine = _isMine(message);
    final attachmentType = _effectiveAttachmentType(message);
    return GestureDetector(
      key: ValueKey<String>('pinned-message-row:${message.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMessage(message),
      onLongPressStart: (_) => unawaited(_showMessageActions(message)),
      onSecondaryTapDown: (_) =>
          unawaited(_showMessageActions(message, longPressFeedback: false)),
      child: MessageBubble(
        content: message.content,
        time: _time(message),
        isMine: isMine,
        senderName: isMine ? null : message.senderName,
        showTail: true,
        status: isMine ? message.status : null,
        isVoiceNote: message.isVoiceNote,
        isVideoNote: attachmentType == 'video',
        voiceDuration: message.voiceDuration,
        audioUrl: message.attachmentUrl,
        isVoiceOpened: isMine,
        isVoiceListened: message.isVoiceListened,
        attachmentType: attachmentType,
        attachmentUrl: message.attachmentUrl,
        attachmentFileName: message.attachmentFileName,
        attachmentSize: message.attachmentSize,
        audioTitle: message.audioTitle,
        audioArtist: message.audioArtist,
        audioArtworkUrl: message.audioArtworkUrl,
        mediaWidth: message.mediaWidth,
        mediaHeight: message.mediaHeight,
        isForwarded: message.isForwarded,
        isStarred: message.isStarred,
        isDeleted: message.isDeleted,
        isEdited: message.isEdited,
        isPinned: true,
        replyPreview: message.replyPreview,
        replySender: message.replyToSenderId,
        animateOnMount: false,
        contextMenuBoundaryKey: _bubbleBoundaryKey(message.id),
        hideForContextMenu: _contextMenuMessageId == message.id,
      ),
    );
  }

  GlobalKey _bubbleBoundaryKey(String messageId) {
    return _bubbleBoundaryKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'pinned-message-bubble:$messageId'),
    );
  }

  void _removeMessageLocally(ChatMessage message) {
    if (!mounted) return;
    setState(() => _removedMessageIds.add(message.id));
  }

  List<MessageActionItem> _deleteActions(ChatMessage message) {
    return widget
        .deleteActionsFor(message)
        .map((action) {
          return MessageActionItem(
            icon: action.icon,
            svgAsset: action.svgAsset,
            iconScale: action.iconScale,
            mirrorSvgHorizontally: action.mirrorSvgHorizontally,
            label: action.label,
            destructive: action.destructive,
            submenu: action.submenu,
            onSelected: () async {
              await action.onSelected();
              if (action.label != 'Cancel') _removeMessageLocally(message);
            },
          );
        })
        .toList(growable: false);
  }

  List<MessageActionItem> _messageActions(ChatMessage message) {
    return [
      MessageActionItem(
        svgAsset: 'assets/svg/Copy icon.svg',
        iconScale: 1.03,
        label: 'Copy',
        onSelected: () => widget.onCopy(message),
      ),
      MessageActionItem(
        svgAsset: 'assets/svg/Unpin icon .svg',
        iconScale: 1.12,
        label: 'Unpin',
        onSelected: () async {
          final removed = await widget.onUnpin(message);
          if (removed) _removeMessageLocally(message);
        },
      ),
      MessageActionItem(
        svgAsset: 'assets/svg/Forward Icon.svg',
        iconScale: 1.18,
        label: 'Forward',
        onSelected: () => widget.onForward(message),
      ),
      MessageActionItem(
        svgAsset: 'assets/svg/Delete icon.svg',
        iconScale: 1.16,
        label: 'Delete',
        destructive: true,
        onSelected: () {},
        submenu: _deleteActions(message),
      ),
    ];
  }

  Future<void> _showMessageActions(
    ChatMessage message, {
    bool longPressFeedback = true,
  }) async {
    if (_messageActionsActive || !mounted) return;
    _messageActionsActive = true;
    if (longPressFeedback) {
      unawaited(Feedback.forLongPress(context));
    }

    try {
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus?.hasFocus == true) {
        primaryFocus!.unfocus();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }

      final boundaryKey = _bubbleBoundaryKey(message.id);
      var boundary = boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderBox || !boundary.attached || !boundary.hasSize) {
        await WidgetsBinding.instance.endOfFrame;
        boundary = boundaryKey.currentContext?.findRenderObject();
      }
      if (boundary is! RenderBox || !boundary.attached || !boundary.hasSize) {
        return;
      }

      final bubbleRect = boundary.localToGlobal(Offset.zero) & boundary.size;
      if (bubbleRect.isEmpty) return;
      if (!mounted) return;
      final bubbleAnchor = boundaryKey.currentState;
      if (bubbleAnchor is! MessageActionsAnchorState) return;

      final result = await showTelegramMessageActionsOverlay(
        context: context,
        bubbleAnchor: bubbleAnchor,
        isMine: _isMine(message),
        actions: _messageActions(message),
      );

      final action = result?.action;
      if (action != null) {
        await action.onSelected();
      } else {
        final reaction = result?.reaction;
        if (reaction == null) return;
        await widget.onReaction(message, reaction);
      }
    } finally {
      _messageActionsActive = false;
    }
  }

  Widget _glassSurface({required double radius, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: 10,
          sigmaY: 10,
          tileMode: TileMode.clamp,
        ),
        blendMode: BlendMode.srcOver,
        child: DecoratedBox(
          decoration: wrytteGlassDecoration(radius: radius),
          child: child,
        ),
      ),
    );
  }

  Widget _headerControl({
    required String semanticsLabel,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: SizedBox.square(
        dimension: 42,
        child: _glassSurface(
          radius: 21,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(21),
              onTap: onTap,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSearch() {
    if (!_searching) {
      setState(() => _searching = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
      return;
    }
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      setState(() {});
      return;
    }
    _searchFocusNode.unfocus();
    setState(() => _searching = false);
  }

  void _openMessage(ChatMessage message) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onOpenMessage(message.id);
    });
  }

  Future<void> _unpinAll() async {
    if (_unpinning) return;
    setState(() => _unpinning = true);
    try {
      await widget.onUnpinAll();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _unpinning = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages;
    final visiblePinnedCount = (widget.pinnedCount - _removedMessageIds.length)
        .clamp(0, widget.pinnedCount)
        .toInt();
    final countLabel =
        '$visiblePinnedCount pinned ${visiblePinnedCount == 1 ? 'message' : 'messages'}';
    final media = MediaQuery.of(context);
    final headerExtent = media.viewPadding.top + 62;
    final bottomSafeInset = media.viewPadding.bottom;

    return Scaffold(
      backgroundColor: WrytteColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (messages.isEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: headerExtent,
                bottom: 76 + bottomSafeInset,
              ),
              child: Center(
                child: Text(
                  _searching
                      ? 'No pinned messages found'
                      : 'Pinned messages are unavailable',
                  style: const TextStyle(
                    color: Color(0xFF777A82),
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              padding: EdgeInsets.fromLTRB(
                12,
                headerExtent + 18,
                12,
                92 + bottomSafeInset,
              ),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: messages.length,
              separatorBuilder: (_, index) {
                final changesDirection =
                    _isMine(messages[index]) != _isMine(messages[index + 1]);
                return SizedBox(height: changesDirection ? 10 : 4);
              },
              itemBuilder: (context, index) {
                final message = messages[index];
                final showDate =
                    index == 0 ||
                    !_isSameDay(
                      messages[index - 1].timestamp,
                      message.timestamp,
                    );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showDate) _dateChip(message.timestamp),
                    _messageBubble(message),
                  ],
                );
              },
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerExtent + 18,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xF2050608),
                        Color(0xD9050608),
                        Color(0x00050608),
                      ],
                      stops: [0, .72, 1],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      media.viewPadding.top + 10,
                      10,
                      18,
                    ),
                    child: Row(
                      children: [
                        _headerControl(
                          semanticsLabel: 'Close pinned messages',
                          onTap: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 25,
                            color: WrytteColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: _glassSurface(
                              radius: 21,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _searching
                                    ? Padding(
                                        key: const ValueKey('pin-search'),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Center(
                                          child: TextField(
                                            controller: _searchController,
                                            focusNode: _searchFocusNode,
                                            onChanged: (_) => setState(() {}),
                                            maxLines: 1,
                                            style: const TextStyle(
                                              color: WrytteColors.textPrimary,
                                              fontSize: 14,
                                            ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              border: InputBorder.none,
                                              hintText:
                                                  'Search pinned messages',
                                              hintStyle: TextStyle(
                                                color: Color(0xFF777A82),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Column(
                                        key: const ValueKey('pin-title'),
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Pin',
                                            style: TextStyle(
                                              color: WrytteColors.textPrimary,
                                              fontSize: 17,
                                              height: 1,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            countLabel,
                                            style: const TextStyle(
                                              color: Color(0xFF777A82),
                                              fontSize: 12,
                                              height: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _headerControl(
                          semanticsLabel: 'Search pinned messages',
                          onTap: _toggleSearch,
                          icon: wrytteSvgAssetIcon(
                            assetPath: 'assets/svg/Search icon.svg',
                            canvas: 27,
                            scale: 0.90,
                            color: WrytteColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              maintainBottomViewPadding: true,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: _glassSurface(
                  radius: 22,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _unpinning || messages.isEmpty ? null : _unpinAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: _unpinning
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: WrytteColors.textPrimary,
                                ),
                              )
                            : const Text(
                                'Unpin all messages',
                                style: TextStyle(
                                  color: WrytteColors.textPrimary,
                                  fontSize: 17,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
