part of 'chat_media_editor.dart';

class _TextLayerGeometry {
  final Offset center;
  final Size size;
  final double rotation;
  final double screenScale;

  const _TextLayerGeometry({
    required this.center,
    required this.size,
    required this.rotation,
    required this.screenScale,
  });
}

class _TextHandleSpec {
  final Offset normalizedPosition;
  final bool primary;
  final String label;

  const _TextHandleSpec({
    required this.normalizedPosition,
    required this.primary,
    required this.label,
  });
}

/// Selection and transformation UI for committed text layers.
///
/// Pro Image Editor owns the real layer and export. This overlay measures the
/// package-rendered TextLayer, provides Telegram-like selection dots and mutates
/// the layer's real offset/scale/rotation while it is dragged.
class _TextLayerInteractionOverlay extends StatefulWidget {
  final ProImageEditorState editor;
  final ValueNotifier<TextLayer?> selectedLayer;
  final ValueChanged<TextLayer> onEdit;

  const _TextLayerInteractionOverlay({
    required this.editor,
    required this.selectedLayer,
    required this.onEdit,
  });

  @override
  State<_TextLayerInteractionOverlay> createState() =>
      _TextLayerInteractionOverlayState();
}

class _TextLayerInteractionOverlayState
    extends State<_TextLayerInteractionOverlay>
    with WidgetsBindingObserver {
  static const double _handleVisualSize = 9;
  static const double _handleTouchSize = 34;
  static const double _handleInset = 1.5;

  static const List<_TextHandleSpec> _handles = <_TextHandleSpec>[
    _TextHandleSpec(
      normalizedPosition: Offset(-1, -1),
      primary: true,
      label: 'Resize and rotate text from top left',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(0, -1),
      primary: false,
      label: 'Resize and rotate text from top',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(1, -1),
      primary: true,
      label: 'Resize and rotate text from top right',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(-1, 0),
      primary: false,
      label: 'Resize and rotate text from left',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(1, 0),
      primary: false,
      label: 'Resize and rotate text from right',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(-1, 1),
      primary: true,
      label: 'Resize and rotate text from bottom left',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(0, 1),
      primary: false,
      label: 'Resize and rotate text from bottom',
    ),
    _TextHandleSpec(
      normalizedPosition: Offset(1, 1),
      primary: true,
      label: 'Resize and rotate text from bottom right',
    ),
  ];

  final GlobalKey _overlayKey = GlobalKey();
  Map<String, _TextLayerGeometry> _geometry = const {};
  bool _measurementScheduled = false;

  TextLayer? _gestureLayer;
  double _gestureStartScale = 1;
  double _gestureStartRotation = 0;
  double _gestureScreenScale = 1;

  TextLayer? _handleLayer;
  double _handleStartScale = 1;
  double _handleStartRotation = 0;
  double _handleStartDistance = 1;
  double _handleStartAngle = 0;
  double _handleScreenScale = 1;
  Offset _handleCenterGlobal = Offset.zero;
  Offset _handlePointerOffsetGlobal = Offset.zero;

  List<TextLayer> get _textLayers =>
      widget.editor.activeLayers.whereType<TextLayer>().toList(growable: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _TextLayerInteractionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor) {
      _geometry = const {};
      _scheduleMeasurement();
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled || !mounted) return;
    _measurementScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      _measureLayers();
    });
  }

  RenderBox? _layerRenderBox(TextLayer layer) {
    final candidates = <BuildContext?>[
      layer.keyInternalSize.currentContext,
      layer.repaintBoundaryKey.currentContext,
      layer.key.currentContext,
    ];

    for (final candidate in candidates) {
      final renderObject = candidate?.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize) {
        return renderObject;
      }
    }

    return null;
  }

  void _measureLayers() {
    final overlayObject = _overlayKey.currentContext?.findRenderObject();
    if (overlayObject is! RenderBox ||
        !overlayObject.attached ||
        !overlayObject.hasSize) {
      return;
    }

    final next = <String, _TextLayerGeometry>{};

    for (final layer in _textLayers) {
      final box = _layerRenderBox(layer);
      if (box == null || box.size.isEmpty) continue;

      final topLeft = overlayObject.globalToLocal(
        box.localToGlobal(Offset.zero),
      );
      final topRight = overlayObject.globalToLocal(
        box.localToGlobal(Offset(box.size.width, 0)),
      );
      final bottomLeft = overlayObject.globalToLocal(
        box.localToGlobal(Offset(0, box.size.height)),
      );
      final bottomRight = overlayObject.globalToLocal(
        box.localToGlobal(Offset(box.size.width, box.size.height)),
      );

      final corners = <Offset>[topLeft, topRight, bottomLeft, bottomRight];

      if (corners.any((point) => !point.isFinite)) continue;

      final horizontalVector = topRight - topLeft;
      final verticalVector = bottomLeft - topLeft;
      final visualWidth = horizontalVector.distance;
      final visualHeight = verticalVector.distance;

      if (!visualWidth.isFinite ||
          !visualHeight.isFinite ||
          visualWidth <= 0 ||
          visualHeight <= 0) {
        continue;
      }

      final visualScale =
          box.size.width <= 0 ? 1.0 : visualWidth / box.size.width;
      final center = Offset(
        corners.map((point) => point.dx).reduce((a, b) => a + b) / 4,
        corners.map((point) => point.dy).reduce((a, b) => a + b) / 4,
      );

      next[layer.id] = _TextLayerGeometry(
        center: center,
        size: Size(visualWidth, visualHeight),
        rotation: math.atan2(horizontalVector.dy, horizontalVector.dx),
        screenScale: visualScale.isFinite && visualScale > 0 ? visualScale : 1,
      );
    }

    final selected = widget.selectedLayer.value;
    if (selected != null &&
        !_textLayers.any((layer) => layer.id == selected.id)) {
      widget.selectedLayer.value = null;
    }

    if (_sameGeometry(_geometry, next)) return;
    setState(() => _geometry = next);
  }

  bool _sameGeometry(
    Map<String, _TextLayerGeometry> first,
    Map<String, _TextLayerGeometry> second,
  ) {
    if (first.length != second.length) return false;

    for (final entry in first.entries) {
      final other = second[entry.key];
      if (other == null) return false;

      final value = entry.value;
      if ((value.center.dx - other.center.dx).abs() > 0.2 ||
          (value.center.dy - other.center.dy).abs() > 0.2 ||
          (value.size.width - other.size.width).abs() > 0.2 ||
          (value.size.height - other.size.height).abs() > 0.2 ||
          (value.rotation - other.rotation).abs() > 0.002 ||
          (value.screenScale - other.screenScale).abs() > 0.002) {
        return false;
      }
    }

    return true;
  }

  void _select(TextLayer layer) {
    widget.editor.clearLayerSelection();

    if (widget.selectedLayer.value?.id == layer.id) return;
    unawaited(HapticFeedback.selectionClick());
    widget.selectedLayer.value = layer;
  }

  void _deselect() {
    if (widget.selectedLayer.value == null) return;
    unawaited(HapticFeedback.selectionClick());
    widget.selectedLayer.value = null;
  }

  void _notifyLayerChanged() {
    widget.editor.setState(() {});
    _scheduleMeasurement();
  }

  void _onScaleStart(
    TextLayer layer,
    _TextLayerGeometry geometry,
    ScaleStartDetails details,
  ) {
    _select(layer);
    _gestureLayer = layer;
    _gestureStartScale = layer.scale;
    _gestureStartRotation = layer.rotation;
    _gestureScreenScale = geometry.screenScale <= 0 ? 1 : geometry.screenScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final layer = _gestureLayer;
    if (layer == null) return;

    layer.offset += details.focalPointDelta / _gestureScreenScale;
    layer.scale =
        (_gestureStartScale * details.scale).clamp(0.25, 8.0).toDouble();
    layer.rotation = _gestureStartRotation + details.rotation;

    _notifyLayerChanged();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureLayer = null;
    _scheduleMeasurement();
  }

  double _normalizeAngle(double angle) {
    while (angle > math.pi) {
      angle -= math.pi * 2;
    }
    while (angle < -math.pi) {
      angle += math.pi * 2;
    }
    return angle;
  }

  Offset _handlePoint(_TextLayerGeometry geometry, Offset normalizedPosition) {
    final halfWidth = math.max(0.0, geometry.size.width / 2 - _handleInset);
    final halfHeight = math.max(0.0, geometry.size.height / 2 - _handleInset);

    final local = Offset(
      normalizedPosition.dx * halfWidth,
      normalizedPosition.dy * halfHeight,
    );
    final cosine = math.cos(geometry.rotation);
    final sine = math.sin(geometry.rotation);

    return geometry.center +
        Offset(
          local.dx * cosine - local.dy * sine,
          local.dx * sine + local.dy * cosine,
        );
  }

  void _onHandlePanStart(
    TextLayer layer,
    _TextLayerGeometry geometry,
    Offset handlePoint,
    DragStartDetails details,
  ) {
    _select(layer);

    final overlayBox = _overlayKey.currentContext?.findRenderObject();
    if (overlayBox is! RenderBox) return;

    _handleLayer = layer;
    _handleScreenScale = geometry.screenScale <= 0 ? 1 : geometry.screenScale;
    _handleStartScale = layer.scale;
    _handleStartRotation = layer.rotation;
    _handleCenterGlobal = overlayBox.localToGlobal(geometry.center);

    final handleGlobal = overlayBox.localToGlobal(handlePoint);
    _handlePointerOffsetGlobal = details.globalPosition - handleGlobal;
    final startVector = handleGlobal - _handleCenterGlobal;
    _handleStartDistance = math.max(1.0, startVector.distance);
    _handleStartAngle = math.atan2(startVector.dy, startVector.dx);
  }

  void _onHandlePanUpdate(DragUpdateDetails details) {
    final layer = _handleLayer;
    if (layer == null) return;

    final handleGlobal = details.globalPosition - _handlePointerOffsetGlobal;
    final currentVector = handleGlobal - _handleCenterGlobal;
    final currentDistance = math.max(1.0, currentVector.distance);
    final currentAngle = math.atan2(currentVector.dy, currentVector.dx);

    layer.scale =
        (_handleStartScale * currentDistance / _handleStartDistance)
            .clamp(0.25, 8.0)
            .toDouble();
    layer.rotation =
        _handleStartRotation +
        _normalizeAngle(currentAngle - _handleStartAngle);

    _notifyLayerChanged();
  }

  void _onHandlePanEnd([DragEndDetails? details]) {
    _handleLayer = null;
    _scheduleMeasurement();
  }

  Widget _positionedLayerBox({
    required _TextLayerGeometry geometry,
    required Widget child,
    double inflate = 0,
  }) {
    final width = math.max(1.0, geometry.size.width + inflate * 2);
    final height = math.max(1.0, geometry.size.height + inflate * 2);

    return Positioned(
      left: geometry.center.dx - width / 2,
      top: geometry.center.dy - height / 2,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: geometry.rotation,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _selectionBorder(_TextLayerGeometry geometry) {
    return IgnorePointer(
      child: _positionedLayerBox(
        geometry: geometry,
        inflate: 5,
        child: CustomPaint(painter: const _TelegramTextSelectionDotsPainter()),
      ),
    );
  }

  Widget _controlPoint(
    TextLayer layer,
    _TextLayerGeometry geometry,
    _TextHandleSpec handle,
  ) {
    final point = _handlePoint(geometry, handle.normalizedPosition);

    return Positioned(
      left: point.dx - _handleTouchSize / 2,
      top: point.dy - _handleTouchSize / 2,
      width: _handleTouchSize,
      height: _handleTouchSize,
      child: Semantics(
        button: true,
        label: handle.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart:
              (details) => _onHandlePanStart(layer, geometry, point, details),
          onPanUpdate: _onHandlePanUpdate,
          onPanEnd: _onHandlePanEnd,
          onPanCancel: _onHandlePanEnd,
          child: Center(
            child: Container(
              width: _handleVisualSize,
              height: _handleVisualSize,
              decoration: BoxDecoration(
                color:
                    handle.primary
                        ? WrytteColors.primary
                        : const Color(0xFFF7FAFF),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      handle.primary
                          ? const Color(0xFFF7FAFF)
                          : WrytteColors.primary,
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    final layers = _textLayers;

    return KeyedSubtree(
      key: _overlayKey,
      child: ValueListenableBuilder<TextLayer?>(
        valueListenable: widget.selectedLayer,
        builder: (context, selectedLayer, child) {
          final children = <Widget>[];

          if (selectedLayer != null) {
            children.add(
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _deselect,
                  child: const SizedBox.expand(),
                ),
              ),
            );
          }

          for (final layer in layers) {
            final geometry = _geometry[layer.id];
            if (geometry == null) continue;

            final isSelected = selectedLayer?.id == layer.id;

            children.add(
              _positionedLayerBox(
                geometry: geometry,
                inflate: 12,
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Movable text layer',
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _select(layer),
                    onDoubleTap: () {
                      _select(layer);
                      widget.onEdit(layer);
                    },
                    onScaleStart:
                        (details) => _onScaleStart(layer, geometry, details),
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );

            if (isSelected) {
              children.add(_selectionBorder(geometry));

              for (final handle in _handles) {
                children.add(_controlPoint(layer, geometry, handle));
              }
            }
          }

          return Stack(clipBehavior: Clip.none, children: children);
        },
      ),
    );
  }
}

class _TelegramTextSelectionDotsPainter extends CustomPainter {
  const _TelegramTextSelectionDotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final radius = math.min(12.0, size.shortestSide / 4);
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(rect.deflate(0.7), Radius.circular(radius)),
        );

    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    const spacing = 8.0;
    const blueRadius = 1.35;
    const whiteRadius = 1.0;

    for (double distance = 0; distance < metric.length; distance += spacing) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;

      final index = (distance / spacing).round();
      final isBlue = index.isEven;

      canvas.drawCircle(
        tangent.position,
        isBlue ? blueRadius : whiteRadius,
        Paint()
          ..color = isBlue ? WrytteColors.primary : const Color(0xDDF7FAFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TelegramTextSelectionDotsPainter oldDelegate) {
    return false;
  }
}

/// Horizontally aligns [child] with the exact screen-space center of a widget
/// identified by [targetKey].
///
/// Pro Image Editor mounts its custom app bar and `bodyItems` in separate
/// render boxes. Therefore, reusing the app bar's right padding inside
/// `bodyItems` can still leave the two controls visibly offset. This widget
/// converts through global coordinates, then applies an explicit horizontal
/// offset so the picker can be moved right consistently on every device.

bool _isTransformablePaintShape(PaintLayer layer) {
  switch (layer.item.mode) {
    case PaintMode.rect:
    case PaintMode.circle:
    case PaintMode.polygon:
    case PaintMode.arrow:
      return true;
    default:
      return false;
  }
}

class _PaintLayerGeometry {
  final Offset center;
  final Size size;
  final double rotation;
  final double screenScale;

  const _PaintLayerGeometry({
    required this.center,
    required this.size,
    required this.rotation,
    required this.screenScale,
  });
}

enum _PaintHandleRole { transform, move }

class _PaintHandleSpec {
  final Offset normalizedPosition;
  final _PaintHandleRole role;
  final String label;

  const _PaintHandleSpec({
    required this.normalizedPosition,
    this.role = _PaintHandleRole.transform,
    required this.label,
  });
}

/// Adds direct manipulation to shape paint layers while the paint editor is
/// open. Pro Image Editor still owns and renders the real PaintLayer. This
/// overlay only supplies hit targets and Telegram-style blue control points.
class _PaintShapeInteractionOverlay extends StatefulWidget {
  final PaintEditorState editor;
  final ValueNotifier<PaintLayer?> selectedLayer;

  const _PaintShapeInteractionOverlay({
    required this.editor,
    required this.selectedLayer,
  });

  @override
  State<_PaintShapeInteractionOverlay> createState() =>
      _PaintShapeInteractionOverlayState();
}

class _PaintShapeInteractionOverlayState
    extends State<_PaintShapeInteractionOverlay>
    with WidgetsBindingObserver {
  static const double _handleVisualSize = 8.5;
  static const double _handleTouchSize = 32;

  // Pull the visible control-point centres slightly inside the measured layer
  // bounds. This makes each blue dot overlap the shape stroke instead of
  // appearing to float just outside it. The larger invisible touch target is
  // unchanged, so the handles remain easy to grab.
  static const double _handleInset = 3.5;

  final GlobalKey _overlayKey = GlobalKey();
  Map<String, _PaintLayerGeometry> _geometry = const {};
  bool _measurementScheduled = false;

  PaintLayer? _gestureLayer;
  double _gestureStartScale = 1;
  double _gestureStartRotation = 0;
  double _gestureScreenScale = 1;

  PaintLayer? _handleLayer;
  _PaintHandleRole? _activeHandleRole;
  double _handleStartScale = 1;
  double _handleStartRotation = 0;
  double _handleStartDistance = 1;
  double _handleStartAngle = 0;
  double _handleScreenScale = 1;
  Offset _handleCenterGlobal = Offset.zero;
  Offset _handlePointerOffsetGlobal = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _PaintShapeInteractionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor) {
      _geometry = const {};
      _scheduleMeasurement();
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<PaintLayer> get _shapeLayers => widget.editor.activeHistory.layers
      .whereType<PaintLayer>()
      .where(_isTransformablePaintShape)
      .toList(growable: false);

  void _scheduleMeasurement() {
    if (_measurementScheduled || !mounted) return;
    _measurementScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      _measureLayers();
    });
  }

  RenderBox? _layerRenderBox(PaintLayer layer) {
    // keyInternalSize measures the package-owned visual layer. Keep the other
    // keys as fallbacks for frames where the internal key is not mounted yet.
    final candidates = <BuildContext?>[
      layer.keyInternalSize.currentContext,
      layer.repaintBoundaryKey.currentContext,
      layer.key.currentContext,
    ];

    for (final context in candidates) {
      final renderObject = context?.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize) {
        return renderObject;
      }
    }
    return null;
  }

  void _measureLayers() {
    final overlayObject = _overlayKey.currentContext?.findRenderObject();
    if (overlayObject is! RenderBox ||
        !overlayObject.attached ||
        !overlayObject.hasSize) {
      return;
    }

    final next = <String, _PaintLayerGeometry>{};
    for (final layer in _shapeLayers) {
      final box = _layerRenderBox(layer);
      if (box == null || box.size.isEmpty) continue;

      // Convert the package layer's transformed corners into this overlay's
      // coordinate system. This follows translation, scaling, rotation, safe
      // areas, and the editor canvas transform.
      final topLeft = overlayObject.globalToLocal(
        box.localToGlobal(Offset.zero),
      );
      final topRight = overlayObject.globalToLocal(
        box.localToGlobal(Offset(box.size.width, 0)),
      );
      final bottomLeft = overlayObject.globalToLocal(
        box.localToGlobal(Offset(0, box.size.height)),
      );
      final bottomRight = overlayObject.globalToLocal(
        box.localToGlobal(Offset(box.size.width, box.size.height)),
      );

      final corners = <Offset>[topLeft, topRight, bottomLeft, bottomRight];
      if (corners.any((point) => !point.isFinite)) continue;

      final horizontalVector = topRight - topLeft;
      final verticalVector = bottomLeft - topLeft;
      final visualWidth = horizontalVector.distance;
      final visualHeight = verticalVector.distance;
      if (!visualWidth.isFinite ||
          !visualHeight.isFinite ||
          visualWidth <= 0 ||
          visualHeight <= 0) {
        continue;
      }

      final scale = box.size.width <= 0 ? 1.0 : visualWidth / box.size.width;
      final center = Offset(
        corners.map((point) => point.dx).reduce((a, b) => a + b) / 4,
        corners.map((point) => point.dy).reduce((a, b) => a + b) / 4,
      );

      next[layer.id] = _PaintLayerGeometry(
        center: center,
        size: Size(visualWidth, visualHeight),
        rotation: math.atan2(horizontalVector.dy, horizontalVector.dx),
        screenScale: scale.isFinite && scale > 0 ? scale : 1,
      );
    }

    final selected = widget.selectedLayer.value;
    if (selected != null &&
        !_shapeLayers.any((layer) => layer.id == selected.id)) {
      widget.selectedLayer.value = null;
    }

    if (_sameGeometry(_geometry, next)) return;
    setState(() => _geometry = next);
  }

  bool _sameGeometry(
    Map<String, _PaintLayerGeometry> first,
    Map<String, _PaintLayerGeometry> second,
  ) {
    if (first.length != second.length) return false;
    for (final entry in first.entries) {
      final other = second[entry.key];
      if (other == null) return false;
      final value = entry.value;
      if ((value.center.dx - other.center.dx).abs() > 0.2 ||
          (value.center.dy - other.center.dy).abs() > 0.2 ||
          (value.size.width - other.size.width).abs() > 0.2 ||
          (value.size.height - other.size.height).abs() > 0.2 ||
          (value.rotation - other.rotation).abs() > 0.002 ||
          (value.screenScale - other.screenScale).abs() > 0.002) {
        return false;
      }
    }
    return true;
  }

  void _select(PaintLayer layer) {
    if (widget.selectedLayer.value?.id == layer.id) return;
    unawaited(HapticFeedback.selectionClick());
    widget.selectedLayer.value = layer;
  }

  void _deselect() {
    if (widget.selectedLayer.value == null) return;
    unawaited(HapticFeedback.selectionClick());
    widget.selectedLayer.value = null;
  }

  void _notifyLayerChanged() {
    widget.editor.setState(() {});
    widget.editor.rebuildController.add(null);
    _scheduleMeasurement();
  }

  void _onScaleStart(
    PaintLayer layer,
    _PaintLayerGeometry geometry,
    ScaleStartDetails details,
  ) {
    _select(layer);
    _gestureLayer = layer;
    _gestureStartScale = layer.scale;
    _gestureStartRotation = layer.rotation;
    _gestureScreenScale = geometry.screenScale <= 0 ? 1 : geometry.screenScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final layer = _gestureLayer;
    if (layer == null) return;

    final translatedDelta = details.focalPointDelta / _gestureScreenScale;
    layer.offset += translatedDelta;
    layer.scale =
        (_gestureStartScale * details.scale).clamp(0.25, 8.0).toDouble();
    layer.rotation = _gestureStartRotation + details.rotation;

    _notifyLayerChanged();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureLayer = null;
    _scheduleMeasurement();
  }

  double _normaliseAngle(double angle) {
    while (angle > math.pi) {
      angle -= math.pi * 2;
    }
    while (angle < -math.pi) {
      angle += math.pi * 2;
    }
    return angle;
  }

  Offset _handlePoint(_PaintLayerGeometry geometry, Offset normalizedPosition) {
    final halfWidth = math.max(0.0, geometry.size.width / 2 - _handleInset);
    final halfHeight = math.max(0.0, geometry.size.height / 2 - _handleInset);

    final local = Offset(
      normalizedPosition.dx * halfWidth,
      normalizedPosition.dy * halfHeight,
    );
    final cosine = math.cos(geometry.rotation);
    final sine = math.sin(geometry.rotation);

    return geometry.center +
        Offset(
          local.dx * cosine - local.dy * sine,
          local.dx * sine + local.dy * cosine,
        );
  }

  List<_PaintHandleSpec> _handleSpecsFor(PaintLayer layer) {
    switch (layer.item.mode) {
      case PaintMode.rect:
        // Four corners plus four edge midpoints.
        return const [
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, -1),
            label: 'Resize and rotate from top left',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(0, -1),
            label: 'Resize and rotate from top',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, -1),
            label: 'Resize and rotate from top right',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, 0),
            label: 'Resize and rotate from left',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, 0),
            label: 'Resize and rotate from right',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, 1),
            label: 'Resize and rotate from bottom left',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(0, 1),
            label: 'Resize and rotate from bottom',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, 1),
            label: 'Resize and rotate from bottom right',
          ),
        ];
      case PaintMode.circle:
        // Four points touch the circle at its cardinal directions. The four
        // corner points sit on the surrounding square bounds, matching the
        // familiar mobile-editor treatment requested for circles.
        return const [
          _PaintHandleSpec(
            normalizedPosition: Offset(0, -1),
            label: 'Resize and rotate circle from top',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, 0),
            label: 'Resize and rotate circle from left',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, 0),
            label: 'Resize and rotate circle from right',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(0, 1),
            label: 'Resize and rotate circle from bottom',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, -1),
            label: 'Resize and rotate circle from top left',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, -1),
            label: 'Resize and rotate circle from top right',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, 1),
            label: 'Resize and rotate circle from bottom left',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, 1),
            label: 'Resize and rotate circle from bottom right',
          ),
        ];
      case PaintMode.polygon:
        // The inserted polygon is a triangle: three vertex points and three
        // midpoint controls positioned on its edges.
        return const [
          _PaintHandleSpec(
            normalizedPosition: Offset(0, -1),
            label: 'Resize and rotate triangle from top vertex',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, 1),
            label: 'Resize and rotate triangle from bottom left vertex',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, 1),
            label: 'Resize and rotate triangle from bottom right vertex',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(-0.5, 0),
            label: 'Resize and rotate triangle from left edge',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(0.5, 0),
            label: 'Resize and rotate triangle from right edge',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(0, 1),
            label: 'Resize and rotate triangle from bottom edge',
          ),
        ];
      case PaintMode.arrow:
        // Telegram-style compact arrow editing: start, centre and end points.
        // The centre point moves the arrow; either endpoint changes its length
        // and rotation in one drag.
        return const [
          _PaintHandleSpec(
            normalizedPosition: Offset(-1, 0),
            label: 'Resize and rotate arrow from start',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(0, 0),
            role: _PaintHandleRole.move,
            label: 'Move arrow',
          ),
          _PaintHandleSpec(
            normalizedPosition: Offset(1, 0),
            label: 'Resize and rotate arrow from end',
          ),
        ];
      default:
        return const [];
    }
  }

  void _onHandlePanStart(
    PaintLayer layer,
    _PaintLayerGeometry geometry,
    _PaintHandleSpec handle,
    Offset handlePoint,
    DragStartDetails details,
  ) {
    _select(layer);
    final overlayBox = _overlayKey.currentContext?.findRenderObject();
    if (overlayBox is! RenderBox) return;

    _handleLayer = layer;
    _activeHandleRole = handle.role;
    _handleScreenScale = geometry.screenScale <= 0 ? 1 : geometry.screenScale;

    if (handle.role == _PaintHandleRole.move) return;

    _handleStartScale = layer.scale;
    _handleStartRotation = layer.rotation;
    _handleCenterGlobal = overlayBox.localToGlobal(geometry.center);

    final handleGlobal = overlayBox.localToGlobal(handlePoint);
    _handlePointerOffsetGlobal = details.globalPosition - handleGlobal;
    final startVector = handleGlobal - _handleCenterGlobal;
    _handleStartDistance = math.max(1.0, startVector.distance);
    _handleStartAngle = math.atan2(startVector.dy, startVector.dx);
  }

  void _onHandlePanUpdate(DragUpdateDetails details) {
    final layer = _handleLayer;
    final role = _activeHandleRole;
    if (layer == null || role == null) return;

    if (role == _PaintHandleRole.move) {
      layer.offset += details.delta / _handleScreenScale;
      _notifyLayerChanged();
      return;
    }

    final handleGlobal = details.globalPosition - _handlePointerOffsetGlobal;
    final currentVector = handleGlobal - _handleCenterGlobal;
    final currentDistance = math.max(1.0, currentVector.distance);
    final currentAngle = math.atan2(currentVector.dy, currentVector.dx);

    layer.scale =
        (_handleStartScale * currentDistance / _handleStartDistance)
            .clamp(0.25, 8.0)
            .toDouble();
    layer.rotation =
        _handleStartRotation +
        _normaliseAngle(currentAngle - _handleStartAngle);

    _notifyLayerChanged();
  }

  void _onHandlePanEnd([DragEndDetails? details]) {
    _handleLayer = null;
    _activeHandleRole = null;
    _scheduleMeasurement();
  }

  Widget _positionedLayerBox({
    required _PaintLayerGeometry geometry,
    required Widget child,
    double inflate = 0,
  }) {
    final width = math.max(1.0, geometry.size.width + inflate * 2);
    final height = math.max(1.0, geometry.size.height + inflate * 2);

    return Positioned(
      left: geometry.center.dx - width / 2,
      top: geometry.center.dy - height / 2,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: geometry.rotation,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _paintControlPoint(
    PaintLayer layer,
    _PaintLayerGeometry geometry,
    _PaintHandleSpec handle,
  ) {
    final point = _handlePoint(geometry, handle.normalizedPosition);

    return Positioned(
      left: point.dx - _handleTouchSize / 2,
      top: point.dy - _handleTouchSize / 2,
      width: _handleTouchSize,
      height: _handleTouchSize,
      child: Semantics(
        button: true,
        label: handle.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart:
              (details) =>
                  _onHandlePanStart(layer, geometry, handle, point, details),
          onPanUpdate: _onHandlePanUpdate,
          onPanEnd: _onHandlePanEnd,
          onPanCancel: _onHandlePanEnd,
          child: Center(
            child: Container(
              width: _handleVisualSize,
              height: _handleVisualSize,
              decoration: BoxDecoration(
                color: WrytteColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF7FAFF), width: 0.9),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    final layers = _shapeLayers;

    return KeyedSubtree(
      key: _overlayKey,
      child: ValueListenableBuilder<PaintLayer?>(
        valueListenable: widget.selectedLayer,
        builder: (context, selectedLayer, child) {
          final children = <Widget>[];

          // A selected shape is cleared only when the user taps empty canvas.
          // This sits behind every shape hit target, so tapping a shape selects
          // or manipulates it instead of triggering deselection.
          if (selectedLayer != null) {
            children.add(
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _deselect,
                  child: const SizedBox.expand(),
                ),
              ),
            );
          }

          for (final layer in layers) {
            final geometry = _geometry[layer.id];
            if (geometry == null) continue;

            final isSelected = selectedLayer?.id == layer.id;

            // The invisible touch target is slightly larger than the real
            // shape. No blue rectangle is painted around the object; selection
            // is communicated only by the shape-specific blue control points.
            children.add(
              _positionedLayerBox(
                geometry: geometry,
                inflate: 10,
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Editable drawing shape',
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _select(layer),
                    onScaleStart:
                        (details) => _onScaleStart(layer, geometry, details),
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );

            if (isSelected) {
              for (final handle in _handleSpecsFor(layer)) {
                children.add(_paintControlPoint(layer, geometry, handle));
              }
            }
          }

          return Stack(clipBehavior: Clip.none, children: children);
        },
      ),
    );
  }
}

/// Builds a true square for the custom square shape option.
/// The drag direction is preserved while width and height stay equal.
class _SquarePathBuilder extends PathBuilderBase {
  _SquarePathBuilder({
    required PaintedModel item,
    required PaintEditorConfigs paintEditorConfigs,
    required double scale,
  }) : super(item: item, paintEditorConfigs: paintEditorConfigs, scale: scale);

  @override
  Path build() {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final side = math.min(dx.abs(), dy.abs());
    final squareEnd = Offset(
      start.dx + (dx < 0 ? -side : side),
      start.dy + (dy < 0 ? -side : side),
    );

    final rect = Rect.fromPoints(start, squareEnd);
    path
      ..reset()
      ..addRect(rect);

    return path;
  }

  @override
  bool hitTest(Offset position) => hitTestFillableObject(position);
}

/// Builds a normal drag-to-size triangle for `PaintMode.custom2`.
class _TrianglePathBuilder extends PathBuilderBase {
  _TrianglePathBuilder({
    required PaintedModel item,
    required PaintEditorConfigs paintEditorConfigs,
    required double scale,
  }) : super(item: item, paintEditorConfigs: paintEditorConfigs, scale: scale);

  @override
  Path build() {
    final left = math.min(start.dx, end.dx);
    final right = math.max(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final bottom = math.max(start.dy, end.dy);
    final centerX = (left + right) / 2;

    path
      ..reset()
      ..moveTo(centerX, top)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();

    return path;
  }

  @override
  bool hitTest(Offset position) => hitTestFillableObject(position);
}

class _AlignedPaintColorPickerOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final double top;
  final double pickerFootprintWidth;
  final double horizontalOffset;
  final Widget child;

  const _AlignedPaintColorPickerOverlay({
    required this.targetKey,
    required this.top,
    required this.pickerFootprintWidth,
    this.horizontalOffset = 0,
    required this.child,
  });

  @override
  State<_AlignedPaintColorPickerOverlay> createState() =>
      _AlignedPaintColorPickerOverlayState();
}

class _AlignedPaintColorPickerOverlayState
    extends State<_AlignedPaintColorPickerOverlay>
    with WidgetsBindingObserver {
  final GlobalKey _overlayKey = GlobalKey();

  double? _resolvedLeft;
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _AlignedPaintColorPickerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.pickerFootprintWidth != widget.pickerFootprintWidth ||
        oldWidget.horizontalOffset != widget.horizontalOffset) {
      _resolvedLeft = null;
      _scheduleMeasurement();
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final targetContext = widget.targetKey.currentContext;
    final overlayContext = _overlayKey.currentContext;

    final targetRenderObject = targetContext?.findRenderObject();
    final overlayRenderObject = overlayContext?.findRenderObject();

    if (targetRenderObject is! RenderBox ||
        overlayRenderObject is! RenderBox ||
        !targetRenderObject.attached ||
        !overlayRenderObject.attached ||
        !targetRenderObject.hasSize ||
        !overlayRenderObject.hasSize) {
      _scheduleMeasurement();
      return;
    }

    // Find the selected-color circle's center in global screen coordinates,
    // then convert that point into this body overlay's local coordinates.
    final targetCenterGlobal = targetRenderObject.localToGlobal(
      targetRenderObject.size.center(Offset.zero),
    );
    final targetCenterLocal = overlayRenderObject.globalToLocal(
      targetCenterGlobal,
    );

    if (!targetCenterLocal.dx.isFinite || overlayRenderObject.size.width <= 0) {
      return;
    }

    final maximumLeft = math.max(
      0.0,
      overlayRenderObject.size.width - widget.pickerFootprintWidth,
    );

    final resolvedLeft =
        (targetCenterLocal.dx +
                widget.horizontalOffset -
                widget.pickerFootprintWidth / 2)
            .clamp(0.0, maximumLeft)
            .toDouble();

    if (_resolvedLeft != null && (_resolvedLeft! - resolvedLeft).abs() < 0.01) {
      return;
    }

    setState(() => _resolvedLeft = resolvedLeft);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Recalculate after layout so changes to orientation, safe-area insets, or
    // Pro Image Editor's internal body bounds cannot leave the picker offset.
    _scheduleMeasurement();

    return SizedBox.expand(
      key: _overlayKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_resolvedLeft != null)
            Positioned(
              top: widget.top,
              left: _resolvedLeft!,
              width: widget.pickerFootprintWidth,
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

enum _VideoTrimDragTarget { none, left, right }

/// Telegram-inspired filmstrip range selector.
///
/// The drag math is intentionally based on the pointer's global position
/// converted into one fixed timeline RenderBox. This avoids the common handle
/// drift/jump bug caused by calculating movement inside a handle widget that is
/// itself being repositioned on every frame.
class TelegramVideoTrimTimeline extends StatefulWidget {
  final Duration duration;
  final TrimDurationSpan span;
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
  final ValueChanged<TrimDurationSpan> onChanged;
  final ValueChanged<TrimDurationSpan> onChangeEnd;
  final ValueChanged<Duration> onSeek;

  const TelegramVideoTrimTimeline({
    super.key,
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

  @override
  State<TelegramVideoTrimTimeline> createState() =>
      TelegramVideoTrimTimelineState();
}

class TelegramVideoTrimTimelineState extends State<TelegramVideoTrimTimeline> {
  static const double _height = 48;
  static const double _trackInset = 7;
  static const double _trackTop = 4;
  static const double _trackHeight = 40;
  static const double _trackRadius = 11;
  static const double _handleWidth = 22;
  static const double _railThickness = 2;
  static const double _railJoinOverlap = 1;
  static const double _handleTouchRadius = 25;
  static const int _minimumTrimMilliseconds = 100;

  final GlobalKey _timelineKey = GlobalKey();

  late TrimDurationSpan _displaySpan;
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
  void didUpdateWidget(covariant TelegramVideoTrimTimeline oldWidget) {
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

    late TrimDurationSpan nextSpan;
    late Duration previewPosition;

    if (_dragTarget == _VideoTrimDragTarget.left) {
      final nextStart =
          math
              .min(pointerFraction, math.max(0.0, endFraction - minFraction))
              .toDouble();
      previewPosition = _durationForFraction(nextStart);
      nextSpan = TrimDurationSpan(
        start: previewPosition,
        end: _displaySpan.end,
      );
    } else {
      final nextEnd =
          math
              .max(pointerFraction, math.min(1.0, startFraction + minFraction))
              .toDouble();
      previewPosition = _durationForFraction(nextEnd);
      nextSpan = TrimDurationSpan(
        start: _displaySpan.start,
        end: previewPosition,
      );
    }

    if (nextSpan.start == _displaySpan.start &&
        nextSpan.end == _displaySpan.end) {
      return;
    }

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
    const cadence = Duration(milliseconds: 40);
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
          final trackWidth =
              math.max(1.0, width - (_trackInset * 2)).toDouble();
          final startFraction = _fraction(_displaySpan.start);
          final endFraction = _fraction(_displaySpan.end);
          final playheadFraction =
              _fraction(
                widget.playhead,
              ).clamp(startFraction, endFraction).toDouble();

          final startX = _trackInset + (trackWidth * startFraction);
          final endX = _trackInset + (trackWidth * endFraction);
          final playheadX = _trackInset + (trackWidth * playheadFraction);
          final selectedWidth = math.max(0.0, endX - startX).toDouble();

          // The range boundary (startX/endX) runs through the CENTER of each
          // Endpoint handle. The horizontal rails must therefore join the
          // handles at their inner faces, not at their outside edges:
          //
          // left inner face  = startX + handleWidth / 2
          // right inner face = endX   - handleWidth / 2
          //
          // Move each rail 1dp into the handle to guarantee a seamless join
          // even when startX/endX land on fractional physical pixels.
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_trackRadius),
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
                                            alpha: index == 8 ? 0 : 0.055,
                                          ),
                                          width: 0.7,
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
                                      transform:
                                          Matrix4.identity()..scale(
                                            widget.thumbnailMirrorX
                                                ? -1.0
                                                : 1.0,
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
                              color: Colors.black.withValues(alpha: 0.56),
                            ),
                          ),
                        if (endX < width - _trackInset)
                          Positioned(
                            left: endX - _trackInset,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.56),
                            ),
                          ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  _trackRadius,
                                ),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.34),
                                  width: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Joined range frame. The rails terminate inside the flat
                // faces of the handles, so the outer rounded ends stay clean.
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
                          color: widget.playheadColor.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
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
      // The handles now share the exact same top/bottom coordinates as the
      // filmstrip. This makes the horizontal white rails meet the vertical
      // handles as one continuous frame instead of sitting 2dp inside them.
      top: _trackTop,
      width: _handleWidth,
      height: _trackHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.handleColor,
            // Only the OUTER corners are rounded. The inner face stays flat so
            // the top/bottom rails can enter the handle cleanly with no notch.
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(left ? 20 : 0),
              bottomLeft: Radius.circular(left ? 20 : 0),
              topRight: Radius.circular(left ? 0 : 20),
              bottomRight: Radius.circular(left ? 0 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.30 : 0.22),
                blurRadius: active ? 3 : 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 4,
              height: 24,
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

/// Telegram-style fine-rotation wheel for the crop editor.
///
/// The wheel only owns gesture/display state. The real transform, crop-bound
/// fitting, history and export remain owned by [CropRotateEditorState].
class _TelegramCropRotationDial extends StatefulWidget {
  final double valueDegrees;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _TelegramCropRotationDial({
    required this.valueDegrees,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_TelegramCropRotationDial> createState() =>
      _TelegramCropRotationDialState();
}

class _TelegramCropRotationDialState extends State<_TelegramCropRotationDial> {
  static const double _minimumAngle = -80;
  static const double _maximumAngle = 80;
  static const double _pixelsPerDegree = 4.0;
  static const double _hapticStep = 2.5;

  late double _displayDegrees = _clamp(widget.valueDegrees);
  double _dragStartX = 0;
  double _dragStartDegrees = 0;
  int _lastHapticIndex = 0;
  bool _dragging = false;
  bool _dragChanged = false;

  static double _clamp(double value) =>
      value.clamp(_minimumAngle, _maximumAngle).toDouble();

  @override
  void didUpdateWidget(covariant _TelegramCropRotationDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragging) return;

    final nextValue = _clamp(widget.valueDegrees);
    if ((nextValue - _displayDegrees).abs() > 0.001) {
      setState(() => _displayDegrees = nextValue);
    }
  }

  void _startDrag(DragStartDetails details) {
    _dragging = true;
    _dragStartX = details.localPosition.dx;
    _dragStartDegrees = _displayDegrees;
    _lastHapticIndex = (_displayDegrees / _hapticStep).round();
    _dragChanged = false;
  }

  void _updateDrag(DragUpdateDetails details) {
    var nextValue = _clamp(
      _dragStartDegrees +
          (_dragStartX - details.localPosition.dx) / _pixelsPerDegree,
    );

    // Telegram's wheel settles precisely at level without making the centre
    // feel sticky during a normal drag.
    if (nextValue.abs() < 0.12) nextValue = 0;
    if ((nextValue - _displayDegrees).abs() < 0.001) return;

    final hapticIndex = (nextValue / _hapticStep).round();
    if (hapticIndex != _lastHapticIndex) {
      _lastHapticIndex = hapticIndex;
      unawaited(HapticFeedback.selectionClick());
    }

    _dragChanged = true;
    setState(() => _displayDegrees = nextValue);
    widget.onChanged(nextValue);
  }

  void _finishDrag() {
    if (!_dragging) return;
    _dragging = false;
    if (_dragChanged) widget.onChangeEnd(_displayDegrees);
  }

  void _nudge(double delta) {
    final nextValue = _clamp(_displayDegrees + delta);
    if (nextValue == _displayDegrees) return;
    setState(() => _displayDegrees = nextValue);
    unawaited(HapticFeedback.selectionClick());
    widget.onChanged(nextValue);
    widget.onChangeEnd(nextValue);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      label: 'Fine crop rotation',
      value: '${_displayDegrees.toStringAsFixed(1)} degrees',
      increasedValue:
          '${_clamp(_displayDegrees + 1).toStringAsFixed(1)} degrees',
      decreasedValue:
          '${_clamp(_displayDegrees - 1).toStringAsFixed(1)} degrees',
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _startDrag,
        onHorizontalDragUpdate: _updateDrag,
        onHorizontalDragEnd: (_) => _finishDrag(),
        onHorizontalDragCancel: _finishDrag,
        child: SizedBox(
          height: 68,
          width: double.infinity,
          child: CustomPaint(
            painter: _TelegramCropRotationDialPainter(
              valueDegrees: _displayDegrees,
            ),
          ),
        ),
      ),
    );
  }
}

class _TelegramCropRotationDialPainter extends CustomPainter {
  final double valueDegrees;

  const _TelegramCropRotationDialPainter({required this.valueDegrees});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const horizontalInset = 3.0;
    const pixelsPerDegree = _TelegramCropRotationDialState._pixelsPerDegree;
    final centerX = size.width / 2;
    final usableHalfWidth = math.max(1.0, centerX - horizontalInset);
    final wheelRadius = usableHalfWidth * 2.0;
    final wheelCenterY = 46.0 - wheelRadius;

    final tickPaint =
        Paint()
          ..color = WrytteColors.textSecondary
          ..isAntiAlias = true;
    final activePaint =
        Paint()
          ..color = WrytteColors.textPrimary
          ..isAntiAlias = true;

    // Five markers make each ten-degree interval: four small two-degree dots,
    // followed by one larger labeled ten-degree marker. The ±80° endpoints are
    // intentionally large but unlabeled, matching the Telegram wheel cadence.
    for (var degree = -80; degree <= 80; degree += 2) {
      final x = centerX + (degree - valueDegrees) * pixelsPerDegree;
      if (x < horizontalInset || x > size.width - horizontalInset) continue;

      final normalized =
          ((x - centerX).abs() / usableHalfWidth).clamp(0.0, 1.0).toDouble();
      final distanceX = x - centerX;
      final circleHeight = math.sqrt(
        math.max(0.0, wheelRadius * wheelRadius - distanceX * distanceX),
      );
      final arcY = wheelCenterY + circleHeight;
      final major = degree % 10 == 0;
      final terminal = degree.abs() == 80;
      final distanceFromPointer = (degree - valueDegrees).abs();

      tickPaint.color = WrytteColors.textPrimary;

      final selected = distanceFromPointer < 0.55;
      final radius = selected ? 2.35 : ((major || terminal) ? 1.9 : 1.35);
      canvas.drawCircle(
        Offset(x, arcY),
        radius,
        selected ? activePaint : tickPaint,
      );

      if (major && !terminal && normalized < 0.86) {
        final tangentAngle = math.atan2(-distanceX, circleHeight);
        final labelPainter = TextPainter(
          text: TextSpan(
            text: '$degree',
            style: const TextStyle(
              color: WrytteColors.textPrimary,
              fontFamily: WrytteTypography.primaryFontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(x, arcY - 15);
        canvas.rotate(tangentAngle);
        labelPainter.paint(
          canvas,
          Offset(-labelPainter.width / 2, -labelPainter.height / 2),
        );
        canvas.restore();
      }
    }

    // Fixed upward-facing pointer: the scale moves, this marker does not.
    final pointerPath =
        Path()
          ..moveTo(centerX, size.height - 14)
          ..lineTo(centerX - 4.5, size.height - 6)
          ..lineTo(centerX + 4.5, size.height - 6)
          ..close();
    canvas.drawPath(pointerPath, activePaint);
  }

  @override
  bool shouldRepaint(covariant _TelegramCropRotationDialPainter oldDelegate) {
    return (oldDelegate.valueDegrees - valueDegrees).abs() > 0.001;
  }
}

class _CropFrameOverlay extends StatefulWidget {
  final CropRotateEditorState editor;
  final Stream<void> rebuildStream;
  final Widget? centerChild;
  final Widget? belowChild;

  const _CropFrameOverlay({
    required this.editor,
    required this.rebuildStream,
    this.centerChild,
    this.belowChild,
  });

  @override
  State<_CropFrameOverlay> createState() => _CropFrameOverlayState();
}

class _CropFrameOverlayState extends State<_CropFrameOverlay>
    with WidgetsBindingObserver {
  final GlobalKey _overlayKey = GlobalKey();

  StreamSubscription<void>? _rebuildSubscription;
  Rect? _resolvedCropRect;
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToEditor();
    _scheduleMeasurement();
  }

  @override
  void didUpdateWidget(covariant _CropFrameOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.rebuildStream != widget.rebuildStream) {
      _listenToEditor();
    }

    _scheduleMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasurement();
  }

  @override
  void didChangeMetrics() {
    _scheduleMeasurement();
  }

  void _listenToEditor() {
    _rebuildSubscription?.cancel();
    _rebuildSubscription = widget.rebuildStream.listen((_) {
      _scheduleMeasurement();
    });
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      _measureCropRect();
    });
  }

  void _measureCropRect() {
    final cropPainter = widget.editor.cropPainter;
    final cropPainterContext = widget.editor.cropPainterKey.currentContext;
    final overlayContext = _overlayKey.currentContext;

    if (cropPainter == null ||
        cropPainterContext == null ||
        overlayContext == null) {
      _clearRect();
      return;
    }

    final cropRenderObject = cropPainterContext.findRenderObject();
    final overlayRenderObject = overlayContext.findRenderObject();

    if (cropRenderObject is! RenderBox ||
        overlayRenderObject is! RenderBox ||
        !cropRenderObject.attached ||
        !overlayRenderObject.attached ||
        !cropRenderObject.hasSize ||
        !overlayRenderObject.hasSize) {
      _clearRect();
      return;
    }

    // `cropPainter.cropRect` is local to Pro Image Editor's own CustomPaint.
    // Convert every corner from that box to this overlay's box. This includes
    // app-bar, SafeArea, padding and any package-internal layout translation.
    final sourceRect = cropPainter.cropRect;
    final convertedCorners = <Offset>[
          sourceRect.topLeft,
          sourceRect.topRight,
          sourceRect.bottomRight,
          sourceRect.bottomLeft,
        ]
        .map((point) {
          final globalPoint = cropRenderObject.localToGlobal(point);
          return overlayRenderObject.globalToLocal(globalPoint);
        })
        .toList(growable: false);

    if (convertedCorners.any((point) => !point.isFinite)) {
      _clearRect();
      return;
    }

    final resolvedRect = Rect.fromLTRB(
      convertedCorners.map((point) => point.dx).reduce(math.min),
      convertedCorners.map((point) => point.dy).reduce(math.min),
      convertedCorners.map((point) => point.dx).reduce(math.max),
      convertedCorners.map((point) => point.dy).reduce(math.max),
    );

    if (!resolvedRect.isFinite || resolvedRect.isEmpty) {
      _clearRect();
      return;
    }

    if (_resolvedCropRect == resolvedRect) return;
    setState(() => _resolvedCropRect = resolvedRect);
  }

  void _clearRect() {
    if (_resolvedCropRect == null || !mounted) return;
    setState(() => _resolvedCropRect = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rebuildSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-measure after this overlay receives its final size for the frame.
    _scheduleMeasurement();
    final cropRect = _resolvedCropRect;

    return SizedBox.expand(
      key: _overlayKey,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Border is display-only and must never steal crop gestures.
          IgnorePointer(
            child: CustomPaint(
              painter: _CropFrameBorderPainter(cropRect: cropRect),
            ),
          ),
          // Unlike the old full-screen body item, this control is attached to
          // the resolved crop rectangle itself. The crop editor therefore cannot
          // paint its video/crop surface over the play button.
          if (widget.centerChild != null &&
              cropRect != null &&
              cropRect.isFinite &&
              !cropRect.isEmpty)
            Positioned(
              left: cropRect.left,
              top: cropRect.top,
              width: cropRect.width,
              height: cropRect.height,
              child: Center(child: widget.centerChild!),
            ),
          if (widget.belowChild != null &&
              cropRect != null &&
              cropRect.isFinite &&
              !cropRect.isEmpty)
            Positioned(
              left: cropRect.left + 20,
              top: cropRect.bottom,
              width: math.max(1.0, cropRect.width - 40).toDouble(),
              height: 74,
              child: ClipRect(child: widget.belowChild!),
            ),
        ],
      ),
    );
  }
}

class _TelegramTextSizeSlider extends StatefulWidget {
  final ValueListenable<double> valueListenable;
  final double min;
  final double max;
  final double height;
  final ValueChanged<double> onChanged;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _TelegramTextSizeSlider({
    required this.valueListenable,
    required this.min,
    required this.max,
    required this.height,
    required this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<_TelegramTextSizeSlider> createState() =>
      _TelegramTextSizeSliderState();
}

class _TelegramTextSizeSliderState extends State<_TelegramTextSizeSlider> {
  // The screenshot uses a large invisible gesture area, while the visible
  // tapered rail is partly outside the screen when it is not being touched.
  static const double _touchWidth = 58;
  static const double _railTopWidth = 33;
  static const double _railBottomWidth = 5.5;
  static const double _railVerticalInset = 2;
  static const double _handleDiameter = 35;

  // Active reference: the rail is around 7 px from the left.
  // Idle reference: it is translated about 18 px back outside the screen.
  static const double _activeVisualLeft = 7;
  static const double _idleVisualLeft = -15;

  bool _active = false;
  double? _dragStartLocalY;
  double? _dragStartValue;

  double get _railHeight =>
      math.max(1, widget.height - (_railVerticalInset * 2));

  double get _handleTravel => math.max(1, _railHeight - _handleDiameter);

  double _normalized(double value) {
    if (widget.max <= widget.min) return 0;
    return ((value - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _valueFromLocalY(double localY) {
    final railLocalY =
        (localY - _railVerticalInset - (_handleDiameter / 2))
            .clamp(0.0, _handleTravel)
            .toDouble();

    // Top means the largest text; bottom means the smallest text.
    final normalized = 1 - (railLocalY / _handleTravel);
    return widget.min + ((widget.max - widget.min) * normalized);
  }

  void _activate() {
    if (_active) return;
    setState(() => _active = true);
    widget.onDragStart?.call();
  }

  void _deactivate() {
    if (!_active) return;

    setState(() {
      _active = false;
      _dragStartLocalY = null;
      _dragStartValue = null;
    });
    widget.onDragEnd?.call();
  }

  void _handleTapDown(TapDownDetails details) {
    _activate();
    widget.onChanged(_valueFromLocalY(details.localPosition.dy));
  }

  void _handleDragStart(DragStartDetails details) {
    _activate();
    _dragStartLocalY = details.localPosition.dy;
    _dragStartValue = widget.valueListenable.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final startY = _dragStartLocalY;
    final startValue = _dragStartValue;
    if (startY == null || startValue == null) return;

    // Relative drag avoids the handle jumping when the user's finger lands
    // above or below the white circle.
    final deltaY = details.localPosition.dy - startY;
    final valueDelta = -(deltaY / _handleTravel) * (widget.max - widget.min);

    widget.onChanged(
      (startValue + valueDelta).clamp(widget.min, widget.max).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Text size',
      slider: true,
      child: SizedBox(
        width: _touchWidth,
        height: widget.height,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: _handleTapDown,
          onTapUp: (_) => _deactivate(),
          onTapCancel: _deactivate,
          onVerticalDragStart: _handleDragStart,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: (_) => _deactivate(),
          onVerticalDragCancel: _deactivate,
          child: ValueListenableBuilder<double>(
            valueListenable: widget.valueListenable,
            builder: (context, value, child) {
              final normalized = _normalized(value);
              final handleTop =
                  _railVerticalInset + ((1 - normalized) * _handleTravel);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    left: _active ? _activeVisualLeft : _idleVisualLeft,
                    top: _railVerticalInset,
                    width: _railTopWidth,
                    height: _railHeight,
                    child: ClipPath(
                      clipper: const _TelegramTextSizeRailClipper(
                        topWidth: _railTopWidth,
                        bottomWidth: _railBottomWidth,
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: CustomPaint(
                          foregroundPainter:
                              const _TelegramTextSizeRailGlassPainter(
                                topWidth: _railTopWidth,
                                bottomWidth: _railBottomWidth,
                              ),
                          child: const DecoratedBox(
                            // Borderless translucent surface. The ClipPath keeps
                            // the exact tapered shape while BackdropFilter keeps
                            // the glass effect.
                            decoration: BoxDecoration(color: Color(0x182D3035)),
                            child: SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    left:
                        (_active ? _activeVisualLeft : _idleVisualLeft) -
                        ((_handleDiameter - _railTopWidth) / 2),
                    top: handleTop,
                    width: _handleDiameter,
                    height: _handleDiameter,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 5,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Path _telegramTextSizeRailPath({
  required Size size,
  required double topWidth,
  required double bottomWidth,
}) {
  final centerX = size.width / 2;
  final topRadius = topWidth / 2;
  final bottomRadius = bottomWidth / 2;

  final topCircle = Rect.fromCircle(
    center: Offset(centerX, topRadius),
    radius: topRadius,
  );
  final bottomCircle = Rect.fromCircle(
    center: Offset(centerX, size.height - bottomRadius),
    radius: bottomRadius,
  );

  final path =
      Path()
        ..moveTo(centerX - topRadius, topRadius)
        ..arcTo(topCircle, math.pi, math.pi, false)
        ..cubicTo(
          centerX + topRadius,
          size.height * 0.28,
          centerX + bottomRadius,
          size.height * 0.80,
          centerX + bottomRadius,
          size.height - bottomRadius,
        )
        // Exact lower semicircle for a clean, fully rounded tail.
        ..arcTo(bottomCircle, 0, math.pi, false)
        ..cubicTo(
          centerX - bottomRadius,
          size.height * 0.80,
          centerX - topRadius,
          size.height * 0.28,
          centerX - topRadius,
          topRadius,
        )
        ..close();

  return path;
}

class _TelegramTextSizeRailClipper extends CustomClipper<Path> {
  final double topWidth;
  final double bottomWidth;

  const _TelegramTextSizeRailClipper({
    required this.topWidth,
    required this.bottomWidth,
  });

  @override
  Path getClip(Size size) {
    return _telegramTextSizeRailPath(
      size: size,
      topWidth: topWidth,
      bottomWidth: bottomWidth,
    );
  }

  @override
  bool shouldReclip(covariant _TelegramTextSizeRailClipper oldClipper) {
    return oldClipper.topWidth != topWidth ||
        oldClipper.bottomWidth != bottomWidth;
  }
}

class _TelegramTextSizeRailGlassPainter extends CustomPainter {
  final double topWidth;
  final double bottomWidth;

  const _TelegramTextSizeRailGlassPainter({
    required this.topWidth,
    required this.bottomWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _telegramTextSizeRailPath(
      size: size,
      topWidth: topWidth,
      bottomWidth: bottomWidth,
    );

    final fillPaint =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x4A34373D), Color(0x3524262B), Color(0x2A17191D)],
            stops: [0.0, 0.42, 1.0],
          ).createShader(Offset.zero & size);

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _TelegramTextSizeRailGlassPainter oldDelegate) {
    return oldDelegate.topWidth != topWidth ||
        oldDelegate.bottomWidth != bottomWidth;
  }
}

class _CropFrameBorderPainter extends CustomPainter {
  final Rect? cropRect;

  const _CropFrameBorderPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = cropRect;
    if (rect == null || rect.isEmpty || !rect.isFinite) return;

    final paint =
        Paint()
          ..color = const Color(0xE6FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter
          ..isAntiAlias = true;

    // Draw the exact four crop edges. Because `rect` was converted between the
    // two RenderBoxes, these lines share the same screen-space anchors as the
    // package's built-in corner handles.
    canvas.drawLine(rect.topLeft, rect.topRight, paint);
    canvas.drawLine(rect.topRight, rect.bottomRight, paint);
    canvas.drawLine(rect.bottomRight, rect.bottomLeft, paint);
    canvas.drawLine(rect.bottomLeft, rect.topLeft, paint);
  }

  @override
  bool shouldRepaint(covariant _CropFrameBorderPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
