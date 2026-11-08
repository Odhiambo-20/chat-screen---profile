import 'dart:convert';

import 'package:matrix/matrix.dart' as mx;

enum MessageStatus { sending, sent, delivered, read, failed }

const String chatAttachmentTypeVideo = 'video';
const String chatAttachmentTypeVideoMessage = 'video_message';
const String chatVideoMessageContent = 'Video message';
const String wrytteMessageTypeKey = 'wrytte.message_type';

bool _boolFromJson(Object? value) =>
    value == true || value == 1 || value?.toString() == '1';

bool isRoundVideoMessageMarker({
  String? attachmentType,
  String? content,
  String? attachmentFileName,
  String? wrytteMessageType,
  int? attachmentSize,
  int? mediaWidth,
  int? mediaHeight,
}) {
  final type = attachmentType?.trim().toLowerCase();
  final messageType = wrytteMessageType?.trim().toLowerCase();
  if (type == chatAttachmentTypeVideoMessage ||
      messageType == chatAttachmentTypeVideoMessage) {
    return true;
  }
  if (type != chatAttachmentTypeVideo) return false;
  if (content?.trim().toLowerCase() == chatVideoMessageContent.toLowerCase()) {
    return true;
  }

  // Legacy safety net: before round videos had a first-class Matrix marker,
  // the inline recorder could fall through the generic attachment path. Those
  // events came back as regular m.video with camera-package names such as
  // REC4411347978739011157.mp4. Keep this narrow so normal gallery videos and
  // sent-as-file videos stay rectangular.
  final name =
      (attachmentFileName?.trim().isNotEmpty == true
              ? attachmentFileName
              : content)
          ?.trim()
          .toLowerCase();
  final looksLikeCameraRecorderFile =
      name != null && RegExp(r'^rec\d+\.mp4$').hasMatch(name);
  if (!looksLikeCameraRecorderFile) return false;
  final smallEnough = attachmentSize == null || attachmentSize <= 1500 * 1024;
  final hasRecorderPreviewShape =
      (mediaWidth == 1280 && mediaHeight == 720) ||
      (mediaWidth == 720 && mediaHeight == 1280) ||
      mediaWidth == null ||
      mediaHeight == null;
  return smallEnough && hasRecorderPreviewShape;
}

String? normalizeChatAttachmentType(
  String? attachmentType, {
  String? content,
  String? attachmentFileName,
  String? wrytteMessageType,
  int? attachmentSize,
  int? mediaWidth,
  int? mediaHeight,
}) {
  if (isRoundVideoMessageMarker(
    attachmentType: attachmentType,
    content: content,
    attachmentFileName: attachmentFileName,
    wrytteMessageType: wrytteMessageType,
    attachmentSize: attachmentSize,
    mediaWidth: mediaWidth,
    mediaHeight: mediaHeight,
  )) {
    return chatAttachmentTypeVideoMessage;
  }
  final normalized = attachmentType?.trim().toLowerCase();
  return normalized?.isEmpty == true ? null : normalized;
}

MessageStatus _statusFromString(String? value) {
  switch (value) {
    case "sent":
      return MessageStatus.sent;
    case "delivered":
      return MessageStatus.delivered;
    case "read":
      return MessageStatus.read;
    case "failed":
      return MessageStatus.failed;
    case "sending":
    default:
      return MessageStatus.sending;
  }
}

String _statusToString(MessageStatus status) {
  return status.name;
}

class ChatMessage {
  final String id;
  final String conversationId;

  /// Sender userId
  final String senderId;

  /// Receiver Matrix userId or direct-chat peer id.
  final String receiverId;

  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final String? attachmentUrl;
  final String? attachmentFileName;

  // ── attachmentType values used in this app ─────────────────────────────────
  // 'voice'   → voice note
  // 'video'   → video clip
  // 'video_message' → Telegram-style circular video message
  // 'image'   → image
  // 'file'    → file
  // 'contact' → shared contact
  final String? attachmentType;

  final int? attachmentSize;
  final String? audioTitle;
  final String? audioArtist;
  final String? audioArtworkUrl;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? mediaGroupId;
  final int? mediaGroupIndex;
  final int? mediaGroupCount;

  // ── Contact fields (null for non-contact messages) ──────────────────────────
  final String? contactName;
  final String? contactPhone;
  final String? contactAvatarUrl;
  final String? contactUserId;

  // ── Voice-note duration in seconds (null for non-voice messages) ────────────
  // Populated from Matrix media metadata when receiving and recorder output
  // when sending.
  final int? voiceDuration;

  final int unreadCount;
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyPreview;
  final String? senderPhone;
  final String? senderName;
  final bool isForwarded;
  final bool isStarred;
  final bool isDeletedForMe;
  final bool isDeletedForEveryone;
  final bool isEdited;
  final bool isVoiceListened;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.sending,
    this.attachmentUrl,
    this.attachmentFileName,
    this.attachmentType,
    this.attachmentSize,
    this.audioTitle,
    this.audioArtist,
    this.audioArtworkUrl,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaGroupId,
    this.mediaGroupIndex,
    this.mediaGroupCount,
    this.contactName,
    this.contactPhone,
    this.contactAvatarUrl,
    this.contactUserId,
    this.voiceDuration, // ← NEW
    this.unreadCount = 0,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyPreview,
    this.senderPhone,
    this.senderName,
    this.isForwarded = false,
    this.isStarred = false,
    this.isDeletedForMe = false,
    this.isDeletedForEveryone = false,
    this.isEdited = false,
    this.isVoiceListened = false,
  });

  // FROM JSON (Backend / local DB)
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final content = json["content"]?.toString() ?? "";
    final attachmentSize = int.tryParse(
      json["attachmentSize"]?.toString() ?? '',
    );
    final mediaWidth = int.tryParse(json["mediaWidth"]?.toString() ?? '');
    final mediaHeight = int.tryParse(json["mediaHeight"]?.toString() ?? '');
    return ChatMessage(
      id: json["id"]?.toString() ?? "",
      conversationId: json["conversationId"]?.toString() ?? "",
      senderId: json["senderId"]?.toString() ?? "",
      receiverId: json["receiverId"]?.toString() ?? "",
      content: content,
      timestamp:
          json["timestamp"] != null
              ? DateTime.tryParse(json["timestamp"].toString()) ??
                  DateTime.now()
              : DateTime.now(),
      status: _statusFromString(json["status"]?.toString()),
      attachmentUrl: json["attachmentUrl"]?.toString(),
      attachmentFileName: json["attachmentFileName"]?.toString(),
      attachmentType: normalizeChatAttachmentType(
        json["attachmentType"]?.toString(),
        content: content,
        attachmentFileName: json["attachmentFileName"]?.toString(),
        attachmentSize: attachmentSize,
        mediaWidth: mediaWidth,
        mediaHeight: mediaHeight,
      ),
      attachmentSize: attachmentSize,
      audioTitle: json["audioTitle"]?.toString(),
      audioArtist: json["audioArtist"]?.toString(),
      audioArtworkUrl: json["audioArtworkUrl"]?.toString(),
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      mediaGroupId: json["mediaGroupId"]?.toString(),
      mediaGroupIndex: int.tryParse(json["mediaGroupIndex"]?.toString() ?? ''),
      mediaGroupCount: int.tryParse(json["mediaGroupCount"]?.toString() ?? ''),
      contactName: json["contactName"]?.toString(),
      contactPhone: json["contactPhone"]?.toString(),
      contactAvatarUrl: json["contactAvatarUrl"]?.toString(),
      contactUserId: json["contactUserId"]?.toString(),
      voiceDuration:
          json["voiceDuration"] !=
                  null // ← NEW
              ? int.tryParse(json["voiceDuration"].toString())
              : null,
      replyToMessageId: json["replyToMessageId"]?.toString(),
      replyToSenderId: json["replyToSenderId"]?.toString(),
      replyPreview: json["replyPreview"]?.toString(),
      senderPhone: json["senderPhone"]?.toString(),
      senderName: json["senderName"]?.toString(),
      isForwarded: _boolFromJson(json["isForwarded"]),
      isStarred: _boolFromJson(json["isStarred"]),
      isDeletedForMe: _boolFromJson(json["isDeletedForMe"]),
      isDeletedForEveryone: _boolFromJson(json["isDeletedForEveryone"]),
      isEdited: _boolFromJson(json["isEdited"]),
      isVoiceListened: _boolFromJson(json["isVoiceListened"]),
    );
  }

  factory ChatMessage.fromMatrix(mx.Event event) {
    final content = event.content;
    final msgType = content['msgtype']?.toString() ?? event.messageType;
    final wrytteMessageType = content[wrytteMessageTypeKey]?.toString();

    final attachmentType =
        wrytteMessageType == 'contact'
            ? 'contact'
            : isRoundVideoMessageMarker(wrytteMessageType: wrytteMessageType)
            ? chatAttachmentTypeVideoMessage
            : content['wrytte.sent_as_file'] == true
            ? 'file'
            : normalizeChatAttachmentType(
              _attachmentTypeFromMatrix(msgType),
              content: _matrixEventBody(event),
              wrytteMessageType: wrytteMessageType,
            );

    final info = content['info'];
    int? duration;
    int? mediaWidth;
    int? mediaHeight;
    int? attachmentSize;

    if (info is Map && info['duration'] != null) {
      duration = ((info['duration'] as num).toInt() / 1000).round();
    }

    duration ??= int.tryParse(
      content['wrytte.video_duration']?.toString() ??
          content['wrytte.audio_duration']?.toString() ??
          '',
    );

    if (info is Map) {
      attachmentSize = int.tryParse(info['size']?.toString() ?? '');
      mediaWidth = int.tryParse(info['w']?.toString() ?? '');
      mediaHeight = int.tryParse(info['h']?.toString() ?? '');
    }

    mediaWidth ??= int.tryParse(
      content['wrytte.media_width']?.toString() ?? '',
    );

    mediaHeight ??= int.tryParse(
      content['wrytte.media_height']?.toString() ?? '',
    );

    attachmentSize ??= int.tryParse(
      content['wrytte.file_size']?.toString() ?? '',
    );

    final effectiveAttachmentType = normalizeChatAttachmentType(
      attachmentType,
      content: _matrixEventBody(event),
      attachmentFileName: content['filename']?.toString(),
      wrytteMessageType: wrytteMessageType,
      attachmentSize: attachmentSize,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
    );

    final contactName = content['wrytte.contact_name']?.toString();
    final contactPhone = content['wrytte.contact_phone']?.toString();
    final contactAvatarUrl = content['wrytte.contact_avatar_url']?.toString();
    final contactUserId = content['wrytte.contact_user_id']?.toString();

    final matrixBody = _stripReplyFallback(_matrixEventBody(event));
    final contactFallbackParts = <String>[
      if (contactName?.trim().isNotEmpty == true) contactName!.trim(),
      if (contactPhone?.trim().isNotEmpty == true) contactPhone!.trim(),
    ];
    final contactFallback =
        matrixBody.trim().isNotEmpty
            ? matrixBody
            : contactFallbackParts.isNotEmpty
            ? contactFallbackParts.join('\n')
            : 'Contact';

    return ChatMessage(
      id: event.eventId,
      conversationId: event.room.id,
      senderId: event.senderId,
      receiverId: event.room.directChatMatrixID ?? '',
      content:
          event.redacted
              ? _redactedMessageText(event)
              : effectiveAttachmentType == 'voice'
              ? 'Voice message'
              : effectiveAttachmentType == chatAttachmentTypeVideoMessage
              ? chatVideoMessageContent
              : effectiveAttachmentType == 'contact'
              ? contactFallback
              : matrixBody,
      timestamp: event.originServerTs,
      status: _statusFromMatrix(event.status),
      attachmentUrl: _attachmentUrlFromMatrix(event),
      attachmentFileName: content['filename']?.toString(),
      attachmentType: effectiveAttachmentType,
      attachmentSize: attachmentSize,
      audioTitle: content['wrytte.audio_title']?.toString(),
      audioArtist: content['wrytte.audio_artist']?.toString(),
      audioArtworkUrl: _thumbnailUrlFromMatrix(event),
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      mediaGroupId: content['wrytte.media_group_id']?.toString(),
      mediaGroupIndex: int.tryParse(
        content['wrytte.media_group_index']?.toString() ?? '',
      ),
      mediaGroupCount: int.tryParse(
        content['wrytte.media_group_count']?.toString() ?? '',
      ),
      contactName: contactName,
      contactPhone: contactPhone,
      contactAvatarUrl: contactAvatarUrl,
      contactUserId: contactUserId,
      voiceDuration: duration,
      replyToMessageId: event.inReplyToEventId(),
      replyToSenderId: _replySenderFromFallback(event.body),
      replyPreview: _replyPreviewFromFallback(event.body),
      senderPhone: content['wrytte.sender_phone']?.toString(),
      senderName: content['wrytte.sender_name']?.toString(),
      // Matrix/custom event content can be decoded as a bool, a string, or a
      // numeric value depending on the source (live event, sync, or cache).
      // Keep forwarded messages marked in all of those cases.
      isForwarded: _boolFromJson(content['wrytte.forwarded']),
      isDeletedForEveryone: event.redacted,
      isEdited: _isMatrixEdit(event),
    );
  }

  static ChatMessage? fromMatrixEvent(mx.Event event) {
    if (event.type != mx.EventTypes.Message) return null;

    final isContact =
        event.content[wrytteMessageTypeKey]?.toString() == 'contact';

    if (!event.redacted &&
        _matrixEventBody(event).isEmpty &&
        !event.hasAttachment &&
        !isContact) {
      return null;
    }

    return ChatMessage.fromMatrix(event);
  }

  static String? matrixEditTargetId(mx.Event event) {
    final relatesTo = event.content['m.relates_to'];
    if (relatesTo is! Map || relatesTo['rel_type'] != 'm.replace') {
      return null;
    }
    return relatesTo['event_id']?.toString();
  }

  // TO JSON (HTTP / Local DB)
  Map<String, dynamic> toJson() {
    final serializedAttachmentType =
        isVideoMessage ? chatAttachmentTypeVideoMessage : attachmentType;
    final serializedContent =
        isVideoMessage ? chatVideoMessageContent : content;
    return {
      "id": id,
      "conversationId": conversationId,
      "senderId": senderId,
      "receiverId": receiverId,
      "content": serializedContent,
      "timestamp": timestamp.toUtc().toIso8601String(),
      "status": _statusToString(status),
      if (attachmentUrl != null) "attachmentUrl": attachmentUrl,
      if (attachmentFileName != null) "attachmentFileName": attachmentFileName,
      if (serializedAttachmentType != null)
        "attachmentType": serializedAttachmentType,
      if (attachmentSize != null) "attachmentSize": attachmentSize,
      if (audioTitle != null) "audioTitle": audioTitle,
      if (audioArtist != null) "audioArtist": audioArtist,
      if (audioArtworkUrl != null) "audioArtworkUrl": audioArtworkUrl,
      if (mediaWidth != null) "mediaWidth": mediaWidth,
      if (mediaHeight != null) "mediaHeight": mediaHeight,
      if (mediaGroupId != null) "mediaGroupId": mediaGroupId,
      if (mediaGroupIndex != null) "mediaGroupIndex": mediaGroupIndex,
      if (mediaGroupCount != null) "mediaGroupCount": mediaGroupCount,
      if (contactName != null) "contactName": contactName,
      if (contactPhone != null) "contactPhone": contactPhone,
      if (contactAvatarUrl != null) "contactAvatarUrl": contactAvatarUrl,
      if (contactUserId != null) "contactUserId": contactUserId,
      if (voiceDuration != null) "voiceDuration": voiceDuration, // ← NEW
      if (replyToMessageId != null) "replyToMessageId": replyToMessageId,
      if (replyToSenderId != null) "replyToSenderId": replyToSenderId,
      if (replyPreview != null) "replyPreview": replyPreview,
      if (senderPhone != null) "senderPhone": senderPhone,
      if (senderName != null) "senderName": senderName,
      "isForwarded": isForwarded,
      "isStarred": isStarred,
      "isDeletedForMe": isDeletedForMe,
      "isDeletedForEveryone": isDeletedForEveryone,
      "isEdited": isEdited,
      "isVoiceListened": isVoiceListened,
    };
  }

  // COPY WITH
  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? receiverId,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    String? attachmentUrl,
    String? attachmentFileName,
    String? attachmentType,
    int? attachmentSize,
    String? audioTitle,
    String? audioArtist,
    String? audioArtworkUrl,
    int? mediaWidth,
    int? mediaHeight,
    String? mediaGroupId,
    int? mediaGroupIndex,
    int? mediaGroupCount,
    String? contactName,
    String? contactPhone,
    String? contactAvatarUrl,
    String? contactUserId,
    int? voiceDuration, // ← NEW
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyPreview,
    String? senderPhone,
    String? senderName,
    bool? isForwarded,
    bool? isStarred,
    bool? isDeletedForMe,
    bool? isDeletedForEveryone,
    bool? isEdited,
    bool? isVoiceListened,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentFileName: attachmentFileName ?? this.attachmentFileName,
      attachmentType: attachmentType ?? this.attachmentType,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      audioTitle: audioTitle ?? this.audioTitle,
      audioArtist: audioArtist ?? this.audioArtist,
      audioArtworkUrl: audioArtworkUrl ?? this.audioArtworkUrl,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      mediaGroupId: mediaGroupId ?? this.mediaGroupId,
      mediaGroupIndex: mediaGroupIndex ?? this.mediaGroupIndex,
      mediaGroupCount: mediaGroupCount ?? this.mediaGroupCount,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      contactAvatarUrl: contactAvatarUrl ?? this.contactAvatarUrl,
      contactUserId: contactUserId ?? this.contactUserId,
      voiceDuration: voiceDuration ?? this.voiceDuration, // ← NEW
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyPreview: replyPreview ?? this.replyPreview,
      senderPhone: senderPhone ?? this.senderPhone,
      senderName: senderName ?? this.senderName,
      isForwarded: isForwarded ?? this.isForwarded,
      isStarred: isStarred ?? this.isStarred,
      isDeletedForMe: isDeletedForMe ?? this.isDeletedForMe,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      isEdited: isEdited ?? this.isEdited,
      isVoiceListened: isVoiceListened ?? this.isVoiceListened,
    );
  }

  // HELPER METHODS
  bool isMine(String currentUserId) => senderId == currentUserId;

  bool get hasAttachment => attachmentUrl != null;

  bool get isVoiceNote => attachmentType == 'voice'; // ← NEW convenience getter

  bool get isVideoMessage => isRoundVideoMessageMarker(
    attachmentType: attachmentType,
    content: content,
    attachmentFileName: attachmentFileName,
    attachmentSize: attachmentSize,
    mediaWidth: mediaWidth,
    mediaHeight: mediaHeight,
  );

  bool get isContact => attachmentType == 'contact';

  bool get isDeleted => isDeletedForMe || isDeletedForEveryone;

  // LOCAL SERIALIZATION
  String toRaw() => jsonEncode(toJson());

  factory ChatMessage.fromRaw(String source) {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return ChatMessage.fromJson(decoded);
    }
    throw const FormatException("Invalid ChatMessage format");
  }

  @override
  String toString() {
    return "ChatMessage(id: $id, senderId: $senderId, receiverId: $receiverId, "
        "content: $content, status: $status, attachmentType: $attachmentType, "
        "voiceDuration: $voiceDuration)";
  }
}

String _redactedMessageText(mx.Event event) {
  final redactedBy = event.redactedBecause?.senderId.trim() ?? '';
  final originalSender = event.senderId.trim();

  if (redactedBy.isNotEmpty &&
      originalSender.isNotEmpty &&
      redactedBy != originalSender) {
    return 'This message was deleted by admin';
  }

  return 'This message was deleted';
}

String _stripReplyFallback(String body) {
  // Matrix prefixes the fallback of an edited reply with `* `. Strip that
  // marker only for fallback detection; it must never expose the quoted MXID
  // or homeserver in the visible message body.
  final candidate = body.startsWith('* > ') ? body.substring(2) : body;
  final split = candidate.split(RegExp(r'\r?\n\r?\n'));

  if (candidate.startsWith('> ') && split.length > 1) {
    return split.sublist(1).join('\n\n');
  }

  return body;
}

String _matrixEventBody(mx.Event event) {
  final newContent = event.content['m.new_content'];
  if (_isMatrixEdit(event) && newContent is Map) {
    final editedBody = newContent['body']?.toString() ?? '';
    if (editedBody.isNotEmpty) return editedBody;
  }
  return event.body;
}

String? _replyPreviewFromFallback(String body) {
  final candidate = body.startsWith('* > ') ? body.substring(2) : body;
  if (!candidate.startsWith('> ')) return null;

  final firstBlock = candidate.split(RegExp(r'\r?\n\r?\n')).first;
  final lines =
      firstBlock
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^> ?'), '').trim())
          .where((line) => line.isNotEmpty)
          .toList();

  if (lines.isEmpty) return null;

  final text = lines.join(' ').replaceFirst(RegExp(r'^<[^>]+>\s*'), '');
  if (text.trim().isEmpty) return null;

  return text.length > 120 ? '${text.substring(0, 120)}...' : text;
}

String? _replySenderFromFallback(String body) {
  final candidate = body.startsWith('* > ') ? body.substring(2) : body;
  if (!candidate.startsWith('> ')) return null;

  final firstBlock = candidate.split(RegExp(r'\r?\n\r?\n')).first;
  final firstLine = firstBlock
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^> ?'), '').trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');

  final match = RegExp(r'^<([^>]+)>').firstMatch(firstLine);
  return match?.group(1);
}

bool _isMatrixEdit(mx.Event event) {
  final relatesTo = event.content['m.relates_to'];
  return relatesTo is Map && relatesTo['rel_type'] == 'm.replace';
}

String? _attachmentTypeFromMatrix(String msgType) {
  switch (msgType) {
    case mx.MessageTypes.Audio:
      return 'voice';
    case mx.MessageTypes.Image:
      return 'image';
    case mx.MessageTypes.Video:
      return 'video';
    case mx.MessageTypes.File:
      return 'file';
    default:
      return null;
  }
}

String? _attachmentUrlFromMatrix(mx.Event event) {
  final mxcUrl = event.attachmentMxcUrl;
  if (mxcUrl == null) return null;
  if (!mxcUrl.isScheme('mxc')) return mxcUrl.toString();
  return mxcUrl.getDownloadLink(event.room.client).toString();
}

String? _thumbnailUrlFromMatrix(mx.Event event) {
  // Encrypted thumbnails cannot be displayed through their raw media URL.
  // ChatService decrypts those small cover files into a persistent local path.
  if (event.isThumbnailEncrypted) return null;

  final mxcUrl = event.thumbnailMxcUrl;
  if (mxcUrl == null || mxcUrl.toString().isEmpty) return null;
  if (!mxcUrl.isScheme('mxc')) return mxcUrl.toString();
  return mxcUrl.getDownloadLink(event.room.client).toString();
}

MessageStatus _statusFromMatrix(mx.EventStatus status) {
  if (status.isSent) return MessageStatus.sent;
  final raw = status.toString().toLowerCase();
  if (raw.contains('error')) return MessageStatus.failed;
  return MessageStatus.sending;
}
