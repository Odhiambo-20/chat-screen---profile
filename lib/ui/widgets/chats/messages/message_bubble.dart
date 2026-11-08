import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart' as audio_players;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wrytte/ui/widgets/global/avatars/user_avatar.dart';
import 'package:wrytte/models/chat_models/chat_message.dart';
import 'package:wrytte/services/attachments/attachment_local_store.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/ui/screens/media/full_screen_image_viewer.dart';
import 'package:wrytte/ui/screens/media/full_screen_video_viewer.dart';
import 'package:wrytte/ui/widgets/global/files/wrytte_file_card.dart';
import 'package:wrytte/ui/widgets/global/links/wrytte_link_preview.dart';
import 'package:wrytte/ui/widgets/global/media/wrytte_persistent_image.dart';
import 'package:wrytte/ui/widgets/global/media/wrytte_video_thumbnail.dart';
import 'package:wrytte/ui/widgets/chats/overlays/message_actions_anchor.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// MessageBubble
//
// Changes vs original:
//   â€¢ Accepts optional `isVoiceNote` and `voiceDuration` and `audioUrl` params
//   â€¢ When isVoiceNote is true, renders a WhatsApp-style voice note player
//     instead of text â€” play/pause button, waveform bars, elapsed time
//   â€¢ Text bubbles: ZERO changes â€” same layout, colours, tail, time, ticks
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

part 'contact_message_bubble.dart';
part 'round_video_message_bubble.dart';
part 'video_message_bubble.dart';
part 'media_attachment_bubbles.dart';
part 'voice_message_bubble.dart';
part 'text_message_content.dart';

const Duration _sendBubblePopDuration = Duration(milliseconds: 480);
const double _sendBubblePopStartScale = 0.04;
const Curve _sendBubblePopCurve = Curves.easeOutCubic;
const double _sharedAttachmentCircleSize = 44.0;
const MethodChannel _messageSendSoundChannel = MethodChannel(
  'com.example.wrytte/message_send_sound',
);

Future<void> _playMessageSendTick() async {
  try {
    final played = await _messageSendSoundChannel.invokeMethod<bool>(
      'playSendTick',
    );
    if (played == true) return;
  } catch (_) {
    // Fall back to the OS click if the native SoundPool is not ready.
  }

  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {
    // Keep audio feedback best-effort; sending must never wait on it.
  }
}

class VoiceNotePlaybackSettings {
  VoiceNotePlaybackSettings._();

  // This is the single source of truth for playback speed across the app.
  // Every mounted speed control listens to it directly, while newly opened
  // chats read the latest value during player initialisation.
  static final ValueNotifier<double> speed = ValueNotifier<double>(1.0);
  static const List<double> supportedSpeeds = <double>[1.0, 1.5, 2.0];

  static double get currentSpeed => speed.value;

  static void setSpeed(double value) {
    if (!supportedSpeeds.contains(value) || speed.value == value) return;
    speed.value = value;
  }

  static void cycleSpeed() {
    final currentIndex = supportedSpeeds.indexOf(speed.value);
    final nextIndex =
        currentIndex < 0 ? 0 : (currentIndex + 1) % supportedSpeeds.length;
    speed.value = supportedSpeeds[nextIndex];
  }
}

class VoiceNotePlaybackController {
  _VoiceNotePlayerState? _attachedPlayer;
  bool _playWhenAttached = false;

  bool get isAttached => _attachedPlayer != null;

  void _attach(_VoiceNotePlayerState player) {
    _attachedPlayer = player;
    if (_playWhenAttached) {
      _playWhenAttached = false;
      unawaited(player._playFromController());
    }
  }

  void _detach(_VoiceNotePlayerState player) {
    if (identical(_attachedPlayer, player)) {
      _attachedPlayer = null;
    }
  }

  // Programmatic play is intentionally not a toggle. Autoplay must never pause
  // a voice note just because it was already selected by the coordinator.
  Future<void> play() async {
    final player = _attachedPlayer;
    if (player == null) {
      _playWhenAttached = true;
      return;
    }
    _playWhenAttached = false;
    await player._playFromController();
  }

  Future<void> pause() async {
    _playWhenAttached = false;
    await _attachedPlayer?._pauseFromController();
  }

  void dispose() {
    _playWhenAttached = false;
    _attachedPlayer = null;
  }
}

class FileAudioPlaybackUiState {
  final String id;
  final String title;
  final String? artist;
  final String? artworkUrl;
  final bool isPlaying;
  final ValueListenable<bool> playing;
  final ValueListenable<double> progress;
  final ValueListenable<Duration> duration;
  final Future<void> Function() togglePlayback;
  final Future<void> Function(double progress) seek;
  final Future<void> Function() close;

  const FileAudioPlaybackUiState({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.isPlaying,
    required this.playing,
    required this.progress,
    required this.duration,
    required this.togglePlayback,
    required this.seek,
    required this.close,
  });
}

class MediaAlbumItem {
  final String id;
  final String imageUrl;
  final String? caption;
  final int? width;
  final int? height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  const MediaAlbumItem({
    required this.id,
    required this.imageUrl,
    this.caption,
    this.width,
    this.height,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });
}

class MessageBubble extends StatelessWidget {
  final String content;
  final String time;
  final String? dateLabel;
  final bool isMine;
  final String? senderName;
  final bool showAdminLabel;
  final bool showTail;
  final MessageStatus? status;

  // â”€â”€ Voice note fields (null = plain text bubble) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final bool isVoiceNote;
  final bool isVideoNote;
  final int? voiceDuration; // total seconds
  final String? audioUrl; // CDN URL from Matrix media upload
  final bool showUnopenedVoiceIndicator;
  final bool isVoiceOpened;
  final Future<void> Function()? onVoiceOpened;
  final bool isVoiceListened;
  final VoidCallback? onVoiceListened;
  final VoidCallback? onVoicePlaybackStarted;
  final VoidCallback? onVoicePlaybackCompleted;
  final VoiceNotePlaybackController? voicePlaybackController;
  final String? attachmentType;
  final String? attachmentUrl;
  final String? attachmentFileName;
  final int? attachmentSize;
  final String? contactName;
  final String? contactPhone;
  final String? contactAvatarUrl;
  final String? contactUserId;
  final Future<void> Function()? onContactMessage;
  final Future<void> Function()? onContactAdd;
  final String? audioTitle;
  final String? audioArtist;
  final String? audioArtworkUrl;
  final VoidCallback? onCancelFileTransfer;
  final ValueChanged<FileAudioPlaybackUiState?>? onFileAudioPlaybackChanged;
  final int? mediaWidth;
  final int? mediaHeight;
  final List<MediaAlbumItem> mediaAlbumItems;
  final bool isForwarded;
  final bool isStarred;
  final bool isDeleted;
  final bool isEdited;
  final bool isPinned;
  final bool isHighlighted;
  final String? replyPreview;
  final String? replySender;
  final VoidCallback? onReplyTap;
  final VoidCallback? onImageTap;
  final Future<void> Function()? onVideoShare;
  final Future<void> Function()? onVideoDownload;
  final Future<void> Function()? onVideoEdit;
  final Future<bool> Function()? onVideoDelete;
  final Future<void> Function()? onVideoReply;
  final Future<void> Function()? onVideoShowInChat;
  final Future<void> Function()? onVideoOpenProfile;
  final String? videoViewerTitle;
  final bool animateOnMount;
  final bool animatePopOnMount;
  final String? sendAnimationId;
  final VoidCallback? onSendAnimationConsumed;
  // Maximum bubble-body width. A visible tail is added outside this width.
  final double? maxWidth;
  final double ambientProgress;
  final bool joinsPrevious;
  final bool joinsNext;
  final GlobalKey? contextMenuBoundaryKey;
  final bool hideForContextMenu;

  static const Color _blue = WrytteColors.primary;
  static const Color _deliveredCheckColor = WrytteColors.textPrimary;
  static const Color _readCheckColor = Color(0xFF2978FF);
  static const TextStyle _timeTextStyle = TextStyle(
    color: Color(0xBFC6C6C6),
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  const MessageBubble({
    super.key,
    required this.content,
    required this.time,
    this.dateLabel,
    required this.isMine,
    this.senderName,
    this.showAdminLabel = false,
    this.showTail = true,
    this.status,
    // voice note params
    this.isVoiceNote = false,
    this.isVideoNote = false,
    this.voiceDuration,
    this.audioUrl,
    this.showUnopenedVoiceIndicator = false,
    this.isVoiceOpened = false,
    this.onVoiceOpened,
    this.isVoiceListened = false,
    this.onVoiceListened,
    this.onVoicePlaybackStarted,
    this.onVoicePlaybackCompleted,
    this.voicePlaybackController,
    this.attachmentType,
    this.attachmentUrl,
    this.attachmentFileName,
    this.attachmentSize,
    this.contactName,
    this.contactPhone,
    this.contactAvatarUrl,
    this.contactUserId,
    this.onContactMessage,
    this.onContactAdd,
    this.audioTitle,
    this.audioArtist,
    this.audioArtworkUrl,
    this.onCancelFileTransfer,
    this.onFileAudioPlaybackChanged,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaAlbumItems = const <MediaAlbumItem>[],
    this.isForwarded = false,
    this.isStarred = false,
    this.isDeleted = false,
    this.isEdited = false,
    this.isPinned = false,
    this.isHighlighted = false,
    this.replyPreview,
    this.replySender,
    this.onReplyTap,
    this.onImageTap,
    this.onVideoShare,
    this.onVideoDownload,
    this.onVideoEdit,
    this.onVideoDelete,
    this.onVideoReply,
    this.onVideoShowInChat,
    this.onVideoOpenProfile,
    this.videoViewerTitle,
    this.animateOnMount = true,
    this.animatePopOnMount = false,
    this.sendAnimationId,
    this.onSendAnimationConsumed,
    this.maxWidth,
    this.ambientProgress = 0,
    this.joinsPrevious = false,
    this.joinsNext = false,
    this.contextMenuBoundaryKey,
    this.hideForContextMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isImageBubble =
        !isDeleted && (attachmentType == 'image' || mediaAlbumItems.length > 1);
    final bool isVideoBubble = !isDeleted && attachmentType == 'video';
    final bool isRoundVideoMessage = !isDeleted && isVideoNote;
    final bool isMediaBubble =
        isImageBubble || isVideoBubble || isRoundVideoMessage;
    final bool hasMediaCaption =
        (attachmentType == 'image' &&
            _visibleImageCaptionText(content) != null) ||
        (attachmentType == 'video' &&
            _visibleVideoCaptionText(content) != null);
    // A caption is painted on the normal bubble surface, not over pixels.
    // Give its timestamp and checks the same geometry as a text bubble while
    // retaining the shadowed, centered treatment for true media overlays.
    final bool usesMediaOverlayMetadata = isMediaBubble && !hasMediaCaption;
    final cleanAttachmentFileName = attachmentFileName?.trim() ?? '';
    final cleanContent = content.trim();
    final inferredFileName =
        cleanAttachmentFileName.isNotEmpty
            ? cleanAttachmentFileName
            : cleanContent.isNotEmpty
            ? cleanContent
            : 'File';
    final fileExtension = p.extension(inferredFileName).toLowerCase();
    final fileCaption =
        cleanAttachmentFileName.isNotEmpty &&
                cleanContent.isNotEmpty &&
                cleanContent != cleanAttachmentFileName
            ? cleanContent
            : '';
    final isCompactFileBubble =
        !isDeleted &&
        attachmentType == 'file' &&
        fileExtension != '.pdf' &&
        fileCaption.isEmpty;
    final isPdfBubble =
        !isDeleted && attachmentType == 'file' && fileExtension == '.pdf';
    final bool isVoiceBubble = isVoiceNote && !isDeleted;
    final bool isContactBubble = !isDeleted && attachmentType == 'contact';
    final bool isPlainTextBubble =
        !isVoiceNote &&
        !isVideoNote &&
        attachmentType == null &&
        (replyPreview?.trim().isEmpty ?? true);
    final plainTextScaler =
        isPlainTextBubble
            ? MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.10)
            : null;
    Widget withPlainTextScaling(Widget child) =>
        isPlainTextBubble
            ? MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.10,
              child: child,
            )
            : child;
    final bool compactFileHasAuthor =
        isCompactFileBubble && (audioArtist?.trim().isNotEmpty ?? false);
    final timeTextStyle = DefaultTextStyle.of(context).style.merge(
      usesMediaOverlayMetadata
          ? _timeTextStyle.copyWith(
            shadows: const <Shadow>[
              Shadow(color: Color(0xB3000000), blurRadius: 3),
            ],
          )
          : _timeTextStyle,
    );
    final Widget timeWidget = _buildTimeRow(
      timeTextStyle,
      centerForMediaOverlay: usesMediaOverlayMetadata,
    );
    final rawTrailingSize = _measureTrailingSize(
      context,
      timeTextStyle,
      textScaler: plainTextScaler,
    );

    // The round-video metadata ends 7px inside the message body's right edge.
    // Match that same visual guide for every outgoing non-media bubble. The
    // offsets compensate for each content type's own right-side padding/inset.
    final outgoingMetadataOffset = isVoiceBubble ? 21.0 : 5.0;
    late final Widget alignedTimeWidget;
    late final Size alignedTrailingSize;
    if (!isMine || usesMediaOverlayMetadata) {
      alignedTimeWidget = timeWidget;
      alignedTrailingSize = rawTrailingSize;
    } else {
      alignedTimeWidget = Transform.translate(
        key: const ValueKey('outgoing-bubble-metadata-alignment'),
        offset: Offset(outgoingMetadataOffset, 0),
        child: timeWidget,
      );
      alignedTrailingSize = rawTrailingSize;
    }

    final Widget contactTimeWidget = _buildTimeRow(_timeTextStyle);
    final Widget fileTimeWidget = _buildTimeRow(_timeTextStyle);
    final trailingSize = alignedTrailingSize;

    final Widget coreBubbleContent =
        isDeleted
            ? withPlainTextScaling(
              _BubbleContent(
                content: content,
                timeWidget: alignedTimeWidget,
                isForwarded: false,
                isStarred: false,
                isDeleted: true,
                isEdited: false,
                replyPreview: null,
                replySender: null,
                onReplyTap: null,
                isMine: isMine,
                trailingWidth: trailingSize.width,
                trailingHeight: trailingSize.height,
              ),
            )
            : isVoiceNote
            ? _VoiceNotePlayer(
              audioUrl: audioUrl ?? '',
              totalSeconds: voiceDuration ?? 0,
              isMine: isMine,
              isOpened: isVoiceOpened,
              isListened: isVoiceListened,
              timeWidget: alignedTimeWidget,
              onOpened: onVoiceOpened,
              onListened: onVoiceListened,
              onPlaybackStarted: onVoicePlaybackStarted,
              onPlaybackCompleted: onVoicePlaybackCompleted,
              playbackController: voicePlaybackController,
            )
            : mediaAlbumItems.length > 1
            ? _MediaAlbumMessageBubble(
              items: mediaAlbumItems,
              timeWidget: alignedTimeWidget,
              isForwarded: isForwarded,
              isMine: isMine,
              showTail: showTail && !joinsNext,
              senderName: senderName,
              showAdminLabel: showAdminLabel,
            )
            : attachmentType == 'image'
            ? _ImageMessageBubble(
              imageUrl: attachmentUrl ?? '',
              timeWidget: alignedTimeWidget,
              isForwarded: isForwarded,
              isMine: isMine,
              showTail: showTail && !joinsNext,
              mediaWidth: mediaWidth,
              mediaHeight: mediaHeight,
              senderName: senderName,
              showAdminLabel: showAdminLabel,
              caption: content,
              isStarred: isStarred,
              trailingWidth: trailingSize.width,
              trailingHeight: trailingSize.height,
              onTap: onImageTap,
            )
            : attachmentType == 'contact'
            ? _ContactMessageBubble(
              name: contactName,
              phone: contactPhone,
              avatarUrl: contactAvatarUrl,
              userId: contactUserId,
              timeWidget: contactTimeWidget,
              isMine: isMine,
              isForwarded: isForwarded,
              replyPreview: replyPreview,
              replySender: replySender,
              onReplyTap: onReplyTap,
              onMessage: onContactMessage,
              onAddContact: onContactAdd,
            )
            : attachmentType == 'file'
            ? fileExtension == '.pdf'
                ? WrytteFileCard(
                  fileName: inferredFileName,
                  source: attachmentUrl ?? '',
                  trailing: alignedTimeWidget,
                  isForwarded: isForwarded,
                  isMine: isMine,
                )
                : _FileMessageBubble(
                  fileName: inferredFileName,
                  fileUrl: attachmentUrl ?? '',
                  totalBytes: attachmentSize,
                  durationSeconds: voiceDuration,
                  audioTitle: audioTitle,
                  audioArtist: audioArtist,
                  audioArtworkUrl: audioArtworkUrl,
                  onCancelTransfer: onCancelFileTransfer,
                  onPlaybackChanged: onFileAudioPlaybackChanged,
                  caption: fileCaption,
                  timeWidget: fileTimeWidget,
                  timeWidth: rawTrailingSize.width,
                  isForwarded: isForwarded,
                  isMine: isMine,
                  status: status,
                )
            : isVideoNote
            ? _RoundVideoMessageBubble(
              videoUrl: attachmentUrl ?? '',
              durationSeconds: voiceDuration,
              viewerTitle: videoViewerTitle,
              viewerSubtitle: '${dateLabel ?? 'Today'}, $time',
              timeWidget: alignedTimeWidget,
              isMine: isMine,
              onShare: onVideoShare,
              onDownload: onVideoDownload,
              onDelete: onVideoDelete,
              onReply: onVideoReply,
              onShowInChat: onVideoShowInChat,
              onOpenProfile: onVideoOpenProfile,
            )
            : attachmentType == 'video'
            ? _VideoMessageBubble(
              videoUrl: attachmentUrl ?? '',
              durationSeconds: voiceDuration,
              viewerTitle: videoViewerTitle,
              viewerSubtitle: '${dateLabel ?? 'Today'}, $time',
              timeWidget: alignedTimeWidget,
              isForwarded: isForwarded,
              isMine: isMine,
              showTail: showTail && !joinsNext,
              mediaWidth: mediaWidth,
              mediaHeight: mediaHeight,
              senderName: senderName,
              showAdminLabel: showAdminLabel,
              caption: content,
              isStarred: isStarred,
              trailingWidth: trailingSize.width,
              trailingHeight: trailingSize.height,
              onShare: onVideoShare,
              onDownload: onVideoDownload,
              onEdit: onVideoEdit,
              onDelete: onVideoDelete,
              onReply: onVideoReply,
              onShowInChat: onVideoShowInChat,
              onOpenProfile: onVideoOpenProfile,
            )
            : withPlainTextScaling(
              _BubbleContent(
                content: content,
                timeWidget: alignedTimeWidget,
                isForwarded: isForwarded,
                isStarred: isStarred,
                isDeleted: isDeleted,
                isEdited: isEdited,
                replyPreview: replyPreview,
                replySender: replySender,
                onReplyTap: onReplyTap,
                isMine: isMine,
                trailingWidth: trailingSize.width,
                trailingHeight: trailingSize.height,
              ),
            );

    final hasSenderMetadata =
        !isMine && (senderName?.trim().isNotEmpty == true || showAdminLabel);
    final Widget bubbleContent =
        isMediaBubble || !hasSenderMetadata
            ? coreBubbleContent
            : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (senderName?.trim().isNotEmpty == true)
                        Flexible(
                          child: Text(
                            senderName!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFC861),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (showAdminLabel) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'Admin',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                coreBubbleContent,
              ],
            );

    final Widget bubble;

    // Keep normal text on its own radius path. Text was previously included in
    // `usesCapsuleTail`, which gave one-line messages the 40px voice radius.
    // Flutter then clamps that radius to half the bubble height, producing the
    // pill/capsule look seen on short messages such as "derrick".
    final bool isTextSurface =
        !isVoiceNote && !isVideoNote && attachmentType == null;

    // Voice notes and compact audio/file attachments use the same rounded-square
    // body as the rest of the chat design. Their content and tail stay unchanged;
    // only the old 40px capsule silhouette is removed.
    final bool usesRoundedSquareAttachment =
        isVoiceBubble || isCompactFileBubble;
    final bool hasTail = showTail && !joinsNext;

    const Radius attachmentRadius = Radius.circular(20);
    const Radius textRadius = Radius.circular(18);

    final BorderRadius borderRadius =
        isTextSurface
            ? const BorderRadius.all(textRadius)
            : usesRoundedSquareAttachment
            ? const BorderRadius.all(attachmentRadius)
            : _bubbleRadius();

    final EdgeInsets bubblePadding =
        isVoiceBubble
            ? _VoiceNoteGeometry.noTailBubblePadding
            : isCompactFileBubble
            // Artist/author rows already have enough natural height, so keep their
            // original compact padding. Files without an author get extra vertical
            // breathing room to preserve the strong rounded silhouette.
            ? compactFileHasAuthor
                ? const EdgeInsets.fromLTRB(10, 8, 12, 8)
                : const EdgeInsets.fromLTRB(10, 16, 12, 16)
            : isContactBubble
            ? const EdgeInsets.fromLTRB(12, 12, 12, 8)
            : isPdfBubble
            ? EdgeInsets.zero
            : isPlainTextBubble
            ? const EdgeInsets.fromLTRB(12, 7, 12, 6)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    if (isMediaBubble) {
      bubble = Padding(
        padding:
            isRoundVideoMessage
                ? const EdgeInsets.only(top: 9, bottom: 12)
                : const EdgeInsets.only(top: 1, bottom: 1),
        child: bubbleContent,
      );
    } else if (!isMine) {
      bubble = Container(
        margin: const EdgeInsets.only(top: 1, bottom: 1),
        child: _IncomingBubbleSurface(
          borderRadius: borderRadius,
          showTail: hasTail,
          useRRectTail: false,
          padding: bubblePadding,
          child: bubbleContent,
        ),
      );
    } else {
      bubble = _MessageBubbleSurface(
        margin: const EdgeInsets.only(top: 1, bottom: 1),
        isMine: true,
        showTail: hasTail,
        useRRectTail: false,
        borderRadius: borderRadius,
        padding: bubblePadding,
        gradient: const LinearGradient(colors: [_blue, _blue]),
        child: bubbleContent,
      );
    }

    const screenEdgeMargin = 14.0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final widthBudget = _BubbleWidthBudget.resolve(
      viewportWidth: viewportWidth,
      requestedMaxBodyWidth: maxWidth,
      screenEdgeMargin: screenEdgeMargin,
      showTail: hasTail,
    );

    // The bubble surface now paints the body and Telegram-style tail as one
    // continuous path. No separate tail widget is overlaid, so every message
    // type shares the exact same body/tail silhouette and clipping geometry.
    final contextMenuBubble =
        contextMenuBoundaryKey == null && !hideForContextMenu
            ? bubble
            : MessageActionsAnchor(
              key: contextMenuBoundaryKey,
              child: Opacity(
                opacity: hideForContextMenu ? 0 : 1,
                child: bubble,
              ),
            );
    final standardSlotWidth =
        isRoundVideoMessage
            ? (viewportWidth - (screenEdgeMargin * 2))
                .clamp(0.0, double.infinity)
                .toDouble()
            : widthBudget.maxSurfaceWidth;
    final standardBubbleSlot = SizedBox(
      width: standardSlotWidth,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: contextMenuBubble,
      ),
    );
    final bubbleSlot =
        isVoiceBubble && !isMine
            ? SizedBox(
              width: widthBudget.maxSurfaceWidth,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      right: _VoiceNoteGeometry.unopenedIndicatorReserve,
                    ),
                    child: SizedBox(
                      width:
                          (widthBudget.maxSurfaceWidth -
                                  _VoiceNoteGeometry.unopenedIndicatorReserve)
                              .clamp(0.0, double.infinity)
                              .toDouble(),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: contextMenuBubble,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: _UnopenedVoiceIndicator(
                      visible: showUnopenedVoiceIndicator,
                      color: _readCheckColor,
                      onTap: () {
                        final controller = voicePlaybackController;
                        if (controller != null) {
                          unawaited(controller.play());
                        } else {
                          final openFuture = onVoiceOpened?.call();
                          if (openFuture != null) unawaited(openFuture);
                        }
                      },
                    ),
                  ),
                ],
              ),
            )
            : standardBubbleSlot;

    final messageRow = SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? screenEdgeMargin : widthBudget.surfaceEdgeInset,
          right: isMine ? widthBudget.surfaceEdgeInset : screenEdgeMargin,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children:
              isMine
                  ? [const Spacer(), bubbleSlot]
                  : [bubbleSlot, const Spacer()],
        ),
      ),
    );
    if (sendAnimationId != null) {
      return _MessageBubbleSendEntrance(
        key: ValueKey<String>('message-send-entrance:$sendAnimationId'),
        startAnimation:
            animatePopOnMount && !MediaQuery.disableAnimationsOf(context),
        isMine: isMine,
        onAnimationConsumed: onSendAnimationConsumed,
        child: messageRow,
      );
    }
    if (!animateOnMount || MediaQuery.disableAnimationsOf(context)) {
      return messageRow;
    }

    const beginOffset = 24.0;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: 1 - (value * 0.08),
          child: Transform.translate(
            offset: Offset(beginOffset * value, 0),
            child: child,
          ),
        );
      },
      child: messageRow,
    );
  }

  BorderRadius _bubbleRadius() {
    const full = Radius.circular(20);
    return const BorderRadius.all(full);
  }

  Widget _buildTimeRow(
    TextStyle textStyle, {
    bool centerForMediaOverlay = false,
  }) {
    final statusIcon = _buildStatusIcon(
      centerForMediaOverlay: centerForMediaOverlay,
    );
    final compactVoiceStatus = isVoiceNote && !isDeleted;

    return Row(
      key: const ValueKey('message-time-row'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centerForMediaOverlay
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.end,
      children: [
        if (isPinned) ...[
          wrytteSvgAssetIcon(
            assetPath: 'assets/svg/Pin icon fill.svg',
            canvas: 12,
            color: Colors.white.withOpacity(isMine ? 0.72 : 0.55),
          ),
          const SizedBox(width: 3),
        ],
        if (isEdited && !isDeleted) ...[
          Text('Edited', style: textStyle),
          const SizedBox(width: 5),
        ],
        Text(time, style: textStyle),
        if (isMine) ...[
          const SizedBox(width: 3),
          if (compactVoiceStatus)
            SizedBox(
              width: _statusIconSize,
              height: textStyle.fontSize ?? _timeTextStyle.fontSize,
              child: OverflowBox(
                minWidth: _statusIconSize,
                maxWidth: _statusIconSize,
                minHeight: _statusIconSize,
                maxHeight: _statusIconSize,
                alignment: Alignment.bottomCenter,
                child: statusIcon,
              ),
            )
          else
            statusIcon,
        ],
      ],
    );
  }

  Size _measureTrailingSize(
    BuildContext context,
    TextStyle textStyle, {
    TextScaler? textScaler,
  }) {
    final textDirection = Directionality.of(context);
    final effectiveTextScaler = textScaler ?? MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    Size measure(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: textStyle),
        textDirection: textDirection,
        textScaler: effectiveTextScaler,
        locale: locale,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final editedSize = isEdited && !isDeleted ? measure('Edited') : Size.zero;
    final editedGapWidth = isEdited && !isDeleted ? 5.0 : 0.0;
    final timeSize = measure(time);
    final pinnedWidth = isPinned ? 15.0 : 0.0;
    final statusWidth = isMine ? 3 + _statusIconSize : 0.0;
    final textHeight =
        editedSize.height > timeSize.height
            ? editedSize.height
            : timeSize.height;
    final rowHeight =
        isMine && _statusIconSize > textHeight ? _statusIconSize : textHeight;
    return Size(
      pinnedWidth +
          editedSize.width +
          editedGapWidth +
          timeSize.width +
          statusWidth,
      rowHeight,
    );
  }

  double get _statusIconSize => switch (status) {
    MessageStatus.sending => 13,
    MessageStatus.failed => 14,
    _ => 17,
  };

  Widget _buildCheckmarkIcon({
    required String assetPath,
    required Color color,
    bool centerForMediaOverlay = false,
  }) {
    return Transform.translate(
      offset: centerForMediaOverlay ? Offset.zero : const Offset(0, 2),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          centerForMediaOverlay ? 1 : 1.05,
          centerForMediaOverlay ? 1 : 1.12,
          1,
        ),
        child: wrytteSvgAssetIcon(
          assetPath: assetPath,
          canvas: _statusIconSize,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusIcon({bool centerForMediaOverlay = false}) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(
          Icons.access_time_rounded,
          size: _statusIconSize,
          color: Colors.white.withOpacity(0.55),
        );
      case MessageStatus.sent:
        return _buildCheckmarkIcon(
          assetPath: 'assets/svg/Single checkmark.svg',
          color: _deliveredCheckColor,
          centerForMediaOverlay: centerForMediaOverlay,
        );
      case MessageStatus.delivered:
        return _buildCheckmarkIcon(
          assetPath: 'assets/svg/Check mark delivered .svg',
          color: _deliveredCheckColor,
          centerForMediaOverlay: centerForMediaOverlay,
        );
      case MessageStatus.read:
        return _buildCheckmarkIcon(
          assetPath: 'assets/svg/Check mark delivered .svg',
          color: _readCheckColor,
          centerForMediaOverlay: centerForMediaOverlay,
        );
      case MessageStatus.failed:
        return Icon(
          Icons.error_outline,
          size: _statusIconSize,
          color: Colors.redAccent,
        );
      default:
        return _buildCheckmarkIcon(
          assetPath: 'assets/svg/Check mark delivered .svg',
          color: _deliveredCheckColor,
          centerForMediaOverlay: centerForMediaOverlay,
        );
    }
  }
}

class _MessageBubbleSendEntrance extends StatefulWidget {
  final bool startAnimation;
  final bool isMine;
  final VoidCallback? onAnimationConsumed;
  final Widget child;

  const _MessageBubbleSendEntrance({
    super.key,
    required this.startAnimation,
    required this.isMine,
    this.onAnimationConsumed,
    required this.child,
  });

  @override
  State<_MessageBubbleSendEntrance> createState() =>
      _MessageBubbleSendEntranceState();
}

class _MessageBubbleSendEntranceState extends State<_MessageBubbleSendEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _sendBubblePopDuration,
      value: widget.startAnimation ? 0 : 1,
    );
    _scale = Tween<double>(
      begin: _sendBubblePopStartScale,
      end: 1,
    ).animate(
      CurvedAnimation(parent: _controller, curve: _sendBubblePopCurve),
    );
    if (widget.startAnimation) {
      _controller.forward();
      unawaited(_playMessageSendTick());
    }
    widget.onAnimationConsumed?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignment = widget.isMine
        ? Alignment.bottomRight
        : Alignment.bottomLeft;
    return AnimatedBuilder(
      animation: _controller,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final scale = _scale.value;
        return Align(
          alignment: alignment,
          heightFactor: scale,
          child: Transform.scale(
            alignment: alignment,
            scale: scale,
            child: child,
          ),
        );
      },
    );
  }
}
