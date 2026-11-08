part of 'conversations_screen.dart';

class _GroupExitUndoBanner extends StatelessWidget {
  final GroupExitRequest request;
  final int secondsRemaining;
  final double progress;
  final VoidCallback onUndo;

  const _GroupExitUndoBanner({
    required this.request,
    required this.secondsRemaining,
    required this.progress,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1D1D21),
      elevation: 12,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                  Center(
                    child: Text(
                      '$secondsRemaining',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                request.type == GroupExitType.delete
                    ? 'You deleted the ${request.isChannel ? 'channel' : 'group'}.'
                    : 'You left the ${request.isChannel ? 'channel' : 'group'}.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onUndo,
              child: const Text(
                'Undo',
                style: TextStyle(color: Color(0xFF64B5F6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationsScrollBehavior extends ScrollBehavior {
  const _ConversationsScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _ConversationLoadingRow extends StatelessWidget {
  const _ConversationLoadingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: WrytteColors.surfaceRaised,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 18,
                  width: 120,
                  decoration: BoxDecoration(
                    color: WrytteColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 14,
                  width: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1D22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(
                  color: Color(0xFF2A2D34),
                  thickness: 0.5,
                  height: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
