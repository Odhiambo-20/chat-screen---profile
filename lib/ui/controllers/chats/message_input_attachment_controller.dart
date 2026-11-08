import 'package:wrytte/models/chat_models/ui/chat_attachment_models.dart';

/// Small bridge used by the chat screen to invoke composer-owned pickers.
///
/// Camera, recorder and picker state remain owned by their widgets; this
/// controller only exposes commands and never owns platform resources.
class MessageInputAttachmentController {
  Future<void> Function()? _openAudioPicker;
  Future<List<ChatPickedAttachment>?> Function()? _openAudioPlaylistPicker;

  Future<void> openAudioPicker() async => _openAudioPicker?.call();

  Future<List<ChatPickedAttachment>?> openAudioPlaylistPicker() async =>
      _openAudioPlaylistPicker?.call();

  void attach({
    required Future<void> Function() openAudioPicker,
    required Future<List<ChatPickedAttachment>?> Function()
    openAudioPlaylistPicker,
  }) {
    _openAudioPicker = openAudioPicker;
    _openAudioPlaylistPicker = openAudioPlaylistPicker;
  }

  void detach() {
    _openAudioPicker = null;
    _openAudioPlaylistPicker = null;
  }
}
