part of '../../screens/chats/chat_screen.dart';

class _ForwardTarget {
  final String? conversationId;
  final String receiverId;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final String? phone;
  final bool isSavedContact;
  final int sortOrder;

  const _ForwardTarget({
    this.conversationId,
    required this.receiverId,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.phone,
    this.isSavedContact = false,
    this.sortOrder = 0,
  });

  _ForwardTarget copyWith({
    String? conversationId,
    String? receiverId,
    String? subtitle,
    String? avatarUrl,
    int? sortOrder,
  }) {
    return _ForwardTarget(
      conversationId: conversationId ?? this.conversationId,
      receiverId: receiverId ?? this.receiverId,
      title: title,
      subtitle: subtitle ?? this.subtitle,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone,
      isSavedContact: isSavedContact,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class _SharedContactData {
  final String name;
  final String phone;
  final String? avatarUrl;
  final String? userId;

  const _SharedContactData({
    required this.name,
    required this.phone,
    this.avatarUrl,
    this.userId,
  });
}

class _ForwardPickerPage extends StatefulWidget {
  final List<_ForwardTarget> targets;
  final String previewText;
  final String? previewAvatarUrl;

  const _ForwardPickerPage({
    required this.targets,
    required this.previewText,
    this.previewAvatarUrl,
  });

  @override
  State<_ForwardPickerPage> createState() => _ForwardPickerPageState();
}

class _ForwardPickerPageState extends State<_ForwardPickerPage> {
  final Set<String> _selectedReceiverIds = {};

  List<_ForwardTarget> get _selectedTargets =>
      widget.targets
          .where((target) => _selectedReceiverIds.contains(target.receiverId))
          .toList();

  void _toggle(_ForwardTarget target) {
    setState(() {
      if (!_selectedReceiverIds.add(target.receiverId)) {
        _selectedReceiverIds.remove(target.receiverId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final savedTargets =
        widget.targets.where((target) => target.isSavedContact).toList();
    final recentTargets =
        widget.targets.where((target) => !target.isSavedContact).toList();
    final selectedTargets = _selectedTargets;

    return Scaffold(
      backgroundColor: WrytteColors.background,
      appBar: AppBar(
        backgroundColor: WrytteColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Forward to...',
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
            if (selectedTargets.isNotEmpty)
              Text(
                '${selectedTargets.length} selected',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 13,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                children: [
                  if (savedTargets.isNotEmpty) ...[
                    _sectionHeader('Frequently contacted'),
                    for (final target in savedTargets) _targetTile(target),
                  ],
                  if (recentTargets.isNotEmpty) ...[
                    _sectionHeader('Recent chats'),
                    for (final target in recentTargets) _targetTile(target),
                  ],
                ],
              ),
            ),
            if (selectedTargets.isNotEmpty) _bottomBar(selectedTargets),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.48),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _targetTile(_ForwardTarget target) {
    final selected = _selectedReceiverIds.contains(target.receiverId);
    final subtitle = target.subtitle?.trim() ?? '';

    return InkWell(
      onTap: () => _toggle(target),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              imageUrl: target.avatarUrl,
              cacheIdentity: 'user:${target.receiverId.trim().toLowerCase()}',
              name: target.title,
              size: 54,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.48),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? WrytteColors.success : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected
                          ? WrytteColors.success
                          : Colors.white.withOpacity(0.42),
                  width: 2,
                ),
              ),
              child:
                  selected
                      ? const Icon(Icons.check, color: Colors.black, size: 19)
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(List<_ForwardTarget> selectedTargets) {
    final names = selectedTargets.map((target) => target.title).join(', ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF101318),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 54,
              height: 54,
              color: const Color(0xFF1B2028),
              child:
                  widget.previewAvatarUrl?.isNotEmpty == true
                      ? Image.network(
                        widget.previewAvatarUrl!,
                        fit: BoxFit.cover,
                      )
                      : const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.white54,
                      ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.56),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  names,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'forward-send',
            mini: false,
            backgroundColor: WrytteColors.success,
            foregroundColor: Colors.black,
            onPressed: () => Navigator.pop(context, selectedTargets),
            child: const Icon(Icons.send, size: 28),
          ),
        ],
      ),
    );
  }
}
