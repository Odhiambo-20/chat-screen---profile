part of '../../screens/chats/chat_screen.dart';

extension _ChatAudioPlaybackController on _ChatScreenState {
  Set<String> _voiceMessageOpenKeys(ChatMessage message) {
    final keys = <String>{};
    final messageId = message.id.trim();
    final conversationId = message.conversationId.trim();
    if (messageId.isNotEmpty) {
      keys.add('event|${widget.currentUserId}|$conversationId|$messageId');
    }

    // The same Matrix voice event can briefly be represented by different
    // local/conversation identifiers while chat data is reconciled. The media
    // identity remains stable across those hydrations and across restarts.
    final mediaUrl = message.attachmentUrl?.trim() ?? '';
    if (mediaUrl.isNotEmpty) {
      keys.add(
        'media|${widget.currentUserId}|${message.senderId}|'
        '${message.timestamp.toUtc().microsecondsSinceEpoch}|$mediaUrl',
      );
    }
    return keys;
  }

  String _voicePlaybackKey(ChatMessage message) {
    final messageId = message.id.trim();
    if (messageId.isNotEmpty) {
      return '${message.conversationId}|$messageId';
    }
    final persistedKeys = _voiceMessageOpenKeys(message);
    if (persistedKeys.isNotEmpty) return persistedKeys.first;
    return '${message.senderId}|${message.timestamp.microsecondsSinceEpoch}';
  }

  Future<void> _loadOpenedVoiceMessageKeys() async {
    final loadFuture =
        _openedVoiceMessageLoadFuture ??= _readOpenedVoiceMessageKeys();
    await loadFuture;
    if (!mounted || _disposing) return;
    _setChatState(() => _openedVoiceMessageStateReady = true);
  }

  Future<void> _readOpenedVoiceMessageKeys() async {
    try {
      final storedKeys =
          await ChatLocalDb.instance.loadOpenedVoiceMessageKeys();
      _openedVoiceMessageKeys.addAll(storedKeys);
    } catch (error) {
      debugPrint(
        '[ChatScreen] Could not restore opened voice messages: $error',
      );
    }
  }

  Future<void> _persistOpenedVoiceMessageKeys(Set<String> newKeys) {
    final previousWrite = _openedVoiceMessageWriteQueue;
    final nextWrite = () async {
      try {
        await previousWrite;
      } catch (_) {
        // A failed write must not prevent later opened messages from saving.
      }
      final loadFuture = _openedVoiceMessageLoadFuture;
      if (loadFuture != null) {
        await loadFuture;
      }
      await ChatLocalDb.instance.markVoiceMessagesOpened(newKeys);
    }();
    _openedVoiceMessageWriteQueue = nextWrite;
    return nextWrite;
  }

  bool _isVoiceMessageOpened(ChatMessage message) {
    if (_isMine(message)) return true;
    return _voiceMessageOpenKeys(message).any(_openedVoiceMessageKeys.contains);
  }

  VoiceNotePlaybackController _voicePlaybackControllerFor(ChatMessage message) {
    final key = _voicePlaybackKey(message);
    return _voicePlaybackControllers.putIfAbsent(
      key,
      VoiceNotePlaybackController.new,
    );
  }

  Future<void> _markVoiceMessageOpened(ChatMessage message) async {
    if (_isMine(message) || !message.isVoiceNote || message.isDeleted) return;
    final newKeys =
        _voiceMessageOpenKeys(
          message,
        ).where((key) => !_openedVoiceMessageKeys.contains(key)).toSet();
    if (newKeys.isEmpty) return;
    _openedVoiceMessageKeys.addAll(newKeys);
    if (mounted) _setChatState(() {});
    try {
      await _persistOpenedVoiceMessageKeys(newKeys);
    } catch (error) {
      debugPrint('[ChatScreen] Could not persist opened voice message: $error');
    }
  }

  void _handleVoicePlaybackStarted(ChatMessage message) {
    if (!mounted || _disposing) return;
    final nextKey = _voicePlaybackKey(message);
    final previousKey = _activeVoicePlaybackKey;
    _activeVoicePlaybackKey = nextKey;

    if (previousKey == null || previousKey == nextKey) return;
    final previousController = _voicePlaybackControllers[previousKey];
    if (previousController != null) {
      unawaited(previousController.pause());
    }
  }

  void _handleFileAudioPlaybackChanged(
    ChatMessage message,
    FileAudioPlaybackUiState? playback,
  ) {
    if (!mounted || _disposing) return;
    if (playback == null) {
      if (_activeFileAudioMessageId == message.id) {
        _setChatState(() {
          _activeFileAudioPlayback = null;
          _activeFileAudioMessageId = null;
        });
      }
      return;
    }
    final previousPlayback = _activeFileAudioPlayback;
    final previousMessageId = _activeFileAudioMessageId;
    _setChatState(() {
      _activeFileAudioPlayback = playback;
      _activeFileAudioMessageId = message.id;
    });
    if (previousPlayback != null && previousMessageId != message.id) {
      unawaited(previousPlayback.close());
    }
  }

  Future<void> _handleVoicePlaybackCompleted(ChatMessage message) async {
    if (!mounted || _disposing) return;
    final completedKey = _voicePlaybackKey(message);
    if (_activeVoicePlaybackKey != completedKey) return;
    _activeVoicePlaybackKey = null;

    var currentIndex = _messages.indexWhere(
      (candidate) => candidate.id == message.id,
    );
    currentIndex =
        currentIndex >= 0
            ? currentIndex
            : _messages.indexWhere(
              (candidate) =>
                  candidate.isVoiceNote &&
                  candidate.senderId == message.senderId &&
                  candidate.attachmentUrl == message.attachmentUrl &&
                  candidate.timestamp == message.timestamp,
            );
    if (currentIndex < 0 || currentIndex + 1 >= _messages.length) return;

    // Autoplay is deliberately limited to the immediately following message.
    // Any text, image, video, file, deleted item, or other non-voice message
    // breaks the chain. Sender direction does not matter.
    final nextMessage = _messages[currentIndex + 1];
    if (!nextMessage.isVoiceNote ||
        nextMessage.isDeleted ||
        (nextMessage.attachmentUrl?.trim().isEmpty ?? true)) {
      return;
    }

    final nextKey = _voicePlaybackKey(nextMessage);
    final controller = _voicePlaybackControllerFor(nextMessage);
    _activeVoicePlaybackKey = nextKey;
    try {
      await controller.play();
    } catch (_) {
      if (_activeVoicePlaybackKey == nextKey) {
        _activeVoicePlaybackKey = null;
      }
    }
  }
}
