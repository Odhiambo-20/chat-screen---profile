part of '../../../screens/chats/chat_screen.dart';

extension _ChatAudioPlayerSurfaces on _ChatScreenState {
  String _formatAudioPlayerTime(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999).toInt();
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Widget _buildExpandedAudioFallbackArtwork() {
    return ColoredBox(
      color: WrytteColors.textPrimary,
      child: Center(
        child: wrytteSvgAssetIcon(
          assetPath: 'assets/svg/Audio icon.svg',
          canvas: 31,
          color: WrytteColors.primary,
          offset: const Offset(-1.5, -0.8),
        ),
      ),
    );
  }

  Widget _buildExpandedAudioArtwork(FileAudioPlaybackUiState playback) {
    final source = playback.artworkUrl?.trim() ?? '';
    if (source.isEmpty) {
      return _buildExpandedAudioFallbackArtwork();
    }
    final uri = Uri.tryParse(source);
    final isRemote =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mxc');
    if (isRemote) {
      return WryttePersistentImage(
        source: source,
        fit: BoxFit.cover,
        errorWidget: _buildExpandedAudioFallbackArtwork(),
      );
    }
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder:
          (context, error, stackTrace) => _buildExpandedAudioFallbackArtwork(),
    );
  }

  Future<void> _createLocalAudioPlaylist(
    BuildContext sheetContext,
    FileAudioPlaybackUiState playback,
  ) async {
    Navigator.of(sheetContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    final selected = await _attachmentController.openAudioPlaylistPicker();
    if (!mounted || selected == null || selected.isEmpty) return;

    final items = <LocalAudioPlaylistItem>[];
    for (final attachment in selected) {
      final path = attachment.filePath.trim();
      var byteSize = 0;
      try {
        final file = File(path);
        if (await file.exists()) byteSize = await file.length();
      } catch (_) {}
      final suppliedTitle = attachment.audioTitle?.trim() ?? '';
      items.add(
        LocalAudioPlaylistItem(
          filePath: path,
          title:
              suppliedTitle.isNotEmpty
                  ? suppliedTitle
                  : p.basenameWithoutExtension(path),
          artist: attachment.audioArtist?.trim(),
          artworkPath: attachment.audioArtworkPath?.trim(),
          durationSeconds: attachment.audioDurationSeconds ?? 0,
          byteSize: byteSize,
        ),
      );
    }
    final playlist = await AudioPlaylistStore.instance.create(
      conversationId: widget.conversationId,
      items: items,
    );
    if (!mounted) return;
    _setChatState(() {
      _localAudioPlaylists = <LocalAudioPlaylist>[
        playlist,
        ..._localAudioPlaylists.where((entry) => entry.id != playlist.id),
      ];
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (mounted) await _showExpandedFileAudioPlayer(playback);
  }

  Future<void> _showExpandedFileAudioPlayer(
    FileAudioPlaybackUiState playback,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder:
          (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: wrytteGlassDecoration(radius: 30).copyWith(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      8,
                      24,
                      14 + MediaQuery.paddingOf(sheetContext).bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF2F2F2,
                            ).withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ClipOval(
                              child: SizedBox.square(
                                dimension: 54,
                                child: _buildExpandedAudioArtwork(playback),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    playback.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: WrytteColors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (playback.artist?.trim().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      playback.artist!.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF9B9DA3),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Share',
                              onPressed: () {},
                              icon: wrytteSvgAssetIcon(
                                assetPath: 'assets/svg/Share via icon.svg',
                                canvas: 23,
                                color: WrytteColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<Duration>(
                          valueListenable: playback.duration,
                          builder:
                              (
                                context,
                                duration,
                                child,
                              ) => ValueListenableBuilder<double>(
                                valueListenable: playback.progress,
                                builder: (context, progress, child) {
                                  final value =
                                      progress.clamp(0.0, 1.0).toDouble();
                                  final elapsed = Duration(
                                    milliseconds:
                                        (duration.inMilliseconds * value)
                                            .round(),
                                  );
                                  return Column(
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 4,
                                          activeTrackColor: const Color(
                                            0xFFF2F2F2,
                                          ),
                                          inactiveTrackColor: const Color(
                                            0xFFF2F2F2,
                                          ).withValues(alpha: 0.34),
                                          thumbShape:
                                              SliderComponentShape.noThumb,
                                          overlayShape:
                                              SliderComponentShape.noOverlay,
                                        ),
                                        child: Slider(
                                          value: value,
                                          onChanged:
                                              (next) => unawaited(
                                                playback.seek(next),
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatAudioPlayerTime(elapsed),
                                              style: const TextStyle(
                                                color: Color(0xFF9B9DA3),
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              _formatAudioPlayerTime(duration),
                                              style: const TextStyle(
                                                color: Color(0xFF9B9DA3),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const SizedBox(width: 9),
                            wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Shuffle icon .svg',
                              canvas: 27,
                              color: WrytteColors.textPrimary,
                            ),
                            const Spacer(),
                            Transform.rotate(
                              angle: math.pi,
                              child: wrytteSvgAssetIcon(
                                assetPath: 'assets/svg/Skip audio icon.svg',
                                canvas: 28,
                                color: WrytteColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ValueListenableBuilder<bool>(
                              valueListenable: playback.playing,
                              builder:
                                  (context, playing, child) => SizedBox.square(
                                    dimension: 60,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      onPressed:
                                          () => unawaited(
                                            playback.togglePlayback(),
                                          ),
                                      icon: Icon(
                                        playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: WrytteColors.textPrimary,
                                        size: 54,
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(width: 12),
                            wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Skip audio icon.svg',
                              canvas: 28,
                              color: WrytteColors.textPrimary,
                            ),
                            const Spacer(),
                            wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Repeat audio icon.svg',
                              canvas: 27,
                              color: WrytteColors.textPrimary,
                            ),
                            const SizedBox(width: 9),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: FilledButton.icon(
                              onPressed:
                                  () => unawaited(
                                    _createLocalAudioPlaylist(
                                      sheetContext,
                                      playback,
                                    ),
                                  ),
                              style: FilledButton.styleFrom(
                                backgroundColor: WrytteColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(21),
                                ),
                              ),
                              icon: wrytteSvgAssetIcon(
                                assetPath:
                                    'assets/svg/Create playlist icon.svg',
                                canvas: 19,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Add to playlist',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildFileAudioPlayerStrip(
    FileAudioPlaybackUiState playback, {
    bool embedded = false,
  }) {
    final player = SizedBox(
      height: 50,
      child: Stack(
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 50,
                child: ValueListenableBuilder<bool>(
                  valueListenable: playback.playing,
                  builder:
                      (context, playing, child) => IconButton(
                        onPressed: () => unawaited(playback.togglePlayback()),
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: WrytteColors.textPrimary,
                          size: 29,
                        ),
                      ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      () => unawaited(_showExpandedFileAudioPlayer(playback)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        playback.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: WrytteColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                      ),
                      if (playback.artist?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 3),
                        Text(
                          playback.artist!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF9B9DA3),
                            fontSize: 14,
                            height: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox.square(
                dimension: 50,
                child: IconButton(
                  onPressed: () => unawaited(playback.close()),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: WrytteColors.textPrimary,
                    size: 27,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 0,
            height: 2,
            child: ValueListenableBuilder<double>(
              valueListenable: playback.progress,
              builder: (context, progress, child) {
                final value = progress.clamp(0.0, 1.0).toDouble();
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    child: SizedBox(
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: WrytteColors.textPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (embedded) return player;
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: wrytteGlassDecoration(radius: 28),
            child: player,
          ),
        ),
      ),
    );
  }

  Widget _buildJoinedPinnedAudioSurface({
    required List<String> pinnedEventIds,
    required String pinnedStripSignature,
    required FileAudioPlaybackUiState playback,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: wrytteGlassDecoration(radius: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PinnedEventsStrip(
                  pinnedEventIds: pinnedEventIds,
                  events: _messages,
                  embedded: true,
                  onOpenEvent: (eventId) {
                    unawaited(_openPinnedMessage(eventId));
                  },
                  onDismiss: () {
                    _setChatState(
                      () =>
                          _dismissedPinnedStripSignature = pinnedStripSignature,
                    );
                  },
                  onOpenList: () {
                    unawaited(_openPinnedMessagesPage(pinnedEventIds));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: ColoredBox(
                    color: const Color(0xFF777A82).withValues(alpha: 0.72),
                    child: const SizedBox(width: double.infinity, height: 1),
                  ),
                ),
                _buildFileAudioPlayerStrip(playback, embedded: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
