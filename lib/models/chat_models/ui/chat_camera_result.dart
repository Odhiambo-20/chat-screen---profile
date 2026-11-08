enum ChatCameraMode { photo, video }

class ChatCameraResult {
  final String? filePath;
  final String? attachmentType;
  final String? caption;
  final bool openGallery;

  const ChatCameraResult._({
    this.filePath,
    this.attachmentType,
    this.caption,
    this.openGallery = false,
  });

  const ChatCameraResult.media({
    required String filePath,
    required String attachmentType,
    String? caption,
  }) : this._(
         filePath: filePath,
         attachmentType: attachmentType,
         caption: caption,
       );

  const ChatCameraResult.gallery() : this._(openGallery: true);
}
