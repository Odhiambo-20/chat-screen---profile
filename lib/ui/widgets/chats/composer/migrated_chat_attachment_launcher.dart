import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as device_contacts;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:wrytte/domain/models/camera_capture_result.dart';
import 'package:wrytte/domain/models/camera_session_config.dart';
import 'package:wrytte/domain/repositories/camera_repository.dart';
import 'package:wrytte/models/chat_models/ui/chat_attachment_models.dart';
import 'package:wrytte/models/contact_model.dart';
import 'package:wrytte/services/audio/audio_file_metadata_service.dart';
import 'package:wrytte/services/permissions/photo_library_permission_service.dart';
import 'package:wrytte/ui/auth/profile_photo_crop_page.dart';
import 'package:wrytte/ui/camera/models/camera_route_result.dart';
import 'package:wrytte/ui/camera/views/wrytte_camera_route.dart';
import 'package:wrytte/ui/camera/widgets/attachment_camera_preview.dart';
import 'package:wrytte/ui/core/models/expanding_surface_origin.dart';
import 'package:wrytte/ui/core/routing/expanding_surface_route.dart';
import 'package:wrytte/ui/screens/chats/chat_media_editor.dart';
import 'package:wrytte/ui/screens/media/full_screen_image_viewer.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/ui/widgets/chats/attachments/chat_location_picker.dart';
import 'package:wrytte/ui/widgets/global/avatars/user_avatar.dart';

export 'package:wrytte/models/chat_models/ui/chat_attachment_models.dart';
export 'package:wrytte/models/contact_model.dart';

part '../attachments/migrated_telegram_attachment_panel.dart';

enum _AttachmentAction { camera, gallery, file }

const Duration _attachmentPanelTransitionDuration = Duration(milliseconds: 280);

Widget _attachmentPanelPlusTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
  Rect? sourceRect,
) {
  // Preserve the original Wrytte plus-panel route motion. The attachment
  // surface owns its opening expansion; route dismissal is only a short
  // downward slide, with no route-level fade or scale.
  if (animation.status != AnimationStatus.reverse) return child;
  final position = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInCubic));
  return SlideTransition(position: position, child: child);
}

class _RecentAttachmentFile {
  const _RecentAttachmentFile({
    required this.path,
    required this.name,
    required this.attachmentType,
    required this.size,
    required this.extension,
  });

  final String path;
  final String name;
  final String attachmentType;
  final int size;
  final String extension;
}

class _FileBadgePainter extends CustomPainter {
  const _FileBadgePainter(this.color);

  final Color color;

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

class _AttachmentSelection {
  const _AttachmentSelection.action(
    _AttachmentAction this.action, {
    this.cameraSourceRect,
    this.cameraGalleryThumbnail,
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
       cameraSourceRect = null,
       cameraGalleryThumbnail = null;

  const _AttachmentSelection.contacts({required this.contacts, this.caption})
    : action = null,
      media = const <ChatPickedAttachment>[],
      cameraSourceRect = null,
      cameraGalleryThumbnail = null,
      profilePhotoAlreadyCropped = false;

  final _AttachmentAction? action;
  final List<ChatPickedAttachment> media;
  final List<Contact> contacts;
  final String? caption;
  final Rect? cameraSourceRect;
  final Uint8List? cameraGalleryThumbnail;
  final bool profilePhotoAlreadyCropped;
}

/// Chat-facing result from the migrated old attachment stack.
class LegacyChatAttachmentResult {
  const LegacyChatAttachmentResult({
    required this.media,
    required this.contacts,
    this.caption,
  });

  final List<ChatPickedAttachment> media;
  final List<Contact> contacts;
  final String? caption;
}

Future<void> _openCameraAboveLegacyAttachment({
  required BuildContext panelContext,
  required _AttachmentSelection selection,
  required String recipientLabel,
  required CameraRepository cameraRepository,
  required ValueNotifier<bool> fullScreenCameraOpen,
}) async {
  const cameraConfig = CameraSessionConfig.chatAttachment();
  final sourceRect = selection.cameraSourceRect;
  final origin = sourceRect == null
      ? null
      : ExpandingSurfaceOrigin(
          rect: sourceRect,
          borderRadius: BorderRadius.zero,
        );
  String? reviewedCaption;

  fullScreenCameraOpen.value = true;
  CameraRouteResult? result;
  try {
    result = await showWrytteCamera(
      panelContext,
      repository: cameraRepository,
      config: cameraConfig,
      origin: origin,
      galleryThumbnail: selection.cameraGalleryThumbnail,
      returnToGallery: true,
      keepSessionAliveOnExit: true,
      captureReviewer: (cameraContext, capture) async {
        try {
          await cameraRepository.pausePreview();
        } catch (_) {
          // Some Android camera implementations cannot pause a preview. The
          // editor still safely covers the retained shared session.
        }
        if (!cameraContext.mounted) return null;

        final editorRoute = ExpandingSurfaceRoute<ChatMediaEditorResult>(
          animationsDisabled: MediaQuery.disableAnimationsOf(cameraContext),
          keepUnderlyingVisible: true,
          builder: (context, animation) => ChatMediaEditorScreen(
            sourcePath: capture.path,
            attachmentType: capture.type == CameraMediaType.video
                ? 'video'
                : 'image',
            recipientLabel: recipientLabel,
            initialCaption: '',
            selectionIndex: null,
            selectedCount: 0,
            showSelectionControl: false,
            openedFromCamera: true,
          ),
        );
        final editorResult = await Navigator.of(
          cameraContext,
          rootNavigator: true,
        ).push(editorRoute);
        await editorRoute.completed;

        if (editorResult?.sendNow != true) {
          try {
            final file = File(capture.path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
          try {
            await cameraRepository.resumePreview();
          } catch (_) {}
          return null;
        }

        reviewedCaption = editorResult!.caption;
        final editedPath = editorResult.editedFilePath?.trim();
        return CameraCaptureResult(
          path: editedPath?.isNotEmpty == true ? editedPath! : capture.path,
          type: capture.type,
          capturedAt: capture.capturedAt,
          cameraId: capture.cameraId,
          zoom: capture.zoom,
          duration: capture.duration,
        );
      },
    );
  } finally {
    fullScreenCameraOpen.value = false;
  }

  if (!panelContext.mounted || result == null) return;
  if (result.action == CameraRouteAction.returnToGallery) return;
  final capture = result.capture;
  if (capture == null || capture.path.trim().isEmpty) return;

  Navigator.of(panelContext).pop<_AttachmentSelection>(
    _AttachmentSelection.media(
      caption: reviewedCaption,
      media: <ChatPickedAttachment>[
        ChatPickedAttachment(
          filePath: capture.path,
          attachmentType: capture.type == CameraMediaType.video
              ? 'video'
              : 'image',
        ),
      ],
    ),
  );
}

/// Opens the old Wrytte chat attachment panel and its original editor/camera
/// stack. Profile setup deliberately continues using the new shared picker.
Future<LegacyChatAttachmentResult?> showLegacyChatAttachmentPanel({
  required BuildContext context,
  required String recipientLabel,
  bool initiallyExpanded = false,
  Rect? sourceRect,
}) async {
  final cameraRepository = context.read<CameraRepository>();
  final fullScreenCameraOpen = ValueNotifier<bool>(false);
  final selectionFuture = showGeneralDialog<_AttachmentSelection>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: _attachmentPanelTransitionDuration,
    pageBuilder: (panelContext, animation, secondaryAnimation) => Material(
      color: Colors.transparent,
      child: _TelegramAttachmentPanel(
        recipientLabel: recipientLabel,
        initiallyExpanded: initiallyExpanded,
        cameraRepository: cameraRepository,
        fullScreenCameraOpen: fullScreenCameraOpen,
        onCameraSelected: (selected) => _openCameraAboveLegacyAttachment(
          panelContext: panelContext,
          selection: selected,
          recipientLabel: recipientLabel,
          cameraRepository: cameraRepository,
          fullScreenCameraOpen: fullScreenCameraOpen,
        ),
        onSelected: (selected) {
          unawaited(HapticFeedback.selectionClick());
          Navigator.of(panelContext).pop(selected);
        },
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        _attachmentPanelPlusTransition(
          context,
          animation,
          secondaryAnimation,
          child,
          sourceRect,
        ),
  );

  _AttachmentSelection? selection;
  try {
    selection = await selectionFuture;
  } finally {
    await cameraRepository.close();
    fullScreenCameraOpen.dispose();
  }

  if (selection == null || !context.mounted) return null;
  if (selection.action == _AttachmentAction.gallery) {
    return showLegacyChatAttachmentPanel(
      context: context,
      recipientLabel: recipientLabel,
      initiallyExpanded: true,
      sourceRect: sourceRect,
    );
  }

  // Camera is handled above the still-mounted attachment dialog so Back and
  // the gallery shortcut return to the same panel and the same live session.
  if (selection.action == _AttachmentAction.camera) return null;

  return LegacyChatAttachmentResult(
    media: selection.media,
    contacts: selection.contacts,
    caption: selection.caption,
  );
}
