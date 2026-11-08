part of '../composer/message_input.dart';

class _AlbumMenuReveal extends StatefulWidget {
  const _AlbumMenuReveal({
    super.key,
    required this.onDismissed,
    required this.child,
  });

  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<_AlbumMenuReveal> createState() => _AlbumMenuRevealState();
}

class _AlbumMenuRevealState extends State<_AlbumMenuReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
    reverseDuration: const Duration(milliseconds: 210),
  )..forward();
  bool _closing = false;

  Future<void> close() async {
    if (_closing || !mounted) return;
    setState(() => _closing = true);
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // Keep the established quick entrance, but give dismissal a symmetric
        // ease so it neither snaps at the start nor accelerates into the end.
        // Geometry is unchanged: the same reveal simply runs backwards.
        final curve = _closing ? Curves.easeInOutCubic : Curves.easeOutCubic;
        final progress = curve.transform(_controller.value);
        return Opacity(
          opacity: progress,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              widthFactor: progress,
              heightFactor: progress,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _PreparedAttachmentImage {
  const _PreparedAttachmentImage({
    required this.assetId,
    required this.file,
    required this.heroProvider,
    required this.pixelSize,
  });

  final String assetId;
  final File file;
  final ImageProvider<Object> heroProvider;
  final Size pixelSize;
}

class _TelegramAttachmentPanel extends StatefulWidget {
  final ValueChanged<_AttachmentSelection> onSelected;
  final Future<void> Function(_AttachmentSelection selection)? onCameraSelected;
  final String recipientLabel;
  final bool replacementMode;
  final String initialCaption;
  final bool initialAudioMode;
  final bool playlistMode;
  final bool profilePhotoMode;
  final bool initiallyExpanded;
  final Object? profilePhotoDestinationHeroTag;

  const _TelegramAttachmentPanel({
    super.key,
    required this.onSelected,
    this.onCameraSelected,
    required this.recipientLabel,
    this.replacementMode = false,
    this.initialCaption = '',
    this.initialAudioMode = false,
    this.playlistMode = false,
    this.profilePhotoMode = false,
    this.initiallyExpanded = false,
    this.profilePhotoDestinationHeroTag,
  });

  @override
  State<_TelegramAttachmentPanel> createState() =>
      _TelegramAttachmentPanelState();
}

class _AttachmentAlbumMetadata {
  const _AttachmentAlbumMetadata({required this.count, this.cover});

  final int count;
  final AssetEntity? cover;
}

class _TelegramAttachmentPanelState extends State<_TelegramAttachmentPanel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final List<_RecentAttachmentFile> _recentFiles =
      <_RecentAttachmentFile>[];
  static const double _mediaTileHeightFactor = 1.08;
  static const double _minimumSheetSize = 0.12;
  static const double _initialSheetSize = 0.68;
  static const double _maximumSheetSize = 0.94;
  static const double _dismissSheetSize = 0.42;
  static const int _assetPageSize = 60;
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();
  List<AssetPathEntity> _albums = <AssetPathEntity>[];
  final Map<String, Future<_AttachmentAlbumMetadata>> _albumMetadata =
      <String, Future<_AttachmentAlbumMetadata>>{};
  List<AssetEntity> _assets = <AssetEntity>[];
  static const int _maxSelectedMediaItems = 30;
  final List<AssetEntity> _selectedAssets = <AssetEntity>[];
  final List<_RecentAttachmentFile> _selectedFiles = <_RecentAttachmentFile>[];
  final Map<String, String> _editedAssetPaths = <String, String>{};
  final Map<String, String> _assetFilePaths = <String, String>{};
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _captionFocusNode = FocusNode();
  final TextEditingController _pollQuestionController = TextEditingController();
  final TextEditingController _pollDescriptionController =
      TextEditingController();
  final List<TextEditingController> _pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _pollAllowsMultipleAnswers = true;
  List<Contact> _deviceContacts = <Contact>[];
  final Set<Contact> _selectedContacts = <Contact>{};
  bool _loadingContacts = false;
  bool _contactsLoaded = false;
  bool _contactsAccessDenied = false;

  bool get _pollCanSend =>
      _pollQuestionController.text.trim().isNotEmpty &&
      _pollOptionControllers
          .take(_pollOptionControllers.length - 1)
          .any((controller) => controller.text.trim().isNotEmpty);
  AssetPathEntity? _selectedAlbum;
  bool _sendingSelection = false;
  String? _committedProfilePhotoAssetId;
  String? _committedProfilePhotoPath;
  bool _loadingMedia = true;
  bool _photoAccessDenied = false;
  bool _mediaLoadFailed = false;
  int _assetLoadGeneration = 0;
  int _selectedAttachmentCategory = 0;
  bool _fileGalleryMode = false;
  bool _fileAudioMode = false;
  List<AssetEntity> _audioAssets = <AssetEntity>[];
  final Map<String, String> _audioTitles = <String, String>{};
  final Map<String, String> _audioArtists = <String, String>{};
  final Map<String, String> _audioPaths = <String, String>{};
  final Map<String, int> _audioSizes = <String, int>{};
  final Map<String, int> _audioArtworkIds = <String, int>{};
  final Map<int, Future<Uint8List?>> _audioArtworkFutures =
      <int, Future<Uint8List?>>{};
  final OnAudioQuery _deviceAudioQuery = OnAudioQuery();
  final AudioPlayer _audioListPreviewPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _audioListStateSubscription;
  StreamSubscription<void>? _audioListCompleteSubscription;
  String? _playingAudioAssetId;
  PlayerState _audioListPlayerState = PlayerState.stopped;
  bool _deviceAudioLoaded = false;
  bool _loadingAudio = false;
  bool _audioAccessDenied = false;
  bool _audioLoadFailed = false;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  late final ValueNotifier<double> _sheetExpansionProgress;
  final ValueNotifier<double> _galleryScrollProgress = ValueNotifier(0);
  ScrollController? _galleryScrollController;
  bool _headerDragWasDownward = false;
  bool _isDismissingSheet = false;

  double get _startingSheetSize =>
      widget.initiallyExpanded ? _maximumSheetSize : _initialSheetSize;

  // Custom Recents/album popup so it can use the exact same real backdrop blur
  // and dark glass treatment as the attachment panel instead of Flutter's
  // opaque PopupMenuRoute.
  final LayerLink _albumSelectorLink = LayerLink();
  OverlayEntry? _albumMenuEntry;
  GlobalKey<_AlbumMenuRevealState>? _albumMenuRevealKey;
  Future<void>? _albumChoicesLoadInFlight;
  bool _loadingAlbumChoices = false;
  CameraController? _cameraPreviewController;
  bool _cameraPreviewStarting = false;
  bool _cameraPreviewRestartPending = false;
  bool _cameraPreviewAudioEnabled = false;
  bool _cameraRouteOpen = false;
  final GlobalKey _cameraTileKey = GlobalKey(
    debugLabel: 'attachment-camera-tile',
  );
  Completer<void>? _cameraPreviewAttempt;
  int _cameraPreviewGeneration = 0;
  // Required on legacy Android: without a sort column photo_manager 3.8.3
  // produces the invalid pagination clause `ORDER BY LIMIT ...`.
  PMFilter? _recentMediaFilter;
  static const ThumbnailOption _heroThumbnailOption = ThumbnailOption(
    size: ThumbnailSize.square(720),
    quality: 90,
  );
  final Map<String, _PreparedAttachmentImage> _preparedImages =
      <String, _PreparedAttachmentImage>{};
  final Map<String, Future<_PreparedAttachmentImage?>> _preparingImages =
      <String, Future<_PreparedAttachmentImage?>>{};
  final Set<String> _knownAssetIds = <String>{};
  bool _hasInitialAssetSnapshot = false;
  bool _mediaRefreshInFlight = false;
  late final ValueChanged<MethodCall> _mediaChangeCallback = (_) =>
      _requestMediaRefresh();

  WrytteAttachmentMetrics get _layout => WrytteAttachmentMetrics.of(context);

  @override
  void initState() {
    super.initState();
    // A camera-gallery shortcut starts at the maximum sheet extent, so its
    // header must also begin in the same blurred, dark-transparent state that
    // a manually expanded sheet reaches.
    _sheetExpansionProgress = ValueNotifier(
      widget.initiallyExpanded ? 1.0 : 0.0,
    );
    try {
      _recentMediaFilter = PMFilter.defaultValue();
    } on UnsupportedError {
      // photo_manager's custom date columns are mobile-only. Leaving the
      // filter unset keeps the panel renderable on desktop while the native
      // mobile implementations retain their explicit recents ordering.
      _recentMediaFilter = null;
    }
    if (widget.initialAudioMode) {
      _selectedAttachmentCategory = 1;
      _fileAudioMode = true;
    }
    _captionController.text = widget.initialCaption;
    _audioListStateSubscription = _audioListPreviewPlayer.onPlayerStateChanged
        .listen((state) {
          if (!mounted) return;
          setState(() => _audioListPlayerState = state);
        });
    _audioListCompleteSubscription = _audioListPreviewPlayer.onPlayerComplete
        .listen((_) {
          if (!mounted) return;
          setState(() {
            _audioListPlayerState = PlayerState.stopped;
            _playingAudioAssetId = null;
          });
        });
    WidgetsBinding.instance.addObserver(this);
    PhotoManager.addChangeCallback(_mediaChangeCallback);
    unawaited(PhotoManager.startChangeNotify());
    _sheetController.addListener(_syncSheetExpansionProgress);
    unawaited(_loadAlbums());
    if (widget.initialAudioMode) unawaited(_loadDeviceAudio());
    if (!widget.initialAudioMode) {
      // Render the gallery immediately, but only create the camera tile when
      // access was already granted. Opening Plus must not prompt for camera or
      // microphone access before the user chooses the camera.
      unawaited(_initialiseCameraPreview(requestIfNeeded: false));
    }
  }

  @override
  void dispose() {
    _hideAlbumMenu(immediately: true);
    WidgetsBinding.instance.removeObserver(this);
    PhotoManager.removeChangeCallback(_mediaChangeCallback);
    unawaited(PhotoManager.stopChangeNotify());
    _sheetController.removeListener(_syncSheetExpansionProgress);
    _galleryScrollController?.removeListener(_syncGalleryScrollProgress);
    _sheetController.dispose();
    _sheetExpansionProgress.dispose();
    _galleryScrollProgress.dispose();
    _preparingImages.clear();
    _preparedImages.clear();
    _captionController.dispose();
    _captionFocusNode.dispose();
    _pollQuestionController.dispose();
    _pollDescriptionController.dispose();
    for (final controller in _pollOptionControllers) {
      controller.dispose();
    }
    unawaited(_audioListStateSubscription?.cancel());
    unawaited(_audioListCompleteSubscription?.cancel());
    unawaited(_audioListPreviewPlayer.dispose());
    final cameraController = _cameraPreviewController;
    _cameraPreviewController = null;
    if (cameraController != null) {
      unawaited(cameraController.dispose());
    }
    _entranceController.dispose();
    super.dispose();
  }

  void _syncSheetExpansionProgress() {
    if (!_sheetController.isAttached) return;

    final size = _sheetController.size;

    // The DraggableScrollableSheet can be dragged to its minimum extent through
    // its own scroll controller. Because shouldCloseOnMinExtent is disabled, it
    // would otherwise remain at 12% height and leave the header peeking up from
    // the bottom of the screen. Reaching the minimum now dismisses the entire
    // attachment route instead.
    if (size <= _minimumSheetSize + 0.01) {
      _dismissAttachmentPanel();
      return;
    }

    final progress =
        ((size - _initialSheetSize) / (_maximumSheetSize - _initialSheetSize))
            .clamp(0.0, 1.0)
            .toDouble();
    if ((progress - _sheetExpansionProgress.value).abs() > 0.001) {
      _sheetExpansionProgress.value = progress;
    }
  }

  void _dismissAttachmentPanel({bool withHaptic = false}) {
    if (!mounted || _isDismissingSheet) return;

    _isDismissingSheet = true;
    _hideAlbumMenu();

    if (withHaptic) {
      unawaited(HapticFeedback.selectionClick());
    }

    // Use one route-dismiss path for the close button, backdrop tap, header
    // drag, and a sheet dragged all the way to its minimum extent.
    Navigator.of(context).pop();
  }

  void _bindGalleryScrollController(ScrollController controller) {
    if (identical(_galleryScrollController, controller)) return;
    _galleryScrollController?.removeListener(_syncGalleryScrollProgress);
    _galleryScrollController = controller;
    controller.addListener(_syncGalleryScrollProgress);
  }

  void _syncGalleryScrollProgress() {
    final controller = _galleryScrollController;
    if (controller == null || !controller.hasClients) return;
    final progress = (controller.offset / 28).clamp(0.0, 1.0).toDouble();
    if ((progress - _galleryScrollProgress.value).abs() > 0.001) {
      _galleryScrollProgress.value = progress;
    }
  }

  void _handleHeaderDragStart(DragStartDetails details) {
    _headerDragWasDownward = false;
    _hideAlbumMenu();
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    final delta = details.primaryDelta ?? 0;
    if (delta > 0) _headerDragWasDownward = true;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight <= 0) return;
    final nextSize = (_sheetController.size - (delta / screenHeight))
        .clamp(_minimumSheetSize, _maximumSheetSize)
        .toDouble();
    _sheetController.jumpTo(nextSize);
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    final size = _sheetController.size;
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _headerDragWasDownward &&
        (size <= _dismissSheetSize ||
            (velocity > 1200 && size < _initialSheetSize));
    if (shouldDismiss) {
      _dismissAttachmentPanel(withHaptic: true);
      return;
    }
    final shouldExpand =
        velocity < -700 || size > (_initialSheetSize + _maximumSheetSize) / 2;
    unawaited(
      _sheetController.animateTo(
        shouldExpand ? _maximumSheetSize : _initialSheetSize,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handleHeaderDragCancel() {
    // Do not change the sheet extent when the header drag recognizer loses the
    // gesture arena. Controls inside the header (especially the Recents album
    // selector) use their own tap recognizers. A normal tap can therefore
    // cancel this parent vertical-drag recognizer. Resetting to
    // `_startingSheetSize` here used to collapse a fully expanded attachment
    // panel back to half height whenever the Recents popup was closed.
    //
    // A cancelled drag is not a completed resize gesture, so preserving the
    // current extent is both safer and consistent with child header actions.
    _headerDragWasDownward = false;
  }

  Widget _draggableAttachmentHeader() => GestureDetector(
    key: const ValueKey('attachment-drag-header'),
    behavior: HitTestBehavior.translucent,
    onVerticalDragStart: _handleHeaderDragStart,
    onVerticalDragUpdate: _handleHeaderDragUpdate,
    onVerticalDragEnd: _handleHeaderDragEnd,
    onVerticalDragCancel: _handleHeaderDragCancel,
    child: _attachmentHeader(),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestMediaRefresh();
      if (_fileAudioMode && _audioAccessDenied) {
        unawaited(_refreshAudioPermissionState());
      }
      if (_cameraRouteOpen) return;
      if (_cameraPreviewStarting) {
        _cameraPreviewRestartPending = true;
        return;
      }
      if (!widget.initialAudioMode && _selectedAttachmentCategory == 0) {
        unawaited(_initialiseCameraPreview(requestIfNeeded: false));
      }
      return;
    }
    // `inactive` is transient on Android (permission/source choosers, focus
    // loss, notification shade). Disposing here made the native camera open
    // again as soon as the chooser returned, which displayed that chooser a
    // second time. Release only when the app is genuinely backgrounded.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_disposeCameraPreview());
    }
  }

  void _requestMediaRefresh() {
    if (!mounted ||
        _mediaRefreshInFlight ||
        _selectedAlbum?.isAll != true ||
        widget.initialAudioMode) {
      return;
    }
    _mediaRefreshInFlight = true;
    unawaited(_refreshRecentAssets());
  }

  Future<void> _refreshRecentAssets() async {
    final previousIds = Set<String>.of(_knownAssetIds);
    try {
      await _loadAlbums();
      if (!mounted || !_hasInitialAssetSnapshot) return;
      final newImages = _assets
          .where(
            (asset) =>
                asset.type == AssetType.image &&
                !previousIds.contains(asset.id),
          )
          .take(4)
          .toList(growable: false);
      _knownAssetIds
        ..clear()
        ..addAll(_assets.map((asset) => asset.id));
      for (final asset in newImages) {
        unawaited(_prepareAttachmentImage(asset));
      }
    } finally {
      _mediaRefreshInFlight = false;
    }
  }

  Future<void> _initialiseCameraPreview({bool requestIfNeeded = false}) async {
    if (_cameraPreviewController?.value.isInitialized == true) {
      return;
    }
    if (_cameraPreviewStarting) {
      await _cameraPreviewAttempt?.future;
      return;
    }
    _cameraPreviewStarting = true;
    final attempt = Completer<void>();
    _cameraPreviewAttempt = attempt;
    final generation = ++_cameraPreviewGeneration;
    try {
      final cameraPermission = await AppPermissionService.instance
          .ensureCameraGranted(requestIfNeeded: requestIfNeeded);
      if (!cameraPermission) return;
      final cameras = await CameraInventoryService.instance.load();
      if (cameras.isEmpty) return;
      final camera =
          preferredCameraForDirection(cameras, CameraLensDirection.back) ??
          cameras.first;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        fps: 24,
      );
      await controller.initialize();
      if (!mounted || generation != _cameraPreviewGeneration) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraPreviewController = controller;
        _cameraPreviewAudioEnabled = false;
      });
    } catch (error) {
      debugPrint('Attachment camera preview could not start: $error');
    } finally {
      _cameraPreviewStarting = false;
      if (!attempt.isCompleted) attempt.complete();
      if (identical(_cameraPreviewAttempt, attempt)) {
        _cameraPreviewAttempt = null;
      }
      if (_cameraPreviewRestartPending && mounted) {
        _cameraPreviewRestartPending = false;
        unawaited(_initialiseCameraPreview(requestIfNeeded: false));
      }
    }
  }

  Future<void> _disposeCameraPreview() async {
    _cameraPreviewGeneration++;
    final controller = _cameraPreviewController;
    _cameraPreviewController = null;
    _cameraPreviewAudioEnabled = false;
    if (mounted) setState(() {});
    if (controller != null) await controller.dispose();
  }

  void _acceptReturnedCameraController(
    CameraController controller,
    bool audioEnabled,
  ) {
    if (!controller.value.isInitialized) return;
    if (!mounted) {
      unawaited(controller.dispose());
      return;
    }

    final previousController = _cameraPreviewController;
    setState(() {
      _cameraPreviewController = controller;
      _cameraPreviewAudioEnabled = audioEnabled;
    });

    if (previousController != null &&
        !identical(previousController, controller) &&
        previousController.value.isInitialized) {
      unawaited(previousController.dispose());
    }
  }

  Rect? _cameraTileRect() {
    final renderObject = _cameraTileKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    return rect.isFinite && !rect.isEmpty ? rect : null;
  }

  Future<void> _openCamera() async {
    if (!mounted) return;

    // A very fast tap can arrive while native initialization is still
    // finishing. Wait for that same session instead of invalidating it and
    // opening a second controller on the next route.
    if (_cameraPreviewStarting) {
      await _cameraPreviewAttempt?.future;
      if (!mounted) return;
    }

    if (_cameraPreviewController?.value.isInitialized != true) {
      await _initialiseCameraPreview(requestIfNeeded: true);
      if (!mounted) return;
    }

    // Transfer ownership of the initialized preview controller to the full
    // camera route. The panel must not dispose it after Navigator.pop.
    final controller = _cameraPreviewController;
    final transferableController = controller?.value.isInitialized == true
        ? controller
        : null;
    final audioEnabled =
        transferableController != null && _cameraPreviewAudioEnabled;

    // The attachment panel remains underneath the camera route and owns this
    // preview controller. Keep it alive so returning with Back reveals the
    // same live tile instead of waiting for a second native camera session.
    if (controller != null && transferableController == null) {
      _cameraPreviewGeneration++;
      _cameraPreviewController = null;
      _cameraPreviewAudioEnabled = false;
      await controller.dispose();
    }

    if (!mounted) {
      await transferableController?.dispose();
      return;
    }

    final selection = _AttachmentSelection.action(
      _AttachmentAction.camera,
      cameraController: transferableController,
      cameraAudioEnabled: audioEnabled,
      cameraSourceRect: _cameraTileRect(),
      onCameraControllerReturned: _acceptReturnedCameraController,
    );

    final cameraHandler = widget.onCameraSelected;
    if (cameraHandler == null) {
      widget.onSelected(selection);
      return;
    }

    unawaited(HapticFeedback.selectionClick());

    setState(() => _cameraRouteOpen = true);
    try {
      // Keep this route alive underneath while the camera's single preview
      // expands from, and contracts back toward, the measured tile rectangle.
      await cameraHandler(selection);
    } finally {
      if (!mounted) return;
      setState(() => _cameraRouteOpen = false);

      // Normal Back returns the live controller synchronously. This is only a
      // recovery path for a native error, lifecycle loss, or a route that did
      // not return a usable session.
      if (!widget.initialAudioMode &&
          _selectedAttachmentCategory == 0 &&
          _cameraPreviewController?.value.isInitialized != true) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            widget.initialAudioMode ||
            _selectedAttachmentCategory != 0 ||
            _cameraPreviewController?.value.isInitialized == true) {
          return;
        }
        unawaited(_initialiseCameraPreview(requestIfNeeded: false));
      }
    }
  }

  Future<void> _loadAlbums() async {
    if (mounted) {
      setState(() {
        _loadingMedia = true;
        _photoAccessDenied = false;
        _mediaLoadFailed = false;
      });
    }
    try {
      final permission = await PhotoLibraryPermissionService.instance
          .ensureVisualMediaAccess(
            type: widget.profilePhotoMode
                ? RequestType.image
                : RequestType.common,
          );
      if (!mounted) return;
      if (!permission.hasAccess) {
        setState(() {
          _loadingMedia = false;
          _photoAccessDenied = true;
        });
        return;
      }

      // Telegram opens directly on the all-media/recents bucket. Loading every
      // album first can be noticeably slower on large device libraries.
      final recentAlbums = await PhotoManager.getAssetPathList(
        type: widget.profilePhotoMode ? RequestType.image : RequestType.common,
        onlyAll: true,
        filterOption: _recentMediaFilter,
      );
      if (!mounted) return;
      setState(() {
        _albums = recentAlbums;
        _selectedAlbum = recentAlbums.isEmpty ? null : recentAlbums.first;
        _photoAccessDenied = false;
      });
      // Discover device albums alongside Recents paging. Waiting until every
      // recent asset was loaded meant the first menu often contained only the
      // all-media bucket and could not update until it was reopened.
      unawaited(_loadAlbumChoices());
      await _loadAssets();
      if (mounted && !_hasInitialAssetSnapshot) {
        _knownAssetIds
          ..clear()
          ..addAll(_assets.map((asset) => asset.id));
        _hasInitialAssetSnapshot = true;
      }
    } catch (error, stackTrace) {
      debugPrint('Attachment picker could not load recents: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loadingMedia = false;
        _mediaLoadFailed = true;
      });
    }
  }

  Future<void> _loadAlbumChoices() async {
    final activeLoad = _albumChoicesLoadInFlight;
    if (activeLoad != null) {
      await activeLoad;
      return;
    }

    late final Future<void> load;
    load = _performAlbumChoicesLoad();
    _albumChoicesLoadInFlight = load;
    try {
      await load;
    } finally {
      if (identical(_albumChoicesLoadInFlight, load)) {
        _albumChoicesLoadInFlight = null;
      }
    }
  }

  Future<void> _performAlbumChoicesLoad() async {
    if (mounted) {
      _loadingAlbumChoices = true;
      _albumMenuEntry?.markNeedsBuild();
    }
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: widget.profilePhotoMode ? RequestType.image : RequestType.common,
        onlyAll: false,
        filterOption: _recentMediaFilter,
      );
      if (!mounted || albums.isEmpty) return;
      final selectedAlbumId = _selectedAlbum?.id;
      setState(() {
        _albums = albums;
        if (selectedAlbumId != null) {
          for (final album in albums) {
            if (album.id == selectedAlbumId) {
              _selectedAlbum = album;
              break;
            }
          }
        }
      });
      _albumMenuEntry?.markNeedsBuild();
    } catch (_) {
      // Recents remains fully usable if secondary album discovery fails.
    } finally {
      if (mounted) {
        _loadingAlbumChoices = false;
        _albumMenuEntry?.markNeedsBuild();
      }
    }
  }

  Future<void> _loadAssets() async {
    final album = _selectedAlbum;
    final loadGeneration = ++_assetLoadGeneration;
    if (album == null) {
      if (mounted) setState(() => _loadingMedia = false);
      return;
    }
    setState(() {
      _assets = <AssetEntity>[];
      _loadingMedia = true;
      _mediaLoadFailed = false;
    });
    try {
      final loadedAssets = <AssetEntity>[];
      var page = 0;
      while (mounted && loadGeneration == _assetLoadGeneration) {
        final assets = await album.getAssetListPaged(
          page: page,
          size: _assetPageSize,
        );
        if (!mounted || loadGeneration != _assetLoadGeneration) return;
        if (assets.isEmpty) break;

        loadedAssets.addAll(assets);
        setState(() {
          _assets = List<AssetEntity>.of(loadedAssets);
          _loadingMedia = true;
        });

        if (assets.length < _assetPageSize) break;
        page++;
      }
      if (!mounted || loadGeneration != _assetLoadGeneration) return;
      setState(() => _loadingMedia = false);
    } catch (error, stackTrace) {
      debugPrint('Attachment picker could not load album media: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || loadGeneration != _assetLoadGeneration) return;
      setState(() {
        _loadingMedia = false;
        _mediaLoadFailed = true;
      });
    }
  }

  void _toggleAssetSelection(AssetEntity asset) {
    if (_sendingSelection) return;
    unawaited(HapticFeedback.selectionClick());
    final selectionCount =
        _selectedAssets.length + (_fileAudioMode ? _selectedFiles.length : 0);
    if (!_selectedAssets.contains(asset) &&
        selectionCount >= _maxSelectedMediaItems) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('You can send up to 30 media items')),
      );
      return;
    }
    setState(() {
      final selectedIndex = _selectedAssets.indexOf(asset);
      if (selectedIndex == -1) {
        _selectedAssets.add(asset);
      } else {
        _selectedAssets.removeAt(selectedIndex);
        if (_selectedAssets.isEmpty && _selectedFiles.isEmpty) {
          _captionFocusNode.unfocus();
          _captionController.clear();
        }
      }
    });
  }

  Future<Size?> _resolveProfilePhotoSourceSize(
    AssetEntity asset,
    File file,
  ) async {
    if (asset.width > 0 && asset.height > 0) {
      return Size(asset.width.toDouble(), asset.height.toDouble());
    }

    try {
      final bytes = await file.readAsBytes();
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size.width > 0 && size.height > 0 ? size : null;
    } catch (error) {
      debugPrint('Could not resolve profile-photo dimensions: $error');
      return null;
    }
  }

  Future<_PreparedAttachmentImage?> _prepareAttachmentImage(AssetEntity asset) {
    final existing = _preparedImages[asset.id];
    if (existing != null)
      return Future<_PreparedAttachmentImage?>.value(existing);
    final active = _preparingImages[asset.id];
    if (active != null) return active;

    final future = _hydrateAttachmentImage(asset);
    _preparingImages[asset.id] = future;
    future.whenComplete(() {
      if (identical(_preparingImages[asset.id], future)) {
        _preparingImages.remove(asset.id);
      }
    });
    return future;
  }

  Future<_PreparedAttachmentImage?> _hydrateAttachmentImage(
    AssetEntity asset,
  ) async {
    if (asset.type != AssetType.image) return null;
    try {
      final refreshed = await asset.obtainForNewProperties() ?? asset;
      if (!mounted) return null;
      final file = await refreshed.file;
      if (file == null || !await file.exists()) return null;

      _assetFilePaths[refreshed.id] = file.path;
      await PhotoCachingManager.instance.requestCacheAssets(
        assets: <AssetEntity>[refreshed],
        option: _heroThumbnailOption,
      );
      final bytes = await refreshed.thumbnailDataWithOption(
        _heroThumbnailOption,
      );
      if (bytes == null || bytes.isEmpty || !mounted) return null;

      final provider = MemoryImage(bytes);
      await precacheImage(provider, context);
      if (!mounted) return null;
      final prepared = _PreparedAttachmentImage(
        assetId: refreshed.id,
        file: file,
        heroProvider: provider,
        pixelSize: Size(
          refreshed.width > 0 ? refreshed.width.toDouble() : 0,
          refreshed.height > 0 ? refreshed.height.toDouble() : 0,
        ),
      );
      _preparedImages[refreshed.id] = prepared;
      if (mounted) {
        setState(() {
          _assets = _assets
              .map(
                (candidate) =>
                    candidate.id == refreshed.id ? refreshed : candidate,
              )
              .toList(growable: false);
        });
      }
      return prepared;
    } catch (error, stackTrace) {
      debugPrint('Could not hydrate attachment image ${asset.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _selectProfilePhoto(AssetEntity asset) async {
    if (_sendingSelection || asset.type != AssetType.image) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _sendingSelection = true);

    final file = await asset.file;
    if (!mounted) return;
    if (file == null || !await file.exists()) {
      setState(() => _sendingSelection = false);
      return;
    }
    _assetFilePaths[asset.id] = file.path;

    // Hero destinations must exist on the first frame of the pushed route.
    // Resolve dimensions before navigation so ProfilePhotoCropPage can build
    // its image rect (and therefore its Hero) synchronously on frame one.
    final sourceSize = await _resolveProfilePhotoSourceSize(asset, file);
    if (!mounted) return;
    if (sourceSize == null) {
      setState(() => _sendingSelection = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not read this photo.')),
        );
      return;
    }

    final heroTag = _attachmentImageHeroTag(asset.id);
    final croppedPath = await Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProfilePhotoCropPage(
              sourcePath: file.path,
              sourcePixelSize: sourceSize,
              openingImageHeroTag: heroTag,
              openedFromCamera: false,
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
    if (!mounted) return;
    if (croppedPath == null || croppedPath.trim().isEmpty) {
      setState(() => _sendingSelection = false);
      return;
    }

    final committedPath = croppedPath.trim();

    // The crop route has just completed its reverse Hero flight back into this
    // tile. Switch the tile to the final profile Hero tag and cropped file, then
    // give Flutter one frame to register that Hero before the panel route pops.
    setState(() {
      _committedProfilePhotoAssetId = asset.id;
      _committedProfilePhotoPath = committedPath;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    widget.onSelected(
      _AttachmentSelection.media(
        profilePhotoAlreadyCropped: true,
        media: <ChatPickedAttachment>[
          ChatPickedAttachment(
            filePath: committedPath,
            attachmentType: 'image',
            width: 640,
            height: 640,
          ),
        ],
      ),
    );
  }

  Future<void> _openAssetEditor(AssetEntity asset) async {
    if (_sendingSelection) return;
    setState(() => _sendingSelection = true);
    final originalFile = await asset.file;
    if (!mounted || originalFile == null) {
      if (mounted) setState(() => _sendingSelection = false);
      return;
    }
    _assetFilePaths[asset.id] = originalFile.path;

    if (asset.type == AssetType.image) {
      final editedPath = _editedAssetPaths[asset.id]?.trim();
      if (editedPath != null && editedPath.isNotEmpty) {
        await precacheImage(FileImage(File(editedPath)), context);
      } else if (await _prepareAttachmentImage(asset) == null) {
        if (mounted) setState(() => _sendingSelection = false);
        return;
      }
    }
    if (!mounted) return;

    if (asset.type == AssetType.image) {
      final flightProvider = _heroFlightImageProvider(asset);
      try {
        // The Hero shuttle uses this exact provider/configuration. Resolve its
        // first frame before pushing the editor so a new MediaStore photo does
        // not begin decoding during the shared-element flight.
        await precacheImage(flightProvider, context);
      } catch (error) {
        debugPrint('Could not prepare attachment Hero image: $error');
        if (mounted) setState(() => _sendingSelection = false);
        return;
      }
    }
    if (!mounted) return;

    final selectedIndex = _selectedAssets.indexOf(asset);

    // Build the exact visible Recents/album image sequence before opening the
    // editor. The editor no longer has to guess the next photo by querying the
    // device library again, which is what prevented paging on some Android
    // devices/permission states.
    final mediaIds = <String>[];
    final mediaPaths = <String>[];

    if (asset.type == AssetType.image) {
      for (final candidate in _assets) {
        if (candidate.type != AssetType.image) continue;

        final candidateFile = await candidate.file;
        if (candidateFile == null) continue;

        mediaIds.add(candidate.id);
        mediaPaths.add(_editedAssetPaths[candidate.id] ?? candidateFile.path);
      }
    }

    var initialMediaIndex = mediaIds.indexOf(asset.id);
    if (initialMediaIndex < 0) {
      mediaIds
        ..clear()
        ..add(asset.id);
      mediaPaths
        ..clear()
        ..add(_editedAssetPaths[asset.id] ?? originalFile.path);
      initialMediaIndex = 0;
    }

    final isImage = asset.type == AssetType.image;
    final imageHeroTag = isImage ? _attachmentImageHeroTag(asset.id) : null;
    final preparedImage = isImage ? _preparedImages[asset.id] : null;
    final result = await Navigator.of(context).push<ChatMediaEditorResult>(
      PageRouteBuilder<ChatMediaEditorResult>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ChatMediaEditorScreen(
              sourcePath: _editedAssetPaths[asset.id] ?? originalFile.path,
              attachmentType: asset.type == AssetType.video ? 'video' : 'image',
              recipientLabel: widget.recipientLabel,
              initialCaption: _captionController.text,
              selectionIndex: selectedIndex < 0 ? null : selectedIndex + 1,
              selectedCount: _selectedAssets.length,
              mediaIds: mediaIds,
              mediaPaths: mediaPaths,
              initialMediaIndex: initialMediaIndex,
              initialSelectedMediaIds: _selectedAssets
                  .map((selectedAsset) => selectedAsset.id)
                  .toList(growable: false),
              openingImageHeroTag: imageHeroTag,
              openingImageMediaId: isImage ? asset.id : null,
              openingHeroImageProvider: preparedImage?.heroProvider,
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
    if (mounted) setState(() => _sendingSelection = false);
    if (!mounted || result == null) return;

    setState(() {
      _captionController.text = result.caption;

      // Apply edits to the actual asset that was on screen when the user
      // completed editing, not blindly to the tile that originally opened the
      // editor.
      for (final entry in result.editedMediaPaths.entries) {
        if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
          _editedAssetPaths[entry.key] = entry.value;
        }
      }

      // Backward-compatible fallback for any old result that lacks media IDs.
      if (result.editedMediaPaths.isEmpty) {
        final editedPath = result.editedFilePath;
        if (editedPath != null && editedPath.isNotEmpty) {
          final editedId = result.currentMediaId ?? asset.id;
          _editedAssetPaths[editedId] = editedPath;
        }
      }

      final selectedIds = result.selectedMediaIds;
      if (selectedIds != null) {
        final availableById = <String, AssetEntity>{
          for (final selectedAsset in _selectedAssets)
            selectedAsset.id: selectedAsset,
          for (final candidate in _assets) candidate.id: candidate,
        };

        _selectedAssets
          ..clear()
          ..addAll(
            selectedIds
                .take(_maxSelectedMediaItems)
                .map((id) => availableById[id])
                .whereType<AssetEntity>(),
          );
      } else {
        final currentIndex = _selectedAssets.indexOf(asset);
        if (result.selected && currentIndex < 0) {
          _selectedAssets.add(asset);
        } else if (!result.selected && currentIndex >= 0) {
          _selectedAssets.removeAt(currentIndex);
        }
      }
    });

    if (result.sendNow) await _sendSelectedAssets();
  }

  Future<void> _sendSelectedAssets() async {
    if (_selectedAssets.isEmpty || _sendingSelection) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _sendingSelection = true);

    final selectedMedia = <ChatPickedAttachment>[];
    for (final asset in List<AssetEntity>.of(
      _selectedAssets.take(_maxSelectedMediaItems),
    )) {
      final editedPath = _editedAssetPaths[asset.id];
      final file = editedPath == null ? await asset.file : File(editedPath);
      if (file == null || !await file.exists()) continue;
      var mediaWidth = asset.width;
      var mediaHeight = asset.height;
      if (editedPath != null && asset.type == AssetType.image) {
        final editedSize = await _readEncodedImageSize(file);
        mediaWidth = editedSize?.width.round() ?? mediaWidth;
        mediaHeight = editedSize?.height.round() ?? mediaHeight;
      }
      selectedMedia.add(
        ChatPickedAttachment(
          filePath: file.path,
          attachmentType: _fileGalleryMode || _fileAudioMode
              ? 'file'
              : asset.type == AssetType.video
              ? 'video'
              : 'image',
          width: _fileGalleryMode || _fileAudioMode || mediaWidth <= 0
              ? null
              : mediaWidth,
          height: _fileGalleryMode || _fileAudioMode || mediaHeight <= 0
              ? null
              : mediaHeight,
        ),
      );
    }

    if (!mounted) return;
    if (selectedMedia.isEmpty) {
      setState(() => _sendingSelection = false);
      return;
    }

    final caption = _captionController.text.trim();
    widget.onSelected(
      _AttachmentSelection.media(
        media: selectedMedia,
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  Future<Size?> _readEncodedImageSize(File file) async {
    ImmutableBuffer? buffer;
    ImageDescriptor? descriptor;
    try {
      buffer = await ImmutableBuffer.fromUint8List(await file.readAsBytes());
      descriptor = await ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) return null;
      return Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  String _videoDuration(AssetEntity asset) {
    final duration = asset.videoDuration;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _closeButton() {
    final layout = _layout;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _dismissAttachmentPanel(withHaptic: true),
            splashFactory: NoSplash.splashFactory,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF17191E).withValues(alpha: 0.88),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: SizedBox.square(
                dimension: layout.headerControlSize,
                child: Icon(
                  Icons.close_rounded,
                  size: 26 * layout.scale,
                  color: WrytteColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _hideAlbumMenu({bool immediately = false}) {
    final entry = _albumMenuEntry;
    if (entry == null) return;

    void removeEntry() {
      if (identical(_albumMenuEntry, entry)) {
        _albumMenuEntry = null;
        _albumMenuRevealKey = null;
      }
      if (entry.mounted) entry.remove();
    }

    if (immediately) {
      removeEntry();
    } else {
      final revealState = _albumMenuRevealKey?.currentState;
      if (revealState == null) {
        // The entry can be dismissed in the same frame it was inserted,
        // before its animation state is mounted.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final mountedState = _albumMenuRevealKey?.currentState;
          if (identical(_albumMenuEntry, entry) && mountedState != null) {
            mountedState.close();
          } else if (identical(_albumMenuEntry, entry)) {
            removeEntry();
          }
        });
      } else {
        revealState.close();
      }
    }

    // Intentionally do not resize the attachment sheet here. Opening Recents
    // promotes the panel to full height; dismissing only the popup must leave
    // the attachment panel at whatever extent it currently has.
  }

  Future<void> _toggleAlbumMenu() async {
    if (_albumMenuEntry != null) {
      // Closing Recents only removes the popup. It must not collapse the sheet
      // back to `_initialSheetSize`.
      _hideAlbumMenu();
      return;
    }

    // Recents needs the full attachment layout. Once promoted to max extent,
    // that full-size state is intentionally preserved after the popup closes.
    if (_sheetController.isAttached &&
        _sheetController.size < _maximumSheetSize - 0.01) {
      await _sheetController.animateTo(
        _maximumSheetSize,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || _isDismissingSheet) return;
      // animateTo completes before the composited LayerLink has necessarily
      // published its final expanded-frame transform to the root overlay.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _isDismissingSheet) return;
    }

    _showAlbumMenu();
  }

  Future<_AttachmentAlbumMetadata> _loadAlbumMetadata(AssetPathEntity album) =>
      _albumMetadata.putIfAbsent(album.id, () async {
        final count = await album.assetCountAsync;
        final covers = await album.getAssetListRange(start: 0, end: 1);
        return _AttachmentAlbumMetadata(
          count: count,
          cover: covers.isEmpty ? null : covers.first,
        );
      });

  List<AssetPathEntity> get _visibleAlbumChoices {
    final visible = <AssetPathEntity>[];
    final seenLabels = <String>{};
    for (final album in _albums) {
      final label = (album.isAll ? 'Recents' : album.name).trim();
      // Android MediaStore can expose a root/test bucket as `0`, and can
      // expose multiple storage buckets with the same display name. Their
      // media remains available through Recents, so keep this quick chooser
      // clear rather than presenting misleading duplicate entries.
      if (label.isEmpty || label == '0') continue;
      if (!seenLabels.add(label.toLowerCase())) continue;
      visible.add(album);
    }
    return visible;
  }

  void _showAlbumMenu() {
    if (!mounted || _visibleAlbumChoices.isEmpty) return;
    if (_albumMenuEntry != null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final revealKey = GlobalKey<_AlbumMenuRevealState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final visibleAlbums = _visibleAlbumChoices;
        final showLoadingRow = _loadingAlbumChoices;
        final screenHeight = MediaQuery.sizeOf(overlayContext).height;
        final screenWidth = MediaQuery.sizeOf(overlayContext).width;
        final menuWidth = math.min(258.0, screenWidth - 32);
        final maxMenuHeight = math.min(420.0, screenHeight * 0.54);

        void dismiss() {
          // Dismiss only this overlay entry. Never alter the sheet extent here;
          // Recents closing should keep an expanded attachment panel expanded.
          if (_albumMenuEntry == entry) {
            _hideAlbumMenu();
          } else if (entry.mounted) {
            entry.remove();
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: dismiss,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _albumSelectorLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomCenter,
              followerAnchor: Alignment.topCenter,
              offset: const Offset(0, 4),
              child: Material(
                type: MaterialType.transparency,
                child: _AlbumMenuReveal(
                  key: revealKey,
                  onDismissed: () {
                    if (identical(_albumMenuEntry, entry)) {
                      _albumMenuEntry = null;
                      _albumMenuRevealKey = null;
                    }
                    if (entry.mounted) entry.remove();
                  },
                  child: SizedBox(
                    width: menuWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxMenuHeight),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  WrytteColors.surfaceRaised.withValues(
                                    alpha: 0.82,
                                  ),
                                  const Color(
                                    0xFF0B0D11,
                                  ).withValues(alpha: 0.78),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.32),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              itemCount:
                                  visibleAlbums.length +
                                  (showLoadingRow ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == visibleAlbums.length) {
                                  return const SizedBox(
                                    height: 48,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox.square(
                                          dimension: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.7,
                                            color: WrytteColors.textSecondary,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Loading albums…',
                                          style: TextStyle(
                                            color: WrytteColors.textSecondary,
                                            fontFamily: WrytteTypography
                                                .primaryFontFamily,
                                            fontSize: 12,
                                            height: 1,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                final album = visibleAlbums[index];
                                final selected = album == _selectedAlbum;
                                final label = album.isAll
                                    ? 'Recents'
                                    : album.name;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashFactory: NoSplash.splashFactory,
                                    onTap: () {
                                      unawaited(
                                        HapticFeedback.selectionClick(),
                                      );
                                      dismiss();
                                      if (album == _selectedAlbum) return;
                                      setState(() => _selectedAlbum = album);
                                      unawaited(_loadAssets());
                                    },
                                    child: Container(
                                      height: 60,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: FutureBuilder<_AttachmentAlbumMetadata>(
                                        future: _loadAlbumMetadata(album),
                                        builder: (context, snapshot) => Row(
                                          children: [
                                            _albumCover(
                                              snapshot.data?.cover,
                                              label,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: WrytteColors
                                                          .textPrimary,
                                                      fontFamily:
                                                          WrytteTypography
                                                              .primaryFontFamily,
                                                      fontSize: 15,
                                                      height: 1.08,
                                                      fontWeight: selected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    snapshot.hasData
                                                        ? '${snapshot.data!.count} ${snapshot.data!.count == 1 ? 'item' : 'items'}'
                                                        : 'Loading…',
                                                    style: const TextStyle(
                                                      color: WrytteColors
                                                          .textSecondary,
                                                      fontFamily:
                                                          WrytteTypography
                                                              .primaryFontFamily,
                                                      fontSize: 12,
                                                      height: 1,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (selected)
                                              const Icon(
                                                Icons.check_rounded,
                                                color: WrytteColors.primary,
                                                size: 21,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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
      },
    );

    _albumMenuEntry = entry;
    _albumMenuRevealKey = revealKey;
    overlay.insert(entry);
  }

  Widget _albumCover(AssetEntity? cover, String label) {
    final Widget child;
    if (cover != null) {
      child = Image(
        image: AssetEntityImageProvider(
          cover,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(144),
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      child = ColoredBox(
        color: Colors.white.withValues(alpha: 0.07),
        child: Icon(
          label.toLowerCase().contains('camera')
              ? Icons.photo_camera_outlined
              : Icons.photo_library_outlined,
          color: WrytteColors.textSecondary,
          size: 21,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(dimension: 43, child: child),
    );
  }

  Widget _albumSelector() {
    final albumLabel = _selectedAlbum == null || _selectedAlbum!.isAll
        ? 'Recents'
        : _selectedAlbum!.name;

    return CompositedTransformTarget(
      link: _albumSelectorLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          unawaited(_toggleAlbumMenu());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _selectedAssets.isEmpty ? 190 : 120,
                ),
                child: Text(
                  albumLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WrytteColors.textPrimary,
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              wrytteSvgAssetIcon(
                assetPath: 'assets/svg/solar--alt-arrow-down-linear.svg',
                canvas: 20,
                scale: 1.04,
                offset: const Offset(0, 0.5),
                color: Colors.white.withValues(alpha: 0.76),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionHeaderActions() {
    final layout = _layout;
    final selectedCount = _selectedAssets.length;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.centerRight,
          scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: selectedCount == 0
          ? const SizedBox.shrink(key: ValueKey<String>('no-selection'))
          : Row(
              key: const ValueKey<String>('selection-actions'),
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Container(
                    key: ValueKey<int>(selectedCount),
                    width: 32 * layout.scale,
                    height: 32 * layout.scale,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: WrytteColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$selectedCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 15,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 19 * layout.scale),
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => unawaited(HapticFeedback.selectionClick()),
                        splashFactory: NoSplash.splashFactory,
                        child: DecoratedBox(
                          decoration: wrytteGlassDecoration(radius: 20),
                          child: SizedBox.square(
                            dimension: 40 * layout.scale,
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: 23 * layout.scale,
                              color: WrytteColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _locationHeaderAction() {
    final layout = _layout;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => unawaited(HapticFeedback.selectionClick()),
            splashFactory: NoSplash.splashFactory,
            child: DecoratedBox(
              decoration: wrytteGlassDecoration(radius: 22),
              child: SizedBox.square(
                dimension: layout.headerControlSize,
                child: Icon(
                  Icons.search_rounded,
                  size: 24 * layout.scale,
                  color: WrytteColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cameraTile() {
    final cameraController = _cameraPreviewController;
    final tile = Material(
      key: _cameraTileKey,
      color: const Color(0xFF171A1F),
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: () => unawaited(_openCamera()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF24282E), Color(0xFF14171B)],
                ),
              ),
            ),
            if (!_cameraRouteOpen &&
                cameraController != null &&
                cameraController.value.isInitialized)
              Positioned.fill(
                child: WrytteCameraPreviewSurface(controller: cameraController),
              ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.06)),
            Positioned(
              top: 8,
              right: 8,
              child: wrytteSvgAssetIcon(
                assetPath: 'assets/svg/Camera icon .svg',
                canvas: 25,
                scale: 0.94,
                color: WrytteColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    return tile;
  }

  Widget _assetTile(AssetEntity asset) {
    final selectedIndex = _selectedAssets.indexOf(asset);
    final isSelected = selectedIndex >= 0;
    final thumbnail = Image(
      image: AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(360),
      ),
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );

    final committedPath = _committedProfilePhotoAssetId == asset.id
        ? _committedProfilePhotoPath
        : null;
    final isCommittedProfilePhoto =
        committedPath != null && committedPath.trim().isNotEmpty;
    final heroTag =
        isCommittedProfilePhoto && widget.profilePhotoDestinationHeroTag != null
        ? widget.profilePhotoDestinationHeroTag!
        : _attachmentImageHeroTag(asset.id);

    final visibleImage = isCommittedProfilePhoto
        ? Image.file(
            File(committedPath!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          )
        : thumbnail;

    // Keep the Hero in the tree synchronously. The old FutureBuilder created
    // asset.file during build, which meant a rebuild could temporarily replace
    // the Hero with a plain thumbnail exactly when navigation started.
    final highQualityFlightImage = isCommittedProfilePhoto
        ? Image.file(
            File(committedPath!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          )
        : Image(
            image: _heroFlightImageProvider(asset),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          );

    final image = asset.type == AssetType.image && !_fileGalleryMode
        ? widget.profilePhotoMode && !isCommittedProfilePhoto
              // This is the source half of the crop-specific Hero. The crop
              // destination supplies the normalized circular window, and the
              // shuttle animates the photo + dim mask together as one visual.
              ? ProfilePhotoCropImageHero(
                  tag: heroTag,
                  source:
                      _editedAssetPaths[asset.id] ??
                      _assetFilePaths[asset.id] ??
                      asset.id,
                  flightChild: highQualityFlightImage,
                  child: visibleImage,
                )
              // Once a crop has been committed this tile hands off to the
              // circular profile avatar, so use the existing generic Hero and
              // preserve its known-good circle-to-image treatment.
              : FullScreenImageHero(
                  tag: heroTag,
                  source:
                      committedPath ??
                      _editedAssetPaths[asset.id] ??
                      _assetFilePaths[asset.id] ??
                      asset.id,
                  flightStartBorderRadius: 0,
                  flightChild: highQualityFlightImage,
                  child: visibleImage,
                )
        : visibleImage;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.profilePhotoMode
          ? () => unawaited(_selectProfilePhoto(asset))
          : _fileGalleryMode
          ? () => _toggleAssetSelection(asset)
          : () => unawaited(_openAssetEditor(asset)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          if (asset.type == AssetType.video)
            Positioned(
              right: 6,
              bottom: 5,
              child: Text(
                _videoDuration(asset),
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
          if (!widget.profilePhotoMode)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleAssetSelection(asset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? WrytteColors.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? WrytteColors.primary
                          : const Color(0xFFC7CBD1),
                      width: 1.15,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: isSelected
                        ? KeyedSubtree(
                            key: const ValueKey<String>('selected-check'),
                            child: wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Checkmark edit.svg',
                              canvas: 16,
                              scale: 1,
                              color: Colors.white,
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey<String>('empty')),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ImageProvider<Object> _heroFlightImageProvider(AssetEntity asset) {
    final editedPath = _editedAssetPaths[asset.id]?.trim();
    if (editedPath != null && editedPath.isNotEmpty) {
      return FileImage(File(editedPath));
    }
    final prepared = _preparedImages[asset.id];
    if (prepared != null) return prepared.heroProvider;
    return AssetEntityImageProvider(
      asset,
      isOriginal: false,
      thumbnailSize: const ThumbnailSize.square(720),
    );
  }

  Object _attachmentImageHeroTag(String assetId) =>
      'attachment-image-${identityHashCode(this)}-$assetId';

  Widget _loadingTile(int index) {
    final shade = index.isEven ? 0.055 : 0.075;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: shade),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: shade + 0.025),
            Colors.white.withValues(alpha: shade),
          ],
        ),
      ),
    );
  }

  Widget _mediaStateMessage({
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 104, 34, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: Colors.white.withValues(alpha: 0.50)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WrytteColors.textSecondary,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: WrytteColors.primary,
                textStyle: const TextStyle(
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaGrid(ScrollController scrollController) {
    final layout = _layout;
    final galleryOnly = _fileGalleryMode;
    final showSkeletons = _loadingMedia && _assets.isEmpty;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final adaptiveBottomInset = math.max(bottomInset, 10.0);
    const tileGap = 2.0;
    final columnCount = layout.galleryColumnCount;
    final panelWidth =
        MediaQuery.sizeOf(context).width - (layout.sheetHorizontalInset * 2);
    final tileWidth =
        (panelWidth - (tileGap * (columnCount - 1))) / columnCount;
    final tileHeight = tileWidth * _mediaTileHeightFactor;
    final featuredAssetCount = (columnCount - 1) * 2;
    final skeletonItemCount = columnCount * 3;
    final remainingItemCount = showSkeletons
        ? math.max(0, skeletonItemCount - featuredAssetCount)
        : math.max(0, _assets.length - featuredAssetCount);
    final galleryOnlyItemCount = showSkeletons
        ? skeletonItemCount
        : _assets.length;

    Widget mediaSlot(int assetIndex) {
      if (showSkeletons) return _loadingTile(assetIndex + 1);
      if (assetIndex < _assets.length) return _assetTile(_assets[assetIndex]);
      return const ColoredBox(color: Color(0xFF0B0D10));
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: ValueListenableBuilder<double>(
                valueListenable: _sheetExpansionProgress,
                builder: (context, expansion, child) =>
                    SizedBox(height: layout.headerHeight * (1 - expansion)),
              ),
            ),
            if (!galleryOnly)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: (tileHeight * 2) + 2,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: tileWidth, child: _cameraTile()),
                      const SizedBox(width: tileGap),
                      Expanded(
                        child: Column(
                          children: [
                            for (var row = 0; row < 2; row++) ...[
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var column = 0;
                                      column < columnCount - 1;
                                      column++
                                    ) ...[
                                      if (column > 0)
                                        const SizedBox(width: tileGap),
                                      Expanded(
                                        child: mediaSlot(
                                          (row * (columnCount - 1)) + column,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (row == 0) const SizedBox(height: tileGap),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!galleryOnly)
              const SliverToBoxAdapter(child: SizedBox(height: 2)),
            if (galleryOnly && galleryOnlyItemCount > 0)
              SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                  mainAxisExtent: tileHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, index) => mediaSlot(index),
                  childCount: galleryOnlyItemCount,
                ),
              ),
            if (!galleryOnly && remainingItemCount > 0)
              SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                  mainAxisExtent: tileHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, index) => mediaSlot(index + featuredAssetCount),
                  childCount: remainingItemCount,
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: widget.profilePhotoMode
                    ? 12 + adaptiveBottomInset
                    : layout.bottomNavHeight + 12 + adaptiveBottomInset,
              ),
            ),
          ],
        ),
        if (_photoAccessDenied)
          Positioned.fill(
            child: _mediaStateMessage(
              icon: Icons.photo_library_outlined,
              message: 'Allow photo access to see your recent media',
              actionLabel: 'Open settings',
              onAction: () => unawaited(PhotoManager.openSetting()),
            ),
          )
        else if (_mediaLoadFailed)
          Positioned.fill(
            child: _mediaStateMessage(
              icon: Icons.refresh_rounded,
              message: 'Recent media could not be loaded',
              actionLabel: 'Try again',
              onAction: () => unawaited(_loadAlbums()),
            ),
          )
        else if (!_loadingMedia && _assets.isEmpty)
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 104, 34, 24),
                child: Text(
                  'No recent photos or videos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.56),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _categoryItem({
    required String iconAsset,
    required String selectedIconAsset,
    required String label,
    required WrytteAttachmentMetrics layout,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Semantics(
        button: onTap != null,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  unawaited(HapticFeedback.selectionClick());
                  onTap();
                },
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(18),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4 * layout.scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: layout.bottomNavIconCanvas + 2,
                    child: AnimatedScale(
                      scale: selected ? 1.04 : 1,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOutCubic,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        reverseDuration: const Duration(milliseconds: 210),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.92,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey<bool>(selected),
                          child: wrytteSvgAssetIcon(
                            assetPath: selected ? selectedIconAsset : iconAsset,
                            canvas: layout.bottomNavIconCanvas,
                            scale: 1,
                            color: selected
                                ? WrytteColors.textPrimary
                                : const Color(
                                    0xFFF2F2F2,
                                  ).withValues(alpha: 0.70),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 2 + layout.progress),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    style: TextStyle(
                      color: selected
                          ? WrytteColors.textPrimary
                          : WrytteColors.textPrimary.withValues(alpha: 0.64),
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: layout.bottomNavLabelSize,
                      height: 1,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
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

  void _selectAttachmentCategory(int index) {
    if (_selectedAttachmentCategory == index) return;
    _hideAlbumMenu();
    setState(() => _selectedAttachmentCategory = index);
    if (index == 4) {
      unawaited(_loadDeviceContacts());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = _galleryScrollController;
        if (controller?.hasClients == true) controller!.jumpTo(0);
      });
    }
  }

  Widget _contactsHeaderAction() {
    final layout = _layout;
    final selectedCount = _selectedContacts.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: selectedCount == 0
              ? const SizedBox.shrink(key: ValueKey<String>('contacts-none'))
              : Container(
                  key: ValueKey<int>(selectedCount),
                  width: 32 * layout.scale,
                  height: 32 * layout.scale,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: WrytteColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$selectedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
        if (selectedCount > 0) SizedBox(width: 12 * layout.scale),
        _locationHeaderAction(),
      ],
    );
  }

  List<Contact> _fallbackContacts() {
    return [
      Contact(
        displayName: 'Alice Johnson',
        phones: ['+250 788 100 201'],
        isOnWrytte: true,
      ),
      Contact(
        displayName: 'Daniel Smith',
        phones: ['+250 788 100 202'],
        isOnWrytte: true,
      ),
      Contact(
        displayName: 'Grace Uwase',
        phones: ['+250 788 100 203'],
        isOnWrytte: true,
      ),
      Contact(
        displayName: 'James Williams',
        phones: ['+250 788 100 204'],
        isOnWrytte: true,
      ),
      Contact(
        displayName: 'Maya Niyonzima',
        phones: ['+250 788 100 205'],
        isOnWrytte: true,
      ),
      Contact(
        displayName: 'Samuel Karemera',
        phones: ['+250 788 100 206'],
        isOnWrytte: true,
      ),
    ];
  }

  Future<void> _loadDeviceContacts() async {
    if (_contactsLoaded || _loadingContacts) return;
    setState(() {
      _loadingContacts = true;
      _contactsAccessDenied = false;
    });
    try {
      final ownerId = await AuthService.instance.getCurrentUserId() ?? '';
      if (ownerId.isEmpty) {
        if (mounted) {
          setState(() {
            _deviceContacts = _fallbackContacts();
            _loadingContacts = false;
            _contactsLoaded = true;
          });
        }
        return;
      }
      var contacts = await ContactLocalDb.loadSavedContacts(
        ownerUserId: ownerId,
      );
      if (contacts.isEmpty) {
        final cached = await ContactLocalDb.loadContacts(ownerUserId: ownerId);
        contacts = cached.where((contact) => contact.isOnWrytte).toList();
      }
      if (contacts.isEmpty) {
        contacts = await ContactService().getMatrixContactsCached(ownerId);
      }
      if (contacts.isEmpty) contacts = _fallbackContacts();
      contacts.sort(
        (a, b) => a.formattedName.toLowerCase().compareTo(
          b.formattedName.toLowerCase(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _deviceContacts = contacts;
        _loadingContacts = false;
        _contactsLoaded = true;
      });
    } catch (error) {
      debugPrint('Could not load device contacts: $error');
      if (!mounted) return;
      setState(() {
        _deviceContacts = _fallbackContacts();
        _loadingContacts = false;
        _contactsLoaded = true;
      });
    }
  }

  void _openFileGallery() {
    _hideAlbumMenu();
    _captionFocusNode.unfocus();
    setState(() {
      _fileGalleryMode = true;
      _fileAudioMode = false;
      _selectedFiles.clear();
      _selectedAssets.clear();
      _captionController.clear();
    });
  }

  void _closeFileGallery() {
    _hideAlbumMenu();
    _captionFocusNode.unfocus();
    setState(() {
      _fileGalleryMode = false;
      _selectedAssets.clear();
      _captionController.clear();
    });
  }

  void _openFileAudio() {
    _hideAlbumMenu();
    _captionFocusNode.unfocus();
    setState(() {
      _fileGalleryMode = false;
      _fileAudioMode = true;
      _selectedFiles.clear();
      _selectedAssets.clear();
      _captionController.clear();
    });
    if (!_deviceAudioLoaded && !_audioAccessDenied && !_audioLoadFailed) {
      unawaited(_loadDeviceAudio());
    }
  }

  void _closeFileAudio() {
    _captionFocusNode.unfocus();
    unawaited(_audioListPreviewPlayer.stop());
    setState(() {
      _fileAudioMode = false;
      _selectedFiles.clear();
      _selectedAssets.clear();
      _playingAudioAssetId = null;
      _audioListPlayerState = PlayerState.stopped;
      _captionController.clear();
    });
  }

  Future<void> _loadDeviceAudio() async {
    if (_loadingAudio) return;
    if (mounted) {
      setState(() {
        _loadingAudio = true;
        _audioAccessDenied = false;
        _audioLoadFailed = false;
      });
    }

    try {
      final permission = await PhotoLibraryPermissionService.instance
          .ensureAudioAccess();
      if (!mounted) return;
      if (!permission.hasAccess) {
        setState(() {
          _loadingAudio = false;
          _audioAccessDenied = true;
        });
        return;
      }

      final songs = await _deviceAudioQuery.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      final assets = <AssetEntity>[];
      final titles = <String, String>{};
      final artists = <String, String>{};
      final paths = <String, String>{};
      final sizes = <String, int>{};
      final artworkIds = <String, int>{};
      for (final song in songs.take(200)) {
        final path = song.data.trim();
        if (path.isEmpty) continue;
        final assetId = 'device_audio_${song.id}';
        final title = song.title.trim().isNotEmpty
            ? song.title.trim()
            : song.displayNameWOExt.trim().isNotEmpty
            ? song.displayNameWOExt.trim()
            : 'Audio file';
        final artist = song.artist?.trim() ?? '';
        assets.add(
          AssetEntity(
            id: assetId,
            typeInt: AssetType.audio.index,
            width: 0,
            height: 0,
            duration: ((song.duration ?? 0) / 1000).round(),
            title: title,
          ),
        );
        titles[assetId] = title;
        if (artist.isNotEmpty && artist.toLowerCase() != '<unknown>') {
          artists[assetId] = artist;
        }
        paths[assetId] = path;
        sizes[assetId] = song.size;
        artworkIds[assetId] = song.id;
      }

      if (!mounted) return;
      setState(() {
        _audioAssets = assets;
        _audioTitles
          ..clear()
          ..addAll(titles);
        _audioArtists
          ..clear()
          ..addAll(artists);
        _audioPaths
          ..clear()
          ..addAll(paths);
        _audioSizes
          ..clear()
          ..addAll(sizes);
        _audioArtworkIds
          ..clear()
          ..addAll(artworkIds);
        _deviceAudioLoaded = true;
        _loadingAudio = false;
        _audioAccessDenied = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Attachment picker could not load device audio: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loadingAudio = false;
        _audioLoadFailed = true;
      });
    }
  }

  Future<void> _refreshAudioPermissionState() async {
    try {
      final permission = await PhotoLibraryPermissionService.instance
          .ensureAudioAccess(requestIfNeeded: false);
      if (!mounted || !permission.hasAccess) return;
      setState(() => _audioAccessDenied = false);
      await _loadDeviceAudio();
    } catch (_) {
      // Returning from system settings should never close the attachment UI.
    }
  }

  Widget _fileSubpageBackButton({required VoidCallback onBack}) {
    final layout = _layout;
    return Semantics(
      button: true,
      label: 'Back to files',
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                onBack();
              },
              splashFactory: NoSplash.splashFactory,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF17191E).withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: SizedBox.square(
                  dimension: layout.headerControlSize,
                  child: wrytteSvgAssetIcon(
                    assetPath: 'assets/svg/ic--round-arrow-back-ios.svg',
                    canvas: 26 * layout.scale,
                    color: WrytteColors.textPrimary,
                    scale: 1.0,
                    offset: const Offset(-0.5, 0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileSearchButton({
    String semanticsLabel = 'Search files',
    VoidCallback? onPressed,
  }) {
    final layout = _layout;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                if (onPressed != null) {
                  onPressed();
                } else {
                  unawaited(
                    _pickFileForTab(FileType.any, dialogTitle: 'Choose a file'),
                  );
                }
              },
              splashFactory: NoSplash.splashFactory,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF17191E).withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: SizedBox.square(
                  dimension: layout.headerControlSize,
                  child: Center(
                    child: wrytteSvgAssetIcon(
                      assetPath: 'assets/svg/Search icon.svg',
                      canvas: 23 * layout.scale,
                      color: WrytteColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileHeaderActions() {
    final layout = _layout;
    final selectedCount = _selectedFiles.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: selectedCount == 0
              ? const SizedBox.shrink(
                  key: ValueKey<String>('file-selection-empty'),
                )
              : Container(
                  key: ValueKey<int>(selectedCount),
                  width: 40 * layout.scale,
                  height: 40 * layout.scale,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: WrytteColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$selectedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
        if (selectedCount > 0) SizedBox(width: 14 * layout.scale),
        _fileSearchButton(),
      ],
    );
  }

  Widget _audioHeaderActions() {
    final layout = _layout;
    final selectedCount = _selectedAssets.length + _selectedFiles.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: selectedCount == 0
              ? const SizedBox.shrink(
                  key: ValueKey<String>('audio-selection-empty'),
                )
              : Container(
                  key: ValueKey<int>(selectedCount),
                  width: 40 * layout.scale,
                  height: 40 * layout.scale,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: WrytteColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$selectedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
        if (selectedCount > 0) SizedBox(width: 14 * layout.scale),
        _fileSearchButton(
          semanticsLabel: 'Browse audio files',
          onPressed: () => unawaited(
            _pickFileForTab(FileType.audio, dialogTitle: 'Choose audio'),
          ),
        ),
      ],
    );
  }

  Future<void> _openStorageAccessFramework() =>
      _pickFileForTab(FileType.any, dialogTitle: 'Internal storage');

  Future<void> _pickFileForTab(FileType type, {String? dialogTitle}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: type,
        dialogTitle: dialogTitle,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result.isEmpty) return;

      final picked = result.single;
      final path = picked.path?.trim() ?? '';
      if (path.isEmpty) return;

      final extension = (picked.extension ?? '').trim().toLowerCase();
      // Everything chosen from the File page is intentionally sent as a
      // document. In particular, Gallery here means original-quality media,
      // not the compressed image/video flow used by the Gallery tab.
      const attachmentType = 'file';
      final recent = _RecentAttachmentFile(
        path: path,
        name: picked.name,
        attachmentType: attachmentType,
        size: await File(path).length(),
        extension: extension,
      );
      _recentFiles.removeWhere((item) => item.path == path);
      _recentFiles.insert(0, recent);
      if (_recentFiles.length > 12) {
        _recentFiles.removeRange(12, _recentFiles.length);
      }
      setState(() {
        _selectedFiles.removeWhere((item) => item.path == path);
        final selectionCount = _selectedAssets.length + _selectedFiles.length;
        if (selectionCount < _maxSelectedMediaItems) {
          _selectedFiles.add(recent);
        }
      });
    } catch (_) {
      // Keep the sheet open if the native picker cannot be started.
    }
  }

  void _toggleRecentFile(_RecentAttachmentFile file) {
    if (_sendingSelection) return;
    if (!File(file.path).existsSync()) {
      setState(() {
        _recentFiles.removeWhere((item) => item.path == file.path);
        _selectedFiles.removeWhere((item) => item.path == file.path);
      });
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      final selectedIndex = _selectedFiles.indexWhere(
        (item) => item.path == file.path,
      );
      if (selectedIndex < 0) {
        if (_selectedFiles.length >= _maxSelectedMediaItems) return;
        _selectedFiles.add(file);
      } else {
        _selectedFiles.removeAt(selectedIndex);
        if (_selectedFiles.isEmpty && _selectedAssets.isEmpty) {
          _captionFocusNode.unfocus();
          _captionController.clear();
        }
      }
    });
  }

  Future<ChatPickedAttachment> _attachmentForPickedFile(
    _RecentAttachmentFile pickedFile,
  ) async {
    if (!isAudioMetadataFile(pickedFile.path)) {
      return ChatPickedAttachment(
        filePath: pickedFile.path,
        attachmentType: 'file',
      );
    }

    final metadata = await readAudioFileMetadata(
      filePath: pickedFile.path,
      fallbackFileName: pickedFile.name,
    );

    return ChatPickedAttachment(
      filePath: pickedFile.path,
      attachmentType: 'file',
      audioTitle: metadata?.title,
      audioArtist: metadata?.artist,
      audioArtworkPath: metadata?.artworkPath,
      audioDurationSeconds: metadata?.durationSeconds,
    );
  }

  Future<void> _sendSelectedFiles() async {
    if (_selectedFiles.isEmpty || _sendingSelection) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _sendingSelection = true);

    final selectedFiles = <ChatPickedAttachment>[];
    for (final file in _selectedFiles.take(_maxSelectedMediaItems)) {
      if (!File(file.path).existsSync()) continue;
      selectedFiles.add(await _attachmentForPickedFile(file));
    }
    if (!mounted) return;
    if (selectedFiles.isEmpty) {
      setState(() => _sendingSelection = false);
      return;
    }

    final caption = _captionController.text.trim();
    widget.onSelected(
      _AttachmentSelection.media(
        media: selectedFiles,
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  Future<void> _sendSelectedAudio() async {
    if ((_selectedAssets.isEmpty && _selectedFiles.isEmpty) ||
        _sendingSelection) {
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    setState(() => _sendingSelection = true);

    final selectedAudio = <ChatPickedAttachment>[];
    final selectedPaths = <String>{};
    for (final asset in List<AssetEntity>.of(_selectedAssets)) {
      final indexedPath = _audioPaths[asset.id];
      final file = indexedPath == null
          ? await asset.originFile ?? await asset.file
          : File(indexedPath);
      if (file == null || !await file.exists()) continue;
      if (!selectedPaths.add(file.path)) continue;
      final artworkPath = await _cacheSelectedAudioArtwork(asset);
      selectedAudio.add(
        ChatPickedAttachment(
          filePath: file.path,
          attachmentType: 'file',
          audioTitle: _audioTitles[asset.id] ?? asset.title,
          audioArtist: _audioArtists[asset.id],
          audioArtworkPath: artworkPath,
          audioDurationSeconds: asset.duration,
        ),
      );
      if (selectedAudio.length >= _maxSelectedMediaItems) break;
    }
    if (selectedAudio.length < _maxSelectedMediaItems) {
      for (final audio in _selectedFiles) {
        if (!File(audio.path).existsSync() || !selectedPaths.add(audio.path)) {
          continue;
        }
        selectedAudio.add(await _attachmentForPickedFile(audio));
        if (selectedAudio.length >= _maxSelectedMediaItems) break;
      }
    }

    if (!mounted) return;
    if (selectedAudio.isEmpty) {
      setState(() => _sendingSelection = false);
      return;
    }
    final caption = _captionController.text.trim();
    widget.onSelected(
      _AttachmentSelection.media(
        media: selectedAudio,
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  Future<String?> _cacheSelectedAudioArtwork(AssetEntity asset) async {
    final artworkId = _audioArtworkIds[asset.id];
    if (artworkId == null) return null;
    try {
      final bytes = await _deviceAudioQuery.queryArtwork(
        artworkId,
        ArtworkType.AUDIO,
        size: 256,
        quality: 88,
      );
      if (bytes == null || bytes.isEmpty) return null;
      final directory = await getTemporaryDirectory();
      final file = File(
        p.join(directory.path, 'wrytte_audio_artwork_$artworkId.jpg'),
      );
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendCurrentAttachmentSelection() {
    if (_selectedContacts.isNotEmpty) return _sendSelectedContacts();
    if (_fileAudioMode) return _sendSelectedAudio();
    if (_selectedFiles.isNotEmpty) return _sendSelectedFiles();
    return _sendSelectedAssets();
  }

  Future<void> _sendSelectedContacts() async {
    if (_selectedContacts.isEmpty || _sendingSelection) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _sendingSelection = true);
    final caption = _captionController.text.trim();
    widget.onSelected(
      _AttachmentSelection.contacts(
        contacts: List<Contact>.of(_selectedContacts),
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  String _fileSizeLabel(_RecentAttachmentFile file) {
    final bytes = file.size;
    return bytes >= 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : bytes >= 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '$bytes B';
  }

  Color _fileBadgeColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFE51F4B);
      case 'doc':
      case 'docx':
        return const Color(0xFF3979E9);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF299968);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFE06A32);
      case 'zip':
      case 'rar':
      case '7z':
        return const Color(0xFFB38438);
      default:
        return const Color(0xFF777C82);
    }
  }

  Widget _fileTypeBadge(_RecentAttachmentFile file) {
    final layout = _layout;
    final rawExtension = file.extension.trim().toUpperCase();
    final extension = rawExtension.isEmpty
        ? 'FILE'
        : rawExtension == 'JPEG'
        ? 'JPG'
        : rawExtension.length > 4
        ? rawExtension.substring(0, 4)
        : rawExtension;
    return SizedBox(
      width: 30 * layout.scale,
      height: 38 * layout.scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FileBadgePainter(_fileBadgeColor(file.extension)),
            ),
          ),
          Positioned(
            left: 3,
            right: 3,
            bottom: 8,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                extension,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 9.5 * layout.scale,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentFileRow(_RecentAttachmentFile file) {
    final layout = _layout;
    final selectedIndex = _selectedFiles.indexWhere(
      (item) => item.path == file.path,
    );
    final isSelected = selectedIndex >= 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _toggleRecentFile(file);
        },
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: layout.fileRowHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.listHorizontalPadding,
            ),
            child: Row(
              children: [
                _fileTypeBadge(file),
                SizedBox(width: 13 * layout.scale),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: WrytteColors.textPrimary,
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 14 + layout.progress,
                          height: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 7 * layout.scale),
                      Text(
                        _fileSizeLabel(file),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(
                            0xFFC6C6C6,
                          ).withValues(alpha: 0.65),
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 18 * layout.scale),
                Container(
                  width: 22 + (2 * layout.progress),
                  height: 22 + (2 * layout.progress),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? WrytteColors.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? WrytteColors.primary
                          : Colors.white.withValues(alpha: 0.52),
                      width: 1.3,
                    ),
                  ),
                  child: isSelected
                      ? Text(
                          '${selectedIndex + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 13,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileShortcut({
    required String iconAsset,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final layout = _layout;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: layout.fileShortcutHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.listHorizontalPadding,
            ),
            child: Row(
              children: [
                wrytteSvgAssetIcon(
                  assetPath: iconAsset,
                  canvas: 29 * layout.scale,
                  color: WrytteColors.primary,
                ),
                SizedBox(width: 15 * layout.scale),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: WrytteColors.textPrimary,
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 15 + layout.progress,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 7 * layout.scale),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(
                            0xFFC6C6C6,
                          ).withValues(alpha: 0.72),
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filePage(ScrollController scrollController) {
    final layout = _layout;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ColoredBox(
      color: WrytteColors.surfaceRaised,
      child: CustomScrollView(
        key: const ValueKey<String>('file-page'),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: layout.headerHeight + 4)),
          SliverToBoxAdapter(
            child: _fileShortcut(
              iconAsset: 'assets/svg/Storage icon.svg',
              title: 'Internal storage',
              description: 'Browse your system files',
              onTap: () => unawaited(_openStorageAccessFramework()),
            ),
          ),
          SliverToBoxAdapter(
            child: _fileShortcut(
              iconAsset: 'assets/svg/Gallery icon Blue.svg',
              title: 'Gallery',
              description: 'Send original-quality photos or videos',
              onTap: _openFileGallery,
            ),
          ),
          SliverToBoxAdapter(
            child: _fileShortcut(
              iconAsset: 'assets/svg/Audio icon.svg',
              title: 'Audio',
              description: 'Select audio or music files',
              onTap: _openFileAudio,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.listHorizontalPadding,
                15 * layout.scale,
                layout.listHorizontalPadding,
                9 * layout.scale,
              ),
              child: Text(
                'Recent files',
                style: TextStyle(
                  color: WrytteColors.textSecondary.withValues(alpha: 0.72),
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_recentFiles.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, index) => _recentFileRow(_recentFiles[index]),
                childCount: _recentFiles.length,
              ),
            )
          else
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.listHorizontalPadding,
                  10 * layout.scale,
                  layout.listHorizontalPadding,
                  layout.bottomNavHeight + 16 + bottomInset,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    'Choose a source above to browse files',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: WrytteColors.textSecondary.withValues(alpha: 0.48),
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          if (_recentFiles.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: layout.bottomNavHeight + 16 + bottomInset,
              ),
            ),
        ],
      ),
    );
  }

  String _audioDurationLabel(AssetEntity asset) {
    final totalSeconds = asset.duration.clamp(0, 359999).toInt();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60).remainder(60);
    final seconds = totalSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _audioSizeLabel(AssetEntity asset) {
    final bytes = _audioSizes[asset.id] ?? 0;
    if (bytes <= 0) return '0 MB';
    final megabytes = bytes / (1024 * 1024);
    final precision = megabytes >= 10 ? 0 : 1;
    return '${megabytes.toStringAsFixed(precision)} MB';
  }

  Future<void> _toggleAudioListPreview(AssetEntity asset) async {
    final isCurrent = _playingAudioAssetId == asset.id;
    if (isCurrent && _audioListPlayerState == PlayerState.playing) {
      await _audioListPreviewPlayer.pause();
      return;
    }
    if (isCurrent && _audioListPlayerState == PlayerState.paused) {
      await _audioListPreviewPlayer.resume();
      return;
    }

    final path = _audioPaths[asset.id];
    if (path == null || path.isEmpty || !File(path).existsSync()) return;
    final Source source = DeviceFileSource(path);

    await _audioListPreviewPlayer.stop();
    if (!mounted) return;
    setState(() => _playingAudioAssetId = asset.id);
    try {
      await _audioListPreviewPlayer.play(source);
    } catch (error) {
      debugPrint('Could not preview audio file: $error');
      if (!mounted) return;
      setState(() {
        _playingAudioAssetId = null;
        _audioListPlayerState = PlayerState.stopped;
      });
    }
  }

  Future<Uint8List?> _loadAudioArtwork(int artworkId) {
    return _audioArtworkFutures.putIfAbsent(artworkId, () async {
      try {
        return await _deviceAudioQuery.queryArtwork(
          artworkId,
          ArtworkType.AUDIO,
          size: 256,
          quality: 90,
        );
      } catch (_) {
        return null;
      }
    });
  }

  Widget _audioArtworkWithOverlay(
    AssetEntity asset, {
    required bool isPlaying,
  }) {
    final artworkId = _audioArtworkIds[asset.id];
    final fallback = ColoredBox(
      color: WrytteColors.textPrimary,
      child: Center(
        child: wrytteSvgAssetIcon(
          assetPath: 'assets/svg/Audio icon.svg',
          canvas: 27,
          color: WrytteColors.primary,
          offset: const Offset(-1.5, -0.7),
        ),
      ),
    );
    Widget buildArtwork(Uint8List? bytes) {
      if (bytes == null || bytes.isEmpty) return fallback;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.34)),
          _audioPreviewGlyph(isPlaying: isPlaying, color: Colors.white),
        ],
      );
    }

    if (artworkId == null) return buildArtwork(null);
    return FutureBuilder<Uint8List?>(
      future: _loadAudioArtwork(artworkId),
      builder: (_, snapshot) => buildArtwork(snapshot.data),
    );
  }

  Widget _audioPreviewGlyph({required bool isPlaying, required Color color}) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey<bool>(isPlaying),
          size: 27,
          color: color,
        ),
      ),
    );
  }

  Widget _audioPreviewButton(AssetEntity asset) {
    final layout = _layout;
    final isPlaying =
        _playingAudioAssetId == asset.id &&
        _audioListPlayerState == PlayerState.playing;
    return Semantics(
      button: true,
      label: isPlaying ? 'Pause audio preview' : 'Play audio preview',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_toggleAudioListPreview(asset)),
        child: SizedBox.square(
          dimension: 42 + (4 * layout.progress),
          child: ClipOval(
            child: _audioArtworkWithOverlay(asset, isPlaying: isPlaying),
          ),
        ),
      ),
    );
  }

  Widget _audioSelectionIndicator(int selectedIndex, {int numberOffset = 0}) {
    final layout = _layout;
    final isSelected = selectedIndex >= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 22 + (2 * layout.progress),
      height: 22 + (2 * layout.progress),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? WrytteColors.primary : Colors.transparent,
        border: Border.all(
          color: isSelected
              ? WrytteColors.primary
              : Colors.white.withValues(alpha: 0.52),
          width: 1.3,
        ),
      ),
      child: isSelected
          ? Text(
              '${selectedIndex + 1 + numberOffset}',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  Widget _deviceAudioRow(AssetEntity asset) {
    final layout = _layout;
    final selectedIndex = _selectedAssets.indexOf(asset);
    final title = _audioTitles[asset.id] ?? asset.title ?? 'Audio file';
    final artist = _audioArtists[asset.id]?.trim() ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleAssetSelection(asset),
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: artist.isEmpty
              ? 62 + (6 * layout.progress)
              : 68 + (6 * layout.progress),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.listHorizontalPadding,
            ),
            child: Row(
              children: [
                _audioPreviewButton(asset),
                SizedBox(width: 10 * layout.scale),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (artist.isEmpty)
                        Text(
                          title,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WrytteColors.textPrimary,
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 15.5,
                            height: 1.05,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: title,
                                style: const TextStyle(
                                  color: WrytteColors.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextSpan(
                                text: '  •  ',
                                style: TextStyle(
                                  color: const Color(
                                    0xFFC6C6C6,
                                  ).withValues(alpha: 0.72),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: artist,
                                style: TextStyle(
                                  color: const Color(
                                    0xFFC6C6C6,
                                  ).withValues(alpha: 0.72),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: WrytteTypography.primaryFontFamily,
                            height: 1.05,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: _audioDurationLabel(asset)),
                            const TextSpan(
                              text: ' • ',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: _audioSizeLabel(asset)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(
                            0xFFC6C6C6,
                          ).withValues(alpha: 0.66),
                          fontFamily: WrytteTypography.primaryFontFamily,
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 18 * layout.scale),
                _audioSelectionIndicator(
                  selectedIndex,
                  numberOffset: _selectedFiles.length,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioEmptyState({
    required IconData icon,
    required String title,
    required String detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 90, 28, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: WrytteColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WrytteColors.textPrimary,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WrytteColors.textSecondary.withValues(alpha: 0.64),
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: WrytteColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _audioPage(ScrollController scrollController) {
    final layout = _layout;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    if (_loadingAudio && _audioAssets.isEmpty) {
      return const ColoredBox(
        key: ValueKey<String>('audio-loading'),
        color: WrytteColors.surfaceRaised,
        child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: WrytteColors.primary,
            ),
          ),
        ),
      );
    }
    if (_audioAccessDenied) {
      return ColoredBox(
        key: const ValueKey<String>('audio-permission-denied'),
        color: WrytteColors.surfaceRaised,
        child: _audioEmptyState(
          icon: Icons.music_off_rounded,
          title: 'Audio access is off',
          detail:
              'Allow audio access to browse music and recordings on this device.',
          actionLabel: 'Open settings',
          onAction: () => unawaited(PhotoManager.openSetting()),
        ),
      );
    }
    if (_audioLoadFailed) {
      return ColoredBox(
        key: const ValueKey<String>('audio-load-failed'),
        color: WrytteColors.surfaceRaised,
        child: _audioEmptyState(
          icon: Icons.refresh_rounded,
          title: 'Audio could not be loaded',
          detail: 'Check device access, then try again.',
          actionLabel: 'Try again',
          onAction: () => unawaited(_loadDeviceAudio()),
        ),
      );
    }
    if (_audioAssets.isEmpty) {
      return ColoredBox(
        key: const ValueKey<String>('audio-empty'),
        color: WrytteColors.surfaceRaised,
        child: _audioEmptyState(
          icon: Icons.audio_file_rounded,
          title: 'No audio found',
          detail:
              'Music and recordings indexed by the device will appear here.',
          actionLabel: 'Browse files',
          onAction: () => unawaited(
            _pickFileForTab(FileType.audio, dialogTitle: 'Choose audio'),
          ),
        ),
      );
    }

    return ColoredBox(
      key: const ValueKey<String>('audio-page'),
      color: WrytteColors.surfaceRaised,
      child: CustomScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: layout.headerHeight + 10)),
          if (_selectedFiles.isNotEmpty) ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, index) => _recentFileRow(_selectedFiles[index]),
                childCount: _selectedFiles.length,
              ),
            ),
            SliverToBoxAdapter(
              child: Divider(
                height: 12,
                thickness: 0.7,
                indent: 20,
                endIndent: 20,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ],
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) => _deviceAudioRow(_audioAssets[index]),
              childCount: _audioAssets.length,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: layout.bottomNavHeight + 16 + bottomInset),
          ),
        ],
      ),
    );
  }

  Widget _pollField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) {
    final layout = _layout;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : 1,
      textInputAction: textInputAction,
      style: TextStyle(
        color: const Color(0xFFE9EBEF),
        fontFamily: WrytteTypography.primaryFontFamily,
        fontSize: 15 + layout.progress,
        height: 1.2,
      ),
      cursorColor: const Color(0xFF6DAAFF),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: const Color(0xFF5D616A),
          fontFamily: WrytteTypography.primaryFontFamily,
          fontSize: 15 + layout.progress,
          height: 1.2,
        ),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(
          horizontal: layout.bodyHorizontalPadding,
          vertical: 14 + layout.progress,
        ),
        isDense: true,
      ),
    );
  }

  Widget _pollGlassGroup({required Widget child, bool navbarStyle = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: navbarStyle
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.48, 1.0],
                    colors: [
                      Color.fromRGBO(26, 29, 37, 0.44),
                      Color.fromRGBO(15, 18, 25, 0.36),
                      Color.fromRGBO(8, 10, 15, 0.30),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.fromRGBO(24, 27, 34, 0.66),
                      Color.fromRGBO(14, 17, 23, 0.52),
                    ],
                  ),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: Colors.white.withValues(alpha: navbarStyle ? 0.09 : 0.055),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  void _onPollOptionChanged(int index, String value) {
    if (index == _pollOptionControllers.length - 1 && value.trim().isNotEmpty) {
      setState(() {
        _pollOptionControllers.add(TextEditingController());
      });
      return;
    }
    setState(() {});
  }

  Widget _pollOptionsEditor() {
    final layout = _layout;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _pollOptionControllers.length,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final progress = Curves.easeOutCubic.transform(animation.value);
            return Material(
              color: Colors.transparent,
              elevation: 10 * progress,
              shadowColor: Colors.black.withValues(alpha: 0.72 * progress),
              borderRadius: BorderRadius.circular(19),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF20242B),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14 * progress),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42 * progress),
                      blurRadius: 24 * progress,
                      spreadRadius: 2 * progress,
                      offset: Offset(0, 10 * progress),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) {
        final addOptionIndex = _pollOptionControllers.length - 1;
        if (oldIndex >= addOptionIndex || newIndex > addOptionIndex) {
          return;
        }
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final controller = _pollOptionControllers.removeAt(oldIndex);
          _pollOptionControllers.insert(newIndex, controller);
        });
      },
      itemBuilder: (context, index) {
        final controller = _pollOptionControllers[index];
        final isAddOptionField = index == _pollOptionControllers.length - 1;
        final field = _pollField(
          controller: controller,
          hint: isAddOptionField ? 'Add an option' : 'Option',
          textInputAction: TextInputAction.next,
          onChanged: (value) => _onPollOptionChanged(index, value),
        );
        final dragHandle = IgnorePointer(
          // Keep this widget in every row so adding a new option does not
          // rebuild the focused TextField. The placeholder handle is hidden
          // and disabled, while completed options can be dragged from it.
          ignoring: isAddOptionField,
          child: Opacity(
            opacity: isAddOptionField ? 0 : 1,
            child: ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 38 + (4 * layout.progress),
                height: 46 + (4 * layout.progress),
                child: Center(
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Divider(color: Color(0xFF8E949E), height: 3),
                      ),
                      SizedBox(
                        width: 20,
                        child: Divider(color: Color(0xFF8E949E), height: 3),
                      ),
                      SizedBox(
                        width: 20,
                        child: Divider(color: Color(0xFF8E949E), height: 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final row = Column(
          children: [
            Row(
              children: [
                Expanded(child: field),
                dragHandle,
              ],
            ),
            if (!isAddOptionField)
              Divider(
                height: 1,
                indent: 17,
                endIndent: 17,
                color: Colors.white.withValues(alpha: 0.055),
              ),
          ],
        );
        // Keep the same widget structure for the trailing Add field as the
        // normal options. This preserves keyboard focus when it becomes an
        // option after the first character is typed.
        return KeyedSubtree(
          key: ValueKey<TextEditingController>(controller),
          child: row,
        );
      },
    );
  }

  Widget _pollPage(ScrollController scrollController) {
    final layout = _layout;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return SizedBox.expand(
      key: const ValueKey<String>('poll-page'),
      child: ColoredBox(
        color: WrytteColors.surfaceRaised,
        child: SingleChildScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            layout.bodyHorizontalPadding,
            layout.headerHeight + 12,
            layout.bodyHorizontalPadding,
            layout.bottomNavHeight + 56 + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Text(
                  'Question',
                  style: TextStyle(
                    color: Color(0xFF9A9DA5),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              _pollGlassGroup(
                child: Column(
                  children: [
                    _pollField(
                      controller: _pollQuestionController,
                      hint: 'Ask question',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                    Divider(
                      height: 1,
                      indent: 17,
                      endIndent: 17,
                      color: Colors.white.withValues(alpha: 0.055),
                    ),
                    _pollField(
                      controller: _pollDescriptionController,
                      hint: 'Add description (optional)',
                      maxLines: 2,
                      textInputAction: TextInputAction.newline,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Text(
                  'Options',
                  style: TextStyle(
                    color: Color(0xFF9A9DA5),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              _pollGlassGroup(child: Column(children: [_pollOptionsEditor()])),
              const SizedBox(height: 24),
              _pollGlassGroup(
                navbarStyle: true,
                child: SizedBox(
                  height: 51 + (4 * layout.progress),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: layout.bodyHorizontalPadding,
                      right: 7 * layout.scale,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Allow multiple answers',
                            style: TextStyle(
                              color: Color(0xFFE0E2E7),
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 15 + layout.progress,
                            ),
                          ),
                        ),
                        Semantics(
                          label: 'Allow multiple answers',
                          toggled: _pollAllowsMultipleAnswers,
                          button: true,
                          child: GestureDetector(
                            onTap: () => setState(
                              () => _pollAllowsMultipleAnswers =
                                  !_pollAllowsMultipleAnswers,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 51 + (4 * layout.progress),
                              height: 30 + (2 * layout.progress),
                              padding: EdgeInsets.all(3 * layout.scale),
                              decoration: BoxDecoration(
                                color: _pollAllowsMultipleAnswers
                                    ? const Color(0xFF69A9FF)
                                    : const Color(0xFF383C45),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                alignment: _pollAllowsMultipleAnswers
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 24 + (2 * layout.progress),
                                  height: 24 + (2 * layout.progress),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF7F9FC),
                                    shape: BoxShape.circle,
                                  ),
                                  child: null,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactAvatar(Contact contact, {required double size}) {
    final avatarUrl = contact.avatarUrl?.trim() ?? '';
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: avatarUrl.isNotEmpty
            ? UserAvatar(
                size: size,
                imageUrl: avatarUrl,
                name: contact.formattedName.trim().isEmpty
                    ? 'Unnamed contact'
                    : contact.formattedName.trim(),
              )
            : Image.asset(
                'assets/images/default_pic.jpg',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }

  Widget _contactRow(
    Contact contact, {
    required WrytteAttachmentMetrics layout,
  }) {
    final selectedIndex = _selectedContacts.toList().indexOf(contact);
    final isSelected = selectedIndex >= 0;
    final avatarSize = layout.contactAvatarSize;
    final selectionSize = layout.contactSelectionSize;
    return Padding(
      padding: EdgeInsets.only(right: 4 * layout.scale),
      child: SizedBox(
        height: layout.contactRowHeight,
        child: Row(
          children: [
            SizedBox.square(
              dimension: avatarSize,
              child: _contactAvatar(contact, size: avatarSize),
            ),
            SizedBox(width: 10 + (2 * layout.progress)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.formattedName.trim().isEmpty
                        ? 'Unnamed contact'
                        : contact.formattedName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF1F3F6),
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: layout.contactNameSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selectionSize,
              height: selectionSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? WrytteColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? WrytteColors.primary
                      : Colors.white.withValues(alpha: 0.30),
                  width: 1.2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: wrytteSvgAssetIcon(
                        assetPath: 'assets/svg/Checkmark edit.svg',
                        canvas: 16 * layout.scale,
                        scale: 1,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactGroup(
    List<Contact> contacts, {
    required WrytteAttachmentMetrics layout,
  }) {
    return Column(
      children: [
        for (var i = 0; i < contacts.length; i++) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                if (!_selectedContacts.add(contacts[i])) {
                  _selectedContacts.remove(contacts[i]);
                }
              });
            },
            child: _contactRow(contacts[i], layout: layout),
          ),
          if (i < contacts.length - 1)
            Padding(
              padding: EdgeInsets.only(
                left: layout.contactAvatarSize + 24 + (2 * layout.progress),
                right: layout.bodyHorizontalPadding,
              ),
              child: Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
        ],
      ],
    );
  }

  Widget _contactsPage(ScrollController scrollController) {
    final layout = _layout;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final grouped = <String, List<Contact>>{};
    for (final contact in _deviceContacts) {
      final name = contact.formattedName.trim();
      final letter = name.isEmpty ? '#' : name.substring(0, 1).toUpperCase();
      final key = RegExp(r'[A-Z]').hasMatch(letter) ? letter : '#';
      grouped.putIfAbsent(key, () => <Contact>[]).add(contact);
    }
    final letters = grouped.keys.toList()..sort();
    final content = <Widget>[];
    for (var letterIndex = 0; letterIndex < letters.length; letterIndex++) {
      final letter = letters[letterIndex];
      content.add(
        Padding(
          padding: EdgeInsets.fromLTRB(
            0,
            9 + (4 * layout.progress),
            5 * layout.scale,
            4 + (2 * layout.progress),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                SizedBox(
                  width: layout.sectionLabelWidth,
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        color: const Color(0xFF9DA2AB),
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 13 + layout.progress,
                        height: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                if (letterIndex > 0)
                  Expanded(
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      content.add(_contactGroup(grouped[letter]!, layout: layout));
    }
    if (_loadingContacts) {
      content.add(
        const Padding(
          padding: EdgeInsets.only(top: 55),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF69A9FF),
            ),
          ),
        ),
      );
    } else if (_contactsAccessDenied) {
      content.add(
        const Padding(
          padding: EdgeInsets.only(top: 45, left: 18, right: 18),
          child: Text(
            'Allow contacts access to see people from your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB5BAC3), fontSize: 14),
          ),
        ),
      );
    } else if (_contactsLoaded && _deviceContacts.isEmpty) {
      content.add(
        const Padding(
          padding: EdgeInsets.only(top: 45),
          child: Center(
            child: Text(
              'No contacts found',
              style: TextStyle(color: Color(0xFFB5BAC3)),
            ),
          ),
        ),
      );
    }
    final sideLetters = const [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
    ];
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SizedBox.expand(
        child: ColoredBox(
          color: WrytteColors.surfaceRaised,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SingleChildScrollView(
                key: const ValueKey<String>('contacts-page'),
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  8 + (2 * layout.progress),
                  layout.headerHeight + 12,
                  layout.alphabetRailWidth + 17,
                  layout.bottomNavHeight + 42 + bottomInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
              Positioned(
                right: 3,
                top: layout.headerHeight + 22,
                bottom: layout.bottomNavHeight + 30 + bottomInset,
                child: SizedBox(
                  width: layout.alphabetRailWidth,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemExtent = math.min(
                        13.0,
                        constraints.maxHeight / sideLetters.length,
                      );
                      final letterSize = math.min(
                        10.5 + layout.progress,
                        math.max(7.0, itemExtent * 0.88),
                      );
                      return ListView.builder(
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sideLetters.length,
                        itemExtent: itemExtent,
                        itemBuilder: (_, index) => Center(
                          child: Text(
                            sideLetters[index],
                            style: TextStyle(
                              color: const Color(0xFF69A9FF),
                              fontSize: letterSize,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pollHeaderAction() {
    final canSend = _pollCanSend;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: const Color(0xFF171A20).withValues(alpha: 0.72),
            child: InkWell(
              onTap: () => unawaited(HapticFeedback.selectionClick()),
              borderRadius: BorderRadius.circular(21),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 17, vertical: 9),
                child: Text(
                  'Send',
                  style: TextStyle(
                    color: canSend
                        ? const Color(0xFFE6E8EC)
                        : const Color(0xFF777B84),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachmentContent(ScrollController scrollController) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.025, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _selectedAttachmentCategory == 1
          ? _fileAudioMode
                ? _audioPage(scrollController)
                : _fileGalleryMode
                ? KeyedSubtree(
                    key: const ValueKey<String>('file-gallery-page'),
                    child: _mediaGrid(scrollController),
                  )
                : _filePage(scrollController)
          : _selectedAttachmentCategory == 2
          ? ChatLocationPicker(scrollController: scrollController)
          : _selectedAttachmentCategory == 3
          ? _pollPage(scrollController)
          : _selectedAttachmentCategory == 4
          ? _contactsPage(scrollController)
          : KeyedSubtree(
              key: const ValueKey<String>('gallery-page'),
              child: _mediaGrid(scrollController),
            ),
    );
  }

  Widget _selectionComposer() {
    final layout = _layout;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasSelection =
        _selectedAssets.isNotEmpty ||
        _selectedFiles.isNotEmpty ||
        _selectedContacts.isNotEmpty;
    final canConfirm = hasSelection && !_sendingSelection;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        left: false,
        top: false,
        right: false,
        maintainBottomViewPadding: true,
        minimum: EdgeInsets.only(bottom: 10 * layout.scale),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.bodyHorizontalPadding,
            8 * layout.scale,
            layout.bodyHorizontalPadding,
            0,
          ),
          child: Row(
            children: [
              if (!widget.playlistMode)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      layout.composerControlSize / 2,
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0, 0.48, 1],
                            colors: [
                              Color.fromRGBO(30, 33, 41, 0.62),
                              Color.fromRGBO(17, 20, 27, 0.52),
                              Color.fromRGBO(8, 10, 15, 0.46),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(
                            layout.composerControlSize / 2,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.11),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.34),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.035),
                              blurRadius: 1,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          height: layout.composerControlSize,
                          child: Row(
                            children: [
                              if (widget.replacementMode &&
                                  _selectedAssets.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 5),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: SizedBox.square(
                                      dimension:
                                          layout.composerControlSize - 10,
                                      child: Image(
                                        image: AssetEntityImageProvider(
                                          _selectedAssets.first,
                                          isOriginal: false,
                                          thumbnailSize:
                                              const ThumbnailSize.square(160),
                                        ),
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: TextField(
                                  controller: _captionController,
                                  focusNode: _captionFocusNode,
                                  enabled: !_sendingSelection,
                                  expands: true,
                                  minLines: null,
                                  maxLines: null,
                                  textInputAction: TextInputAction.done,
                                  textAlignVertical: TextAlignVertical.center,
                                  onSubmitted: (_) {
                                    if (canConfirm) {
                                      unawaited(
                                        _sendCurrentAttachmentSelection(),
                                      );
                                    }
                                  },
                                  cursorColor: const Color(0xFF2978FF),
                                  cursorWidth: 1.5,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily:
                                        WrytteTypography.primaryFontFamily,
                                    fontSize: 16 + layout.progress,
                                    height: 1,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    hintText: widget.replacementMode
                                        ? 'Add caption'
                                        : 'Add a caption...',
                                    hintStyle: TextStyle(
                                      color: const Color(
                                        0xFFC6C6C6,
                                      ).withValues(alpha: 0.72),
                                      fontFamily:
                                          WrytteTypography.primaryFontFamily,
                                      fontSize: 16 + layout.progress,
                                      height: 1,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal:
                                          widget.replacementMode &&
                                              _selectedAssets.isNotEmpty
                                          ? 9 + layout.progress
                                          : 14 + (3 * layout.progress),
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
              if (!widget.playlistMode) SizedBox(width: 9 * layout.scale),
              if (widget.playlistMode) const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: canConfirm
                    ? () => unawaited(_sendCurrentAttachmentSelection())
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: layout.composerControlSize,
                  height: layout.composerControlSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF4DA3FF,
                    ).withValues(alpha: canConfirm ? 1 : 0.58),
                    shape: BoxShape.circle,
                  ),
                  child: _sendingSelection
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : widget.playlistMode || widget.replacementMode
                      ? wrytteSvgAssetIcon(
                          assetPath: 'assets/svg/Checkmark edit.svg',
                          canvas: 27 * layout.scale,
                          scale: 1,
                          color: Colors.white,
                        )
                      : Transform.translate(
                          offset: const Offset(-1.5, 0),
                          child: Transform.rotate(
                            angle: math.pi / 4,
                            child: wrytteSvgAssetIcon(
                              assetPath: 'assets/svg/Send icon .svg',
                              canvas: 28 * layout.scale,
                              scale: 1.12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomCategories() {
    final layout = _layout;
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.bottomNavHorizontalInset,
          8 * layout.scale,
          layout.bottomNavHorizontalInset,
          0,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(layout.bottomNavHeight / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: wrytteGlassDecoration(
                radius: layout.bottomNavHeight / 2,
              ),
              child: SizedBox(
                height: layout.bottomNavHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth / 5;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 420),
                          curve: const Cubic(0.22, 1, 0.36, 1),
                          left: (_selectedAttachmentCategory * itemWidth) + 2,
                          top: 3,
                          bottom: 3,
                          width: itemWidth - 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              (layout.bottomNavHeight - 6) / 2,
                            ),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF23262C,
                                  ).withValues(alpha: 0.78),
                                  borderRadius: BorderRadius.circular(
                                    (layout.bottomNavHeight - 6) / 2,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.07),
                                    width: 0.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.24,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _categoryItem(
                              iconAsset: 'assets/svg/Gallery icon.svg',
                              selectedIconAsset:
                                  'assets/svg/Galley icon tapped.svg',
                              label: 'Gallery',
                              layout: layout,
                              selected: _selectedAttachmentCategory == 0,
                              onTap: () => _selectAttachmentCategory(0),
                            ),
                            _categoryItem(
                              iconAsset: 'assets/svg/File icon.svg',
                              selectedIconAsset:
                                  'assets/svg/File icon tapped.svg',
                              label: 'File',
                              layout: layout,
                              selected: _selectedAttachmentCategory == 1,
                              onTap: () => _selectAttachmentCategory(1),
                            ),
                            _categoryItem(
                              iconAsset: 'assets/svg/Location icon.svg',
                              selectedIconAsset:
                                  'assets/svg/Location icon tapped.svg',
                              label: 'Location',
                              layout: layout,
                              selected: _selectedAttachmentCategory == 2,
                              onTap: () => _selectAttachmentCategory(2),
                            ),
                            _categoryItem(
                              iconAsset: 'assets/svg/Poll icon.svg',
                              selectedIconAsset:
                                  'assets/svg/Poll icon tapped.svg',
                              label: 'Poll',
                              layout: layout,
                              selected: _selectedAttachmentCategory == 3,
                              onTap: () => _selectAttachmentCategory(3),
                            ),
                            _categoryItem(
                              iconAsset: 'assets/svg/Contact icon.svg',
                              selectedIconAsset:
                                  'assets/svg/Contact icon tapped.svg',
                              label: 'Contact',
                              layout: layout,
                              selected: _selectedAttachmentCategory == 4,
                              onTap: () => _selectAttachmentCategory(4),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachmentHeader() {
    final layout = _layout;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _sheetExpansionProgress,
        _galleryScrollProgress,
      ]),
      builder: (context, child) {
        final expansion = _sheetExpansionProgress.value;
        final galleryScroll = _galleryScrollProgress.value;
        final isFilePage =
            _selectedAttachmentCategory == 1 && !_fileGalleryMode;
        final isLocationPage = _selectedAttachmentCategory == 2;
        final isPollPage = _selectedAttachmentCategory == 3;
        final isContactsPage = _selectedAttachmentCategory == 4;
        final transitionInput = ((expansion - 0.48) / 0.40)
            .clamp(0.0, 1.0)
            .toDouble();
        final backgroundTransition = isLocationPage
            ? 1.0
            : isPollPage
            ? 0.0
            : isFilePage
            ? 0.0
            : Curves.easeInOutCubic.transform(transitionInput);
        final glassStrength = isLocationPage
            ? 1.0
            : isPollPage
            ? 0.0
            : isFilePage
            ? 0.0
            : math.max(backgroundTransition, galleryScroll);
        final blurStrength = isLocationPage
            ? 1.0
            : isPollPage
            ? 0.0
            : isFilePage
            ? 0.0
            : math.max(0.25 * expansion, glassStrength);
        final headerBlurSigma = isLocationPage || isPollPage ? 44.0 : 32.0;
        final headerGradientColors = isLocationPage
            ? const [
                Color.fromRGBO(25, 43, 61, 0.56),
                Color.fromRGBO(22, 39, 57, 0.50),
                Color.fromRGBO(19, 35, 52, 0.40),
                Color.fromRGBO(16, 31, 47, 0.27),
                Color.fromRGBO(13, 27, 42, 0.13),
                Color.fromRGBO(10, 22, 36, 0.04),
                Color.fromRGBO(10, 22, 36, 0),
              ]
            : const [
                Color.fromRGBO(2, 3, 5, 0.985),
                Color.fromRGBO(3, 4, 7, 0.960),
                Color.fromRGBO(5, 7, 10, 0.870),
                Color.fromRGBO(6, 8, 12, 0.650),
                Color.fromRGBO(6, 8, 12, 0.400),
                Color.fromRGBO(6, 8, 12, 0.120),
                Color.fromRGBO(6, 8, 12, 0),
              ];
        return SizedBox(
          height: layout.headerOverlayHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.44, 0.56, 0.68, 0.78, 0.85, 1],
                      colors: [
                        Colors.white.withValues(alpha: blurStrength),
                        Colors.white.withValues(alpha: blurStrength),
                        Colors.white.withValues(alpha: 0.82 * blurStrength),
                        Colors.white.withValues(alpha: 0.43 * blurStrength),
                        Colors.white.withValues(alpha: 0.12 * blurStrength),
                        Colors.transparent,
                        Colors.transparent,
                      ],
                    ).createShader(bounds),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: headerBlurSigma,
                        sigmaY: headerBlurSigma,
                        tileMode: TileMode.clamp,
                      ),
                      blendMode: BlendMode.srcOver,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: glassStrength,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.22, 0.44, 0.62, 0.76, 0.88, 1],
                          colors: headerGradientColors,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: layout.headerHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF23262C,
                    ).withValues(alpha: 1 - backgroundTransition),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (isLocationPage ? 0.10 : 0.30) * glassStrength,
                        ),
                        blurRadius: (isLocationPage ? 28 : 20) * glassStrength,
                        spreadRadius:
                            (isLocationPage ? 0.5 : 1.5) * glassStrength,
                        offset: Offset(0, 7 * glassStrength),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.headerHorizontalPadding,
                      10 * layout.scale,
                      layout.headerHorizontalPadding,
                      6 * layout.scale,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -1,
                          child: Container(
                            width: 56 * layout.scale,
                            height: 4 * layout.scale,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: 0.36 + (0.12 * expansion),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: widget.playlistMode
                              ? _closeButton()
                              : _fileGalleryMode || _fileAudioMode
                              ? _fileSubpageBackButton(
                                  onBack: _fileAudioMode
                                      ? _closeFileAudio
                                      : _closeFileGallery,
                                )
                              : _closeButton(),
                        ),
                        if (_fileGalleryMode)
                          _albumSelector()
                        else if (_fileAudioMode)
                          const Text(
                            'Audio',
                            style: TextStyle(
                              color: WrytteColors.textPrimary,
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 17,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (_selectedAttachmentCategory == 1)
                          const Text(
                            'File',
                            style: TextStyle(
                              color: WrytteColors.textPrimary,
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 17,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (_selectedAttachmentCategory == 2)
                          const Text(
                            'Location',
                            style: TextStyle(
                              color: WrytteColors.textPrimary,
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 17,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (_selectedAttachmentCategory == 3)
                          const Text(
                            'Poll',
                            style: TextStyle(
                              color: WrytteColors.textPrimary,
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 17,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (isContactsPage)
                          const Text(
                            'Contacts',
                            style: TextStyle(
                              color: WrytteColors.textPrimary,
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 17,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          _albumSelector(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: widget.profilePhotoMode
                              ? SizedBox.square(
                                  dimension: layout.headerControlSize,
                                )
                              : _fileGalleryMode
                              ? _selectionHeaderActions()
                              : _fileAudioMode
                              ? _audioHeaderActions()
                              : _selectedAttachmentCategory == 1
                              ? _fileHeaderActions()
                              : _selectedAttachmentCategory == 2
                              ? _locationHeaderAction()
                              : _selectedAttachmentCategory == 4
                              ? _contactsHeaderAction()
                              : _selectedAttachmentCategory == 3
                              ? _pollHeaderAction()
                              : _selectionHeaderActions(),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final sheet = DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _startingSheetSize,
      minChildSize: _minimumSheetSize,
      maxChildSize: _maximumSheetSize,
      snap: true,
      snapSizes: const [_initialSheetSize],
      snapAnimationDuration: const Duration(milliseconds: 320),
      shouldCloseOnMinExtent: false,
      builder: (context, scrollController) {
        _bindGalleryScrollController(scrollController);
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.sheetHorizontalInset,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(layout.sheetRadius),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.20,
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [WrytteColors.surfaceRaised, Color(0xFF07090C)],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(layout.sheetRadius),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.09),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: FadeTransition(
                            opacity: CurvedAnimation(
                              parent: _entranceController,
                              curve: const Interval(0.12, 1),
                            ),
                            child: _attachmentContent(scrollController),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: _draggableAttachmentHeader(),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            reverseDuration: const Duration(milliseconds: 210),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.16),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: widget.profilePhotoMode
                                ? const SizedBox.shrink(
                                    key: ValueKey<String>(
                                      'profile-gallery-bottom-empty',
                                    ),
                                  )
                                : _selectedAssets.isEmpty &&
                                      _selectedFiles.isEmpty &&
                                      _selectedContacts.isEmpty &&
                                      !widget.replacementMode
                                ? _fileGalleryMode || _fileAudioMode
                                      ? const SizedBox.shrink(
                                          key: ValueKey<String>(
                                            'file-subpage-bottom-empty',
                                          ),
                                        )
                                      : KeyedSubtree(
                                          key: const ValueKey<String>(
                                            'attachment-categories',
                                          ),
                                          child: _bottomCategories(),
                                        )
                                : KeyedSubtree(
                                    key: const ValueKey<String>(
                                      'attachment-caption',
                                    ),
                                    child: _selectionComposer(),
                                  ),
                          ),
                        ),
                        if ((_selectedAttachmentCategory == 0 ||
                                _fileGalleryMode) &&
                            _loadingMedia &&
                            _assets.isNotEmpty)
                          Positioned(
                            top: layout.headerHeight + 9,
                            right: 10,
                            child: const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: WrytteColors.textSecondary,
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
      },
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          key: const ValueKey('attachment-panel-dismiss-area'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _dismissAttachmentPanel(),
        ),
        sheet,
      ],
    );
  }
}

// ── Pulsing red dot (recording indicator) ─────────────────────────────────────
