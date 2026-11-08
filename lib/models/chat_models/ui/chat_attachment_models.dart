class ChatPickedAttachment {
  final String filePath;
  final String attachmentType;
  final int? width;
  final int? height;
  final String? audioTitle;
  final String? audioArtist;
  final String? audioArtworkPath;
  final int? audioDurationSeconds;

  const ChatPickedAttachment({
    required this.filePath,
    required this.attachmentType,
    this.width,
    this.height,
    this.audioTitle,
    this.audioArtist,
    this.audioArtworkPath,
    this.audioDurationSeconds,
  });
}

class ChatMediaReplacementSelection {
  final List<ChatPickedAttachment> media;
  final String caption;

  const ChatMediaReplacementSelection({
    required this.media,
    required this.caption,
  });
}
