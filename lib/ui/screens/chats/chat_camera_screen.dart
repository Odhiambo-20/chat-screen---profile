// Chat camera view.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraErrorEvent, CameraPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:wrytte/services/media/camera_inventory_service.dart';
import 'package:wrytte/services/permissions/app_permission_service.dart';
import 'package:wrytte/services/permissions/photo_library_permission_service.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/models/chat_models/ui/chat_camera_result.dart';
import 'package:wrytte/ui/auth/profile_photo_crop_page.dart';
import 'package:wrytte/ui/screens/chats/chat_media_editor.dart';
import 'package:wrytte/ui/widgets/global/media/wrytte_camera_preview_surface.dart';

export 'package:wrytte/models/chat_models/ui/chat_camera_result.dart';

class _CameraPreviewRectTransitionDelegate extends SingleChildLayoutDelegate {
  _CameraPreviewRectTransitionDelegate({
    required this.animation,
    required this.sourceRect,
  }) : super(relayout: animation);

  final Animation<double> animation;
  final Rect sourceRect;

  Rect _rectFor(Size viewport) {
    final destination = Offset.zero & viewport;
    final boundedSource = Rect.fromLTRB(
      sourceRect.left.clamp(0.0, viewport.width).toDouble(),
      sourceRect.top.clamp(0.0, viewport.height).toDouble(),
      sourceRect.right.clamp(0.0, viewport.width).toDouble(),
      sourceRect.bottom.clamp(0.0, viewport.height).toDouble(),
    );
    if (boundedSource.isEmpty || !boundedSource.isFinite) return destination;
    final progress = Curves.easeInOutCubic.transform(animation.value);
    return Rect.lerp(boundedSource, destination, progress)!;
  }

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.tight(_rectFor(constraints.biggest).size);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return _rectFor(size).topLeft;
  }

  @override
  bool shouldRelayout(_CameraPreviewRectTransitionDelegate oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.sourceRect != sourceRect;
  }
}

class ChatCameraScreen extends StatefulWidget {
  final String recipientLabel;
  final CameraController? initialController;
  final bool initialAudioEnabled;
  final bool photoOnly;
  final Rect? openingCameraRect;
  final void Function(CameraController controller, bool audioEnabled)?
  onReturnController;

  const ChatCameraScreen({
    super.key,
    required this.recipientLabel,
    this.initialController,
    this.initialAudioEnabled = false,
    this.photoOnly = false,
    this.openingCameraRect,
    this.onReturnController,
  });

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const Color _background = Color(0xFF050608);
  static const Color _blue = WrytteColors.primary;
  static const Color _videoRed = Color(0xFFFF4D4F);
  static const Color _profilePhotoControlColor = Color(0xFFF5F5F5);

  CameraController? _controller;
  bool _ownsController = false;
  List<CameraDescription> _cameras = <CameraDescription>[];

  ChatCameraMode _mode = ChatCameraMode.photo;
  FlashMode _flashMode = FlashMode.off;

  bool _initializing = true;
  bool _cameraPermissionDenied = false;
  bool _microphonePermissionDenied = false;
  bool _captureBusy = false;
  bool _switchingCamera = false;
  bool _closingCamera = false;
  bool _openingEditor = false;
  bool _cameraPreviewPausedForEditor = false;
  bool _audioEnabled = false;
  bool _microphonePermissionResolved = false;
  bool _recording = false;

  int _cameraGeneration = 0;
  Future<void>? _cameraInitialisationInFlight;

  static const Duration _cameraInitialisationTimeout = Duration(seconds: 7);
  static const Duration _cameraOperationTimeout = Duration(seconds: 3);
  static const Duration _zoomOperationTimeout = Duration(milliseconds: 1600);

  double _minZoom = 1;
  double _maxZoom = 1;

  // Display zoom is what the user sees (0.5x, 1x, 2x...). Native zoom is what
  // the active CameraController accepts. They differ on a physical ultra-wide
  // camera, where native 1.0 represents Wrytte's 0.5x view.
  double _displayZoom = 1;
  double _appliedNativeZoom = 1;
  double _lastPinchScale = 1;
  // Native zoom 1.0 does not always mean user-facing 1x. On a physical
  // ultra-wide camera native 1.0 may represent ~0.5x relative to the default
  // wide camera. CameraInventoryService supplies that intrinsic base ratio.
  double _activeCameraBaseZoom = 1.0;
  bool _lensTransitionInFlight = false;
  double? _pendingDisplayZoomAfterLensSwitch;
  CameraDescription? _lastCameraDescription;

  final SmoothCameraZoomController _zoomSmoother = SmoothCameraZoomController();
  StreamSubscription<CameraErrorEvent>? _cameraErrorSubscription;
  late final AnimationController _tapZoomAnimationController;
  double _tapZoomFrom = 1;
  double _tapZoomTo = 1;
  bool _pinchZoomActive = false;

  Offset? _focusPoint;
  Timer? _focusTimer;

  Timer? _recordingTimer;
  final Stopwatch _recordingStopwatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;

  AssetEntity? _latestAsset;
  Uint8List? _latestAssetThumbnail;

  // Keep the camera shortcut's media query aligned with the attachment
  // Recents picker. On some legacy Android/LDPlayer combinations,
  // photo_manager can otherwise build an invalid paged query.
  final PMFilter _latestMediaFilter = PMFilter.defaultValue();

  // Boss-provided SVGs are resolved by trying both filename variants.
  // Flutter asset names are exact, including spaces before ".svg".
  final Map<String, Future<String?>> _cameraSvgCache =
      <String, Future<String?>>{};

  @override
  void initState() {
    super.initState();
    _tapZoomAnimationController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 220),
          )
          ..addListener(_handleTapZoomAnimationTick)
          ..addStatusListener(_handleTapZoomAnimationStatus);
    WidgetsBinding.instance.addObserver(this);
    final initialController = widget.initialController;
    if (initialController?.value.isInitialized == true) {
      _controller = initialController;
      _ownsController = false;
      _observeCameraErrors(initialController!);
      _cameras = <CameraDescription>[initialController!.description];
      _audioEnabled = !widget.photoOnly && widget.initialAudioEnabled;
      _microphonePermissionResolved =
          widget.photoOnly || widget.initialAudioEnabled;
      _initializing = false;
      unawaited(_adoptInitialController(initialController));
    } else {
      unawaited(initialController?.dispose());
      _ownsController = true;
      unawaited(_initialiseCamera());
    }
    unawaited(_loadLatestGalleryAsset());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _recordingTimer?.cancel();
    _tapZoomAnimationController.dispose();
    _zoomSmoother.dispose();
    unawaited(_cameraErrorSubscription?.cancel());
    _cameraErrorSubscription = null;
    _recordingStopwatch.stop();

    final controller = _controller;
    _controller = null;
    if (controller != null && _ownsController) {
      unawaited(controller.dispose());
    }

    // The camera intentionally uses a black three-button navigation area.
    // Restore Wrytte's edge-to-edge transparent system bar as this route
    // leaves so the camera style cannot leak into the gallery or chat UI.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do not destroy the camera on Android's transient `inactive` state. The
    // emulator camera-source chooser and route transitions can both trigger
    // it, and recreating the controller causes the chooser to be shown again.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseCamera());
      return;
    }

    if (state == AppLifecycleState.resumed && !_openingEditor) {
      if (_controller?.value.isInitialized != true) {
        unawaited(
          _initialiseCamera(
            preferredDescription: _lastCameraDescription,
            initialDisplayZoom: _displayZoom,
          ),
        );
      }
      unawaited(_loadLatestGalleryAsset());
    }
  }

  Future<void> _adoptInitialController(CameraController controller) async {
    try {
      final results = await Future.wait<double>(<Future<double>>[
        controller.getMinZoomLevel(),
        controller.getMaxZoomLevel(),
      ]);
      final supportedMinZoom = results[0].isFinite && results[0] > 0
          ? results[0]
          : 1.0;
      final supportedMaxZoom =
          results[1].isFinite && results[1] >= supportedMinZoom
          ? results[1]
          : supportedMinZoom;

      // Load CameraX intrinsic-ratio metadata before interpreting native 1.0.
      final cameras = await CameraInventoryService.instance.load();
      if (!mounted || !identical(_controller, controller)) return;

      CameraInventoryService.instance.rememberZoomRange(
        controller.description,
        supportedMinZoom,
        supportedMaxZoom,
      );

      final baseZoom = CameraInventoryService.instance.displayBaseZoomFor(
        controller.description,
      );
      final requestedNativeZoom = 1.0
          .clamp(supportedMinZoom, supportedMaxZoom)
          .toDouble();
      final effectiveDisplayZoom = baseZoom * requestedNativeZoom;

      final zoomAccepted = await _setNativeZoomOnce(
        controller,
        requestedNativeZoom,
      );
      if (!zoomAccepted) {
        debugPrint(
          '[ChatCameraScreen] Initial zoom was not accepted; keeping the '
          'camera native default.',
        );
      }

      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = FlashMode.off;
      }

      if (!mounted || !identical(_controller, controller)) return;

      setState(() {
        _cameras = cameras.isEmpty
            ? <CameraDescription>[controller.description]
            : cameras;
        _lastCameraDescription = controller.description;
        _minZoom = supportedMinZoom;
        _maxZoom = supportedMaxZoom;
        _activeCameraBaseZoom = baseZoom;
        _displayZoom = effectiveDisplayZoom;
        _appliedNativeZoom = zoomAccepted
            ? requestedNativeZoom
            : 1.0.clamp(supportedMinZoom, supportedMaxZoom).toDouble();
        _lastPinchScale = 1;
        _initializing = false;
      });
    } catch (error) {
      debugPrint('[ChatCameraScreen] Could not adopt camera preview: $error');
      if (mounted && identical(_controller, controller)) {
        setState(() => _initializing = false);
      }
    }
  }

  Future<void> _releaseCamera() async {
    _cameraGeneration++;
    _cancelZoomInteractions();
    unawaited(_cameraErrorSubscription?.cancel());
    _cameraErrorSubscription = null;
    final controller = _controller;
    _controller = null;
    _cameraPreviewPausedForEditor = false;

    if (mounted) {
      setState(() {
        _initializing = true;
      });
    }

    if (controller != null && _ownsController) {
      try {
        await controller.dispose().timeout(_cameraOperationTimeout);
      } catch (_) {
        // The native camera can already be gone after an app lifecycle change.
      }
    }
  }

  CameraDescription _preferredCamera(
    List<CameraDescription> cameras, {
    CameraDescription? preferredDescription,
  }) {
    final direction =
        preferredDescription?.lensDirection ??
        _lastCameraDescription?.lensDirection ??
        CameraLensDirection.back;

    return CameraInventoryService.instance.preferredForDirection(
          cameras,
          direction,
          explicitDescription: preferredDescription ?? _lastCameraDescription,
        ) ??
        cameras.first;
  }

  void _observeCameraErrors(CameraController controller) {
    unawaited(_cameraErrorSubscription?.cancel());
    _cameraErrorSubscription = CameraPlatform.instance
        .onCameraError(controller.cameraId)
        .listen((event) {
          debugPrint(
            '[ChatCameraScreen] Native camera error: ${event.description}',
          );
        });
  }

  Future<bool> _setNativeZoomOnce(
    CameraController controller,
    double zoom,
  ) async {
    try {
      await controller.setZoomLevel(zoom).timeout(_zoomOperationTimeout);
      return true;
    } on TimeoutException {
      debugPrint(
        '[ChatCameraScreen] Native zoom timed out at ${zoom.toStringAsFixed(2)}x.',
      );
      return false;
    } on CameraException catch (error) {
      debugPrint(
        '[ChatCameraScreen] Native zoom failed at '
        '${zoom.toStringAsFixed(2)}x: ${error.code}: ${error.description}',
      );
      return false;
    } catch (error) {
      debugPrint(
        '[ChatCameraScreen] Native zoom failed at '
        '${zoom.toStringAsFixed(2)}x: $error',
      );
      return false;
    }
  }

  Future<void> _resolveMicrophonePermission({
    bool requestIfNeeded = true,
  }) async {
    if (widget.photoOnly) {
      _audioEnabled = false;
      _microphonePermissionResolved = true;
      _microphonePermissionDenied = false;
      return;
    }
    if (_microphonePermissionResolved) return;

    final microphoneGranted = await AppPermissionService.instance
        .ensureMicrophoneGranted(requestIfNeeded: requestIfNeeded);
    _audioEnabled = microphoneGranted;
    // A silent status check that finds a denial must remain retryable when the
    // user explicitly chooses Video. An explicit decision is resolved once.
    _microphonePermissionResolved = microphoneGranted || requestIfNeeded;
    _microphonePermissionDenied = requestIfNeeded && !microphoneGranted;
  }

  Future<void> _initialiseCamera({
    CameraDescription? preferredDescription,
    double? initialDisplayZoom,
  }) async {
    if (_openingEditor) return;

    // Lifecycle `resumed` and an editor route completing can arrive in the same
    // frame. Reuse one initialization future so two native camera sessions can
    // never race each other or leave an abandoned texture behind.
    final activeAttempt = _cameraInitialisationInFlight;
    if (activeAttempt != null) {
      await activeAttempt;
      if (!mounted ||
          _openingEditor ||
          _controller?.value.isInitialized == true) {
        return;
      }
      // A lifecycle invalidation may have made the awaited attempt stale. Its
      // late completion cannot satisfy this resumed screen, so start one fresh
      // initialization instead of returning to a permanent loading state.
      if (identical(_cameraInitialisationInFlight, activeAttempt)) {
        _cameraInitialisationInFlight = null;
      }
    }

    late final Future<void> attempt;
    attempt = _performCameraInitialisation(
      preferredDescription: preferredDescription,
      initialDisplayZoom: initialDisplayZoom,
    );
    _cameraInitialisationInFlight = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_cameraInitialisationInFlight, attempt)) {
        _cameraInitialisationInFlight = null;
      }
    }
  }

  Future<void> _performCameraInitialisation({
    CameraDescription? preferredDescription,
    double? initialDisplayZoom,
  }) async {
    if (_openingEditor) return;

    final generation = ++_cameraGeneration;
    CameraController? candidateController;

    if (mounted) {
      setState(() {
        _initializing = true;
        _cameraPermissionDenied = false;
      });
    }

    try {
      final cameraPermission = await AppPermissionService.instance
          .ensureCameraGranted();
      if (!cameraPermission) {
        if (mounted) {
          setState(() {
            _cameraPermissionDenied = true;
            _initializing = false;
          });
        }
        return;
      }

      final cameras = _cameras.isEmpty
          ? await CameraInventoryService.instance.load()
          : _cameras;
      if (!mounted || generation != _cameraGeneration) return;

      if (cameras.isEmpty) {
        setState(() => _initializing = false);
        return;
      }

      _cameras = cameras;
      final description = _preferredCamera(
        cameras,
        preferredDescription: preferredDescription,
      );

      // Reuse an existing grant, but do not prompt for microphone merely by
      // opening the photo camera. Video mode requests it explicitly.
      if (!widget.photoOnly) {
        await _resolveMicrophonePermission(requestIfNeeded: false);
      } else {
        _audioEnabled = false;
      }
      if (!mounted || generation != _cameraGeneration) return;

      final previousController = _controller;
      _controller = null;
      _cancelZoomInteractions();
      unawaited(_cameraErrorSubscription?.cancel());
      _cameraErrorSubscription = null;
      if (previousController != null) {
        try {
          await previousController.dispose().timeout(_cameraOperationTimeout);
        } catch (_) {}
      }

      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: !widget.photoOnly && _audioEnabled,
        fps: 30,
        videoBitrate: 5000000,
        audioBitrate: 96000,
      );
      candidateController = controller;

      await controller.initialize().timeout(_cameraInitialisationTimeout);
      _observeCameraErrors(controller);
      if (_audioEnabled) {
        try {
          await controller.prepareForVideoRecording().timeout(
            _cameraOperationTimeout,
          );
        } catch (_) {
          // Optional optimization; recording still works without warm-up.
        }
      }

      if (!mounted || generation != _cameraGeneration) {
        try {
          await controller.dispose().timeout(_cameraOperationTimeout);
        } catch (_) {}
        candidateController = null;
        return;
      }

      var minZoom = 1.0;
      var maxZoom = 1.0;

      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
      } catch (_) {
        minZoom = 1;
        maxZoom = 1;
      }

      final supportedMinZoom = minZoom.isFinite && minZoom > 0 ? minZoom : 1.0;
      final supportedMaxZoom = maxZoom.isFinite && maxZoom >= supportedMinZoom
          ? maxZoom
          : supportedMinZoom;

      CameraInventoryService.instance.rememberZoomRange(
        description,
        supportedMinZoom,
        supportedMaxZoom,
      );

      final baseZoom = CameraInventoryService.instance.displayBaseZoomFor(
        description,
      );
      final requestedDisplayZoom =
          initialDisplayZoom ?? (baseZoom < 1.0 ? baseZoom : 1.0);
      final rawNativeZoom = requestedDisplayZoom / baseZoom;
      final requestedNativeZoom = rawNativeZoom
          .clamp(supportedMinZoom, supportedMaxZoom)
          .toDouble();
      final effectiveDisplayZoom = baseZoom * requestedNativeZoom;

      final zoomAccepted = await _setNativeZoomOnce(
        controller,
        requestedNativeZoom,
      );

      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = FlashMode.off;
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {}
      }

      if (!mounted || generation != _cameraGeneration) {
        try {
          await controller.dispose().timeout(_cameraOperationTimeout);
        } catch (_) {}
        candidateController = null;
        return;
      }

      setState(() {
        _controller = controller;
        _ownsController = true;
        _lastCameraDescription = description;
        _minZoom = supportedMinZoom;
        _maxZoom = supportedMaxZoom;
        _activeCameraBaseZoom = baseZoom;
        _displayZoom = effectiveDisplayZoom;
        _appliedNativeZoom = zoomAccepted
            ? requestedNativeZoom
            : 1.0.clamp(supportedMinZoom, supportedMaxZoom).toDouble();
        _lastPinchScale = 1;
        _initializing = false;
        _cameraPermissionDenied = false;
      });
      candidateController = null;
    } on TimeoutException catch (error, stackTrace) {
      if (!mounted || generation != _cameraGeneration) return;

      debugPrint('[ChatCameraScreen] camera initialization timed out: $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _initializing = false);
    } on CameraException catch (error) {
      if (!mounted || generation != _cameraGeneration) return;

      final permissionError =
          error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted';

      setState(() {
        _cameraPermissionDenied = permissionError;
        _initializing = false;
      });

      debugPrint(
        '[ChatCameraScreen] camera initialization failed: '
        '${error.code}: ${error.description}',
      );
    } catch (error, stackTrace) {
      debugPrint('[ChatCameraScreen] camera initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted && generation == _cameraGeneration) {
        setState(() => _initializing = false);
      }
    } finally {
      final abandonedController = candidateController;
      if (abandonedController != null &&
          !identical(_controller, abandonedController)) {
        try {
          await abandonedController.dispose().timeout(_cameraOperationTimeout);
        } catch (_) {
          // A timed-out native initialization may have already torn itself down.
        }
      }
    }
  }

  Future<void> _loadLatestGalleryAsset() async {
    try {
      // A camera launch must not unexpectedly open a second permission dialog
      // just to decorate the gallery shortcut. The actual Gallery action asks
      // in context; here we only use access that was already granted.
      final permission = await PhotoLibraryPermissionService.instance
          .ensureVisualMediaAccess(
            type: RequestType.image,
            requestIfNeeded: false,
          );

      if (!permission.hasAccess) {
        debugPrint(
          '[ChatCameraScreen] No photo-library access for camera thumbnail.',
        );
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: _latestMediaFilter,
      );

      if (albums.isEmpty) {
        debugPrint('[ChatCameraScreen] No image album available.');
        return;
      }

      // Ask for a few recent images instead of one. If the newest item cannot
      // produce thumbnail bytes on a particular Android media provider, use the
      // next valid image rather than leaving the camera shortcut blank.
      final recent = await albums.first.getAssetListPaged(page: 0, size: 12);

      if (recent.isEmpty) {
        debugPrint('[ChatCameraScreen] No recent images available.');
        return;
      }

      AssetEntity? resolvedAsset;
      Uint8List? resolvedThumbnail;

      for (final asset in recent) {
        if (asset.type != AssetType.image) continue;

        try {
          final thumbnail = await asset.thumbnailDataWithSize(
            const ThumbnailSize.square(256),
            quality: 95,
          );

          if (thumbnail != null && thumbnail.isNotEmpty) {
            resolvedAsset = asset;
            resolvedThumbnail = thumbnail;
            break;
          }
        } catch (error) {
          debugPrint(
            '[ChatCameraScreen] Could not read thumbnail for '
            '${asset.id}: $error',
          );
        }
      }

      if (!mounted) return;

      if (resolvedAsset == null || resolvedThumbnail == null) {
        debugPrint(
          '[ChatCameraScreen] Recent images exist but no thumbnail could be read.',
        );
        return;
      }

      setState(() {
        _latestAsset = resolvedAsset;
        _latestAssetThumbnail = resolvedThumbnail;
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[ChatCameraScreen] Could not load latest gallery photo: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _switchCamera() async {
    if (_captureBusy || _recording || _switchingCamera || _cameras.length < 2) {
      return;
    }

    final current = _controller?.description;
    if (current == null) return;

    final currentIndex = _cameras.indexWhere(
      (camera) => camera.name == current.name,
    );
    if (currentIndex < 0) return;

    final targetDirection = current.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final target =
        CameraInventoryService.instance.preferredForDirection(
          _cameras,
          targetDirection,
        ) ??
        _cameras.firstWhere(
          (camera) => camera.lensDirection != current.lensDirection,
          orElse: () => _cameras[(currentIndex + 1) % _cameras.length],
        );

    unawaited(HapticFeedback.selectionClick());

    setState(() => _switchingCamera = true);
    try {
      _cancelZoomInteractions();
      _flashMode = FlashMode.off;
      await _initialiseCamera(
        preferredDescription: target,
        initialDisplayZoom: 1,
      );
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _setMode(ChatCameraMode mode) async {
    if (widget.photoOnly && mode == ChatCameraMode.video) return;
    if (_mode == mode || _captureBusy || _recording) return;

    unawaited(HapticFeedback.selectionClick());

    if (mode == ChatCameraMode.video && !_audioEnabled) {
      await _resolveMicrophonePermission();
      if (!mounted) return;
      if (!_audioEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone access is needed to record video.'),
          ),
        );
        return;
      }

      // CameraController cannot enable audio in place. Recreate the current
      // camera once, only after the explicit Video choice, then reuse it.
      final currentDescription = _controller?.description;
      await _initialiseCamera(
        preferredDescription: currentDescription,
        initialDisplayZoom: _displayZoom,
      );
      if (!mounted || _controller?.value.isInitialized != true) return;
    }

    final controller = _controller;
    final shouldTurnOffFlash = _flashMode != FlashMode.off;
    setState(() {
      _mode = mode;
      _flashMode = FlashMode.off;
    });

    if (shouldTurnOffFlash &&
        controller != null &&
        controller.value.isInitialized) {
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
    }
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _captureBusy) {
      return;
    }

    // Only two flash states are exposed in the camera UI, matching the two
    // boss-provided assets: OFF and ON.
    final turningOn = _flashMode == FlashMode.off;
    final nextMode = turningOn
        ? (_mode == ChatCameraMode.video ? FlashMode.torch : FlashMode.always)
        : FlashMode.off;

    try {
      await controller.setFlashMode(nextMode);
      if (!mounted) return;

      unawaited(HapticFeedback.selectionClick());
      setState(() => _flashMode = nextMode);
    } catch (_) {
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}

      if (mounted) {
        setState(() => _flashMode = FlashMode.off);
        _showCameraMessage('Flash is not available on this camera.');
      }
    }
  }

  CameraDescription? get _currentCameraDescription =>
      _controller?.description ?? _lastCameraDescription;

  CameraDescription? get _separateUltraWideCamera {
    final current = _currentCameraDescription;
    if (current == null) return null;
    return CameraInventoryService.instance.ultraWideForDirection(
      _cameras,
      current.lensDirection,
      excluding: current,
    );
  }

  CameraDescription? get _standardWideCamera {
    final current = _currentCameraDescription;
    if (current == null) return null;
    return CameraInventoryService.instance.standardWideForDirection(
      _cameras,
      current.lensDirection,
      excluding: _activeCameraBaseZoom < 0.975 ? current : null,
    );
  }

  double get _activeDisplayMinimum => _activeCameraBaseZoom * _minZoom;

  double get _activeDisplayMaximum => _activeCameraBaseZoom * _maxZoom;

  bool get _halfXAvailable => CameraInventoryService.instance.halfXAvailable(
    cameras: _cameras,
    current: _currentCameraDescription,
    currentBaseZoom: _activeCameraBaseZoom,
    currentNativeMinimum: _minZoom,
  );

  double get _gestureMinZoom =>
      CameraInventoryService.instance.minimumDisplayZoom(
        cameras: _cameras,
        current: _currentCameraDescription,
        currentBaseZoom: _activeCameraBaseZoom,
        currentNativeMinimum: _minZoom,
      );

  double get _gestureMaxZoom {
    if (_activeCameraBaseZoom >= 0.975) {
      return math.max(_gestureMinZoom, _activeDisplayMaximum);
    }

    final standard = _standardWideCamera;
    if (standard != null) {
      final range = CameraInventoryService.instance.zoomRangeFor(standard);
      final base = CameraInventoryService.instance.displayBaseZoomFor(standard);
      if (range != null) {
        return math.max(_gestureMinZoom, base * range.maximum);
      }
    }

    return math.max(_gestureMinZoom, math.max(1.0, _activeDisplayMaximum));
  }

  double _displayZoomForNative(double nativeZoom) =>
      _activeCameraBaseZoom * nativeZoom;

  double _nativeZoomForDisplay(double displayZoom) =>
      displayZoom / _activeCameraBaseZoom;

  void _cancelZoomInteractions() {
    _tapZoomAnimationController.stop();
    _pinchZoomActive = false;
    _lastPinchScale = 1;
    _zoomSmoother.cancel();
  }

  void _requestNativeZoom(
    double requestedNativeZoom, {
    bool forceFinal = false,
  }) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final nativeTarget = requestedNativeZoom
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    final effectiveDisplayZoom = _displayZoomForNative(nativeTarget);

    if (!forceFinal &&
        (nativeTarget - _appliedNativeZoom).abs() < 0.0005 &&
        (effectiveDisplayZoom - _displayZoom).abs() < 0.0005) {
      return;
    }

    if ((effectiveDisplayZoom - _displayZoom).abs() >= 0.0005) {
      setState(() => _displayZoom = effectiveDisplayZoom);
    }

    _zoomSmoother.setZoom(
      controller,
      nativeTarget,
      onApplied: (appliedZoom) {
        if (!mounted || !identical(_controller, controller)) return;
        _appliedNativeZoom = appliedZoom;
      },
      onError: (error, stackTrace) {
        if (!mounted || !identical(_controller, controller)) return;
        debugPrint('[ChatCameraScreen] Native zoom failed: $error');
        _tapZoomAnimationController.stop();
        _zoomSmoother.cancel();
        setState(
          () => _displayZoom = _displayZoomForNative(_appliedNativeZoom),
        );
      },
    );
  }

  Future<void> _switchLensForDisplayZoom({
    required CameraDescription target,
    required double displayZoom,
  }) async {
    if (_lensTransitionInFlight || _captureBusy || _recording) {
      _pendingDisplayZoomAfterLensSwitch = displayZoom;
      return;
    }

    _lensTransitionInFlight = true;
    _pendingDisplayZoomAfterLensSwitch = null;

    try {
      await _initialiseCamera(
        preferredDescription: target,
        initialDisplayZoom: displayZoom,
      );
    } finally {
      _lensTransitionInFlight = false;
    }

    if (!mounted) return;

    final pending = _pendingDisplayZoomAfterLensSwitch;
    _pendingDisplayZoomAfterLensSwitch = null;
    if (pending != null) {
      _requestDisplayZoom(pending, forceFinal: true);
    }
  }

  void _requestDisplayZoom(
    double requestedDisplayZoom, {
    bool forceFinal = false,
  }) {
    if (_controller?.value.isInitialized != true) return;

    final displayTarget = requestedDisplayZoom
        .clamp(_gestureMinZoom, _gestureMaxZoom)
        .toDouble();

    if (_lensTransitionInFlight) {
      _pendingDisplayZoomAfterLensSwitch = displayTarget;
      return;
    }

    // A physical ultra-wide lens runs at native 1.0 for Wrytte's 0.5x view.
    // When the gesture reaches the standard 1x boundary, hand back to the
    // standard/logical wide camera rather than digitally stretching ultra-wide.
    if (_activeCameraBaseZoom < 0.975 && displayTarget >= 0.995) {
      final standard = _standardWideCamera;
      if (standard != null) {
        unawaited(
          _switchLensForDisplayZoom(
            target: standard,
            displayZoom: math.max(1.0, displayTarget),
          ),
        );
        return;
      }
    }

    // If the current standard camera cannot zoom below 1x but the platform
    // exposes a real ultra-wide CameraDescription, hand the gesture to it.
    if (_activeCameraBaseZoom >= 0.975 &&
        displayTarget < _activeDisplayMinimum - 0.001 &&
        displayTarget < 1) {
      final ultraWide = _separateUltraWideCamera;
      if (ultraWide != null) {
        unawaited(
          _switchLensForDisplayZoom(
            target: ultraWide,
            displayZoom: displayTarget,
          ),
        );
        return;
      }
    }

    final nativeTarget = _nativeZoomForDisplay(displayTarget);
    _requestNativeZoom(nativeTarget, forceFinal: forceFinal);
  }

  void _handleTapZoomAnimationTick() {
    if (!mounted || !_tapZoomAnimationController.isAnimating) return;
    final progress = Curves.easeOutCubic.transform(
      _tapZoomAnimationController.value,
    );
    final zoom = _tapZoomFrom + ((_tapZoomTo - _tapZoomFrom) * progress);
    _requestDisplayZoom(zoom);
  }

  void _handleTapZoomAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _requestDisplayZoom(_tapZoomTo, forceFinal: true);
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastPinchScale = 1;
    _pinchZoomActive = false;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;

    if (!_pinchZoomActive) {
      _tapZoomAnimationController.stop();
      _zoomSmoother.cancel();
      _pinchZoomActive = true;
      _lastPinchScale = details.scale;
      return;
    }

    final previousScale = _lastPinchScale.isFinite && _lastPinchScale > 0
        ? _lastPinchScale
        : 1.0;
    final incrementalScale = details.scale.isFinite && details.scale > 0
        ? details.scale / previousScale
        : 1.0;
    _lastPinchScale = details.scale.isFinite && details.scale > 0
        ? details.scale
        : 1.0;

    // Apply only the movement since the previous gesture update. This avoids a
    // jump when a pinch crosses 1x and the active physical lens changes.
    final sensitiveScale = math.pow(incrementalScale, 1.65).toDouble();
    _requestDisplayZoom(_displayZoom * sensitiveScale);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_pinchZoomActive) {
      _requestDisplayZoom(_displayZoom, forceFinal: true);
      _pinchZoomActive = false;
    }
    _lastPinchScale = 1;
  }

  List<double> get _tapZoomStops => cameraZoomStops(
    minimumDisplayZoom: _gestureMinZoom,
    maximumDisplayZoom: _gestureMaxZoom,
    halfXAvailable: _halfXAvailable,
  );

  double _nextTapZoom(double current) {
    final supported = _tapZoomStops;
    if (supported.isEmpty) return current;
    if (supported.length == 1) return supported.first;

    const epsilon = 0.05;

    // Exact UI order: 1x -> 2x -> 3x -> 0.5x -> 1x.
    for (var index = 0; index < supported.length; index++) {
      if ((supported[index] - current).abs() <= epsilon) {
        return supported[(index + 1) % supported.length];
      }
    }

    // If the user pinched between shortcuts, continue forward from the nearest
    // logical point in the same order.
    if (current < 1 - epsilon) {
      return supported.firstWhere(
        (zoom) => zoom >= 1,
        orElse: () => supported.first,
      );
    }

    for (final zoom in supported) {
      if (zoom >= 1 && zoom > current + epsilon) return zoom;
    }

    final half = supported.where((zoom) => zoom < 1);
    if (half.isNotEmpty) return half.first;
    return supported.first;
  }

  void _animateTapZoom(double target) {
    final start = _displayZoom;
    if ((target - start).abs() < 0.005) return;

    _tapZoomAnimationController.stop();
    _zoomSmoother.cancel();
    _pinchZoomActive = false;
    _tapZoomFrom = start;
    _tapZoomTo = target;

    final distance = (target - start).abs().clamp(0.0, 3.0).toDouble();
    _tapZoomAnimationController.duration = Duration(
      milliseconds: 180 + ((distance / 3) * 70).round(),
    );
    _tapZoomAnimationController.forward(from: 0);
  }

  Future<void> _applyTapZoom(double target) async {
    if (_controller?.value.isInitialized != true) return;

    if ((target - 0.5).abs() < 0.025 && 0.5 < _activeDisplayMinimum - 0.001) {
      final ultraWide = _separateUltraWideCamera;
      if (ultraWide != null) {
        await _switchLensForDisplayZoom(target: ultraWide, displayZoom: 0.5);
        return;
      }
    }

    if (_activeCameraBaseZoom < 0.975 && target >= 1) {
      final standard = _standardWideCamera;
      if (standard != null) {
        await _switchLensForDisplayZoom(target: standard, displayZoom: target);
        return;
      }
    }

    _animateTapZoom(target);
  }

  Future<void> _cycleZoom() async {
    if (_lensTransitionInFlight || _captureBusy || _recording) return;

    final cycleFrom = _tapZoomAnimationController.isAnimating
        ? _tapZoomTo
        : _displayZoom;
    final target = _nextTapZoom(cycleFrom);
    if ((target - cycleFrom).abs() < 0.005) return;

    unawaited(HapticFeedback.selectionClick());
    await _applyTapZoom(target);
  }

  Future<void> _focusAt(
    TapUpDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _captureBusy ||
        constraints.maxWidth <= 0 ||
        constraints.maxHeight <= 0) {
      return;
    }

    final local = details.localPosition;
    final normalized = Offset(
      (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );

    _focusTimer?.cancel();
    if (mounted) {
      setState(() => _focusPoint = local);
      _focusTimer = Timer(const Duration(milliseconds: 850), () {
        if (mounted) setState(() => _focusPoint = null);
      });
    }

    try {
      await Future.wait<void>([
        controller.setFocusPoint(normalized),
        controller.setExposurePoint(normalized),
      ]);
    } catch (_) {
      // Some front/emulated cameras do not expose focus/exposure points.
    }
  }

  Future<void> _handleShutter() async {
    if (_mode == ChatCameraMode.photo) {
      await _takePhoto();
      return;
    }

    if (_recording) {
      await _stopVideoRecording();
    } else {
      await _startVideoRecording();
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _captureBusy ||
        controller.value.isTakingPicture) {
      return;
    }

    setState(() => _captureBusy = true);
    unawaited(HapticFeedback.mediumImpact());

    try {
      final photo = await controller.takePicture();
      if (!mounted) return;

      // Keep this camera route alive under the profile cropper. Back from the
      // cropper can then resume this exact camera session for a retake.
      if (widget.photoOnly) {
        await _openProfilePhotoCrop(photo.path);
        return;
      }

      await _openCapturedEditor(
        capturedPath: photo.path,
        attachmentType: 'image',
      );
    } on CameraException catch (error) {
      debugPrint(
        '[ChatCameraScreen] takePicture failed: '
        '${error.code}: ${error.description}',
      );
      if (mounted) _showCameraMessage('Could not take the photo.');
    } catch (error) {
      debugPrint('[ChatCameraScreen] takePicture failed: $error');
      if (mounted) _showCameraMessage('Could not take the photo.');
    } finally {
      if (mounted) setState(() => _captureBusy = false);
    }
  }

  Future<void> _startVideoRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _captureBusy ||
        controller.value.isRecordingVideo) {
      return;
    }

    setState(() => _captureBusy = true);

    try {
      await controller.startVideoRecording();
      if (!mounted) return;

      _recordingStopwatch
        ..reset()
        ..start();

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || !_recordingStopwatch.isRunning) return;
        setState(() => _recordingDuration = _recordingStopwatch.elapsed);
      });

      unawaited(HapticFeedback.mediumImpact());

      setState(() {
        _recording = true;
        _recordingDuration = Duration.zero;
      });
    } on CameraException catch (error) {
      debugPrint(
        '[ChatCameraScreen] startVideoRecording failed: '
        '${error.code}: ${error.description}',
      );
      if (mounted) _showCameraMessage('Could not start video recording.');
    } finally {
      if (mounted) setState(() => _captureBusy = false);
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _captureBusy ||
        !controller.value.isRecordingVideo) {
      return;
    }

    setState(() => _captureBusy = true);
    unawaited(HapticFeedback.mediumImpact());

    _recordingTimer?.cancel();
    _recordingStopwatch.stop();

    try {
      final video = await controller.stopVideoRecording();

      if (_flashMode == FlashMode.torch) {
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {}
        _flashMode = FlashMode.off;
      }

      if (!mounted) return;

      setState(() {
        _recording = false;
        _recordingDuration = Duration.zero;
      });

      // Open the editor with the captured file immediately. The old path
      // synchronously rendered a second cropped MP4 here, keeping the shutter
      // busy and showing a loading state before navigation.
      setState(() => _captureBusy = false);
      await _openCapturedEditor(
        capturedPath: video.path,
        attachmentType: 'video',
      );
    } on CameraException catch (error) {
      debugPrint(
        '[ChatCameraScreen] stopVideoRecording failed: '
        '${error.code}: ${error.description}',
      );

      if (mounted) {
        setState(() => _recording = false);
        _showCameraMessage('Could not finish the video.');
      }
    } finally {
      _recordingStopwatch.reset();
      if (mounted) setState(() => _captureBusy = false);
    }
  }

  Future<void> _restartCameraAfterEditor(CameraDescription? description) async {
    if (!mounted) return;

    // Normally the same authorized camera session was only preview-paused while
    // the editor was visible. Resume it instead of opening a second native
    // session (which would show the emulator camera-source chooser again).
    final existingController = _controller;
    if (existingController?.value.isInitialized == true) {
      final activeController = existingController!;
      // Read the controller value as well as our flag. On a slow emulator the
      // native pause can finish just after the timeout, so relying only on the
      // flag would incorrectly leave a valid controller paused on a black
      // preview after Back.
      final previewNeedsResume =
          _cameraPreviewPausedForEditor ||
          activeController.value.isPreviewPaused;
      if (previewNeedsResume) {
        try {
          await activeController.resumePreview().timeout(
            _cameraOperationTimeout,
          );
          _cameraPreviewPausedForEditor = false;
        } catch (error) {
          debugPrint(
            '[ChatCameraScreen] Could not resume camera after editor: $error',
          );
          await _releaseCamera();
        }
      }

      if (_controller?.value.isInitialized == true) {
        if (mounted) setState(() => _initializing = false);
        return;
      }
    }

    // The app may have been backgrounded while editing, in which case the
    // lifecycle observer correctly released the camera. Wait for the editor's
    // reverse transition before rebuilding that genuinely lost session.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;

    await _initialiseCamera(
      preferredDescription: description,
      initialDisplayZoom: _displayZoom,
    );

    final ready = _controller?.value.isInitialized == true && !_initializing;

    if (ready || !mounted || _cameraPermissionDenied) return;

    // CameraX/emulators can hold a released video texture for one additional
    // frame. Retry once with a clean controller; each attempt is bounded, so a
    // native hang can never leave this screen showing an endless spinner.
    await _releaseCamera();
    await Future<void>.delayed(const Duration(milliseconds: 320));

    if (!mounted) return;
    await _initialiseCamera(
      preferredDescription: description,
      initialDisplayZoom: _displayZoom,
    );

    if (mounted &&
        _controller?.value.isInitialized != true &&
        !_cameraPermissionDenied) {
      setState(() => _initializing = false);
      _showCameraMessage('Could not restart the camera. Tap Try Again.');
    }
  }

  Future<void> _openCapturedEditor({
    required String capturedPath,
    required String attachmentType,
  }) async {
    if (!mounted || _openingEditor) return;

    _openingEditor = true;

    final description = _controller?.description;
    final cameraController = _controller;
    _cameraPreviewPausedForEditor = false;
    if (cameraController?.value.isInitialized == true) {
      try {
        await cameraController!.pausePreview().timeout(_cameraOperationTimeout);
        _cameraPreviewPausedForEditor = true;
      } catch (error) {
        // Pausing is an optimization, not a reason to recreate the camera.
        // Keeping this already initialized controller is still safer than
        // opening a second session and asking for the source again.
        debugPrint(
          '[ChatCameraScreen] Could not pause preview for editor: $error',
        );
      }
    }

    if (!mounted) {
      _openingEditor = false;
      return;
    }

    final result = await Navigator.of(context).push<ChatMediaEditorResult>(
      PageRouteBuilder<ChatMediaEditorResult>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ChatMediaEditorScreen(
              sourcePath: capturedPath,
              attachmentType: attachmentType,
              recipientLabel: widget.recipientLabel,
              initialCaption: '',
              selectionIndex: null,
              selectedCount: 0,
              openedFromCamera: true,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );

    _openingEditor = false;

    if (!mounted) return;

    if (result?.sendNow == true) {
      final outgoingPath = result!.editedFilePath?.trim().isNotEmpty == true
          ? result.editedFilePath!
          : capturedPath;

      Navigator.of(context).pop(
        ChatCameraResult.media(
          filePath: outgoingPath,
          attachmentType: attachmentType,
          caption: result.caption,
        ),
      );
      return;
    }

    // The media editor was closed/discarded, so return to the live camera
    // rather than throwing the user all the way back to chat.
    try {
      final capturedFile = File(capturedPath);
      if (await capturedFile.exists()) {
        await capturedFile.delete();
      }
    } catch (_) {}

    await _restartCameraAfterEditor(description);
  }

  Future<void> _openProfilePhotoCrop(String capturedPath) async {
    if (!mounted || _openingEditor) return;

    _openingEditor = true;
    final description = _controller?.description;
    final cameraController = _controller;
    _cameraPreviewPausedForEditor = false;
    if (cameraController?.value.isInitialized == true) {
      try {
        await cameraController!.pausePreview().timeout(_cameraOperationTimeout);
        _cameraPreviewPausedForEditor = true;
      } catch (error) {
        debugPrint(
          '[ChatCameraScreen] Could not pause preview for profile crop: $error',
        );
      }
    }

    if (!mounted) {
      _openingEditor = false;
      return;
    }

    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProfilePhotoCropPage(
          sourcePath: capturedPath,
          openedFromCamera: true,
        ),
      ),
    );
    _openingEditor = false;

    if (!mounted) return;
    if (croppedPath?.trim().isNotEmpty == true) {
      try {
        final capturedFile = File(capturedPath);
        if (await capturedFile.exists()) await capturedFile.delete();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(
        ChatCameraResult.media(
          filePath: croppedPath!.trim(),
          attachmentType: 'image',
        ),
      );
      return;
    }

    try {
      final capturedFile = File(capturedPath);
      if (await capturedFile.exists()) await capturedFile.delete();
    } catch (_) {}
    await _restartCameraAfterEditor(description);
  }

  Future<void> _openGallery() async {
    if (_captureBusy || _recording || _openingEditor) return;
    _openingEditor = true;
    unawaited(HapticFeedback.selectionClick());
    // The next gallery owns a fresh preview session. Finish releasing this
    // native camera first so the two controllers never race for the device.
    await _releaseCamera();
    if (!mounted) return;
    Navigator.of(context).pop(const ChatCameraResult.gallery());
  }

  Future<void> _closeCamera() async {
    if (_captureBusy || _openingEditor || _closingCamera) return;
    _closingCamera = true;

    if (_recording) {
      final controller = _controller;
      try {
        if (controller != null &&
            controller.value.isInitialized &&
            controller.value.isRecordingVideo) {
          final discarded = await controller.stopVideoRecording();
          final file = File(discarded.path);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {}

      _recordingTimer?.cancel();
      _recordingStopwatch
        ..stop()
        ..reset();
    }

    if (!mounted) return;

    // Hand the active native session back before the reverse Hero starts.
    // This matters after lens switching: the controller originally borrowed
    // from the attachment tile has been replaced, so only this controller can
    // render the destination tile without a blank/reinitialisation delay.
    final controller = _controller;
    final returnController = widget.onReturnController;
    if (returnController != null &&
        controller != null &&
        controller.value.isInitialized) {
      _ownsController = false;
      returnController(controller, _audioEnabled);
    }
    Navigator.of(context).pop();
  }

  Future<bool> _handleSystemBack() async {
    await _closeCamera();
    return false;
  }

  void _showCameraMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xEB1B1E24),
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: WrytteColors.textPrimary,
              fontFamily: WrytteTypography.primaryFontFamily,
              fontSize: 14,
            ),
          ),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: _blue,
                  onPressed: onAction,
                ),
        ),
      );
  }

  String get _recordingLabel {
    final totalSeconds = _recordingDuration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _zoomLabel {
    return _formatZoomLabel(_displayZoom);
  }

  String _formatZoomLabel(double zoom) {
    if ((zoom - zoom.round()).abs() < 0.05) return '${zoom.round()}x';
    return '${zoom.toStringAsFixed(1)}x';
  }

  List<String> get _flashIconCandidates {
    if (_flashMode == FlashMode.off) {
      return const <String>[
        'assets/svg/Flash off icon.svg',
        'assets/svg/Flash off icon .svg',
      ];
    }

    return const <String>[
      'assets/svg/Flash on icon.svg',
      'assets/svg/Flash on icon .svg',
    ];
  }

  static const List<String> _flipCameraIconCandidates = <String>[
    'assets/svg/Flip camera icon.svg',
    'assets/svg/Flip camera icon .svg',
  ];

  Future<String?> _resolveCameraSvg(List<String> candidates) {
    final cacheKey = candidates.join('|');

    return _cameraSvgCache.putIfAbsent(cacheKey, () async {
      for (final assetPath in candidates) {
        try {
          final data = await rootBundle.loadString(assetPath);
          if (data.trim().isNotEmpty) {
            debugPrint('[ChatCameraScreen] SVG loaded: $assetPath');
            return data;
          }
        } catch (_) {
          // Try the next exact filename.
        }
      }

      debugPrint(
        '[ChatCameraScreen] SVG not found: ${candidates.join(' OR ')}',
      );
      return null;
    });
  }

  Widget _bossCameraSvg({
    required List<String> candidates,
    required double size,
    Color color = WrytteColors.textPrimary,
  }) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<String?>(
        future: _resolveCameraSvg(candidates),
        builder: (context, snapshot) {
          final svg = snapshot.data;

          if (svg == null || svg.isEmpty) {
            // Keep the control visually empty instead of substituting a third,
            // non-boss icon. The resolver already tries both exact filenames.
            return const SizedBox.shrink();
          }

          return SvgPicture.string(
            svg,
            width: size,
            height: size,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          );
        },
      ),
    );
  }

  BoxDecoration _transparentControlDecoration(double radius) {
    return BoxDecoration(
      color: const Color(0xFF0B0D11).withValues(alpha: 0.50),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  Widget _transparentCircle({
    required Widget child,
    required VoidCallback? onTap,
    double size = 48,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildPreviewSurface(CameraController controller) {
    return WrytteCameraPreviewSurface(
      controller: controller,
      backgroundColor: _background,
    );
  }

  Widget _buildCameraSurface(CameraController? controller, bool cameraReady) {
    return cameraReady && controller != null
        ? _buildPreviewSurface(controller)
        : const ColoredBox(color: _background);
  }

  Widget _buildTransitioningCameraSurface({
    required CameraController? controller,
    required bool cameraReady,
    required Animation<double>? routeAnimation,
  }) {
    final surface = ClipRect(
      child: _buildCameraSurface(controller, cameraReady),
    );
    final sourceRect = widget.openingCameraRect;
    if (sourceRect == null || routeAnimation == null) return surface;
    return CustomSingleChildLayout(
      delegate: _CameraPreviewRectTransitionDelegate(
        animation: routeAnimation,
        sourceRect: sourceRect,
      ),
      child: surface,
    );
  }

  Widget _buildPreviewGestureLayer(CameraController controller) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            onScaleEnd: _handleScaleEnd,
            onTapUp: (details) => unawaited(_focusAt(details, constraints)),
            onDoubleTap: () => unawaited(_switchCamera()),
            child: const ColoredBox(color: Colors.transparent),
          );
        },
      ),
    );
  }

  Widget _buildTopControls() {
    final closeControl = _transparentCircle(
      onTap: _captureBusy || _openingEditor
          ? null
          : () => unawaited(_closeCamera()),
      child: wrytteSvgAssetIcon(
        assetPath: 'assets/svg/ic--round-arrow-back-ios.svg',
        canvas: 26,
        color: _profilePhotoControlColor,
        scale: 1.0,
        offset: const Offset(-0.5, 0),
      ),
    );
    final flashIcon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey<FlashMode>(_flashMode),
        child: _bossCameraSvg(
          candidates: _flashIconCandidates,
          size: 25,
          color: _profilePhotoControlColor,
        ),
      ),
    );
    final flashControl = _transparentCircle(
      onTap: _controller?.value.isInitialized == true
          ? () => unawaited(_cycleFlash())
          : null,
      child: flashIcon,
    );
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Row(
            children: [
              Transform.translate(
                offset: const Offset(-5, 0),
                child: closeControl,
              ),
              const Spacer(),
              if (_recording)
                Container(
                  height: 32,
                  constraints: const BoxConstraints(minWidth: 70),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _videoRed,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _recordingLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 16,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const Spacer(),
              flashControl,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryButton() {
    final thumbnail = _latestAssetThumbnail;
    final asset = _latestAsset;

    Widget preview;

    if (thumbnail != null && thumbnail.isNotEmpty) {
      preview = SizedBox.expand(
        child: Image.memory(
          thumbnail,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    } else if (asset != null) {
      preview = SizedBox.expand(
        child: Image(
          image: AssetEntityImageProvider(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(256),
          ),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              const ColoredBox(color: Color(0x80121418)),
        ),
      );
    } else {
      // Keep the circle visible while the thumbnail is loading. Once the
      // PhotoManager query completes, setState replaces this with the image.
      preview = const ColoredBox(color: Color(0x80121418));
    }

    return Semantics(
      button: true,
      label: 'Open gallery',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_openGallery()),
        child: ClipOval(child: SizedBox(width: 48, height: 48, child: preview)),
      ),
    );
  }

  Widget _buildZoomPill() {
    final canTapZoom = _tapZoomStops.length > 1;
    final zoomLabel = _zoomLabel;

    return Semantics(
      button: true,
      enabled: canTapZoom,
      label: 'Camera zoom',
      value: zoomLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTapZoom ? () => unawaited(_cycleZoom()) : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B0D11).withValues(alpha: 0.54),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.8,
              ),
            ),
            child: Center(
              child: Text(
                zoomLabel,
                style: TextStyle(
                  color: canTapZoom
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.62),
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShutter() {
    final videoMode = _mode == ChatCameraMode.video;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _captureBusy || _initializing
          ? null
          : () => unawaited(_handleShutter()),
      child: AnimatedScale(
        scale: _captureBusy ? 0.94 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 82,
          height: 82,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.12),
            border: Border.all(
              // Keep the outer capture ring white in both Photo and Video.
              // Video mode only changes the INNER circle/square to Wrytte red.
              color: Colors.white.withValues(alpha: 0.96),
              width: 3.2,
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _recording ? 30 : 66,
            height: _recording ? 30 : 66,
            decoration: BoxDecoration(
              color: videoMode ? _videoRed : Colors.white,
              // Keep one rectangular shape throughout the tween. Animating
              // BoxShape.circle <-> a rounded rectangle can briefly produce
              // an invalid BoxDecoration (circle + borderRadius), which was
              // the yellow Flutter assertion visible on start/stop.
              borderRadius: BorderRadius.circular(_recording ? 8 : 33),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return IgnorePointer(
      ignoring: _recording || _captureBusy,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Container(
          width: 132,
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: _transparentControlDecoration(19),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: _mode == ChatCameraMode.video
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  width: 62,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_setMode(ChatCameraMode.video)),
                      child: Center(
                        child: Text(
                          'Video',
                          style: TextStyle(
                            color: _mode == ChatCameraMode.video
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.50),
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 13,
                            fontWeight: _mode == ChatCameraMode.video
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_setMode(ChatCameraMode.photo)),
                      child: Center(
                        child: Text(
                          'Photo',
                          style: TextStyle(
                            color: _mode == ChatCameraMode.photo
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.50),
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 13,
                            fontWeight: _mode == ChatCameraMode.photo
                                ? FontWeight.w600
                                : FontWeight.w500,
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
    );
  }

  Widget _buildBottomControls() {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 232 + bottomPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final modeBottom = bottomPadding + 16;
          final shutterBottom = bottomPadding + 76;
          final shutterCenterX = constraints.maxWidth / 2;

          return Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00000000),
                          Color(0x3D000000),
                          Color(0x9E000000),
                        ],
                        stops: [0, 0.58, 1],
                      ),
                    ),
                  ),
                ),
              ),

              // Shutter gets its own row, like the boss/reference screen.
              Positioned(bottom: shutterBottom, child: _buildShutter()),

              // Zoom sits immediately to the shutter's right.
              Positioned(
                left: shutterCenterX + 62,
                bottom: shutterBottom + 25,
                child: _buildZoomPill(),
              ),

              // Lower row: circular latest-photo thumbnail.
              Positioned(
                left: 22,
                bottom: modeBottom - 5,
                child: _buildGalleryButton(),
              ),

              // Profile photos are intentionally photo-only; chat cameras
              // retain the existing Video / Photo selector.
              if (!widget.photoOnly)
                Positioned(bottom: modeBottom, child: _buildModeSelector()),

              // Lower row: camera switch.
              Positioned(
                right: 22,
                bottom: modeBottom - 7,
                child: _transparentCircle(
                  size: 52,
                  onTap: _cameras.length > 1 && !_recording && !_captureBusy
                      ? () => unawaited(_switchCamera())
                      : null,
                  child: AnimatedRotation(
                    turns: _switchingCamera ? 0.5 : 0,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    child: _bossCameraSvg(
                      candidates: _flipCameraIconCandidates,
                      size: 28,
                      color: _profilePhotoControlColor,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFocusIndicator() {
    final focus = _focusPoint;
    if (focus == null) return const SizedBox.shrink();

    return Positioned(
      left: focus.dx - 24,
      top: focus.dy - 24,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey<Offset>(focus),
          tween: Tween<double>(begin: 1.35, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.92),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraUnavailable() {
    final denied = _cameraPermissionDenied;

    return Positioned.fill(
      child: ColoredBox(
        color: _background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  denied
                      ? Icons.no_photography_outlined
                      : Icons.camera_alt_outlined,
                  size: 38,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
                const SizedBox(height: 15),
                Text(
                  denied
                      ? 'Camera access is turned off'
                      : 'Camera could not be started',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  denied
                      ? 'Allow camera access in Settings to take photos and videos.'
                      : 'Try reopening the camera. If you are using an emulator, make sure a camera source is enabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: denied
                      ? () => unawaited(
                          AppPermissionService.instance.openSettings(),
                        )
                      : () => unawaited(_initialiseCamera()),
                  child: Text(denied ? 'Open settings' : 'Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final cameraReady = controller != null && controller.value.isInitialized;
    final routeAnimation = ModalRoute.of(context)?.animation;
    final sharedCameraTransition =
        widget.openingCameraRect != null && routeAnimation != null;

    final backdropOpacity = routeAnimation == null
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: routeAnimation,
            curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(0.22, 1, curve: Curves.easeInCubic),
          );
    final chromeOpacity = routeAnimation == null
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: routeAnimation,
            curve: const Interval(0.30, 1, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(0.30, 1, curve: Curves.easeInCubic),
          );

    Widget chrome = Stack(
      fit: StackFit.expand,
      children: [
        if (cameraReady) _buildPreviewGestureLayer(controller),

        if (cameraReady)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x52000000), Color(0x00000000)],
                    stops: [0, 0.34],
                  ),
                ),
              ),
            ),
          ),

        if (!_initializing && !cameraReady) _buildCameraUnavailable(),

        if (_initializing && !cameraReady)
          const Positioned.fill(
            child: ColoredBox(
              color: _background,
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),

        if (cameraReady) _buildFocusIndicator(),

        _buildTopControls(),

        if (cameraReady) _buildBottomControls(),

        if (_captureBusy && !_recording)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.04)),
            ),
          ),
      ],
    );

    if (sharedCameraTransition) {
      // Controls belong to the destination screen, not the shared camera tile.
      // Let the live preview expand first, then bring the controls in during the
      // same route animation. On Back this runs in reverse, so the controls are
      // already gone while the preview contracts into the attachment tile.
      chrome = FadeTransition(opacity: chromeOpacity, child: chrome);
    }

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarDividerColor: Colors.black,
          systemNavigationBarContrastEnforced: false,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          // Keep the route transparent while the measured preview rectangle
          // expands or contracts; otherwise a full black page would cover the
          // attachment panel before that motion can be seen.
          backgroundColor: sharedCameraTransition
              ? Colors.transparent
              : _background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (sharedCameraTransition)
                FadeTransition(
                  opacity: backdropOpacity,
                  child: const ColoredBox(color: _background),
                )
              else
                const ColoredBox(color: _background),

              Positioned.fill(
                child: _buildTransitioningCameraSurface(
                  controller: controller,
                  cameraReady: cameraReady,
                  routeAnimation: routeAnimation,
                ),
              ),

              chrome,
            ],
          ),
        ),
      ),
    );
  }
}
