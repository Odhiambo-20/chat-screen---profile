class ChatMediaEditorResult {
  final String? editedFilePath;
  final String caption;
  final bool selected;
  final bool sendNow;

  final String? currentMediaId;
  final List<String>? selectedMediaIds;
  final Map<String, String> editedMediaPaths;

  const ChatMediaEditorResult({
    required this.editedFilePath,
    required this.caption,
    required this.selected,
    required this.sendNow,
    this.currentMediaId,
    this.selectedMediaIds,
    this.editedMediaPaths = const <String, String>{},
  });
}
