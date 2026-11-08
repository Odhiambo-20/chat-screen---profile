import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wrytte/models/chat_models/ui/video_message_result.dart';
import 'package:wrytte/services/media/camera_inventory_service.dart';
import 'package:wrytte/services/permissions/app_permission_service.dart';

export 'package:wrytte/models/chat_models/ui/video_message_result.dart';

class VideoMessageRecorderScreen extends StatefulWidget {
  final Duration maxDuration;

  const VideoMessageRecorderScreen({
    super.key,
    this.maxDuration = const Duration(seconds: 60),
  });

  @override
  State<VideoMessageRecorderScreen> createState() =>
      _VideoMessageRecorderScreenState();
}

class _VideoMessageRecorderScreenState extends State<VideoMessageRecorderScreen>
    with WidgetsBindingObserver {
  static const int _videoBitrate = 1800000;
  static const int _audioBitrate = 64000;
  static const int _framesPerSecond = 24;

  CameraController? _controller;
  Timer? _timer;
  bool _initialising = true;
  bool _recording = false;
  bool _closing = false;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialiseAndRecord());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_finish(save: false));
    }
  }

  Future<void> _initialiseAndRecord() async {
    final cameraGranted =
        await AppPermissionService.instance.ensureCameraGranted();
    if (!mounted || !cameraGranted) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final microphoneGranted =
        await AppPermissionService.instance.ensureMicrophoneGranted();
    if (!microphoneGranted) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    try {
      final cameras = await CameraInventoryService.instance.load();
      if (cameras.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final camera =
          preferredCameraForDirection(cameras, CameraLensDirection.front) ??
          cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
        fps: _framesPerSecond,
        videoBitrate: _videoBitrate,
        audioBitrate: _audioBitrate,
      );
      await controller.initialize();
      await controller.prepareForVideoRecording();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initialising = false;
      });
      await _startRecording();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || _recording || !controller.value.isInitialized) {
      return;
    }

    await controller.startVideoRecording();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _elapsedSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _elapsedSeconds + 1;
      setState(() => _elapsedSeconds = next);
      if (next >= widget.maxDuration.inSeconds) {
        unawaited(_finish(save: true));
      }
    });
  }

  Future<void> _finish({required bool save}) async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();

    final controller = _controller;
    XFile? file;
    if (controller != null && controller.value.isRecordingVideo) {
      file = await controller.stopVideoRecording();
    }

    if (!mounted) return;
    if (!save || file == null || _elapsedSeconds < 1) {
      if (file != null) {
        final recorded = File(file.path);
        if (await recorded.exists()) await recorded.delete();
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pop(
      VideoMessageResult(
        filePath: file.path,
        durationSeconds: _elapsedSeconds.clamp(1, widget.maxDuration.inSeconds),
      ),
    );
  }

  String get _timeLabel {
    final minutes = (_elapsedSeconds ~/ 60).toString();
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_initialising &&
              controller != null &&
              controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: CameraPreview(controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          SafeArea(
            maintainBottomViewPadding: true,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _finish(save: false),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.42),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.circle,
                              color: Colors.redAccent,
                              size: 9,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _timeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _recording ? () => _finish(save: true) : null,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: const Icon(
                        Icons.stop_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
