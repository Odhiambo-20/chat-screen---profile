part of 'message_bubble.dart';

class _VoiceNoteGeometry {
  const _VoiceNoteGeometry._();

  // Shared bubble spacing for both black and blue voice messages.
  static const EdgeInsets noTailBubblePadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 4,
  );

  // Shared internal control geometry.
  static const double contentWidth = 266;
  static const double controlsHeight = 34;
  static const double playSlotWidth = 36;
  static const double playSlotHeight = 34;
  static const double playToWaveformGap = 9;
  static const double waveformHeight = 26;
  static const double microphoneCanvas = 22;
  static const double waveformToSpeedGap = 8;
  static const double speedHeight = 32;

  // Reserved outside the right edge of incoming voice bubbles. The reserved
  // width remains after playback starts, so the bubble never jumps sideways.
  static const double unopenedIndicatorReserve = 24;
  static const double unopenedIndicatorTouchWidth = 24;
  static const double unopenedIndicatorTouchHeight = 48;
  static const double unopenedIndicatorDiameter = 10;

  // Shared lower-row spacing. Timestamp and checkmark widgets are unchanged.
  static const double metadataTopGap = 3;
  static const double durationLeftInset = 45;
  static const double metadataRightInset = 8;
}

class _UnopenedVoiceIndicator extends StatelessWidget {
  final bool visible;
  final Color color;
  final VoidCallback onTap;

  const _UnopenedVoiceIndicator({
    required this.visible,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: visible,
      label: visible ? 'Unplayed voice message. Play audio' : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: visible ? onTap : null,
        child: SizedBox(
          width: _VoiceNoteGeometry.unopenedIndicatorTouchWidth,
          height: _VoiceNoteGeometry.unopenedIndicatorTouchHeight,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child:
                  visible
                      ? DecoratedBox(
                        key: const ValueKey('voice-message-unopened'),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(
                          dimension:
                              _VoiceNoteGeometry.unopenedIndicatorDiameter,
                        ),
                      )
                      : const SizedBox(key: ValueKey('voice-message-opened')),
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Voice note player â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//
// Renders a WhatsApp-style row:
//   [play/pause]  [waveform bars]  [elapsed / total]
//
// Uses flutter_sound FlutterSoundPlayer to stream from the CDN URL.

class _VoiceNotePlayer extends StatefulWidget {
  final String audioUrl;
  final int totalSeconds;
  final bool isMine;
  final bool isOpened;
  final bool isListened;
  final Widget timeWidget;
  final Future<void> Function()? onOpened;
  final VoidCallback? onListened;
  final VoidCallback? onPlaybackStarted;
  final VoidCallback? onPlaybackCompleted;
  final VoiceNotePlaybackController? playbackController;

  const _VoiceNotePlayer({
    required this.audioUrl,
    required this.totalSeconds,
    required this.isMine,
    required this.isOpened,
    required this.isListened,
    required this.timeWidget,
    this.onOpened,
    this.onListened,
    this.onPlaybackStarted,
    this.onPlaybackCompleted,
    this.playbackController,
  });

  @override
  State<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<_VoiceNotePlayer>
    with SingleTickerProviderStateMixin {
  static const List<int> _aacSampleRates = <int>[
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000,
    7350,
  ];

  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  late final AnimationController _playbackProgress;
  bool _playerReady = false;
  Future<void>? _playerOpenAttempt;
  bool _isPlaying = false;
  bool _playbackCompleted = false;
  bool _showsPlaybackSpeed = false;
  bool _isScrubbing = false;
  bool _resumeAfterScrub = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _pendingNativeSeekTarget;
  DateTime? _pendingNativeSeekStartedAt;
  DateTime? _lastAcceptedNativeProgressAt;
  double _playbackSpeed = VoiceNotePlaybackSettings.currentSpeed;
  bool _playWhenReady = false;
  StreamSubscription<PlaybackDisposition>? _playerSub;
  Future<void>? _scrubPauseFuture;
  Future<void> _speedUpdateQueue = Future<void>.value();
  bool _isDisposed = false;
  bool _listenedReported = false;

  @override
  void initState() {
    super.initState();
    _playbackProgress = AnimationController(vsync: this);
    VoiceNotePlaybackSettings.speed.addListener(_onGlobalPlaybackSpeedChanged);
    widget.playbackController?._attach(this);
  }

  @override
  void didUpdateWidget(covariant _VoiceNotePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playbackController, widget.playbackController)) {
      oldWidget.playbackController?._detach(this);
      widget.playbackController?._attach(this);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    VoiceNotePlaybackSettings.speed.removeListener(
      _onGlobalPlaybackSpeedChanged,
    );
    widget.playbackController?._detach(this);
    unawaited(_playerSub?.cancel());
    _playbackProgress.dispose();
    if (_playerReady) unawaited(_player.closePlayer());
    super.dispose();
  }

  void _onGlobalPlaybackSpeedChanged() {
    final next = VoiceNotePlaybackSettings.currentSpeed;
    if (_playbackSpeed == next) return;

    // The label is rebuilt directly by ValueListenableBuilder in every voice
    // bubble. This local value only drives playback timing and the native
    // player, so no full bubble setState is needed here.
    _playbackSpeed = next;

    if (_playerReady && _isPlaying) {
      final previousUpdate = _speedUpdateQueue;
      _speedUpdateQueue = () async {
        try {
          await previousUpdate;
          if (_isDisposed || !_playerReady || !_isPlaying) return;
          final latestSpeed = _playbackSpeed;
          await _player.setSpeed(latestSpeed);
          if (!_isDisposed && mounted && _isPlaying) {
            _animatePlaybackFromCurrentPosition();
          }
        } catch (_) {
          // A native speed failure must not poison subsequent speed changes.
        }
      }();
    }
  }

  int get _resolvedDurationMs {
    final declaredDurationMs =
        widget.totalSeconds * Duration.millisecondsPerSecond;
    if (declaredDurationMs > 0) return declaredDurationMs;
    return _duration.inMilliseconds;
  }

  void _expectNativePosition(Duration target) {
    _pendingNativeSeekTarget = target;
    _pendingNativeSeekStartedAt = DateTime.now();
    _lastAcceptedNativeProgressAt = null;
  }

  Duration? _acceptedNativePosition(Duration reported) {
    final now = DateTime.now();
    final pendingTarget = _pendingNativeSeekTarget;
    if (pendingTarget != null) {
      final seekStartedAt = _pendingNativeSeekStartedAt ?? now;
      final elapsedMs = now.difference(seekStartedAt).inMilliseconds;
      final allowedAdvanceMs = (elapsedMs * _playbackSpeed).round() + 750;
      final lowerBound = pendingTarget - const Duration(milliseconds: 400);
      final safeLowerBound = lowerBound.isNegative ? Duration.zero : lowerBound;
      final upperBound =
          pendingTarget + Duration(milliseconds: allowedAdvanceMs);
      if (reported < safeLowerBound || reported > upperBound) return null;
      _pendingNativeSeekTarget = null;
      _pendingNativeSeekStartedAt = null;
    }

    // Flutter Sound reports the absolute current position. Ignore occasional
    // stale/regressive events and impossible forward spikes.
    if (reported + const Duration(milliseconds: 250) < _position) return null;
    final previousEventAt = _lastAcceptedNativeProgressAt;
    if (previousEventAt != null) {
      final elapsedMs = now.difference(previousEventAt).inMilliseconds;
      final maximumAdvance = Duration(
        milliseconds: (elapsedMs * _playbackSpeed).round() + 600,
      );
      if (reported - _position > maximumAdvance) return null;
    }
    _lastAcceptedNativeProgressAt = now;
    return reported < _position ? _position : reported;
  }

  Future<Duration?> _measureAdtsDuration(File file) async {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    var cursor = 0;
    var elapsedMicros = 0.0;
    var frameCount = 0;
    while (cursor + 7 <= bytes.length) {
      final hasSync =
          bytes[cursor] == 0xFF && (bytes[cursor + 1] & 0xF0) == 0xF0;
      if (!hasSync) {
        cursor++;
        continue;
      }
      final sampleRateIndex = (bytes[cursor + 2] >> 2) & 0x0F;
      final frameLength =
          ((bytes[cursor + 3] & 0x03) << 11) |
          (bytes[cursor + 4] << 3) |
          ((bytes[cursor + 5] & 0xE0) >> 5);
      if (sampleRateIndex >= _aacSampleRates.length ||
          frameLength < 7 ||
          cursor + frameLength > bytes.length) {
        cursor++;
        continue;
      }
      final rawDataBlocks = bytes[cursor + 6] & 0x03;
      elapsedMicros +=
          (1024.0 * (rawDataBlocks + 1) * Duration.microsecondsPerSecond) /
          _aacSampleRates[sampleRateIndex];
      frameCount++;
      cursor += frameLength;
    }
    if (frameCount == 0) return null;
    return Duration(microseconds: elapsedMicros.round());
  }

  void _animatePlaybackFromCurrentPosition() {
    final durationMs = _resolvedDurationMs;
    if (durationMs <= 0) return;
    final reportedProgress =
        (_position.inMilliseconds / durationMs).clamp(0.0, 1.0).toDouble();
    if ((_playbackProgress.value - reportedProgress).abs() > 0.03) {
      _playbackProgress.value = reportedProgress;
    }
    final remainingFraction = 1 - _playbackProgress.value;
    final remainingPlaybackMs =
        ((durationMs * remainingFraction) / _playbackSpeed).round();
    _playbackProgress.animateTo(
      1,
      duration: Duration(milliseconds: remainingPlaybackMs.clamp(1, 1 << 31)),
      curve: Curves.linear,
    );
  }

  Future<void> _ensurePlayerReady() async {
    if (_playerReady || _isDisposed) return;
    final activeAttempt = _playerOpenAttempt;
    if (activeAttempt != null) {
      await activeAttempt;
      return;
    }

    late final Future<void> attempt;
    attempt = _openPlayerOnDemand();
    _playerOpenAttempt = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_playerOpenAttempt, attempt)) _playerOpenAttempt = null;
    }
  }

  Future<void> _openPlayerOnDemand() async {
    try {
      await _player.openPlayer();
      if (_isDisposed || !mounted) {
        await _player.closePlayer();
        return;
      }
      // Progress events update elapsed text and correct meaningful native drift.
      // The AnimationController remains the frame-rate source for the marker.
      await _player.setSubscriptionDuration(const Duration(milliseconds: 100));
      _playerSub = _player.onProgress?.listen((event) {
        if (!mounted) return;
        if (_isScrubbing || !_isPlaying) {
          if (event.duration > Duration.zero && event.duration != _duration) {
            setState(() => _duration = event.duration);
          }
          return;
        }
        final sessionPosition = _acceptedNativePosition(event.position);
        if (sessionPosition == null) return;
        final previousDurationMs = _resolvedDurationMs;
        final previousDisplayedSecond = _position.inSeconds;
        _position = sessionPosition;
        if (event.duration > Duration.zero) {
          _duration = event.duration;
        }
        final durationMs = _resolvedDurationMs;
        if (durationMs <= 0) return;
        final durationChanged = (durationMs - previousDurationMs).abs() > 250;
        if (durationChanged ||
            sessionPosition.inSeconds != previousDisplayedSecond) {
          setState(() {});
        }
        // Native events update elapsed text only. The marker has one timeline:
        // the frame-synced AnimationController started by playback/seek/speed.
        final animationStoppedBeforeEnd =
            !_playbackProgress.isAnimating && _playbackProgress.value < 0.999;
        if (_isPlaying && (durationChanged || animationStoppedBeforeEnd)) {
          _animatePlaybackFromCurrentPosition();
        }
      });
      if (_isDisposed || !mounted) {
        await _playerSub?.cancel();
        await _player.closePlayer();
        return;
      }
      setState(() => _playerReady = true);

      if (_playWhenReady) {
        _playWhenReady = false;
        unawaited(_playFromController());
      }
    } catch (error) {
      debugPrint('Voice-message player could not open: $error');
      _playWhenReady = false;
    }
  }

  void _beginScrub() {
    if (_resolvedDurationMs <= 0 || _isScrubbing) return;

    _playbackProgress.stop(canceled: false);
    _isScrubbing = true;
    _resumeAfterScrub = _isPlaying;

    if (_isPlaying && _playerReady) {
      setState(() => _isPlaying = false);
      _scrubPauseFuture = _player.pausePlayer();
    } else {
      _scrubPauseFuture = null;
    }
  }

  void _updateScrubBy(double deltaFraction) {
    if (!_isScrubbing || _resolvedDurationMs <= 0) return;

    final progress =
        (_playbackProgress.value + deltaFraction).clamp(0.0, 1.0).toDouble();
    final target = Duration(
      milliseconds: (_resolvedDurationMs * progress).round(),
    );
    _playbackProgress.value = progress;
    setState(() => _position = target);
  }

  Future<void> _finishScrub() async {
    if (!_isScrubbing || _resolvedDurationMs <= 0) return;

    final progress = _playbackProgress.value.clamp(0.0, 1.0).toDouble();
    final target = Duration(
      milliseconds: (_resolvedDurationMs * progress).round(),
    );
    final shouldResume = _resumeAfterScrub;

    try {
      final pauseFuture = _scrubPauseFuture;
      if (pauseFuture != null) await pauseFuture;
      if (_playerReady && (_player.isPlaying || _player.isPaused)) {
        _expectNativePosition(target);
        await _player.seekToPlayer(target);

        if (shouldResume && _player.isPaused) {
          await _player.resumePlayer();
          await _player.setSpeed(_playbackSpeed);
        }
      } else {
        _expectNativePosition(target);
      }
    } catch (_) {
      // Keep the selected visual position if native seeking is unavailable.
    } finally {
      _scrubPauseFuture = null;
      _resumeAfterScrub = false;
      _isScrubbing = false;
      if (mounted) {
        setState(() {
          _position = target;
          _playbackCompleted = progress >= 1;
          _isPlaying = shouldResume && _player.isPlaying;
        });
        if (_isPlaying) _animatePlaybackFromCurrentPosition();
      }
    }
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl.isEmpty || _isScrubbing) return;

    if (_isPlaying) {
      await _pausePlayback();
      return;
    }

    if (!_playerReady) {
      _playWhenReady = true;
      unawaited(_ensurePlayerReady());
      return;
    }

    widget.onPlaybackStarted?.call();
    await _startOrResumePlayback();
  }

  Future<void> _playFromController() async {
    if (!_playerReady) {
      _playWhenReady = true;
      unawaited(_ensurePlayerReady());
      return;
    }
    if (_isPlaying || widget.audioUrl.isEmpty || _isScrubbing) return;

    widget.onPlaybackStarted?.call();
    await _startOrResumePlayback();
  }

  Future<void> _pauseFromController() async {
    _playWhenReady = false;
    await _pausePlayback();
  }

  Future<void> _pausePlayback() async {
    if (!_playerReady || !_isPlaying) return;
    await _player.pausePlayer();
    _playbackProgress.stop(canceled: false);
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _startOrResumePlayback() async {
    if (!_playerReady || widget.audioUrl.isEmpty || _isScrubbing) return;

    if (_player.isPaused && !_playbackCompleted) {
      await _reportVoiceOpenedAndListened();
      if (!mounted) return;
      _expectNativePosition(_position);
      await _player.resumePlayer();
    } else {
      var requestedStartPosition =
          _playbackCompleted ? Duration.zero : _position;
      if (requestedStartPosition >=
          Duration(milliseconds: _resolvedDurationMs)) {
        requestedStartPosition = Duration.zero;
      }
      _position = requestedStartPosition;
      _playbackCompleted = false;
      _playbackProgress
        ..stop(canceled: false)
        ..value =
            _resolvedDurationMs > 0
                ? (requestedStartPosition.inMilliseconds / _resolvedDurationMs)
                    .clamp(0.0, 1.0)
                    .toDouble()
                : 0;
      final copy = await AttachmentLocalStore.instance.ensureComplete(
        source: widget.audioUrl,
        fileName: 'voice_message.aac',
      );
      if (!mounted) return;
      final measuredDuration = await _measureAdtsDuration(copy.file);
      if (!mounted) return;
      if (measuredDuration != null && measuredDuration > Duration.zero) {
        _duration = measuredDuration;
      }
      await _reportVoiceOpenedAndListened();
      if (!mounted) return;
      _expectNativePosition(Duration.zero);
      final playbackDuration = await _player.startPlayer(
        fromURI: copy.file.path,
        codec: Codec.aacADTS,
        whenFinished: () {
          if (!mounted) return;

          _playbackProgress
            ..stop(canceled: false)
            ..value = 0;
          setState(() {
            _isPlaying = false;
            _playbackCompleted = true;
            _showsPlaybackSpeed = false;
            _position = Duration.zero;
            _pendingNativeSeekTarget = null;
            _pendingNativeSeekStartedAt = null;
            _lastAcceptedNativeProgressAt = null;
          });

          // The chat screen decides whether the immediately following message
          // is another playable voice note. A text/image/file message breaks
          // the chain, so autoplay stops there.
          widget.onPlaybackCompleted?.call();
        },
      );
      if (playbackDuration != null && playbackDuration > Duration.zero) {
        _duration = playbackDuration;
      }
      if (requestedStartPosition > Duration.zero) {
        _expectNativePosition(requestedStartPosition);
        await _player.seekToPlayer(requestedStartPosition);
      }
    }

    _playbackSpeed = VoiceNotePlaybackSettings.currentSpeed;
    try {
      await _player.setSpeed(_playbackSpeed);
    } catch (_) {
      // Playback has already started; an unsupported native speed change must
      // not leave the UI paused or the message marked as unopened.
    }
    if (mounted) {
      setState(() {
        _isPlaying = true;
        _showsPlaybackSpeed = true;
      });
      _animatePlaybackFromCurrentPosition();
    }
  }

  Future<void> _reportVoiceOpenedAndListened() async {
    await widget.onOpened?.call();
    if (_listenedReported || widget.isListened) return;
    _listenedReported = true;
    widget.onListened?.call();
  }

  void _cyclePlaybackSpeed() {
    if (!_showsPlaybackSpeed) {
      setState(() => _showsPlaybackSpeed = true);
      VoiceNotePlaybackSettings.setSpeed(1.0);
      return;
    }
    VoiceNotePlaybackSettings.cycleSpeed();
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString();
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  String _speedLabelFor(double speed) =>
      speed == 1
          ? '1X'
          : speed == 1.5
          ? '1.5X'
          : '2X';

  Widget _buildPlaybackSpeedButton(Color background) {
    return ValueListenableBuilder<double>(
      valueListenable: VoiceNotePlaybackSettings.speed,
      builder: (context, selectedSpeed, _) {
        final speedLabel = _speedLabelFor(selectedSpeed);
        return Semantics(
          button: true,
          label: 'Playback speed $speedLabel',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cyclePlaybackSpeed,
            child: Container(
              width: _VoiceNoteGeometry.speedHeight,
              height: _VoiceNoteGeometry.speedHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                  width: 0.8,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<String>(speedLabel),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        speedLabel.substring(0, speedLabel.length - 1),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: WrytteColors.textPrimary,
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                          fontFeatures: [
                            ui.FontFeature.tabularFigures(),
                            ui.FontFeature('cv01', 1),
                          ],
                        ),
                      ),
                      wrytteSvgAssetIcon(
                        assetPath: 'assets/svg/Speed X icon.svg',
                        canvas: 8,
                        scale: 1.94,
                        offset: const Offset(-1, 0),
                        color: WrytteColors.textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTotalSeconds =
        _resolvedDurationMs > 0
            ? ((_resolvedDurationMs + 999) ~/ 1000)
            : widget.totalSeconds;
    final displayedSeconds =
        _isPlaying || _position > Duration.zero
            ? _position.inSeconds.clamp(0, resolvedTotalSeconds).toInt()
            : resolvedTotalSeconds;
    final primaryIconColor =
        widget.isMine
            ? Colors.white.withValues(alpha: 0.92)
            : WrytteColors.textSecondary;
    final voiceIconColor =
        (widget.isMine && widget.isListened) ||
                (!widget.isMine && widget.isOpened)
            ? const Color(0xFF2978FF)
            : primaryIconColor;
    final speedBackground =
        widget.isMine
            ? const Color(0xFF2568A8).withValues(alpha: 0.56)
            : Colors.white.withValues(alpha: 0.16);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : _VoiceNoteGeometry.contentWidth;
        final playerWidth = math.min(
          _VoiceNoteGeometry.contentWidth,
          availableWidth,
        );
        final metadataBandHeight =
            _VoiceNoteGeometry.metadataTopGap +
            MediaQuery.textScalerOf(context).scale(12);

        return SizedBox(
          width: playerWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The duration/timestamp row occupies a band below the waveform.
              // Reserve the same height above it so the controls remain visually
              // centred without device-specific transforms or offsets.
              SizedBox(height: metadataBandHeight),
              // The whole control row has one fixed geometry for incoming and
              // outgoing voice notes. Only colours depend on `widget.isMine`.
              Transform.translate(
                key: const ValueKey('voice-primary-controls'),
                offset: const Offset(0, -3),
                child: SizedBox(
                  height: _VoiceNoteGeometry.controlsHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // â”€â”€ Play / pause button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      GestureDetector(
                        onTap: _togglePlay,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: _VoiceNoteGeometry.playSlotWidth,
                          height: _VoiceNoteGeometry.playSlotHeight,
                          decoration: const BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 170),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInCubic,
                            child:
                                _isPlaying
                                    ? Icon(
                                      Icons.pause_rounded,
                                      key: const ValueKey('voice-note-pause'),
                                      color: primaryIconColor,
                                      size: 28,
                                    )
                                    : KeyedSubtree(
                                      key: const ValueKey('voice-note-play'),
                                      child: wrytteSvgAssetIcon(
                                        assetPath: 'assets/svg/Play icon .svg',
                                        canvas: 29,
                                        scale: 1.22,
                                        color: primaryIconColor,
                                      ),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: _VoiceNoteGeometry.playToWaveformGap,
                      ),

                      // â”€â”€ Waveform + progress â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      Expanded(
                        child: RepaintBoundary(
                          child: _VoiceWaveformTrack(
                            progress: _playbackProgress,
                            microphoneColor: voiceIconColor,
                            activeColor: Colors.white.withValues(alpha: 0.96),
                            inactiveColor:
                                widget.isMine
                                    ? Colors.white.withValues(alpha: 0.40)
                                    : WrytteColors.textMuted,
                            onSeekStart: _beginScrub,
                            onSeekDelta: _updateScrubBy,
                            onSeekEnd: () => unawaited(_finishScrub()),
                          ),
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: _showsPlaybackSpeed ? 1 : 0,
                        ),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        builder: (context, reveal, child) {
                          return ExcludeSemantics(
                            excluding: !_showsPlaybackSpeed,
                            child: IgnorePointer(
                              ignoring: !_showsPlaybackSpeed,
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  widthFactor: reveal,
                                  child: Opacity(
                                    opacity: reveal,
                                    child: Transform.scale(
                                      alignment: Alignment.centerRight,
                                      scale: 0.84 + (0.16 * reveal),
                                      child: child,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        child: SizedBox(
                          width:
                              _VoiceNoteGeometry.waveformToSpeedGap +
                              _VoiceNoteGeometry.speedHeight,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _buildPlaybackSpeedButton(speedBackground),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Timestamp/checkmark widgets are intentionally unchanged.
              const SizedBox(height: _VoiceNoteGeometry.metadataTopGap),
              Row(
                children: [
                  const SizedBox(width: _VoiceNoteGeometry.durationLeftInset),
                  Text(
                    _fmt(displayedSeconds),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 12,
                      height: 1,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(
                      right: _VoiceNoteGeometry.metadataRightInset,
                    ),
                    child: widget.timeWidget,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// â”€â”€ Waveform bars â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//
// Static decorative bars (like WhatsApp). Progress splits them into
// played (white) vs unplayed (white 30%) segments.

class _VoiceWaveformTrack extends StatelessWidget {
  final Animation<double> progress;
  final Color microphoneColor;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekDelta;
  final VoidCallback onSeekEnd;

  const _VoiceWaveformTrack({
    required this.progress,
    required this.microphoneColor,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeekStart,
    required this.onSeekDelta,
    required this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _VoiceNoteGeometry.waveformHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const microphoneCanvas = _VoiceNoteGeometry.microphoneCanvas;
          const waveformInset = microphoneCanvas / 2;
          final travel = (constraints.maxWidth - microphoneCanvas).clamp(
            0.0,
            double.infinity,
          );
          final marker = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => onSeekStart(),
            onHorizontalDragUpdate: (details) {
              if (travel <= 0) return;
              onSeekDelta(details.delta.dx / travel);
            },
            onHorizontalDragEnd: (_) => onSeekEnd(),
            onHorizontalDragCancel: onSeekEnd,
            child: wrytteSvgAssetIcon(
              assetPath: 'assets/svg/Fill voice icon .svg',
              canvas: microphoneCanvas,
              scale: 1.02,
              color: microphoneColor,
            ),
          );
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: waveformInset,
                right: waveformInset,
                child: _WaveformBars(
                  progress: progress,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                ),
              ),
              Positioned(
                left: 0,
                top: 2,
                width: microphoneCanvas,
                height: microphoneCanvas,
                child: AnimatedBuilder(
                  animation: progress,
                  child: marker,
                  builder: (context, child) {
                    final safeProgress =
                        progress.value.clamp(0.0, 1.0).toDouble();
                    return Transform.translate(
                      offset: Offset(travel * safeProgress, 0),
                      child: child,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final Animation<double> progress;

  final Color activeColor;
  final Color inactiveColor;

  const _WaveformBars({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  static const List<double> _heights = [
    6,
    10,
    14,
    8,
    18,
    12,
    20,
    10,
    16,
    8,
    14,
    18,
    6,
    12,
    20,
    10,
    16,
    8,
    14,
    18,
    12,
    6,
    10,
    16,
    8,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformBarsPainter(
          progress: progress,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          heights: _heights,
        ),
      ),
    );
  }
}

class _WaveformBarsPainter extends CustomPainter {
  final Animation<double> progress;
  final Color activeColor;
  final Color inactiveColor;
  final List<double> heights;

  _WaveformBarsPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.heights,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const barWidth = 2.2;
    const targetPitch = 4.2;
    final barCount = (size.width / targetPitch).floor().clamp(8, 64);
    final pitch = barCount > 1 ? (size.width - barWidth) / (barCount - 1) : 0.0;
    final playedX = size.width * progress.value.clamp(0.0, 1.0).toDouble();
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < barCount; index++) {
      final sourceHeight = heights[index % heights.length];
      final normalizedHeight = (sourceHeight / 20).clamp(0.0, 1.0);
      final barHeight = 4 + (normalizedHeight * (size.height - 4));
      final x = index * pitch;
      final played = x + (barWidth / 2) <= playedX;
      paint.color = played ? activeColor : inactiveColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - barHeight) / 2, barWidth, barHeight),
          const Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformBarsPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        activeColor != oldDelegate.activeColor ||
        inactiveColor != oldDelegate.inactiveColor ||
        !identical(heights, oldDelegate.heights);
  }
}

// â”€â”€ Text bubble content (unchanged from original) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

String _normalizeMessageForDisplay(String raw) {
  final normalized = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim()
      .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');

  return normalized
      .split(RegExp(r'\n{2,}'))
      .map(
        (paragraph) =>
            paragraph
                .replaceAll('\n', ' ')
                .replaceAll(RegExp(r'[ \t]+'), ' ')
                .trim(),
      )
      .where((paragraph) => paragraph.isNotEmpty)
      .join('\n\n');
}
