import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:vibration/vibration.dart';

import 'package:wrytte/ui/widgets/global/avatars/user_avatar.dart';
import 'package:wrytte/models/chat_models/chat_conversation.dart';
import 'package:wrytte/models/chat_models/chat_message.dart';
import 'package:wrytte/models/contact_model.dart';
import 'package:wrytte/models/user_models/user_profile.dart';
import 'package:wrytte/models/user_models/wrytte_profile.dart';
import 'package:wrytte/services/permissions/app_permission_service.dart';
import 'package:wrytte/services/calls/call_service.dart';
import 'package:wrytte/services/chat/chat_local_db.dart';
import 'package:wrytte/services/chat/chat_service.dart';
import 'package:wrytte/services/auth/auth_service.dart';
import 'package:wrytte/services/attachments/attachment_local_store.dart';
import 'package:wrytte/services/audio/audio_file_metadata_service.dart';
import 'package:wrytte/services/audio/audio_playlist_store.dart';
import 'package:wrytte/services/contacts/contact_identity_cache.dart';
import 'package:wrytte/services/contacts/contact_directory_service.dart';
import 'package:wrytte/services/contacts/contact_local_db.dart';
import 'package:wrytte/services/contacts/contact_service.dart';
import 'package:wrytte/services/matrix/matrix_chat_service.dart';
import 'package:wrytte/services/matrix/matrix_client.dart';
import 'package:wrytte/services/matrix/matrix_config.dart';
import 'package:wrytte/services/matrix/matrix_presence.dart';
import 'package:wrytte/services/matrix/matrix_profile_service.dart';
import 'package:wrytte/services/matrix/block_state_service.dart';
import 'package:wrytte/services/notifications/notification_service.dart';
import 'package:wrytte/services/user/avatar_preload_service.dart';
import 'package:wrytte/services/user/user_profile_service.dart';
import 'package:wrytte/ui/screens/calls/call_screen.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/ui/screens/chats/chat_media_editor.dart';
import 'package:wrytte/ui/screens/chats/pinned_messages_page.dart';
import 'package:wrytte/ui/screens/chats/video_message_recorder_screen.dart';
import 'package:wrytte/ui/chat/models/chat_forward_target.dart';
import 'package:wrytte/ui/chat/views/chat_forward_sheet.dart';
import 'package:wrytte/ui/widgets/chats/composer/message_input.dart';
import 'package:wrytte/ui/widgets/chats/composer/migrated_message_input.dart';
import 'package:wrytte/ui/widgets/chats/messages/message_bubble.dart';
import 'package:wrytte/ui/widgets/chats/overlays/message_actions_overlay.dart';
import 'package:wrytte/ui/widgets/global/surfaces/wrytte_glass_surface.dart';
import 'package:wrytte/ui/widgets/chats/timeline/sticky_date_geometry.dart';
import 'package:wrytte/ui/widgets/chats/timeline/chat_timeline_coordinates.dart';
import 'package:wrytte/ui/widgets/global/navigation/pinned_events_strip.dart';
import 'package:wrytte/ui/screens/groups/group_profile_screen.dart';
import 'package:wrytte/ui/screens/contacts/new_contact_screen.dart';
import 'package:wrytte/ui/screens/profiles/profile_screen.dart';
import 'package:wrytte/utils/apk_debug_logger.dart';
import 'package:wrytte/utils/wrytte_id.dart';
import 'package:wrytte/ui/screens/media/full_screen_image_viewer.dart';
import 'package:wrytte/ui/widgets/global/media/wrytte_persistent_image.dart';

part '../../widgets/chats/forward_picker.dart';
part '../../widgets/chats/interactions/swipe_message_action.dart';
part '../../widgets/chats/overlays/copy_toast.dart';
part '../../widgets/chats/timeline/date_viewport_marker.dart';
part '../../controllers/chats/chat_identity_actions.dart';
part '../../controllers/chats/chat_conversation_controller.dart';
part '../../controllers/chats/chat_timeline_controller.dart';
part '../../controllers/chats/chat_message_commands.dart';
part '../../controllers/chats/chat_scroll_commands.dart';
part '../../controllers/chats/chat_message_store.dart';
part '../../controllers/chats/chat_message_actions.dart';
part '../../widgets/chats/overlays/message_action_tile.dart';
part '../../controllers/chats/chat_forwarding_controller.dart';
part '../../widgets/chats/audio/chat_audio_player_surfaces.dart';
part '../../widgets/chats/overlays/chat_screen_overlays.dart';
part '../../widgets/chats/timeline/chat_message_list.dart';
part '../../controllers/chats/chat_selection_controller.dart';
part '../../widgets/chats/composer/group_membership_bars.dart';
part '../../controllers/chats/chat_audio_playback_controller.dart';
part '../../widgets/chats/messages/chat_message_builder.dart';
part '../../controllers/chats/chat_group_actions.dart';
part '../../widgets/chats/header/chat_header.dart';
part '../../widgets/chats/overlays/chat_debug_toggle.dart';
part '../../controllers/chats/chat_group_profile_controller.dart';
part '../../widgets/chats/messages/chat_message_presenter.dart';
part '../../widgets/chats/timeline/chat_date_divider.dart';
part '../../widgets/chats/header/chat_glass_pill.dart';
part '../../widgets/chats/chat_screen_view.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String receiverId;
  final String currentUserId;
  final String title;
  final String? avatarUrl;
  final String? localAvatarPath;
  final List<ChatMessage> initialMessages;
  final bool readOnlyUntilJoin;
  final int? initialMemberCount;
  final String? groupAlias;
  final String? groupDescription;
  final String conversationKind;
  final int? initialRoomProfileVersion;
  final bool uiPreviewMode;
  final bool loadRoomEventsOnDemand;
  final bool initialEventsHaveMore;
  final bool initialMemberCountIsAuthoritative;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.receiverId,
    required this.currentUserId,
    required this.title,
    this.avatarUrl,
    this.localAvatarPath,
    this.initialMessages = const [],
    this.readOnlyUntilJoin = false,
    this.initialMemberCount,
    this.groupAlias,
    this.groupDescription,
    this.conversationKind = ConversationKind.unknown,
    this.initialRoomProfileVersion,
    this.uiPreviewMode = false,
    this.loadRoomEventsOnDemand = false,
    this.initialEventsHaveMore = false,
    this.initialMemberCountIsAuthoritative = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScrollBehavior extends ScrollBehavior {
  const _ChatScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _FloatingDateVisualState {
  final String? activeDayKey;
  final String? outgoingDayKey;
  final String? outgoingLabel;
  final double outgoingOffsetY;
  final String? incomingDayKey;
  final String? incomingLabel;
  final double incomingOffsetY;
  final double transitionProgress;

  const _FloatingDateVisualState({
    this.activeDayKey,
    this.outgoingDayKey,
    this.outgoingLabel,
    this.outgoingOffsetY = 0,
    this.incomingDayKey,
    this.incomingLabel,
    this.incomingOffsetY = 0,
    this.transitionProgress = 0,
  });

  bool get hasDate => outgoingDayKey != null && outgoingLabel != null;
  bool get hasIncoming => incomingDayKey != null && incomingLabel != null;

  bool ownsInlineDay(String dayKey) =>
      outgoingDayKey == dayKey || incomingDayKey == dayKey;
}

enum _DateViewportMarkerKind { message, divider }

const double _chatBackCanvas = 26.0;
const double _chatPhoneCanvas = 26.0;
const double _chatDropdownCanvas = 12.0;
const Color _chatIconColor = WrytteVisualTokens.iconColor;
const double _chatBackOpticalScale = 1.00;
const Offset _chatBackOffset = Offset(-0.5, 0);
const double _chatPhoneOpticalScale = 1.00;
const double _chatCallDropdownOpticalScale = 1.00;
const double _chatCallCompositionWidth = 30.0;
const double _chatCallCompositionHeight = 29.0;
const double _chatCallPhoneLeft = 0.0;
const double _chatCallPhoneTop = 1.0;
const double _chatCallDropdownLeft = 19.0;
const double _chatCallDropdownTop = 4.0;
const Offset _chatCallCompositionOffset = Offset(-0.75, 2.0);
const double _floatingDateTopGap = 4.0;
const double _dateChipHeight = 23.0;
const double _dateChipHorizontalPadding = 12.0;
const double _dateChipRadius = 11.5;
const double _dateDividerVerticalPadding = 11.5;
const double _dateCollisionGap = 2.0;
const double _dateCrossingHysteresis = 0.6;
const double _directConversationStartTopGap = 7.0;
const double _directConversationDateEncryptionGap = 7.0;
const double _directConversationFirstMessageGap = 47.0;
const double _pinnedStripExtent = 56.0;
const double _fileAudioPlayerExtent = 62.0;
const double _joinedPinnedAudioExtent = 107.0;
const double _dateHandoffExtent = _dateChipHeight + _dateCollisionGap;
const double _dateHandoffClipHeight =
    (_dateChipHeight * 2) + _dateCollisionGap + _dateCrossingHysteresis;
const Duration _floatingDateHideDelay = Duration(milliseconds: 180);
const List<mx.Membership> _groupMemberships = [
  mx.Membership.join,
  mx.Membership.invite,
];

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _nearBottom = true;
  int _pendingNewMessages = 0;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _screenStackKey = GlobalKey();
  final GlobalKey _messageViewportKey = GlobalKey();
  final MessageInputAttachmentController _attachmentController =
      MessageInputAttachmentController();
  final Map<String, GlobalKey> _messageBubbleBoundaryKeys = {};
  final _ExclusiveMessageSwipeCoordinator _messageSwipeCoordinator =
      _ExclusiveMessageSwipeCoordinator();

  final Set<_DateViewportMarkerState> _mountedMessageDateMarkers = {};
  final Set<_DateViewportMarkerState> _mountedDividerDateMarkers = {};

  late final ValueNotifier<_FloatingDateVisualState> _floatingDateVisual;
  late final AnimationController _floatingDateVisibilityController;
  late final Animation<double> _floatingDateOpacity;
  Timer? _floatingDateHideTimer;
  bool _floatingDateMeasurementScheduled = false;
  bool _floatingDateScrollActive = false;
  bool _floatingDatePinnedAtVisualTop = false;
  bool _disposing = false;
  double _floatingDateTop = 0;
  String? _activeFloatingDayKey;
  DateTime? _activeFloatingDay;

  final ChatService _chat = ChatService();
  final CallService _call = CallService.instance;

  StreamSubscription<List<ChatMessage>>? _messagesSub;
  String? _messagesSubscriptionConversationId;
  String? _lastRoomStreamFingerprint;
  StreamSubscription<mx.SyncUpdate>? _roomProfileSyncSub;
  StreamSubscription<mx.SyncUpdate>? _presenceSyncSub;
  StreamSubscription<dynamic>? _presenceChangedSub;
  StreamSubscription<String>? _groupContactsChangedSub;

  final List<ChatMessage> _messages = [];
  final List<ChatMessage> _initialStreamBuffer = [];
  final Map<String, String> _optimisticIdByContent = {};
  final Map<String, String> _messagePopAnimationRowIds = {};
  final Set<String> _pendingMessagePopAnimationIds = <String>{};
  final Map<String, _SharedContactData> _resolvedSharedContacts = {};
  final Map<String, Future<_SharedContactData>>
  _sharedContactResolutionsInFlight = {};
  final Map<String, DateTime> _sharedContactResolutionFailures = {};
  final Set<String> _cancelledAttachmentPlaceholderIds = <String>{};
  final Set<String> _selectedMessageIds = {};
  final Set<String> _deletingMessageIds = {};
  final Map<String, VoiceNotePlaybackController> _voicePlaybackControllers = {};
  String? _activeVoicePlaybackKey;
  FileAudioPlaybackUiState? _activeFileAudioPlayback;
  String? _activeFileAudioMessageId;
  List<LocalAudioPlaylist> _localAudioPlaylists = const <LocalAudioPlaylist>[];
  final Set<String> _openedVoiceMessageKeys = <String>{};
  Future<void>? _openedVoiceMessageLoadFuture;
  Future<void> _openedVoiceMessageWriteQueue = Future<void>.value();
  bool _openedVoiceMessageStateReady = false;
  final Map<String, String> _groupMemberNames = {};
  final Map<String, String> _groupMemberAvatars = {};
  final Set<String> _groupSenderProfilesInFlight = {};
  final Set<String> _pinUpdatesInFlight = {};
  final Set<String> _mediaSavesInFlight = {};
  final Set<String> _roundVideoSourceRepairsInFlight = {};
  final Map<String, DateTime> _lastPinUpdateAt = {};
  List<String> _pinnedEventIds = [];
  List<String> _pinnedForMeEventIds = [];
  String? _dismissedPinnedStripSignature;
  List<mx.User> _groupMembers = const [];

  List<String> get _visiblePinnedEventIds => <String>[
    ..._pinnedForMeEventIds,
    ..._pinnedEventIds.where((id) => !_pinnedForMeEventIds.contains(id)),
  ];

  String? _resolvedConversationId;

  String get _activeConversationId =>
      (_resolvedConversationId?.trim().isNotEmpty == true)
      ? _resolvedConversationId!.trim()
      : widget.conversationId.trim();

  bool get _isReadOnlySuggestedGroup {
    if (!widget.readOnlyUntilJoin || _joinedSuggestedGroup) return false;
    final room = MatrixChatService.instance.getRoomById(_activeConversationId);
    return room == null || room.membership != mx.Membership.join;
  }

  bool get _isDeletedConversation =>
      _chat.isConversationDeleted(_activeConversationId) ||
      _messages.any(
        (message) => ChatService.isGroupDeletedPreview(message.content),
      );

  bool _loadingOlder = false;
  bool _olderHistoryPrefetchScheduled = false;
  bool _showOlderLoadingIndicator = false;
  Timer? _olderLoadingIndicatorTimer;
  bool _loadingInitial = true;
  bool _hasMoreOlder = true;
  bool _groupProfilesReady = false;

  bool _isSending = false;
  bool _matrixAvailable = false;
  bool _joinedSuggestedGroup = false;
  bool _joiningSuggestedGroup = false;

  UserProfile? _receiverProfile;
  ContactIdentity? _receiverIdentity;
  bool _receiverIsSavedContact = false;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  String? _contextMenuMessageId;
  String? _highlightedMessageId;
  int _highlightPulse = 0;
  bool _messageActionsActive = false;
  OverlayEntry? _copyToastEntry;
  Timer? _highlightTimer;
  // The header starts with the route's avatar, then profile/room syncs may
  // replace it while this screen is alive. This must remain mutable: declaring
  // it `late final` makes the first profile refresh throw after initState has
  // already assigned the initial value.
  String? _stableHeaderAvatarUrl;

  // ── debug overlay ──────────────────────────────────────────────────────────
  bool _showDebug = false;
  final ScrollController _debugScrollCtrl = ScrollController();
  final ApkDebugLogger _logger = ApkDebugLogger.instance;

  // ─── LIFECYCLE ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    BlockStateService.instance.revision.addListener(_onChatBlockStateChanged);
    unawaited(BlockStateService.instance.load());
    // Resolve Flutter's text-input channel while the chat is being prepared,
    // instead of paying that one-time setup cost on the first composer tap.
    TextInput.ensureInitialized();
    assert(_dateChipHeight > 0);
    assert(_dateDividerVerticalPadding >= 0);
    assert(_dateCollisionGap >= 0);
    assert(_dateCrossingHysteresis >= 0);
    assert(_dateHandoffExtent > _dateChipHeight);
    assert(_dateHandoffClipHeight > _dateHandoffExtent);
    _floatingDateVisual = ValueNotifier(const _FloatingDateVisualState());
    _floatingDateVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 150),
    );
    final floatingDateCurve = CurvedAnimation(
      parent: _floatingDateVisibilityController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _floatingDateOpacity = floatingDateCurve;
    _stableHeaderAvatarUrl = _initialStableHeaderAvatarUrl();
    if (widget.uiPreviewMode) {
      _mergeMessages(widget.initialMessages);
      _loadingInitial = false;
      _openedVoiceMessageStateReady = true;
      _groupProfilesReady = true;
      _logger.addListener(_onNewLog);
      _scrollCtrl.addListener(_onScroll);
      return;
    }

    _chat.activateConversationRead(widget.conversationId);
    try {
      final matrixClient = MatrixClientService.instance.client;
      _presenceChangedSub = matrixClient.onPresenceChanged.stream
          .listen((update) {
        if (!mounted || _isGroupChat) return;
        final peerId = _profilePeerId()?.trim() ?? '';
        if (peerId.isEmpty) return;
        final senderId = update.userid.trim();
        final changed = senderId.toLowerCase() == peerId.toLowerCase();
        if (changed) {
          debugPrint('[Matrix.presence] chat_header_refresh user_id="$peerId"');
          setState(() {});
        }
      });
      unawaited(_fetchPeerPresence(matrixClient));
    } catch (_) {}
    _subscribeToRoomProfileUpdates();
    _subscribeToGroupContactUpdates();
    apkLog(
      'ChatScreen',
      '── initState ──  '
          'convId="${widget.conversationId}"  '
          'receiverId="${widget.receiverId}"  '
          'currentUserId="${widget.currentUserId}"',
    );
    if (!_isGroupChat) {
      apkLog(
        'Identity.display',
        'surface="conversation_header" phase="initial" '
            'user_id="${_matrixLocalpart(widget.receiverId)}" '
            'name="${widget.title}" avatar=${(_stableHeaderAvatarUrl ?? '').trim().isNotEmpty} '
            'avatar_url="${_stableHeaderAvatarUrl ?? ''}"',
      );
    }
    if (_isSelfConversation) {
      _logSelfConversationBlocked('open');
    }
    final initialGroupRoom = MatrixChatService.instance.getRoomById(
      widget.conversationId,
    );
    _joinedSuggestedGroup =
        !widget.readOnlyUntilJoin ||
        initialGroupRoom?.membership == mx.Membership.join;

    _seedGroupProfile2FromMemory();
    if (!_isGroupChat) unawaited(_seedReceiverIdentityFromCache());
    _logger.addListener(_onNewLog);
    final initialMessages = widget.initialMessages.isNotEmpty
        ? widget.initialMessages
        : _chat.recentCachedMessagesFor(widget.conversationId);
    if (initialMessages.isNotEmpty && _suppliedRoomMatchesScreenKind) {
      _mergeMessages(initialMessages);
      _loadingInitial = false;
    }
    unawaited(_loadOpenedVoiceMessageKeys());
    unawaited(_loadLocalAudioPlaylists());
    if (!_isGroupChat) {
      // Warm the shared Matrix profile cache as soon as the chat opens. The
      // header/profile route can then read the resolved human name
      // synchronously instead of starting the first request after the tap.
      unawaited(_warmReceiverMatrixProfile());
    }
    unawaited(_loadInitialSafely());
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _fetchPeerPresence(mx.Client client) async {
    if (_isGroupChat || !mounted) return;
    final peerId = _profilePeerId()?.trim() ?? '';
    if (peerId.isEmpty) return;
    try {
      final presence = await client.fetchCurrentPresence(peerId);
      if (!mounted) return;
      debugPrint(
        '[Matrix.presence] initial_fetch user_id="$peerId" '
        'state="${presence.presence.name}" '
        'currently_active="${presence.currentlyActive}" '
        'last_seen="${presence.lastActiveTimestamp}"',
      );
      setState(() {});
    } catch (error) {
      debugPrint(
        '[Matrix.presence] initial_fetch_failed user_id="$peerId" error="$error"',
      );
    }
  }

  Future<void> _warmReceiverMatrixProfile() async {
    final receiverId = widget.receiverId.trim();
    if (receiverId.isEmpty) return;
    try {
      await MatrixProfileService.instance.getProfile(receiverId);
    } catch (error) {
      apkLog(
        'ModuleProfile.warm',
        'receiver="$receiverId" failed error="$error"',
      );
    }
  }

  Future<void> _loadLocalAudioPlaylists() async {
    final playlists = await AudioPlaylistStore.instance.loadForConversation(
      widget.conversationId,
    );
    if (!mounted || playlists.isEmpty) return;
    setState(() {
      _localAudioPlaylists = playlists;
    });
  }

  @override
  void dispose() {
    _disposing = true;
    BlockStateService.instance.revision.removeListener(
      _onChatBlockStateChanged,
    );
    _chat.deactivateConversationRead(widget.conversationId);
    _roomProfileSyncSub?.cancel();
    _presenceSyncSub?.cancel();
    _presenceChangedSub?.cancel();
    _groupContactsChangedSub?.cancel();
    final resolvedConversationId = _resolvedConversationId;
    if (resolvedConversationId != null &&
        resolvedConversationId != widget.conversationId) {
      _chat.deactivateConversationRead(resolvedConversationId);
    }
    _logger.removeListener(_onNewLog);
    _messagesSub?.cancel();
    _highlightTimer?.cancel();
    _floatingDateHideTimer?.cancel();
    _olderLoadingIndicatorTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _copyToastEntry?.remove();
    _copyToastEntry = null;
    _controller.dispose();
    _scrollCtrl.dispose();
    _debugScrollCtrl.dispose();
    _focusNode.dispose();
    _floatingDateVisibilityController.dispose();
    _floatingDateVisual.dispose();
    for (final controller in _voicePlaybackControllers.values) {
      controller.dispose();
    }
    _voicePlaybackControllers.clear();
    _activeVoicePlaybackKey = null;
    _activeFileAudioPlayback = null;
    _activeFileAudioMessageId = null;
    _mountedMessageDateMarkers.clear();
    _mountedDividerDateMarkers.clear();
    super.dispose();
  }

  void _subscribeToRoomProfileUpdates() {
    _roomProfileSyncSub = MatrixChatService.instance.syncStream.listen((_) {
      if (!mounted) return;
      final room = MatrixChatService.instance.getRoomById(
        _resolvedConversationId ?? widget.conversationId,
      );
      if (room == null) return;
      if (_pinUpdatesInFlight.isEmpty) {
        final pinned = room.pinnedEventIds.toList();
        final pinnedForMe = _isGroupChat
            ? const <String>[]
            : _chat.pinnedForMeEventIdsForRoom(room.id);
        if (!listEquals(pinned, _pinnedEventIds) ||
            !listEquals(pinnedForMe, _pinnedForMeEventIds)) {
          setState(() {
            _pinnedEventIds = pinned;
            _pinnedForMeEventIds = pinnedForMe;
          });
        }
      }
      if (!_isGroupChat) {
        // Presence updates arrive through Matrix sync. Rebuild the header so
        // its status reflects the latest event and visibility setting.
        setState(() {});
        return;
      }
      final latestAvatar = _safeGroupRoomAvatarUrl(room);
      if (latestAvatar == _stableHeaderAvatarUrl) {
        // Name/topic/custom profile state may still have changed.
        setState(() {});
        return;
      }
      setState(() => _stableHeaderAvatarUrl = latestAvatar);
    });
  }

  void _subscribeToGroupContactUpdates() {
    if (!_isGroupChat) return;
    _groupContactsChangedSub = ContactService.contactsChanged.listen((owner) {
      if (!mounted ||
          owner.trim().toLowerCase() !=
              widget.currentUserId.trim().toLowerCase()) {
        return;
      }
      _groupMemberNames.clear();
      _groupMemberAvatars.clear();
      _seedGroupProfile2FromMemory();
      _resolveGroupMessageSenders(_messages);
      _groupProfilesReady = false;
      if (mounted) setState(() {});
      unawaited(_refreshGroupContactProfiles());
    });
  }

  Future<void> _refreshGroupContactProfiles() async {
    await _primeGroupMemberProfiles(_activeConversationId);
    if (!mounted) return;
    setState(() => _groupProfilesReady = true);
  }

  void _onNewLog() {
    if (_showDebug && mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_debugScrollCtrl.hasClients) {
          _debugScrollCtrl.jumpTo(_debugScrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  void _refreshState() {
    if (mounted) setState(() {});
  }

  void _setChatState(VoidCallback mutation) {
    if (mounted) setState(mutation);
  }

  @override
  Widget build(BuildContext context) => _buildChatScreenView(context);
}
