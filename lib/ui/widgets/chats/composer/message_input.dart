import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart' hide PlayerState;
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart' as pie;
import 'package:pro_video_editor/pro_video_editor.dart' as pve;
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;
import 'package:video_player/video_player.dart';
import 'package:wrytte/services/attachments/attachment_local_store.dart';
import 'package:wrytte/services/audio/audio_file_metadata_service.dart';
import 'package:wrytte/services/auth/auth_service.dart';
import 'package:wrytte/services/media/camera_inventory_service.dart';
import 'package:wrytte/services/permissions/app_permission_service.dart';
import 'package:wrytte/services/permissions/photo_library_permission_service.dart';
import 'package:wrytte/services/contacts/contact_local_db.dart';
import 'package:wrytte/services/contacts/contact_service.dart';
import 'package:wrytte/ui/widgets/global/avatars/user_avatar.dart';
import 'package:wrytte/models/contact_model.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/models/chat_models/ui/chat_attachment_models.dart';
import 'package:wrytte/ui/screens/chats/chat_camera_screen.dart';
import 'package:wrytte/ui/screens/chats/chat_media_editor.dart';
import 'package:wrytte/ui/screens/media/full_screen_image_viewer.dart';
import 'package:wrytte/ui/auth/profile_photo_crop_page.dart';
import 'package:wrytte/ui/widgets/chats/attachments/chat_location_picker.dart';
import 'package:wrytte/ui/controllers/chats/message_input_attachment_controller.dart';
import 'package:wrytte/ui/widgets/global/media/wrytte_persistent_image.dart';
import 'package:wrytte/ui/widgets/global/media/wrytte_camera_preview_surface.dart';
import 'package:wrytte/ui/core/models/expanding_surface_origin.dart';
import 'package:wrytte/ui/core/routing/expanding_surface_route.dart';

export 'package:wrytte/models/chat_models/ui/chat_attachment_models.dart';
export 'package:wrytte/ui/controllers/chats/message_input_attachment_controller.dart';

part '../attachments/telegram_attachment_panel.dart';
part 'recording_widgets.dart';

enum _AttachmentAction { camera, gallery, file }

const Duration _attachmentPanelTransitionDuration = Duration(milliseconds: 280);

PageRouteBuilder<ChatCameraResult> _attachmentCameraRoute({
  required String recipientLabel,
  CameraController? initialController,
  bool initialAudioEnabled = false,
  bool photoOnly = false,
  Rect? sourceRect,
  void Function(CameraController controller, bool audioEnabled)?
  onReturnController,
}) {
  return PageRouteBuilder<ChatCameraResult>(
    opaque: false,
    barrierColor: Colors.transparent,
    maintainState: true,
    allowSnapshotting: false,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => ChatCameraScreen(
      recipientLabel: recipientLabel,
      initialController: initialController,
      initialAudioEnabled: initialAudioEnabled,
      photoOnly: photoOnly,
      openingCameraRect: sourceRect,
      onReturnController: onReturnController,
    ),
    // The camera screen owns the measured tile-to-fullscreen preview motion
    // together with its backdrop/chrome. A second route transition here would
    // make that single movement look like two competing animations.
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        child,
  );
}

Widget _attachmentPanelSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // The panel owns its entrance treatment. On dismissal, use only a short
  // downward movement: no route-level fade or scale.
  if (animation.status != AnimationStatus.reverse) return child;
  final position = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInCubic));
  return SlideTransition(position: position, child: child);
}

class ProfilePhotoPickResult {
  const ProfilePhotoPickResult({
    required this.path,
    required this.alreadyCropped,
  });

  final String path;
  final bool alreadyCropped;
}

class _RecentAttachmentFile {
  final String path;
  final String name;
  final String attachmentType;
  final int size;
  final String extension;

  const _RecentAttachmentFile({
    required this.path,
    required this.name,
    required this.attachmentType,
    required this.size,
    required this.extension,
  });
}

class _FileBadgePainter extends CustomPainter {
  final Color color;

  const _FileBadgePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final fold = size.width * 0.31;
    final radius = Radius.circular(size.width * 0.12);
    final body = Path()
      ..moveTo(radius.x, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height - radius.y)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - radius.x,
        size.height,
      )
      ..lineTo(radius.x, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius.y)
      ..lineTo(0, radius.y)
      ..quadraticBezierTo(0, 0, radius.x, 0)
      ..close();
    canvas.drawPath(body, Paint()..color = color);

    final foldPath = Path()
      ..moveTo(size.width - fold, 0)
      ..lineTo(size.width - fold, fold)
      ..lineTo(size.width, fold)
      ..close();
    canvas.drawPath(
      foldPath,
      Paint()..color = Color.lerp(color, Colors.white, 0.40)!,
    );
  }

  @override
  bool shouldRepaint(covariant _FileBadgePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Opens the same gallery surface used by the chat attachment button, reduced
/// to the single action needed while setting an account photo.
Future<void> _openProfilePhotoCameraAbovePanel({
  required BuildContext dialogContext,
  required _AttachmentSelection selection,
}) async {
  final route = _attachmentCameraRoute(
    recipientLabel: 'Profile photo',
    initialController: selection.cameraController,
    initialAudioEnabled: selection.cameraAudioEnabled,
    photoOnly: true,
    sourceRect: selection.cameraSourceRect,
    onReturnController: selection.onCameraControllerReturned,
  );
  final result = await Navigator.of(
    dialogContext,
  ).push<ChatCameraResult>(route);
  await route.completed;

  if (!dialogContext.mounted || result == null) return;
  if (result.openGallery) {
    Navigator.of(dialogContext).pop<_AttachmentSelection>(
      const _AttachmentSelection.action(_AttachmentAction.gallery),
    );
    return;
  }

  final path = result.filePath?.trim() ?? '';
  if (path.isEmpty || result.attachmentType?.trim() != 'image') return;
  Navigator.of(dialogContext).pop<_AttachmentSelection>(
    _AttachmentSelection.media(
      profilePhotoAlreadyCropped: true,
      media: <ChatPickedAttachment>[
        ChatPickedAttachment(
          filePath: path,
          attachmentType: 'image',
          width: 640,
          height: 640,
        ),
      ],
    ),
  );
}

Future<void> _closeProfilePhotoPanelWithSelection({
  required BuildContext panelContext,
  required _AttachmentSelection selection,
  ValueChanged<String>? onProfilePhotoCommitted,
}) async {
  if (selection.profilePhotoAlreadyCropped &&
      selection.media.isNotEmpty &&
      onProfilePhotoCommitted != null) {
    final path = selection.media.first.filePath.trim();
    if (path.isNotEmpty) {
      // Update the page underneath the non-opaque panel first. This creates the
      // destination avatar Hero before the panel PageRoute begins popping.
      onProfilePhotoCommitted(path);
      await WidgetsBinding.instance.endOfFrame;
      if (!panelContext.mounted) return;
    }
  }

  Navigator.of(panelContext).pop(selection);
}

Future<ProfilePhotoPickResult?> showProfilePhotoGalleryPanel({
  required BuildContext context,
  bool initiallyExpanded = false,
  Object? destinationHeroTag,
  ValueChanged<String>? onProfilePhotoCommitted,
}) async {
  final navigator = Navigator.of(context);
  final selection = await navigator.push<_AttachmentSelection>(
    PageRouteBuilder<_AttachmentSelection>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.44),
      maintainState: true,
      allowSnapshotting: false,
      transitionDuration: _attachmentPanelTransitionDuration,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (panelContext, animation, secondaryAnimation) => Material(
        color: Colors.transparent,
        child: _TelegramAttachmentPanel(
          key: const ValueKey('profile-photo-gallery-panel'),
          recipientLabel: '',
          profilePhotoMode: true,
          initiallyExpanded: initiallyExpanded,
          profilePhotoDestinationHeroTag: destinationHeroTag,
          onCameraSelected: (selected) => _openProfilePhotoCameraAbovePanel(
            dialogContext: panelContext,
            selection: selected,
          ),
          onSelected: (selected) {
            unawaited(
              _closeProfilePhotoPanelWithSelection(
                panelContext: panelContext,
                selection: selected,
                onProfilePhotoCommitted: onProfilePhotoCommitted,
              ),
            );
          },
        ),
      ),
      transitionsBuilder: _attachmentPanelSlideTransition,
    ),
  );

  if (selection == null || !context.mounted) return null;
  if (selection.action == _AttachmentAction.gallery) {
    return showProfilePhotoGalleryPanel(
      context: context,
      initiallyExpanded: true,
      destinationHeroTag: destinationHeroTag,
      onProfilePhotoCommitted: onProfilePhotoCommitted,
    );
  }
  if (selection.action == _AttachmentAction.camera) {
    final cameraResult = await Navigator.of(context, rootNavigator: true)
        .push<ChatCameraResult>(
          PageRouteBuilder<ChatCameraResult>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 230),
            pageBuilder: (context, animation, secondaryAnimation) =>
                ChatCameraScreen(
                  recipientLabel: 'Profile photo',
                  initialController: selection.cameraController,
                  initialAudioEnabled: selection.cameraAudioEnabled,
                  photoOnly: true,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(opacity: curved, child: child);
                },
          ),
        );
    if (!context.mounted) return null;
    if (cameraResult?.openGallery == true) {
      return showProfilePhotoGalleryPanel(
        context: context,
        initiallyExpanded: true,
        destinationHeroTag: destinationHeroTag,
        onProfilePhotoCommitted: onProfilePhotoCommitted,
      );
    }
    final path = cameraResult?.filePath?.trim() ?? '';
    final type = cameraResult?.attachmentType?.trim() ?? '';
    if (path.isEmpty || type != 'image') return null;
    return ProfilePhotoPickResult(path: path, alreadyCropped: true);
  }
  if (selection.media.isEmpty) return null;
  return ProfilePhotoPickResult(
    path: selection.media.first.filePath,
    alreadyCropped: selection.profilePhotoAlreadyCropped,
  );
}

Future<void> _openReplacementCameraAbovePanel({
  required BuildContext panelContext,
  required _AttachmentSelection selection,
  required String recipientLabel,
  required String initialCaption,
}) async {
  final route = _attachmentCameraRoute(
    recipientLabel: recipientLabel,
    initialController: selection.cameraController,
    initialAudioEnabled: selection.cameraAudioEnabled,
    sourceRect: selection.cameraSourceRect,
    onReturnController: selection.onCameraControllerReturned,
  );
  final result = await Navigator.of(panelContext).push<ChatCameraResult>(route);
  await route.completed;

  if (!panelContext.mounted || result == null) return;
  if (result.openGallery) {
    Navigator.of(panelContext).pop<_AttachmentSelection>(
      const _AttachmentSelection.action(_AttachmentAction.gallery),
    );
    return;
  }

  final path = result.filePath?.trim() ?? '';
  final type = result.attachmentType?.trim() ?? '';
  if (path.isEmpty || type.isEmpty) return;

  Navigator.of(panelContext).pop<_AttachmentSelection>(
    _AttachmentSelection.media(
      caption: result.caption?.trim().isNotEmpty == true
          ? result.caption!.trim()
          : initialCaption.trim(),
      media: <ChatPickedAttachment>[
        ChatPickedAttachment(filePath: path, attachmentType: type),
      ],
    ),
  );
}

Future<ChatMediaReplacementSelection?> showChatMediaReplacementPanel({
  required BuildContext context,
  required String recipientLabel,
  required String initialCaption,
  bool initiallyExpanded = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final selection = await navigator.push<_AttachmentSelection>(
    PageRouteBuilder<_AttachmentSelection>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.44),
      maintainState: true,
      allowSnapshotting: false,
      transitionDuration: _attachmentPanelTransitionDuration,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (panelContext, animation, secondaryAnimation) => Material(
        color: Colors.transparent,
        child: _TelegramAttachmentPanel(
          recipientLabel: recipientLabel,
          replacementMode: true,
          initialCaption: initialCaption,
          initiallyExpanded: initiallyExpanded,
          onCameraSelected: (selected) => _openReplacementCameraAbovePanel(
            panelContext: panelContext,
            selection: selected,
            recipientLabel: recipientLabel,
            initialCaption: initialCaption,
          ),
          onSelected: (selected) {
            unawaited(HapticFeedback.selectionClick());
            Navigator.of(panelContext).pop(selected);
          },
        ),
      ),
      transitionsBuilder: _attachmentPanelSlideTransition,
    ),
  );

  if (selection == null || !context.mounted) return null;
  if (selection.action == _AttachmentAction.gallery) {
    return showChatMediaReplacementPanel(
      context: context,
      recipientLabel: recipientLabel,
      initialCaption: initialCaption,
      initiallyExpanded: true,
    );
  }
  if (selection.action == _AttachmentAction.camera) {
    final cameraResult = await Navigator.of(context, rootNavigator: true)
        .push<ChatCameraResult>(
          PageRouteBuilder<ChatCameraResult>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 230),
            pageBuilder: (context, animation, secondaryAnimation) =>
                ChatCameraScreen(
                  recipientLabel: recipientLabel,
                  initialController: selection.cameraController,
                  initialAudioEnabled: selection.cameraAudioEnabled,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(opacity: curved, child: child);
                },
          ),
        );
    if (cameraResult?.openGallery == true) {
      return showChatMediaReplacementPanel(
        context: context,
        recipientLabel: recipientLabel,
        initialCaption: initialCaption,
        initiallyExpanded: true,
      );
    }
    final path = cameraResult?.filePath?.trim() ?? '';
    final type = cameraResult?.attachmentType?.trim() ?? '';
    if (path.isEmpty || type.isEmpty) return null;
    return ChatMediaReplacementSelection(
      media: <ChatPickedAttachment>[
        ChatPickedAttachment(filePath: path, attachmentType: type),
      ],
      caption: cameraResult?.caption?.trim() ?? initialCaption.trim(),
    );
  }
  if (selection.media.isEmpty) return null;
  return ChatMediaReplacementSelection(
    media: selection.media,
    caption: selection.caption?.trim() ?? '',
  );
}

class _EditingMediaThumbnail extends StatefulWidget {
  final String source;
  final String? mediaType;

  const _EditingMediaThumbnail({required this.source, required this.mediaType});

  @override
  State<_EditingMediaThumbnail> createState() => _EditingMediaThumbnailState();
}

class _EditingMediaThumbnailState extends State<_EditingMediaThumbnail> {
  Future<Uint8List?>? _videoThumbnail;

  bool get _isVideo => widget.mediaType?.trim().toLowerCase() == 'video';

  @override
  void initState() {
    super.initState();
    if (_isVideo) _videoThumbnail = _loadVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant _EditingMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.mediaType != widget.mediaType) {
      _videoThumbnail = _isVideo ? _loadVideoThumbnail() : null;
    }
  }

  Future<Uint8List?> _loadVideoThumbnail() async {
    try {
      final copy = await AttachmentLocalStore.instance.ensureComplete(
        source: widget.source,
        fileName: 'edit_media_preview.mp4',
      );
      if (!copy.isComplete || !await copy.file.exists()) return null;
      return video_thumbnail.VideoThumbnail.thumbnailData(
        video: copy.file.path,
        imageFormat: video_thumbnail.ImageFormat.JPEG,
        maxWidth: 144,
        maxHeight: 144,
        quality: 80,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (_isVideo) {
      preview = FutureBuilder<Uint8List?>(
        future: _videoThumbnail,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return const ColoredBox(
              color: WrytteColors.surfaceRaised,
              child: Center(
                child: Icon(
                  Icons.videocam_rounded,
                  size: 20,
                  color: WrytteColors.textSecondary,
                ),
              ),
            );
          }
          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        },
      );
    } else {
      preview = WryttePersistentImage(
        source: widget.source,
        fit: BoxFit.cover,
        placeholder: const ColoredBox(color: WrytteColors.surfaceRaised),
        errorWidget: const ColoredBox(color: WrytteColors.surfaceRaised),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 42,
        child: ColoredBox(color: WrytteColors.surfaceRaised, child: preview),
      ),
    );
  }
}

class _AttachmentSelection {
  final _AttachmentAction? action;
  final List<ChatPickedAttachment> media;
  final List<Contact> contacts;
  final String? caption;
  final CameraController? cameraController;
  final bool cameraAudioEnabled;
  final Rect? cameraSourceRect;
  final bool profilePhotoAlreadyCropped;
  final void Function(CameraController controller, bool audioEnabled)?
  onCameraControllerReturned;

  const _AttachmentSelection.action(
    _AttachmentAction this.action, {
    this.cameraController,
    this.cameraAudioEnabled = false,
    this.cameraSourceRect,
    this.onCameraControllerReturned,
  }) : media = const <ChatPickedAttachment>[],
       contacts = const <Contact>[],
       caption = null,
       profilePhotoAlreadyCropped = false;

  const _AttachmentSelection.media({
    required this.media,
    this.caption,
    this.profilePhotoAlreadyCropped = false,
  }) : action = null,
       contacts = const <Contact>[],
       cameraController = null,
       cameraAudioEnabled = false,
       cameraSourceRect = null,
       onCameraControllerReturned = null;

  const _AttachmentSelection.contacts({required this.contacts, this.caption})
    : action = null,
      media = const <ChatPickedAttachment>[],
      cameraController = null,
      cameraAudioEnabled = false,
      cameraSourceRect = null,
      onCameraControllerReturned = null,
      profilePhotoAlreadyCropped = false;
}

enum _VideoMessageCameraAccessState {
  idle,
  requestingPermission,
  opening,
  ready,
  denied,
  unavailable,
}

// ─────────────────────────────────────────────────────────────────────────────
// MessageInputField
//
// Changes vs original:
//   • Converted from StatelessWidget → StatefulWidget (needed for recorder state)
//   • Added onVoiceMessage callback — called with (filePath, durationSeconds)
//     when the user lifts their finger off the mic button
//   • Mic button: tap-and-hold to record, release to send (exactly WhatsApp)
//   • Mic button shows a red pulsing dot + elapsed timer while recording
//   • All layout, colours, glass pill shapes, send button — UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

class MessageInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final double inputPillHeight;
  final double controlSize;
  final double controlGap;
  final double controlScale;
  final double horizontalPadding;
  final String? replySender;
  final String? replyPreview;
  final VoidCallback? onCancelReply;
  final bool isEditing;
  final VoidCallback? onCancelEdit;
  final String? editingMediaSource;
  final String? editingMediaType;
  final Future<void> Function()? onReplaceEditingMedia;

  // ── Voice/video message callbacks ─────────────────────────────────────────
  // Voice: filePath is the recorded .aac file.
  final Future<void> Function(String filePath, int durationSeconds)?
  onVoiceMessage;

  // Legacy hook kept so existing callers do not break. It is only used as a
  // fallback if the inline Telegram-style camera cannot be started.
  final Future<void> Function()? onVideoMessage;

  // Preferred hook for Telegram-style round video messages recorded inline.
  // filePath is the recorded camera file returned by the camera package.
  final Future<void> Function(String filePath, int durationSeconds)?
  onVideoMessageRecorded;
  final Future<void> Function()? onCameraAttachment;
  final Future<void> Function()? onGalleryAttachment;
  final Future<void> Function()? onFileAttachment;
  final Future<void> Function(
    String filePath,
    String attachmentType, {
    String? caption,
    String? mediaGroupId,
    int? mediaGroupIndex,
    int? mediaGroupCount,
    int? mediaWidth,
    int? mediaHeight,
    String? audioTitle,
    String? audioArtist,
    String? audioArtworkPath,
    int? audioDurationSeconds,
  })?
  onPickedAttachment;
  final Future<void> Function(
    List<ChatPickedAttachment> media, {
    String? caption,
  })?
  onPickedAttachments;
  final Future<void> Function(List<Contact> contacts, {String? caption})?
  onPickedContacts;
  final String attachmentRecipientLabel;
  final MessageInputAttachmentController? attachmentController;

  const MessageInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    this.inputPillHeight = WrytteVisualTokens.capsuleHeight,
    this.controlSize = WrytteVisualTokens.controlSize,
    this.controlGap = WrytteVisualTokens.controlGap,
    this.controlScale = 1,
    this.horizontalPadding = 12,
    this.replySender,
    this.replyPreview,
    this.onCancelReply,
    this.isEditing = false,
    this.onCancelEdit,
    this.editingMediaSource,
    this.editingMediaType,
    this.onReplaceEditingMedia,
    this.onVoiceMessage,
    this.onVideoMessage,
    this.onVideoMessageRecorded,
    this.onCameraAttachment,
    this.onGalleryAttachment,
    this.onFileAttachment,
    this.onPickedAttachment,
    this.onPickedAttachments,
    this.onPickedContacts,
    this.attachmentRecipientLabel = 'Recipient',
    this.attachmentController,
  });

  @override
  State<MessageInputField> createState() => _MessageInputFieldState();
}

class _MessageInputFieldState extends State<MessageInputField>
    with WidgetsBindingObserver {
  static const double _composerMainIconCanvas = 28.0;
  static const double _composerPlusOpticalScale = 0.86;
  static const double _microphoneOpticalScale = 1.0;
  static const double _sendOpticalScale = 1.12;
  static const double _videoOpticalScale = 0.96;
  double _observedKeyboardInset = 0;
  static const double _replyPreviewHeight = 50.0;
  static const double _mediaEditPreviewHeight = 56.0;
  static const List<int> _aacSampleRates = <int>[
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000,
    7350,
  ];

  // ph:video-camera-bold — Phosphor Icons, MIT.
  // ── flutter_sound recorder ─────────────────────────────────────────────────
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderReady = false;
  Future<void>? _recorderOpenAttempt;
  Timer? _recorderIdleTimer;
  int _recorderGeneration = 0;

  // ── Recording state ────────────────────────────────────────────────────────
  bool _isRecording = false;
  bool _cameraMode = false;
  bool _recordButtonPressed = false;
  bool _cancelRecordingOnRelease = false;
  double _cancelDragProgress = 0;
  double _cancelDragVisualDx = 0;
  double _cancelDragVisualDy = 0;
  double _recordLockProgress = 0;
  bool _recordGuideReached = false;
  bool _recordingLocked = false;
  bool _recordingPaused = false;
  bool _videoFinalizeInFlight = false;
  bool _videoMessagePreparing = false;
  bool _videoPointerReleasedWhilePreparing = false;
  bool _attachmentMenuOpen = false;
  int? _quickRecordPointer;
  Offset? _quickRecordOrigin;
  bool _quickLockRequested = false;
  static const double _quickLockSwipeDistance = 34;
  static const double _quickLockHorizontalTolerance = 30;
  double _recordingKeyboardInset = 0;
  bool _preserveKeyboardDuringRecording = false;
  bool _keyboardRestoreScheduled = false;
  int _keyboardRestoreAttempts = 0;
  Timer? _keyboardRestoreTimer;
  final GlobalKey _attachmentButtonKey = GlobalKey();
  final LayerLink _recordButtonLayerLink = LayerLink();
  OverlayEntry? _recordModeHintEntry;
  OverlayEntry? _recordLockGuideEntry;
  OverlayEntry? _videoMessagePreviewEntry;
  int _elapsedSeconds = 0;
  Timer? _timer;
  Timer? _waveformTimer;
  final Stopwatch _recordingStopwatch = Stopwatch();
  String? _recordingPath;
  StreamSubscription<RecordingDisposition>? _recorderProgressSubscription;
  final ValueNotifier<List<double>> _recordingLevelsNotifier =
      ValueNotifier<List<double>>(<double>[]);
  double _latestRecordingLevel = 0.02;
  double? _recordingNoiseFloorDb;
  double _recordingPeakDb = 60;
  int _voiceActivityFrames = 0;
  DateTime? _lastRecorderLevelAt;
  int _waveformSampleTick = 0;
  final AudioPlayer _recordingPreviewPlayer = AudioPlayer();
  StreamSubscription<Duration>? _previewPositionSubscription;
  StreamSubscription<void>? _previewCompleteSubscription;
  bool _isPreviewPlaying = false;
  bool _previewTimelineInteracting = false;
  bool _previewSeekInFlight = false;
  Duration _previewPosition = Duration.zero;
  Duration _pausedRecordingDuration = Duration.zero;
  double _trimStartFraction = 0;
  double _trimEndFraction = 1;

  // ── Telegram-style round video message state ──────────────────────────────
  static const int _maxVideoMessageSeconds = 60;
  static const double _roundVideoCoverBleed = 1.06;
  static const Duration _roundVideoWarmupFrameSkip = Duration.zero;
  static const double _roundVideoThumbnailCropScale = 1.08;
  CameraController? _videoMessageController;
  List<CameraDescription> _videoMessageCameras = <CameraDescription>[];
  int _videoMessageCameraIndex = 0;
  _VideoMessageCameraAccessState _videoMessageCameraAccessState =
      _VideoMessageCameraAccessState.idle;
  Completer<void>? _videoMessageCameraAttempt;
  Future<void> _videoMessageCameraOperationTail = Future<void>.value();
  int _videoMessageCameraGeneration = 0;
  bool _videoFlashEnabled = false;
  double _videoZoom = 1;
  double _videoZoomAtGestureStart = 1;
  double _videoMinZoom = 1;
  double _videoMaxZoom = 1;
  final SmoothCameraZoomController _videoZoomSmoother =
      SmoothCameraZoomController();
  String? _pausedVideoMessagePath;
  VideoPlayerController? _pausedVideoPreviewController;
  Future<void>? _pausedVideoPreviewAttempt;
  List<ImageProvider> _pausedVideoMessageThumbnails = const <ImageProvider>[];
  int _pausedVideoMessageGeneration = 0;
  bool _playPausedVideoWhenReady = false;
  bool _pausedVideoMuted = true;

  bool get _videoMessageCameraAccessBusy =>
      _videoMessageCameraAccessState ==
          _VideoMessageCameraAccessState.requestingPermission ||
      _videoMessageCameraAccessState == _VideoMessageCameraAccessState.opening;

  bool get _videoMessageHasFrontBackCameras =>
      _videoMessageCameras.any(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      ) &&
      _videoMessageCameras.any(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

  double get _roundVideoActiveThumbnailCropScale =>
      _roundVideoThumbnailCropScale;

  Future<T> _serializeVideoMessageCameraOperation<T>(
    Future<T> Function() operation,
  ) {
    final completer = Completer<T>();
    _videoMessageCameraOperationTail = _videoMessageCameraOperationTail
        .catchError((_) {})
        .then((_) async {
          try {
            completer.complete(await operation());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });
    return completer.future;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachAttachmentController();
    _previewPositionSubscription = _recordingPreviewPlayer.onPositionChanged
        .listen(_handlePreviewPosition);
    _previewCompleteSubscription = _recordingPreviewPlayer.onPlayerComplete
        .listen((_) => _finishPreviewPlayback());
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboardInset = _currentKeyboardInset();
    if (keyboardInset == _observedKeyboardInset) return;
    _observedKeyboardInset = keyboardInset;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant MessageInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentController != widget.attachmentController) {
      oldWidget.attachmentController?.detach();
      _attachAttachmentController();
    }
  }

  void _attachAttachmentController() {
    widget.attachmentController?.attach(
      openAudioPicker: _showAudioAttachmentMenu,
      openAudioPlaylistPicker: _showAudioPlaylistPicker,
    );
  }

  Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Temporary recorder cleanup must never block widget disposal/send flow.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.attachmentController?.detach();
    _removeRecordModeHint();
    _removeRecordLockGuide();
    _removeVideoMessagePreview();
    _timer?.cancel();
    _waveformTimer?.cancel();
    _recorderIdleTimer?.cancel();
    _keyboardRestoreTimer?.cancel();
    _recordingStopwatch.stop();
    final progressSubscription = _recorderProgressSubscription;
    if (progressSubscription != null) {
      unawaited(progressSubscription.cancel());
    }
    final previewPositionSubscription = _previewPositionSubscription;
    if (previewPositionSubscription != null) {
      unawaited(previewPositionSubscription.cancel());
    }
    final previewCompleteSubscription = _previewCompleteSubscription;
    if (previewCompleteSubscription != null) {
      unawaited(previewCompleteSubscription.cancel());
    }
    unawaited(_recordingPreviewPlayer.dispose());
    _videoZoomSmoother.dispose();
    _videoMessageCameraGeneration++;
    final videoMessageController = _videoMessageController;
    _videoMessageController = null;
    if (videoMessageController != null) {
      unawaited(
        _serializeVideoMessageCameraOperation(videoMessageController.dispose),
      );
    }
    final pausedVideoPreviewController = _pausedVideoPreviewController;
    _pausedVideoPreviewController = null;
    if (pausedVideoPreviewController != null) {
      pausedVideoPreviewController.removeListener(
        _syncPausedVideoPreviewPosition,
      );
      unawaited(pausedVideoPreviewController.dispose());
    }
    final pausedVideoMessagePath = _pausedVideoMessagePath;
    _pausedVideoMessagePath = null;
    if (pausedVideoMessagePath != null) {
      unawaited(_deleteFileIfExists(pausedVideoMessagePath));
    }
    _recorderGeneration++;
    unawaited(_recorder.closeRecorder());
    _recordingLevelsNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android temporarily pauses the activity while showing the first camera
    // or microphone permission sheet. Keep the preparing hold alive so the
    // granted gesture returns as a locked recording instead of being cancelled.
    if (state == AppLifecycleState.paused && _videoMessagePreparing) {
      _videoPointerReleasedWhilePreparing = true;
      return;
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    if (_isRecording) {
      unawaited(_cancelActiveRecording());
      return;
    }
    unawaited(_disposeVideoMessageCamera());
    unawaited(_closeRecorderWhenIdle());
  }

  Future<void> _showAudioAttachmentMenu() {
    return _showAttachmentMenu(initialAudioMode: true);
  }

  Future<List<ChatPickedAttachment>?> _showAudioPlaylistPicker() async {
    if (_attachmentMenuOpen || !mounted) return null;
    widget.focusNode.unfocus();
    setState(() => _attachmentMenuOpen = true);
    try {
      final selection = await showGeneralDialog<_AttachmentSelection>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.44),
        transitionDuration: _attachmentPanelTransitionDuration,
        pageBuilder: (dialogContext, animation, secondaryAnimation) => Material(
          color: Colors.transparent,
          child: _TelegramAttachmentPanel(
            recipientLabel: widget.attachmentRecipientLabel,
            initialAudioMode: true,
            playlistMode: true,
            onSelected: (selected) {
              unawaited(HapticFeedback.selectionClick());
              Navigator.of(dialogContext).pop(selected);
            },
          ),
        ),
        transitionBuilder: _attachmentPanelSlideTransition,
      );
      return selection?.media.isNotEmpty == true ? selection!.media : null;
    } finally {
      if (mounted) setState(() => _attachmentMenuOpen = false);
    }
  }

  void _removeRecordModeHint() {
    _recordModeHintEntry?.remove();
    _recordModeHintEntry = null;
  }

  void _showRecordLockGuide() {
    if (_recordLockGuideEntry != null) {
      _recordLockGuideEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        width: 42,
        child: CompositedTransformFollower(
          link: _recordButtonLayerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -22),
          child: Material(
            type: MaterialType.transparency,
            child: _buildRecordingLockGuide(),
          ),
        ),
      ),
    );
    _recordLockGuideEntry = entry;
    overlay.insert(entry);
  }

  void _refreshRecordLockGuide() {
    _recordLockGuideEntry?.markNeedsBuild();
  }

  void _removeRecordLockGuide() {
    _recordLockGuideEntry?.remove();
    _recordLockGuideEntry = null;
  }

  void _toggleRecordingMode() {
    if (_isRecording || _videoMessageCameraAccessBusy) return;
    unawaited(Feedback.forLongPress(context));
    setState(() => _cameraMode = !_cameraMode);
    if (!_cameraMode) {
      unawaited(_disposeVideoMessageCamera());
    }
    final visibleHint = _recordModeHintEntry;
    if (visibleHint != null) {
      visibleHint.markNeedsBuild();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRecordModeHint();
    });
  }

  void _showRecordModeHint() {
    if (_recordModeHintEntry != null) {
      _recordModeHintEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        width: 318,
        height: 42,
        child: CompositedTransformFollower(
          link: _recordButtonLayerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -6),
          child: _RecordingModeHint(
            message: _cameraMode
                ? 'Hold to record video  •  Tap to switch to audio'
                : 'Hold to record audio  •  Tap to switch to video',
            onDismissed: () {
              if (_recordModeHintEntry != entry) return;
              _recordModeHintEntry = null;
              entry.remove();
            },
          ),
        ),
      ),
    );
    _recordModeHintEntry = entry;
    overlay.insert(entry);
  }

  void _setRecordButtonPressed(bool pressed) {
    if (!mounted || _recordButtonPressed == pressed) return;
    setState(() => _recordButtonPressed = pressed);
  }

  void _handleRecordButtonLongPressDown() {
    _setRecordButtonPressed(true);
    if (_cameraMode) {
      // Pointer-down is also fired for a normal tap. Only warm already-granted
      // resources here; the recognized long press owns any system prompt.
      unawaited(_prepareVideoMessageCamera(requestIfNeeded: false));
    } else {
      _recorderIdleTimer?.cancel();
      unawaited(_ensureRecorderReady(requestIfNeeded: false));
    }
  }

  double _currentKeyboardInset() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 0;
    final view = views.first;
    final ratio = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    return view.viewInsets.bottom / ratio;
  }

  void _captureRecordingKeyboardState() {
    final inset = _currentKeyboardInset();
    if (inset <= 1) return;
    _recordingKeyboardInset = math.max(_recordingKeyboardInset, inset);
    _preserveKeyboardDuringRecording = true;
    _keyboardRestoreAttempts = 0;
  }

  void _scheduleRecordingKeyboardRestore() {
    if (_keyboardRestoreScheduled ||
        _keyboardRestoreAttempts >= 12 ||
        !_preserveKeyboardDuringRecording ||
        !mounted) {
      return;
    }
    _keyboardRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardRestoreScheduled = false;
      if (!mounted ||
          !_preserveKeyboardDuringRecording ||
          (!_isRecording && !_recordButtonPressed)) {
        return;
      }
      final needsRestore =
          !widget.focusNode.hasFocus ||
          _currentKeyboardInset() < _recordingKeyboardInset - 1;
      if (!needsRestore) {
        _keyboardRestoreAttempts = 0;
        _keyboardRestoreTimer?.cancel();
        _keyboardRestoreTimer = null;
        return;
      }
      if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
      _keyboardRestoreAttempts += 1;
      if (_keyboardRestoreAttempts < 12) {
        _keyboardRestoreTimer?.cancel();
        _keyboardRestoreTimer = Timer(const Duration(milliseconds: 80), () {
          if (mounted) _scheduleRecordingKeyboardRestore();
        });
      }
    });
  }

  void _finishRecordingKeyboardPreservation() {
    _keyboardRestoreTimer?.cancel();
    _keyboardRestoreTimer = null;
    _keyboardRestoreAttempts = 0;
    _keyboardRestoreScheduled = false;
    _recordingKeyboardInset = 0;
    _preserveKeyboardDuringRecording = false;
  }

  void _handleRecordPointerDown(PointerDownEvent event) {
    if (_quickRecordPointer != null || _isRecording) return;
    _quickRecordPointer = event.pointer;
    _quickRecordOrigin = event.position;
    _quickLockRequested = false;
    _captureRecordingKeyboardState();

    // Warm only already-granted native resources. Any permission prompt still
    // belongs to the committed recording gesture.
    if (_cameraMode) {
      unawaited(_prepareVideoMessageCamera(requestIfNeeded: false));
    } else {
      _recorderIdleTimer?.cancel();
      unawaited(_ensureRecorderReady(requestIfNeeded: false));
    }
  }

  void _handleRecordPointerMove(PointerMoveEvent event) {
    if (_quickRecordPointer != event.pointer || _quickLockRequested) return;
    final origin = _quickRecordOrigin;
    if (origin == null) return;
    final delta = event.position - origin;
    if (delta.dy > -_quickLockSwipeDistance ||
        delta.dx.abs() > _quickLockHorizontalTolerance) {
      return;
    }

    _quickLockRequested = true;
    _removeRecordModeHint();
    _setRecordButtonPressed(true);
    unawaited(Feedback.forLongPress(context));
    unawaited(_startQuickLockedRecording());
  }

  void _handleRecordPointerUp(PointerEvent event) {
    if (_quickRecordPointer != event.pointer) return;
    _quickRecordPointer = null;
    _quickRecordOrigin = null;
  }

  Future<void> _startQuickLockedRecording() async {
    if (_cameraMode) {
      await _startVideoMessageRecording();
    } else {
      await _startRecording();
    }
    if (!mounted) return;
    if (_isRecording) {
      setState(() {
        _recordingLocked = true;
        _recordGuideReached = true;
        _recordButtonPressed = false;
        _cancelRecordingOnRelease = false;
        _cancelDragProgress = 0;
        _cancelDragVisualDx = 0;
        _cancelDragVisualDy = 0;
        _recordLockProgress = 1;
        _quickLockRequested = false;
      });
      _refreshRecordLockGuide();
      _scheduleRecordingKeyboardRestore();
      return;
    }
    _quickLockRequested = false;
    _setRecordButtonPressed(false);
    _finishRecordingKeyboardPreservation();
  }

  // ── Telegram-style round video message camera ─────────────────────────────
  Future<bool> _prepareVideoMessageCamera({bool requestIfNeeded = true}) async {
    return _serializeVideoMessageCameraOperation(
      () => _prepareVideoMessageCameraNow(requestIfNeeded: requestIfNeeded),
    );
  }

  Future<bool> _prepareVideoMessageCameraNow({
    required bool requestIfNeeded,
  }) async {
    final existing = _videoMessageController;
    if (existing?.value.isInitialized == true) return true;

    if (_videoMessageCameraAccessState ==
            _VideoMessageCameraAccessState.requestingPermission ||
        _videoMessageCameraAccessState ==
            _VideoMessageCameraAccessState.opening) {
      await _videoMessageCameraAttempt?.future;
      if (_videoMessageController?.value.isInitialized == true) return true;
      if (!requestIfNeeded) return false;
    }

    final attempt = Completer<void>();
    _videoMessageCameraAttempt = attempt;
    final generation = _videoMessageCameraGeneration;
    try {
      if (mounted) {
        setState(() {
          _videoMessageCameraAccessState =
              _VideoMessageCameraAccessState.requestingPermission;
        });
      }
      final cameraGranted = await AppPermissionService.instance
          .ensureCameraGranted(requestIfNeeded: requestIfNeeded);
      if (!cameraGranted) {
        if (mounted) {
          setState(() {
            _videoMessageCameraAccessState = requestIfNeeded
                ? _VideoMessageCameraAccessState.denied
                : _VideoMessageCameraAccessState.idle;
          });
        }
        return false;
      }

      final microphoneGranted = await AppPermissionService.instance
          .ensureMicrophoneGranted(requestIfNeeded: requestIfNeeded);
      if (!microphoneGranted) {
        if (mounted) {
          setState(() {
            _videoMessageCameraAccessState = requestIfNeeded
                ? _VideoMessageCameraAccessState.denied
                : _VideoMessageCameraAccessState.idle;
          });
        }
        return false;
      }

      if (mounted) {
        setState(() {
          _videoMessageCameraAccessState =
              _VideoMessageCameraAccessState.opening;
        });
      }

      final cameras = await CameraInventoryService.instance.load();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _videoMessageCameraAccessState =
                _VideoMessageCameraAccessState.unavailable;
          });
        }
        return false;
      }

      final preferredCamera = preferredCameraForDirection(
        cameras,
        CameraLensDirection.front,
      );
      var cameraIndex = cameras.indexWhere(
        (camera) => camera.name == preferredCamera?.name,
      );
      if (cameraIndex < 0) cameraIndex = 0;

      final controller = CameraController(
        cameras[cameraIndex],
        ResolutionPreset.medium,
        enableAudio: true,
        fps: 24,
        videoBitrate: 1800000,
        audioBitrate: 64000,
      );
      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (error) {
        debugPrint('Round-video orientation lock failed: $error');
      }
      try {
        await controller.prepareForVideoRecording();
      } catch (_) {
        // Some platform camera implementations do not need an explicit warmup.
      }

      final reportedMinZoom = await controller.getMinZoomLevel();
      final reportedMaxZoom = await controller.getMaxZoomLevel();
      final minZoom = reportedMinZoom.isFinite && reportedMinZoom > 0
          ? reportedMinZoom
          : 1.0;
      final maxZoom = reportedMaxZoom.isFinite && reportedMaxZoom >= minZoom
          ? reportedMaxZoom
          : minZoom;
      final initialZoom = 1.0.clamp(minZoom, maxZoom).toDouble();
      CameraInventoryService.instance.rememberZoomRange(
        cameras[cameraIndex],
        minZoom,
        maxZoom,
      );
      await controller.setZoomLevel(initialZoom);
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Front cameras and some emulators do not expose flash controls.
      }

      if (!mounted ||
          !_cameraMode ||
          generation != _videoMessageCameraGeneration) {
        await controller.dispose();
        if (mounted) {
          setState(() {
            _videoMessageCameraAccessState =
                _VideoMessageCameraAccessState.idle;
          });
        }
        return false;
      }

      final oldController = _videoMessageController;
      _videoZoomSmoother.cancel();
      setState(() {
        _videoMessageCameras = cameras;
        _videoMessageCameraIndex = cameraIndex;
        _videoMessageController = controller;
        _videoFlashEnabled = false;
        _videoMinZoom = minZoom;
        _videoMaxZoom = maxZoom;
        _videoZoom = initialZoom;
        _videoZoomAtGestureStart = initialZoom;
        _videoMessageCameraAccessState = _VideoMessageCameraAccessState.ready;
      });
      if (oldController != null && !identical(oldController, controller)) {
        await oldController.dispose();
      }
      return true;
    } catch (error) {
      debugPrint('Round video message camera could not start: $error');
      if (mounted) {
        setState(() {
          _videoMessageCameraAccessState =
              _VideoMessageCameraAccessState.unavailable;
        });
      }
      return false;
    } finally {
      if (!attempt.isCompleted) attempt.complete();
      if (identical(_videoMessageCameraAttempt, attempt)) {
        _videoMessageCameraAttempt = null;
      }
    }
  }

  Future<void> _disposeVideoMessageCamera() async {
    if (_isRecording && _cameraMode) return;
    _videoMessageCameraGeneration++;
    return _serializeVideoMessageCameraOperation(_disposeVideoMessageCameraNow);
  }

  Future<void> _disposeVideoMessageCameraNow() async {
    _videoZoomSmoother.cancel();
    final controller = _videoMessageController;
    _videoMessageController = null;
    _videoFlashEnabled = false;
    _videoMessageCameraAccessState = _VideoMessageCameraAccessState.idle;
    if (mounted) setState(() {});
    if (controller != null) await controller.dispose();
  }

  Future<void> _startVideoMessageRecording() async {
    if (_isRecording) return;
    _videoMessagePreparing = true;
    _videoPointerReleasedWhilePreparing = false;
    _captureRecordingKeyboardState();
    if (_preserveKeyboardDuringRecording) {
      if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      _scheduleRecordingKeyboardRestore();
    }
    _elapsedSeconds = 0;
    _cancelRecordingOnRelease = false;
    _cancelDragProgress = 0;
    _cancelDragVisualDx = 0;
    _cancelDragVisualDy = 0;
    _recordLockProgress = 0;
    _recordGuideReached = false;
    _recordingLocked = false;
    _recordingPaused = false;
    _recordingLevelsNotifier.value = <double>[];
    _pausedRecordingDuration = Duration.zero;
    _pausedVideoMessagePath = null;
    _pausedVideoMessageThumbnails = const <ImageProvider>[];
    _playPausedVideoWhenReady = false;
    _pausedVideoMuted = true;
    _previewPosition = Duration.zero;
    _isPreviewPlaying = false;
    _trimStartFraction = 0;
    _trimEndFraction = 1;
    _recordingStopwatch.reset();
    if (mounted) {
      setState(() => _isRecording = true);
      _showRecordLockGuide();
      _showVideoMessagePreview();
    }
    try {
      final ready = await _prepareVideoMessageCamera();
      if (!mounted) return;
      if (!_cameraMode) {
        _videoMessagePreparing = false;
        _removeRecordLockGuide();
        _removeVideoMessagePreview();
        setState(() {
          _isRecording = false;
          _recordButtonPressed = false;
          _recordingLocked = false;
          _recordingPaused = false;
        });
        await _disposeVideoMessageCamera();
        return;
      }
      if (!_recordButtonPressed && !_videoPointerReleasedWhilePreparing) {
        _videoMessagePreparing = false;
        if (_isRecording) {
          await _cancelVideoRecording();
        } else {
          await _disposeVideoMessageCamera();
        }
        return;
      }
      if (!ready) {
        _videoMessagePreparing = false;
        _removeRecordLockGuide();
        _removeVideoMessagePreview();
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordButtonPressed = false;
            _recordingLocked = false;
            _recordingPaused = false;
          });
        }
        await _disposeVideoMessageCamera();
        return;
      }

      final controller = _videoMessageController;
      if (controller == null || !controller.value.isInitialized) {
        _videoMessagePreparing = false;
        _removeRecordLockGuide();
        _removeVideoMessagePreview();
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordButtonPressed = false;
            _recordingLocked = false;
            _recordingPaused = false;
          });
        }
        await _disposeVideoMessageCamera();
        return;
      }

      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (error) {
        debugPrint('Round-video pre-record orientation lock failed: $error');
      }
      await _serializeVideoMessageCameraOperation(
        controller.startVideoRecording,
      );

      final lockAfterPermission = _videoPointerReleasedWhilePreparing;
      _videoMessagePreparing = false;
      _videoPointerReleasedWhilePreparing = false;

      if (lockAfterPermission && mounted) {
        setState(() {
          _recordingLocked = true;
          _recordGuideReached = true;
          _recordButtonPressed = false;
          _cancelRecordingOnRelease = false;
          _recordLockProgress = 1;
        });
        _refreshRecordLockGuide();
      }

      // Camera initialization can finish after the user has already released.
      // In that case immediately discard the just-started native recording.
      if (!mounted || (!_recordButtonPressed && !lockAfterPermission)) {
        final file = await _serializeVideoMessageCameraOperation(
          controller.stopVideoRecording,
        );
        final discarded = File(file.path);
        if (await discarded.exists()) await discarded.delete();
        if (mounted) {
          if (_isRecording) {
            await _cancelVideoRecording();
          } else {
            await _disposeVideoMessageCamera();
          }
        }
        return;
      }

      _recordingStopwatch
        ..reset()
        ..start();
      if (mounted) setState(() {});
      _startRecordingTimers();
      _refreshRecordLockGuide();
      _refreshVideoMessagePreview();
      _scheduleRecordingKeyboardRestore();
    } catch (error) {
      _videoMessagePreparing = false;
      _videoPointerReleasedWhilePreparing = false;
      debugPrint('Round video message recording failed to start: $error');
      _removeRecordLockGuide();
      _removeVideoMessagePreview();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordButtonPressed = false;
          _recordingLocked = false;
          _recordingPaused = false;
        });
      }
      await _disposeVideoMessageCamera();
      _finishRecordingKeyboardPreservation();
    }
  }

  Future<void> _stopVideoRecordingAndSend() async {
    if (!_isRecording || !_cameraMode || _videoFinalizeInFlight) return;
    if (_recordingPaused && _pausedVideoMessagePath == null) return;
    if (_cancelRecordingOnRelease) {
      await _cancelVideoRecording();
      return;
    }

    _videoFinalizeInFlight = true;
    try {
      _timer?.cancel();
      _waveformTimer?.cancel();
      _recordingStopwatch.stop();
      final recordedDuration = _recordingStopwatch.elapsed;
      final pausedVideoPath = _pausedVideoMessagePath;
      final controller = _videoMessageController;
      XFile? videoFile;
      Size? previewSize;

      if (pausedVideoPath != null) {
        videoFile = XFile(pausedVideoPath);
      } else if (controller != null && controller.value.isInitialized) {
        previewSize = controller.value.previewSize;
        if (controller.value.isRecordingVideo) {
          try {
            videoFile = await _serializeVideoMessageCameraOperation(
              controller.stopVideoRecording,
            );
          } catch (error) {
            debugPrint('Round video message could not stop cleanly: $error');
          }
        }
      }

      final wasPaused = _recordingPaused;
      final sourceDuration =
          wasPaused && _pausedRecordingDuration > Duration.zero
          ? _pausedRecordingDuration
          : recordedDuration;
      final trimStart = wasPaused
          ? _safePausedVideoStartPosition()
          : _trimStartDuration;
      final trimEnd = _trimEndDuration;
      if (wasPaused) {
        await _disposePausedVideoPreview();
      }

      _removeRecordLockGuide();
      _removeVideoMessagePreview();
      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _cancelRecordingOnRelease = false;
        _recordButtonPressed = false;
        _cancelDragProgress = 0;
        _cancelDragVisualDx = 0;
        _cancelDragVisualDy = 0;
        _recordLockProgress = 0;
        _recordGuideReached = false;
        _recordingLocked = false;
        _recordingPaused = false;
        _pausedVideoMessagePath = null;
        _pausedVideoMessageThumbnails = const <ImageProvider>[];
        _playPausedVideoWhenReady = false;
        _elapsedSeconds = 0;
      });
      _recordingStopwatch.reset();
      await _disposeVideoMessageCamera();
      _finishRecordingKeyboardPreservation();

      if (videoFile == null) return;
      final file = File(videoFile.path);
      if (sourceDuration.inMilliseconds < 1000) {
        if (await file.exists()) await file.delete();
        return;
      }
      if (!await file.exists()) return;

      var outgoingPath = videoFile.path;
      var outgoingDuration = sourceDuration;
      if (wasPaused &&
          trimEnd > trimStart &&
          (trimStart > Duration.zero || trimEnd < sourceDuration)) {
        try {
          outgoingPath = await _trimVideoRecording(
            path: videoFile.path,
            start: trimStart,
            end: trimEnd,
          );
          outgoingDuration = trimEnd - trimStart;
          if (outgoingPath != videoFile.path) {
            final original = File(videoFile.path);
            if (await original.exists()) await original.delete();
          }
        } catch (error) {
          debugPrint('Round video message could not be trimmed: $error');
          outgoingPath = videoFile.path;
          outgoingDuration = recordedDuration;
        }
      }

      final durationSeconds = math.max(
        1,
        (outgoingDuration.inMilliseconds / 1000).ceil(),
      );

      final videoHandler = widget.onVideoMessageRecorded;
      if (videoHandler != null) {
        await videoHandler(outgoingPath, durationSeconds);
        return;
      }

      // If the caller has not added the dedicated round-video callback yet,
      // route the file through the existing attachment sender using a distinct
      // type so the message bubble can render it as a circle.
      final pickedAttachment = widget.onPickedAttachment;
      if (pickedAttachment != null) {
        await pickedAttachment(
          outgoingPath,
          'video_message',
          mediaWidth: previewSize?.width.round(),
          mediaHeight: previewSize?.height.round(),
        );
      }
    } finally {
      _videoFinalizeInFlight = false;
    }
  }

  Future<void> _cancelVideoRecording() async {
    if (!_isRecording || !_cameraMode || _videoFinalizeInFlight) return;
    _videoFinalizeInFlight = true;
    try {
      _timer?.cancel();
      _waveformTimer?.cancel();
      _recordingStopwatch
        ..stop()
        ..reset();
      _removeRecordLockGuide();
      _removeVideoMessagePreview();

      final controller = _videoMessageController;
      final pausedVideoPath = _pausedVideoMessagePath;

      // Match the new recorder: remove the recording UI on the tap frame.
      // Native camera finalization/disposal can continue underneath instead of
      // holding the visible composer open until stopVideoRecording completes.
      if (mounted) {
        setState(() {
          _isRecording = false;
          _cancelRecordingOnRelease = false;
          _recordButtonPressed = false;
          _cancelDragProgress = 0;
          _cancelDragVisualDx = 0;
          _cancelDragVisualDy = 0;
          _recordLockProgress = 0;
          _recordGuideReached = false;
          _recordingLocked = false;
          _recordingPaused = false;
          _pausedVideoMessagePath = null;
          _pausedVideoMessageThumbnails = const <ImageProvider>[];
          _playPausedVideoWhenReady = false;
          _elapsedSeconds = 0;
        });
      }

      XFile? discardedFile;
      if (controller != null && controller.value.isRecordingVideo) {
        try {
          discardedFile = await _serializeVideoMessageCameraOperation(
            controller.stopVideoRecording,
          );
        } catch (_) {
          // The native camera may already have stopped while the gesture ended.
        }
      }

      await _disposePausedVideoPreview();

      await _disposeVideoMessageCamera();
      if (pausedVideoPath != null) {
        await _deleteFileIfExists(pausedVideoPath);
      }
      if (discardedFile != null) {
        final file = File(discardedFile.path);
        if (await file.exists()) await file.delete();
      }
    } finally {
      _videoFinalizeInFlight = false;
    }
  }

  Future<void> _pauseLockedVideoRecording() async {
    if (!_isRecording ||
        !_cameraMode ||
        !_recordingLocked ||
        _recordingPaused) {
      return;
    }
    final controller = _videoMessageController;
    if (controller == null || !controller.value.isRecordingVideo) return;

    _timer?.cancel();
    _recordingStopwatch.stop();
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
    final pausedDuration =
        _recordingStopwatch.elapsed < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : _recordingStopwatch.elapsed;
    final generation = ++_pausedVideoMessageGeneration;
    setState(() {
      _recordingPaused = true;
      _pausedRecordingDuration = pausedDuration;
      _pausedVideoMessagePath = null;
      _pausedVideoMessageThumbnails = const <ImageProvider>[];
      _playPausedVideoWhenReady = false;
      _previewPosition = Duration.zero;
      _isPreviewPlaying = false;
      _trimStartFraction = 0;
      _trimEndFraction = 1;
    });
    _refreshRecordLockGuide();
    _refreshVideoMessagePreview();
    unawaited(_finishPausedVideoRecording(controller, generation));
  }

  Future<void> _finishPausedVideoRecording(
    CameraController controller,
    int generation,
  ) async {
    try {
      final pausedFile = await _serializeVideoMessageCameraOperation(
        controller.stopVideoRecording,
      );
      final finalizedFile = File(pausedFile.path);
      final finalizedBytes = await finalizedFile.exists()
          ? await finalizedFile.length()
          : 0;
      debugPrint(
        'Round-video pause finalized: generation=$generation bytes=$finalizedBytes',
      );
      if (!mounted ||
          !_recordingPaused ||
          generation != _pausedVideoMessageGeneration) {
        await _deleteFileIfExists(pausedFile.path);
        return;
      }
      setState(() => _pausedVideoMessagePath = pausedFile.path);
      _refreshVideoMessagePreview();
      unawaited(
        _preparePausedVideoAssets(pausedFile.path, generation: generation),
      );
    } catch (error) {
      debugPrint('Round-video pause finalize failed: $error');
      if (mounted &&
          _recordingPaused &&
          generation == _pausedVideoMessageGeneration) {
        _refreshVideoMessagePreview();
      }
    }
  }

  Future<void> _resumeLockedVideoRecording() async {
    if (!_isRecording ||
        !_cameraMode ||
        !_recordingLocked ||
        !_recordingPaused) {
      return;
    }
    final controller = _videoMessageController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_pausedVideoMessagePath == null) return;

    final pausedPath = _pausedVideoMessagePath;
    if (pausedPath != null) {
      await _disposePausedVideoPreview();
      await _deleteFileIfExists(pausedPath);
    }
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (error) {
      debugPrint('Round-video resume orientation lock failed: $error');
    }
    await _serializeVideoMessageCameraOperation(controller.startVideoRecording);
    _recordingStopwatch.start();
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _recordingPaused = false;
      _pausedVideoMessagePath = null;
      _pausedVideoMessageThumbnails = const <ImageProvider>[];
      _playPausedVideoWhenReady = false;
      _previewPosition = Duration.zero;
      _isPreviewPlaying = false;
      _pausedRecordingDuration = Duration.zero;
      _trimStartFraction = 0;
      _trimEndFraction = 1;
    });
    _refreshRecordLockGuide();
    _refreshVideoMessagePreview();
    _startRecordingTimers();
  }

  Future<void> _disposePausedVideoPreview() async {
    final controller = _pausedVideoPreviewController;
    _pausedVideoPreviewController = null;
    if (controller == null) return;
    controller.removeListener(_syncPausedVideoPreviewPosition);
    try {
      await controller.pause();
    } catch (_) {}
    await controller.dispose();
  }

  Future<void> _preparePausedVideoPreview(
    String path, {
    required int generation,
  }) async {
    final activeAttempt = _pausedVideoPreviewAttempt;
    if (activeAttempt != null) {
      await activeAttempt;
      if (_pausedVideoMessagePath == path &&
          _pausedVideoPreviewController?.value.isInitialized == true) {
        return;
      }
    }

    final attempt = _preparePausedVideoPreviewInternal(
      path,
      generation: generation,
    );
    _pausedVideoPreviewAttempt = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_pausedVideoPreviewAttempt, attempt)) {
        _pausedVideoPreviewAttempt = null;
      }
    }
  }

  Future<void> _preparePausedVideoPreviewInternal(
    String path, {
    required int generation,
  }) async {
    await _disposePausedVideoPreview();
    final controller = VideoPlayerController.file(File(path));
    _pausedVideoPreviewController = controller;
    controller.addListener(_syncPausedVideoPreviewPosition);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_pausedVideoMuted ? 0 : 1);
      if (!mounted ||
          generation != _pausedVideoMessageGeneration ||
          _pausedVideoMessagePath != path) {
        controller.removeListener(_syncPausedVideoPreviewPosition);
        await controller.dispose();
        if (identical(_pausedVideoPreviewController, controller)) {
          _pausedVideoPreviewController = null;
        }
        return;
      }
      final encodedDuration = controller.value.duration;
      if (encodedDuration > Duration.zero) {
        _pausedRecordingDuration = encodedDuration;
      }
      final previewStart = _safePausedVideoStartPosition();
      await controller.seekTo(previewStart);
      _playPausedVideoWhenReady = false;
      await controller.play();
      setState(() {
        _previewPosition = previewStart;
        _isPreviewPlaying = controller.value.isPlaying;
      });
      _refreshVideoMessagePreview();
    } catch (error) {
      debugPrint('Round-video paused preview could not load: $error');
      if (identical(_pausedVideoPreviewController, controller)) {
        _pausedVideoPreviewController = null;
      }
      controller.removeListener(_syncPausedVideoPreviewPosition);
      await controller.dispose();
    }
  }

  Future<void> _preparePausedVideoAssets(
    String path, {
    required int generation,
  }) async {
    await _waitForReadableVideoFile(path);
    if (!mounted ||
        generation != _pausedVideoMessageGeneration ||
        _pausedVideoMessagePath != path) {
      return;
    }
    unawaited(_loadPausedVideoInitialThumbnail(path, generation: generation));
    unawaited(_loadPausedVideoMessageThumbnails(path, generation: generation));
    await _preparePausedVideoPreview(path, generation: generation);
    if (!mounted ||
        generation != _pausedVideoMessageGeneration ||
        _pausedVideoMessagePath != path) {
      return;
    }
  }

  Future<void> _waitForReadableVideoFile(String path) async {
    var previousLength = -1;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final length = await file.length();
          if (length > 0 && length == previousLength) return;
          previousLength = length;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }
  }

  Duration _safePausedVideoStartPosition() {
    final total = _pausedVideoTimelineDuration;
    final trimStart = _trimStartDuration;
    if (total <= _roundVideoWarmupFrameSkip) return trimStart;
    final trimEnd = _trimEndDuration;
    final candidate = trimStart < _roundVideoWarmupFrameSkip
        ? _roundVideoWarmupFrameSkip
        : trimStart;
    if (trimEnd > trimStart && candidate < trimEnd) return candidate;
    return trimStart;
  }

  void _syncPausedVideoPreviewPosition() {
    if (!_cameraMode || !_recordingPaused) return;
    final controller = _pausedVideoPreviewController;
    if (controller == null || !controller.value.isInitialized) return;
    final position = controller.value.position;
    final end = _trimEndDuration;
    if (controller.value.isPlaying && end > Duration.zero && position >= end) {
      final resetPosition = _safePausedVideoStartPosition();
      unawaited(
        controller.seekTo(resetPosition).then((_) {
          if (_cameraMode &&
              _recordingPaused &&
              identical(_pausedVideoPreviewController, controller)) {
            return controller.play();
          }
        }),
      );
      if (mounted) {
        setState(() {
          _isPreviewPlaying = true;
          _previewPosition = resetPosition;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _isPreviewPlaying = controller.value.isPlaying;
      _previewPosition = position;
    });
  }

  Future<void> _togglePausedVideoPreview() async {
    if (!_cameraMode || !_recordingPaused) return;
    var controller = _pausedVideoPreviewController;
    var waitedForPreview = false;
    if (controller == null || !controller.value.isInitialized) {
      final path = _pausedVideoMessagePath;
      _playPausedVideoWhenReady = true;
      if (path == null) return;
      waitedForPreview = true;
      await _preparePausedVideoPreview(
        path,
        generation: _pausedVideoMessageGeneration,
      );
      controller = _pausedVideoPreviewController;
    }
    if (controller == null || !controller.value.isInitialized) return;
    if (waitedForPreview && controller.value.isPlaying) {
      if (mounted) setState(() => _isPreviewPlaying = true);
      _refreshVideoMessagePreview();
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) {
        setState(() => _isPreviewPlaying = false);
        _refreshVideoMessagePreview();
      }
      return;
    }
    var position = _previewPosition;
    if (position < _trimStartDuration || position >= _trimEndDuration) {
      position = _safePausedVideoStartPosition();
    }
    _playPausedVideoWhenReady = false;
    await controller.seekTo(position);
    await controller.play();
    if (mounted) {
      setState(() {
        _previewPosition = position;
        _isPreviewPlaying = true;
      });
      _refreshVideoMessagePreview();
    }
  }

  Future<void> _seekPausedVideoPreview(Duration position) async {
    final controller = _pausedVideoPreviewController;
    final lowerBound = _safePausedVideoStartPosition();
    final safePosition = Duration(
      microseconds: position.inMicroseconds
          .clamp(lowerBound.inMicroseconds, _trimEndDuration.inMicroseconds)
          .toInt(),
    );
    if (mounted) setState(() => _previewPosition = safePosition);
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(safePosition);
  }

  Future<void> _loadPausedVideoMessageThumbnails(
    String path, {
    required int generation,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final frameCount = (screenWidth / 42).ceil().clamp(7, 12).toInt();
      final frameWidth = math.max(
        56.0,
        (screenWidth / frameCount) * devicePixelRatio,
      );
      final frameHeight = math.max(56.0, 40.0 * devicePixelRatio);
      final frames = await pve.ProVideoEditor.instance.getKeyFrames(
        pve.KeyFramesConfigs(
          video: pve.EditorVideo.file(path),
          outputSize: Size(frameWidth, frameHeight),
          boxFit: pve.ThumbnailBoxFit.cover,
          maxOutputFrames: frameCount,
          outputFormat: pve.ThumbnailFormat.jpeg,
        ),
      );
      final thumbnails = frames
          .map<ImageProvider>(MemoryImage.new)
          .toList(growable: false);
      if (!mounted ||
          generation != _pausedVideoMessageGeneration ||
          _pausedVideoMessagePath != path ||
          thumbnails.isEmpty) {
        return;
      }
      debugPrint(
        'Round-video keyframes loaded: count=${thumbnails.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      setState(() => _pausedVideoMessageThumbnails = thumbnails);
    } catch (error) {
      debugPrint('Round-video keyframe thumbnails could not load: $error');
      final fallback = await _loadPausedVideoThumbnailFallback(
        path: path,
        duration: _pausedVideoTimelineDuration,
        frameCount: 9,
        maxWidth: 0,
        maxHeight: 160,
      );
      if (!mounted ||
          generation != _pausedVideoMessageGeneration ||
          _pausedVideoMessagePath != path ||
          fallback.isEmpty) {
        debugPrint(
          'Round-video fallback thumbnails empty: elapsed=${stopwatch.elapsedMilliseconds}ms',
        );
        return;
      }
      debugPrint(
        'Round-video fallback thumbnails loaded: count=${fallback.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      setState(() => _pausedVideoMessageThumbnails = fallback);
    }
  }

  Future<void> _loadPausedVideoInitialThumbnail(
    String path, {
    required int generation,
  }) async {
    try {
      final bytes = await video_thumbnail.VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: video_thumbnail.ImageFormat.JPEG,
        timeMs: _firstUsableVideoThumbnailMs(_pausedVideoTimelineDuration),
        maxWidth: 0,
        maxHeight: 160,
        quality: 72,
      );
      if (bytes == null || bytes.isEmpty) return;
      if (!mounted ||
          generation != _pausedVideoMessageGeneration ||
          _pausedVideoMessagePath != path ||
          _pausedVideoMessageThumbnails.isNotEmpty) {
        return;
      }
      setState(() {
        _pausedVideoMessageThumbnails = List<ImageProvider>.filled(
          5,
          MemoryImage(bytes),
          growable: false,
        );
      });
    } catch (_) {
      // The full keyframe loader/fallback below will still try.
    }
  }

  Future<List<ImageProvider>> _loadPausedVideoThumbnailFallback({
    required String path,
    required Duration duration,
    required int frameCount,
    required int maxWidth,
    required int maxHeight,
  }) async {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return const <ImageProvider>[];
    final startMs = _firstUsableVideoThumbnailMs(duration);
    final sampleRangeMs = math.max(0, totalMs - startMs);
    final frameTasks = <Future<ImageProvider?>>[];
    for (var index = 0; index < frameCount; index++) {
      final fraction = frameCount <= 1
          ? 0.0
          : index / math.max(1, frameCount - 1);
      final timeMs = (startMs + (sampleRangeMs * fraction).round())
          .clamp(0, totalMs)
          .toInt();
      frameTasks.add(
        video_thumbnail.VideoThumbnail.thumbnailData(
          video: path,
          imageFormat: video_thumbnail.ImageFormat.JPEG,
          timeMs: timeMs,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          quality: 76,
        ).then<ImageProvider?>(
          (bytes) => bytes == null || bytes.isEmpty ? null : MemoryImage(bytes),
          onError: (_) => null,
        ),
      );
    }
    final frames = await Future.wait(frameTasks);
    return frames.whereType<ImageProvider>().toList(growable: false);
  }

  int _firstUsableVideoThumbnailMs(Duration duration) {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= _roundVideoWarmupFrameSkip.inMilliseconds) return 0;
    return _roundVideoWarmupFrameSkip.inMilliseconds.clamp(0, totalMs).toInt();
  }

  Future<void> _switchVideoMessageCamera() async {
    return _serializeVideoMessageCameraOperation(_switchVideoMessageCameraNow);
  }

  Future<void> _switchVideoMessageCameraNow() async {
    final controller = _videoMessageController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _videoMessageCameras.length < 2) {
      return;
    }

    final currentDirection = controller.description.lensDirection;
    final targetDirection = currentDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final preferredCamera = preferredCameraForDirection(
      _videoMessageCameras,
      targetDirection,
    );
    var nextIndex = _videoMessageCameras.indexWhere(
      (camera) => camera.name == preferredCamera?.name,
    );

    // Some devices expose external/extra cameras in addition to front/back.
    // If the exact opposite lens is unavailable, fall back to the first camera
    // whose direction differs from the current one.
    if (nextIndex < 0) {
      nextIndex = _videoMessageCameras.indexWhere(
        (camera) => camera.lensDirection != currentDirection,
      );
    }
    if (nextIndex < 0 || nextIndex == _videoMessageCameraIndex) return;

    try {
      if (_videoFlashEnabled) {
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {
          // The active camera may not expose a flash control.
        }
      }

      _videoZoomSmoother.cancel();
      await controller.setDescription(_videoMessageCameras[nextIndex]);
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (error) {
        debugPrint('Round-video orientation lock after switch failed: $error');
      }

      final reportedMinZoom = await controller.getMinZoomLevel();
      final reportedMaxZoom = await controller.getMaxZoomLevel();
      final minZoom = reportedMinZoom.isFinite && reportedMinZoom > 0
          ? reportedMinZoom
          : 1.0;
      final maxZoom = reportedMaxZoom.isFinite && reportedMaxZoom >= minZoom
          ? reportedMaxZoom
          : minZoom;
      final initialZoom = 1.0.clamp(minZoom, maxZoom).toDouble();
      CameraInventoryService.instance.rememberZoomRange(
        _videoMessageCameras[nextIndex],
        minZoom,
        maxZoom,
      );
      await controller.setZoomLevel(initialZoom);
      if (!mounted) return;

      unawaited(HapticFeedback.selectionClick());
      setState(() {
        _videoMessageCameraIndex = nextIndex;
        _videoFlashEnabled = false;
        _videoMinZoom = minZoom;
        _videoMaxZoom = maxZoom;
        _videoZoom = initialZoom;
        _videoZoomAtGestureStart = initialZoom;
      });
      _refreshVideoMessagePreview();
    } catch (error) {
      debugPrint('Could not switch round-video camera: $error');
    }
  }

  Future<void> _toggleVideoFlash() async {
    return _serializeVideoMessageCameraOperation(_toggleVideoFlashNow);
  }

  Future<void> _toggleVideoFlashNow() async {
    final controller = _videoMessageController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.description.lensDirection == CameraLensDirection.front) {
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    final enableFlash = !_videoFlashEnabled;
    try {
      await controller.setFlashMode(
        enableFlash ? FlashMode.torch : FlashMode.off,
      );
      if (!mounted) return;
      unawaited(HapticFeedback.selectionClick());
      setState(() => _videoFlashEnabled = enableFlash);
      _refreshVideoMessagePreview();
    } catch (error) {
      debugPrint('Round-video flash is unavailable: $error');
    }
  }

  void _handleVideoPreviewScaleStart(ScaleStartDetails details) {
    _videoZoomSmoother.cancel();
    _videoZoomAtGestureStart = _videoZoom;
  }

  void _handleVideoPreviewScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    final controller = _videoMessageController;
    if (controller == null || !controller.value.isInitialized) return;
    final nextZoom = (_videoZoomAtGestureStart * details.scale)
        .clamp(_videoMinZoom, _videoMaxZoom)
        .toDouble();
    _videoZoomSmoother.setZoom(
      controller,
      nextZoom,
      onApplied: (appliedZoom) {
        if (!mounted || !identical(_videoMessageController, controller)) {
          return;
        }
        _videoZoom = appliedZoom;
      },
    );
  }

  Future<void> _stopActiveRecordingAndSend() =>
      _cameraMode ? _stopVideoRecordingAndSend() : _stopRecordingAndSend();

  Future<void> _cancelActiveRecording() =>
      _cameraMode ? _cancelVideoRecording() : _cancelRecording();

  Future<void> _pauseActiveLockedRecording() =>
      _cameraMode ? _pauseLockedVideoRecording() : _pauseLockedRecording();

  Future<void> _resumeActiveLockedRecording() =>
      _cameraMode ? _resumeLockedVideoRecording() : _resumeLockedRecording();

  // ── Lazy recorder initialization ──────────────────────────────────────────
  Future<bool> _ensureRecorderReady({bool requestIfNeeded = true}) async {
    if (_recorderReady) return true;
    final activeAttempt = _recorderOpenAttempt;
    if (activeAttempt != null) {
      await activeAttempt;
      if (_recorderReady || !requestIfNeeded) return _recorderReady;
    }

    late final Future<void> attempt;
    attempt = _openRecorderOnDemand(requestIfNeeded: requestIfNeeded);
    _recorderOpenAttempt = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_recorderOpenAttempt, attempt)) {
        _recorderOpenAttempt = null;
      }
    }
    return _recorderReady;
  }

  Future<void> _openRecorderOnDemand({required bool requestIfNeeded}) async {
    final generation = _recorderGeneration;
    final microphoneGranted = await AppPermissionService.instance
        .ensureMicrophoneGranted(requestIfNeeded: requestIfNeeded);
    if (!mounted || generation != _recorderGeneration || !microphoneGranted) {
      return;
    }

    try {
      await _recorder.openRecorder();
      if (!mounted || generation != _recorderGeneration) {
        await _recorder.closeRecorder();
        return;
      }
      // Ten level samples per second are visually smooth for the 8 Hz
      // waveform while avoiding needless platform-channel traffic at idle.
      try {
        await _recorder.setSubscriptionDuration(
          const Duration(milliseconds: 100),
        );
      } catch (_) {
        // Recording remains available when a platform has no level callbacks.
      }
      await _recorderProgressSubscription?.cancel();
      _recorderProgressSubscription = _recorder.onProgress?.listen(
        _handleRecorderProgress,
      );
      if (mounted) setState(() => _recorderReady = true);
    } catch (error) {
      debugPrint('Voice recorder could not start: $error');
      if (mounted) setState(() => _recorderReady = false);
    }
  }

  void _scheduleRecorderRelease() {
    _recorderIdleTimer?.cancel();
    if (!_recorderReady || _isRecording) return;
    _recorderIdleTimer = Timer(
      const Duration(seconds: 30),
      () => unawaited(_closeRecorderWhenIdle()),
    );
  }

  Future<void> _closeRecorderWhenIdle() async {
    if (_isRecording) return;
    _recorderIdleTimer?.cancel();
    _recorderGeneration++;
    final opening = _recorderOpenAttempt;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {}
    }
    if (_isRecording) return;
    await _recorderProgressSubscription?.cancel();
    _recorderProgressSubscription = null;
    try {
      await _recorder.closeRecorder();
    } catch (_) {
      // The native recorder may already be closed by an app lifecycle change.
    }
    if (mounted && _recorderReady) {
      setState(() => _recorderReady = false);
    } else {
      _recorderReady = false;
    }
  }

  void _handleRecorderProgress(RecordingDisposition disposition) {
    if (!mounted || !_isRecording || _recordingPaused) return;

    final rawDecibels = disposition.decibels;
    var normalizedLevel = 0.02;
    if (rawDecibels != null && rawDecibels.isFinite) {
      final meterDecibels = (rawDecibels < 0 ? rawDecibels + 60 : rawDecibels)
          .clamp(0.0, 120.0)
          .toDouble();
      var noiseFloor = _recordingNoiseFloorDb;
      if (noiseFloor == null) {
        noiseFloor = meterDecibels;
        _recordingPeakDb = (meterDecibels + 28).clamp(24.0, 120.0);
      } else if (meterDecibels < noiseFloor) {
        noiseFloor = (noiseFloor * 0.68) + (meterDecibels * 0.32);
      } else if (meterDecibels <= noiseFloor + 6) {
        noiseFloor = (noiseFloor * 0.94) + (meterDecibels * 0.06);
      }
      _recordingNoiseFloorDb = noiseFloor;
      _recordingPeakDb = math.max(
        meterDecibels,
        math.max(noiseFloor + 22, _recordingPeakDb - 0.18),
      );

      final audibleFloor = noiseFloor + 3.5;
      final relativeStrength =
          ((meterDecibels - audibleFloor) /
                  math.max(22, _recordingPeakDb - audibleFloor))
              .clamp(0.0, 1.0)
              .toDouble();
      if (relativeStrength >= 0.10) {
        _voiceActivityFrames = math.min(4, _voiceActivityFrames + 1);
      } else {
        _voiceActivityFrames = math.max(0, _voiceActivityFrames - 1);
      }
      normalizedLevel = _voiceActivityFrames < 2 || relativeStrength <= 0.04
          ? 0.02
          : 0.02 + (0.98 * math.pow(relativeStrength, 0.72).toDouble());
      _lastRecorderLevelAt = DateTime.now();
    } else {
      _voiceActivityFrames = math.max(0, _voiceActivityFrames - 1);
    }
    final response = normalizedLevel > _latestRecordingLevel ? 0.75 : 0.24;
    _latestRecordingLevel =
        ((_latestRecordingLevel * (1 - response)) +
                (normalizedLevel * response))
            .clamp(0.02, 1.0)
            .toDouble();
  }

  void _appendWaveformSample() {
    if (!mounted || !_isRecording || _recordingPaused) return;

    const voiceVariation = <double>[
      0.88,
      1.06,
      0.94,
      1.12,
      0.90,
      1.02,
      1.09,
      0.96,
    ];
    final lastLevelAt = _lastRecorderLevelAt;
    final hasFreshLevel =
        lastLevelAt != null &&
        DateTime.now().difference(lastLevelAt) <
            const Duration(milliseconds: 280);
    final hasConfirmedVoice = hasFreshLevel && _voiceActivityFrames >= 2;
    final patternIndex = _waveformSampleTick % voiceVariation.length;
    final nextLevel =
        (hasConfirmedVoice
                ? _latestRecordingLevel * voiceVariation[patternIndex]
                : 0.02)
            .clamp(0.02, 1.0)
            .toDouble();
    final nextLevels = List<double>.of(_recordingLevelsNotifier.value)
      ..add(nextLevel);
    // Keep enough samples for a full one-hour voice note. Dropping samples from
    // the front makes the rendered waveform stop matching the recording time.
    if (nextLevels.length > 28800) nextLevels.removeAt(0);

    _waveformSampleTick++;
    _recordingLevelsNotifier.value = nextLevels;
  }

  // ── Start recording ────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_isRecording) return;
    _captureRecordingKeyboardState();
    if (_preserveKeyboardDuringRecording) {
      if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      _scheduleRecordingKeyboardRestore();
    }
    _recorderIdleTimer?.cancel();
    final recorderReady = await _ensureRecorderReady();
    if (!mounted || !recorderReady || !_recordButtonPressed || _isRecording) {
      _scheduleRecorderRelease();
      if (mounted && !_isRecording) {
        _finishRecordingKeyboardPreservation();
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

    await _recorder.startRecorder(toFile: _recordingPath, codec: Codec.aacADTS);

    if (!mounted) {
      await _recorder.stopRecorder();
      return;
    }

    _elapsedSeconds = 0;
    _cancelRecordingOnRelease = false;
    _cancelDragProgress = 0;
    _cancelDragVisualDx = 0;
    _cancelDragVisualDy = 0;
    _recordLockProgress = 0;
    _recordGuideReached = false;
    _recordingLocked = false;
    _recordingPaused = false;
    _isPreviewPlaying = false;
    _previewPosition = Duration.zero;
    _pausedRecordingDuration = Duration.zero;
    _trimStartFraction = 0;
    _trimEndFraction = 1;
    _recordingLevelsNotifier.value = <double>[];
    _latestRecordingLevel = 0.02;
    _recordingNoiseFloorDb = null;
    _recordingPeakDb = 60;
    _voiceActivityFrames = 0;
    _lastRecorderLevelAt = null;
    _waveformSampleTick = 0;
    _recordingStopwatch
      ..reset()
      ..start();
    setState(() => _isRecording = true);
    _startRecordingTimers();
    _showRecordLockGuide();
    _scheduleRecordingKeyboardRestore();
  }

  void _startRecordingTimers() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_isRecording || _recordingPaused) return;
      final elapsedSeconds = _recordingStopwatch.elapsed.inSeconds;

      if (_cameraMode) {
        // Rebuild at 10 fps so the circular progress ring moves smoothly.
        setState(() => _elapsedSeconds = elapsedSeconds);
        _refreshVideoMessagePreview();
        if (elapsedSeconds >= _maxVideoMessageSeconds) {
          unawaited(_stopVideoRecordingAndSend());
        }
        return;
      }

      if (elapsedSeconds != _elapsedSeconds) {
        setState(() => _elapsedSeconds = elapsedSeconds);
      }
    });

    _waveformTimer?.cancel();
    if (!_cameraMode) {
      _waveformTimer = Timer.periodic(
        const Duration(milliseconds: 125),
        (_) => _appendWaveformSample(),
      );
    }
  }

  Duration _durationAtFraction(double fraction) {
    final totalMicros = _pausedRecordingDuration.inMicroseconds;
    return Duration(
      microseconds: (totalMicros * fraction.clamp(0.0, 1.0)).round(),
    );
  }

  Duration get _pausedVideoTimelineDuration {
    final controller = _pausedVideoPreviewController;
    if (controller != null && controller.value.isInitialized) {
      final videoDuration = controller.value.duration;
      if (videoDuration > Duration.zero) return videoDuration;
    }
    return _pausedRecordingDuration;
  }

  Duration get _trimStartDuration => _durationAtFraction(_trimStartFraction);

  Duration get _trimEndDuration => _durationAtFraction(_trimEndFraction);

  Duration get _trimmedDuration {
    final duration = _trimEndDuration - _trimStartDuration;
    return duration.isNegative ? Duration.zero : duration;
  }

  Future<void> _pauseLockedRecording() async {
    if (!_isRecording || !_recordingLocked || _recordingPaused) return;
    await _recorder.pauseRecorder();
    _timer?.cancel();
    _waveformTimer?.cancel();
    _recordingStopwatch.stop();
    var encodedDuration = _recordingStopwatch.elapsed;
    final path = _recordingPath;
    if (path != null) {
      final measuredDuration = await _readAdtsDuration(path);
      if (measuredDuration != null && measuredDuration > Duration.zero) {
        encodedDuration = measuredDuration;
      }
    }
    if (!mounted) return;

    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _recordingPaused = true;
      _pausedRecordingDuration = encodedDuration;
      _previewPosition = Duration.zero;
      _isPreviewPlaying = false;
      _trimStartFraction = 0;
      _trimEndFraction = 1;
    });
    _refreshRecordLockGuide();
  }

  Future<Duration?> _readAdtsDuration(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    var cursor = 0;
    var elapsedMicros = 0.0;
    var frameCount = 0;
    while (cursor + 7 <= bytes.length) {
      final hasSync =
          bytes[cursor] == 0xFF && (bytes[cursor + 1] & 0xF0) == 0xF0;
      if (!hasSync) {
        cursor++;
        continue;
      }
      final sampleRateIndex = (bytes[cursor + 2] >> 2) & 0x0F;
      final frameLength =
          ((bytes[cursor + 3] & 0x03) << 11) |
          (bytes[cursor + 4] << 3) |
          ((bytes[cursor + 5] & 0xE0) >> 5);
      if (sampleRateIndex >= _aacSampleRates.length ||
          frameLength < 7 ||
          cursor + frameLength > bytes.length) {
        cursor++;
        continue;
      }
      final rawDataBlocks = bytes[cursor + 6] & 0x03;
      elapsedMicros +=
          (1024.0 * (rawDataBlocks + 1) * Duration.microsecondsPerSecond) /
          _aacSampleRates[sampleRateIndex];
      frameCount++;
      cursor += frameLength;
    }
    if (frameCount == 0) return null;
    return Duration(microseconds: elapsedMicros.round());
  }

  Future<void> _resumeLockedRecording() async {
    if (!_isRecording || !_recordingLocked || !_recordingPaused) return;
    await _stopPreviewPlayback();
    try {
      await _recordingPreviewPlayer.release();
    } catch (_) {
      // Recorder resume remains available if preview release already happened.
    }
    await _recorder.resumeRecorder();
    if (!mounted) return;

    _recordingStopwatch.start();
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _recordingPaused = false;
      _previewPosition = Duration.zero;
      _isPreviewPlaying = false;
      _trimStartFraction = 0;
      _trimEndFraction = 1;
    });
    _refreshRecordLockGuide();
    _startRecordingTimers();
  }

  void _handlePreviewPosition(Duration position) {
    if (!mounted ||
        !_recordingPaused ||
        !_isPreviewPlaying ||
        _previewTimelineInteracting ||
        _previewSeekInFlight) {
      return;
    }
    if (position >= _trimEndDuration) {
      unawaited(_stopPreviewPlayback(resetToTrimStart: true));
      return;
    }
    setState(() => _previewPosition = position);
  }

  void _finishPreviewPlayback() {
    unawaited(_stopPreviewPlayback(resetToTrimStart: true));
  }

  Future<void> _stopPreviewPlayback({bool resetToTrimStart = false}) async {
    try {
      await _recordingPreviewPlayer.stop();
    } catch (_) {
      // The preview may already have been released by the native player.
    }
    if (!mounted) return;
    setState(() {
      _isPreviewPlaying = false;
      if (resetToTrimStart) _previewPosition = _trimStartDuration;
    });
  }

  Future<void> _togglePreviewPlayback() async {
    if (!_recordingPaused || _recordingPath == null) return;
    if (_isPreviewPlaying) {
      await _recordingPreviewPlayer.pause();
      if (mounted) setState(() => _isPreviewPlaying = false);
      return;
    }

    final start = _trimStartDuration;
    final end = _trimEndDuration;
    var position = _previewPosition;
    if (position < start || position >= end) position = start;
    try {
      await _recordingPreviewPlayer.play(
        DeviceFileSource(_recordingPath!),
        position: position,
      );
      if (!mounted) return;
      setState(() {
        _previewPosition = position;
        _isPreviewPlaying = true;
      });
    } catch (_) {
      if (mounted) setState(() => _isPreviewPlaying = false);
    }
  }

  void _updateTrimRange(double start, double end) {
    if (!_recordingPaused) return;
    final totalMs = math.max(1, _pausedRecordingDuration.inMilliseconds);
    final minimumRange = (750 / totalMs).clamp(0.04, 1.0).toDouble();
    final safeStart = start.clamp(0.0, 1.0 - minimumRange).toDouble();
    final safeEnd = end.clamp(safeStart + minimumRange, 1.0).toDouble();
    final previewOutsideRange =
        _previewPosition < _durationAtFraction(safeStart) ||
        _previewPosition >= _durationAtFraction(safeEnd);
    setState(() {
      _trimStartFraction = safeStart;
      _trimEndFraction = safeEnd;
      if (previewOutsideRange) {
        _previewPosition = _trimStartDuration;
      }
    });
    if (_isPreviewPlaying && previewOutsideRange) {
      unawaited(_stopPreviewPlayback(resetToTrimStart: true));
    }
  }

  void _updateVideoTrimRange(double start, double end) {
    if (!_recordingPaused || !_cameraMode) return;
    final totalMs = math.max(1, _pausedRecordingDuration.inMilliseconds);
    final minimumRange = (750 / totalMs).clamp(0.04, 1.0).toDouble();
    final safeStart = start.clamp(0.0, 1.0 - minimumRange).toDouble();
    final safeEnd = end.clamp(safeStart + minimumRange, 1.0).toDouble();
    final nextStart = _durationAtFraction(safeStart);
    final nextEnd = _durationAtFraction(safeEnd);
    final nextPreviewStart =
        nextStart < _roundVideoWarmupFrameSkip &&
            _pausedVideoTimelineDuration > _roundVideoWarmupFrameSkip &&
            nextEnd > _roundVideoWarmupFrameSkip
        ? _roundVideoWarmupFrameSkip
        : nextStart;
    final previewOutsideRange =
        _previewPosition < nextStart || _previewPosition >= nextEnd;
    setState(() {
      _trimStartFraction = safeStart;
      _trimEndFraction = safeEnd;
      if (previewOutsideRange) {
        _previewPosition = nextPreviewStart;
      }
    });
    if (previewOutsideRange) {
      unawaited(_seekPausedVideoPreview(nextStart));
    }
  }

  void _setPreviewTimelineInteraction(bool interacting) {
    _previewTimelineInteracting = interacting;
  }

  void _seekPreviewToFraction(double fraction, bool commit) {
    if (!_recordingPaused) return;
    final safeFraction = fraction
        .clamp(_trimStartFraction, _trimEndFraction)
        .toDouble();
    final position = _durationAtFraction(safeFraction);
    if (mounted) {
      setState(() => _previewPosition = position);
    }
    if (commit && _isPreviewPlaying) {
      _previewSeekInFlight = true;
      unawaited(_commitPreviewSeek(position));
    }
  }

  Future<void> _commitPreviewSeek(Duration position) async {
    try {
      await _recordingPreviewPlayer.seek(position);
    } catch (_) {
      // The preview may have been stopped while the drag was completing.
    } finally {
      _previewSeekInFlight = false;
    }
  }

  // ── Stop recording and send ────────────────────────────────────────────────
  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    if (_cancelRecordingOnRelease) {
      await _cancelRecording();
      return;
    }

    final wasPaused = _recordingPaused;
    final trimStart = _trimStartDuration;
    final trimEnd = _trimEndDuration;
    if (_isPreviewPlaying) {
      await _stopPreviewPlayback();
    }
    _timer?.cancel();
    _waveformTimer?.cancel();
    _recordingStopwatch.stop();
    final path = _recordingPath;
    var recordedDuration = _recordingStopwatch.elapsed;
    await _recorder.stopRecorder();
    if (path != null) {
      final encodedDuration = await _readAdtsDuration(path);
      if (encodedDuration != null && encodedDuration > Duration.zero) {
        recordedDuration = encodedDuration;
      }
    }
    _removeRecordLockGuide();

    if (!mounted) {
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      return;
    }

    setState(() {
      _isRecording = false;
      _cancelRecordingOnRelease = false;
      _recordButtonPressed = false;
      _cancelDragProgress = 0;
      _cancelDragVisualDx = 0;
      _cancelDragVisualDy = 0;
      _recordLockProgress = 0;
      _recordGuideReached = false;
      _recordingLocked = false;
      _recordingPaused = false;
      _isPreviewPlaying = false;
      _previewPosition = Duration.zero;
      _pausedRecordingDuration = Duration.zero;
      _trimStartFraction = 0;
      _trimEndFraction = 1;
      _elapsedSeconds = 0;
      _recordingPath = null;
    });
    _recordingStopwatch.reset();
    _scheduleRecorderRelease();
    _finishRecordingKeyboardPreservation();

    // Discard recordings under 1 second (accidental taps)
    if (path == null || recordedDuration.inMilliseconds < 1000) return;

    // Verify the file actually exists before handing it off
    if (!await File(path).exists()) return;

    var outgoingPath = path;
    var outgoingDuration = recordedDuration;
    if (wasPaused &&
        (trimStart > Duration.zero || trimEnd < recordedDuration)) {
      final trimmed = await _trimAdtsRecording(
        path: path,
        start: trimStart,
        end: trimEnd,
        fallbackDuration: recordedDuration,
      );
      outgoingPath = trimmed.path;
      outgoingDuration = trimmed.duration;
      if (outgoingPath != path) {
        final original = File(path);
        if (await original.exists()) await original.delete();
      }
    }

    final durationSeconds = math.max(
      1,
      (outgoingDuration.inMilliseconds / 1000).ceil(),
    );
    await widget.onVoiceMessage?.call(outgoingPath, durationSeconds);
  }

  Future<({String path, Duration duration})> _trimAdtsRecording({
    required String path,
    required Duration start,
    required Duration end,
    required Duration fallbackDuration,
  }) async {
    final source = File(path);
    final bytes = await source.readAsBytes();
    final output = BytesBuilder(copy: false);
    final startMicros = start.inMicroseconds;
    final endMicros = end.inMicroseconds;
    var elapsedMicros = 0.0;
    var selectedMicros = 0.0;
    var cursor = 0;

    while (cursor + 7 <= bytes.length) {
      final hasSync =
          bytes[cursor] == 0xFF && (bytes[cursor + 1] & 0xF0) == 0xF0;
      if (!hasSync) {
        cursor++;
        continue;
      }

      final sampleRateIndex = (bytes[cursor + 2] >> 2) & 0x0F;
      final frameLength =
          ((bytes[cursor + 3] & 0x03) << 11) |
          (bytes[cursor + 4] << 3) |
          ((bytes[cursor + 5] & 0xE0) >> 5);
      if (sampleRateIndex >= _aacSampleRates.length ||
          frameLength < 7 ||
          cursor + frameLength > bytes.length) {
        cursor++;
        continue;
      }

      final rawDataBlocks = bytes[cursor + 6] & 0x03;
      final frameMicros =
          (1024.0 * (rawDataBlocks + 1) * Duration.microsecondsPerSecond) /
          _aacSampleRates[sampleRateIndex];
      final frameStart = elapsedMicros;
      final frameEnd = frameStart + frameMicros;
      final frameMidpoint = (frameStart + frameEnd) / 2;
      if (frameMidpoint >= startMicros && frameMidpoint < endMicros) {
        output.add(Uint8List.sublistView(bytes, cursor, cursor + frameLength));
        selectedMicros += frameMicros;
      }
      elapsedMicros = frameEnd;
      cursor += frameLength;
      if (frameStart >= endMicros) break;
    }

    if (output.length == 0) {
      return (path: path, duration: fallbackDuration);
    }

    final extensionIndex = path.lastIndexOf('.');
    final base = extensionIndex > 0 ? path.substring(0, extensionIndex) : path;
    final trimmedPath =
        '${base}_trim_${DateTime.now().millisecondsSinceEpoch}.aac';
    await File(trimmedPath).writeAsBytes(output.takeBytes(), flush: true);
    return (
      path: trimmedPath,
      duration: Duration(microseconds: selectedMicros.round()),
    );
  }

  Future<String> _trimVideoRecording({
    required String path,
    required Duration start,
    required Duration end,
  }) async {
    final source = pve.EditorVideo.file(path);
    final metadata = await pve.ProVideoEditor.instance.getMetadata(source);
    final directory = await getTemporaryDirectory();
    final outPath =
        '${directory.path}${Platform.pathSeparator}wrytte_video_msg_trim_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final trimmed = await pve.ProVideoEditor.instance.renderVideoToFile(
      outPath,
      pve.VideoRenderData(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        videoSegments: [pve.VideoSegment(video: source)],
        startTime: start,
        endTime: end,
        enableAudio: true,
        outputFormat: pve.VideoOutputFormat.mp4,
        bitrate: metadata.bitrate,
      ),
    );
    return trimmed;
  }

  // ── Cancel recording (swipe-to-cancel hook — extend here if needed) ────────
  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    final path = _recordingPath;
    if (_isPreviewPlaying) {
      await _stopPreviewPlayback();
    }
    _timer?.cancel();
    _waveformTimer?.cancel();
    _recordingStopwatch
      ..stop()
      ..reset();
    _removeRecordLockGuide();

    setState(() {
      _isRecording = false;
      _cancelRecordingOnRelease = false;
      _recordButtonPressed = false;
      _cancelDragProgress = 0;
      _cancelDragVisualDx = 0;
      _cancelDragVisualDy = 0;
      _recordLockProgress = 0;
      _recordGuideReached = false;
      _recordingLocked = false;
      _recordingPaused = false;
      _isPreviewPlaying = false;
      _previewPosition = Duration.zero;
      _pausedRecordingDuration = Duration.zero;
      _trimStartFraction = 0;
      _trimEndFraction = 1;
      _elapsedSeconds = 0;
      _recordingPath = null;
    });

    await _recorder.stopRecorder();
    _scheduleRecorderRelease();
    _finishRecordingKeyboardPreservation();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  void _handleRecordMove(LongPressMoveUpdateDetails details) {
    if (!_isRecording || _recordingLocked) return;
    final rawDx = details.offsetFromOrigin.dx;
    final rawDy = details.offsetFromOrigin.dy;
    final horizontalDistance = rawDx.abs();
    final leftDistance = (-rawDx).clamp(0.0, double.infinity).toDouble();
    final upwardDistance = (-rawDy).clamp(0.0, double.infinity).toDouble();
    final downwardDistance = rawDy.clamp(0.0, double.infinity).toDouble();
    final horizontalCancelProgress = (leftDistance / _recordCancelDistance)
        .clamp(0.0, 1.0)
        .toDouble();
    final lockCorridorWidth = (_recordCancelDistance * 0.16)
        .clamp(16.0, 23.0)
        .toDouble();
    final lockAllowed =
        horizontalCancelProgress < 0.30 &&
        rawDy < 0 &&
        horizontalDistance <= lockCorridorWidth;
    final isTopLeftDiagonal =
        rawDx < -14 &&
        rawDy < -12 &&
        !lockAllowed &&
        leftDistance >= upwardDistance * 0.55;
    final diagonalDistance = Offset(leftDistance, upwardDistance).distance;
    final diagonalCancelLimit = _recordCancelDistance * 0.78;
    final diagonalCancelProgress = isTopLeftDiagonal
        ? (diagonalDistance / diagonalCancelLimit).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final isUpperDiagonal =
        upwardDistance > 8 && horizontalDistance > lockCorridorWidth;
    const lowerCancelDistance = 28.0;
    final isInLowerCancelSector = rawDy > 0 && rawDx <= 10;
    final lowerCancelProgressRaw = isInLowerCancelSector
        ? Offset(
            leftDistance / _recordCancelDistance,
            downwardDistance / lowerCancelDistance,
          ).distance
        : 0.0;
    final lowerCancelProgress = lowerCancelProgressRaw
        .clamp(0.0, 1.0)
        .toDouble();
    final cancelProgress =
        (rawDy > 0
                ? lowerCancelProgress
                : isUpperDiagonal
                ? diagonalCancelProgress
                : horizontalCancelProgress)
            .toDouble();
    final lockProgress = lockAllowed
        ? (upwardDistance / 76).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final guideReached = lockAllowed && lockProgress >= 0.98;
    final diagonalEndpointFactor =
        isTopLeftDiagonal && diagonalDistance > diagonalCancelLimit
        ? diagonalCancelLimit / diagonalDistance
        : 1.0;
    final lowerEndpointFactor = lowerCancelProgressRaw > 1
        ? 1 / lowerCancelProgressRaw
        : 1.0;
    final endpointFactor = rawDy > 0
        ? lowerEndpointFactor
        : diagonalEndpointFactor;
    final visualDx = (leftDistance * endpointFactor)
        .clamp(0.0, _recordCancelDistance)
        .toDouble();
    final visualDy = lockAllowed
        ? -(19.5 * lockProgress)
        : (rawDy * endpointFactor).clamp(-22.0, 24.0).toDouble();

    if (cancelProgress >= 1) {
      unawaited(HapticFeedback.mediumImpact());
      unawaited(_cancelActiveRecording());
      return;
    }

    if (guideReached) {
      unawaited(Feedback.forLongPress(context));
      setState(() {
        _recordingLocked = true;
        _recordGuideReached = true;
        _recordButtonPressed = false;
        _cancelRecordingOnRelease = false;
        _cancelDragProgress = 0;
        _cancelDragVisualDx = 0;
        _cancelDragVisualDy = 0;
        _recordLockProgress = 1;
      });
      _refreshRecordLockGuide();
      _refreshVideoMessagePreview();
      return;
    }

    final cancelOnRelease = cancelProgress >= 0.55;
    if (cancelOnRelease != _cancelRecordingOnRelease) {
      unawaited(HapticFeedback.selectionClick());
    }
    setState(() {
      _cancelRecordingOnRelease = cancelOnRelease;
      _cancelDragProgress = cancelProgress;
      _cancelDragVisualDx = visualDx;
      _cancelDragVisualDy = visualDy;
      _recordLockProgress = lockProgress;
      _recordGuideReached = guideReached;
    });
    _refreshRecordLockGuide();
    _refreshVideoMessagePreview();
  }

  void _handleRecordingButtonTap() {
    if (_isRecording) {
      if (_recordingLocked) {
        unawaited(_stopActiveRecordingAndSend());
      }
      return;
    }
    _toggleRecordingMode();
  }

  // ── Format mm:ss for the recording timer ───────────────────────────────────
  String get _timerLabel {
    final m = (_elapsedSeconds ~/ 60).toString();
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _recordCancelDistance {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 132;
    final view = views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    return (logicalWidth * 0.32).clamp(0.0, 132.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        final hasReply =
            widget.replySender?.trim().isNotEmpty == true ||
            widget.replyPreview?.trim().isNotEmpty == true;
        final hasContextPreview = hasReply || widget.isEditing;
        final isMediaEditing =
            widget.isEditing &&
            widget.editingMediaSource?.trim().isNotEmpty == true;
        final contextPreviewHeight = isMediaEditing
            ? _mediaEditPreviewHeight
            : _replyPreviewHeight;
        final isComposerActive =
            widget.focusNode.hasFocus || hasText || hasContextPreview;
        final showExpressMessage = !_isRecording && !isComposerActive;
        final composerPillHeight =
            widget.inputPillHeight +
            (hasContextPreview ? contextPreviewHeight : 0);
        final pillRadius = widget.inputPillHeight / 2;
        final keyboardInset = _currentKeyboardInset();
        _observedKeyboardInset = keyboardInset;
        final bottomFloatGap = keyboardInset > 0
            ? 0.0
            : (MediaQuery.viewPaddingOf(context).bottom > 0 ? 10.0 : 12.0);

        return Container(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            // As soon as the IME starts moving, its inset is the composer
            // boundary. Keeping the nav-bar safe area here leaves a visible
            // gap until the keyboard has risen past that area.
            bottom: keyboardInset <= 0,
            minimum: EdgeInsets.only(bottom: bottomFloatGap),
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.horizontalPadding,
                right: widget.horizontalPadding,
                top: 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ── Attachment ──────────────────────────────────────────
                  IgnorePointer(
                    ignoring:
                        isMediaEditing || (_isRecording && !_recordingLocked),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        end:
                            isMediaEditing ||
                                (_isRecording && !_recordingLocked)
                            ? 0
                            : 1,
                      ),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      builder: (context, visibility, child) => ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: visibility,
                          child: Opacity(
                            opacity: visibility,
                            child: Transform.translate(
                              offset: Offset(-14 * (1 - visibility), 0),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _glassPill(
                            key: _attachmentButtonKey,
                            width: widget.controlSize,
                            height: widget.controlSize,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedOpacity(
                                  opacity: _recordingLocked ? 0 : 1,
                                  duration: const Duration(milliseconds: 200),
                                  child: AnimatedScale(
                                    scale: _recordingLocked ? 0.68 : 1,
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedRotation(
                                      turns: _attachmentMenuOpen ? 0.125 : 0,
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      child: wrytteSvgAssetIcon(
                                        assetPath:
                                            'assets/svg/Plus add icon new .svg',
                                        canvas:
                                            _composerMainIconCanvas *
                                            widget.controlScale,
                                        scale: _composerPlusOpticalScale,
                                      ),
                                    ),
                                  ),
                                ),
                                AnimatedOpacity(
                                  opacity: _recordingLocked ? 1 : 0,
                                  duration: const Duration(milliseconds: 230),
                                  child: AnimatedScale(
                                    scale: _recordingLocked ? 1 : 0.68,
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutBack,
                                    child: wrytteSvgAssetIcon(
                                      assetPath: 'assets/svg/Delete icon.svg',
                                      canvas: 22 * widget.controlScale,
                                      scale: 1.04,
                                      color: WrytteColors.destructive,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            onTap: _recordingLocked
                                ? () {
                                    unawaited(HapticFeedback.mediumImpact());
                                    unawaited(_cancelActiveRecording());
                                  }
                                : _showAttachmentMenu,
                          ),
                          SizedBox(width: widget.controlGap),
                        ],
                      ),
                    ),
                  ),

                  // ── Text field (hidden while recording) ─────────────────
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      reverseDuration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) =>
                          currentChild ?? const SizedBox.shrink(),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.96,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _isRecording
                          ? KeyedSubtree(
                              key: ValueKey(
                                _cameraMode
                                    ? 'video-recording-indicator'
                                    : 'audio-recording-indicator',
                              ),
                              child: SizedBox(
                                height: widget.inputPillHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: 0,
                                      right: -49,
                                      top: 0,
                                      bottom: 0,
                                      child: _buildRecordingIndicator(),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ClipRRect(
                              key: const ValueKey('message-composer-pill'),
                              borderRadius: BorderRadius.circular(pillRadius),
                              child: _wrapComposerBackdrop(
                                keyboardInset: keyboardInset,
                                child: AnimatedSize(
                                  key: const ValueKey('message-input-pill'),
                                  duration: const Duration(milliseconds: 210),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.bottomCenter,
                                  clipBehavior: Clip.hardEdge,
                                  child: Container(
                                    height: composerPillHeight,
                                    decoration: wrytteGlassDecoration(
                                      radius: pillRadius,
                                    ),
                                    padding: const EdgeInsets.only(
                                      left: 16,
                                      right: 8,
                                    ),
                                    child: Column(
                                      children: [
                                        if (hasContextPreview)
                                          SizedBox(
                                            height: contextPreviewHeight,
                                            child: _buildContextPreview(),
                                          ),
                                        Expanded(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: widget.controller,
                                                  focusNode: widget.focusNode,
                                                  maxLines: null,
                                                  minLines: 1,
                                                  keyboardType:
                                                      TextInputType.multiline,
                                                  textInputAction:
                                                      TextInputAction.newline,
                                                  textAlignVertical:
                                                      TextAlignVertical.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    height: 1.4,
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                  decoration:
                                                      InputDecoration.collapsed(
                                                        hintText: isMediaEditing
                                                            ? 'Add caption'
                                                            : 'Message',
                                                        hintStyle: TextStyle(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.45,
                                                              ),
                                                          fontSize: 18,
                                                        ),
                                                      ),
                                                ),
                                              ),

                                              // ── Express Message SVG ─────────────
                                              GestureDetector(
                                                onTap: () {},
                                                child: SizedBox(
                                                  width:
                                                      36 * widget.controlScale,
                                                  height:
                                                      36 * widget.controlScale,
                                                  child: Center(
                                                    child: wrytteSvgAssetIcon(
                                                      assetPath:
                                                          'assets/svg/mage--round-sticker.svg',
                                                      canvas:
                                                          WrytteVisualTokens
                                                              .inlineIconCanvas *
                                                          widget.controlScale,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.46,
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
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: widget.controlGap),

                  // ── Express Message pill ────────────────────────────────
                  IgnorePointer(
                    ignoring: !showExpressMessage,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: showExpressMessage ? 1 : 0),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      builder: (context, visibility, child) {
                        return ClipRect(
                          child: Align(
                            alignment: Alignment.centerRight,
                            widthFactor: visibility,
                            child: Opacity(opacity: visibility, child: child),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _glassPill(
                            width: widget.controlSize,
                            height: widget.controlSize,
                            child: wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Express chat icon.svg',
                              canvas: 30.5 * widget.controlScale,
                              scale: 1.0,
                            ),
                            onTap: () {},
                          ),
                          SizedBox(width: widget.controlGap),
                        ],
                      ),
                    ),
                  ),

                  // ── Send / mic button ───────────────────────────────────
                  (hasText || widget.isEditing)
                      ? GestureDetector(
                          onTap: widget.isEditing || hasText
                              ? widget.onSend
                              : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(pillRadius),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: widget.inputPillHeight,
                              height: widget.inputPillHeight,
                              decoration: BoxDecoration(
                                color: WrytteColors.primary,
                                borderRadius: BorderRadius.circular(pillRadius),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF4DA3FF,
                                    ).withValues(alpha: 0.24),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: widget.isSending
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : widget.isEditing
                                  ? wrytteSvgAssetIcon(
                                      assetPath:
                                          'assets/svg/Checkmark edit.svg',
                                      canvas:
                                          WrytteVisualTokens.mainIconCanvas *
                                          widget.controlScale,
                                      scale: 0.98,
                                      color: Colors.white,
                                    )
                                  : Transform.translate(
                                      offset: const Offset(-1.5, 0),
                                      child: Transform.rotate(
                                        angle: math.pi / 4,
                                        child: wrytteSvgAssetIcon(
                                          assetPath:
                                              'assets/svg/Send icon .svg',
                                          canvas:
                                              _composerMainIconCanvas *
                                              widget.controlScale,
                                          scale: _sendOpticalScale,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        )
                      // ── Mic pill — hold to record, release to send ──────
                      : Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _handleRecordPointerDown,
                          onPointerMove: _handleRecordPointerMove,
                          onPointerUp: _handleRecordPointerUp,
                          onPointerCancel: _handleRecordPointerUp,
                          child: CompositedTransformTarget(
                            link: _recordButtonLayerLink,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _handleRecordingButtonTap,
                              onLongPressDown: (_) =>
                                  _handleRecordButtonLongPressDown(),
                              onLongPressStart: (_) {
                                _removeRecordModeHint();
                                unawaited(Feedback.forLongPress(context));
                                if (_cameraMode) {
                                  unawaited(_startVideoMessageRecording());
                                } else {
                                  unawaited(_startRecording());
                                }
                              },
                              onLongPressMoveUpdate: _handleRecordMove,
                              onLongPressEnd: (_) {
                                if (_videoMessagePreparing) {
                                  _videoPointerReleasedWhilePreparing = true;
                                  return;
                                }
                                _setRecordButtonPressed(false);
                                if (_isRecording && !_recordingLocked) {
                                  unawaited(_stopActiveRecordingAndSend());
                                }
                              },
                              onLongPressCancel: () {
                                if (_quickLockRequested) return;
                                if (_videoMessagePreparing) {
                                  _videoPointerReleasedWhilePreparing = true;
                                  return;
                                }
                                _setRecordButtonPressed(false);
                                if (_isRecording && !_recordingLocked) {
                                  unawaited(_cancelActiveRecording());
                                }
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.bottomCenter,
                                children: [
                                  TweenAnimationBuilder<Offset>(
                                    tween: Tween<Offset>(
                                      end: Offset(
                                        -_cancelDragVisualDx,
                                        _cancelDragVisualDy,
                                      ),
                                    ),
                                    duration: Duration(
                                      milliseconds: _recordingLocked ? 220 : 65,
                                    ),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, offset, child) =>
                                        Transform.translate(
                                          offset: offset,
                                          child: child,
                                        ),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween<double>(
                                        end: 1 - (0.42 * _cancelDragProgress),
                                      ),
                                      duration: const Duration(
                                        milliseconds: 65,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, scale, child) =>
                                          Transform.scale(
                                            scale: scale,
                                            alignment: Alignment.center,
                                            child: child,
                                          ),
                                      child: AnimatedScale(
                                        scale: _isRecording
                                            ? 1.40
                                            : _recordButtonPressed
                                            ? 1.1
                                            : 1,
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: _isRecording
                                            ? Curves.easeOutBack
                                            : Curves.easeOutCubic,
                                        child: _glassPill(
                                          width: _isRecording
                                              ? widget.controlSize + 1.5
                                              : widget.controlSize,
                                          height: _isRecording
                                              ? widget.controlSize + 1.5
                                              : widget.controlSize,
                                          decoration: _isRecording
                                              ? _recordingActionButtonDecoration()
                                              : null,
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 260,
                                            ),
                                            reverseDuration: const Duration(
                                              milliseconds: 210,
                                            ),
                                            switchInCurve: Curves.easeOutBack,
                                            switchOutCurve: Curves.easeInCubic,
                                            layoutBuilder:
                                                (
                                                  currentChild,
                                                  previousChildren,
                                                ) => Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    ...previousChildren,
                                                    if (currentChild != null)
                                                      currentChild,
                                                  ],
                                                ),
                                            transitionBuilder:
                                                (child, animation) {
                                                  final turn = Tween<double>(
                                                    begin: -0.08,
                                                    end: 0,
                                                  ).animate(animation);
                                                  final scale = Tween<double>(
                                                    begin: 0.58,
                                                    end: 1,
                                                  ).animate(animation);
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: RotationTransition(
                                                      turns: turn,
                                                      child: ScaleTransition(
                                                        scale: scale,
                                                        child: child,
                                                      ),
                                                    ),
                                                  );
                                                },
                                            child: _recordingLocked
                                                ? KeyedSubtree(
                                                    key: const ValueKey(
                                                      'locked-recording-send',
                                                    ),
                                                    child: Transform.translate(
                                                      offset: const Offset(
                                                        -1.5,
                                                        0,
                                                      ),
                                                      child: Transform.rotate(
                                                        angle: math.pi / 4,
                                                        child: wrytteSvgAssetIcon(
                                                          assetPath:
                                                              'assets/svg/Send icon .svg',
                                                          canvas:
                                                              24 *
                                                              widget
                                                                  .controlScale,
                                                          scale: 1.12,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : _cameraMode
                                                ? KeyedSubtree(
                                                    key: const ValueKey(
                                                      'video-message-mode',
                                                    ),
                                                    child: wrytteSvgAssetIcon(
                                                      assetPath:
                                                          'assets/svg/Video Message.svg',
                                                      canvas:
                                                          _composerMainIconCanvas *
                                                          widget.controlScale,
                                                      scale: _videoOpticalScale,
                                                    ),
                                                  )
                                                : KeyedSubtree(
                                                    key: const ValueKey(
                                                      'voice-message-mode',
                                                    ),
                                                    child: wrytteSvgAssetIcon(
                                                      assetPath:
                                                          'assets/svg/New voice msg icon .svg',
                                                      canvas:
                                                          _composerMainIconCanvas *
                                                          widget.controlScale,
                                                      scale:
                                                          _microphoneOpticalScale,
                                                      color: _isRecording
                                                          ? Colors.white
                                                          : WrytteVisualTokens
                                                                .iconColor,
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

  Widget _buildContextPreview() {
    final sender = widget.replySender?.trim();
    final preview = widget.replyPreview?.trim();
    final isEditing = widget.isEditing;
    final isMediaEdit =
        isEditing && widget.editingMediaSource?.trim().isNotEmpty == true;

    return Semantics(
      key: ValueKey(
        isEditing
            ? 'message-input-edit-preview'
            : 'message-input-reply-preview',
      ),
      container: true,
      label: isEditing
          ? 'Editing message'
          : 'Replying to ${sender?.isNotEmpty == true ? sender : 'message'}',
      child: Padding(
        padding: EdgeInsets.only(top: isMediaEdit ? 4 : 6, bottom: 4),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF72BCFF), WrytteColors.primary],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: isEditing
                  ? _buildEditingPreview()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender?.isNotEmpty == true ? sender! : 'Reply',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF62ACF8),
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          preview?.isNotEmpty == true ? preview! : 'Message',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.76),
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.08,
                          ),
                        ),
                      ],
                    ),
            ),
            IconButton(
              key: ValueKey(
                isEditing
                    ? 'message-input-cancel-edit'
                    : 'message-input-cancel-reply',
              ),
              tooltip: isEditing ? 'Cancel edit' : 'Cancel reply',
              onPressed: isEditing ? widget.onCancelEdit : widget.onCancelReply,
              constraints: const BoxConstraints.tightFor(width: 36, height: 40),
              padding: EdgeInsets.zero,
              splashRadius: 19,
              icon: Transform.translate(
                offset: const Offset(3, 0),
                child: Icon(
                  Icons.close_rounded,
                  size: 21,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditingPreview() {
    final mediaSource = widget.editingMediaSource?.trim() ?? '';
    final hasMedia = mediaSource.isNotEmpty;
    return Row(
      children: [
        const Flexible(
          child: Text(
            'Edit message',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF62ACF8),
              fontFamily: WrytteTypography.primaryFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.08,
            ),
          ),
        ),
        if (hasMedia) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Replace media',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onReplaceEditingMedia == null
                  ? null
                  : () => unawaited(widget.onReplaceEditingMedia!()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    wrytteSvgAssetIcon(
                      assetPath: 'assets/svg/Replace media icon.svg',
                      canvas: 17,
                      scale: 1.04,
                      color: const Color(0xFF62ACF8),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Replace',
                      style: TextStyle(
                        color: Color(0xFF62ACF8),
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          _EditingMediaThumbnail(
            source: mediaSource,
            mediaType: widget.editingMediaType,
          ),
        ],
      ],
    );
  }

  Future<void> _openDedicatedChatCamera({
    CameraController? initialController,
    bool initialAudioEnabled = false,
  }) async {
    if (!mounted) return;

    final result = await Navigator.of(context, rootNavigator: true)
        .push<ChatCameraResult>(
          PageRouteBuilder<ChatCameraResult>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 230),
            pageBuilder: (context, animation, secondaryAnimation) =>
                ChatCameraScreen(
                  recipientLabel: widget.attachmentRecipientLabel,
                  initialController: initialController,
                  initialAudioEnabled: initialAudioEnabled,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );

                  return FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.985,
                        end: 1,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
          ),
        );

    if (!mounted || result == null) return;

    if (result.openGallery) {
      // The camera's gallery thumbnail behaves like Telegram: it returns to
      // the same attachment Recents panel instead of opening a second picker.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) await _showAttachmentMenu(initiallyExpanded: true);
      return;
    }

    final path = result.filePath?.trim() ?? '';
    final attachmentType = result.attachmentType?.trim() ?? '';

    if (path.isEmpty || attachmentType.isEmpty) return;

    final pickedAttachment = widget.onPickedAttachment;
    if (pickedAttachment != null) {
      await pickedAttachment(
        path,
        attachmentType,
        caption: result.caption?.trim().isEmpty == true
            ? null
            : result.caption?.trim(),
      );
      return;
    }

    // Compatibility fallback for any caller that has not migrated to the
    // direct picked-attachment callback yet.
    await widget.onCameraAttachment?.call();
  }

  Future<void> _openCameraAboveAttachmentPanel({
    required BuildContext dialogContext,
    required _AttachmentSelection selection,
  }) async {
    final route = _attachmentCameraRoute(
      recipientLabel: widget.attachmentRecipientLabel,
      initialController: selection.cameraController,
      initialAudioEnabled: selection.cameraAudioEnabled,
      sourceRect: selection.cameraSourceRect,
      onReturnController: selection.onCameraControllerReturned,
    );
    final result = await Navigator.of(
      dialogContext,
    ).push<ChatCameraResult>(route);
    await route.completed;

    if (!mounted || result == null) return;
    if (result.openGallery) {
      Navigator.of(dialogContext).pop<_AttachmentSelection>(
        const _AttachmentSelection.action(_AttachmentAction.gallery),
      );
      return;
    }

    final path = result.filePath?.trim() ?? '';
    final attachmentType = result.attachmentType?.trim() ?? '';
    if (path.isEmpty || attachmentType.isEmpty) return;

    Navigator.of(dialogContext).pop<_AttachmentSelection>(
      _AttachmentSelection.media(
        caption: result.caption,
        media: <ChatPickedAttachment>[
          ChatPickedAttachment(filePath: path, attachmentType: attachmentType),
        ],
      ),
    );
  }

  Future<void> _showAttachmentMenu({
    bool initialAudioMode = false,
    bool initiallyExpanded = false,
  }) async {
    if (_attachmentMenuOpen || !mounted) return;
    widget.focusNode.unfocus();

    setState(() => _attachmentMenuOpen = true);

    _AttachmentSelection? selection;
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      selection = await navigator.push<_AttachmentSelection>(
        PageRouteBuilder<_AttachmentSelection>(
          opaque: false,
          barrierDismissible: true,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          barrierColor: Colors.black.withValues(alpha: 0.44),
          maintainState: true,
          allowSnapshotting: false,
          transitionDuration: _attachmentPanelTransitionDuration,
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (panelContext, animation, secondaryAnimation) =>
              Material(
                color: Colors.transparent,
                child: _TelegramAttachmentPanel(
                  recipientLabel: widget.attachmentRecipientLabel,
                  initialAudioMode: initialAudioMode,
                  initiallyExpanded: initiallyExpanded,
                  onCameraSelected: (selected) =>
                      _openCameraAboveAttachmentPanel(
                        dialogContext: panelContext,
                        selection: selected,
                      ),
                  onSelected: (selected) {
                    unawaited(HapticFeedback.selectionClick());
                    Navigator.of(panelContext).pop(selected);
                  },
                ),
              ),
          transitionsBuilder: _attachmentPanelSlideTransition,
        ),
      );
    } finally {
      if (mounted) setState(() => _attachmentMenuOpen = false);
    }

    if (!mounted || selection == null) return;
    if (selection.contacts.isNotEmpty) {
      final pickedContacts = widget.onPickedContacts;
      if (pickedContacts != null) {
        await pickedContacts(selection.contacts, caption: selection.caption);
        return;
      }

      // Keep the previous text-sharing fallback for any other caller that has
      // not opted into dedicated contact messages yet.
      final shareText = _contactShareText(
        selection.contacts,
        caption: selection.caption,
      );
      if (shareText.isNotEmpty) {
        widget.controller.value = TextEditingValue(
          text: shareText,
          selection: TextSelection.collapsed(offset: shareText.length),
        );
        widget.onSend();
      }
      return;
    }
    if (selection.media.isNotEmpty) {
      final pickedAttachments = widget.onPickedAttachments;
      if (selection.media.length > 1 && pickedAttachments != null) {
        await pickedAttachments(selection.media, caption: selection.caption);
        return;
      }
      final pickedAttachment = widget.onPickedAttachment;
      if (pickedAttachment != null) {
        final mediaGroupId = selection.media.length > 1
            ? 'album_${DateTime.now().microsecondsSinceEpoch}'
            : null;
        for (var index = 0; index < selection.media.length; index++) {
          final media = selection.media[index];
          await pickedAttachment(
            media.filePath,
            media.attachmentType,
            caption: index == 0 ? selection.caption : null,
            mediaGroupId: mediaGroupId,
            mediaGroupIndex: mediaGroupId == null ? null : index,
            mediaGroupCount: mediaGroupId == null
                ? null
                : selection.media.length,
            mediaWidth: media.width,
            mediaHeight: media.height,
            audioTitle: media.audioTitle,
            audioArtist: media.audioArtist,
            audioArtworkPath: media.audioArtworkPath,
            audioDurationSeconds: media.audioDurationSeconds,
          );
        }
      } else {
        await widget.onGalleryAttachment?.call();
      }
      return;
    }

    switch (selection.action) {
      case _AttachmentAction.camera:
        await _openDedicatedChatCamera(
          initialController: selection.cameraController,
          initialAudioEnabled: selection.cameraAudioEnabled,
        );
        break;
      case _AttachmentAction.gallery:
        await widget.onGalleryAttachment?.call();
        break;
      case _AttachmentAction.file:
        await widget.onFileAttachment?.call();
        break;
      case null:
        break;
    }
  }

  String _contactShareText(List<Contact> contacts, {String? caption}) {
    final lines = <String>[];
    final trimmedCaption = caption?.trim() ?? '';
    if (trimmedCaption.isNotEmpty) {
      lines.add(trimmedCaption);
      lines.add('');
    }
    for (var index = 0; index < contacts.length; index++) {
      final contact = contacts[index];
      final name = contact.formattedName.trim().isEmpty
          ? 'Contact'
          : contact.formattedName.trim();
      final phone = contact.primaryPhone.trim();
      lines.add(phone.isEmpty ? name : '$name\n$phone');
      if (index < contacts.length - 1) lines.add('');
    }
    return lines.join('\n').trim();
  }

  // ── Telegram round-video preview overlay ──────────────────────────────────
  void _showVideoMessagePreview() {
    if (_videoMessagePreviewEntry != null) {
      _videoMessagePreviewEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final mediaSize = MediaQuery.sizeOf(overlayContext);
        final keyboardInset = math.max(
          MediaQuery.viewInsetsOf(overlayContext).bottom,
          _recordingKeyboardInset,
        );
        final availableHeight = math.max(0.0, mediaSize.height - keyboardInset);
        final compactForKeyboard = keyboardInset > 1;
        final panelHeight = compactForKeyboard
            ? math.min(availableHeight, mediaSize.height * 0.50)
            : availableHeight;

        return Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 165),
              curve: const Cubic(0.18, 0.92, 0.22, 1),
              builder: (context, value, child) => _buildVideoMessagePreview(
                panelSize: Size(mediaSize.width, panelHeight),
                keyboardInset: keyboardInset,
                compactForKeyboard: compactForKeyboard,
                bottomSystemInset: compactForKeyboard
                    ? 0
                    : MediaQuery.viewPaddingOf(overlayContext).bottom,
                entranceProgress: value,
              ),
            ),
          ),
        );
      },
    );
    _videoMessagePreviewEntry = entry;
    overlay.insert(entry);
  }

  void _refreshVideoMessagePreview() {
    _videoMessagePreviewEntry?.markNeedsBuild();
  }

  void _removeVideoMessagePreview() {
    _videoMessagePreviewEntry?.remove();
    _videoMessagePreviewEntry = null;
  }

  // ── Telegram round-video preview ──────────────────────────────────────────
  // The recording logic stays shared with the voice recorder. This overlay only
  // changes the presentation: the live camera becomes a blurred full-screen
  // backdrop, while a crisp circular preview sits in the visual center.
  Widget _buildVideoMessagePreview({
    required Size panelSize,
    required double keyboardInset,
    required bool compactForKeyboard,
    required double bottomSystemInset,
    required double entranceProgress,
  }) {
    final controller = _videoMessageController;
    final cameraReady = controller?.value.isInitialized == true;
    final size = panelSize;
    final progress =
        (_recordingStopwatch.elapsedMilliseconds /
                (_maxVideoMessageSeconds * 1000))
            .clamp(0.0, 1.0)
            .toDouble();
    final frontCamera =
        controller?.description.lensDirection == CameraLensDirection.front;

    // The circle stays visually centered regardless of the controls below it.
    final previewDiameter = compactForKeyboard
        ? math.min(size.width * 0.52, math.min(size.height * 0.46, 210.0))
        : math.min(size.width * 0.84, math.min(size.height * 0.48, 420.0));
    // Keep the recording progress inside the video circle instead of outside it.
    final ringDiameter = previewDiameter;

    // Use the exact same bottom floating gap as the normal voice composer.
    final bottomFloatGap =
        bottomSystemInset + (bottomSystemInset > 0 ? 10.0 : 12.0);
    final secondaryControlsBottom =
        bottomFloatGap + widget.inputPillHeight + 25.0;

    Widget circularPreview;
    final pausedVideoPreviewController = _pausedVideoPreviewController;
    if (_recordingPaused) {
      if (pausedVideoPreviewController?.value.isInitialized == true) {
        circularPreview = _buildRoundVideoPlaybackFeed(
          pausedVideoPreviewController!,
        );
      } else {
        circularPreview = _buildRoundVideoStatusPreview(loading: false);
      }
    } else if (_videoMessageCameraAccessState ==
        _VideoMessageCameraAccessState.denied) {
      circularPreview = _buildRoundVideoStatusPreview(loading: false);
    } else if (_videoMessageCameraAccessState ==
        _VideoMessageCameraAccessState.unavailable) {
      circularPreview = _buildRoundVideoStatusPreview(loading: false);
    } else if (!cameraReady || controller == null) {
      circularPreview = _buildRoundVideoStatusPreview(loading: true);
    } else {
      circularPreview = _buildRoundVideoCameraFeed(controller);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen chat blur + dark wash. The chat remains present underneath
        // but is intentionally unreadable while a video message is recording.
        Positioned.fill(
          child: Opacity(
            opacity: entranceProgress,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 38 * entranceProgress,
                  sigmaY: 38 * entranceProgress,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.black.withValues(alpha: 0.80),
                        Colors.black.withValues(alpha: 0.90),
                      ],
                      stops: const [0, 0.54, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: keyboardInset,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The sharp preview and old composer controls share one panel. When
              // the IME is open this panel is half-height and sits directly above it.
              Positioned.fill(
                child: Align(
                  alignment: compactForKeyboard
                      ? const Alignment(0, -0.30)
                      : Alignment.center,
                  child: Transform.translate(
                    offset: Offset(0, compactForKeyboard ? -10 : -20),
                    child: Opacity(
                      opacity: entranceProgress,
                      child: Transform.scale(
                        scale: 0.955 + (0.045 * entranceProgress),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _handleVideoPreviewScaleStart,
                          onScaleUpdate: _handleVideoPreviewScaleUpdate,
                          child: SizedBox.square(
                            dimension: ringDiameter,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipOval(
                                  child: SizedBox.square(
                                    dimension: previewDiameter,
                                    child: ColoredBox(
                                      color: Colors.black,
                                      child: circularPreview,
                                    ),
                                  ),
                                ),
                                // Draw progress only while the live texture is visible.
                                // When the camera has not produced a frame yet, the ring
                                // endpoint reads like a random white mark at the bottom.
                                if (cameraReady)
                                  IgnorePointer(
                                    child: CustomPaint(
                                      size: Size.square(ringDiameter),
                                      painter: _RoundVideoProgressPainter(
                                        progress: progress,
                                      ),
                                    ),
                                  ),
                                if (_recordingPaused)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: previewDiameter * 0.02,
                                    child: Center(
                                      child: _buildRoundVideoMuteBadge(),
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
              ),

              // Camera + flash use the same glass sizing language and sit horizontally
              // above the exact place where the voice recorder's Delete button appears.
              Positioned(
                left: 14,
                bottom: secondaryControlsBottom,
                child: Opacity(
                  opacity: entranceProgress,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - entranceProgress)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildVideoAccentButton(
                          semanticLabel: frontCamera
                              ? 'Switch to back camera'
                              : 'Switch to front camera',
                          assetPath: 'assets/svg/Flip camera icon .svg',
                          enabled: _videoMessageHasFrontBackCameras,
                          onTap: () => unawaited(_switchVideoMessageCamera()),
                        ),
                        const SizedBox(width: 10),
                        _buildVideoAccentButton(
                          semanticLabel: _videoFlashEnabled
                              ? 'Turn flash off'
                              : 'Turn flash on',
                          assetPath: _videoFlashEnabled
                              ? 'assets/svg/Flash on icon .svg'
                              : 'assets/svg/Flash off icon.svg',
                          color: const Color(0xFFF3F4F6),
                          enabled: !frontCamera,
                          forceEnabledLook: true,
                          onTap: () => unawaited(_toggleVideoFlash()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // IMPORTANT: this is the SAME lock widget as voice recording. Therefore
              // the arrow movement, lock shrink/morph, pause/resume transition and
              // timing are not re-created or approximated for video.
              Positioned(
                right: 14 + ((widget.controlSize + 1.5 - 42) / 2),
                bottom: secondaryControlsBottom,
                child: _buildRecordingLockGuide(),
              ),

              // Build the bottom recorder using the SAME pieces as voice recording:
              // same delete pill, same recording indicator and same moving blue action
              // button. The video overlay only changes what is inside the round preview.
              Positioned(
                left: 14,
                right: 14,
                bottom: bottomFloatGap,
                child: Opacity(
                  opacity: entranceProgress,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - entranceProgress)),
                    child: Transform.scale(
                      scale: 0.985 + (0.015 * entranceProgress),
                      alignment: Alignment.bottomCenter,
                      child: _buildVideoVoiceMatchedBottomRow(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoundVideoStatusPreview({required bool loading}) {
    final glowAlpha = loading ? 0.78 : 0.72;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                const Color(0xFF28313A).withValues(alpha: glowAlpha),
                const Color(0xFF090B0F).withValues(alpha: 0.92),
              ],
              center: const Alignment(0, -0.18),
              radius: 0.96,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildRoundVideoCameraFeed(CameraController controller) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final previewAspect = _orientedCameraPreviewAspect(controller);
        if (!previewAspect.isFinite || previewAspect <= 0) {
          return const ColoredBox(color: Colors.black);
        }

        const baseExtent = 1000.0;
        final previewWidth = previewAspect >= 1
            ? baseExtent * previewAspect
            : baseExtent;
        final previewHeight = previewAspect >= 1
            ? baseExtent
            : baseExtent / previewAspect;

        return ColoredBox(
          color: Colors.black,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              child: Transform.scale(
                scale: _roundVideoCoverBleed,
                child: SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _orientedCameraPreviewAspect(CameraController controller) {
    final rawAspect = controller.value.aspectRatio;
    if (!rawAspect.isFinite || rawAspect <= 0) return 1;
    final orientation = controller.value.isRecordingVideo
        ? controller.value.recordingOrientation ??
              controller.value.lockedCaptureOrientation ??
              controller.value.deviceOrientation
        : controller.value.previewPauseOrientation ??
              controller.value.lockedCaptureOrientation ??
              controller.value.deviceOrientation;
    final isLandscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    return isLandscape ? rawAspect : (1 / rawAspect);
  }

  Widget _buildRoundVideoPlaybackFeed(VideoPlayerController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final videoSize = controller.value.size;
        final videoAspect = videoSize.width > 0 && videoSize.height > 0
            ? videoSize.width / videoSize.height
            : 1.0;
        return ColoredBox(
          color: Colors.black,
          child: _buildRoundVideoCover(
            sourceAspect: videoAspect,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }

  Widget _buildRoundVideoMuteBadge() {
    return Semantics(
      button: true,
      label: _pausedVideoMuted ? 'Unmute video preview' : 'Mute video preview',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePausedVideoMute,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF05070A).withValues(alpha: 0.48),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.8,
            ),
          ),
          child: SizedBox.square(
            dimension: 34,
            child: Center(
              child: wrytteSvgAssetIcon(
                assetPath: _pausedVideoMuted
                    ? 'assets/svg/Nosound icon.svg'
                    : 'assets/svg/Sound icon.svg',
                canvas: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _togglePausedVideoMute() {
    if (!_cameraMode || !_recordingPaused) return;
    final muted = !_pausedVideoMuted;
    _pausedVideoMuted = muted;
    final controller = _pausedVideoPreviewController;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.setVolume(muted ? 0 : 1));
    }
    if (mounted) setState(() {});
    _refreshVideoMessagePreview();
  }

  Widget _buildRoundVideoCover({
    required double sourceAspect,
    required Widget child,
  }) {
    if (!sourceAspect.isFinite || sourceAspect <= 0) {
      return SizedBox.expand(child: child);
    }
    const baseExtent = 1000.0;
    final sourceWidth = sourceAspect >= 1
        ? baseExtent * sourceAspect
        : baseExtent;
    final sourceHeight = sourceAspect >= 1
        ? baseExtent
        : baseExtent / sourceAspect;

    return ClipRect(
      child: Transform.scale(
        scale: _roundVideoCoverBleed,
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: sourceWidth,
            height: sourceHeight,
            child: child,
          ),
        ),
      ),
    );
  }

  // The blue recording button used by BOTH voice and video. Keeping this in one
  // helper prevents the two modes from slowly drifting apart visually.
  BoxDecoration _recordingActionButtonDecoration() {
    return BoxDecoration(
      color: const Color(0xFF5AA4F0),
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.10),
        width: 0.8,
      ),
      // Intentionally flat: no separate drop shadow around the recording action.
      boxShadow: const [],
    );
  }

  Widget _buildVideoVoiceMatchedBottomRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Voice recording hides + while holding and reveals the same slot as a
        // red Delete control after locking. Reproduce that exact width animation.
        IgnorePointer(
          ignoring: !_recordingLocked,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _recordingLocked ? 1 : 0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, visibility, child) => ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: visibility,
                child: Opacity(
                  opacity: visibility,
                  child: Transform.translate(
                    offset: Offset(-14 * (1 - visibility), 0),
                    child: child,
                  ),
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildVideoDeleteButton(),
                SizedBox(width: widget.controlGap),
              ],
            ),
          ),
        ),

        Expanded(
          child: SizedBox(
            height: widget.inputPillHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // This mirrors the voice composer, whose recording pill extends
                // beneath the right action-button area by 49 logical pixels.
                Positioned(
                  left: 0,
                  right: -49,
                  top: 0,
                  bottom: 0,
                  child: _buildRecordingIndicator(),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: widget.controlGap),
        _buildVideoVoiceMatchedActionButton(),
      ],
    );
  }

  Widget _buildVideoVoiceMatchedActionButton() {
    return TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(
        end: Offset(-_cancelDragVisualDx, _cancelDragVisualDy),
      ),
      duration: Duration(milliseconds: _recordingLocked ? 220 : 65),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) =>
          Transform.translate(offset: offset, child: child),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: 1 - (0.42 * _cancelDragProgress)),
        duration: const Duration(milliseconds: 65),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
        child: AnimatedScale(
          // Exact same recording growth used by the voice-message button.
          scale: _isRecording ? 1.40 : (_recordButtonPressed ? 1.1 : 1),
          duration: const Duration(milliseconds: 250),
          curve: _isRecording ? Curves.easeOutBack : Curves.easeOutCubic,
          child: _glassPill(
            width: _isRecording ? widget.controlSize + 1.5 : widget.controlSize,
            height: _isRecording
                ? widget.controlSize + 1.5
                : widget.controlSize,
            decoration: _isRecording
                ? _recordingActionButtonDecoration()
                : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              reverseDuration: const Duration(milliseconds: 210),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                final turn = Tween<double>(
                  begin: -0.08,
                  end: 0,
                ).animate(animation);
                final scale = Tween<double>(
                  begin: 0.58,
                  end: 1,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: RotationTransition(
                    turns: turn,
                    child: ScaleTransition(scale: scale, child: child),
                  ),
                );
              },
              child: _recordingLocked
                  ? KeyedSubtree(
                      key: const ValueKey('video-locked-recording-send'),
                      child: Transform.translate(
                        offset: const Offset(-1.5, 0),
                        child: Transform.rotate(
                          angle: math.pi / 4,
                          child: wrytteSvgAssetIcon(
                            assetPath: 'assets/svg/Send icon .svg',
                            canvas: 24,
                            scale: 1.12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('video-message-active-recording'),
                      child: wrytteSvgAssetIcon(
                        assetPath: 'assets/svg/Video Message.svg',
                        canvas: _composerMainIconCanvas * widget.controlScale,
                        scale: _videoOpticalScale,
                        color: Colors.white,
                      ),
                    ),
            ),
            onTap: _recordingLocked
                ? () => unawaited(_stopVideoRecordingAndSend())
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoDeleteButton() {
    // Exact same dimensions/icon values as the voice recorder's locked Delete.
    return _glassPill(
      width: widget.controlSize,
      height: widget.controlSize,
      child: wrytteSvgAssetIcon(
        assetPath: 'assets/svg/Delete icon.svg',
        canvas: 22,
        scale: 1.04,
        color: WrytteColors.destructive,
      ),
      onTap: () {
        unawaited(HapticFeedback.mediumImpact());
        unawaited(_cancelVideoRecording());
      },
    );
  }

  Widget _buildVideoAccentButton({
    required String semanticLabel,
    required String assetPath,
    required VoidCallback onTap,
    bool enabled = true,
    bool forceEnabledLook = false,
    Color? color,
  }) {
    final visuallyEnabled = enabled || forceEnabledLook;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Opacity(
        opacity: visuallyEnabled ? 1 : 0.48,
        child: _glassPill(
          width: widget.controlSize,
          height: widget.controlSize,
          onTap: enabled ? onTap : null,
          child: wrytteSvgAssetIcon(
            assetPath: assetPath,
            canvas: 28,
            color:
                color ??
                (visuallyEnabled
                    ? const Color(0xFFF3F4F6)
                    : const Color(0xFF777A82)),
          ),
        ),
      ),
    );
  }

  // ── Recording indicator — replaces the text field while recording ──────────
  // Same glass pill style as the rest of the bar. Shows a red dot + timer.
  Widget _buildRecordingLockGuide() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _isRecording ? 1 : 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, visibility, child) {
        return Opacity(
          opacity: visibility,
          child: Transform.scale(
            scale: 0.88 + (visibility * 0.12),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: _buildUnlockedRecordingLockGuide(),
    );
  }

  Widget _buildUnlockedRecordingLockGuide() {
    final unlockedGuideContent = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        wrytteSvgAssetIcon(
          assetPath: 'assets/svg/Lock open Voice msg (1).svg',
          canvas: 24,
          scale: 1.02,
          color: const Color(0xFFF7F8FA),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _recordLockProgress),
          duration: const Duration(milliseconds: 65),
          curve: Curves.easeOutCubic,
          builder: (context, progress, child) => Transform.translate(
            offset: Offset(0, -(8 * progress)),
            child: child,
          ),
          child: RotatedBox(
            quarterTurns: 1,
            child: wrytteSvgAssetIcon(
              assetPath: 'assets/svg/Arrow voice area.svg',
              canvas: 24,
              scale: 1.25,
              color: const Color(0xFFF7F8FA),
            ),
          ),
        ),
      ],
    );

    return IgnorePointer(
      key: const ValueKey('voice-lock-guide'),
      ignoring: !_recordingLocked,
      child: Semantics(
        button: _recordingLocked,
        label: _recordingPaused
            ? (_cameraMode
                  ? 'Resume video recording'
                  : 'Resume voice recording')
            : (_cameraMode ? 'Pause video recording' : 'Pause voice recording'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _recordingPaused
              ? () => unawaited(_resumeActiveLockedRecording())
              : () => unawaited(_pauseActiveLockedRecording()),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 42,
                height: _recordGuideReached ? 42 : 72,
                decoration: wrytteGlassDecoration(radius: 21),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: _recordGuideReached ? 0 : 1,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        scale: _recordGuideReached ? 0.76 : 1,
                        child: OverflowBox(
                          minHeight: 72,
                          maxHeight: 72,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 42,
                            height: 72,
                            child: unlockedGuideContent,
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      opacity: _recordGuideReached ? 1 : 0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        scale: _recordGuideReached ? 1 : 0.62,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          reverseDuration: const Duration(milliseconds: 190),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.62,
                                    end: 1,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _recordingPaused
                              ? KeyedSubtree(
                                  key: ValueKey(
                                    _cameraMode
                                        ? 'resume-recording-video'
                                        : 'resume-recording-microphone',
                                  ),
                                  child: _cameraMode
                                      ? wrytteSvgAssetIcon(
                                          assetPath:
                                              'assets/svg/Video Message.svg',
                                          canvas:
                                              _composerMainIconCanvas *
                                              widget.controlScale,
                                          scale: _videoOpticalScale,
                                          color: Colors.white,
                                        )
                                      : wrytteSvgAssetIcon(
                                          assetPath:
                                              'assets/svg/ph--microphone.svg',
                                          canvas: 27,
                                          scale: 0.96,
                                          color: Colors.white,
                                        ),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('pause-locked-recording'),
                                  child: wrytteSvgAssetIcon(
                                    assetPath:
                                        'assets/svg/Pause icon voice .svg',
                                    canvas: 28,
                                    scale: 1.16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    const pillRadius = WrytteVisualTokens.capsuleRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(pillRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: widget.inputPillHeight,
          width: double.infinity,
          decoration: wrytteGlassDecoration(radius: pillRadius),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                alignment: Alignment.centerRight,
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: _cameraMode
                ? _recordingPaused
                      ? KeyedSubtree(
                          key: const ValueKey('paused-video-recording-trimmer'),
                          child: _buildPausedVideoEditor(),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('video-recording-controls'),
                          child: _buildSlidingRecordingControls(),
                        )
                : _recordingPaused
                ? KeyedSubtree(
                    key: const ValueKey('paused-recording-trimmer'),
                    child: _buildPausedRecordingEditor(),
                  )
                : KeyedSubtree(
                    key: const ValueKey('live-recording-controls'),
                    child: _buildSlidingRecordingControls(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPausedRecordingEditor() {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 66),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: _isPreviewPlaying ? 'Pause preview' : 'Play preview',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_togglePreviewPlayback()),
              child: SizedBox(
                width: 34,
                height: widget.inputPillHeight,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 190),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.72,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _isPreviewPlaying
                        ? const Icon(
                            Icons.pause_rounded,
                            key: ValueKey('trim-preview-pause'),
                            color: WrytteColors.textSecondary,
                            size: 27,
                          )
                        : KeyedSubtree(
                            key: const ValueKey('trim-preview-play'),
                            child: wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Play icon .svg',
                              canvas: 27,
                              scale: 1.18,
                              color: WrytteColors.textSecondary,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: ValueListenableBuilder<List<double>>(
              valueListenable: _recordingLevelsNotifier,
              builder: (context, levels, child) => _VoiceTrimTimeline(
                levels: levels,
                startFraction: _trimStartFraction,
                endFraction: _trimEndFraction,
                playbackFraction: _pausedRecordingDuration.inMicroseconds <= 0
                    ? _trimStartFraction
                    : (_previewPosition.inMicroseconds /
                              _pausedRecordingDuration.inMicroseconds)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                totalDuration: _pausedRecordingDuration,
                durationLabel: _formatVoiceDuration(
                  _isPreviewPlaying
                      ? _previewPosition - _trimStartDuration
                      : _trimmedDuration,
                ),
                onRangeChanged: _updateTrimRange,
                onSeek: _seekPreviewToFraction,
                onInteractionChanged: _setPreviewTimelineInteraction,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausedVideoEditor() {
    final total = _pausedVideoTimelineDuration;
    if (total.inMilliseconds <= 0) {
      return _buildSlidingRecordingControls();
    }
    final start = _trimStartDuration;
    final end = _trimEndDuration;
    return Transform.translate(
      offset: const Offset(0, -1),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 72),
        child: Row(
          children: [
            Expanded(
              child: TelegramVideoTrimTimeline(
                duration: total,
                span: pie.TrimDurationSpan(start: start, end: end),
                playhead: _previewPosition,
                thumbnails: _pausedVideoMessageThumbnails,
                thumbnailRotation: 0,
                thumbnailMirrorX: false,
                thumbnailScale: _roundVideoActiveThumbnailCropScale,
                frameColor: Colors.transparent,
                handleColor: const Color(0xFF5AA4F0),
                handleGripColor: Colors.white,
                playheadColor: const Color(0xFFD8DEE7),
                onInteractionStart: () {},
                onChanged: (span) {
                  final totalMicros = total.inMicroseconds;
                  if (totalMicros <= 0) return;
                  _updateVideoTrimRange(
                    span.start.inMicroseconds / totalMicros,
                    span.end.inMicroseconds / totalMicros,
                  );
                },
                onChangeEnd: (span) {
                  unawaited(_seekPausedVideoPreview(span.start));
                  unawaited(_pausedVideoPreviewController?.play());
                },
                onSeek: (position) {
                  unawaited(_seekPausedVideoPreview(position));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatVoiceDuration(Duration duration) {
    final safeSeconds = math.max(0, duration.inSeconds);
    final minutes = safeSeconds ~/ 60;
    final seconds = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildLockedVideoRecordingStatus() {
    return Row(
      children: [
        _buildRecordingTimer(),
        const SizedBox(width: 12),
        _PulsingDot(second: _elapsedSeconds),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _recordingPaused ? 'Video paused' : 'Video message',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WrytteColors.textSecondary,
              fontFamily: WrytteTypography.primaryFontFamily,
              fontSize: 15,
              height: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        // The recording pill extends under the blue send button. Reserve a
        // small visual spacer so the centered label never hides underneath it.
        const SizedBox(width: 38),
      ],
    );
  }

  Widget _buildSlidingRecordingControls() {
    return Padding(
      key: const ValueKey('sliding-recording-controls'),
      padding: const EdgeInsets.only(left: 14, right: 66),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _recordingLocked ? 1 : 0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, lockedProgress, child) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            Opacity(
              opacity: 1 - lockedProgress,
              child: Transform.translate(
                offset: Offset(-8 * lockedProgress, 0),
                child: Row(
                  children: [
                    _buildRecordingTimer(),
                    const SizedBox(width: 18),
                    _PulsingDot(second: _elapsedSeconds),
                    const SizedBox(width: 12),
                    const Flexible(
                      fit: FlexFit.tight,
                      child: Text(
                        'Slide to cancel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WrytteColors.textMuted,
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 16,
                          height: 1,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _LoopingTranslation(
                      begin: const Offset(2, 0),
                      end: const Offset(-2, 0),
                      duration: const Duration(milliseconds: 650),
                      child: wrytteSvgAssetIcon(
                        assetPath: 'assets/svg/Arrow voice area.svg',
                        canvas: 17,
                        scale: 1.12,
                        color: WrytteColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Opacity(
              opacity: lockedProgress,
              child: Transform.translate(
                offset: Offset(10 * (1 - lockedProgress), 0),
                child: _cameraMode
                    ? _buildLockedVideoRecordingStatus()
                    : Row(
                        children: [
                          _buildRecordingTimer(),
                          const SizedBox(width: 12),
                          _PulsingDot(second: _elapsedSeconds),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ValueListenableBuilder<List<double>>(
                              valueListenable: _recordingLevelsNotifier,
                              builder: (context, levels, child) =>
                                  _LiveRecordingWaveform(levels: levels),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingTimer() {
    return Text(
      _timerLabel,
      style: const TextStyle(
        color: WrytteColors.textPrimary,
        fontFamily: WrytteTypography.primaryFontFamily,
        fontSize: 17,
        height: 1,
        fontWeight: FontWeight.w400,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _glassPill({
    Key? key,
    required double width,
    required double height,
    required Widget child,
    VoidCallback? onTap,
    BoxDecoration? decoration,
  }) {
    final surface = Container(
      width: width,
      height: height,
      decoration: decoration ?? wrytteGlassDecoration(radius: height / 2),
      child: Center(child: child),
    );
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: _wrapComposerBackdrop(
          keyboardInset: _currentKeyboardInset(),
          child: surface,
        ),
      ),
    );
  }

  Widget _wrapComposerBackdrop({
    required double keyboardInset,
    required Widget child,
  }) {
    if (keyboardInset > 0) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: child,
    );
  }
}
