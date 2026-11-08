class ChatLocationSelection {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final bool isCurrentPosition;

  const ChatLocationSelection({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isCurrentPosition,
  });
}
