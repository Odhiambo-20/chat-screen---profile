import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wrytte/data/repositories/audio_recording_repository_impl.dart';
import 'package:wrytte/data/repositories/camera_repository_impl.dart';
import 'package:wrytte/data/services/camera_capabilities_service.dart';
import 'package:wrytte/data/services/camera_session_manager.dart';
import 'package:wrytte/data/services/device_audio_recording_service.dart';
import 'package:wrytte/data/services/device_camera_service.dart';
import 'package:wrytte/domain/repositories/audio_recording_repository.dart';
import 'package:wrytte/domain/repositories/camera_repository.dart';
import 'package:wrytte/ui/chat/view_models/chat_record_mode.dart';
import 'package:wrytte/ui/chat/widgets/chat_composer.dart';
import 'package:wrytte/ui/widgets/chats/composer/migrated_chat_attachment_launcher.dart';

/// Compatibility boundary between the legacy chat model and the current
/// Wrytte composer/recording/attachment implementation.
///
/// Recorder and camera ownership intentionally live here instead of in the
/// legacy 5,000-line input widget. The old screen keeps its send callbacks and
/// message model; interaction, keyboard retention, trimming and round-video UI
/// come directly from the current implementation.
class MigratedMessageInputField extends StatefulWidget {
  const MigratedMessageInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.replySender,
    this.replyPreview,
    this.onCancelReply,
    this.isEditing = false,
    this.onCancelEdit,
    this.editingMediaSource,
    this.editingMediaType,
    this.onReplaceEditingMedia,
    this.onVoiceMessage,
    this.onVideoMessageRecorded,
    this.onPickedAttachments,
    this.onPickedContacts,
    this.attachmentRecipientLabel = 'Recipient',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final String? replySender;
  final String? replyPreview;
  final VoidCallback? onCancelReply;
  final bool isEditing;
  final VoidCallback? onCancelEdit;
  final String? editingMediaSource;
  final String? editingMediaType;
  final Future<void> Function()? onReplaceEditingMedia;
  final Future<void> Function(String path, int durationSeconds)? onVoiceMessage;
  final Future<void> Function(String path, int durationSeconds)?
  onVideoMessageRecorded;
  final Future<void> Function(
    List<ChatPickedAttachment> media, {
    String? caption,
  })?
  onPickedAttachments;
  final Future<void> Function(List<Contact> contacts, {String? caption})?
  onPickedContacts;
  final String attachmentRecipientLabel;

  @override
  State<MigratedMessageInputField> createState() =>
      _MigratedMessageInputFieldState();
}

class _MigratedMessageInputFieldState extends State<MigratedMessageInputField> {
  late final DeviceAudioRecordingService _audioService;
  late final AudioRecordingRepository _audioRepository;
  late final DeviceCameraService _cameraService;
  late final CameraSessionManager _cameraSessionManager;
  late final CameraRepository _cameraRepository;
  ChatRecordMode _recordMode = ChatRecordMode.audio;
  bool _attachmentOpening = false;

  @override
  void initState() {
    super.initState();
    _audioService = DeviceAudioRecordingService();
    _audioRepository = AudioRecordingRepositoryImpl(_audioService);
    _cameraService = DeviceCameraService();
    _cameraSessionManager = CameraSessionManager();
    _cameraRepository = CameraRepositoryImpl(
      _cameraService,
      const CameraCapabilitiesService(),
      _cameraSessionManager,
    );
  }

  @override
  void dispose() {
    unawaited(_audioRepository.dispose());
    unawaited(_cameraRepository.close());
    super.dispose();
  }

  Future<void> _openAttachments(
    BuildContext providerContext,
    Rect? sourceRect,
  ) async {
    if (_attachmentOpening) return;
    _attachmentOpening = true;
    try {
      final result = await showLegacyChatAttachmentPanel(
        context: providerContext,
        recipientLabel: widget.attachmentRecipientLabel,
        sourceRect: sourceRect,
      );
      if (!mounted || result == null) return;
      if (result.media.isNotEmpty) {
        await widget.onPickedAttachments?.call(
          result.media,
          caption: result.caption,
        );
      } else if (result.contacts.isNotEmpty) {
        await widget.onPickedContacts?.call(
          result.contacts,
          caption: result.caption,
        );
      }
    } finally {
      _attachmentOpening = false;
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AudioRecordingRepository>.value(value: _audioRepository),
        Provider<CameraRepository>.value(value: _cameraRepository),
      ],
      child: Builder(
        builder: (providerContext) => ChatComposer(
          controller: widget.controller,
          focusNode: widget.focusNode,
          recordMode: _recordMode,
          onSend: (_) => widget.onSend(),
          onToggleRecordMode: () => setState(() {
            _recordMode = _recordMode == ChatRecordMode.audio
                ? ChatRecordMode.video
                : ChatRecordMode.audio;
          }),
          onAttachmentPressed: (sourceRect) =>
              _openAttachments(providerContext, sourceRect),
          onExpressPressed: () {},
          replySender: widget.replySender,
          replyPreview: widget.replyPreview,
          onCancelReply: widget.onCancelReply,
          isEditing: widget.isEditing,
          editingMediaSource: widget.editingMediaSource,
          editingMediaType: widget.editingMediaType,
          onCancelEdit: widget.onCancelEdit,
          onReplaceEditingMedia: widget.onReplaceEditingMedia,
          onVoiceRecorded: (recording) => widget.onVoiceMessage?.call(
            recording.path,
            recording.trimRange.duration.inSeconds.clamp(1, 3600),
          ),
          onRoundVideoRecorded: (recording) =>
              widget.onVideoMessageRecorded?.call(
                recording.path,
                (recording.duration ?? const Duration(seconds: 1)).inSeconds
                    .clamp(1, 60),
              ),
          onRecordingFailure: _showFailure,
        ),
      ),
    );
  }
}
