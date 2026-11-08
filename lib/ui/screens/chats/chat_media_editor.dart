import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/enums/tilt_mode_enum.dart';
import 'package:pro_video_editor/pro_video_editor.dart' as pve;
import 'package:video_player/video_player.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/models/chat_models/ui/chat_media_editor_result.dart';
import 'package:wrytte/services/permissions/photo_library_permission_service.dart';
import 'package:wrytte/ui/screens/media/full_screen_image_viewer.dart';

export 'package:wrytte/models/chat_models/ui/chat_media_editor_result.dart';
part 'chat_media_editor_overlays.dart';

enum _TelegramTextBackgroundStyle { light, dark, transparent }

class ChatMediaEditorScreen extends StatefulWidget {
  final String sourcePath;
  final String attachmentType;
  final String recipientLabel;
  final String initialCaption;
  final int? selectionIndex;
  final int selectedCount;
  final bool showSelectionControl;

  // Exact media context from the attachment picker. Keeping IDs separate from
  // file paths is important because an edited image can use a temporary path
  // while still representing the same gallery asset.
  final List<String> mediaIds;
  final List<String> mediaPaths;
  final int initialMediaIndex;
  final List<String> initialSelectedMediaIds;

  // Camera captures use the exact same editor/media layout as gallery media.
  // This flag changes only the top-left navigation icon to Back.
  final bool openedFromCamera;
  final Object? openingImageHeroTag;
  final String? openingImageMediaId;
  final ImageProvider<Object>? openingHeroImageProvider;

  const ChatMediaEditorScreen({
    super.key,
    required this.sourcePath,
    required this.attachmentType,
    required this.recipientLabel,
    required this.initialCaption,
    required this.selectionIndex,
    required this.selectedCount,
    this.showSelectionControl = true,
    this.mediaIds = const <String>[],
    this.mediaPaths = const <String>[],
    this.initialMediaIndex = 0,
    this.initialSelectedMediaIds = const <String>[],
    this.openedFromCamera = false,
    this.openingImageHeroTag,
    this.openingImageMediaId,
    this.openingHeroImageProvider,
  });

  @override
  State<ChatMediaEditorScreen> createState() => _ChatMediaEditorScreenState();
}

class _ChatMediaEditorScreenState extends State<ChatMediaEditorScreen> {
  static const int _maxSelectedMediaItems = 30;
  static const Color _background = Color(0xFF050608);
  static const Color _sentBlue = WrytteColors.primary;
  static const double _editorCircleButtonSize = 42;
  static const double _composerControlHeight = 42;
  static const double _headerContentHeight = 64;
  static const double _bottomBarHeight = 107;
  static const double _videoTrimControlsHeight = 97;
  static const double _textToolbarHeight = 42;

  // Boss-approved filter screen design.
  // Keep the exact #23262C tone at 50% opacity. This is transparency only;
  // the filter panel still has no BackdropFilter or glass blur.
  static const Color _filterBottomBackground = Color(0x8023262C);

  // Intentionally brighter and more saturated than the previous tone so the
  // Done control remains visibly blue over dark images.
  static const Color _filterDoneBlue = Color(0xFF67C1FF);

  // Use a slightly wider filter slot so about 5.4 filters fit across the
  // viewport. The sixth frame intentionally peeks in from the right, giving
  // the row more breathing room while still hinting that it can be scrolled.
  static const double _filterVisibleItemCount = 5.4;
  // Taller because the wider 9:16 previews can reach ~114dp high.
  // 168dp leaves room for the label, 9dp gap and 12dp top/bottom padding
  // without a RenderFlex bottom overflow.
  static const double _filterBottomPanelHeight = 168;
  static const double _filterHorizontalPadding = 10;
  static const double _filterItemSpacing = 8;
  static const double _filterPreviewMinWidth = 46;
  static const double _filterPreviewMaxWidth = 58;

  static const FontWeight _typedTextWeight = FontWeight.normal;
  static const FontWeight _textHintWeight = FontWeight.w500;

  // Telegram-like text sizing range. The slider uses the editor's real
  // fontScale value so the editing preview and exported TextLayer stay equal.
  static const double _textFontScaleMin = 0.45;
  static const double _textFontScaleDefault = 1.0;
  static const double _textFontScaleMax = 3.0;

  // Telegram-style text background states. The toolbar's active grey is a
  // translucent light surface, while the text layer uses a soft black overlay.
  static const Color _textToolbarActiveGrey = Color(0x66FFFFFF);
  static const Color _textLayerDarkOverlay = Color(0x99000000);

  // Keep every text-editor icon sourced from assets/svg. The initial centered
  // state uses icon 1, then toggleTextAlign cycles to right and left.
  static const String _textAlignCenterSvg = 'assets/svg/Text alighn icon 1.svg';
  static const String _textAlignRightSvg = 'assets/svg/Text alighn icon 2.svg';
  static const String _textAlignLeftSvg = 'assets/svg/Text alighn icon 3.svg';
  static const String _textStickerEditSvg = 'assets/svg/Sticker icon edit.svg';

  // Font choices requested for the editor. The visible labels match the
  // provided reference, while each entry points to a concrete bundled family.
  //
  // Roboto and Pacifico are retained from the existing assets.
  // Italic uses Roboto Italic.
  // Serif uses Noto Serif.
  // Condensed uses Roboto Condensed.
  // Mono-serif uses Roboto Mono.
  // Merriweather uses Merriweather Regular.
  static const List<String> _textFontNames = <String>[
    'Roboto',
    'Italic',
    'Serif',
    'Condensed',
    'Mono-serif',
    'Merriweather',
    'Pacifico',
  ];

  static const List<TextStyle> _textFontPresets = <TextStyle>[
    TextStyle(
      fontFamily: WrytteTypography.primaryFontFamily,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    ),
    TextStyle(
      fontFamily: WrytteTypography.primaryFontFamily,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
    ),
    TextStyle(
      fontFamily: 'NotoSerif',
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    ),
    TextStyle(
      fontFamily: 'RobotoCondensed',
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    ),
    TextStyle(
      fontFamily: 'RobotoMono',
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    ),
    TextStyle(
      fontFamily: 'Merriweather',
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    ),
    TextStyle(
      fontFamily: 'Pacifico',
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    ),
  ];

  static const double _textEmojiPanelPreferredHeight = 342;

  static const List<String> _textEmojiCategoryNames = <String>[
    'Recent',
    'Smileys & People',
    'Animals & Nature',
    'Food & Drink',
    'Travel & Places',
    'Activities',
    'Objects',
    'Symbols',
  ];

  static const List<IconData> _textEmojiCategoryIcons = <IconData>[
    Icons.history_rounded,
    Icons.sentiment_satisfied_alt_rounded,
    Icons.cruelty_free_rounded,
    Icons.local_cafe_rounded,
    Icons.directions_car_filled_rounded,
    Icons.sports_soccer_rounded,
    Icons.lightbulb_outline_rounded,
    Icons.emoji_symbols_rounded,
  ];

  static const List<List<String>> _textEmojiCategories = <List<String>>[
    <String>[
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '🙃',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '☺️',
      '😚',
      '😙',
      '🥲',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🫢',
      '🫣',
    ],
    <String>[
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '🙃',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '☺️',
      '😚',
      '😙',
      '🥲',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🫢',
      '🫣',
      '🤫',
      '🤔',
      '🫡',
      '🤐',
      '🤨',
      '😐',
      '😑',
      '😶',
      '🫥',
      '😏',
      '😒',
      '🙄',
      '😬',
      '🤥',
      '😌',
      '😔',
      '😪',
      '🤤',
      '😴',
      '😷',
      '🤒',
      '🤕',
      '🤢',
      '🤮',
      '🥵',
      '🥶',
      '🥴',
      '😵',
      '🤯',
      '🤠',
      '🥳',
      '🥸',
      '😎',
      '🤓',
      '🧐',
      '😕',
      '🫤',
      '😟',
      '🙁',
      '☹️',
      '😮',
      '😯',
      '😲',
      '😳',
      '🥺',
      '🥹',
      '😦',
      '😧',
      '😨',
      '😰',
      '😥',
      '😢',
      '😭',
      '😱',
      '😖',
      '😣',
      '😞',
      '😓',
      '😩',
      '😫',
      '🥱',
      '😤',
      '😡',
      '😠',
      '🤬',
      '😈',
      '👿',
      '💀',
      '☠️',
      '💩',
      '🤡',
      '👻',
      '👽',
      '🤖',
      '😺',
      '😸',
      '😹',
      '😻',
      '😼',
      '😽',
      '🙈',
      '🙉',
      '🙊',
      '💋',
      '💌',
      '💘',
      '💝',
      '💖',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '👍',
      '👎',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🫰',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '👇',
      '☝️',
      '👏',
      '🙌',
      '🫶',
      '🤲',
      '🤝',
      '🙏',
      '✍️',
      '💪',
    ],
    <String>[
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐻‍❄️',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🦄',
      '🐝',
      '🪲',
      '🦋',
      '🐌',
      '🐞',
      '🐜',
      '🪰',
      '🐢',
      '🐍',
      '🦎',
      '🐙',
      '🦑',
      '🦀',
      '🐠',
      '🐟',
      '🐬',
      '🐳',
      '🦈',
      '🐊',
      '🌵',
      '🎄',
      '🌲',
      '🌳',
      '🌴',
      '🪴',
      '🌱',
      '🌿',
      '☘️',
      '🍀',
      '🎍',
      '🪷',
      '🌺',
      '🌸',
      '🌼',
      '🌻',
      '🌞',
      '🌝',
      '🌚',
      '🌙',
      '⭐',
      '🌟',
      '✨',
      '⚡',
    ],
    <String>[
      '🍏',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍆',
      '🥑',
      '🥦',
      '🥬',
      '🥒',
      '🌶️',
      '🌽',
      '🥕',
      '🧄',
      '🧅',
      '🥔',
      '🍠',
      '🥐',
      '🥯',
      '🍞',
      '🥖',
      '🥨',
      '🧀',
      '🥚',
      '🍳',
      '🥞',
      '🧇',
      '🥓',
      '🥩',
      '🍗',
      '🍔',
      '🍟',
      '🍕',
      '🌭',
      '🥪',
      '🌮',
      '🌯',
      '🥙',
      '🧆',
      '🍝',
      '🍜',
      '🍲',
      '🍛',
      '🍣',
      '🍱',
      '🥟',
      '🍦',
      '🍩',
      '🍪',
      '🎂',
      '🍫',
      '☕',
      '🫖',
      '🥤',
      '🧃',
      '🧋',
      '🍵',
      '🥛',
      '🍼',
    ],
    <String>[
      '🚗',
      '🚕',
      '🚙',
      '🚌',
      '🚎',
      '🏎️',
      '🚓',
      '🚑',
      '🚒',
      '🚐',
      '🛻',
      '🚚',
      '🚜',
      '🏍️',
      '🛵',
      '🚲',
      '🛴',
      '🚨',
      '🚥',
      '🚦',
      '✈️',
      '🛫',
      '🛬',
      '🚀',
      '🛸',
      '🚁',
      '⛵',
      '🚤',
      '🛳️',
      '🚢',
      '⚓',
      '⛽',
      '🗺️',
      '🗿',
      '🗽',
      '🗼',
      '🏰',
      '🏯',
      '🏟️',
      '🎡',
      '🎢',
      '⛲',
      '⛺',
      '🏠',
      '🏡',
      '🏢',
      '🏥',
      '🏫',
    ],
    <String>[
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🥎',
      '🎾',
      '🏐',
      '🏉',
      '🥏',
      '🎱',
      '🪀',
      '🏓',
      '🏸',
      '🏒',
      '🏑',
      '🥍',
      '🏏',
      '⛳',
      '🪁',
      '🏹',
      '🎣',
      '🤿',
      '🥊',
      '🥋',
      '🎽',
      '🛹',
      '🛼',
      '🛷',
      '⛸️',
      '🥌',
      '🎿',
      '🏂',
      '🎮',
      '🕹️',
      '🎲',
      '♟️',
      '🎯',
      '🎳',
      '🎨',
      '🎭',
      '🎤',
      '🎧',
      '🎼',
      '🎹',
      '🥁',
      '🎷',
      '🎺',
      '🎸',
    ],
    <String>[
      '⌚',
      '📱',
      '💻',
      '⌨️',
      '🖥️',
      '🖨️',
      '🖱️',
      '💾',
      '💿',
      '📷',
      '📸',
      '📹',
      '🎥',
      '📞',
      '☎️',
      '📺',
      '📻',
      '🎙️',
      '⏰',
      '⌛',
      '🔋',
      '🔌',
      '💡',
      '🔦',
      '🕯️',
      '🧯',
      '💵',
      '💳',
      '💎',
      '⚖️',
      '🧰',
      '🔧',
      '🔨',
      '🪛',
      '🔩',
      '⚙️',
      '⛓️',
      '🧲',
      '🛡️',
      '🔮',
      '💊',
      '🩹',
      '🩺',
      '🚪',
      '🪑',
      '🛏️',
      '🚿',
      '🧴',
      '📚',
      '📖',
      '📝',
      '✏️',
      '📌',
      '📎',
      '🔒',
      '🔑',
    ],
    <String>[
      '❤️',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '☮️',
      '✝️',
      '☪️',
      '🕉️',
      '☸️',
      '✡️',
      '🔯',
      '🕎',
      '☯️',
      '☦️',
      '🛐',
      '⛎',
      '♈',
      '♉',
      '♊',
      '♋',
      '♌',
      '♍',
      '♎',
      '♏',
      '♐',
      '♑',
      '♒',
      '♓',
      '🆔',
      '⚛️',
      '☢️',
      '☣️',
      '📴',
      '✅',
      '☑️',
      '✔️',
      '❎',
      '➕',
      '➖',
      '➗',
      '✖️',
      '‼️',
      '⁉️',
      '❓',
      '❔',
      '❕',
      '❗',
      '〰️',
      '©️',
    ],
  ];

  GlobalKey<ProImageEditorState> _editorKey = GlobalKey<ProImageEditorState>();

  // Used to align the vertical picker to the exact screen-space center of
  // the selected-color circle, even though the app bar and body overlay are
  // mounted in different render boxes.
  final GlobalKey _paintColorCircleKey = GlobalKey();

  // Anchors the floating shape menu to the actual plus button position.
  final GlobalKey _paintShapeButtonKey = GlobalKey();

  // Anchors the font chooser above the real font toolbar button.
  final GlobalKey _textFontButtonKey = GlobalKey();

  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  late final TextEditingController _captionController = TextEditingController(
    text: widget.initialCaption,
  );
  final FocusNode _captionFocusNode = FocusNode();

  VideoPlayerController? _videoPlayerController;
  ProVideoController? _proVideoController;
  pve.VideoMetadata? _videoMetadata;
  List<ImageProvider> _videoThumbnails = const <ImageProvider>[];
  TrimDurationSpan? _trimSpan;
  Duration _videoPosition = Duration.zero;
  bool _videoMuted = false;

  // Crop needs a contained video surface so the complete source stays visible
  // inside the crop frame. The normal editor keeps its edge-to-edge preview.
  final ValueNotifier<bool> _videoCropPreviewMode = ValueNotifier<bool>(false);

  bool _videoSeeking = false;
  TrimDurationSpan? _queuedTrimSpan;
  int _videoPreviewSeekGeneration = 0;
  bool _poppingEditor = false;
  OverlayEntry? _cropRatioOverlay;
  OverlayEntry? _cropDiscardOverlay;
  OverlayEntry? _paintShapeOverlay;
  OverlayEntry? _textFontOverlay;

  final ValueNotifier<bool> _textEmojiPickerVisible = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<int> _textEmojiCategory = ValueNotifier<int>(1);
  final ValueNotifier<TextAlign> _textAlignment = ValueNotifier<TextAlign>(
    TextAlign.center,
  );
  final ValueNotifier<double> _textFontScale = ValueNotifier<double>(
    _textFontScaleDefault,
  );

  // The text editor only creates a movable layer after `TextEditorState.done()`.
  // Track that committed layer separately so the Telegram-style canvas controls
  // can move, rotate and scale the real exported TextLayer.
  final ValueNotifier<TextLayer?> _selectedTextLayer =
      ValueNotifier<TextLayer?>(null);

  TextEditorState? _textFontScaleEditor;
  int _textFontPresetIndex = 0;
  String? _textLayerBeingEditedId;
  bool _textTransformCommitInProgress = false;

  // TextEditorConfigs supplies defaults, but Pro Image Editor creates its live
  // TextEditorState after the sub-editor opens. Apply the requested Telegram
  // light style once to that mounted state so the first frame cannot retain the
  // package/theme contrast defaults (black background with white text).
  bool _textInitialStylePending = false;
  bool _textInitialStyleScheduled = false;

  // The package builds the hint from the currently selected text style.
  // Start that style as SemiBold while the field is empty, then switch it to
  // Roboto Regular as soon as the user enters the first character.
  TextEditingController? _textTypographyController;
  VoidCallback? _textTypographyListener;
  bool _textTypingHasStarted = false;

  // The rounded-background painter calculates a separate rectangle for each
  // rendered line. Re-apply the final alignment after layout so one-line and
  // multiline backgrounds move with the text instead of keeping stale bounds.
  bool _textAlignmentRelayoutScheduled = false;
  TextAlign? _pendingTextAlignment;

  // One source of truth for Telegram's three A-button appearances.
  // Keeping this in a notifier guarantees that the toolbar preview and the
  // actual text layer update together, even if the package rebuild stream
  // does not emit immediately after a custom control changes editor state.
  final ValueNotifier<_TelegramTextBackgroundStyle> _textBackgroundStyle =
      ValueNotifier<_TelegramTextBackgroundStyle>(
        _TelegramTextBackgroundStyle.light,
      );

  // Tracks the real Pro Image Editor paint layer selected on the canvas.
  // Fill/outline changes and transform gestures therefore affect the layer
  // that is exported, rather than a separate visual overlay.
  final ValueNotifier<PaintLayer?> _selectedPaintShape =
      ValueNotifier<PaintLayer?>(null);

  // Baseline copies of the paint layers that existed when the drawing editor
  // opened. Our custom shape controls mutate PaintLayer objects directly, so
  // these copies let the custom cancel action restore every transform/style
  // before Pro Image Editor closes the sub-editor without applying changes.
  Map<String, PaintLayer> _paintSessionOriginalLayers = <String, PaintLayer>{};
  bool _paintSessionSnapshotCaptured = false;

  late bool _selected = widget.selectionIndex != null;

  // Main-toolbar edit indicators. Crop and filter do not create normal layers,
  // so keep their committed state explicitly. Draw/Text/Sticker are derived
  // from the editor's live layers so undo/delete automatically returns them
  // to white.
  bool _activeCropEdit = false;
  bool _activeFilterEdit = false;
  bool _cropSessionActive = false;
  bool _filterSessionActive = false;

  // Main-editor media browsing. The editor can move through nearby gallery
  // photos without leaving the full-screen media editor. Each photo keeps its
  // own Pro Image Editor history so swiping away and back does not throw edits
  // away or flatten editable layers.
  late String _currentSourcePath;
  late String _currentOriginalMediaPath;
  final List<String> _swipeMediaIds = <String>[];
  final List<String> _swipeMediaPaths = <String>[];
  final List<String> _selectedMediaIds = <String>[];
  final Map<String, String> _mediaHistoryJson = <String, String>{};
  final Map<String, String> _mediaCaptions = <String, String>{};
  final Map<String, bool> _mediaCropEditState = <String, bool>{};
  final Map<String, bool> _mediaFilterEditState = <String, bool>{};
  final Map<String, String> _editedMediaPathsById = <String, String>{};
  late String _currentMediaId;
  int _swipeMediaIndex = -1;
  bool _loadingSwipeMedia = false;
  bool _switchingSwipeMedia = false;
  bool _subEditorOpen = false;

  void _setSubEditorOpen(bool value) {
    if (_subEditorOpen == value) return;
    if (mounted) {
      setState(() => _subEditorOpen = value);
    } else {
      _subEditorOpen = value;
    }
  }

  // Raw-pointer tracking is used instead of HorizontalDragGestureRecognizer so
  // the editor keeps ownership of normal layer movement/zoom gestures.
  final Set<int> _mediaSwipePointers = <int>{};
  int? _mediaSwipePrimaryPointer;
  Offset? _mediaSwipeStart;
  Offset? _mediaSwipeLast;

  String? _completedPath;
  bool _sendOnComplete = false;
  bool _finishing = false;
  bool _videoInitialising = false;
  Object? _videoInitialisationError;
  bool _isHd = true;
  Rect? _videoBaseCropRect;
  Size? _videoSourceResolution;

  bool get _isVideo => widget.attachmentType == 'video';

  double get _mainBottomBarHeight =>
      _bottomBarHeight +
      (_isVideo && !_subEditorOpen ? _videoTrimControlsHeight : 0);

  late final ProImageEditorConfigs _configs = ProImageEditorConfigs(
    i18n: const I18n(textEditor: I18nTextEditor(inputHintText: 'Add Text')),
    theme: mui.ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _background,
      canvasColor: _background,
      colorScheme: mui.ColorScheme.fromSeed(
        seedColor: _sentBlue,
        brightness: Brightness.dark,
      ),
    ),
    mainEditor: MainEditorConfigs(
      enableZoom: true,
      enableDoubleTapZoom: true,
      editorMinScale: 1.0,
      editorMaxScale: 8,
      safeArea: const EditorSafeArea.none(),
      interactiveViewerClipBehavior: Clip.none,
      tools: const [
        SubEditorMode.cropRotate,
        SubEditorMode.paint,
        SubEditorMode.text,
        SubEditorMode.emoji,
        SubEditorMode.tune,
        SubEditorMode.filter,
        SubEditorMode.blur,
      ],
      style: const MainEditorStyle(
        background: _background,
        appBarBackground: Colors.transparent,
        bottomBarBackground: Colors.transparent,
        bottomBarColor: WrytteColors.textPrimary,
        appBarColor: WrytteColors.textPrimary,
        uiOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: _background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      widgets: MainEditorWidgets(
        // Do not give the Scaffold a real app bar or bottom navigation bar.
        // Those slots reduce the editor body and make vertically fitted images
        // smaller. The controls are rendered as overlays in `bodyItems` instead,
        // so the image keeps the full-screen canvas and can continue underneath
        // every control container.
        appBar: (editor, rebuildStream) => null,
        bottomBar: (editor, rebuildStream, key) => null,
        bodyItems: (editor, rebuildStream) {
          final headerHeight =
              MediaQuery.paddingOf(context).top + _headerContentHeight;

          return [
            if (_isVideo)
              ReactiveWidget(
                stream: rebuildStream,
                builder: (_) =>
                    Positioned.fill(child: _buildVideoPlayOverlay()),
              ),
            // Telegram-style selection for committed text layers. The package
            // continues to render/export the real TextLayer; this overlay only
            // supplies selection dots and direct manipulation gestures.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => Positioned.fill(
                child: _TextLayerInteractionOverlay(
                  editor: editor,
                  selectedLayer: _selectedTextLayer,
                  onEdit: (layer) => _editTextLayerFromCanvas(editor, layer),
                ),
              ),
            ),
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: headerHeight,
                child: _buildHeader(editor),
              ),
            ),
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) {
                final bottomSafeInset = MediaQuery.viewPaddingOf(
                  context,
                ).bottom;
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _mainBottomBarHeight + bottomSafeInset,
                  child: _buildBottomBar(editor),
                );
              },
            ),
          ];
        },
      ),
    ),
    paintEditor: PaintEditorConfigs(
      enableZoom: true,
      enableDoubleTapZoom: true,
      editorMinScale: 1.0,
      editorMaxScale: 8,
      enableShareZoomMatrix: true,
      enableEdit: true,
      showLayers: true,
      tools: const [
        PaintMode.freeStyle,
        PaintMode.rect,
        PaintMode.circle,
        PaintMode.polygon,
        PaintMode.arrow,
      ],
      initialPaintMode: PaintMode.freeStyle,
      customPathBuilders: {
        PaintMode.custom1:
            ({
              required PaintedModel item,
              required PaintEditorConfigs paintEditorConfigs,
              required double scale,
            }) => _SquarePathBuilder(
              item: item,
              paintEditorConfigs: paintEditorConfigs,
              scale: scale,
            ),
        PaintMode.custom2:
            ({
              required PaintedModel item,
              required PaintEditorConfigs paintEditorConfigs,
              required double scale,
            }) => _TrianglePathBuilder(
              item: item,
              paintEditorConfigs: paintEditorConfigs,
              scale: scale,
            ),
      },
      showToggleFillButton: false,
      showLineWidthAdjustmentButton: false,
      showOpacityAdjustmentButton: false,
      // Match the main editor viewport. The custom app bar and bottom bar
      // already handle the device insets themselves.
      safeArea: const EditorSafeArea.none(),
      style: const PaintEditorStyle(
        background: _background,
        appBarBackground: Colors.transparent,
        appBarColor: WrytteColors.textPrimary,
        bottomBarBackground: Colors.transparent,
        bottomBarActiveItemColor: WrytteColors.textPrimary,
        bottomBarInactiveItemColor: WrytteColors.textPrimary,
        initialColor: Color(0xFFFF0000),
        initialStrokeWidth: 3,
        uiOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: _background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      widgets: PaintEditorWidgets(
        // Keep Draw on the same full-screen body used by the main editor.
        // The image is therefore never refitted when Draw opens. Its controls
        // float over the canvas and the image is allowed to remain behind them.
        appBar: (paintEditor, rebuildStream) => null,
        bottomBar: (paintEditor, rebuildStream) => null,
        // Calculate the picker's horizontal position from the selected-color
        // circle's real global center, so it remains aligned on every device.
        bodyItems: (paintEditor, rebuildStream) {
          _ensurePaintSessionSnapshot(paintEditor);

          return [
            // Keep shape interaction below the color picker. When a shape is
            // selected, the interaction overlay catches blank canvas taps to
            // deselect it, while the picker remains fully interactive above it.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => Positioned.fill(
                child: _PaintShapeInteractionOverlay(
                  editor: paintEditor,
                  selectedLayer: _selectedPaintShape,
                ),
              ),
            ),
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => Positioned.fill(
                child: _AlignedPaintColorPickerOverlay(
                  targetKey: _paintColorCircleKey,
                  // The picker used to start 16 px below the real app bar.
                  // Since the app bar is now an overlay, include its height
                  // explicitly while leaving the canvas completely untouched.
                  top:
                      MediaQuery.paddingOf(context).top +
                      _headerContentHeight +
                      16,
                  // Keep the picker narrow and align its exact center with
                  // the selected-color circle above it.
                  pickerFootprintWidth: 28,
                  horizontalOffset: 0,
                  child: _verticalPaintColorPicker(
                    onColorChanged: (color) =>
                        _setPaintColor(paintEditor, color),
                  ),
                ),
              ),
            ),
            // All Draw chrome is now painted over the image. These widgets do
            // not reserve layout space, so even a tall image can extend behind
            // them without being scaled down.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) {
                final headerHeight =
                    MediaQuery.paddingOf(context).top + _headerContentHeight;

                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerHeight,
                  child: _buildPaintHeader(paintEditor),
                );
              },
            ),
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) {
                final bottomSafeInset = MediaQuery.viewPaddingOf(
                  context,
                ).bottom;
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _bottomBarHeight + bottomSafeInset,
                  child: _buildPaintBottomBar(paintEditor),
                );
              },
            ),
          ];
        },
        // Disable the package picker. The single custom picker is rendered
        // above through bodyItems.
        colorPicker: (paintEditor, rebuildStream, currentColor, setColor) =>
            null,
      ),
    ),
    textEditor: TextEditorConfigs(
      // The text editor uses the same full-screen canvas as the main editor.
      // Its controls are overlays, so opening Text never refits or shrinks the
      // image, even while the keyboard or floating controls are visible.
      safeArea: const EditorSafeArea.none(),
      resizeToAvoidBottomInset: false,
      enableTapOutsideToSave: false,
      initialPrimaryColor: Colors.black,
      // Text starts black on white. The custom A button cycles:
      // white -> soft black overlay -> transparent -> white.
      initialSecondaryColor: Colors.white,
      initialBackgroundColorMode: LayerBackgroundMode.backgroundAndColor,

      // Telegram keeps the text entity anchored around its center while the
      // line layout moves left, center, or right inside the available image
      // width. These options make the editing preview and the final TextLayer
      // use the same wrapping boundary.
      initialTextAlign: TextAlign.center,
      inputTextFieldAlign: Alignment.center,
      layerFractionalOffset: const Offset(-0.5, -0.5),
      enableAutoOverflow: true,
      enableAutoWrapOnLayer: true,
      enableImageBoundaryTextWrap: true,
      initFontSize: 30,
      showSelectFontStyleBottomBar: false,
      showTextAlignButton: false,
      showFontScaleButton: false,
      showBackgroundModeButton: false,
      customTextStyles: _textFontPresets,
      defaultTextStyle: const TextStyle(
        color: Colors.black,
        fontFamily: WrytteTypography.primaryFontFamily,
        fontWeight: _textHintWeight,
        fontStyle: FontStyle.normal,
      ),
      style: const TextEditorStyle(
        // Use the exact blue used by the circular send button.
        inputCursorColor: _sentBlue,
      ),
      widgets: TextEditorWidgets(
        // Do not use real Scaffold bars because they would change the text
        // editor body size. Everything below floats over the image instead.
        appBar: (textEditor, rebuildStream) => null,
        bottomBar: (textEditor, rebuildStream) => null,
        colorPicker: (textEditor, rebuildStream, currentColor, setColor) =>
            null,
        bodyItems: (textEditor, rebuildStream) {
          _bindTextEditorTypography(textEditor);
          _bindTextFontScale(textEditor);
          _scheduleInitialTextStyle(textEditor);

          final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
          final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;
          final bottomBarHeight = 64.0 + bottomSafeInset;

          return <ReactiveWidget<Widget>>[
            // Telegram behavior: tapping the canvas while the emoji panel is
            // open first slides the panel down, stops text input, commits the
            // text as a layer and immediately selects it for movement.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: _textEmojiPickerVisible,
                builder: (context, visible, child) => Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () =>
                          unawaited(_commitTextForCanvasTransform(textEditor)),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),

            // Reuse the exact same color strip used by Draw.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => Positioned(
                top: MediaQuery.paddingOf(context).top + 92,
                right: 7,
                child: _verticalPaintColorPicker(
                  onColorChanged: (color) => _setTextColor(textEditor, color),
                ),
              ),
            ),
            // The toolbar moves upward exactly like it does above the system
            // keyboard. The image/canvas remains full size underneath.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: _textEmojiPickerVisible,
                builder: (context, emojiVisible, child) {
                  final panelHeight = _textEmojiPanelHeight(context);

                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 230),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    bottom: keyboardInset + (emojiVisible ? panelHeight : 0),
                    height: bottomBarHeight,
                    child: _buildTextBottomBar(
                      textEditor,
                      height: bottomBarHeight,
                    ),
                  );
                },
              ),
            ),

            // Full keyboard-like emoji panel with the same glass language as
            // the editor's bottom containers.
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: _textEmojiPickerVisible,
                builder: (context, visible, child) {
                  final panelHeight = _textEmojiPanelHeight(context);

                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 230),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    bottom: visible ? 0 : -panelHeight,
                    height: panelHeight,
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: AnimatedOpacity(
                        opacity: visible ? 1 : 0,
                        duration: const Duration(milliseconds: 170),
                        child: _buildTextEmojiPicker(
                          textEditor,
                          height: panelHeight,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ];
        },

        // Use the package's full-body overlay slot for the text-size control.
        // `bodyItems` shares the internal text-content stack, which can clip or
        // constrain tall controls. `bodyItemsOverlay` is positioned above all
        // text-editor body content and receives the complete editor body.
        bodyItemsOverlay: (textEditor, rebuildStream) {
          final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
          final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;
          final bottomBarHeight = 64.0 + bottomSafeInset;
          final topInset = MediaQuery.paddingOf(context).top + 72.0;
          final bottomInset = keyboardInset + bottomBarHeight + 12.0;

          return <ReactiveWidget<Widget>>[
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => Positioned(
                left: 0,
                top: topInset,
                bottom: bottomInset,
                width: 58,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;
                    final requestedHeight = (availableHeight * 0.34).clamp(
                      255.0,
                      315.0,
                    );
                    final sliderHeight = math
                        .min(requestedHeight, availableHeight)
                        .toDouble();

                    return Align(
                      // Keep the rail close to the usable canvas centre, with
                      // a small upward offset matching Telegram's placement.
                      alignment: const Alignment(-1, -0.08),
                      child: _TelegramTextSizeSlider(
                        valueListenable: _textFontScale,
                        min: _textFontScaleMin,
                        max: _textFontScaleMax,
                        height: sliderHeight,
                        onDragStart: () {
                          unawaited(HapticFeedback.selectionClick());
                        },
                        onChanged: (scale) =>
                            _setTelegramTextFontScale(textEditor, scale),
                        onDragEnd: () {
                          unawaited(HapticFeedback.lightImpact());
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ];
        },
      ),
    ),
    filterEditor: FilterEditorConfigs(
      enableMultiSelection: false,
      safeArea: const EditorSafeArea.none(),
      style: const FilterEditorStyle(background: _background),
      widgets: FilterEditorWidgets(
        // Do not reserve any Scaffold bar space. Both controls and filter row
        // float over the same full-screen image canvas used by Text editing.
        appBar: (filterEditor, rebuildStream) => null,
        bottomBar: (filterEditor, rebuildStream) => null,

        bodyItems: (filterEditor, rebuildStream) => [
          // Render the live filter preview across the complete sub-editor body,
          // matching the full-height canvas used by Text editing. The package
          // still owns the selected filter and final export; this is display-only.
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => Positioned.fill(
              child: IgnorePointer(
                child: _buildFilterFullscreenPreview(filterEditor),
              ),
            ),
          ),

          // The filter row is an overlay, not a layout bottom bar. Therefore
          // opening Filters never changes the fitted image size.
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) {
              final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;

              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _filterBottomPanelHeight + bottomSafeInset,
                child: _buildFilterBottomBar(filterEditor),
              );
            },
          ),
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + _headerContentHeight,
              child: _buildFilterHeader(filterEditor),
            ),
          ),
        ],

        // The boss reference does not show an opacity/strength slider.
        slider: (filterEditor, rebuildStream, value, onChanged, onChangeEnd) =>
            ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => const SizedBox.shrink(),
            ),
      ),
    ),
    cropRotateEditor: CropRotateEditorConfigs(
      rotateDirection: RotateDirection.left,
      tools: const [
        CropRotateTool.rotate,
        CropRotateTool.flip,
        CropRotateTool.aspectRatio,
        CropRotateTool.reset,
      ],
      aspectRatios: const [
        AspectRatioItem(text: 'Original', value: 0),
        AspectRatioItem(text: 'Square', value: 1),
        AspectRatioItem(text: '3:2', value: 3 / 2),
        AspectRatioItem(text: '5:3', value: 5 / 3),
        AspectRatioItem(text: '4:3', value: 4 / 3),
        AspectRatioItem(text: '5:4', value: 5 / 4),
        AspectRatioItem(text: '7:5', value: 7 / 5),
        AspectRatioItem(text: '16:9', value: 16 / 9),
      ],
      // Keep the crop editor inside the device status/navigation safe areas.
      safeArea: const EditorSafeArea(),
      style: const CropRotateEditorStyle(
        background: _background,
        appBarBackground: Colors.transparent,
        appBarColor: WrytteColors.textPrimary,
        bottomBarBackground: Colors.transparent,
        bottomBarColor: WrytteColors.textPrimary,
        cropOverlayColor: Color(0xCC000000),
        cropCornerColor: WrytteColors.textPrimary,
        // Thin lines around/across the crop frame. Keep these slimmer
        // than the thicker corner handles.
        helperLineColor: Color(0xCCFFFFFF),
        helperLineWidth: 0.8,
        cropCornerLength: 22,
        cropCornerThickness: 3,
        uiOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: _background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      widgets: CropRotateEditorWidgets(
        // Reserve 45 px above the crop canvas so the image/crop container
        // starts lower while still respecting the device safe area.
        appBar: (cropEditor, rebuildStream) => ReactiveAppbar(
          stream: rebuildStream,
          appbarSize: const Size.fromHeight(45),
          builder: (_) => const PreferredSize(
            preferredSize: Size.fromHeight(45),
            child: SizedBox(height: 45),
          ),
        ),
        // `bodyItems` and Pro Image Editor's built-in crop painter are mounted
        // in different render boxes. Convert the crop rectangle through global
        // coordinates instead of reusing its local coordinates directly.
        bodyItems: (cropEditor, rebuildStream) => [
          // Keep the crop play button in the SAME overlay that resolves the
          // package crop rectangle. CropRotate paints some of its own content
          // above normal body items, so a separate full-screen play overlay can
          // disappear behind it. Anchoring the button to the measured crop rect
          // guarantees that it stays visible and centered on the actual video.
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => _CropFrameOverlay(
              editor: cropEditor,
              rebuildStream: rebuildStream,
              centerChild: _isVideo ? _buildCropVideoPlayButton() : null,
              belowChild: _isVideo
                  ? null
                  : _TelegramCropRotationDial(
                      valueDegrees: cropEditor.tiltRotateAngle * 180 / math.pi,
                      onChanged: (degrees) {
                        _cropSessionActive = true;
                        cropEditor.tilt(
                          TiltMode.rotate,
                          degrees * math.pi / 180,
                          updateStateHistory: false,
                        );
                      },
                      onChangeEnd: (degrees) {
                        _cropSessionActive = true;
                        cropEditor.tilt(
                          TiltMode.rotate,
                          degrees * math.pi / 180,
                        );
                      },
                    ),
            ),
          ),
        ],
        bottomBar: (cropEditor, rebuildStream) => ReactiveWidget(
          stream: rebuildStream,
          builder: (_) => _buildCropBottomBar(cropEditor),
        ),
        aspectRatioOptions:
            (cropEditor, rebuildStream, aspectRatio, originalAspectRatio) =>
                ReactiveWidget(
                  stream: rebuildStream,
                  builder: (_) => _buildCropAspectRatioOptions(
                    cropEditor,
                    aspectRatio,
                    originalAspectRatio,
                  ),
                ),
      ),
    ),
    helperLines: const HelperLineConfigs(
      style: HelperLineStyle(
        horizontalColor: _sentBlue,
        verticalColor: _sentBlue,
        rotateColor: _sentBlue,
      ),
    ),
    videoEditor: const VideoEditorConfigs(
      initialMuted: false,
      initialPlay: false,
      isAudioSupported: true,
      // The package normally places its trim/mute/duration controls at the
      // top. Wrytte renders those controls in the bottom overlay instead.
      showControls: false,
      enableTrimBar: false,
      playTimeSmoothingDuration: Duration(milliseconds: 450),
    ),
  );

  late final ProImageEditorCallbacks _imageCallbacks = ProImageEditorCallbacks(
    onImageEditingComplete: _completeImageEditing,
    onCloseEditor: _handleEditorClosed,
    mainEditorCallbacks: MainEditorCallbacks(onTap: _toggleChrome),
  );

  late final ProImageEditorCallbacks _videoCallbacks = ProImageEditorCallbacks(
    onCompleteWithParameters: _completeVideoEditing,
    onCloseEditor: _handleEditorClosed,
    mainEditorCallbacks: MainEditorCallbacks(onTap: _toggleChrome),
    videoEditorCallbacks: VideoEditorCallbacks(
      onPause: () async {
        await _videoPlayerController?.pause();
      },
      onPlay: () async {
        await _videoPlayerController?.play();
      },
      onMuteToggle: (muted) async {
        await _videoPlayerController?.setVolume(muted ? 0 : 1);
        if (mounted) {
          setState(() => _videoMuted = muted);
        } else {
          _videoMuted = muted;
        }
      },
      onTrimSpanUpdate: (span) {
        if (mounted) {
          setState(() => _trimSpan = span);
        } else {
          _trimSpan = span;
        }

        if (_videoPlayerController?.value.isPlaying == true) {
          _proVideoController?.pause();
        }
      },
      onTrimSpanEnd: _seekVideoToSpan,
    ),
  );

  @override
  void initState() {
    super.initState();

    final hasProvidedMedia =
        !_isVideo &&
        widget.mediaIds.isNotEmpty &&
        widget.mediaIds.length == widget.mediaPaths.length;

    if (hasProvidedMedia) {
      final safeIndex = widget.initialMediaIndex
          .clamp(0, widget.mediaPaths.length - 1)
          .toInt();

      _swipeMediaIds.addAll(widget.mediaIds);
      _swipeMediaPaths.addAll(widget.mediaPaths);
      _swipeMediaIndex = safeIndex;
      _currentMediaId = widget.mediaIds[safeIndex];
      _currentSourcePath = widget.mediaPaths[safeIndex];
      _currentOriginalMediaPath = widget.mediaPaths[safeIndex];
    } else {
      _currentMediaId = _mediaPathKey(widget.sourcePath);
      _currentSourcePath = widget.sourcePath;
      _currentOriginalMediaPath = widget.sourcePath;
    }

    _selectedMediaIds.addAll(
      widget.initialSelectedMediaIds.take(_maxSelectedMediaItems),
    );
    if (_selected && !_selectedMediaIds.contains(_currentMediaId)) {
      final requestedPosition =
          (widget.selectionIndex ?? (_selectedMediaIds.length + 1)) - 1;
      final insertAt = requestedPosition
          .clamp(0, _selectedMediaIds.length)
          .toInt();
      _selectedMediaIds.insert(insertAt, _currentMediaId);
    }
    _selected = _selectedMediaIds.contains(_currentMediaId);

    if (_isVideo) {
      unawaited(_initialiseVideo());
    } else if (!hasProvidedMedia) {
      unawaited(_loadSwipeMedia());
    }
  }

  @override
  void dispose() {
    _cropRatioOverlay?.remove();
    _cropRatioOverlay = null;
    _cropDiscardOverlay?.remove();
    _cropDiscardOverlay = null;
    _paintShapeOverlay?.remove();
    _paintShapeOverlay = null;
    _textFontOverlay?.remove();
    _textFontOverlay = null;
    _detachTextEditorTypography();
    _textEmojiPickerVisible.dispose();
    _textEmojiCategory.dispose();
    _textAlignment.dispose();
    _textFontScale.dispose();
    _selectedTextLayer.dispose();
    _textBackgroundStyle.dispose();
    _selectedPaintShape.dispose();
    _paintSessionOriginalLayers.clear();
    _captionController.dispose();
    _captionFocusNode.dispose();
    _chromeVisible.dispose();
    _videoCropPreviewMode.dispose();
    final videoPlayer = _videoPlayerController;
    _videoPlayerController = null;
    if (videoPlayer != null) {
      videoPlayer.removeListener(_syncVideoPosition);
      unawaited(videoPlayer.dispose());
    }
    _proVideoController?.dispose();
    _proVideoController = null;
    super.dispose();
  }

  Future<void> _initialiseVideo() async {
    if (_videoInitialising || _proVideoController != null) return;
    setState(() {
      _videoInitialising = true;
      _videoInitialisationError = null;
    });

    try {
      final source = pve.EditorVideo.file(widget.sourcePath);
      final metadataFuture = pve.ProVideoEditor.instance.getMetadata(source);
      final player = VideoPlayerController.file(File(widget.sourcePath));
      _videoPlayerController = player;
      await player.initialize();
      await player.setLooping(false);
      await player.setVolume(1);
      final metadata = await metadataFuture;

      final screenWidth = MediaQuery.sizeOf(context).width;
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

      // Keep the editor/export base on the real captured video. The preview can
      // still display edge-to-edge using cover fit, but exporting must not
      // inherit any live-camera preview crop unless the user explicitly crops.
      final sourceResolution = metadata.resolution;
      final baseCrop = Offset.zero & sourceResolution;
      final canvasResolution = sourceResolution;

      _videoSourceResolution = sourceResolution;
      _videoBaseCropRect = baseCrop;

      // Telegram's timeline reads as a continuous filmstrip: roughly one
      // thumbnail per ~40 logical pixels, center-cropped to the strip height.
      // Keep enough frames on wider phones so motion is easy to read while
      // trimming instead of stretching a handful of thumbnails.
      final timelineFrameCount = (screenWidth / 40).ceil().clamp(8, 14).toInt();
      final thumbnailWidth = math.max(
        56.0,
        (screenWidth / timelineFrameCount) * devicePixelRatio,
      );
      final thumbnailHeight = math.max(56.0, 40.0 * devicePixelRatio);

      if (!mounted) {
        await player.dispose();
        return;
      }

      _videoMetadata = metadata;
      _videoThumbnails = const <ImageProvider>[];
      _trimSpan = TrimDurationSpan(
        start: Duration.zero,
        end: metadata.duration,
      );
      _videoPosition = Duration.zero;
      _videoMuted = false;

      final proVideoController = ProVideoController(
        // The main editor can keep the edge-to-edge preview, but Crop must
        // never receive an already center-cropped surface. Switching to contain
        // while Crop is open keeps the entire source visible and centered, so
        // the crop frame manipulates the real video instead of a top/right slice.
        videoPlayer: ValueListenableBuilder<bool>(
          valueListenable: _videoCropPreviewMode,
          builder: (context, cropPreviewMode, child) => LayoutBuilder(
            builder: (context, constraints) {
              final videoSize = player.value.size;

              if (videoSize.width <= 0 ||
                  videoSize.height <= 0 ||
                  constraints.maxWidth <= 0 ||
                  constraints.maxHeight <= 0) {
                return ColoredBox(
                  color: _background,
                  child: SizedBox.expand(child: VideoPlayer(player)),
                );
              }

              if (cropPreviewMode) {
                return ColoredBox(
                  color: _background,
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: videoSize.width,
                        height: videoSize.height,
                        child: VideoPlayer(player),
                      ),
                    ),
                  ),
                );
              }

              // Display-only cover fit: the editor can look edge-to-edge
              // without changing the real exported video unless the user
              // explicitly applies crop/rotate tools.
              return ColoredBox(
                color: _background,
                child: SizedBox.expand(
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: videoSize.width,
                        height: videoSize.height,
                        child: VideoPlayer(player),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        initialResolution: canvasResolution,
        videoDuration: metadata.duration,
        fileSize: metadata.fileSize,
        bitrate: metadata.bitrate,
        // Show the full-screen editor as soon as playback and metadata are
        // ready. Timeline keyframes are filled in asynchronously below.
        thumbnails: const <ImageProvider>[],
      );
      _proVideoController = proVideoController;
      player.addListener(_syncVideoPosition);
      setState(() => _videoInitialising = false);

      unawaited(
        _loadVideoThumbnails(
          source: source,
          controller: proVideoController,
          frameCount: timelineFrameCount,
          width: thumbnailWidth,
          height: thumbnailHeight,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _videoInitialising = false;
        _videoInitialisationError = error;
      });
    }
  }

  Future<void> _loadVideoThumbnails({
    required pve.EditorVideo source,
    required ProVideoController controller,
    required int frameCount,
    required double width,
    required double height,
  }) async {
    try {
      final frames = await pve.ProVideoEditor.instance.getKeyFrames(
        pve.KeyFramesConfigs(
          video: source,
          outputSize: Size(width, height),
          boxFit: pve.ThumbnailBoxFit.cover,
          maxOutputFrames: frameCount,
          outputFormat: pve.ThumbnailFormat.jpeg,
        ),
      );

      if (!mounted || !identical(_proVideoController, controller)) return;
      final thumbnails = frames
          .map<ImageProvider>(MemoryImage.new)
          .toList(growable: false);
      controller.thumbnails = thumbnails;
      setState(() => _videoThumbnails = thumbnails);
    } catch (error) {
      debugPrint('[ChatMediaEditor] Video thumbnails could not load: $error');
    }
  }

  void _syncVideoPosition() {
    final player = _videoPlayerController;
    final proController = _proVideoController;
    final metadata = _videoMetadata;
    if (player == null || proController == null || metadata == null) return;

    final position = player.value.position;
    proController.setPlayTime(position);

    if (mounted &&
        (position - _videoPosition).abs() >= const Duration(milliseconds: 80)) {
      setState(() => _videoPosition = position);
    } else {
      _videoPosition = position;
    }

    final span = _trimSpan;
    if (span != null && position >= span.end) {
      unawaited(_seekVideoToSpan(span));
    } else if (position >= metadata.duration) {
      unawaited(
        _seekVideoToSpan(
          TrimDurationSpan(start: Duration.zero, end: metadata.duration),
        ),
      );
    }
  }

  Future<void> _seekVideoToSpan(TrimDurationSpan span) async {
    _trimSpan = span;
    if (_videoSeeking) {
      _queuedTrimSpan = span;
      return;
    }
    _videoSeeking = true;
    _proVideoController?.pause();
    _proVideoController?.setPlayTime(span.start);
    await _videoPlayerController?.pause();
    await _videoPlayerController?.seekTo(span.start);
    _videoSeeking = false;

    final queued = _queuedTrimSpan;
    _queuedTrimSpan = null;
    if (queued != null) await _seekVideoToSpan(queued);
  }

  void _toggleChrome() {
    if (_captionFocusNode.hasFocus) {
      _captionFocusNode.unfocus();
      return;
    }
    _chromeVisible.value = !_chromeVisible.value;
  }

  Future<void> _completeImageEditing(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}wrytte_edit_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(bytes, flush: true);
    _completedPath = path;
    _editedMediaPathsById[_currentMediaId] = path;
  }

  Future<void> _completeVideoEditing(CompleteParameters parameters) async {
    final metadata = _videoMetadata;
    if (metadata == null) return;
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}wrytte_video_edit_${DateTime.now().microsecondsSinceEpoch}.mp4';

    final sourceResolution = _videoSourceResolution ?? metadata.resolution;
    final baseCrop = _videoBaseCropRect ?? (Offset.zero & sourceResolution);
    final editorCropX = parameters.isTransformed ? parameters.cropX ?? 0 : 0;
    final editorCropY = parameters.isTransformed ? parameters.cropY ?? 0 : 0;
    final editorCropWidth = parameters.isTransformed
        ? parameters.cropWidth ?? baseCrop.width.round()
        : baseCrop.width.round();
    final editorCropHeight = parameters.isTransformed
        ? parameters.cropHeight ?? baseCrop.height.round()
        : baseCrop.height.round();

    final cropX = (baseCrop.left.round() + editorCropX)
        .clamp(0, math.max(0, sourceResolution.width.round() - 2))
        .toInt();
    final cropY = (baseCrop.top.round() + editorCropY)
        .clamp(0, math.max(0, sourceResolution.height.round() - 2))
        .toInt();
    final cropWidth = editorCropWidth
        .clamp(2, math.max(2, sourceResolution.width.round() - cropX))
        .toInt();
    final cropHeight = editorCropHeight
        .clamp(2, math.max(2, sourceResolution.height.round() - cropY))
        .toInt();

    final baseCropChangesSource =
        baseCrop.left.round() != 0 ||
        baseCrop.top.round() != 0 ||
        baseCrop.width.round() != sourceResolution.width.round() ||
        baseCrop.height.round() != sourceResolution.height.round();
    final requiresCropTransform =
        baseCropChangesSource || parameters.isTransformed;

    final renderData = pve.VideoRenderData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      videoSegments: [
        pve.VideoSegment(video: pve.EditorVideo.file(widget.sourcePath)),
      ],
      imageLayers: [
        if (parameters.layers.isNotEmpty)
          pve.ImageLayer(image: pve.EditorLayerImage.memory(parameters.image)),
      ],
      blur: parameters.blur,
      colorFilters: [pve.ColorFilter(matrix: parameters.colorFiltersCombined)],
      startTime: parameters.startTime,
      endTime: parameters.endTime,
      transform: requiresCropTransform
          ? pve.ExportTransform(
              width: cropWidth,
              height: cropHeight,
              rotateTurns: 4 - parameters.rotateTurns,
              x: cropX,
              y: cropY,
              flipX: parameters.flipX,
              flipY: parameters.flipY,
            )
          : null,
      enableAudio: _proVideoController?.isAudioEnabled ?? true,
      outputFormat: pve.VideoOutputFormat.mp4,
      bitrate: metadata.bitrate,
    );

    _completedPath = await pve.ProVideoEditor.instance.renderVideoToFile(
      path,
      renderData,
    );
  }

  String _mediaPathKey(String path) {
    return path.replaceAll('\\', '/').trim().toLowerCase();
  }

  String _mediaFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized.toLowerCase() : parts.last.toLowerCase();
  }

  int? get _currentSelectionNumber {
    final index = _selectedMediaIds.indexOf(_currentMediaId);
    return index < 0 ? null : index + 1;
  }

  void _setCurrentMediaSelected(bool selected, {bool notify = true}) {
    if (selected &&
        !_selectedMediaIds.contains(_currentMediaId) &&
        _selectedMediaIds.length >= _maxSelectedMediaItems) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('You can send up to 30 media items')),
        );
      }
      return;
    }
    void update() {
      if (selected) {
        if (!_selectedMediaIds.contains(_currentMediaId)) {
          _selectedMediaIds.add(_currentMediaId);
        }
      } else {
        _selectedMediaIds.remove(_currentMediaId);
      }

      // The number is derived from the CURRENT ordered selection list, never
      // from a monotonically increasing counter. Therefore:
      // select -> 1, deselect, select again -> 1.
      _selected = _selectedMediaIds.contains(_currentMediaId);
    }

    if (notify && mounted) {
      setState(update);
    } else {
      update();
    }
  }

  Future<void> _loadSwipeMedia() async {
    if (_isVideo || _loadingSwipeMedia) return;
    _loadingSwipeMedia = true;

    try {
      final permission = await PhotoLibraryPermissionService.instance
          .ensureVisualMediaAccess();
      if (!permission.hasAccess) return;

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (albums.isEmpty) return;

      final assets = await albums.first.getAssetListPaged(page: 0, size: 300);

      final ids = <String>[];
      final paths = <String>[];
      final seen = <String>{};

      for (final asset in assets) {
        final file = await asset.file;
        final path = file?.path.trim() ?? '';
        if (path.isEmpty) continue;

        final key = _mediaPathKey(path);
        if (seen.add(key)) {
          ids.add(asset.id);
          paths.add(path);
        }
      }

      final currentKey = _mediaPathKey(_currentOriginalMediaPath);
      var currentIndex = paths.indexWhere(
        (path) => _mediaPathKey(path) == currentKey,
      );

      // Some Android pickers return a copied/cache path. Fall back to matching
      // the filename so the current photo still lands in the right Recents
      // position when possible.
      if (currentIndex < 0) {
        final currentName = _mediaFileName(_currentOriginalMediaPath);
        currentIndex = paths.indexWhere(
          (path) => _mediaFileName(path) == currentName,
        );
      }

      if (currentIndex < 0) {
        paths.insert(0, _currentOriginalMediaPath);
        ids.insert(0, _currentMediaId);
        currentIndex = 0;
      } else {
        // Keep the exact picker path as the source for this session. Android
        // can expose the same photo through a different MediaStore path.
        paths[currentIndex] = _currentOriginalMediaPath;
        ids[currentIndex] = _currentMediaId;
      }

      if (!mounted) return;
      setState(() {
        _swipeMediaIds
          ..clear()
          ..addAll(ids);
        _swipeMediaPaths
          ..clear()
          ..addAll(paths);
        _swipeMediaIndex = currentIndex;
      });
    } catch (error) {
      debugPrint('[ChatMediaEditor] Could not load swipe media: $error');
    } finally {
      _loadingSwipeMedia = false;
    }
  }

  Future<bool> _saveCurrentMediaSession() async {
    final key = _currentMediaId;
    _mediaCaptions[key] = _captionController.text;
    _mediaCropEditState[key] = _activeCropEdit;
    _mediaFilterEditState[key] = _activeFilterEdit;

    final editor = _editorKey.currentState;
    if (editor == null) return true;

    try {
      final export = await editor.exportStateHistory();
      _mediaHistoryJson[key] = await export.toJson();
      return true;
    } catch (error) {
      debugPrint(
        '[ChatMediaEditor] Could not preserve edits before media swipe: $error',
      );
      return false;
    }
  }

  Future<void> _restoreCurrentMediaHistory(String mediaKey) async {
    final json = _mediaHistoryJson[mediaKey];
    if (json == null || json.isEmpty) return;

    // Wait for the new ProImageEditor and its source image to mount.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || mediaKey != _currentMediaId) {
      return;
    }

    final editor = _editorKey.currentState;
    if (editor == null) return;

    try {
      await editor.importStateHistory(ImportStateHistory.fromJson(json));
    } catch (error) {
      debugPrint('[ChatMediaEditor] Could not restore media edits: $error');
    }
  }

  Future<void> _switchSwipeMedia(int delta) async {
    if (_isVideo ||
        _subEditorOpen ||
        _switchingSwipeMedia ||
        _swipeMediaIndex < 0 ||
        _swipeMediaPaths.isEmpty) {
      return;
    }

    final targetIndex = _swipeMediaIndex + delta;
    if (targetIndex < 0 || targetIndex >= _swipeMediaPaths.length) return;

    _switchingSwipeMedia = true;
    try {
      if (!await _saveCurrentMediaSession()) return;
      if (!mounted) return;

      final targetPath = _swipeMediaPaths[targetIndex];
      final targetId = targetIndex < _swipeMediaIds.length
          ? _swipeMediaIds[targetIndex]
          : _mediaPathKey(targetPath);
      final targetKey = targetId;

      _closeTextFontMenu();
      _closePaintShapeMenu();
      _selectedTextLayer.value = null;
      _selectedPaintShape.value = null;
      _textEmojiPickerVisible.value = false;
      _hideDiscardChangesMenu();

      setState(() {
        _swipeMediaIndex = targetIndex;
        _currentMediaId = targetId;
        _currentOriginalMediaPath = targetPath;
        _currentSourcePath = targetPath;
        _editorKey = GlobalKey<ProImageEditorState>();

        _selected = _selectedMediaIds.contains(targetId);
        _captionController.text = _mediaCaptions[targetKey] ?? '';
        _activeCropEdit = _mediaCropEditState[targetKey] ?? false;
        _activeFilterEdit = _mediaFilterEditState[targetKey] ?? false;
        _cropSessionActive = _activeCropEdit;
        _filterSessionActive = _activeFilterEdit;
        _completedPath = null;
        _chromeVisible.value = true;
      });

      unawaited(HapticFeedback.selectionClick());
      await _restoreCurrentMediaHistory(targetKey);
    } finally {
      _switchingSwipeMedia = false;
    }
  }

  void _onMediaPointerDown(PointerDownEvent event) {
    if (_isVideo || _subEditorOpen || _switchingSwipeMedia) return;

    _mediaSwipePointers.add(event.pointer);
    if (_mediaSwipePointers.length == 1) {
      _mediaSwipePrimaryPointer = event.pointer;
      _mediaSwipeStart = event.position;
      _mediaSwipeLast = event.position;
    } else {
      // Any multi-touch gesture belongs to zoom/rotate, never media paging.
      _mediaSwipePrimaryPointer = null;
      _mediaSwipeStart = null;
      _mediaSwipeLast = null;
    }
  }

  void _onMediaPointerMove(PointerMoveEvent event) {
    if (_mediaSwipePrimaryPointer != event.pointer ||
        _mediaSwipePointers.length != 1) {
      return;
    }
    _mediaSwipeLast = event.position;
  }

  void _onMediaPointerUp(PointerUpEvent event) {
    final wasPrimary = _mediaSwipePrimaryPointer == event.pointer;
    final start = _mediaSwipeStart;
    final end = _mediaSwipeLast ?? event.position;

    _mediaSwipePointers.remove(event.pointer);

    if (wasPrimary &&
        _mediaSwipePointers.isEmpty &&
        start != null &&
        !_subEditorOpen &&
        !_switchingSwipeMedia) {
      final delta = end - start;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final threshold = math.max(52.0, screenWidth * 0.12);

      // A clear left/right gesture pages the media. Raw pointer tracking means
      // this still works when Pro Image Editor owns the canvas recognizers.
      if (delta.dx.abs() >= threshold &&
          delta.dx.abs() > delta.dy.abs() * 1.15) {
        if (delta.dx < 0) {
          unawaited(_switchSwipeMedia(1));
        } else {
          unawaited(_switchSwipeMedia(-1));
        }
      }
    }

    _mediaSwipePrimaryPointer = null;
    _mediaSwipeStart = null;
    _mediaSwipeLast = null;
  }

  void _onMediaPointerCancel(PointerCancelEvent event) {
    _mediaSwipePointers.remove(event.pointer);
    if (_mediaSwipePrimaryPointer == event.pointer) {
      _mediaSwipePrimaryPointer = null;
      _mediaSwipeStart = null;
      _mediaSwipeLast = null;
    }
  }

  Widget _withMainMediaSwipe(Widget child) {
    if (_isVideo) return child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onMediaPointerDown,
      onPointerMove: _onMediaPointerMove,
      onPointerUp: _onMediaPointerUp,
      onPointerCancel: _onMediaPointerCancel,
      child: child,
    );
  }

  void _finish(ProImageEditorState editor) {
    if (_finishing) return;
    if (!_selected) _setCurrentMediaSelected(true, notify: false);
    _sendOnComplete = true;
    setState(() => _finishing = true);
    unawaited(HapticFeedback.lightImpact());
    editor.doneEditing();
  }

  Future<void> _disposeVideoPlaybackForExit() async {
    if (!_isVideo) return;

    final player = _videoPlayerController;
    final proController = _proVideoController;

    _videoPlayerController = null;
    _proVideoController = null;

    if (player != null) {
      player.removeListener(_syncVideoPosition);
      try {
        await player.pause();
      } catch (_) {}
    }

    // Dispose the ProImageEditor video controller before the camera route
    // becomes visible again. This releases its video surfaces/listeners first.
    try {
      proController?.dispose();
    } catch (_) {}

    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  Future<void> _popEditorResult({
    required String? editedFilePath,
    required bool sendNow,
    required Map<String, String> editedMediaPaths,
  }) async {
    if (!mounted || _poppingEditor) return;
    _poppingEditor = true;

    await _disposeVideoPlaybackForExit();
    if (!mounted) return;

    Navigator.of(context).pop(
      ChatMediaEditorResult(
        editedFilePath: editedFilePath,
        caption: _captionController.text.trim(),
        selected: _selected,
        sendNow: sendNow,
        currentMediaId: _currentMediaId,
        selectedMediaIds: List<String>.unmodifiable(_selectedMediaIds),
        editedMediaPaths: editedMediaPaths,
      ),
    );
  }

  void _handleEditorClosed(EditorMode mode) {
    if (!mounted) return;

    if (mode != EditorMode.main) {
      _setSubEditorOpen(false);
      if (_isVideo) _videoCropPreviewMode.value = false;
      _hideDiscardChangesMenu();
      return;
    }

    unawaited(
      _popEditorResult(
        editedFilePath: _completedPath,
        sendNow: _sendOnComplete,
        editedMediaPaths: Map<String, String>.unmodifiable(
          _editedMediaPathsById,
        ),
      ),
    );
  }

  void _closeWithoutSaving() {
    unawaited(
      _popEditorResult(
        editedFilePath: null,
        sendNow: false,
        editedMediaPaths: const <String, String>{},
      ),
    );
  }

  Widget _buildHeader(ProImageEditorState editor) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final headerHeight = topInset + _headerContentHeight;

    return SizedBox(
      height: headerHeight,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, child) => IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, -0.18),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubic,
              child: child,
            ),
          ),
        ),
        // This editor intentionally removes the package SafeArea so the media
        // canvas remains edge-to-edge. Apply the physical view padding to the
        // custom chrome explicitly; a nested SafeArea would see removed
        // MediaQuery.padding and could overlap a real phone's status bar.
        child: Padding(
          padding: EdgeInsets.fromLTRB(13, topInset + 6, 13, 0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _glassCircleButton(
                  tooltip: widget.openedFromCamera ? 'Back to camera' : 'Back',
                  onTap: _closeWithoutSaving,
                  child: wrytteSvgAssetIcon(
                    assetPath: 'assets/svg/ic--round-arrow-back-ios.svg',
                    canvas: 27,
                    scale: 1.0,
                    offset: const Offset(-0.5, 0),
                    color: WrytteColors.textPrimary,
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 66),
                  child: Center(
                    child: Text(
                      widget.recipientLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFF2F2F2).withValues(alpha: 0.76),
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
              // Camera captures are already a single, explicit media item.
              // Do not show the gallery selection-order circle there because it
              // has no meaningful selection-index workflow.
              if (widget.showSelectionControl && !widget.openedFromCamera)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_finishing) return;
                      unawaited(HapticFeedback.selectionClick());
                      _setCurrentMediaSelected(!_selected);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _selected ? _sentBlue : Colors.transparent,
                        shape: BoxShape.circle,
                        border: _selected
                            ? null
                            : Border.all(color: Colors.white, width: 1.6),
                      ),
                      child: _selected
                          ? Text(
                              '${_currentSelectionNumber ?? 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: WrytteTypography.primaryFontFamily,
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayButton() {
    final player = _videoPlayerController;

    if (!_isVideo || player == null || !player.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final playing = player.value.isPlaying;

        return Semantics(
          button: true,
          label: playing ? 'Pause video' : 'Play video',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(HapticFeedback.selectionClick());
              _proVideoController?.togglePlayState();
            },
            child: AnimatedOpacity(
              opacity: playing ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoPlayOverlay() {
    return Center(child: _buildVideoPlayButton());
  }

  // Crop uses the same play/pause control, but _CropFrameOverlay positions it
  // at the measured crop rectangle's center so it cannot be hidden by the
  // package crop painter and always sits over the visible video.
  Widget _buildCropVideoPlayButton() => _buildVideoPlayButton();

  void _setCustomTrimSpan(TrimDurationSpan span) {
    final controller = _proVideoController;
    if (controller == null) return;

    controller.setTrimSpan(span);

    if (mounted) {
      setState(() => _trimSpan = span);
    } else {
      _trimSpan = span;
    }
  }

  Future<void> _previewVideoAt(Duration requestedPosition) async {
    final player = _videoPlayerController;
    final metadata = _videoMetadata;
    if (player == null || metadata == null || !player.value.isInitialized)
      return;

    final safeMs = requestedPosition.inMilliseconds
        .clamp(0, math.max(0, metadata.duration.inMilliseconds))
        .toInt();
    final position = Duration(milliseconds: safeMs);
    final generation = ++_videoPreviewSeekGeneration;

    _proVideoController?.pause();
    _proVideoController?.setPlayTime(position);

    try {
      await player.pause();
      if (generation != _videoPreviewSeekGeneration) return;
      await player.seekTo(position);
    } catch (_) {
      // A superseded preview seek is harmless; the next drag update/end seek
      // will place the player at the newest requested frame.
    }
  }

  Widget _buildVideoTrimTimeline() {
    final metadata = _videoMetadata;
    final controller = _proVideoController;

    if (!_isVideo || metadata == null || controller == null) {
      return const SizedBox(height: 48);
    }

    final span =
        _trimSpan ??
        TrimDurationSpan(start: Duration.zero, end: metadata.duration);

    return TelegramVideoTrimTimeline(
      duration: metadata.duration,
      span: span,
      playhead: _videoPosition,
      thumbnails: _videoThumbnails,
      onInteractionStart: () {
        controller.pause();
        unawaited(_videoPlayerController?.pause() ?? Future<void>.value());
      },
      onChanged: _setCustomTrimSpan,
      onChangeEnd: (nextSpan) {
        unawaited(_seekVideoToSpan(nextSpan));
      },
      onSeek: (position) {
        unawaited(_previewVideoAt(position));
      },
    );
  }

  Widget _buildVideoTrimControls() {
    final controller = _proVideoController;

    if (!_isVideo || _videoMetadata == null || controller == null) {
      return const SizedBox(height: _videoTrimControlsHeight);
    }

    return SizedBox(
      height: _videoTrimControlsHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                toggled: _videoMuted,
                label: _videoMuted
                    ? 'Send as video with sound'
                    : 'Remove sound',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    controller.setMuteState(!_videoMuted);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.48),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey<bool>(_videoMuted),
                        child: wrytteSvgAssetIcon(
                          assetPath: _videoMuted
                              ? 'assets/svg/Gif icon.svg'
                              : 'assets/svg/Sound icon.svg',
                          canvas: 20,
                          scale: 1.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 44 + 5 + 48 keeps the complete trim-controls block at the existing
          // 97dp height while giving the sound/GIF control more presence.
          const SizedBox(height: 5),
          _buildVideoTrimTimeline(),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ProImageEditorState editor) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;
    return SizedBox(
      height: _mainBottomBarHeight + bottomSafeInset,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        maintainBottomViewPadding: true,
        child: Transform.translate(
          offset: Offset(0, -keyboardInset),
          child: ValueListenableBuilder<bool>(
            valueListenable: _chromeVisible,
            builder: (context, visible, child) => IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 0.20),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  child: child,
                ),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                // Keep the old-wrytte control sizes, but let the fixed-height
                // bar own the spacing so its children can never exceed it.
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isVideo && !_subEditorOpen) ...[
                      _buildVideoTrimControls(),
                      // The old-wrytte bar is intentionally shorter than the
                      // cleanup branch. Keep its dimensions without letting the
                      // trim gap create a bottom overflow.
                      const SizedBox(height: 0),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            type: MaterialType.transparency,
                            child: _captionField(),
                          ),
                        ),
                        const SizedBox(width: 9),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _finishing ? null : () => _finish(editor),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: _editorCircleButtonSize,
                            height: _editorCircleButtonSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _sentBlue.withValues(
                                alpha: _finishing ? 0.70 : 1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: _finishing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Transform.translate(
                                    offset: const Offset(-1.5, 0),
                                    child: Transform.rotate(
                                      angle: math.pi / 4,
                                      child: wrytteSvgAssetIcon(
                                        assetPath: 'assets/svg/Send icon .svg',
                                        canvas: 25,
                                        scale: 1.12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    // Keep the edit-tools container anchored while the keyboard
                    // is shown; the whole chrome translates above the IME.
                    const SizedBox(height: 7),
                    _editorTools(editor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _captionField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: wrytteGlassDecoration(radius: 21),
          child: SizedBox(
            height: _composerControlHeight,
            child: TextField(
              controller: _captionController,
              focusNode: _captionFocusNode,
              enabled: !_finishing,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.done,
              cursorColor: _sentBlue,
              cursorWidth: 1.5,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Add a caption...',
                hintStyle: TextStyle(
                  color: WrytteColors.textSecondary.withValues(alpha: 0.72),
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCropEditor(ProImageEditorState editor) {
    _setSubEditorOpen(true);
    _cropSessionActive = _activeCropEdit;
    if (_isVideo) {
      _videoCropPreviewMode.value = true;
      _proVideoController?.pause();
      unawaited(_videoPlayerController?.pause() ?? Future<void>.value());
    }
    editor.openCropRotateEditor();
  }

  void _openFilterEditor(ProImageEditorState editor) {
    _setSubEditorOpen(true);
    _filterSessionActive = _activeFilterEdit;
    editor.openFilterEditor();
  }

  bool _hasDrawEdit(ProImageEditorState editor) {
    return editor.activeLayers.any((layer) => layer is PaintLayer);
  }

  bool _hasTextEdit(ProImageEditorState editor) {
    return editor.activeLayers.any((layer) => layer is TextLayer);
  }

  bool _hasStickerEdit(ProImageEditorState editor) {
    return editor.activeLayers.any((layer) => layer is EmojiLayer);
  }

  Widget _editorTools(ProImageEditorState editor) {
    final drawActive = _hasDrawEdit(editor);
    final textActive = _hasTextEdit(editor);
    final stickerActive = _hasStickerEdit(editor);

    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: wrytteGlassDecoration(radius: 21),
          child: SizedBox(
            height: _composerControlHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolButtonSvg(
                  assetPath: 'assets/svg/Crop icon.svg',
                  label: 'Crop',
                  selected: _activeCropEdit,
                  onTap: () => _openCropEditor(editor),
                ),
                _toolButtonSvg(
                  assetPath: 'assets/svg/Draw icon.svg',
                  label: 'Draw',
                  selected: drawActive,
                  onTap: () => _openPaintEditor(editor),
                ),
                _toolButtonSvg(
                  assetPath: 'assets/svg/Text icon.svg',
                  label: 'Text',
                  selected: textActive,
                  onTap: () => _openTextEditor(editor),
                ),
                _toolButtonSvg(
                  assetPath: 'assets/svg/Sticker icon.svg',
                  label: 'Sticker',
                  selected: stickerActive,
                  onTap: () {
                    _setSubEditorOpen(true);
                    editor.openEmojiEditor();
                  },
                ),
                _toolButtonSvg(
                  assetPath: 'assets/svg/Photo filter .svg',
                  label: 'Filters',
                  selected: _activeFilterEdit,
                  onTap: () => _openFilterEditor(editor),
                  canvas: 26,
                  scale: 1.08,
                ),
                _qualityToggleButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qualityToggleButton() {
    final assetPath = _isHd
        ? 'assets/svg/Hd icon .svg'
        : 'assets/svg/Sd icon.svg';
    final label = _isHd ? 'HD quality' : 'SD quality';

    return Expanded(
      child: Semantics(
        button: true,
        toggled: _isHd,
        label: label,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            setState(() => _isHd = !_isHd);
          },
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              reverseDuration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final turn = Tween<double>(begin: 0.18, end: 0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.72,
                      end: 1,
                    ).animate(animation),
                    child: RotationTransition(turns: turn, child: child),
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(assetPath),
                child: wrytteSvgAssetIcon(
                  assetPath: assetPath,
                  canvas: 24,
                  scale: 0.98,
                  color: WrytteColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolButtonSvg({
    required String assetPath,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    double rotation = 0,
    double canvas = 24,
    double scale = 0.98,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: Transform.rotate(
              angle: rotation,
              child: wrytteSvgAssetIcon(
                assetPath: assetPath,
                canvas: canvas,
                scale: scale,
                color: selected ? _sentBlue : WrytteColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassCircleButton({
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: tooltip,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              child: DecoratedBox(
                decoration: wrytteGlassDecoration(radius: 21),
                child: SizedBox.square(
                  dimension: _editorCircleButtonSize,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openTextEditor(ProImageEditorState editor) {
    _setSubEditorOpen(true);
    _closeTextFontMenu();
    _selectedTextLayer.value = null;
    _textLayerBeingEditedId = null;
    _textTransformCommitInProgress = false;
    _textEmojiPickerVisible.value = false;
    _textEmojiCategory.value = 1;
    _textFontPresetIndex = 0;
    _textAlignment.value = TextAlign.center;
    _textBackgroundStyle.value = _TelegramTextBackgroundStyle.light;
    _textFontScale.value = _textFontScaleDefault;
    _textFontScaleEditor = null;
    _textInitialStylePending = true;
    _textInitialStyleScheduled = false;
    _textTypingHasStarted = false;
    _detachTextEditorTypography();

    // Pro Image Editor opens Text as a transparent overlay over the main editor.
    // Hide the main editor chrome first so only the image remains behind the
    // Text editor, matching the full-screen appearance of the Crop editor.
    _chromeVisible.value = false;
    editor.openTextEditor();
  }

  void _scheduleInitialTextStyle(TextEditorState editor) {
    if (!_textInitialStylePending || _textInitialStyleScheduled) return;

    _textInitialStyleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textInitialStyleScheduled = false;

      if (!_textInitialStylePending || !editor.mounted) return;
      _textInitialStylePending = false;

      // The editor state now exists, so override any contrast/default values
      // that were applied while Pro Image Editor initialized the sub-editor.
      _applyTextBackgroundStyle(editor, _TelegramTextBackgroundStyle.light);
      _applyInitialTextTypography(editor);
      _applyTelegramTextAlignment(editor, TextAlign.center);
    });
  }

  void _bindTextEditorTypography(TextEditorState editor) {
    final controller = editor.textCtrl;
    if (identical(_textTypographyController, controller)) return;

    _detachTextEditorTypography();
    _textTypographyController = controller;

    void listener() {
      if (_textTypingHasStarted || controller.text.isEmpty) return;

      _textTypingHasStarted = true;
      if (!editor.mounted) return;

      // The placeholder has disappeared. From this first character onward,
      // the actual text uses Roboto Regular.
      editor.setTextStyle(
        editor.selectedTextStyle.copyWith(
          fontFamily: _textFontPresets[_textFontPresetIndex].fontFamily,
          fontWeight:
              _textFontPresets[_textFontPresetIndex].fontWeight ??
              _typedTextWeight,
          fontStyle:
              _textFontPresets[_textFontPresetIndex].fontStyle ??
              FontStyle.normal,
        ),
      );
    }

    _textTypographyListener = listener;
    controller.addListener(listener);
  }

  void _applyInitialTextTypography(TextEditorState editor) {
    final hasExistingText = editor.textCtrl.text.isNotEmpty;
    _textTypingHasStarted = hasExistingText;

    editor.setTextStyle(
      editor.selectedTextStyle.copyWith(
        fontFamily: _textFontPresets[_textFontPresetIndex].fontFamily,
        fontWeight: hasExistingText
            ? (_textFontPresets[_textFontPresetIndex].fontWeight ??
                  _typedTextWeight)
            : _textHintWeight,
        fontStyle:
            _textFontPresets[_textFontPresetIndex].fontStyle ??
            FontStyle.normal,
      ),
    );
  }

  void _detachTextEditorTypography() {
    final controller = _textTypographyController;
    final listener = _textTypographyListener;

    if (controller != null && listener != null) {
      controller.removeListener(listener);
    }

    _textTypographyController = null;
    _textTypographyListener = null;
  }

  void _bindTextFontScale(TextEditorState editor) {
    if (identical(_textFontScaleEditor, editor)) return;

    _textFontScaleEditor = editor;
    final editorScale = editor.fontScale
        .clamp(_textFontScaleMin, _textFontScaleMax)
        .toDouble();

    if ((_textFontScale.value - editorScale).abs() > 0.001) {
      _textFontScale.value = editorScale;
    }
  }

  void _setTelegramTextFontScale(
    TextEditorState editor,
    double requestedScale,
  ) {
    final scale = requestedScale
        .clamp(_textFontScaleMin, _textFontScaleMax)
        .toDouble();

    if ((editor.fontScale - scale).abs() < 0.002) return;

    // Updating the real editor property keeps the text, cursor, wrapping,
    // rounded background, hitbox and exported layer on the same scale.
    editor.setState(() {
      editor.fontScale = scale;
    });

    if ((_textFontScale.value - scale).abs() > 0.001) {
      _textFontScale.value = scale;
    }

    // Let the rounded background and current alignment settle again after the
    // resized paragraph receives its new line metrics.
    _scheduleTelegramTextAlignmentRelayout(editor, editor.align);
  }

  void _applyTextBackgroundStyle(
    TextEditorState editor,
    _TelegramTextBackgroundStyle style,
  ) {
    final textColor = switch (style) {
      _TelegramTextBackgroundStyle.light => Colors.black,
      _TelegramTextBackgroundStyle.dark => Colors.white,
      _TelegramTextBackgroundStyle.transparent => Colors.white,
    };

    final backgroundColor = switch (style) {
      _TelegramTextBackgroundStyle.light => Colors.white,
      _TelegramTextBackgroundStyle.dark => _textLayerDarkOverlay,
      _TelegramTextBackgroundStyle.transparent => Colors.transparent,
    };

    final backgroundMode = style == _TelegramTextBackgroundStyle.transparent
        ? LayerBackgroundMode.onlyColor
        : LayerBackgroundMode.backgroundAndColor;

    editor.setState(() {
      editor.primaryColor = textColor;
      editor.secondaryColor = backgroundColor;
      editor.backgroundColorMode = backgroundMode;
      editor.selectedTextStyle = editor.selectedTextStyle.copyWith(
        color: textColor,
      );
    });

    if (_textBackgroundStyle.value != style) {
      _textBackgroundStyle.value = style;
    }
  }

  void _setTextColor(TextEditorState editor, Color color) {
    editor.primaryColor = color;
    editor.setTextStyle(editor.selectedTextStyle.copyWith(color: color));
  }

  Widget _buildTextBottomBar(TextEditorState editor, {required double height}) {
    return SizedBox(
      height: height,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Preserve the screenshot proportions on normal phones, but allow
              // the center pill to contract on narrow devices instead of causing
              // a horizontal overflow.
              final toolbarWidth = (constraints.maxWidth - 112)
                  .clamp(164.0, 222.0)
                  .toDouble();

              return Row(
                children: [
                  _cropRoundActionButton(
                    tooltip: 'Cancel text',
                    onTap: () => _cancelTextEditing(editor),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 29,
                      color: WrytteColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: _buildTextToolbar(editor, width: toolbarWidth),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _cropRoundActionButton(
                    tooltip: 'Apply text',
                    backgroundColor: _sentBlue,
                    onTap: () => _applyTextEditing(editor),
                    child: wrytteSvgAssetIcon(
                      assetPath: 'assets/svg/Checkmark edit.svg',
                      canvas: 27,
                      scale: 0.92,
                      color: Colors.white,
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

  Widget _buildTextToolbar(TextEditorState editor, {required double width}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: wrytteGlassDecoration(radius: 21),
          child: SizedBox(
            width: width,
            height: _textToolbarHeight,
            child: Row(
              children: [
                _textBackgroundToolbarButton(editor),
                ValueListenableBuilder<TextAlign>(
                  valueListenable: _textAlignment,
                  builder: (context, align, child) => _textToolbarButton(
                    tooltip: _textAlignmentTooltip(align),
                    assetPath: _textAlignmentAsset(align),
                    onTap: () => _cycleTextAlignment(editor),
                    canvas: 25,
                    scale: 0.96,
                  ),
                ),
                _textToolbarButton(
                  tooltip: 'Insert sticker',
                  assetPath: _textStickerEditSvg,
                  onTap: () => _toggleTextEmojiPicker(editor),
                  canvas: 24,
                  scale: 0.94,
                ),
                _textToolbarButton(
                  key: _textFontButtonKey,
                  tooltip: 'Choose font',
                  assetPath: 'assets/svg/Fonts type icon.svg',
                  onTap: () => _toggleTextFontMenu(editor),
                  canvas: 26,
                  scale: 0.96,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _textAlignmentAsset(TextAlign align) {
    return switch (align) {
      TextAlign.right => _textAlignRightSvg,
      TextAlign.left => _textAlignLeftSvg,
      _ => _textAlignCenterSvg,
    };
  }

  String _textAlignmentTooltip(TextAlign align) {
    return switch (align) {
      TextAlign.right => 'Text aligned right. Tap to change.',
      TextAlign.left => 'Text aligned left. Tap to change.',
      _ => 'Text aligned center. Tap to change.',
    };
  }

  void _cycleTextAlignment(TextEditorState editor) {
    final nextAlign = switch (_textAlignment.value) {
      TextAlign.center => TextAlign.right,
      TextAlign.right => TextAlign.left,
      _ => TextAlign.center,
    };

    _applyTelegramTextAlignment(editor, nextAlign);
  }

  void _applyTelegramTextAlignment(
    TextEditorState editor,
    TextAlign targetAlign,
  ) {
    // Use Pro Image Editor's own toggle method rather than only mutating
    // `align`. Its method updates the RoundedBackgroundTextField and the
    // TextLayer using the package's expected state path.
    var attempts = 0;
    while (editor.align != targetAlign && attempts < 3) {
      editor.toggleTextAlign();
      attempts++;
    }

    // Defensive fallback for package versions whose toggle order differs.
    if (editor.align != targetAlign) {
      editor.setState(() {
        editor.align = targetAlign;
      });
    }

    if (_textAlignment.value != targetAlign) {
      _textAlignment.value = targetAlign;
    }

    _scheduleTelegramTextAlignmentRelayout(editor, targetAlign);
  }

  void _scheduleTelegramTextAlignmentRelayout(
    TextEditorState editor,
    TextAlign targetAlign,
  ) {
    _pendingTextAlignment = targetAlign;
    if (_textAlignmentRelayoutScheduled) return;

    _textAlignmentRelayoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textAlignmentRelayoutScheduled = false;

      final pendingAlign = _pendingTextAlignment;
      _pendingTextAlignment = null;

      if (pendingAlign == null || !editor.mounted) return;

      // Telegram recalculates its text/background geometry after measure and
      // layout. This second state pass gives the Flutter rounded-background
      // painter the same opportunity after the alignment has changed.
      editor.setState(() {
        editor.align = pendingAlign;
      });

      if (_textAlignment.value != pendingAlign) {
        _textAlignment.value = pendingAlign;
      }
    });
  }

  Widget _textBackgroundToolbarButton(TextEditorState editor) {
    return Expanded(
      child: ValueListenableBuilder<_TelegramTextBackgroundStyle>(
        valueListenable: _textBackgroundStyle,
        builder: (context, style, child) {
          final previewColor = switch (style) {
            _TelegramTextBackgroundStyle.light => Colors.white,
            _TelegramTextBackgroundStyle.dark => _textToolbarActiveGrey,
            _TelegramTextBackgroundStyle.transparent => Colors.transparent,
          };
          final letterColor = style == _TelegramTextBackgroundStyle.light
              ? Colors.black
              : Colors.white;
          final stateLabel = switch (style) {
            _TelegramTextBackgroundStyle.light =>
              'White background with black text',
            _TelegramTextBackgroundStyle.dark =>
              'Dark translucent background with white text',
            _TelegramTextBackgroundStyle.transparent =>
              'Transparent background with white text',
          };

          return Semantics(
            button: true,
            label: '$stateLabel. Tap to change.',
            child: InkWell(
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                _cycleTextBackground(editor);
              },
              splashFactory: NoSplash.splashFactory,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: previewColor,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: letterColor,
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                    child: const Text(
                      'A',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _cycleTextBackground(TextEditorState editor) {
    final nextStyle = switch (_textBackgroundStyle.value) {
      _TelegramTextBackgroundStyle.light => _TelegramTextBackgroundStyle.dark,
      _TelegramTextBackgroundStyle.dark =>
        _TelegramTextBackgroundStyle.transparent,
      _TelegramTextBackgroundStyle.transparent =>
        _TelegramTextBackgroundStyle.light,
    };

    _textInitialStylePending = false;
    _applyTextBackgroundStyle(editor, nextStyle);
  }

  Widget _textToolbarButton({
    Key? key,
    required String tooltip,
    required String assetPath,
    required VoidCallback onTap,
    double canvas = 24,
    double scale = 1,
  }) {
    return Expanded(
      child: Semantics(
        key: key,
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: wrytteSvgAssetIcon(
              assetPath: assetPath,
              canvas: canvas,
              scale: scale,
              color: WrytteColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  double _textEmojiPanelHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return (screenHeight * 0.43)
        .clamp(310.0, _textEmojiPanelPreferredHeight + bottomInset)
        .toDouble();
  }

  Widget _buildTextEmojiPicker(
    TextEditorState editor, {
    required double height,
  }) {
    final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: wrytteGlassDecoration(radius: 30),
            child: SizedBox(
              height: height,
              child: ValueListenableBuilder<int>(
                valueListenable: _textEmojiCategory,
                builder: (context, selectedCategory, child) {
                  final safeCategory = selectedCategory.clamp(
                    0,
                    _textEmojiCategories.length - 1,
                  );
                  final emojis = _textEmojiCategories[safeCategory];

                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 26,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _textEmojiCategoryNames[safeCategory],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.68),
                                  fontFamily:
                                      WrytteTypography.primaryFontFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _closeTextEmojiPicker(editor),
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: Icon(
                                  Icons.keyboard_hide_rounded,
                                  size: 22,
                                  color: Colors.white.withValues(alpha: 0.68),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                          physics: const BouncingScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                                mainAxisSpacing: 3,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: emojis.length,
                          itemBuilder: (context, index) {
                            final emoji = emojis[index];

                            return InkWell(
                              onTap: () => _insertTextEmoji(editor, emoji),
                              splashFactory: NoSplash.splashFactory,
                              overlayColor: const WidgetStatePropertyAll<Color>(
                                Colors.transparent,
                              ),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(
                                    fontSize: 29,
                                    height: 1,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        height: 48 + bottomSafeInset,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 7,
                            right: 7,
                            bottom: bottomSafeInset,
                          ),
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < _textEmojiCategoryIcons.length;
                                index++
                              )
                                Expanded(
                                  child: _textEmojiCategoryButton(
                                    index: index,
                                    selected: safeCategory == index,
                                  ),
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
        ),
      ),
    );
  }

  Widget _textEmojiCategoryButton({
    required int index,
    required bool selected,
  }) {
    return InkWell(
      onTap: () {
        unawaited(HapticFeedback.selectionClick());
        _textEmojiCategory.value = index;
      },
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _textEmojiCategoryIcons[index],
            size: 21,
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.58),
          ),
        ),
      ),
    );
  }

  void _toggleTextEmojiPicker(TextEditorState editor) {
    _closeTextFontMenu();
    final opening = !_textEmojiPickerVisible.value;

    if (opening) {
      editor.focusNode.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      _textEmojiPickerVisible.value = true;
    } else {
      _closeTextEmojiPicker(editor, restoreKeyboard: true);
    }
  }

  void _closeTextEmojiPicker(
    TextEditorState editor, {
    bool restoreKeyboard = false,
  }) {
    if (!_textEmojiPickerVisible.value) return;

    _textEmojiPickerVisible.value = false;

    if (restoreKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (editor.mounted) editor.focusNode.requestFocus();
      });
    }
  }

  void _insertTextEmoji(TextEditorState editor, String emoji) {
    final controller = editor.textCtrl;
    final selection = controller.selection;
    final start = selection.start >= 0
        ? selection.start
        : controller.text.length;
    final end = selection.end >= 0 ? selection.end : start;
    final updatedText = controller.text.replaceRange(start, end, emoji);

    controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _toggleTextFontMenu(TextEditorState editor) {
    unawaited(HapticFeedback.selectionClick());

    if (_textFontOverlay != null) {
      _closeTextFontMenu();
      return;
    }

    // Keep only one floating text panel visible at a time.
    _closeTextEmojiPicker(editor);

    final overlay = Overlay.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    const menuWidth = 226.0;
    const menuHeight = 330.0;

    final targetContext = _textFontButtonKey.currentContext;
    final targetRenderObject = targetContext?.findRenderObject();

    double menuLeft = math
        .max(12.0, screenSize.width - menuWidth - 12)
        .toDouble();
    double menuBottom =
        mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom + 78;

    if (targetRenderObject is RenderBox &&
        targetRenderObject.attached &&
        targetRenderObject.hasSize) {
      final targetTopLeft = targetRenderObject.localToGlobal(Offset.zero);
      final targetCenter = targetRenderObject.localToGlobal(
        targetRenderObject.size.center(Offset.zero),
      );

      if (targetCenter.dx.isFinite) {
        final maximumLeft = math.max(12.0, screenSize.width - menuWidth - 12);
        menuLeft = (targetCenter.dx - menuWidth / 2)
            .clamp(12.0, maximumLeft)
            .toDouble();
      }

      if (targetTopLeft.dy.isFinite) {
        final requestedBottom = screenSize.height - targetTopLeft.dy + 10;
        final minimumBottom =
            mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom + 72;
        final maximumBottom = math.max(
          minimumBottom,
          screenSize.height - mediaQuery.padding.top - menuHeight - 10,
        );

        menuBottom = requestedBottom
            .clamp(minimumBottom, maximumBottom)
            .toDouble();
      }
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeTextFontMenu,
            ),
          ),
          Positioned(
            left: menuLeft,
            bottom: menuBottom,
            width: menuWidth,
            child: _buildTextFontMenu(editor),
          ),
        ],
      ),
    );

    _textFontOverlay = entry;
    overlay.insert(entry);
  }

  Widget _buildTextFontMenu(TextEditorState editor) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 226, maxHeight: 330),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              // Reuse the exact glass surface and radius used by the existing
              // shape chooser shown in the reference image.
              decoration: wrytteGlassDecoration(radius: 26),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (
                      var index = 0;
                      index < _textFontPresets.length;
                      index++
                    )
                      _textFontMenuButton(editor: editor, index: index),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textFontMenuButton({
    required TextEditorState editor,
    required int index,
  }) {
    final fontStyle = _textFontPresets[index];
    final isActive = index == _textFontPresetIndex;

    return Semantics(
      button: true,
      selected: isActive,
      label: 'Use ${_textFontNames[index]} font',
      child: InkWell(
        onTap: () => _selectTextFont(editor, index),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _textFontNames[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fontStyle.copyWith(
                  color: isActive ? _sentBlue : WrytteColors.textPrimary,
                  fontSize: 16,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectTextFont(TextEditorState editor, int index) {
    if (index < 0 || index >= _textFontPresets.length) return;

    unawaited(HapticFeedback.selectionClick());
    _textFontPresetIndex = index;

    final preset = _textFontPresets[index];
    final hasText = editor.textCtrl.text.isNotEmpty;

    // Change only font properties. Text color, size, alignment, background,
    // scale and every other text setting stay untouched.
    editor.setTextStyle(
      editor.selectedTextStyle.copyWith(
        fontFamily: preset.fontFamily,
        fontWeight: hasText
            ? (preset.fontWeight ?? FontWeight.w400)
            : _textHintWeight,
        fontStyle: preset.fontStyle ?? FontStyle.normal,
      ),
    );

    _scheduleTelegramTextAlignmentRelayout(editor, editor.align);
    _closeTextFontMenu();
    editor.focusNode.requestFocus();
  }

  void _closeTextFontMenu() {
    final entry = _textFontOverlay;
    _textFontOverlay = null;

    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  void _clearTextEditorTransientState() {
    _textInitialStylePending = false;
    _textInitialStyleScheduled = false;
    _textAlignmentRelayoutScheduled = false;
    _pendingTextAlignment = null;
    _textFontScaleEditor = null;
    _detachTextEditorTypography();
  }

  void _cancelTextEditing(TextEditorState editor) {
    unawaited(HapticFeedback.selectionClick());
    _showDiscardChangesMenu(onDiscard: () => _discardTextEditing(editor));
  }

  void _discardTextEditing(TextEditorState editor) {
    _closeTextFontMenu();
    _textEmojiPickerVisible.value = false;
    _textTransformCommitInProgress = false;
    _textLayerBeingEditedId = null;
    _clearTextEditorTransientState();

    _setSubEditorOpen(false);
    _chromeVisible.value = true;
    editor.close();
  }

  void _applyTextEditing(TextEditorState editor) {
    unawaited(HapticFeedback.selectionClick());
    unawaited(_commitTextForCanvasTransform(editor));
  }

  Future<void> _commitTextForCanvasTransform(TextEditorState editor) async {
    if (_textTransformCommitInProgress || !editor.mounted) return;

    final rawText = editor.textCtrl.text;
    if (rawText.trim().isEmpty) {
      _closeTextEmojiPicker(editor, restoreKeyboard: true);
      return;
    }

    _textTransformCommitInProgress = true;

    final mainEditor = _editorKey.currentState;
    final previousTextIds =
        mainEditor?.activeLayers
            .whereType<TextLayer>()
            .map((layer) => layer.id)
            .toSet() ??
        <String>{};
    final editedLayerId = _textLayerBeingEditedId;
    final emojiWasVisible = _textEmojiPickerVisible.value;

    _closeTextFontMenu();
    _textEmojiPickerVisible.value = false;
    editor.focusNode.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _clearTextEditorTransientState();

    // Let the keyboard-like emoji panel and bottom toolbar visibly slide down
    // before the text sub-editor is removed.
    if (emojiWasVisible) {
      await Future<void>.delayed(const Duration(milliseconds: 190));
    }

    if (!mounted || !editor.mounted) {
      _textTransformCommitInProgress = false;
      return;
    }

    _chromeVisible.value = true;
    editor.done();

    unawaited(
      _selectCommittedTextLayer(
        previousTextIds: previousTextIds,
        editedLayerId: editedLayerId,
      ),
    );
  }

  Future<void> _selectCommittedTextLayer({
    required Set<String> previousTextIds,
    required String? editedLayerId,
  }) async {
    // TextEditor.done() closes with an animation and the main history can be
    // updated a frame later. Retry briefly instead of depending on one frame.
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 45),
      Duration(milliseconds: 90),
      Duration(milliseconds: 160),
      Duration(milliseconds: 260),
      Duration(milliseconds: 420),
    ];

    for (final delay in retryDelays) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (!mounted) break;

      final editor = _editorKey.currentState;
      if (editor == null) continue;

      final textLayers = editor.activeLayers.whereType<TextLayer>().toList(
        growable: false,
      );
      TextLayer? target;

      if (editedLayerId != null) {
        for (final layer in textLayers) {
          if (layer.id == editedLayerId) {
            target = layer;
            break;
          }
        }
      }

      if (target == null) {
        for (final layer in textLayers.reversed) {
          if (!previousTextIds.contains(layer.id)) {
            target = layer;
            break;
          }
        }
      }

      target ??= textLayers.isNotEmpty ? textLayers.last : null;

      if (target != null) {
        // Remove the package's default selection decoration so only the custom
        // Telegram dots are displayed.
        editor.clearLayerSelection();
        _selectedTextLayer.value = target;
        _textLayerBeingEditedId = null;
        _textTransformCommitInProgress = false;
        editor.setState(() {});
        return;
      }
    }

    _textLayerBeingEditedId = null;
    _textTransformCommitInProgress = false;
  }

  void _editTextLayerFromCanvas(ProImageEditorState editor, TextLayer layer) {
    unawaited(HapticFeedback.selectionClick());

    _closeTextFontMenu();
    _textEmojiPickerVisible.value = false;
    _textEmojiCategory.value = 1;
    _selectedTextLayer.value = null;
    _textLayerBeingEditedId = layer.id;
    _textTransformCommitInProgress = false;
    _textAlignment.value = layer.align;
    _textFontScale.value = layer.fontScale
        .clamp(_textFontScaleMin, _textFontScaleMax)
        .toDouble();
    _textInitialStylePending = false;
    _textInitialStyleScheduled = false;
    _textTypingHasStarted = layer.text.isNotEmpty;
    _detachTextEditorTypography();

    editor.clearLayerSelection();
    _chromeVisible.value = false;
    editor.editTextLayer(layer);
  }

  Widget _buildPaintHeader(PaintEditorState editor) {
    _ensurePaintSessionSnapshot(editor);
    final topSafeInset = MediaQuery.viewPaddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, topSafeInset + 8, 18, 0),
      child: Align(
        alignment: Alignment.topRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _paintHeaderCircleButton(
              tooltip: 'Undo drawing',
              enabled: editor.canUndo,
              onTap: () => _undoPaintAction(editor),
              child: wrytteSvgAssetIcon(
                assetPath: 'assets/svg/Undo left icon.svg',
                canvas: 23,
                scale: 0.78,
                color: WrytteColors.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Container(
              key: _paintColorCircleKey,
              width: _editorCircleButtonSize,
              height: _editorCircleButtonSize,
              decoration: BoxDecoration(
                color: editor.activeColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verticalPaintColorPicker({
    required ValueChanged<Color> onColorChanged,
  }) {
    const pickerHeight = 174.0;
    const pickerWidth = 13.0;
    const pickerTouchWidth = 28.0;

    // Reference-style order:
    // white/grey/black at the top, then red and the complete spectrum.
    const colors = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFC9C9C9),
      Color(0xFF777777),
      Color(0xFF171717),
      Color(0xFF000000),
      Color(0xFFFF0000),
      Color(0xFFFF6A00),
      Color(0xFFFFFF00),
      Color(0xFF66FF00),
      Color(0xFF00FF45),
      Color(0xFF00FFD5),
      Color(0xFF00BFFF),
      Color(0xFF1957FF),
      Color(0xFF5028FF),
      Color(0xFF8A20FF),
      Color(0xFFE51CFF),
      Color(0xFFFF168E),
      Color(0xFFFF3158),
    ];

    const stops = <double>[
      0.00,
      0.045,
      0.09,
      0.145,
      0.18,
      0.205,
      0.28,
      0.36,
      0.44,
      0.52,
      0.60,
      0.68,
      0.76,
      0.83,
      0.89,
      0.94,
      0.975,
      1.00,
    ];

    Color colorAtPosition(double localY) {
      final progress = (localY / pickerHeight).clamp(0.0, 1.0);

      for (var index = 0; index < stops.length - 1; index++) {
        final start = stops[index];
        final end = stops[index + 1];

        if (progress <= end) {
          final sectionProgress = ((progress - start) / (end - start)).clamp(
            0.0,
            1.0,
          );

          return Color.lerp(
                colors[index],
                colors[index + 1],
                sectionProgress,
              ) ??
              colors[index];
        }
      }

      return colors.last;
    }

    void updateColor(double localY) {
      onColorChanged(colorAtPosition(localY.clamp(0.0, pickerHeight)));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        unawaited(HapticFeedback.selectionClick());
        updateColor(details.localPosition.dy);
      },
      onVerticalDragStart: (details) {
        unawaited(HapticFeedback.selectionClick());
        updateColor(details.localPosition.dy);
      },
      onVerticalDragUpdate: (details) => updateColor(details.localPosition.dy),
      child: SizedBox(
        width: pickerTouchWidth,
        height: pickerHeight,
        child: Center(
          child: Container(
            width: pickerWidth,
            height: pickerHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFF7F7F7), width: 1),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
                stops: stops,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
                BoxShadow(
                  color: Color(0x55FFFFFF),
                  blurRadius: 3,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paintHeaderCircleButton({
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.42,
        duration: const Duration(milliseconds: 160),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled
                    ? () {
                        unawaited(HapticFeedback.selectionClick());
                        onTap();
                      }
                    : null,
                splashFactory: NoSplash.splashFactory,
                child: DecoratedBox(
                  decoration: wrytteGlassDecoration(radius: 21),
                  child: SizedBox.square(
                    dimension: _editorCircleButtonSize,
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaintBottomBar(PaintEditorState editor) {
    _ensurePaintSessionSnapshot(editor);
    final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;

    // This bar is mounted inside `bodyItems` as a Positioned overlay. It never
    // becomes Scaffold.bottomNavigationBar, so its height and explicit physical
    // navigation inset cannot reduce or refit the image canvas.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: _bottomBarHeight + bottomSafeInset,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          maintainBottomViewPadding: true,
          minimum: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _resetPaintEditor(editor),
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.resolveWith<Color?>(
                              (states) => states.contains(WidgetState.pressed)
                                  ? const Color(0xFFB8B8B8)
                                  : WrytteColors.textPrimary,
                            ),
                        overlayColor: const WidgetStatePropertyAll<Color>(
                          Colors.transparent,
                        ),
                        splashFactory: NoSplash.splashFactory,
                        minimumSize: const WidgetStatePropertyAll<Size>(
                          Size.zero,
                        ),
                        padding:
                            const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                              EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const WidgetStatePropertyAll<TextStyle>(
                          TextStyle(
                            fontFamily: WrytteTypography.primaryFontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      child: const Text('Reset'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _cropRoundActionButton(
                          tooltip: 'Cancel drawing',
                          onTap: () => _cancelPaintEditing(editor),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 29,
                            color: WrytteColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        _buildPaintBrushToolbar(editor, width: 222),
                        const Spacer(),
                        _cropRoundActionButton(
                          tooltip: 'Apply drawing',
                          backgroundColor: _sentBlue,
                          onTap: () => _applyPaintEditing(editor),
                          child: wrytteSvgAssetIcon(
                            assetPath: 'assets/svg/Checkmark edit.svg',
                            canvas: 27,
                            scale: 0.92,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // The selector floats above the X button instead of increasing
                // the bottom bar height and shrinking the image viewport.
                Positioned(
                  left: 0,
                  bottom: 56,
                  width: 58,
                  child: ValueListenableBuilder<PaintLayer?>(
                    valueListenable: _selectedPaintShape,
                    builder: (context, selectedLayer, child) {
                      final fillLayer =
                          selectedLayer != null &&
                              _paintLayerStillExists(editor, selectedLayer) &&
                              _paintLayerSupportsFill(selectedLayer)
                          ? selectedLayer
                          : null;

                      if (fillLayer == null) return const SizedBox.shrink();
                      return _paintFillSelector(editor, fillLayer);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaintBrushToolbar(
    PaintEditorState editor, {
    required double width,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: wrytteGlassDecoration(radius: 21),
          child: SizedBox(
            width: width,
            height: 42,
            child: Row(
              children: [
                _paintBrushButton(
                  editor: editor,
                  tooltip: 'Thin brush',
                  assetPath: 'assets/svg/Draw icon 1.svg',
                  strokeWidth: 3,
                ),
                _paintBrushButton(
                  editor: editor,
                  tooltip: 'Medium brush',
                  assetPath: 'assets/svg/Draw icon 2.svg',
                  strokeWidth: 6,
                ),
                _paintBrushButton(
                  editor: editor,
                  tooltip: 'Thick brush',
                  assetPath: 'assets/svg/Draw icon 3.svg',
                  strokeWidth: 10,
                ),
                _paintMoreBrushButton(editor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paintMoreBrushButton(PaintEditorState editor) {
    final shapeSelected = editor.paintMode != PaintMode.freeStyle;

    return Expanded(
      child: Semantics(
        button: true,
        selected: shapeSelected,
        label: 'Choose drawing shape',
        child: InkWell(
          onTap: () => _togglePaintShapeMenu(editor),
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: SizedBox(
              key: _paintShapeButtonKey,
              width: 40,
              height: 40,
              child: Center(
                child: const Icon(
                  Icons.add_rounded,
                  size: 29,
                  color: WrytteColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openPaintEditor(ProImageEditorState editor) {
    _setSubEditorOpen(true);
    _closePaintShapeMenu();
    _selectedPaintShape.value = null;
    _clearPaintSessionSnapshot();
    editor.openPaintEditor();
  }

  void _ensurePaintSessionSnapshot(PaintEditorState editor) {
    if (_paintSessionSnapshotCaptured) return;

    _paintSessionOriginalLayers = <String, PaintLayer>{
      for (final layer in editor.activeHistory.layers.whereType<PaintLayer>())
        layer.id: layer.copyWith(
          items: layer.items.map((item) => item.copy()).toList(growable: false),
        ),
    };
    _paintSessionSnapshotCaptured = true;
  }

  void _restorePaintSessionLayers(PaintEditorState editor) {
    if (!_paintSessionSnapshotCaptured) return;

    final currentLayers = <String, PaintLayer>{
      for (final layer in editor.activeHistory.layers.whereType<PaintLayer>())
        layer.id: layer,
    };

    for (final entry in _paintSessionOriginalLayers.entries) {
      final current = currentLayers[entry.key];
      if (current == null) continue;

      final original = entry.value;
      current
        ..items = original.items
            .map((item) => item.copy())
            .toList(growable: false)
        ..offset = original.offset
        ..rotation = original.rotation
        ..scale = original.scale
        ..flipX = original.flipX
        ..flipY = original.flipY
        ..opacity = original.opacity
        ..boxConstraints = original.boxConstraints;
    }

    editor.setState(() {});
    editor.rebuildController.add(null);
  }

  void _clearPaintSessionSnapshot() {
    _paintSessionOriginalLayers.clear();
    _paintSessionSnapshotCaptured = false;
  }

  void _cancelPaintEditing(PaintEditorState editor) {
    unawaited(HapticFeedback.selectionClick());
    _showDiscardChangesMenu(onDiscard: () => _discardPaintEditing(editor));
  }

  void _discardPaintEditing(PaintEditorState editor) {
    _closePaintShapeMenu();
    _selectedPaintShape.value = null;

    // Restore direct transformations made by the custom handles before the
    // sub-editor is closed, so "Discard changes" really discards this session.
    _restorePaintSessionLayers(editor);
    _clearPaintSessionSnapshot();
    _returnToMainEditorAfterDiscard(editor.context);
  }

  void _applyPaintEditing(PaintEditorState editor) {
    _closePaintShapeMenu();
    _selectedPaintShape.value = null;
    _clearPaintSessionSnapshot();
    editor.done();
  }

  Widget _paintFillSelector(PaintEditorState editor, PaintLayer selectedLayer) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: wrytteGlassDecoration(radius: 20),
            child: SizedBox(
              width: 58,
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _paintFillOption(
                    editor: editor,
                    selectedLayer: selectedLayer,
                    filled: false,
                    tooltip: 'Outline shapes',
                    assetPath: 'assets/svg/Circle icon.svg',
                  ),
                  _paintFillOption(
                    editor: editor,
                    selectedLayer: selectedLayer,
                    filled: true,
                    tooltip: 'Filled shapes',
                    assetPath: 'assets/svg/Fill circle icon.svg',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paintFillOption({
    required PaintEditorState editor,
    required PaintLayer selectedLayer,
    required bool filled,
    required String tooltip,
    required String assetPath,
  }) {
    final selected = selectedLayer.item.fill == filled;

    return SizedBox(
      width: 27,
      height: 40,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            _setSelectedShapeFill(editor, selectedLayer, filled);
          },
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              width: selected ? 25 : 17,
              height: selected ? 25 : 17,
              alignment: Alignment.center,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                scale: selected ? 1.0 : 0.70,
                child: wrytteSvgAssetIcon(
                  assetPath: assetPath,
                  canvas: selected ? 24 : 17,
                  scale: 0.94,
                  color: selected
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF777A80),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _paintLayerStillExists(PaintEditorState editor, PaintLayer layer) {
    return editor.activeHistory.layers.any(
      (candidate) => candidate.id == layer.id,
    );
  }

  bool _paintLayerSupportsFill(PaintLayer layer) {
    switch (layer.item.mode) {
      case PaintMode.rect:
      case PaintMode.circle:
      case PaintMode.polygon:
        return true;
      default:
        return false;
    }
  }

  void _setSelectedShapeFill(
    PaintEditorState editor,
    PaintLayer selectedLayer,
    bool filled,
  ) {
    if (!_paintLayerStillExists(editor, selectedLayer) ||
        !_paintLayerSupportsFill(selectedLayer)) {
      _selectedPaintShape.value = null;
      return;
    }

    selectedLayer.item = selectedLayer.item.copyWith(fill: filled);
    editor.setFill(filled);
    editor.setState(() {});
    editor.rebuildController.add(null);
  }

  void _setPaintColor(PaintEditorState editor, Color color) {
    final selectedLayer = _selectedPaintShape.value;
    if (selectedLayer != null &&
        _paintLayerStillExists(editor, selectedLayer)) {
      selectedLayer.item = selectedLayer.item.copyWith(color: color);
    }

    editor.setColor(color);
    editor.rebuildController.add(null);
  }

  void _undoPaintAction(PaintEditorState editor) {
    editor.undoAction();

    final selectedLayer = _selectedPaintShape.value;
    if (selectedLayer != null &&
        !_paintLayerStillExists(editor, selectedLayer)) {
      _selectedPaintShape.value = null;
    }
  }

  void _insertPaintShape(PaintEditorState editor, PaintMode mode) {
    _closePaintShapeMenu();
    final bodySize = editor.editorBodySize.isEmpty
        ? MediaQuery.sizeOf(context)
        : editor.editorBodySize;
    final shortestSide = math.min(bodySize.width, bodySize.height);
    final extent = (shortestSide * 0.28).clamp(88.0, 154.0).toDouble();
    final center = Offset(bodySize.width / 2, bodySize.height / 2);

    final Offset start;
    final Offset end;
    if (mode == PaintMode.arrow) {
      start = center - Offset(extent * 0.58, 0);
      end = center + Offset(extent * 0.58, 0);
    } else {
      start = center - Offset(extent / 2, extent / 2);
      end = center + Offset(extent / 2, extent / 2);
    }

    const fill = false;
    final previousIds = editor.activeHistory.layers
        .whereType<PaintLayer>()
        .map((layer) => layer.id)
        .toSet();

    editor.setFill(fill);
    editor.addPainting(
      PaintedModel(
        mode: mode,
        offsets: mode == PaintMode.polygon
            ? [
                Offset(center.dx, center.dy - extent / 2),
                Offset(center.dx + extent / 2, center.dy + extent / 2),
                Offset(center.dx - extent / 2, center.dy + extent / 2),
                Offset(center.dx, center.dy - extent / 2),
              ]
            : [start, end],
        erasedOffsets: [],
        color: editor.activeColor,
        strokeWidth: editor.strokeWidth,
        opacity: editor.opacity,
        // Shapes start as outlines. The fill selector can update this same
        // layer after insertion without creating a second shape.
        fill: false,
      ),
    );

    PaintLayer? insertedLayer;
    for (final layer in editor.activeHistory.layers.whereType<PaintLayer>()) {
      if (!previousIds.contains(layer.id)) insertedLayer = layer;
    }

    if (insertedLayer != null) {
      _selectedPaintShape.value = insertedLayer;
      editor.setMode(PaintMode.moveAndZoom);
      editor.rebuildController.add(null);
    }
  }

  void _togglePaintShapeMenu(PaintEditorState editor) {
    unawaited(HapticFeedback.selectionClick());

    if (_paintShapeOverlay != null) {
      _closePaintShapeMenu();
      return;
    }

    final overlay = Overlay.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;

    final targetContext = _paintShapeButtonKey.currentContext;
    final targetRenderObject = targetContext?.findRenderObject();

    final menuWidth = math
        .min(190.0, math.max(0.0, screenSize.width - 20))
        .toDouble();

    double menuLeft = math.max(10.0, screenSize.width - menuWidth - 10);
    double menuBottom = mediaQuery.padding.bottom + 78;

    if (targetRenderObject is RenderBox &&
        targetRenderObject.attached &&
        targetRenderObject.hasSize) {
      final targetTopLeft = targetRenderObject.localToGlobal(Offset.zero);
      final targetCenter = targetRenderObject.localToGlobal(
        targetRenderObject.size.center(Offset.zero),
      );

      if (targetCenter.dx.isFinite) {
        final maximumLeft = math.max(10.0, screenSize.width - menuWidth - 10);
        menuLeft = (targetCenter.dx - menuWidth / 2)
            .clamp(10.0, maximumLeft)
            .toDouble();
      }

      if (targetTopLeft.dy.isFinite) {
        // Keep an exact 10 dp gap between the plus button and the popup.
        menuBottom = math
            .max(
              mediaQuery.padding.bottom + 78,
              screenSize.height - targetTopLeft.dy + 10,
            )
            .toDouble();
      }
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss when the user touches the canvas. Fill/outline is not
          // shown until a shape has actually been inserted and selected.
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: mediaQuery.padding.bottom + 132,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closePaintShapeMenu,
            ),
          ),
          Positioned(
            left: menuLeft,
            bottom: menuBottom,
            width: menuWidth,
            child: _buildPaintShapeMenu(editor),
          ),
        ],
      ),
    );

    _paintShapeOverlay = entry;
    overlay.insert(entry);
  }

  Widget _buildPaintShapeMenu(PaintEditorState editor) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190, maxHeight: 236),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: wrytteGlassDecoration(radius: 26),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paintShapeMenuButton(
                      editor: editor,
                      mode: PaintMode.rect,
                      label: 'Square',
                      tooltip: 'Square',
                      assetPath: 'assets/svg/Square icon .svg',
                    ),
                    _paintShapeMenuButton(
                      editor: editor,
                      mode: PaintMode.circle,
                      label: 'Circle',
                      tooltip: 'Circle',
                      assetPath: 'assets/svg/Circle icon.svg',
                    ),
                    _paintShapeMenuButton(
                      editor: editor,
                      mode: PaintMode.polygon,
                      label: 'Triangle',
                      tooltip: 'Triangle',
                      assetPath: 'assets/svg/Triangle icon.svg',
                    ),
                    _paintShapeMenuButton(
                      editor: editor,
                      mode: PaintMode.arrow,
                      label: 'Arrow',
                      tooltip: 'Arrow',
                      assetPath: 'assets/svg/Arrow icon .svg',
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

  Widget _paintShapeMenuButton({
    required PaintEditorState editor,
    required PaintMode mode,
    required String label,
    required String tooltip,
    String? assetPath,
    IconData? materialIcon,
  }) {
    final selected = editor.paintMode == mode;

    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      child: InkWell(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          _insertPaintShape(editor, mode);
          _closePaintShapeMenu();
        },
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: assetPath != null
                        ? wrytteSvgAssetIcon(
                            assetPath: assetPath,
                            canvas: 22,
                            scale: 0.88,
                            color: WrytteColors.textPrimary,
                          )
                        : Icon(
                            materialIcon,
                            size: 22,
                            color: WrytteColors.textPrimary,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: WrytteColors.textPrimary,
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _closePaintShapeMenu() {
    final entry = _paintShapeOverlay;
    _paintShapeOverlay = null;

    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  Widget _paintBrushButton({
    required PaintEditorState editor,
    required String tooltip,
    required String assetPath,
    required double strokeWidth,
  }) {
    final selected = (editor.strokeWidth - strokeWidth).abs() < 0.1;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            _closePaintShapeMenu();
            _selectedPaintShape.value = null;
            editor.setMode(PaintMode.freeStyle);
            editor.setStrokeWidth(strokeWidth);
          },
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: wrytteSvgAssetIcon(
              assetPath: assetPath,
              canvas: 29,
              scale: 1,
              color: selected ? editor.activeColor : WrytteColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  void _resetPaintEditor(PaintEditorState editor) {
    unawaited(HapticFeedback.selectionClick());
    _closePaintShapeMenu();
    _selectedPaintShape.value = null;
    while (editor.canUndo) {
      editor.undoAction();
    }
    _restorePaintSessionLayers(editor);
    editor.setFill(false);
    editor.setMode(PaintMode.freeStyle);
  }

  List<FilterModel> _availableFilters(FilterEditorState editor) {
    return editor.filterEditorConfigs.filterList ?? presetFiltersList;
  }

  bool _sameFilterMatrices(
    List<List<double>> first,
    List<List<double>> second,
  ) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;

    for (var matrixIndex = 0; matrixIndex < first.length; matrixIndex++) {
      final firstMatrix = first[matrixIndex];
      final secondMatrix = second[matrixIndex];

      if (firstMatrix.length != secondMatrix.length) return false;

      for (var valueIndex = 0; valueIndex < firstMatrix.length; valueIndex++) {
        if ((firstMatrix[valueIndex] - secondMatrix[valueIndex]).abs() >
            0.0001) {
          return false;
        }
      }
    }

    return true;
  }

  bool _isSameFilter(FilterModel first, FilterModel second) {
    if (identical(first, second)) return true;

    return first.name == second.name ||
        _sameFilterMatrices(first.filters, second.filters);
  }

  bool _isOriginalFilter(FilterEditorState editor) {
    final filters = _availableFilters(editor);
    if (filters.isEmpty) return true;

    final selectedName = editor.selectedFilter.name.trim().toLowerCase();
    final nameMeansOriginal =
        selectedName == 'original' ||
        selectedName == 'no filter' ||
        selectedName == 'none';

    return nameMeansOriginal ||
        _isSameFilter(editor.selectedFilter, filters.first);
  }

  Widget _buildFilterFullscreenPreview(FilterEditorState editor) {
    Widget preview;
    final videoController = _videoPlayerController;

    if (_isVideo &&
        videoController != null &&
        videoController.value.isInitialized) {
      preview = FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: videoController.value.size.width,
          height: videoController.value.size.height,
          child: VideoPlayer(videoController),
        ),
      );
    } else {
      final currentEditorImage = editor.editorImage;

      preview = Image(
        image:
            currentEditorImage?.toImageProvider() ??
            FileImage(File(_currentSourcePath)),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: _background,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 26,
              color: Color(0xFF8C929A),
            ),
          ),
        ),
      );
    }

    // Use the exact same matrix application order as the filter thumbnails.
    // This keeps the full-screen preview synchronized with selectedFilter.
    for (final matrix in editor.selectedFilter.filters) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }

    return ColoredBox(
      color: _background,
      child: SizedBox.expand(child: Center(child: preview)),
    );
  }

  Widget _buildFilterHeader(FilterEditorState editor) {
    final isOriginal = _isOriginalFilter(editor);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Exact same clipped glass action container used by Text/Crop.
            _cropRoundActionButton(
              tooltip: 'Cancel filters',
              onTap: () => _cancelFilterEditing(editor),
              child: const Icon(
                Icons.close_rounded,
                size: 29,
                color: WrytteColors.textPrimary,
              ),
            ),

            // Use the same button geometry and exact SVG checkmark used by the
            // crop screen, rather than Flutter's Icons.check_rounded glyph.
            _cropRoundActionButton(
              tooltip: 'Apply filter',
              backgroundColor: isOriginal
                  ? _filterDoneBlue.withValues(alpha: 0.72)
                  : _filterDoneBlue,
              onTap: () {
                unawaited(HapticFeedback.lightImpact());
                setState(() => _activeFilterEdit = _filterSessionActive);
                editor.done();
              },
              child: wrytteSvgAssetIcon(
                assetPath: 'assets/svg/Checkmark edit.svg',
                canvas: 27,
                scale: 0.92,
                color: isOriginal
                    ? Colors.white.withValues(alpha: 0.70)
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cancelFilterEditing(FilterEditorState editor) {
    unawaited(HapticFeedback.selectionClick());
    _showDiscardChangesMenu(
      fromTop: true,
      onDiscard: () {
        _filterSessionActive = _activeFilterEdit;
        _returnToMainEditorAfterDiscard(editor.context);
      },
    );
  }

  Widget _buildFilterBottomBar(FilterEditorState editor) {
    final filters = _availableFilters(editor);
    final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;

    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: _filterBottomBackground,
        child: Padding(
        padding: EdgeInsets.only(bottom: bottomSafeInset),
        child: SizedBox(
          height: _filterBottomPanelHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalSpacing = _filterItemSpacing * 5;
              final availableItemsWidth =
                  constraints.maxWidth -
                  (_filterHorizontalPadding * 2) -
                  totalSpacing;

              // About 5.4 item slots occupy the visible width.
              // The sixth intentionally peeks in from the right before drag.
              final itemWidth = math
                  .max(1.0, availableItemsWidth / _filterVisibleItemCount)
                  .toDouble();

              final previewWidth = (itemWidth - 4)
                  .clamp(_filterPreviewMinWidth, 64.0)
                  .toDouble();
              final previewHeight = previewWidth * 16 / 9;

              return ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: _filterHorizontalPadding,
                  vertical: 12,
                ),
                itemCount: filters.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: _filterItemSpacing),
                itemBuilder: (context, index) {
                  final filter = filters[index];
                  final selected = _isSameFilter(editor.selectedFilter, filter);

                  return _buildFilterPreviewButton(
                    filter: filter,
                    isSelected: selected,
                    onSelectFilter: () {
                      _filterSessionActive = index != 0;
                      editor.setFilter(filter);
                    },
                    previewImage: _buildFilterPreviewSource(),
                    isFirstFilter: index == 0,
                    itemWidth: itemWidth,
                    previewWidth: previewWidth,
                    previewHeight: previewHeight,
                  );
                },
              );
            },
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildFilterPreviewSource() {
    final videoController = _videoPlayerController;

    if (_isVideo &&
        videoController != null &&
        videoController.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: videoController.value.size.width,
            height: videoController.value.size.height,
            child: VideoPlayer(videoController),
          ),
        ),
      );
    }

    return Image.file(
      File(widget.sourcePath),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: Color(0xFF15171A),
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 18,
            color: Color(0xFF8C929A),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPreviewButton({
    required FilterModel filter,
    required bool isSelected,
    required VoidCallback onSelectFilter,
    required Widget previewImage,
    required bool isFirstFilter,
    required double itemWidth,
    required double previewWidth,
    required double previewHeight,
  }) {
    Widget filteredPreview = previewImage;

    for (final matrix in filter.filters) {
      filteredPreview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: filteredPreview,
      );
    }

    final label =
        isFirstFilter && filter.name.trim().toLowerCase() == 'no filter'
        ? 'Original'
        : filter.name;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onSelectFilter();
        },
        child: SizedBox(
          width: itemWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.72),
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 10,
                  height: 1,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 9),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: previewWidth,
                height: previewHeight,
                padding: EdgeInsets.all(isSelected ? 2 : 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: filteredPreview,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCropBottomBar(CropRotateEditorState editor) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          height: 132,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    unawaited(HapticFeedback.selectionClick());
                    editor.reset();
                    _cropSessionActive = _activeCropEdit;
                  },
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                      (states) => states.contains(WidgetState.pressed)
                          ? const Color(0xFFB8B8B8)
                          : WrytteColors.textPrimary,
                    ),
                    overlayColor: const WidgetStatePropertyAll<Color>(
                      Colors.transparent,
                    ),
                    splashFactory: NoSplash.splashFactory,
                    minimumSize: const WidgetStatePropertyAll<Size>(Size.zero),
                    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const WidgetStatePropertyAll<TextStyle>(
                      TextStyle(
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  child: const Text('Reset'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _cropRoundActionButton(
                      tooltip: 'Cancel crop',
                      onTap: () => _cancelCropEditing(editor),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 29,
                        color: WrytteColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(21),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: DecoratedBox(
                          decoration: wrytteGlassDecoration(radius: 21),
                          child: SizedBox(
                            width: 184,
                            height: 42,
                            child: Row(
                              children: [
                                _cropToolButton(
                                  tooltip: 'Rotate left',
                                  assetPath: 'assets/svg/Rotate left icon.svg',
                                  onTap: () {
                                    _cropSessionActive = true;
                                    editor.rotate();
                                  },
                                ),
                                _cropToolButton(
                                  tooltip: 'Flip horizontally',
                                  assetPath: 'assets/svg/Flip mirror icon.svg',
                                  onTap: () {
                                    _cropSessionActive = true;
                                    editor.flip();
                                  },
                                ),
                                _cropToolButton(
                                  tooltip: 'Change aspect ratio',
                                  assetPath: 'assets/svg/Screen size icon.svg',
                                  onTap: () {
                                    _cropSessionActive = true;
                                    _showCropAspectRatioMenu(editor);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _cropRoundActionButton(
                      tooltip: 'Apply crop',
                      backgroundColor: _sentBlue,
                      onTap: () {
                        if (_isVideo) _videoCropPreviewMode.value = false;
                        setState(() => _activeCropEdit = _cropSessionActive);
                        unawaited(editor.done());
                      },
                      child: wrytteSvgAssetIcon(
                        assetPath: 'assets/svg/Checkmark edit.svg',
                        canvas: 27,
                        scale: 0.92,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _cancelCropEditing(CropRotateEditorState editor) {
    unawaited(HapticFeedback.selectionClick());
    _cropRatioOverlay?.remove();
    _cropRatioOverlay = null;

    _showDiscardChangesMenu(
      onDiscard: () {
        _cropSessionActive = _activeCropEdit;
        _returnToMainEditorAfterDiscard(editor.context);
      },
    );
  }

  void _returnToMainEditorAfterDiscard(BuildContext subEditorContext) {
    _setSubEditorOpen(false);
    _chromeVisible.value = true;
    if (_isVideo) _videoCropPreviewMode.value = false;

    // Pro Image Editor's standalone `close()` delegates to the configured
    // onCloseEditor callback when one exists. That callback restores our state,
    // but it does not pop the embedded sub-editor route. Pop that exact nested
    // route directly so Discard always returns to the main editing canvas.
    Navigator.of(subEditorContext).pop();
  }

  void _hideDiscardChangesMenu() {
    final entry = _cropDiscardOverlay;
    _cropDiscardOverlay = null;
    if (entry != null && entry.mounted) entry.remove();
  }

  void _showDiscardChangesMenu({
    required VoidCallback onDiscard,
    bool fromTop = false,
  }) {
    _cropRatioOverlay?.remove();
    _cropRatioOverlay = null;
    _hideDiscardChangesMenu();

    final overlay = Overlay.of(context);
    final padding = MediaQuery.paddingOf(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        void closeMenu() {
          if (entry.mounted) entry.remove();
          if (_cropDiscardOverlay == entry) _cropDiscardOverlay = null;
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: closeMenu,
              ),
            ),
            if (fromTop)
              Positioned(
                left: 10,
                top: padding.top + 70,
                child: _buildCropDiscardMenu(
                  onDiscard: () {
                    unawaited(HapticFeedback.selectionClick());
                    closeMenu();
                    onDiscard();
                  },
                ),
              )
            else
              Positioned(
                left: 10,
                bottom: padding.bottom + 70,
                child: _buildCropDiscardMenu(
                  onDiscard: () {
                    unawaited(HapticFeedback.selectionClick());
                    closeMenu();
                    onDiscard();
                  },
                ),
              ),
          ],
        );
      },
    );

    _cropDiscardOverlay = entry;
    overlay.insert(entry);
  }

  void _showCropDiscardMenu(CropRotateEditorState editor) {
    _showDiscardChangesMenu(
      onDiscard: () {
        _cropSessionActive = _activeCropEdit;
        _returnToMainEditorAfterDiscard(editor.context);
      },
    );
  }

  Widget _buildCropDiscardMenu({required VoidCallback onDiscard}) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 216,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: wrytteGlassDecoration(radius: 26),
              child: InkWell(
                onTap: onDiscard,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => states.contains(WidgetState.pressed)
                      ? const Color(0x22FF4D4D)
                      : Colors.transparent,
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                  child: Text(
                    'Discard changes',
                    style: TextStyle(
                      color: Color(0xFFFF4D4F),
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
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

  Widget _buildCropAspectRatioOptions(
    CropRotateEditorState editor,
    double aspectRatio,
    double originalAspectRatio,
  ) {
    return _buildCropAspectRatioMenu(
      editor: editor,
      aspectRatio: aspectRatio,
      originalAspectRatio: originalAspectRatio,
      close: () => Navigator.of(context).pop(),
    );
  }

  void _showCropAspectRatioMenu(CropRotateEditorState editor) {
    _cropDiscardOverlay?.remove();
    _cropDiscardOverlay = null;
    _cropRatioOverlay?.remove();
    _cropRatioOverlay = null;

    final overlay = Overlay.of(context);
    final padding = MediaQuery.paddingOf(context);
    final availableWidth = MediaQuery.sizeOf(context).width;

    // Put the menu's right edge directly on the crop frame's right border.
    // The crop rectangle belongs to the package's crop-painter RenderBox, so
    // convert its right edge to global screen coordinates before positioning
    // the OverlayEntry.
    double rightInset = 12.0;
    final cropPainter = editor.cropPainter;
    final cropPainterContext = editor.cropPainterKey.currentContext;

    if (cropPainter != null && cropPainterContext != null) {
      final cropRenderObject = cropPainterContext.findRenderObject();
      final cropRect = cropPainter.cropRect;

      if (cropRenderObject is RenderBox &&
          cropRenderObject.attached &&
          cropRenderObject.hasSize &&
          cropRect.isFinite &&
          !cropRect.isEmpty) {
        final topRightGlobal = cropRenderObject.localToGlobal(
          cropRect.topRight,
        );
        final bottomRightGlobal = cropRenderObject.localToGlobal(
          cropRect.bottomRight,
        );
        final cropRightGlobal = math
            .max(topRightGlobal.dx, bottomRightGlobal.dx)
            .toDouble();

        if (cropRightGlobal.isFinite) {
          rightInset = math
              .max(0.0, availableWidth - cropRightGlobal)
              .toDouble();
        }
      }
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  entry.remove();
                  if (_cropRatioOverlay == entry) _cropRatioOverlay = null;
                },
              ),
            ),
            Positioned(
              right: rightInset,
              bottom: padding.bottom + 72,
              child: _buildCropAspectRatioMenu(
                editor: editor,
                aspectRatio: -1,
                originalAspectRatio: -2,
                close: () {
                  entry.remove();
                  if (_cropRatioOverlay == entry) _cropRatioOverlay = null;
                },
              ),
            ),
          ],
        );
      },
    );

    _cropRatioOverlay = entry;
    overlay.insert(entry);
  }

  Widget _buildCropAspectRatioMenu({
    required CropRotateEditorState editor,
    required double aspectRatio,
    required double originalAspectRatio,
    required VoidCallback close,
  }) {
    final options = editor.cropRotateEditorConfigs.aspectRatios;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 246, maxHeight: 350),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: wrytteGlassDecoration(radius: 26),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final value = option.value;
                  final selected =
                      value == aspectRatio ||
                      (value == 0 && aspectRatio == originalAspectRatio);
                  return InkWell(
                    onTap: () {
                      unawaited(HapticFeedback.selectionClick());
                      if (value != null) editor.updateAspectRatio(value);
                      close();
                    },
                    splashFactory: NoSplash.splashFactory,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8.5,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option.text,
                              style: TextStyle(
                                color: WrytteColors.textPrimary,
                                fontSize: 17,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: WrytteColors.primary,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cropToolButton({
    required String tooltip,
    required String assetPath,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: wrytteSvgAssetIcon(
              assetPath: assetPath,
              canvas: 27,
              scale: 1,
              color: WrytteColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cropRoundActionButton({
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
    Color? backgroundColor,
  }) {
    final button = backgroundColor == null
        ? ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: DecoratedBox(
                decoration: wrytteGlassDecoration(radius: 21),
                child: SizedBox.square(
                  dimension: _editorCircleButtonSize,
                  child: Center(child: child),
                ),
              ),
            ),
          )
        : Container(
            width: _editorCircleButtonSize,
            height: _editorCircleButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: child,
          );

    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        child: button,
      ),
    );
  }

  Widget _buildVideoLoading() {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _videoInitialisationError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: WrytteColors.destructive,
                            size: 34,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'This video could not be opened for editing.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: WrytteColors.textSecondary,
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () => unawaited(_initialiseVideo()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              top: 13,
              left: 13,
              child: _glassCircleButton(
                tooltip: widget.openedFromCamera ? 'Back to camera' : 'Back',
                onTap: _closeWithoutSaving,
                child: wrytteSvgAssetIcon(
                  assetPath: 'assets/svg/ic--round-arrow-back-ios.svg',
                  canvas: 27,
                  scale: 1.0,
                  offset: const Offset(-0.5, 0),
                  color: WrytteColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideo) {
      final controller = _proVideoController;
      if (controller == null) return _buildVideoLoading();
      return ProImageEditor.video(
        controller,
        key: _editorKey,
        callbacks: _videoCallbacks,
        configs: _configs,
      );
    }

    final editor = _withMainMediaSwipe(
      ProImageEditor.file(
        File(_currentSourcePath),
        key: _editorKey,
        callbacks: _imageCallbacks,
        configs: _configs,
      ),
    );

    final heroTag = widget.openingImageHeroTag;
    final heroProvider = widget.openingHeroImageProvider;
    if (heroTag != null &&
        heroProvider != null &&
        _currentMediaId == widget.openingImageMediaId) {
      // ProImageEditor owns Hero widgets for some of its internal tools. It
      // must never be placed below our gallery Hero because Flutter forbids a
      // Hero from being the descendant of another Hero. Keep the shared image
      // destination as a sibling behind the opaque editor instead: its flight
      // still runs in Navigator's overlay, while the live editor remains in a
      // separate subtree with no Hero ancestor.
      final sharedImage = Image(
        image: heroProvider,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: IgnorePointer(
              child: FullScreenImageHero(
                tag: heroTag,
                source: _currentSourcePath,
                flightStartBorderRadius: 0,
                flightChild: sharedImage,
                child: sharedImage,
              ),
            ),
          ),
          editor,
        ],
      );
    }

    // The chat media editor is a full-screen editing screen, not a pure image
    // viewer. Wrapping the entire editor in a single Hero causes the whole
    // editing surface to expand from the thumbnail and then animate its controls
    // in separately, which is the behavior that does not match the profile photo
    // full-screen viewer. Keep the route simple and fade-only so it behaves like
    // the profile photo fullscreen flow rather than a custom sheet-scale zoom.
    return editor;
  }
}
