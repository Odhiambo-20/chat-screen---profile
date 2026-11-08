part of '../../../screens/chats/chat_screen.dart';

extension _ChatMessagePresenter on _ChatScreenState {
  bool _isMine(ChatMessage message) {
    final current = widget.currentUserId.trim();
    final sender = message.senderId.trim();
    if (sender == current) return true;
    if (sender.startsWith('@') && sender.contains(':')) {
      return sender.substring(1, sender.indexOf(':')) == current;
    }
    return false;
  }

  bool _sameBubbleAuthor(ChatMessage a, ChatMessage b) {
    final aMine = _isMine(a);
    final bMine = _isMine(b);
    if (aMine != bMine) return false;
    if (aMine && bMine) return true;
    final aSender = _matrixLocalpart(a.senderId);
    final bSender = _matrixLocalpart(b.senderId);
    return aSender.isNotEmpty && aSender == bSender;
  }

  String? _replySenderDisplayName(ChatMessage message) {
    final rawSender =
        message.replyToSenderId?.trim().isNotEmpty == true
            ? message.replyToSenderId!.trim()
            : _replySenderIdFromQuotedMessage(message);
    if (rawSender == null || rawSender.isEmpty) return null;

    if (_matrixLocalpart(rawSender) == _matrixLocalpart(widget.currentUserId)) {
      return 'You';
    }

    final receiverLocalpart = _matrixLocalpart(widget.receiverId);
    final senderLocalpart = _matrixLocalpart(rawSender);
    final isKnownPeer =
        senderLocalpart.isNotEmpty &&
        (senderLocalpart == receiverLocalpart ||
            senderLocalpart ==
                _matrixLocalpart(_receiverIdentity?.matrixUserId ?? ''));

    if (isKnownPeer) {
      final savedName = _cleanDisplayName(_receiverIdentity?.savedName);
      if (_receiverIsSavedContact && savedName.isNotEmpty) return savedName;

      final phone = _firstPhoneFrom([
        _receiverIdentity?.phone,
        _receiverProfile?.phone,
        widget.receiverId,
        widget.title,
        rawSender,
        ..._messagePeerIdentifiers(),
      ]);
      if (phone.isNotEmpty) return phone;

      final titleName = _cleanDisplayName(widget.title);
      if (titleName.isNotEmpty) return titleName;

      return null;
    }

    final phone = _firstPhoneFrom([rawSender]);
    if (phone.isNotEmpty) return phone;
    if (_looksLikeMatrixId(rawSender)) return null;

    final cleanName = _cleanDisplayName(rawSender);
    return cleanName.isNotEmpty ? cleanName : null;
  }

  String? _replySenderIdForOutgoingReply(ChatMessage? reply) {
    if (reply == null) return null;
    final sender = reply.senderId.trim();
    if (sender.isNotEmpty) return sender;
    return _isMine(reply) ? widget.currentUserId : widget.receiverId;
  }

  String? _replySenderIdFromQuotedMessage(ChatMessage message) {
    final replyToMessageId = message.replyToMessageId?.trim();
    if (replyToMessageId == null || replyToMessageId.isEmpty) return null;
    for (final candidate in _messages) {
      if (candidate.id != replyToMessageId) continue;
      final sender = candidate.senderId.trim();
      if (sender.isNotEmpty) return sender;
      return _isMine(candidate) ? widget.currentUserId : widget.receiverId;
    }
    return null;
  }

  String? _replyPreviewDisplayText(String? preview) {
    var text = preview?.trim() ?? '';
    if (text.isEmpty) return null;
    text = text.replaceFirst(RegExp(r'^<[^>]+>\s*'), '').trim();
    text =
        text.replaceFirst(RegExp(r'^@[A-Za-z0-9._=-]+:[^\s]+\s*'), '').trim();
    return text.isEmpty ? null : text;
  }

  String? _replyPreviewForMessage(ChatMessage message) {
    if (message.isDeleted) return 'This message was deleted';
    final attachmentType = message.attachmentType?.trim();
    if (attachmentType != null && attachmentType.isNotEmpty) {
      return _attachmentLabelForType(attachmentType);
    }
    final text = message.content.trim();
    if (text.isEmpty) return null;
    return text;
  }

  String _attachmentLabelForType(String type) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
      case 'video_message':
        return 'Video';
      case 'voice':
        return 'Voice';
      case 'file':
        return 'File';
      case 'contact':
        return 'Contact';
      default:
        return 'Attachment';
    }
  }

  bool _isValidMatrixUserId(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('@')) return false;
    if (trimmed.startsWith('@!')) return false;
    return trimmed.split(':').length == 2 && trimmed.split(':').last.isNotEmpty;
  }

  bool _isOwnMatrixId(String value) =>
      _matrixLocalpart(value) == _matrixLocalpart(widget.currentUserId);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateDivider(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    if (diff > 1 && diff < 7) return weekdays[dt.weekday - 1];

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
    final monthAndDay = '${months[dt.month - 1]} ${dt.day}';
    return dt.year == now.year ? monthAndDay : '$monthAndDay, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  String? _effectiveAttachmentType(ChatMessage message) {
    final explicit = message.attachmentType?.trim().toLowerCase();
    if (explicit?.isNotEmpty == true) return explicit;

    final value =
        [
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

  bool _isVideoAttachmentType(String? type) =>
      type == chatAttachmentTypeVideo || type == chatAttachmentTypeVideoMessage;

  bool _isRoundVideoMessageType(ChatMessage message, String? type) {
    final normalisedType = type?.trim().toLowerCase();
    if (normalisedType == chatAttachmentTypeVideoMessage) return true;
    return message.isVideoMessage;
  }

  Future<void> _repairMissingRoundVideoSource(ChatMessage message) async {
    if (!message.isVideoMessage) return;
    final source = message.attachmentUrl?.trim() ?? '';
    final sourceUri = Uri.tryParse(source);
    final localSource =
        sourceUri?.scheme == 'file' ? sourceUri!.toFilePath() : source;
    final sourceIsMissing =
        source.isEmpty ||
        (!source.startsWith('http') && !await File(localSource).exists());
    if (!sourceIsMissing) return;

    final eventId = message.id.trim();
    if (eventId.isEmpty ||
        !eventId.startsWith(r'$') ||
        !_roundVideoSourceRepairsInFlight.add(eventId)) {
      return;
    }

    try {
      final room = MatrixChatService.instance.getRoomById(
        message.conversationId,
      );
      final event = await room?.getEventById(eventId);
      final repaired =
          event == null ? null : ChatMessage.fromMatrixEvent(event);
      final repairedSource = repaired?.attachmentUrl?.trim() ?? '';
      if (!mounted || repaired == null || repairedSource.isEmpty) {
        return;
      }
      _setChatState(() {
        _upsertMessage(
          repaired.copyWith(
            content: chatVideoMessageContent,
            attachmentType: chatAttachmentTypeVideoMessage,
            voiceDuration: repaired.voiceDuration ?? message.voiceDuration,
          ),
        );
      });
      apkLog(
        'RoundVideo.repair',
        'restored media source event_id="$eventId" source="$repairedSource"',
      );
    } catch (error) {
      apkLog(
        'RoundVideo.repair',
        'failed event_id="$eventId" source="$source" error="$error"',
      );
    } finally {
      _roundVideoSourceRepairsInFlight.remove(eventId);
    }
  }
}
