import 'dart:async';

import 'dart:io';

import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:path/path.dart' as p;

import 'package:path_provider/path_provider.dart';

import 'package:wrytte/ui/theme/wrytte_visual_style.dart';

/// Hero used specifically for the gallery -> profile-photo crop transition.
///
/// Unlike the generic fullscreen-image Hero, this shuttle owns the crop mask
/// during the flight. The photo, dimmed outside area, and circular guide are
/// therefore composited as one moving visual instead of the mask appearing
/// only after the image lands on the crop route.
class ProfilePhotoCropImageHero extends StatelessWidget {
  const ProfilePhotoCropImageHero({
    super.key,
    required this.tag,
    required this.source,
    required this.child,
    this.flightChild,
    this.normalizedCropRect,
    this.flightStartBorderRadius = 0,
  });

  final Object tag;
  final String source;
  final Widget child;
  final Widget? flightChild;

  /// Crop window expressed in normalized coordinates relative to this Hero's
  /// bounds. Gallery thumbnails leave this null; the crop destination provides
  /// it so the same geometry can be used during both push and pop flights.
  final Rect? normalizedCropRect;
  final double flightStartBorderRadius;

  @override
  Widget build(BuildContext context) {
    final endpointChild = normalizedCropRect == null
        ? child
        : Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: child),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ProfilePhotoCropOverlayPainter(
                      normalizedCropRect: normalizedCropRect!,
                      progress: 1,
                    ),
                  ),
                ),
              ),
            ],
          );

    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      placeholderBuilder: (context, size, child) =>
          SizedBox.fromSize(size: size),
      flightShuttleBuilder:
          (context, animation, direction, fromHeroContext, toHeroContext) {
        final fromHero = fromHeroContext.widget as Hero;
        final toHero = toHeroContext.widget as Hero;
        final fromPayload = fromHero.child as _ProfilePhotoCropHeroPayload;
        final toPayload = toHero.child as _ProfilePhotoCropHeroPayload;

        // The crop route is the endpoint that owns crop geometry. On push that
        // is the destination Hero; on pop it is the source Hero.
        final cropRect =
            toPayload.normalizedCropRect ?? fromPayload.normalizedCropRect;

        final directFile = File(source);
        final image =
            flightChild ??
            (directFile.existsSync()
                ? Image.file(
                    directFile,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  )
                : endpointChild);

        return AnimatedBuilder(
          animation: animation,
          child: image,
          builder: (context, image) {
            // HeroFlightDirection.push runs 0 -> 1 while pop runs 1 -> 0.
            // Bring the crop treatment in early on push so it reads as part of
            // the expansion, and let it clear quickly/smoothly on the return.
            final value = animation.value.clamp(0.0, 1.0).toDouble();
            final overlayProgress = direction == HeroFlightDirection.push
                ? Curves.easeOutCubic.transform(value)
                : Curves.easeInCubic.transform(value);
            final radiusProgress = Curves.easeOutCubic.transform(value);

            return ClipRRect(
              borderRadius: BorderRadius.circular(
                ui.lerpDouble(
                  flightStartBorderRadius,
                  0,
                  radiusProgress,
                )!,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: image!),
                  if (cropRect != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ProfilePhotoCropOverlayPainter(
                            normalizedCropRect: cropRect,
                            progress: overlayProgress,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
      child: _ProfilePhotoCropHeroPayload(
        normalizedCropRect: normalizedCropRect,
        child: endpointChild,
      ),
    );
  }
}

class _ProfilePhotoCropHeroPayload extends StatelessWidget {
  const _ProfilePhotoCropHeroPayload({
    required this.normalizedCropRect,
    required this.child,
  });

  final Rect? normalizedCropRect;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _ProfilePhotoCropOverlayPainter extends CustomPainter {
  const _ProfilePhotoCropOverlayPainter({
    required this.normalizedCropRect,
    required this.progress,
  });

  final Rect normalizedCropRect;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress <= 0) return;

    final cropRect = Rect.fromLTRB(
      normalizedCropRect.left * size.width,
      normalizedCropRect.top * size.height,
      normalizedCropRect.right * size.width,
      normalizedCropRect.bottom * size.height,
    );

    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(cropRect);

    canvas.drawPath(
      mask,
      Paint()
        ..isAntiAlias = true
        ..color = Colors.black.withValues(alpha: 0.56 * progress),
    );

  }

  @override
  bool shouldRepaint(covariant _ProfilePhotoCropOverlayPainter oldDelegate) =>
      oldDelegate.normalizedCropRect != normalizedCropRect ||
      oldDelegate.progress != progress;
}

/// Profile-photo crop step used before an auth profile photo is kept.

///

/// The circular avatar frame stays fixed while the photo moves and scales

/// behind it. This keeps the selection geometry predictable and prevents the

/// frame itself from drifting while the user composes their avatar.

class ProfilePhotoCropPage extends StatefulWidget {

  const ProfilePhotoCropPage({

    super.key,

    required this.sourcePath,

    this.sourcePixelSize,

    this.openedFromCamera = false,

    this.openingImageHeroTag,

  });

  final String sourcePath;

  final Size? sourcePixelSize;

  final bool openedFromCamera;

  final Object? openingImageHeroTag;

  @override

  State<ProfilePhotoCropPage> createState() => _ProfilePhotoCropPageState();

}

class _ProfilePhotoCropPageState extends State<ProfilePhotoCropPage> {

  static const int _outputDimension = 640;

  Size? _sourceSize;

  Rect _activeCropRect = Rect.zero;

  double _imageScale = 1;

  Offset _imageOffset = Offset.zero;

  double _gestureStartScale = 1;

  Offset _gestureStartOffset = Offset.zero;

  Offset _gestureStartFocalPoint = Offset.zero;

  bool _loading = true;

  bool _saving = false;

  String? _loadError;

  @override

  void initState() {

    super.initState();

    final knownSize = widget.sourcePixelSize;

    if (knownSize != null && knownSize.width > 0 && knownSize.height > 0) {

      _sourceSize = knownSize;

      _loading = false;

    } else {

      _loadSourceDimensions();

    }

  }

  Future<void> _loadSourceDimensions() async {

    try {

      final bytes = await File(widget.sourcePath).readAsBytes();

      final codec = await ui.instantiateImageCodec(bytes);

      final frame = await codec.getNextFrame();

      final size = Size(

        frame.image.width.toDouble(),

        frame.image.height.toDouble(),

      );

      frame.image.dispose();

      codec.dispose();

      if (!mounted) return;

      setState(() {

        _sourceSize = size;

        _loading = false;

      });

    } catch (error) {

      debugPrint('Profile photo crop could not decode source: $error');

      if (!mounted) return;

      setState(() {

        _loading = false;

        _loadError = 'This photo could not be opened.';

      });

    }

  }

  Rect _cropRectFor(Size viewport, EdgeInsets safePadding) {

    final top = safePadding.top + 76;

    final bottom = math.max(top + 1, viewport.height - safePadding.bottom - 24);

    final availableHeight = bottom - top;

    final diameter = math.max(1.0, math.min(viewport.width, availableHeight));

    return Rect.fromCenter(

      center: Offset(viewport.width / 2, top + (availableHeight / 2)),

      width: diameter,

      height: diameter,

    );

  }

  double _baseImageScale(Rect cropRect) => math.max(

    cropRect.width / _sourceSize!.width,

    cropRect.height / _sourceSize!.height,

  );

  Size _displayedImageSize(Rect cropRect, double scale) {

    final resolvedScale = _baseImageScale(cropRect) * scale;

    return Size(

      _sourceSize!.width * resolvedScale,

      _sourceSize!.height * resolvedScale,

    );

  }

  Offset _constrainImageOffset(Offset candidate, Rect cropRect, double scale) {

    final imageSize = _displayedImageSize(cropRect, scale);

    final horizontalTravel = math.max(

      0,

      (imageSize.width - cropRect.width) / 2,

    );

    final verticalTravel = math.max(

      0,

      (imageSize.height - cropRect.height) / 2,

    );

    // At the minimum cover scale, horizontal movement adds no value for an

    // avatar and makes alignment feel unstable. Zooming unlocks both axes.

    final horizontalUnlocked = scale > 1.001;

    return Offset(

      horizontalUnlocked

          ? candidate.dx.clamp(-horizontalTravel, horizontalTravel).toDouble()

          : 0,

      candidate.dy.clamp(-verticalTravel, verticalTravel).toDouble(),

    );

  }

  Rect _resolveCropRect(Rect cropRect) {

    if (!_activeCropRect.isEmpty && _activeCropRect != cropRect) {

      final ratio = cropRect.width / _activeCropRect.width;

      _imageOffset *= ratio;

    }

    _activeCropRect = cropRect;

    _imageOffset = _constrainImageOffset(_imageOffset, cropRect, _imageScale);

    return cropRect;

  }

  void _handleScaleStart(ScaleStartDetails details) {

    _gestureStartScale = _imageScale;

    _gestureStartOffset = _imageOffset;

    _gestureStartFocalPoint = details.localFocalPoint;

  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {

    if (_activeCropRect.isEmpty) return;

    final nextScale = (_gestureStartScale * details.scale)

        .clamp(1.0, 6.0)

        .toDouble();

    final scaleRatio = nextScale / _gestureStartScale;

    final startFocalFromCrop = _gestureStartFocalPoint - _activeCropRect.center;

    final currentFocalFromCrop =

        details.localFocalPoint - _activeCropRect.center;

    final candidateOffset =

        currentFocalFromCrop +

        ((_gestureStartOffset - startFocalFromCrop) * scaleRatio);

    setState(() {

      _imageScale = nextScale;

      _imageOffset = _constrainImageOffset(

        candidateOffset,

        _activeCropRect,

        nextScale,

      );

    });

  }

  Future<void> _saveCrop() async {

    if (_saving || _sourceSize == null) return;

    setState(() => _saving = true);

    unawaited(HapticFeedback.mediumImpact());

    try {

      FocusManager.instance.primaryFocus?.unfocus();

      final cropRect = _activeCropRect;

      if (cropRect.isEmpty) {

        throw StateError('Crop guide is not ready');

      }

      final displayedImageSize = _displayedImageSize(cropRect, _imageScale);

      final imageRect = Rect.fromCenter(

        center: cropRect.center + _imageOffset,

        width: displayedImageSize.width,

        height: displayedImageSize.height,

      );

      final bytes = await File(widget.sourcePath).readAsBytes();

      final codec = await ui.instantiateImageCodec(bytes);

      final frame = await codec.getNextFrame();

      final sourceImage = frame.image;

      final scaleX = sourceImage.width / imageRect.width;

      final scaleY = sourceImage.height / imageRect.height;

      final sourceCrop = Rect.fromLTRB(

        ((cropRect.left - imageRect.left) * scaleX)

            .clamp(0, sourceImage.width.toDouble())

            .toDouble(),

        ((cropRect.top - imageRect.top) * scaleY)

            .clamp(0, sourceImage.height.toDouble())

            .toDouble(),

        ((cropRect.right - imageRect.left) * scaleX)

            .clamp(0, sourceImage.width.toDouble())

            .toDouble(),

        ((cropRect.bottom - imageRect.top) * scaleY)

            .clamp(0, sourceImage.height.toDouble())

            .toDouble(),

      );

      final recorder = ui.PictureRecorder();

      final canvas = Canvas(recorder);

      canvas.drawImageRect(

        sourceImage,

        sourceCrop,

        Rect.fromLTWH(

          0,

          0,

          _outputDimension.toDouble(),

          _outputDimension.toDouble(),

        ),

        Paint()..filterQuality = FilterQuality.high,

      );

      sourceImage.dispose();

      codec.dispose();

      final croppedImage = await recorder.endRecording().toImage(

        _outputDimension,

        _outputDimension,

      );

      final data = await croppedImage.toByteData(

        format: ui.ImageByteFormat.png,

      );

      croppedImage.dispose();

      if (data == null) throw StateError('Could not encode crop');

      final directory = await getTemporaryDirectory();

      final outputPath = p.join(

        directory.path,

        'wrytte_profile_${DateTime.now().microsecondsSinceEpoch}.png',

      );

      await File(outputPath).writeAsBytes(

        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),

        flush: true,

      );

      if (!mounted) return;

      // Keep the Hero alive for a successful pop as well as cancellation.

      // This lets the cropped screen reverse-fly into the selected gallery tile

      // before that tile performs the final handoff into the profile avatar.

      Navigator.of(context).pop(outputPath);

    } catch (error) {

      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context)

        ..hideCurrentSnackBar()

        ..showSnackBar(

          const SnackBar(content: Text('Could not prepare this photo.')),

        );

    }

  }

  @override

  Widget build(BuildContext context) {

    final sourceFile = File(widget.sourcePath);

    return PopScope(

      canPop: !_saving,

      child: Scaffold(

        key: const ValueKey('profile-photo-crop-page'),

        // Use one continuous crop surface. The outside-mask dimming blends

        // into this same black, so the transparent top bar never reads as a

        // separate strip above the workspace.

        backgroundColor: Colors.black,

        body: Stack(

          fit: StackFit.expand,

          children: [

            LayoutBuilder(

              builder: (context, constraints) {

                final viewportSize = constraints.biggest;

                return _loading

                    ? const SizedBox.shrink()

                    : _loadError != null

                    ? Center(

                        child: _CropLoadError(

                          message: _loadError!,

                          onClose: () => Navigator.of(context).maybePop(),

                        ),

                      )

                    : _buildCropWorkspace(

                        sourceFile,

                        viewportSize,

                        _cropRectFor(

                          viewportSize,

                          MediaQuery.paddingOf(context),

                        ),

                      );

              },

            ),

            SafeArea(

              child: Align(

                alignment: Alignment.topCenter,

                child: _CropTopBar(

                  saving: _saving,

                  canChoose: !_loading && _loadError == null,

                  showBackIcon:
                      widget.openedFromCamera ||
                      widget.openingImageHeroTag != null,

                  backLabel: widget.openedFromCamera
                      ? 'Back to camera'
                      : widget.openingImageHeroTag != null
                      ? 'Back to gallery'
                      : 'Cancel',

                  onBack: () {

                    unawaited(HapticFeedback.selectionClick());

                    Navigator.of(context).maybePop();

                  },

                  onChoose: () => _saveCrop(),

                ),

              ),

            ),

          ],

        ),

      ),

    );

  }

  Widget _buildCropWorkspace(

    File sourceFile,

    Size viewportSize,

    Rect proposedCropRect,

  ) {

    final cropRect = _resolveCropRect(proposedCropRect);

    final displayedImageSize = _displayedImageSize(cropRect, _imageScale);

    final imageRect = Rect.fromCenter(

      center: cropRect.center + _imageOffset,

      width: displayedImageSize.width,

      height: displayedImageSize.height,

    );

    return SizedBox(

      key: const ValueKey('profile-photo-crop-workspace'),

      width: viewportSize.width,

      height: viewportSize.height,

      child: Semantics(

        container: true,

        image: true,

        label: 'Adjust profile photo',

        hint:

            'Drag the photo vertically. Pinch to zoom, then drag in any direction.',

        child: GestureDetector(

          key: const ValueKey('profile-photo-crop-viewer'),

          behavior: HitTestBehavior.opaque,

          onScaleStart: _handleScaleStart,

          onScaleUpdate: _handleScaleUpdate,

          child: Stack(

            fit: StackFit.expand,

            children: [

              Positioned.fromRect(

                rect: imageRect,

                child: ClipRect(

                  child: widget.openingImageHeroTag == null

                      ? Stack(

                          fit: StackFit.expand,

                          children: [

                            Positioned.fill(child: _cropImage(sourceFile)),

                            Positioned.fill(

                              child: IgnorePointer(

                                child: CustomPaint(

                                  painter: _ProfilePhotoCropOverlayPainter(

                                    normalizedCropRect: _normalizedCropRect(

                                      imageRect: imageRect,

                                      cropRect: cropRect,

                                    ),

                                    progress: 1,

                                  ),

                                ),

                              ),

                            ),

                          ],

                        )

                      : ProfilePhotoCropImageHero(

                          tag: widget.openingImageHeroTag!,

                          source: widget.sourcePath,

                          normalizedCropRect: _normalizedCropRect(

                            imageRect: imageRect,

                            cropRect: cropRect,

                          ),

                          child: _cropImage(sourceFile),

                        ),

                ),

              ),

            ],

          ),

        ),

      ),

    );

  }

  Rect _normalizedCropRect({
    required Rect imageRect,
    required Rect cropRect,
  }) {
    final localCropRect = cropRect.shift(-imageRect.topLeft);
    return Rect.fromLTRB(
      localCropRect.left / imageRect.width,
      localCropRect.top / imageRect.height,
      localCropRect.right / imageRect.width,
      localCropRect.bottom / imageRect.height,
    );
  }

  Widget _cropImage(File sourceFile) => Image.file(

    sourceFile,

    key: const ValueKey('profile-photo-image-frame'),

    fit: BoxFit.fill,

    filterQuality: FilterQuality.high,

    gaplessPlayback: true,

  );

}

class _CropTopBar extends StatelessWidget {

  const _CropTopBar({

    required this.saving,

    required this.canChoose,

    required this.showBackIcon,

    required this.backLabel,

    required this.onBack,

    required this.onChoose,

  });

  final bool saving;

  final bool canChoose;

  final bool showBackIcon;

  final String backLabel;

  final VoidCallback onBack;

  final VoidCallback onChoose;

  @override

  Widget build(BuildContext context) => SizedBox(

    height: 64,

    child: Row(

      mainAxisAlignment: MainAxisAlignment.spaceBetween,

      children: [

        Padding(

          padding: const EdgeInsetsDirectional.only(start: 12),

          child: _CropRoundActionButton(

            key: const ValueKey('profile-crop-cancel'),

            visualKey: const ValueKey('profile-crop-cancel-visual'),

            label: backLabel,

            onTap: saving ? null : onBack,

            child: showBackIcon

                ? wrytteSvgAssetIcon(

                    assetPath: 'assets/svg/ic--round-arrow-back-ios.svg',

                    canvas: 24,

                    scale: 1,

                    offset: const Offset(-0.5, 0),

                    color: WrytteVisualTokens.iconColor,

                  )

                : const Icon(

                    Icons.close_rounded,

                    size: 24,

                    color: WrytteColors.textPrimary,

                  ),

          ),

        ),

        Padding(

          padding: const EdgeInsetsDirectional.only(end: 12),

          child: _CropRoundActionButton(

            key: const ValueKey('profile-crop-choose'),

            visualKey: const ValueKey('profile-crop-choose-visual'),

            label: 'Choose photo',

            backgroundColor: WrytteColors.primary,

            onTap: canChoose && !saving ? onChoose : null,

            child: wrytteSvgAssetIcon(

              assetPath: 'assets/svg/Checkmark edit.svg',

              canvas: 23,

              scale: 1,

              color: Colors.white,

            ),

          ),

        ),

      ],

    ),

  );

}

/// Mirrors the round glass and confirmation controls in the chat media editor.

class _CropRoundActionButton extends StatelessWidget {

  const _CropRoundActionButton({

    super.key,

    required this.visualKey,

    required this.label,

    required this.onTap,

    required this.child,

    this.backgroundColor,

  });

  final Key visualKey;

  final String label;

  final VoidCallback? onTap;

  final Widget child;

  final Color? backgroundColor;

  @override

  Widget build(BuildContext context) {

    final enabled = onTap != null;

    final button = backgroundColor == null

        ? ClipOval(

            child: BackdropFilter(

              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),

              child: DecoratedBox(

                key: visualKey,

                decoration: wrytteGlassDecoration(radius: 21),

                child: SizedBox.square(

                  dimension: 42,

                  child: Center(child: child),

                ),

              ),

            ),

          )

        : DecoratedBox(

            key: visualKey,

            decoration: BoxDecoration(

              color: backgroundColor,

              shape: BoxShape.circle,

            ),

            child: SizedBox.square(dimension: 42, child: Center(child: child)),

          );

    return Semantics(

      button: true,

      enabled: enabled,

      label: label,

      child: IgnorePointer(

        ignoring: !enabled,

        child: AnimatedOpacity(

          duration: const Duration(milliseconds: 150),

          opacity: enabled ? 1 : 0.45,

          child: SizedBox.square(

            dimension: 42,

            child: Center(

              child: GestureDetector(

                behavior: HitTestBehavior.opaque,

                onTap: onTap,

                child: button,

              ),

            ),

          ),

        ),

      ),

    );

  }

}

class _CropLoadError extends StatelessWidget {

  const _CropLoadError({required this.message, required this.onClose});

  final String message;

  final VoidCallback onClose;

  @override

  Widget build(BuildContext context) => Padding(

    padding: const EdgeInsets.all(32),

    child: Column(

      mainAxisSize: MainAxisSize.min,

      children: [

        const Icon(

          Icons.broken_image_outlined,

          size: 42,

          color: WrytteColors.textMuted,

        ),

        const SizedBox(height: 12),

        Text(

          message,

          textAlign: TextAlign.center,

          style: const TextStyle(

            color: WrytteColors.textSecondary,

            fontFamily: WrytteTypography.primaryFontFamily,

            fontSize: 14,

            fontWeight: FontWeight.w400,

          ),

        ),

        const SizedBox(height: 12),

        TextButton(onPressed: onClose, child: const Text('Go back')),

      ],

    ),

  );

}
