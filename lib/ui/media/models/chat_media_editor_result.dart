class ChatMediaEditorResult {
  const ChatMediaEditorResult({
    this.assetId = '',
    this.originalFilePath = '',
    this.editedFilePath,
    this.caption,
    this.durationSeconds,
    this.selected = true,
    this.sendNow = false,
    this.currentMediaId,
    this.selectedMediaIds,
    this.editedMediaPaths = const <String, String>{},
  });

  final String assetId;
  final String originalFilePath;
  final String? editedFilePath;
  final String? caption;
  final int? durationSeconds;

  // Compatibility fields used by the legacy multi-media editor.
  final bool selected;
  final bool sendNow;
  final String? currentMediaId;
  final List<String>? selectedMediaIds;
  final Map<String, String> editedMediaPaths;

  bool get wasEdited => editedFilePath != null;
}
