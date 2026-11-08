import 'dart:async';

import 'dart:io';

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:video_player/video_player.dart';

import 'package:wrytte/domain/models/camera_capture_result.dart';

import 'package:wrytte/domain/models/camera_session_state.dart';

import 'package:wrytte/domain/models/voice_recording_result.dart';

import 'package:wrytte/domain/repositories/audio_recording_repository.dart';

import 'package:wrytte/domain/repositories/camera_repository.dart';

import 'package:wrytte/ui/chat/view_models/chat_record_mode.dart';

import 'package:wrytte/ui/chat/view_models/chat_recording_controller.dart';

import 'package:wrytte/ui/chat/widgets/chat_layout_metrics.dart';

import 'package:wrytte/ui/core/themes/wrytte_theme.dart';

import 'package:wrytte/ui/core/widgets/wrytte_glass_icon_button.dart';

import 'package:wrytte/ui/core/widgets/wrytte_glass_surface.dart';

import 'package:wrytte/ui/core/widgets/wrytte_svg_icon.dart';

// Composer icon geometry preserved from the old implementation.

const double _composerMainIconCanvas = 28.0;

const double _composerPlusOpticalScale = 0.86;

const double _microphoneOpticalScale = 1.0;

const double _sendOpticalScale = 1.12;

const double _videoOpticalScale = 0.96;

/// The idle chat composer.

///

/// Recording capture deliberately does not live here while the old voice and

/// round-video flows are being remigrated. The trailing control only switches

/// between the audio and video modes on tap.

class ChatComposer extends StatefulWidget {
  // Shared with ChatView overlays so composer-adjacent controls use the exact

  // same geometry instead of duplicating a second size source.

  static const double controlSize = 42.0;

  /// Restores the old Wrytte composer breathing room.
  ///
  /// Devices that already reserve a bottom system/navigation inset use 10dp;
  /// devices without one use 12dp. ChatView preserves the stable system inset
  /// while moving for the IME, so this visual gap remains identical above the
  /// Android navigation area and above the keyboard.
  static double bottomGapFor(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom > 0 ? 10.0 : 12.0;

  const ChatComposer({
    super.key,

    required this.controller,

    required this.focusNode,

    required this.recordMode,

    required this.onSend,

    required this.onToggleRecordMode,

    this.onAttachmentPressed,

    this.onExpressPressed,

    this.replySender,

    this.replyPreview,

    this.onCancelReply,

    this.isEditing = false,

    this.editingMediaSource,

    this.editingMediaType,

    this.onCancelEdit,

    this.onReplaceEditingMedia,

    this.onVoiceRecorded,

    this.onRoundVideoRecorded,

    this.onRecordingFailure,

    this.onRecordingActiveChanged,
  });

  final TextEditingController controller;

  final FocusNode focusNode;

  final ChatRecordMode recordMode;

  final ValueChanged<String> onSend;

  final VoidCallback onToggleRecordMode;

  final ValueChanged<Rect?>? onAttachmentPressed;

  final VoidCallback? onExpressPressed;

  final String? replySender;

  final String? replyPreview;

  final VoidCallback? onCancelReply;

  final bool isEditing;

  final String? editingMediaSource;

  final String? editingMediaType;

  final VoidCallback? onCancelEdit;

  final Future<void> Function()? onReplaceEditingMedia;

  final ValueChanged<VoiceRecordingResult>? onVoiceRecorded;

  final ValueChanged<CameraCaptureResult>? onRoundVideoRecorded;

  final ValueChanged<String>? onRecordingFailure;

  final ValueChanged<bool>? onRecordingActiveChanged;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  ChatRecordingController? _recording;

  bool _dependenciesReady = false;

  final GlobalKey _recordButtonKey = GlobalKey();

  final GlobalKey _attachmentButtonKey = GlobalKey(
    debugLabel: 'chat-attachment-button',
  );

  Rect? _attachmentButtonRect() {
    final renderObject = _attachmentButtonKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Timer? _longPressTimer;

  int? _recordPointer;

  Offset? _recordPointerOrigin;

  bool _recordGestureCommitted = false;

  // A quick upward swipe from the idle record button should enter recording
  // already locked, without waiting for the long-press timer.
  bool _quickLockRequested = false;

  static const double _quickLockSwipeDistance = 34.0;
  static const double _quickLockHorizontalTolerance = 30.0;

  bool _reportedRecordingActive = false;

  double _recordingKeyboardInset = 0;
  bool _preserveKeyboardDuringRecording = false;
  bool _keyboardRestoreScheduled = false;
  int _keyboardRestoreAttempts = 0;
  Timer? _keyboardRestoreTimer;

  OverlayEntry? _videoRecordingOverlayEntry;
  bool _videoOverlayScheduled = false;

  @override
  void initState() {
    super.initState();

    widget.controller.addListener(_refresh);

    widget.focusNode.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_dependenciesReady) return;

    _dependenciesReady = true;

    _recording = ChatRecordingController(
      audio: context.read<AudioRecordingRepository>(),

      camera: context.read<CameraRepository>(),

      onVoiceReady: (result) => widget.onVoiceRecorded?.call(result),

      onVideoReady: (result) => widget.onRoundVideoRecorded?.call(result),

      onFailure: (message) => widget.onRecordingFailure?.call(message),
    )..addListener(_refresh);
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);

      widget.controller.addListener(_refresh);
    }

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_refresh);

      widget.focusNode.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _keyboardRestoreTimer?.cancel();
    _removeVideoRecordingOverlay();

    widget.controller.removeListener(_refresh);

    widget.focusNode.removeListener(_refresh);

    _recording
      ?..removeListener(_refresh)
      ..dispose();

    super.dispose();
  }

  void _refresh() {
    final recorder = _recording;
    final recordingActive = recorder?.uiActive == true;

    if (recordingActive != _reportedRecordingActive) {
      _reportedRecordingActive = recordingActive;
      widget.onRecordingActiveChanged?.call(recordingActive);

      if (!recordingActive) {
        _keyboardRestoreTimer?.cancel();
        _keyboardRestoreTimer = null;
        _keyboardRestoreAttempts = 0;
        _recordingKeyboardInset = 0;
        _preserveKeyboardDuringRecording = false;
      }
    }

    if (recordingActive &&
        _preserveKeyboardDuringRecording &&
        (!widget.focusNode.hasFocus ||
            _currentKeyboardInset() < _recordingKeyboardInset - 1)) {
      _scheduleRecordingKeyboardRestore();
    }

    final needsVideoOverlay =
        recorder?.uiActive == true &&
        recorder?.kind == ChatRecordingKind.roundVideo;

    if (needsVideoOverlay) {
      if (_videoRecordingOverlayEntry != null) {
        _videoRecordingOverlayEntry!.markNeedsBuild();
      } else if (!_videoOverlayScheduled) {
        _videoOverlayScheduled = true;
        scheduleMicrotask(() {
          _videoOverlayScheduled = false;
          if (!mounted) return;
          _syncVideoRecordingOverlay();
        });
      }
    } else {
      _removeVideoRecordingOverlay();
    }

    if (mounted) setState(() {});
  }

  void _syncVideoRecordingOverlay() {
    if (!mounted) return;

    final recorder = _recording;
    final shouldShow =
        recorder?.uiActive == true &&
        recorder?.kind == ChatRecordingKind.roundVideo;

    if (!shouldShow) {
      _removeVideoRecordingOverlay();
      return;
    }

    if (_videoRecordingOverlayEntry != null) {
      _videoRecordingOverlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final activeRecorder = _recording;
        if (activeRecorder == null ||
            !activeRecorder.uiActive ||
            activeRecorder.kind != ChatRecordingKind.roundVideo) {
          return const SizedBox.shrink();
        }

        final metrics = ChatLayoutMetrics.of(overlayContext);
        final mediaSize = MediaQuery.sizeOf(overlayContext);
        final keyboardInset = math.max(
          MediaQuery.viewInsetsOf(overlayContext).bottom,
          _recordingKeyboardInset,
        );
        final availableHeight = math.max(0.0, mediaSize.height - keyboardInset);
        final compactForKeyboard = keyboardInset > 1;
        final overlayHeight = compactForKeyboard
            ? math.min(availableHeight, mediaSize.height * .50)
            : availableHeight;
        // Keep the composer's 42px structural height because its trim/review
        // children share that contract. Compact only its icon scale; shrinking
        // the outer box would make the paused filmstrip overflow.
        const controlSize = ChatComposer.controlSize;
        final compactScale = metrics.scale * (compactForKeyboard ? .86 : 1);

        // The visual wash belongs to the root overlay so it also covers the
        // chat header. The recorder controls remain constrained to their
        // compact panel immediately above an open keyboard.
        return Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: _RoundVideoRecordingOverlay(
              controller: activeRecorder,
              controlSize: controlSize,
              scale: compactScale,
              horizontalPadding: metrics.horizontalPadding,
              availableSize: Size(mediaSize.width, overlayHeight),
              recorderBottomInset: keyboardInset,
              compact: compactForKeyboard,
              bottomSystemInset: compactForKeyboard
                  ? 0
                  : MediaQuery.viewPaddingOf(overlayContext).bottom,
            ),
          ),
        );
      },
    );

    _videoRecordingOverlayEntry = entry;
    overlay.insert(entry);
  }

  void _removeVideoRecordingOverlay() {
    final entry = _videoRecordingOverlayEntry;
    _videoRecordingOverlayEntry = null;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
  }

  double _currentKeyboardInset() {
    final view = View.of(context);
    final ratio = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    return view.viewInsets.bottom / ratio;
  }

  double _composerKeyboardInset() {
    return _currentKeyboardInset();
  }

  void _scheduleRecordingKeyboardRestore() {
    if (_keyboardRestoreScheduled ||
        _keyboardRestoreAttempts >= 12 ||
        !mounted) {
      return;
    }
    _keyboardRestoreScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardRestoreScheduled = false;
      if (!mounted ||
          !_preserveKeyboardDuringRecording ||
          _recording?.uiActive != true) {
        return;
      }

      final needsRestore =
          !widget.focusNode.hasFocus ||
          _currentKeyboardInset() < _recordingKeyboardInset - 1;
      if (!needsRestore) {
        _keyboardRestoreAttempts = 0;
        _keyboardRestoreTimer?.cancel();
        _keyboardRestoreTimer = null;
        return;
      }

      if (!widget.focusNode.hasFocus) {
        widget.focusNode.requestFocus();
      }
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));

      // Camera startup may briefly take Android window focus. A single show
      // request during that frame can be ignored, so retry a few times while
      // preserving the original keyboard boundary. This is bounded and stops
      // immediately once the IME returns or recording finishes.
      _keyboardRestoreAttempts += 1;
      if (_keyboardRestoreAttempts < 12) {
        _keyboardRestoreTimer?.cancel();
        _keyboardRestoreTimer = Timer(const Duration(milliseconds: 80), () {
          if (mounted) _scheduleRecordingKeyboardRestore();
        });
      }
    });
  }

  void _send() {
    final value = widget.controller.text;

    final hasEditableMedia =
        widget.editingMediaSource?.trim().isNotEmpty == true;

    if (value.trim().isEmpty && (!widget.isEditing || !hasEditableMedia)) {
      return;
    }

    widget.onSend(value);

    widget.controller.clear();
  }

  void _toggleRecordMode() {
    // Use the same native long-press feedback language as message actions.
    // This is more consistently audible/tactile across Android versions than
    // selectionClick for this explicit mode switch.
    unawaited(Feedback.forLongPress(context));
    widget.onToggleRecordMode();
  }

  bool _recordButtonContains(Offset globalPosition) {
    final box = _recordButtonKey.currentContext?.findRenderObject();

    if (box is! RenderBox || !box.hasSize) return false;

    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
  }

  ChatRecordingKind get _selectedRecordingKind =>
      widget.recordMode == ChatRecordMode.audio
      ? ChatRecordingKind.voice
      : ChatRecordingKind.roundVideo;

  Future<void> _beginRecordingGesture({required bool lockImmediately}) async {
    if (!mounted) return;

    final recorder = _recording;
    if (recorder == null || recorder.phase != ChatRecordingPhase.idle) {
      return;
    }

    // Prefer the inset captured on the initial pointer-down. Waiting until the
    // long-press threshold lets Android begin hiding the IME and incorrectly
    // turns an above-keyboard recorder into the full-screen variant.
    final keyboardInset = math.max(
      _composerKeyboardInset(),
      _recordingKeyboardInset,
    );
    _preserveKeyboardDuringRecording = keyboardInset > 1;
    _recordingKeyboardInset = _preserveKeyboardDuringRecording
        ? keyboardInset
        : 0;

    if (_preserveKeyboardDuringRecording && !widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }

    // begin() synchronously enters PREPARING before its first await, so a
    // forced upward drag can be stored immediately and applied as soon as the
    // native recorder becomes ready.
    final beginFuture = recorder.begin(_selectedRecordingKind);

    if (_preserveKeyboardDuringRecording) {
      _scheduleRecordingKeyboardRestore();
    }

    if (lockImmediately) {
      recorder.updateDrag(
        const Offset(0, -ChatRecordingController.lockDistance),
      );
    }

    // Use the same native long-press feedback language as message actions.
    await Feedback.forLongPress(context);

    await beginFuture;

    if (_preserveKeyboardDuringRecording) {
      _scheduleRecordingKeyboardRestore();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_recordPointer != null || !_recordButtonContains(event.position)) {
      return;
    }

    _recordPointer = event.pointer;
    _recordPointerOrigin = event.position;
    _recordGestureCommitted = false;
    _quickLockRequested = false;

    // Capture keyboard geometry before the 360ms hold delay and before camera
    // preparation can reshuffle Android focus/window insets.
    final keyboardInset = _composerKeyboardInset();
    if (keyboardInset > 1) {
      _recordingKeyboardInset = keyboardInset;
      _preserveKeyboardDuringRecording = true;
      _keyboardRestoreAttempts = 0;
    }

    _longPressTimer?.cancel();

    _longPressTimer = Timer(const Duration(milliseconds: 360), () {
      if (!mounted ||
          _recordPointer != event.pointer ||
          _recordGestureCommitted) {
        return;
      }

      _recordGestureCommitted = true;
      _quickLockRequested = false;

      unawaited(_beginRecordingGesture(lockImmediately: false));
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_recordPointer != event.pointer) return;

    final origin = _recordPointerOrigin;
    if (origin == null) return;

    final delta = event.position - origin;

    // QUICK LOCK:
    // A deliberate upward swipe directly from the idle record button starts
    // recording immediately and stores a full lock gesture while native
    // microphone/camera startup is still preparing.
    if (!_recordGestureCommitted &&
        delta.dy <= -_quickLockSwipeDistance &&
        delta.dx.abs() <= _quickLockHorizontalTolerance) {
      _longPressTimer?.cancel();

      _recordGestureCommitted = true;
      _quickLockRequested = true;

      unawaited(_beginRecordingGesture(lockImmediately: true));

      return;
    }

    if (!_recordGestureCommitted) return;

    final recorder = _recording;
    if (recorder == null) return;

    // Once quick-lock is requested, keep the pending gesture at the lock
    // endpoint until the controller has actually entered its locked phase.
    // This prevents a later intermediate pointer frame from weakening the
    // pending lock while native startup is still in progress.
    if (_quickLockRequested && !recorder.locked) {
      recorder.updateDrag(
        const Offset(0, -ChatRecordingController.lockDistance),
      );
      return;
    }

    recorder.updateDrag(delta);
  }

  void _handlePointerUp(PointerEvent event) {
    if (_recordPointer != event.pointer) return;

    _longPressTimer?.cancel();

    if (_recordGestureCommitted) {
      final recorder = _recording;
      if (recorder != null) {
        unawaited(recorder.releaseHold());
      }
    } else {
      _toggleRecordMode();
      _recordingKeyboardInset = 0;
      _preserveKeyboardDuringRecording = false;
      _keyboardRestoreAttempts = 0;
      _keyboardRestoreTimer?.cancel();
      _keyboardRestoreTimer = null;
    }

    _recordPointer = null;
    _recordPointerOrigin = null;
    _recordGestureCommitted = false;
    _quickLockRequested = false;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ChatLayoutMetrics.of(context);

    const actionSize = ChatComposer.controlSize;
    final bottomGap = ChatComposer.bottomGapFor(context);

    final hasText = widget.controller.text.trim().isNotEmpty;

    final hasReply =
        widget.replySender?.trim().isNotEmpty == true ||
        widget.replyPreview?.trim().isNotEmpty == true;

    final hasComposerContext = hasReply || widget.isEditing;

    final canSend =
        hasText ||
        (widget.isEditing &&
            widget.editingMediaSource?.trim().isNotEmpty == true);

    // Keep the input field expanded whenever the composer is actually being used.

    // Closing the keyboard must NOT bring Express Chat back while there is

    // typed text, an active reply, or an active edit. Express Chat only returns

    // when the keyboard is closed and the composer has no content/context.

    final inputActive = widget.focusNode.hasFocus;

    final keepInputExpanded = inputActive || hasText || hasComposerContext;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final recorder = _recording;
    final recordingUiActive = recorder?.uiActive == true;
    final videoRecordingActive =
        recordingUiActive && recorder?.kind == ChatRecordingKind.roundVideo;

    // Never let Express re-enter during the same frame recording begins.
    // The whole idle composer exits as one coordinated transition instead.
    final expressTargetFactor = recordingUiActive
        ? 0.0
        : (keepInputExpanded ? 0.0 : 1.0);

    final composerMotionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 165);

    return Listener(
      behavior: HitTestBehavior.translucent,

      onPointerDown: _handlePointerDown,

      onPointerMove: _handlePointerMove,

      onPointerUp: _handlePointerUp,

      onPointerCancel: _handlePointerUp,

      child: SafeArea(
        top: false,

        // Use the remaining safe-area padding while the chat viewport follows
        // the keyboard inset. Once the keyboard covers the navigation area,
        // SafeArea drops that inset and leaves only the composer breathing gap.

        child: Padding(
          padding: EdgeInsets.only(
            left: metrics.horizontalPadding,

            right: metrics.horizontalPadding,

            // The 8dp message/composer breathing room is reserved by ChatView's

            // reversed-scroll spacer, so the composer itself stays at its true

            // bottom layout edge.
            top: 0,

            // Restore the old Wrytte breathing room and keep it identical in
            // both states:
            //
            // closed -> system navigation inset + bottomGap
            // open   -> keyboard top + bottomGap
            //
            // SafeArea keeps the stable system inset while ChatView animates by
            // (keyboardInset - stableSystemBottom), so this gap never collapses
            // or jumps during the IME transition.
            bottom: bottomGap,
          ),

          child: _ComposerModeTransition(
            recording: recordingUiActive,
            reduceMotion: reduceMotion,
            recordingChild: KeyedSubtree(
              key: const ValueKey('recording-composer-mode'),
              child: videoRecordingActive
                  // The round-video UI lives in a root OverlayEntry. Keep
                  // only the normal one-line composer footprint here so
                  // ChatView's message viewport never grows or shifts up.
                  ? const SizedBox(height: actionSize)
                  : recorder == null
                  ? const SizedBox(height: actionSize)
                  : _ActiveRecordingComposer(
                      controller: recorder,
                      controlSize: actionSize,
                      scale: metrics.scale,
                    ),
            ),
            idleChild: KeyedSubtree(
              key: const ValueKey('idle-composer-mode'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,

                children: [
                  WrytteGlassIconButton(
                    key: _attachmentButtonKey,
                    semanticLabel: 'Add attachment',

                    onPressed: widget.onAttachmentPressed == null
                        ? null
                        : () => widget.onAttachmentPressed!(
                            _attachmentButtonRect(),
                          ),

                    size: actionSize,

                    child: Transform.scale(
                      scale: _composerPlusOpticalScale,

                      child: WrytteSvgIcon(
                        asset: 'assets/svg/Plus add icon new .svg',

                        size: _composerMainIconCanvas * metrics.scale,

                        color: WrytteColors.textPrimary,
                      ),
                    ),
                  ),

                  SizedBox(width: metrics.controlGap),

                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: actionSize,

                        maxHeight: math.max(
                          170.0,

                          actionSize + (hasComposerContext ? 50 : 0),
                        ),
                      ),

                      child: WrytteGlassSurface(
                        borderRadius: BorderRadius.circular(actionSize / 2),

                        child: Column(
                          mainAxisSize: MainAxisSize.min,

                          children: [
                            if (hasComposerContext)
                              _ComposerReplyPreview(
                                isEditing: widget.isEditing,

                                sender: widget.isEditing
                                    ? 'Edit message'
                                    : widget.replySender,

                                preview: widget.isEditing
                                    ? null
                                    : widget.replyPreview,

                                onClose: widget.isEditing
                                    ? widget.onCancelEdit
                                    : widget.onCancelReply,

                                editingMediaSource: widget.editingMediaSource,

                                editingMediaType: widget.editingMediaType,

                                onReplaceEditingMedia:
                                    widget.onReplaceEditingMedia,
                              ),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,

                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey('chat-message-field'),

                                    controller: widget.controller,

                                    focusNode: widget.focusNode,

                                    minLines: 1,

                                    maxLines: 5,

                                    keyboardType: TextInputType.multiline,

                                    textInputAction: TextInputAction.newline,

                                    textCapitalization:
                                        TextCapitalization.sentences,

                                    // Keep both the hint and typed text vertically

                                    // centered inside the 42px composer pill.
                                    textAlignVertical: TextAlignVertical.center,

                                    style: const TextStyle(
                                      fontFamily:
                                          WrytteTypography.primaryFontFamily,

                                      color: WrytteColors.textPrimary,

                                      fontSize: 15,

                                      fontWeight: FontWeight.w400,

                                      height: 1.35,
                                    ),

                                    decoration: InputDecoration(
                                      isDense: true,

                                      border: InputBorder.none,

                                      enabledBorder: InputBorder.none,

                                      disabledBorder: InputBorder.none,

                                      focusedBorder: InputBorder.none,

                                      errorBorder: InputBorder.none,

                                      focusedErrorBorder: InputBorder.none,

                                      hintText: 'Message',

                                      hintStyle: TextStyle(
                                        fontFamily:
                                            WrytteTypography.primaryFontFamily,

                                        color: Colors.white.withValues(
                                          alpha: .45,
                                        ),

                                        fontSize: 15,

                                        fontWeight: FontWeight.w400,

                                        height: 1.35,
                                      ),

                                      contentPadding:
                                          EdgeInsetsDirectional.fromSTEB(
                                            16,

                                            (actionSize - 20.25) / 2,

                                            6,

                                            (actionSize - 20.25) / 2,
                                          ),
                                    ),
                                  ),
                                ),

                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 5,
                                  ),

                                  child: SizedBox.square(
                                    dimension: actionSize,

                                    child: Center(
                                      child: WrytteSvgIcon(
                                        asset:
                                            'assets/svg/mage--round-sticker.svg',

                                        size: 21 * metrics.scale,

                                        color: Colors.white.withValues(
                                          alpha: .46,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Express controls have their own 200ms animation too.
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: expressTargetFactor),

                    duration: composerMotionDuration,

                    curve: Curves.easeOutCubic,

                    builder: (context, factor, child) {
                      return ClipRect(
                        child: Align(
                          alignment: Alignment.centerRight,

                          widthFactor: factor,

                          child: IgnorePointer(
                            ignoring: factor < 0.98,

                            child: Opacity(
                              opacity: factor,

                              child: Transform.scale(
                                alignment: Alignment.centerRight,

                                scale: 0.94 + (0.06 * factor),

                                child: Row(
                                  mainAxisSize: MainAxisSize.min,

                                  children: [
                                    SizedBox(width: metrics.controlGap),

                                    WrytteGlassIconButton(
                                      semanticLabel: 'Express message',

                                      onPressed: widget.onExpressPressed,

                                      size: actionSize,

                                      child: WrytteSvgIcon(
                                        asset:
                                            'assets/svg/Express chat icon.svg',

                                        size: 30.5 * metrics.scale,

                                        color: WrytteColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(width: metrics.controlGap),

                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 210),

                    switchInCurve: Curves.easeOutCubic,

                    switchOutCurve: Curves.easeInCubic,

                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,

                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: .82,

                          end: 1,
                        ).animate(animation),

                        child: child,
                      ),
                    ),

                    child: canSend
                        ? _SendButton(
                            key: const ValueKey('send'),

                            size: actionSize,

                            scale: metrics.scale,

                            onPressed: _send,
                          )
                        : _RecordModeButton(
                            key: ValueKey(widget.recordMode),

                            gestureKey: _recordButtonKey,

                            recordMode: widget.recordMode,

                            size: actionSize,

                            scale: metrics.scale,

                            onPressed: _toggleRecordMode,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingComposerEntrance extends StatelessWidget {
  const _RecordingComposerEntrance({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final slide = Tween<Offset>(
      begin: const Offset(.025, 0),
      end: Offset.zero,
    ).animate(curved);

    final scale = Tween<double>(begin: .985, end: 1).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }
}

class _ComposerModeTransition extends StatelessWidget {
  const _ComposerModeTransition({
    required this.recording,
    required this.reduceMotion,
    required this.idleChild,
    required this.recordingChild,
  });

  final bool recording;
  final bool reduceMotion;
  final Widget idleChild;
  final Widget recordingChild;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 165);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: recording ? 1 : 0),
      duration: duration,
      curve: recording ? Curves.easeOutCubic : Curves.easeInCubic,
      builder: (context, progress, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomRight,
          children: [
            // Keep the real EditableText mounted while recording. If it owned
            // an open IME before the hold, its TextInputConnection therefore
            // remains alive and Android has no reason to lower the keyboard.
            IgnorePointer(
              ignoring: recording,
              child: Opacity(
                opacity: 1 - progress,
                child: Transform.scale(
                  scale: 1 - (.015 * progress),
                  alignment: Alignment.centerRight,
                  child: idleChild,
                ),
              ),
            ),
            IgnorePointer(
              ignoring: !recording,
              child: Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(1.05 * (1 - progress), 0),
                  child: Transform.scale(
                    scale: .985 + (.015 * progress),
                    alignment: Alignment.centerRight,
                    child: recordingChild,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ComposerReplyPreview extends StatelessWidget {
  const _ComposerReplyPreview({
    required this.isEditing,

    required this.sender,

    required this.preview,

    required this.onClose,

    this.editingMediaSource,

    this.editingMediaType,

    this.onReplaceEditingMedia,
  });

  final bool isEditing;

  final String? sender;

  final String? preview;

  final VoidCallback? onClose;

  final String? editingMediaSource;

  final String? editingMediaType;

  final Future<void> Function()? onReplaceEditingMedia;

  @override
  Widget build(BuildContext context) {
    final senderLabel = sender?.trim().isNotEmpty == true
        ? sender!.trim()
        : 'Reply';

    final previewLabel = preview?.trim().isNotEmpty == true
        ? preview!.trim()
        : 'Message';

    final mediaSource = editingMediaSource?.trim() ?? '';

    final editingMedia = mediaSource.isNotEmpty;

    final editKindLabel = switch (editingMediaType) {
      'image' => 'Image',

      'video' => 'Video',

      _ => 'Message',
    };

    const editTitleStyle = TextStyle(
      color: Color(0xFF62ACF8),

      fontFamily: WrytteTypography.primaryFontFamily,

      fontSize: 15,

      fontWeight: FontWeight.w500,

      height: 1.08,
    );

    final editKindStyle = TextStyle(
      color: Colors.white.withValues(alpha: .76),

      fontFamily: WrytteTypography.primaryFontFamily,

      fontSize: 15,

      fontWeight: FontWeight.w400,

      height: 1.08,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 5, 4),

      child: Row(
        children: [
          Container(
            width: 3,

            height: 36,

            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,

                end: Alignment.bottomCenter,

                colors: [Color(0xFF72BCFF), WrytteColors.primary],
              ),

              borderRadius: BorderRadius.circular(3),
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: editingMedia
                ? Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            const Text(
                              'Edit message',

                              maxLines: 1,

                              overflow: TextOverflow.ellipsis,

                              style: editTitleStyle,
                            ),

                            const SizedBox(height: 3),

                            Text(
                              editKindLabel,

                              maxLines: 1,

                              overflow: TextOverflow.ellipsis,

                              style: editKindStyle,
                            ),
                          ],
                        ),
                      ),

                      if (onReplaceEditingMedia != null)
                        TextButton.icon(
                          onPressed: () => unawaited(onReplaceEditingMedia!()),

                          icon: const WrytteSvgIcon(
                            asset: 'assets/svg/Replace media icon.svg',

                            size: 17,

                            color: Color(0xFF62ACF8),
                          ),

                          label: const Text('Replace'),

                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF62ACF8),

                            padding: const EdgeInsets.symmetric(horizontal: 6),

                            visualDensity: VisualDensity.compact,
                          ),
                        ),

                      const SizedBox(width: 5),

                      _EditingMediaThumbnail(
                        source: mediaSource,

                        isVideo: editingMediaType == 'video',
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        senderLabel,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: isEditing
                            ? editTitleStyle
                            : const TextStyle(
                                color: Color(0xFF62ACF8),

                                fontFamily: WrytteTypography.primaryFontFamily,

                                fontSize: 14,

                                fontWeight: FontWeight.w600,

                                height: 1.08,
                              ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        isEditing ? editKindLabel : previewLabel,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: isEditing
                            ? editKindStyle
                            : TextStyle(
                                color: Colors.white.withValues(alpha: .76),

                                fontFamily: WrytteTypography.primaryFontFamily,

                                fontSize: 15,

                                height: 1.08,
                              ),
                      ),
                    ],
                  ),
          ),

          IconButton(
            tooltip: 'Cancel reply',

            onPressed: onClose,

            constraints: const BoxConstraints.tightFor(width: 36, height: 40),

            padding: EdgeInsets.zero,

            splashRadius: 19,

            icon: Transform.translate(
              offset: const Offset(3, 0),

              child: Icon(
                Icons.close_rounded,

                size: 21,

                color: Colors.white.withValues(alpha: .58),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditingMediaThumbnail extends StatelessWidget {
  const _EditingMediaThumbnail({required this.source, required this.isVideo});

  final String source;

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (isVideo) {
      child = const ColoredBox(
        color: WrytteColors.surfaceRaised,

        child: Center(
          child: Icon(
            Icons.videocam_rounded,

            size: 20,

            color: WrytteColors.textSecondary,
          ),
        ),
      );
    } else if (source.startsWith('assets/')) {
      child = Image.asset(source, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      final uri = Uri.tryParse(source);

      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        child = Image.network(source, fit: BoxFit.cover, gaplessPlayback: true);
      } else {
        final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;

        child = Image.file(
          File(path),

          fit: BoxFit.cover,

          gaplessPlayback: true,
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),

      child: SizedBox.square(dimension: 40, child: child),
    );
  }
}

class _LoopingTranslation extends StatefulWidget {
  const _LoopingTranslation({
    required this.child,
    required this.begin,
    required this.end,
    required this.duration,
  });

  final Widget child;
  final Offset begin;
  final Offset end;
  final Duration duration;

  @override
  State<_LoopingTranslation> createState() => _LoopingTranslationState();
}

class _LoopingTranslationState extends State<_LoopingTranslation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _configureAnimation();
  }

  @override
  void didUpdateWidget(covariant _LoopingTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.begin != widget.begin || oldWidget.end != widget.end) {
      _configureAnimation();
    }

    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  void _configureAnimation() {
    _offset = Tween<Offset>(begin: widget.begin, end: widget.end).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder: (context, child) {
        return Transform.translate(offset: _offset.value, child: child);
      },
    );
  }
}

Future<void> _cancelRecordingWithFeedback(
  BuildContext context,
  ChatRecordingController controller,
) async {
  await Feedback.forLongPress(context);
  if (!context.mounted) return;
  await controller.cancel();
}

class _ActiveRecordingComposer extends StatelessWidget {
  const _ActiveRecordingComposer({
    required this.controller,
    required this.controlSize,
    required this.scale,
  });

  final ChatRecordingController controller;
  final double controlSize;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final locked = controller.locked;
    final pausedVoice =
        controller.paused && controller.kind == ChatRecordingKind.voice;
    final pausedVideo =
        controller.paused && controller.kind == ChatRecordingKind.roundVideo;

    // Keep the recorder pill at the same height as the normal composer.
    // The paused-video filmstrip scales into this 42px Wrytte footprint instead
    // of making the whole bottom composer grow taller.
    final recordingPillHeight = controlSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Match the old composer:
            //
            // holding  -> the left attachment slot collapses completely
            // locked   -> the same slot grows back as the red delete control
            IgnorePointer(
              ignoring: !locked,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: locked ? 1 : 0),
                duration: const Duration(milliseconds: 165),
                curve: Curves.easeOutCubic,
                builder: (context, visibility, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: visibility,
                      child: Opacity(
                        opacity: visibility,
                        child: Transform.translate(
                          offset: Offset(-10 * (1 - visibility), 0),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WrytteGlassIconButton(
                      semanticLabel: 'Delete recording',
                      onPressed: controller.pauseResumeBusy
                          ? null
                          : () => unawaited(
                              _cancelRecordingWithFeedback(context, controller),
                            ),
                      // Keep this exactly the same footprint as the normal
                      // composer + button.
                      size: controlSize,
                      child: WrytteSvgIcon(
                        asset: 'assets/svg/Delete icon.svg',
                        color: const Color(0xFFFF4D57),
                        size: 22 * scale,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: .80, end: 1),
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                builder: (context, fieldProgress, child) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: fieldProgress,
                      child: Opacity(
                        opacity: (.35 + (.65 * fieldProgress)).clamp(0.0, 1.0),
                        child: child,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  height: recordingPillHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PositionedDirectional(
                        start: 0,
                        end: -49,
                        top: 0,
                        bottom: 0,
                        child: WrytteGlassSurface(
                          borderRadius: BorderRadius.circular(controlSize / 2),
                          child: controller.reviewing
                              ? _RecordingReview(controller: controller)
                              : pausedVoice
                              ? _PausedVoiceTrimEditor(controller: controller)
                              : pausedVideo
                              ? _PausedVideoTrimEditor(controller: controller)
                              : _LiveRecordingStatus(controller: controller),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RecordingAction(controller: controller, size: controlSize),
          ],
        ),
      ],
    );
  }
}

class _SlideToCancelPrompt extends StatelessWidget {
  const _SlideToCancelPrompt({required this.cancelProgress});

  final double cancelProgress;

  @override
  Widget build(BuildContext context) {
    // The arrow always has a small directional nudge. Once the user's leftward
    // cancel gesture becomes intentional, the full prompt joins the movement.
    final promptProgress = ((cancelProgress - .16) / .84)
        .clamp(0.0, 1.0)
        .toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: promptProgress),
      duration: const Duration(milliseconds: 72),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) {
        final eased = Curves.easeOutCubic.transform(progress);

        return Transform.translate(
          offset: Offset(-24 * eased, 0),
          child: Opacity(opacity: 1 - (.16 * eased), child: child),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Flexible(
            child: Text(
              'Slide to cancel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WrytteColors.textMuted,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: 5),
          _LoopingTranslation(
            begin: Offset(3.5, 0),
            end: Offset(-3.5, 0),
            duration: Duration(milliseconds: 520),
            child: WrytteSvgIcon(
              asset: 'assets/svg/Arrow voice area.svg',
              size: 16,
              color: WrytteColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveRecordingStatus extends StatelessWidget {
  const _LiveRecordingStatus({required this.controller});

  final ChatRecordingController controller;

  @override
  Widget build(BuildContext context) {
    final locked = controller.locked;

    // The old composer reserved the right side because the glass recording pill
    // visually continues underneath the enlarged blue action button.
    return Padding(
      key: const ValueKey('sliding-recording-controls'),
      // Give the timer and pulsing marker more breathing room from the glass
      // outline. The waveform yields these few pixels instead of changing the
      // recorder pill's overall width.
      padding: const EdgeInsetsDirectional.only(start: 15, end: 58),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: locked ? 1 : 0),
        duration: const Duration(milliseconds: 185),
        curve: Curves.easeOutCubic,
        builder: (context, lockedProgress, child) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Holding state.
              Opacity(
                opacity: 1 - lockedProgress,
                child: Transform.translate(
                  offset: Offset(-8 * lockedProgress, 0),
                  child: Row(
                    children: [
                      Text(
                        _recordingTime(controller.elapsed),
                        style: const TextStyle(
                          color: WrytteColors.textPrimary,
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 15,
                          height: 1,
                          fontWeight: FontWeight.w400,
                          fontFeatures: [
                            FontFeature.tabularFigures(),
                            FontFeature('cv01', 1),
                          ],
                        ),
                      ),

                      const SizedBox(width: 11),

                      _RecordingDot(
                        second: controller.elapsed.inSeconds,
                        active: true,
                      ),

                      const SizedBox(width: 9),

                      Expanded(
                        child: _SlideToCancelPrompt(
                          cancelProgress: controller.cancelProgress,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Locked state.
              Opacity(
                opacity: lockedProgress,
                child: Transform.translate(
                  offset: Offset(10 * (1 - lockedProgress), 0),
                  child: controller.kind == ChatRecordingKind.roundVideo
                      ? Row(
                          children: [
                            Text(
                              _recordingTime(controller.elapsed),
                              style: const TextStyle(
                                color: WrytteColors.textPrimary,
                                fontFamily: WrytteTypography.primaryFontFamily,
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w400,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                  FontFeature('cv01', 1),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            controller.paused
                                ? const Icon(
                                    Icons.pause_rounded,
                                    color: WrytteColors.textSecondary,
                                    size: 17,
                                  )
                                : _RecordingDot(
                                    second: controller.elapsed.inSeconds,
                                    active: true,
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.paused
                                    ? 'Video paused'
                                    : 'Video message',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: WrytteColors.textSecondary,
                                  fontFamily:
                                      WrytteTypography.primaryFontFamily,
                                  fontSize: 15,
                                  height: 1,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Text(
                              _recordingTime(controller.elapsed),
                              style: const TextStyle(
                                color: WrytteColors.textPrimary,
                                fontFamily: WrytteTypography.primaryFontFamily,
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w400,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                  FontFeature('cv01', 1),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            controller.paused
                                ? const Icon(
                                    Icons.pause_rounded,
                                    color: WrytteColors.textSecondary,
                                    size: 17,
                                  )
                                : _RecordingDot(
                                    second: controller.elapsed.inSeconds,
                                    active: true,
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniWaveform(levels: controller.levels),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PausedVoiceTrimEditor extends StatelessWidget {
  const _PausedVoiceTrimEditor({required this.controller});

  final ChatRecordingController controller;

  @override
  Widget build(BuildContext context) {
    final elapsed = controller.elapsed;
    final trimRange = controller.trimRange;

    final playbackFraction = elapsed.inMicroseconds <= 0
        ? controller.trimStart
        : (controller.previewPosition.inMicroseconds / elapsed.inMicroseconds)
              .clamp(0.0, 1.0)
              .toDouble();

    final playedInSelection = controller.previewPosition - trimRange.start;
    final durationLabel = _recordingTime(
      controller.previewPlaying && !playedInSelection.isNegative
          ? playedInSelection
          : trimRange.duration,
    );

    // This is intentionally the old paused-editor layout: one compact row
    // inside the normal-height recording pill.
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 66),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: controller.previewPlaying ? 'Pause preview' : 'Play preview',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Match the old Wrytte behavior: the preview control stays a real
              // action while paused. The controller owns preparation/retry work.
              onTap: () => unawaited(controller.togglePreview()),
              child: SizedBox(
                width: 34,
                height: ChatComposer.controlSize,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 190),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: .72,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: controller.previewPlaying
                        ? const Icon(
                            Icons.pause_rounded,
                            key: ValueKey('trim-preview-pause'),
                            color: WrytteColors.textSecondary,
                            size: 27,
                          )
                        : KeyedSubtree(
                            key: const ValueKey('trim-preview-play'),
                            child: Transform.scale(
                              scale: 1.18,
                              child: const WrytteSvgIcon(
                                asset: 'assets/svg/Play icon .svg',
                                color: WrytteColors.textSecondary,
                                size: 27,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _VoiceTrimBar(
              controller: controller,
              durationLabel: durationLabel,
              playbackFraction: playbackFraction,
              allowScrub: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PausedVideoTrimEditor extends StatelessWidget {
  const _PausedVideoTrimEditor({required this.controller});

  final ChatRecordingController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.elapsed;
    if (total.inMilliseconds <= 0) {
      return _LiveRecordingStatus(controller: controller);
    }

    final thumbnails = controller.videoThumbnailBytes
        .map<ImageProvider>((bytes) => MemoryImage(bytes))
        .toList(growable: false);

    final range = controller.trimRange;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 72),
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          height: ChatComposer.controlSize,
          child: Row(
            children: [
              Expanded(
                child: _TelegramVideoTrimTimeline(
                  duration: total,
                  span: _VideoTrimSpan(start: range.start, end: range.end),
                  playhead: controller.previewPosition,
                  thumbnails: thumbnails,
                  thumbnailRotation: 0,
                  thumbnailMirrorX: false,
                  thumbnailScale: 1.06,
                  frameColor: Colors.transparent,
                  handleColor: const Color(0xFF5AA4F0),
                  handleGripColor: Colors.white,
                  playheadColor: const Color(0xFFD8DEE7),
                  onInteractionStart: () {},
                  onChanged: (span) {
                    final totalMicros = total.inMicroseconds;
                    if (totalMicros <= 0) return;
                    unawaited(
                      controller.updateTrim(
                        span.start.inMicroseconds / totalMicros,
                        span.end.inMicroseconds / totalMicros,
                      ),
                    );
                  },
                  onChangeEnd: (span) {
                    final totalMicros = total.inMicroseconds;
                    if (totalMicros > 0) {
                      unawaited(
                        controller.updateTrim(
                          span.start.inMicroseconds / totalMicros,
                          span.end.inMicroseconds / totalMicros,
                        ),
                      );
                    }
                    unawaited(controller.seekVideoPreview(span.start));
                    unawaited(controller.playVideoPreview());
                  },
                  onSeek: (position) {
                    unawaited(controller.seekVideoPreview(position));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoTrimSpan {
  const _VideoTrimSpan({required this.start, required this.end});

  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is _VideoTrimSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

enum _VideoTrimDragTarget { none, left, right }

class _TelegramVideoTrimTimeline extends StatefulWidget {
  const _TelegramVideoTrimTimeline({
    required this.duration,
    required this.span,
    required this.playhead,
    required this.thumbnails,
    this.thumbnailRotation = 0,
    this.thumbnailMirrorX = false,
    this.thumbnailScale = 1,
    this.frameColor = Colors.white,
    this.handleColor = Colors.white,
    this.handleGripColor = const Color(0xFF55585E),
    this.playheadColor = Colors.white,
    required this.onInteractionStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onSeek,
  });

  final Duration duration;
  final _VideoTrimSpan span;
  final Duration playhead;
  final List<ImageProvider> thumbnails;
  final double thumbnailRotation;
  final bool thumbnailMirrorX;
  final double thumbnailScale;
  final Color frameColor;
  final Color handleColor;
  final Color handleGripColor;
  final Color playheadColor;
  final VoidCallback onInteractionStart;
  final ValueChanged<_VideoTrimSpan> onChanged;
  final ValueChanged<_VideoTrimSpan> onChangeEnd;
  final ValueChanged<Duration> onSeek;

  @override
  State<_TelegramVideoTrimTimeline> createState() =>
      _TelegramVideoTrimTimelineState();
}

class _TelegramVideoTrimTimelineState
    extends State<_TelegramVideoTrimTimeline> {
  // Scale the old 48px Telegram filmstrip into Wrytte's existing 42px
  // composer pill. The frame strip itself stays square-ended; only the blue
  // trim handles are rounded. The 38px track sits exactly centered in 42px.
  static const double _height = ChatComposer.controlSize;
  static const double _trackInset = 6;
  static const double _trackTop = 2;
  static const double _trackHeight = 38;
  static const double _handleWidth = 20;
  static const double _railThickness = 2;
  static const double _railJoinOverlap = 1;
  static const double _handleTouchRadius = 23;
  static const int _minimumTrimMilliseconds = 100;

  final GlobalKey _timelineKey = GlobalKey();

  late _VideoTrimSpan _displaySpan;
  _VideoTrimDragTarget _dragTarget = _VideoTrimDragTarget.none;
  double _dragGrabOffset = 0;

  Timer? _previewSeekTimer;
  Duration? _pendingPreviewSeek;
  DateTime _lastPreviewSeek = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _displaySpan = widget.span;
  }

  @override
  void didUpdateWidget(covariant _TelegramVideoTrimTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragTarget == _VideoTrimDragTarget.none ||
        oldWidget.span != widget.span) {
      _displaySpan = widget.span;
    }
  }

  @override
  void dispose() {
    _previewSeekTimer?.cancel();
    super.dispose();
  }

  double get _durationMs =>
      math.max(1, widget.duration.inMilliseconds).toDouble();

  double _fraction(Duration value) =>
      (value.inMilliseconds / _durationMs).clamp(0.0, 1.0).toDouble();

  Duration _durationForFraction(double fraction) =>
      Duration(milliseconds: (_durationMs * fraction.clamp(0.0, 1.0)).round());

  RenderBox? get _timelineBox {
    final renderObject = _timelineKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      return renderObject;
    }
    return null;
  }

  double? _localDx(Offset globalPosition) {
    final box = _timelineBox;
    if (box == null) return null;
    return box.globalToLocal(globalPosition).dx;
  }

  double _trackXForFraction(double fraction, double width) {
    final trackWidth = math.max(1.0, width - (_trackInset * 2)).toDouble();
    return _trackInset + (trackWidth * fraction.clamp(0.0, 1.0));
  }

  double _fractionForTrackX(double x, double width) {
    final trackWidth = math.max(1.0, width - (_trackInset * 2)).toDouble();
    return ((x - _trackInset) / trackWidth).clamp(0.0, 1.0).toDouble();
  }

  double get _minimumFraction =>
      math.min(1.0, _minimumTrimMilliseconds / _durationMs).toDouble();

  void _beginDrag(DragStartDetails details, double width) {
    final localX = details.localPosition.dx;
    final startX = _trackXForFraction(_fraction(_displaySpan.start), width);
    final endX = _trackXForFraction(_fraction(_displaySpan.end), width);
    final leftDistance = (localX - startX).abs();
    final rightDistance = (localX - endX).abs();

    if (leftDistance <= _handleTouchRadius ||
        rightDistance <= _handleTouchRadius) {
      if (leftDistance <= rightDistance) {
        _dragTarget = _VideoTrimDragTarget.left;
        _dragGrabOffset = localX - startX;
      } else {
        _dragTarget = _VideoTrimDragTarget.right;
        _dragGrabOffset = localX - endX;
      }

      widget.onInteractionStart();
      unawaited(HapticFeedback.selectionClick());
      setState(() {});
    }
  }

  void _updateDrag(DragUpdateDetails details, double width) {
    if (_dragTarget == _VideoTrimDragTarget.none) return;

    final globalLocalX = _localDx(details.globalPosition);
    if (globalLocalX == null) return;

    final pointerX = globalLocalX - _dragGrabOffset;
    final pointerFraction = _fractionForTrackX(pointerX, width);
    final minFraction = _minimumFraction;
    final startFraction = _fraction(_displaySpan.start);
    final endFraction = _fraction(_displaySpan.end);

    late _VideoTrimSpan nextSpan;
    late Duration previewPosition;

    if (_dragTarget == _VideoTrimDragTarget.left) {
      final nextStart = math
          .min(pointerFraction, math.max(0.0, endFraction - minFraction))
          .toDouble();
      previewPosition = _durationForFraction(nextStart);
      nextSpan = _VideoTrimSpan(start: previewPosition, end: _displaySpan.end);
    } else {
      final nextEnd = math
          .max(pointerFraction, math.min(1.0, startFraction + minFraction))
          .toDouble();
      previewPosition = _durationForFraction(nextEnd);
      nextSpan = _VideoTrimSpan(
        start: _displaySpan.start,
        end: previewPosition,
      );
    }

    if (nextSpan == _displaySpan) return;

    setState(() => _displaySpan = nextSpan);
    widget.onChanged(nextSpan);
    _schedulePreviewSeek(previewPosition);
  }

  void _endDrag() {
    if (_dragTarget == _VideoTrimDragTarget.none) return;

    _flushPreviewSeek();
    final span = _displaySpan;
    setState(() => _dragTarget = _VideoTrimDragTarget.none);
    unawaited(HapticFeedback.lightImpact());
    widget.onChangeEnd(span);
  }

  void _schedulePreviewSeek(Duration position) {
    _pendingPreviewSeek = position;

    final elapsed = DateTime.now().difference(_lastPreviewSeek);
    const cadence = Duration(milliseconds: 24);
    if (elapsed >= cadence) {
      _flushPreviewSeek();
      return;
    }

    _previewSeekTimer?.cancel();
    _previewSeekTimer = Timer(cadence - elapsed, _flushPreviewSeek);
  }

  void _flushPreviewSeek() {
    _previewSeekTimer?.cancel();
    _previewSeekTimer = null;
    final position = _pendingPreviewSeek;
    _pendingPreviewSeek = null;
    if (position == null) return;

    _lastPreviewSeek = DateTime.now();
    widget.onSeek(position);
  }

  void _seekFromTap(TapUpDetails details, double width) {
    final startFraction = _fraction(_displaySpan.start);
    final endFraction = _fraction(_displaySpan.end);
    final tappedFraction = _fractionForTrackX(details.localPosition.dx, width);

    if (tappedFraction < startFraction || tappedFraction > endFraction) {
      return;
    }

    unawaited(HapticFeedback.selectionClick());
    widget.onSeek(_durationForFraction(tappedFraction));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _timelineKey,
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final trackWidth = math
              .max(1.0, width - (_trackInset * 2))
              .toDouble();
          final startFraction = _fraction(_displaySpan.start);
          final endFraction = _fraction(_displaySpan.end);
          final playheadFraction = _fraction(
            widget.playhead,
          ).clamp(startFraction, endFraction).toDouble();

          final startX = _trackInset + (trackWidth * startFraction);
          final endX = _trackInset + (trackWidth * endFraction);
          final playheadX = _trackInset + (trackWidth * playheadFraction);

          final railStartX = startX + (_handleWidth / 2) - _railJoinOverlap;
          final railEndX = endX - (_handleWidth / 2) + _railJoinOverlap;
          final railWidth = math.max(0.0, railEndX - railStartX).toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) => _beginDrag(details, width),
            onHorizontalDragUpdate: (details) => _updateDrag(details, width),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
            onTapUp: (details) => _seekFromTap(details, width),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: _trackInset,
                  right: _trackInset,
                  top: _trackTop,
                  height: _trackHeight,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0xFF15171B)),
                        if (widget.thumbnails.isEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var index = 0; index < 9; index++)
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF050608),
                                      border: Border(
                                        right: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: index == 8 ? 0 : .055,
                                          ),
                                          width: .7,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final thumbnail in widget.thumbnails)
                                Expanded(
                                  child: ClipRect(
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()
                                        ..scale(
                                          widget.thumbnailMirrorX ? -1.0 : 1.0,
                                          1.0,
                                        ),
                                      child: Transform.rotate(
                                        angle: widget.thumbnailRotation,
                                        child: Transform.scale(
                                          scale: widget.thumbnailScale,
                                          child: Image(
                                            image: thumbnail,
                                            fit: BoxFit.cover,
                                            alignment: Alignment.center,
                                            gaplessPlayback: true,
                                            filterQuality: FilterQuality.medium,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (startX > _trackInset)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: startX - _trackInset,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: .56),
                            ),
                          ),
                        if (endX < width - _trackInset)
                          Positioned(
                            left: endX - _trackInset,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: .56),
                            ),
                          ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: .34),
                                  width: .8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (railWidth > 0) ...[
                  Positioned(
                    left: railStartX,
                    top: _trackTop,
                    width: railWidth,
                    height: _railThickness,
                    child: IgnorePointer(
                      child: ColoredBox(color: widget.frameColor),
                    ),
                  ),
                  Positioned(
                    left: railStartX,
                    top: _trackTop + _trackHeight - _railThickness,
                    width: railWidth,
                    height: _railThickness,
                    child: IgnorePointer(
                      child: ColoredBox(color: widget.frameColor),
                    ),
                  ),
                ],
                if (playheadX > startX + 6 && playheadX < endX - 6)
                  Positioned(
                    left: playheadX - 1,
                    top: _trackTop + 5,
                    width: 2,
                    height: _trackHeight - 10,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.playheadColor.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .35),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _buildHandle(
                  x: startX,
                  left: true,
                  active: _dragTarget == _VideoTrimDragTarget.left,
                ),
                _buildHandle(
                  x: endX,
                  left: false,
                  active: _dragTarget == _VideoTrimDragTarget.right,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHandle({
    required double x,
    required bool left,
    required bool active,
  }) {
    return Positioned(
      left: x - (_handleWidth / 2),
      top: _trackTop,
      width: _handleWidth,
      height: _trackHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.handleColor,
            // Preserve the old trim-handle shape: only the OUTER corners
            // are rounded. The inner face stays flat against the filmstrip.
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(left ? 20 : 0),
              bottomLeft: Radius.circular(left ? 20 : 0),
              topRight: Radius.circular(left ? 0 : 20),
              bottomRight: Radius.circular(left ? 0 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? .30 : .22),
                blurRadius: active ? 3 : 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 3,
              height: 11,
              decoration: BoxDecoration(
                color: widget.handleGripColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingReview extends StatelessWidget {
  const _RecordingReview({required this.controller});

  final ChatRecordingController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.kind == ChatRecordingKind.roundVideo) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),

        child: Row(
          children: [
            const Icon(Icons.videocam_rounded, color: WrytteColors.primary),

            const SizedBox(width: 6),

            Expanded(child: _VideoTrimBar(controller: controller)),
          ],
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 38,

          child: IconButton(
            padding: EdgeInsets.zero,

            onPressed: () => unawaited(controller.togglePreview()),

            icon: controller.previewPlaying
                ? const WrytteSvgIcon(
                    asset: 'assets/svg/Pause icon voice .svg',

                    color: WrytteColors.textSecondary,

                    size: 25,
                  )
                : const WrytteSvgIcon(
                    asset: 'assets/svg/Play icon .svg',

                    color: WrytteColors.textSecondary,

                    size: 25,
                  ),
          ),
        ),

        Expanded(child: _VoiceTrimBar(controller: controller)),

        const SizedBox(width: 8),
      ],
    );
  }
}

class _VideoTrimBar extends StatelessWidget {
  const _VideoTrimBar({required this.controller});

  final ChatRecordingController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,

        onHorizontalDragUpdate: (details) {
          final value = (details.localPosition.dx / constraints.maxWidth).clamp(
            0.0,

            1.0,
          );

          if ((value - controller.trimStart).abs() <=
              (value - controller.trimEnd).abs()) {
            unawaited(controller.updateTrim(value, controller.trimEnd));
          } else {
            unawaited(controller.updateTrim(controller.trimStart, value));
          }
        },

        onHorizontalDragEnd: (_) => unawaited(controller.commitTrim()),

        child: CustomPaint(
          painter: _VideoTrimPainter(
            start: controller.trimStart,

            end: controller.trimEnd,
          ),

          child: Center(
            child: Text(
              _recordingTime(controller.trimRange.duration),

              style: const TextStyle(
                color: WrytteColors.textSecondary,

                fontFamily: WrytteTypography.primaryFontFamily,

                fontSize: 13,

                fontFeatures: [
                  FontFeature.tabularFigures(),
                  FontFeature('cv01', 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTrimPainter extends CustomPainter {
  const _VideoTrimPainter({required this.start, required this.end});

  final double start;

  final double end;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 9, size.width, 18),

      const Radius.circular(9),
    );

    canvas.drawRRect(track, Paint()..color = Colors.white10);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          size.width * start,

          size.height / 2 - 9,

          size.width * end,

          size.height / 2 + 9,
        ),

        const Radius.circular(9),
      ),

      Paint()..color = WrytteColors.primary.withValues(alpha: .38),
    );

    final handle = Paint()
      ..color = WrytteColors.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final value in [start, end]) {
      final x = size.width * value;

      canvas.drawLine(Offset(x, 7), Offset(x, size.height - 7), handle);
    }
  }

  @override
  bool shouldRepaint(_VideoTrimPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end;
}

enum _VoiceTrimGesture { startHandle, endHandle, scrub }

class _VoiceTrimBar extends StatefulWidget {
  const _VoiceTrimBar({
    required this.controller,
    this.durationLabel,
    this.playbackFraction,
    this.allowScrub = true,
  });

  final ChatRecordingController controller;
  final String? durationLabel;
  final double? playbackFraction;
  final bool allowScrub;

  @override
  State<_VoiceTrimBar> createState() => _VoiceTrimBarState();
}

class _VoiceTrimBarState extends State<_VoiceTrimBar> {
  static const double _handleInset = 12;
  static const double _handleTouchRadius = 24;

  _VoiceTrimGesture? _gesture;
  double? _interactionFraction;

  double _fractionForPosition(double dx, double width) {
    final trackWidth = math.max(1.0, width - (_handleInset * 2));
    return ((dx - _handleInset) / trackWidth).clamp(0.0, 1.0).toDouble();
  }

  String _formatPrecisePosition(double fraction) {
    final totalMilliseconds = widget.controller.elapsed.inMilliseconds;
    final milliseconds = (totalMilliseconds * fraction.clamp(0.0, 1.0)).round();
    final minutes = milliseconds ~/ Duration.millisecondsPerMinute;
    final seconds =
        (milliseconds ~/ Duration.millisecondsPerSecond) %
        Duration.secondsPerMinute;
    final tenths = (milliseconds % Duration.millisecondsPerSecond) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  void _startTimelineDrag(DragStartDetails details, double width) {
    final trackWidth = math.max(1.0, width - (_handleInset * 2));
    final startX = _handleInset + (trackWidth * widget.controller.trimStart);
    final endX = _handleInset + (trackWidth * widget.controller.trimEnd);
    final pointerX = details.localPosition.dx;

    final startDistance = (pointerX - startX).abs();
    final endDistance = (pointerX - endX).abs();
    final closestDistance = math.min(startDistance, endDistance);
    final pointerFraction = _fractionForPosition(pointerX, width);

    final nextGesture = closestDistance <= _handleTouchRadius
        ? (startDistance <= endDistance
              ? _VoiceTrimGesture.startHandle
              : _VoiceTrimGesture.endHandle)
        : widget.allowScrub &&
              pointerFraction >= widget.controller.trimStart &&
              pointerFraction <= widget.controller.trimEnd
        ? _VoiceTrimGesture.scrub
        : null;

    if (nextGesture == null) return;

    setState(() {
      _gesture = nextGesture;
      _interactionFraction = nextGesture == _VoiceTrimGesture.startHandle
          ? widget.controller.trimStart
          : nextGesture == _VoiceTrimGesture.endHandle
          ? widget.controller.trimEnd
          : pointerFraction;
    });

    if (nextGesture != _VoiceTrimGesture.scrub) {
      unawaited(HapticFeedback.selectionClick());
    } else {
      unawaited(
        widget.controller.seekPreviewFraction(pointerFraction, commit: false),
      );
    }
  }

  void _updateTimelineDrag(DragUpdateDetails details, double width) {
    final gesture = _gesture;
    if (gesture == null) return;

    final fraction = _fractionForPosition(details.localPosition.dx, width);

    if (gesture == _VoiceTrimGesture.startHandle) {
      final nextStart = math.min(fraction, widget.controller.trimEnd - .02);
      setState(() => _interactionFraction = nextStart);
      unawaited(
        widget.controller.updateTrim(nextStart, widget.controller.trimEnd),
      );
    } else if (gesture == _VoiceTrimGesture.endHandle) {
      final nextEnd = math.max(fraction, widget.controller.trimStart + .02);
      setState(() => _interactionFraction = nextEnd);
      unawaited(
        widget.controller.updateTrim(widget.controller.trimStart, nextEnd),
      );
    } else {
      final nextPosition = fraction
          .clamp(widget.controller.trimStart, widget.controller.trimEnd)
          .toDouble();
      setState(() => _interactionFraction = nextPosition);
      unawaited(
        widget.controller.seekPreviewFraction(nextPosition, commit: false),
      );
    }
  }

  void _finishTimelineDrag() {
    final gesture = _gesture;
    final interactionFraction = _interactionFraction;
    if (gesture == null) return;

    if (gesture == _VoiceTrimGesture.scrub && interactionFraction != null) {
      unawaited(
        widget.controller.seekPreviewFraction(
          interactionFraction,
          commit: true,
        ),
      );
    } else {
      unawaited(HapticFeedback.lightImpact());
      unawaited(widget.controller.commitTrim());
    }

    setState(() {
      _gesture = null;
      _interactionFraction = null;
    });
  }

  void _cancelTimelineDrag() {
    if (_gesture == null) return;

    setState(() {
      _gesture = null;
      _interactionFraction = null;
    });
  }

  String? get _displayLabel {
    final base = widget.durationLabel;
    if (base == null) return null;

    final fraction = _interactionFraction;
    if (fraction == null) return base;

    if (_gesture == _VoiceTrimGesture.scrub) {
      return _formatPrecisePosition(fraction);
    }

    return base;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final elapsed = widget.controller.elapsed;
        final playbackFraction =
            widget.playbackFraction ??
            (elapsed.inMicroseconds <= 0
                ? widget.controller.trimStart
                : (widget.controller.previewPosition.inMicroseconds /
                          elapsed.inMicroseconds)
                      .clamp(0.0, 1.0)
                      .toDouble());
        final displayLabel = _displayLabel;

        return SizedBox(
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) =>
                      _startTimelineDrag(details, width),
                  onHorizontalDragUpdate: (details) =>
                      _updateTimelineDrag(details, width),
                  onHorizontalDragEnd: (_) => _finishTimelineDrag(),
                  onHorizontalDragCancel: _cancelTimelineDrag,
                  onTapUp: widget.allowScrub
                      ? (details) {
                          final fraction = _fractionForPosition(
                            details.localPosition.dx,
                            width,
                          );

                          if (fraction < widget.controller.trimStart ||
                              fraction > widget.controller.trimEnd) {
                            return;
                          }

                          unawaited(
                            widget.controller.seekPreviewFraction(
                              fraction,
                              commit: true,
                            ),
                          );
                          unawaited(HapticFeedback.selectionClick());
                        }
                      : null,
                  child: CustomPaint(
                    painter: _VoiceTrimPainter(
                      levels: widget.controller.levels,
                      start: widget.controller.trimStart,
                      end: widget.controller.trimEnd,
                      playhead: playbackFraction,
                      handleInset: _handleInset,
                      activeGesture: _gesture,
                    ),
                  ),
                ),
              ),
              if (displayLabel != null)
                IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18212C).withValues(alpha: .42),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 130),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .18),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        displayLabel,
                        key: ValueKey(displayLabel),
                        style: const TextStyle(
                          color: Color(0xFFE0E3E8),
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 13,
                          height: 1,
                          fontWeight: FontWeight.w400,
                          fontFeatures: [
                            FontFeature.tabularFigures(),
                            FontFeature('cv01', 1),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceTrimPainter extends CustomPainter {
  const _VoiceTrimPainter({
    required this.levels,
    required this.start,
    required this.end,
    required this.playhead,
    required this.handleInset,
    required this.activeGesture,
  });

  static const double _barWidth = 2.2;
  static const double _targetPitch = 4.5;

  final List<double> levels;
  final double start;
  final double end;
  final double playhead;
  final double handleInset;
  final _VoiceTrimGesture? activeGesture;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final capsule = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );

    canvas.drawRRect(capsule, Paint()..color = const Color(0xFF202329));

    canvas.save();
    canvas.clipRRect(capsule);

    final trackWidth = math.max(1.0, size.width - (handleInset * 2));
    final startX = handleInset + (trackWidth * start);
    final endX = handleInset + (trackWidth * end);

    final selectionLeft = (startX - handleInset).clamp(0.0, size.width);
    final selectionRight = (endX + handleInset).clamp(0.0, size.width);

    final selectionRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(selectionLeft, 1, selectionRight, size.height - 1),
      Radius.circular((size.height - 2) / 2),
    );

    final selectionPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF4D8FFF), WrytteColors.primary],
      ).createShader(selectionRect.outerRect);

    canvas.drawRRect(selectionRect, selectionPaint);

    canvas.drawRRect(
      selectionRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = Colors.white.withValues(alpha: .10),
    );

    final safePlayback = playhead.clamp(start, end).toDouble();
    final playbackX = handleInset + (trackWidth * safePlayback);

    final barCount = (trackWidth / _targetPitch).floor().clamp(12, 96);
    final pitch = barCount > 1
        ? (trackWidth - _barWidth) / (barCount - 1)
        : 0.0;

    final barPaint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < barCount; index++) {
      var level = .02;

      if (levels.isNotEmpty) {
        final sourceStart = ((index * levels.length) / barCount).floor();
        final sourceEnd = math.max(
          sourceStart + 1,
          (((index + 1) * levels.length) / barCount).ceil(),
        );

        var peak = .02;
        var energy = 0.0;
        var sampleCount = 0;

        for (
          var sourceIndex = sourceStart;
          sourceIndex < math.min(sourceEnd, levels.length);
          sourceIndex++
        ) {
          final sample = levels[sourceIndex].clamp(.02, 1.0).toDouble();
          peak = math.max(peak, sample);
          energy += sample * sample;
          sampleCount++;
        }

        final rms = sampleCount == 0 ? .02 : math.sqrt(energy / sampleCount);
        level = ((peak * .68) + (rms * .32)).clamp(.02, 1.0).toDouble();
      }

      final x = handleInset + (index * pitch);
      final barCenter = x + (_barWidth / 2);
      final selected = barCenter >= startX && barCenter <= endX;
      final played =
          selected && safePlayback > start + .001 && barCenter <= playbackX;

      final barHeight = 2.5 + (level * (size.height - 17));
      final top = (size.height - barHeight) / 2;

      barPaint.color = !selected
          ? const Color(0xFFADB0B6).withValues(alpha: .82)
          : played
          ? WrytteColors.textPrimary.withValues(alpha: .98)
          : WrytteColors.textSecondary.withValues(alpha: .58);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, _barWidth, barHeight),
          const Radius.circular(_barWidth / 2),
        ),
        barPaint,
      );
    }

    const handleWidth = 4.0;
    final handleHeight = (size.height * .76).clamp(25.0, 27.0).toDouble();

    for (final handle in <({double x, bool active})>[
      (x: startX, active: activeGesture == _VoiceTrimGesture.startHandle),
      (x: endX, active: activeGesture == _VoiceTrimGesture.endHandle),
    ]) {
      final handleTop = (size.height - handleHeight) / 2;
      final handleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          handle.x - (handleWidth / 2),
          handleTop,
          handleWidth,
          handleHeight,
        ),
        const Radius.circular(handleWidth / 2),
      );

      canvas.saveLayer(handleRect.outerRect.inflate(6), Paint());

      canvas.drawRRect(
        handleRect,
        Paint()
          ..color = Colors.white.withValues(alpha: handle.active ? .46 : .22)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            handle.active ? 5 : 3,
          ),
      );

      canvas.drawRRect(handleRect, Paint()..color = WrytteColors.textPrimary);

      final cutoutWidth = math.min(2.0, handleWidth * .50);
      const cutoutHeight = 7.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(handle.x, size.height / 2),
            width: cutoutWidth,
            height: cutoutHeight,
          ),
          Radius.circular(cutoutWidth / 2),
        ),
        Paint()..blendMode = BlendMode.clear,
      );

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VoiceTrimPainter oldDelegate) {
    return !identical(levels, oldDelegate.levels) ||
        start != oldDelegate.start ||
        end != oldDelegate.end ||
        playhead != oldDelegate.playhead ||
        handleInset != oldDelegate.handleInset ||
        activeGesture != oldDelegate.activeGesture;
  }
}

class _RecordingAction extends StatefulWidget {
  const _RecordingAction({required this.controller, required this.size});

  final ChatRecordingController controller;
  final double size;

  @override
  State<_RecordingAction> createState() => _RecordingActionState();
}

class _RecordingActionState extends State<_RecordingAction> {
  final LayerLink _lockGuideLink = LayerLink();
  OverlayEntry? _lockGuideEntry;

  ChatRecordingController get controller => widget.controller;

  Future<void> _runWithPressFeedback(Future<void> Function() action) async {
    await Feedback.forLongPress(context);
    if (!mounted) return;
    await action();
  }

  bool get _shouldShowLockGuide {
    final phase = controller.phase;

    return !controller.reviewing &&
        (phase == ChatRecordingPhase.preparing ||
            phase == ChatRecordingPhase.holding ||
            phase == ChatRecordingPhase.locked ||
            phase == ChatRecordingPhase.paused);
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleControllerChanged);

    // The target must be laid out before an OverlayEntry can follow it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncLockGuide();
    });
  }

  @override
  void didUpdateWidget(covariant _RecordingAction oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncLockGuide();
    });
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncLockGuide();
  }

  void _syncLockGuide() {
    if (!mounted) return;

    if (_shouldShowLockGuide) {
      final entry = _lockGuideEntry;

      if (entry == null) {
        _showLockGuide();
      } else {
        entry.markNeedsBuild();
      }

      return;
    }

    _removeLockGuide();
  }

  void _showLockGuide() {
    if (_lockGuideEntry != null || !mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) {
        final phase = controller.phase;
        final holding =
            phase == ChatRecordingPhase.holding ||
            phase == ChatRecordingPhase.preparing;
        final locked = controller.locked;

        final lockProgress = locked
            ? 1.0
            : holding
            ? controller.lockProgress
            : 0.0;

        final guideSize = math.max(34.0, widget.size - 6.0);

        return Positioned(
          width: guideSize,
          child: CompositedTransformFollower(
            link: _lockGuideLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -28),
            child: Material(
              type: MaterialType.transparency,
              child: _RecordingLockGuide(
                size: guideSize,
                kind: controller.kind,
                locked: locked,
                paused: controller.paused,
                busy: controller.pauseResumeBusy,
                lockProgress: lockProgress,
                onPause: () => unawaited(
                  _runWithPressFeedback(controller.pauseLockedRecording),
                ),
                onResume: () => unawaited(
                  _runWithPressFeedback(controller.resumeLockedRecording),
                ),
              ),
            ),
          ),
        );
      },
    );

    _lockGuideEntry = entry;
    overlay.insert(entry);
  }

  void _removeLockGuide() {
    _lockGuideEntry?.remove();
    _lockGuideEntry = null;
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _removeLockGuide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    final holding =
        controller.phase == ChatRecordingPhase.holding ||
        controller.phase == ChatRecordingPhase.preparing;
    final locked = controller.locked;
    final active = controller.active;

    final cancelProgress = holding ? controller.cancelProgress : 0.0;

    // This is intentionally the OLD movement model:
    //
    // - left cancel follows the real finger path almost 1:1
    // - upward lock motion is only ~19.5px
    // - diagonal/downward movement is clamped by the controller
    // - when cancel progress grows the blue button shrinks
    final dragOffset = holding ? controller.visualDragOffset : Offset.zero;

    final cancelScale = (1 - (.42 * cancelProgress)).clamp(.58, 1.0).toDouble();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // IMPORTANT:
        //
        // The old lock/pause control lived in a root Overlay. It must NOT be a
        // Positioned child painted above this small Stack. Flutter can paint a
        // child outside the Stack with Clip.none, but it cannot hit-test that
        // child outside the Stack's own bounds. The blue button is therefore
        // the composited target; _showLockGuide() paints the actual interactive
        // guide in the root Overlay where taps work normally.
        CompositedTransformTarget(
          link: _lockGuideLink,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(end: dragOffset),
            duration: Duration(milliseconds: locked ? 220 : 65),
            curve: Curves.easeOutCubic,
            builder: (context, offset, child) {
              return Transform.translate(offset: offset, child: child);
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: cancelScale),
              duration: const Duration(milliseconds: 65),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: AnimatedScale(
                // The old button grew to 1.40x for the whole active recording,
                // including the locked and paused states.
                scale: active ? 1.40 : 1,
                duration: const Duration(milliseconds: 180),
                curve: active ? Curves.easeOutBack : Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: active ? size + 1.5 : size,
                  height: active ? size + 1.5 : size,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5AA4F0),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .10),
                      width: .8,
                    ),
                    boxShadow: const [],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: locked && !controller.pauseResumeBusy
                        ? () =>
                              unawaited(_runWithPressFeedback(controller.send))
                        : null,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 175),
                      reverseDuration: const Duration(milliseconds: 210),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        final turn = Tween<double>(
                          begin: -.08,
                          end: 0,
                        ).animate(animation);
                        final iconScale = Tween<double>(
                          begin: .58,
                          end: 1,
                        ).animate(animation);

                        return FadeTransition(
                          opacity: animation,
                          child: RotationTransition(
                            turns: turn,
                            child: ScaleTransition(
                              scale: iconScale,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: locked
                          ? KeyedSubtree(
                              key: const ValueKey('locked-recording-send'),
                              child: Transform.translate(
                                offset: const Offset(-1.5, 0),
                                child: Transform.rotate(
                                  angle: math.pi / 4,
                                  child: const WrytteSvgIcon(
                                    asset: 'assets/svg/Send icon .svg',
                                    color: Colors.white,
                                    size: 27,
                                  ),
                                ),
                              ),
                            )
                          : KeyedSubtree(
                              key: ValueKey(controller.kind),
                              child: WrytteSvgIcon(
                                asset:
                                    controller.kind == ChatRecordingKind.voice
                                    ? 'assets/svg/New voice msg icon .svg'
                                    : 'assets/svg/Video Message.svg',
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordingLockGuide extends StatelessWidget {
  const _RecordingLockGuide({
    required this.size,
    required this.kind,
    required this.locked,
    required this.paused,
    required this.busy,
    required this.lockProgress,
    required this.onPause,
    required this.onResume,
  });

  final double size;
  final ChatRecordingKind kind;
  final bool locked;
  final bool paused;
  final bool busy;
  final double lockProgress;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final unlockedGuideContent = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const WrytteSvgIcon(
          asset: 'assets/svg/Lock open Voice msg (1).svg',
          size: 21,
          color: Color(0xFFF7F8FA),
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: lockProgress),
          duration: const Duration(milliseconds: 65),
          curve: Curves.easeOutCubic,
          builder: (context, progress, child) {
            return Transform.translate(
              offset: Offset(0, -(8 * progress)),
              child: child,
            );
          },
          child: const RotatedBox(
            quarterTurns: 1,
            child: WrytteSvgIcon(
              asset: 'assets/svg/Arrow voice area.svg',
              size: 20,
              color: Color(0xFFF7F8FA),
            ),
          ),
        ),
      ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, visibility, child) {
        return Opacity(
          opacity: visibility,
          child: Transform.scale(
            scale: .88 + (visibility * .12),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: IgnorePointer(
        ignoring: !locked,
        child: Semantics(
          button: locked,
          enabled: locked && !busy,
          label: paused ? 'Resume recording' : 'Pause recording',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: !locked || busy
                ? null
                : paused
                ? onResume
                : onPause,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 175),
              curve: Curves.easeOutCubic,
              width: size,
              height: locked ? size : 72,
              child: WrytteGlassSurface(
                borderRadius: BorderRadius.circular(size / 2),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: locked ? 0 : 1,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        scale: locked ? .76 : 1,
                        child: OverflowBox(
                          minHeight: 72,
                          maxHeight: 72,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: size,
                            height: 72,
                            child: unlockedGuideContent,
                          ),
                        ),
                      ),
                    ),

                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      opacity: locked ? 1 : 0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 175),
                        curve: Curves.easeOutBack,
                        scale: locked ? 1 : .62,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          reverseDuration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: .65,
                                  end: 1,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: paused
                              ? KeyedSubtree(
                                  key: ValueKey(
                                    'resume-locked-recording-${kind.name}',
                                  ),
                                  child: Transform.scale(
                                    scale: .96,
                                    child: WrytteSvgIcon(
                                      asset: kind == ChatRecordingKind.voice
                                          ? 'assets/svg/ph--microphone.svg'
                                          : 'assets/svg/Video Message.svg',
                                      color: Colors.white,
                                      size: 27,
                                    ),
                                  ),
                                )
                              : const KeyedSubtree(
                                  key: ValueKey('pause-locked-recording'),
                                  child: WrytteSvgIcon(
                                    asset: 'assets/svg/Pause icon voice .svg',
                                    color: Colors.white,
                                    size: 28,
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
}

class _RoundVideoRecordingOverlay extends StatefulWidget {
  const _RoundVideoRecordingOverlay({
    required this.controller,
    required this.controlSize,
    required this.scale,
    required this.horizontalPadding,
    required this.availableSize,
    required this.recorderBottomInset,
    required this.compact,
    required this.bottomSystemInset,
  });

  final ChatRecordingController controller;
  final double controlSize;
  final double scale;
  final double horizontalPadding;
  final Size availableSize;
  final double recorderBottomInset;
  final bool compact;
  final double bottomSystemInset;

  @override
  State<_RoundVideoRecordingOverlay> createState() =>
      _RoundVideoRecordingOverlayState();
}

class _RoundVideoRecordingOverlayState
    extends State<_RoundVideoRecordingOverlay>
    with SingleTickerProviderStateMixin {
  static const double _roundVideoCoverBleed = 1.06;

  double _zoomAtGestureStart = 1;
  late final AnimationController _entranceController;
  late final Animation<double> _entrance;

  ChatRecordingController get controller => widget.controller;

  Future<void> _runVideoControlWithFeedback(
    Future<void> Function() action,
  ) async {
    await Feedback.forLongPress(context);
    if (!mounted) return;
    await action();
  }

  Future<void> _togglePausedVideoMute() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    await controller.togglePausedVideoMute();
  }

  double _stagedProgress(
    double value, {
    required double start,
    required double end,
  }) {
    if (end <= start) return value >= end ? 1 : 0;
    final normalized = ((value - start) / (end - start))
        .clamp(0.0, 1.0)
        .toDouble();
    return Curves.easeOutCubic.transform(normalized);
  }

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 165),
    );
    _entrance = CurvedAnimation(
      parent: _entranceController,
      curve: const Cubic(.18, .92, .22, 1),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = widget.availableSize;
    final composerBottomGap = ChatComposer.bottomGapFor(context);

    // Preserve the large old recorder when the IME is closed. Over an open
    // keyboard, shrink the preview with the half-height panel so every control
    // fits without covering the upper conversation.
    final previewDiameter = widget.compact
        ? math.min(
            mediaSize.width * .52,
            math.min(mediaSize.height * .46, 210.0),
          )
        : math.min(
            mediaSize.width * .84,
            math.min(mediaSize.height * .48, 420.0),
          );

    final progress =
        (controller.elapsed.inMilliseconds /
                ChatRecordingController.maxRoundVideoDuration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

    // Match the composer's restored bottom geometry exactly. The recorder
    // controls must sit on the same baseline as the normal composer.
    final bottomSafeGap = widget.bottomSystemInset + composerBottomGap;
    // `_RecordingLockGuide` derives the pause circle from this same formula.
    // Keep the two camera actions on its exact centerline and use its exact
    // footprint in both full-height and keyboard-compact recorder layouts.
    final secondaryControlSize = math.max(34.0, widget.controlSize - 6.0);
    final secondaryControlsBottom = bottomSafeGap + widget.controlSize + 28.0;

    final cameraState = controller.cameraState;
    final cameraReady =
        cameraState.status != CameraSessionStatus.closed &&
        cameraState.status != CameraSessionStatus.opening &&
        cameraState.status != CameraSessionStatus.failure;

    final activeDevice = cameraState.activeDevice;
    final frontCamera = activeDevice?.isFront == true;

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        final visualProgress = _entrance.value.clamp(0.0, 1.0).toDouble();

        // One controller drives the whole entrance. Each surface gets a tiny
        // timing offset, but they overlap heavily so the interaction reads as
        // one fast, coherent motion rather than several independent animations.
        final backdropProgress = _stagedProgress(
          visualProgress,
          start: 0,
          end: .78,
        );
        final circleProgress = _stagedProgress(
          visualProgress,
          start: .04,
          end: 1,
        );
        final cameraControlsProgress = _stagedProgress(
          visualProgress,
          start: .18,
          end: 1,
        );
        final switchCameraProgress = _stagedProgress(
          visualProgress,
          start: .20,
          end: .78,
        );
        final flashProgress = _stagedProgress(
          visualProgress,
          start: .30,
          end: .94,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Same old full-screen chat blur/dark wash, but only the visual
            // backdrop fades in. The recorder controls below are present and
            // interactive on the very first frame.
            Positioned.fill(
              child: Opacity(
                opacity: backdropProgress,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 38 * backdropProgress,
                        sigmaY: 38 * backdropProgress,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .72),
                              Colors.black.withValues(alpha: .80),
                              Colors.black.withValues(alpha: .90),
                            ],
                            stops: const [0, .54, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: widget.recorderBottomInset,
              height: mediaSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Old round-video entrance motion, restricted to the visual
                  // preview so the bottom recorder never slides/fades in late.
                  Positioned.fill(
                    child: Align(
                      alignment: widget.compact
                          ? const Alignment(0, -.30)
                          : Alignment.center,
                      child: Opacity(
                        opacity: circleProgress,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            ((widget.compact ? 28 : 46) *
                                    (1 - circleProgress)) -
                                ((widget.compact ? 10 : 18) * widget.scale),
                          ),
                          child: Transform.scale(
                            scale: .955 + (.045 * circleProgress),
                            alignment: Alignment.bottomCenter,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: controller.paused
                                  ? null
                                  : (_) {
                                      _zoomAtGestureStart = cameraState.zoom;
                                    },
                              onScaleUpdate: controller.paused
                                  ? null
                                  : (details) {
                                      final target =
                                          (_zoomAtGestureStart * details.scale)
                                              .clamp(
                                                controller.videoMinimumZoom,
                                                controller.videoMaximumZoom,
                                              );
                                      unawaited(
                                        controller.setVideoZoom(
                                          target.toDouble(),
                                        ),
                                      );
                                    },
                              child: SizedBox.square(
                                dimension: previewDiameter,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipOval(
                                      child: SizedBox.square(
                                        dimension: previewDiameter,
                                        child: ColoredBox(
                                          color: Colors.black,
                                          child: controller.paused
                                              ? _buildPausedVideoFeed()
                                              : cameraReady
                                              ? Transform.scale(
                                                  scale: _roundVideoCoverBleed,
                                                  alignment: Alignment.center,
                                                  child: controller
                                                      .buildCameraPreview(),
                                                )
                                              : _buildRoundVideoStatusPreview(
                                                  loading:
                                                      cameraState.status ==
                                                      CameraSessionStatus
                                                          .opening,
                                                ),
                                        ),
                                      ),
                                    ),

                                    if (controller.paused)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: previewDiameter * .055,
                                        child: Center(
                                          child: AnimatedOpacity(
                                            opacity:
                                                controller.videoPreviewReady
                                                ? 1
                                                : .58,
                                            duration: const Duration(
                                              milliseconds: 130,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            child: IgnorePointer(
                                              ignoring:
                                                  !controller.videoPreviewReady,
                                              child: Semantics(
                                                button: true,
                                                label:
                                                    controller.videoPreviewMuted
                                                    ? 'Unmute video preview'
                                                    : 'Mute video preview',
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    unawaited(
                                                      _togglePausedVideoMute(),
                                                    );
                                                  },
                                                  child: Container(
                                                    width: widget.compact
                                                        ? 30
                                                        : 36,
                                                    height: widget.compact
                                                        ? 30
                                                        : 36,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF05070A,
                                                      ).withValues(alpha: .46),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: AnimatedSwitcher(
                                                      duration: const Duration(
                                                        milliseconds: 130,
                                                      ),
                                                      switchInCurve:
                                                          Curves.easeOutCubic,
                                                      switchOutCurve:
                                                          Curves.easeInCubic,
                                                      child: WrytteSvgIcon(
                                                        key: ValueKey(
                                                          controller
                                                              .videoPreviewMuted,
                                                        ),
                                                        asset:
                                                            controller
                                                                .videoPreviewMuted
                                                            ? 'assets/svg/Nosound icon.svg'
                                                            : 'assets/svg/Sound icon.svg',
                                                        size: widget.compact
                                                            ? 13
                                                            : 15,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // Exact old progress treatment: no inactive track,
                                    // starts at 12 o'clock and stays inside the circle.
                                    if (cameraReady ||
                                        controller.videoPreviewReady)
                                      IgnorePointer(
                                        child: CustomPaint(
                                          size: Size.square(previewDiameter),
                                          painter: _RoundProgressPainter(
                                            progress,
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
                    ),
                  ),

                  // Video-only secondary controls use the same quick fade/rise
                  // language on entry AND exit. Pausing removes them completely so
                  // the paused trim state stays clean.
                  PositionedDirectional(
                    start: widget.horizontalPadding,
                    bottom: secondaryControlsBottom,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      reverseDuration: const Duration(milliseconds: 135),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final offset = Tween<Offset>(
                          begin: const Offset(0, .22),
                          end: Offset.zero,
                        ).animate(animation);
                        final scale = Tween<double>(
                          begin: .94,
                          end: 1,
                        ).animate(animation);

                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: offset,
                            child: ScaleTransition(
                              scale: scale,
                              alignment: Alignment.bottomLeft,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: controller.paused
                          ? const SizedBox.shrink(
                              key: ValueKey('paused-video-secondary-controls'),
                            )
                          : KeyedSubtree(
                              key: const ValueKey(
                                'live-video-secondary-controls',
                              ),
                              child: Opacity(
                                opacity: cameraControlsProgress,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    8 * (1 - cameraControlsProgress),
                                  ),
                                  child: Transform.scale(
                                    scale: .96 + (.04 * cameraControlsProgress),
                                    alignment: Alignment.bottomLeft,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _RoundVideoCameraControlEntrance(
                                          progress: switchCameraProgress,
                                          child: WrytteGlassIconButton(
                                            semanticLabel: frontCamera
                                                ? 'Switch to back camera'
                                                : 'Switch to front camera',
                                            onPressed:
                                                controller
                                                        .canSwitchVideoCamera &&
                                                    !controller.pauseResumeBusy
                                                ? () => unawaited(
                                                    _runVideoControlWithFeedback(
                                                      controller
                                                          .switchVideoCamera,
                                                    ),
                                                  )
                                                : null,
                                            size: secondaryControlSize,
                                            child: WrytteSvgIcon(
                                              asset:
                                                  'assets/svg/Flip camera icon .svg',
                                              color: const Color(0xFFF3F4F6),
                                              size: 22 * widget.scale,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10 * widget.scale),
                                        _RoundVideoCameraControlEntrance(
                                          progress: flashProgress,
                                          child: WrytteGlassIconButton(
                                            semanticLabel:
                                                controller.videoFlashEnabled
                                                ? 'Turn flash off'
                                                : 'Turn flash on',
                                            onPressed:
                                                controller.canUseVideoFlash &&
                                                    !controller.pauseResumeBusy
                                                ? () => unawaited(
                                                    _runVideoControlWithFeedback(
                                                      controller
                                                          .toggleVideoFlash,
                                                    ),
                                                  )
                                                : null,
                                            size: secondaryControlSize,
                                            child: WrytteSvgIcon(
                                              asset:
                                                  controller.videoFlashEnabled
                                                  ? 'assets/svg/Flash on icon .svg'
                                                  : 'assets/svg/Flash off icon.svg',
                                              color: const Color(0xFFF3F4F6),
                                              size: 22 * widget.scale,
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
                  ),

                  // SAME bottom recorder as voice mode, with the SAME fast transition
                  // language. The video overlay exists in the root Overlay, so without
                  // this wrapper it used to pop in while the audio recorder smoothly
                  // replaced the idle composer.
                  PositionedDirectional(
                    start: widget.horizontalPadding,
                    end: widget.horizontalPadding,
                    bottom: bottomSafeGap,
                    child: _RecordingComposerEntrance(
                      animation: _entrance,
                      child: _ActiveRecordingComposer(
                        controller: controller,
                        controlSize: widget.controlSize,
                        scale: widget.scale,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPausedVideoFeed() {
    final player = controller.videoPreviewController;

    if (player == null || !player.value.isInitialized) {
      return _buildRoundVideoStatusPreview(
        loading: controller.videoPreviewPreparing,
      );
    }

    final size = player.value.size;
    final aspect = size.width > 0 && size.height > 0
        ? size.width / size.height
        : 1.0;

    const baseExtent = 1000.0;
    final sourceWidth = aspect >= 1 ? baseExtent * aspect : baseExtent;
    final sourceHeight = aspect >= 1 ? baseExtent : baseExtent / aspect;

    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          child: Transform.scale(
            scale: _roundVideoCoverBleed,
            child: SizedBox(
              width: sourceWidth,
              height: sourceHeight,
              child: VideoPlayer(player),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoundVideoStatusPreview({required bool loading}) {
    final glowAlpha = loading ? .78 : .72;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                const Color(0xFF28313A).withValues(alpha: glowAlpha),
                const Color(0xFF090B0F).withValues(alpha: .92),
              ],
              center: const Alignment(0, -.18),
              radius: .96,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RoundVideoCameraControlEntrance extends StatelessWidget {
  const _RoundVideoCameraControlEntrance({
    required this.progress,
    required this.child,
  });

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0).toDouble();
    return IgnorePointer(
      ignoring: value < .92,
      child: Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: Transform.scale(
            scale: .90 + (.10 * value),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RoundProgressPainter extends CustomPainter {
  const _RoundProgressPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const startAngle = -math.pi / 2;
    const sweepSpan = math.pi * 2;
    final rect = Offset.zero & size;
    final center = rect.center;

    // Exact old round-video ring: inside the video circle, no inactive track.
    final radius = (math.min(size.width, size.height) / 2) - 4.5;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFFB7BDC6);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepSpan * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RoundProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MiniWaveform extends StatelessWidget {
  const _MiniWaveform({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _WaveformPainter(levels: levels),

    size: const Size(double.infinity, 30),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.levels,

    this.start = 0,

    this.end = 1,

    this.playhead = 0,

    this.showHandles = false,
  });

  final List<double> levels;

  final double start;

  final double end;

  final double playhead;

  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 3.2;

    final count = math.max(1, (size.width / spacing).floor());

    final paint = Paint()
      ..color = WrytteColors.textSecondary
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round;

    if (!showHandles) {
      // LIVE waveform:
      // Do not pre-fill the width with repeated placeholder bars. Start with
      // the first real samples at the RIGHT edge. Every new sample shifts the
      // existing waveform left immediately, so motion begins from the very
      // start of recording rather than only after the container fills.
      if (levels.isNotEmpty) {
        final visibleCount = math.min(count, levels.length);
        final sourceOffset = levels.length - visibleCount;
        final firstX = size.width - 1 - ((visibleCount - 1) * spacing);

        for (var i = 0; i < visibleCount; i++) {
          final source = levels[sourceOffset + i];
          final height = 4 + source * (size.height - 9);
          final x = firstX + (i * spacing);

          canvas.drawLine(
            Offset(x, (size.height - height) / 2),
            Offset(x, (size.height + height) / 2),
            paint,
          );
        }
      }
    } else {
      // Review/trim waveform keeps filling the available editing track.
      final values = levels.isEmpty ? const <double>[.16, .3, .2, .42] : levels;
      final offset = math.max(0, values.length - count);

      for (var i = 0; i < count; i++) {
        final source = values[(offset + i).clamp(0, values.length - 1)];
        final height = 4 + source * (size.height - 9);
        final x = i * spacing + 1;

        canvas.drawLine(
          Offset(x, (size.height - height) / 2),
          Offset(x, (size.height + height) / 2),
          paint,
        );
      }
    }

    if (showHandles) {
      final overlay = Paint()..color = Colors.black.withValues(alpha: .46);

      canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width * start, size.height),

        overlay,
      );

      canvas.drawRect(
        Rect.fromLTRB(size.width * end, 0, size.width, size.height),

        overlay,
      );

      final handle = Paint()
        ..color = WrytteColors.primary
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(size.width * start, 3),

        Offset(size.width * start, size.height - 3),

        handle,
      );

      canvas.drawLine(
        Offset(size.width * end, 3),

        Offset(size.width * end, size.height - 3),

        handle,
      );

      final px = size.width * playhead.clamp(start, end);

      canvas.drawLine(
        Offset(px, 2),

        Offset(px, size.height - 2),

        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot({required this.second, required this.active});

  final int second;
  final bool active;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );

    if (widget.active) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.active) {
      _controller.stop();
      return;
    }

    // Old Wrytte behavior: the elapsed-second update restarts the pulse so the
    // dot is fully red on the exact frame the displayed number changes.
    if (!oldWidget.active || oldWidget.second != widget.second) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SizedBox.square(
      dimension: 10,
      child: Center(
        child: reduceMotion || !widget.active
            ? const SizedBox.square(
                dimension: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WrytteColors.destructive,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : AnimatedBuilder(
                animation: _controller,
                child: const SizedBox.square(
                  dimension: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WrytteColors.destructive,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                builder: (context, child) {
                  final progress = _controller.value.clamp(0.0, 1.0);
                  final opacity = 1 - Curves.easeInOutCubic.transform(progress);

                  return Opacity(opacity: opacity, child: child);
                },
              ),
      ),
    );
  }
}

String _recordingTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 3599);

  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _RecordModeButton extends StatelessWidget {
  const _RecordModeButton({
    super.key,

    required this.recordMode,

    required this.size,

    required this.scale,

    required this.onPressed,

    required this.gestureKey,
  });

  final ChatRecordMode recordMode;

  final double size;

  final double scale;

  final VoidCallback onPressed;

  final GlobalKey gestureKey;

  @override
  Widget build(BuildContext context) {
    final isAudio = recordMode == ChatRecordMode.audio;

    return Semantics(
      button: true,

      label: isAudio
          ? 'Switch to video message mode'
          : 'Switch to voice message mode',

      onTap: onPressed,

      child: SizedBox.square(
        key: gestureKey,

        dimension: size,

        child: WrytteGlassSurface(
          borderRadius: BorderRadius.circular(size / 2),

          child: Center(
            child: Transform.scale(
              scale: isAudio ? _microphoneOpticalScale : _videoOpticalScale,

              child: WrytteSvgIcon(
                asset: isAudio
                    ? 'assets/svg/New voice msg icon .svg'
                    : 'assets/svg/Video Message.svg',

                size: _composerMainIconCanvas * scale,

                color: WrytteColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    super.key,

    required this.size,

    required this.scale,

    required this.onPressed,
  });

  final double size;

  final double scale;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,

      label: 'Send message',

      child: GestureDetector(
        behavior: HitTestBehavior.opaque,

        onTap: onPressed,

        child: Container(
          width: size,

          height: size,

          decoration: const BoxDecoration(
            color: WrytteColors.primary,

            shape: BoxShape.circle,
          ),

          child: Center(
            child: Transform.translate(
              offset: const Offset(-1.5, 0),

              child: Transform.rotate(
                angle: math.pi / 4,

                child: Transform.scale(
                  scale: _sendOpticalScale,

                  child: WrytteSvgIcon(
                    asset: 'assets/svg/Send icon .svg',

                    size: _composerMainIconCanvas * scale,

                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
