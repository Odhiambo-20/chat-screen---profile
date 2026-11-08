part of '../../screens/chats/chat_screen.dart';

extension _ChatIdentityActions on _ChatScreenState {
  String _normaliseId(String id) => id.trim();

  bool get _isSelfConversation {
    final self = _matrixLocalpart(widget.currentUserId);
    final receiver = _matrixLocalpart(widget.receiverId);
    return self.isNotEmpty && receiver.isNotEmpty && self == receiver;
  }

  void _logSelfConversationBlocked(String action) {
    apkLog(
      'ChatScreen.self',
      '$action blocked: receiver is current user '
          'current="${_matrixLocalpart(widget.currentUserId)}" '
          'receiver="${_matrixLocalpart(widget.receiverId)}"',
    );
  }

  void _showSelfConversationError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This contact is linked to your own account.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  bool _looksLikePhone(String value) {
    final stripped = value.trim().replaceAll(RegExp(r'[\s\-()+]'), '');
    if (stripped.length < 7 || stripped.length > 15) return false;
    return stripped.startsWith('+') || RegExp(r'^\d{7,}$').hasMatch(stripped);
  }

  String _extractPhone(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return '';
    final match = RegExp(r'(\+?\d[\d\s\-()]{6,}\d)').firstMatch(raw);
    if (match == null) return '';
    final phone = match.group(1)?.trim() ?? '';
    return _looksLikePhone(phone) ? phone : '';
  }

  String _phoneFromIdentifier(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty || _looksLikeMatrixId(raw)) return '';

    final extracted = _extractPhone(value);
    if (extracted.isNotEmpty) return extracted;

    final localpart = _matrixLocalpart(raw);
    if (_looksLikeMatrixId(localpart)) return '';
    final digits = localpart.replaceAll(RegExp(r'[^\d]'), '');
    return RegExp(r'^\+?\d{7,15}$').hasMatch(localpart) ? digits : '';
  }

  bool _looksLikeMatrixId(String value) {
    final trimmed = value.trim();
    final localpart = _matrixLocalpart(trimmed);
    return trimmed.startsWith('@') ||
        trimmed.startsWith('!') ||
        trimmed.contains(':matrix.') ||
        RegExp(r'^[a-f0-9]{24,}$', caseSensitive: false).hasMatch(localpart);
  }

  String _formatPhone(String phone) {
    final wrytteId = WrytteId.forDisplay(phone);
    if (wrytteId != null) return wrytteId;

    final digits = _stripInvalidNorthAmericaPrefix(
      phone.replaceAll(RegExp(r'[^\d+]'), ''),
    );
    final digitsOnly = digits.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 7 || digitsOnly.length > 15) return '';
    if (digits.startsWith('+1') && digits.length == 12) {
      return '${digits.substring(0, 2)} ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
    }
    if (digits.isNotEmpty && !digits.startsWith('+')) return '+$digits';
    return digits;
  }

  String _stripInvalidNorthAmericaPrefix(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (!phone.startsWith('+1')) return phone;
    if (digits.length <= 11) return phone;
    return '+${digits.substring(1)}';
  }

  String _firstPhoneFrom(Iterable<String?> candidates) {
    for (final candidate in candidates) {
      final phone = _phoneFromIdentifier(candidate);
      if (phone.isNotEmpty) return _formatPhone(phone);
    }
    return '';
  }

  _SharedContactData _localSharedContactData(ChatMessage message) {
    final bodyLines = message.content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    var name = message.contactName?.trim() ?? '';
    var phone = _firstPhoneFrom([
      message.contactPhone,
      ...bodyLines.skip(name.isEmpty ? 1 : 0),
    ]);
    var avatarUrl = message.contactAvatarUrl?.trim() ?? '';
    var userId = message.contactUserId?.trim() ?? '';

    if (name.isEmpty && bodyLines.isNotEmpty) {
      final firstLinePhone = _firstPhoneFrom([bodyLines.first]);
      if (firstLinePhone.isNotEmpty && bodyLines.length == 1) {
        phone = phone.isNotEmpty ? phone : firstLinePhone;
      } else {
        name = bodyLines.first;
      }
    }

    final userKey = _matrixLocalpart(userId).trim().toLowerCase();
    final phoneKey = _forwardPhoneKey(phone);
    Contact? matchedContact;
    for (final contact in ContactService.matrixContactsSnapshot(
      widget.currentUserId,
    )) {
      final contactUserKey =
          _matrixLocalpart(contact.wrytteUserId ?? '').trim().toLowerCase();
      final sameUser =
          userKey.isNotEmpty &&
          contactUserKey.isNotEmpty &&
          contactUserKey == userKey;
      final samePhone =
          phoneKey.isNotEmpty &&
          contact.phones.any(
            (candidate) => _forwardPhoneKey(candidate) == phoneKey,
          );
      if (sameUser || samePhone) {
        matchedContact = contact;
        break;
      }
    }

    if (matchedContact != null) {
      final savedName = _cleanDisplayName(matchedContact.formattedName);
      if (name.isEmpty && savedName.isNotEmpty) name = savedName;
      if (phone.isEmpty) phone = _firstPhoneFrom(matchedContact.phones);
      if (avatarUrl.isEmpty) avatarUrl = matchedContact.avatarUrl?.trim() ?? '';
      if (userId.isEmpty) userId = matchedContact.wrytteUserId?.trim() ?? '';
    }

    // Use the already-warmed public profile cache for the first frame when it
    // is available. Remote/Matrix enrichment still runs afterward and can
    // replace this value when the avatar changes.
    if (userId.isNotEmpty && avatarUrl.isEmpty) {
      final cachedProfile = UserProfileService.instance.cachedPublicProfileByUid(
        userId,
        phone: phone,
      );
      if (cachedProfile?.hasProfileImage == true) {
        avatarUrl = cachedProfile!.profileImage.trim();
      }
    }

    if (name.isEmpty && userId.isNotEmpty) name = _matrixLocalpart(userId);
    if (name.isEmpty) name = phone.isNotEmpty ? phone : 'Contact';

    return _SharedContactData(
      name: name,
      phone: phone,
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      userId: userId.isEmpty ? null : userId,
    );
  }

  _SharedContactData _sharedContactData(ChatMessage message) =>
      _resolvedSharedContacts[message.id] ?? _localSharedContactData(message);

  WrytteContactResolution? _directoryContactForPhone(
    Map<String, WrytteContactResolution> matches,
    String phone,
  ) {
    final phoneKey = _forwardPhoneKey(phone);
    if (phoneKey.isEmpty) return null;
    for (final resolution in matches.values) {
      if (resolution.isOnWrytte &&
          _forwardPhoneKey(resolution.phone) == phoneKey) {
        return resolution;
      }
    }
    return null;
  }

  _SharedContactData _mergeDirectoryContact(
    _SharedContactData local,
    WrytteContactResolution? resolution,
  ) {
    if (resolution == null) return local;

    final directoryName = _cleanDisplayName(resolution.displayName ?? '');
    final localNameKey = local.name.trim().toLowerCase();
    final localNameIsFallback =
        localNameKey.isEmpty ||
        localNameKey == 'contact' ||
        _forwardPhoneKey(local.name) == _forwardPhoneKey(local.phone);
    final rawUserId =
        resolution.matrixUserId?.trim().isNotEmpty == true
            ? resolution.matrixUserId!.trim()
            : resolution.userId?.trim() ?? '';
    final matrixUserId =
        rawUserId.isEmpty ? local.userId : _toMatrixUserId(rawUserId);
    final directoryAvatar = resolution.avatarUrl?.trim() ?? '';

    return _SharedContactData(
      name:
          localNameIsFallback && directoryName.isNotEmpty
              ? directoryName
              : local.name,
      phone: local.phone,
      avatarUrl: directoryAvatar.isNotEmpty ? directoryAvatar : local.avatarUrl,
      userId: matrixUserId,
    );
  }

  bool _sharedContactNameIsFallback(_SharedContactData contact) {
    final name = contact.name.trim().toLowerCase();
    return name.isEmpty ||
        name == 'contact' ||
        (contact.phone.isNotEmpty &&
            _forwardPhoneKey(contact.name) == _forwardPhoneKey(contact.phone));
  }

  bool _sameSharedContact(
    _SharedContactData shared,
    Contact candidate, {
    required bool allowNameMatch,
  }) {
    final sharedUser =
        _matrixLocalpart(shared.userId ?? '').trim().toLowerCase();
    final candidateUser =
        _matrixLocalpart(candidate.wrytteUserId ?? '').trim().toLowerCase();
    if (sharedUser.isNotEmpty &&
        candidateUser.isNotEmpty &&
        sharedUser == candidateUser) {
      return true;
    }

    final sharedPhone = _forwardPhoneKey(shared.phone);
    if (sharedPhone.isNotEmpty &&
        candidate.phones.any(
          (phone) => _forwardPhoneKey(phone) == sharedPhone,
        )) {
      return true;
    }

    if (!allowNameMatch) return false;
    final sharedName = _cleanDisplayName(shared.name).toLowerCase();
    final candidateName =
        _cleanDisplayName(candidate.formattedName).toLowerCase();
    return sharedName.isNotEmpty && sharedName == candidateName;
  }

  Future<Contact?> _savedContactForSharedContact(
    _SharedContactData shared,
  ) async {
    final contacts = <Contact>[
      ...ContactService.matrixContactsSnapshot(widget.currentUserId),
    ];
    try {
      final stored = await ContactLocalDb.loadSavedContacts(
        ownerUserId: widget.currentUserId,
      );
      for (final contact in stored) {
        if (!contacts.contains(contact)) contacts.add(contact);
      }
    } catch (error) {
      apkLog(
        'ChatScreen.contact',
        'saved contact lookup failed error="$error"',
      );
    }

    for (final contact in contacts) {
      if (_sameSharedContact(shared, contact, allowNameMatch: false)) {
        return contact;
      }
    }

    final nameMatches = contacts
        .where(
          (contact) =>
              _sameSharedContact(shared, contact, allowNameMatch: true),
        )
        .toList(growable: false);
    return nameMatches.length == 1 ? nameMatches.single : null;
  }

  bool _sameSharedIdentity(
    _SharedContactData shared,
    ContactIdentity identity, {
    required bool allowNameMatch,
  }) {
    final sharedUser =
        _matrixLocalpart(shared.userId ?? '').trim().toLowerCase();
    final identityUser =
        _matrixLocalpart(identity.matrixUserId).trim().toLowerCase();
    if (sharedUser.isNotEmpty && sharedUser == identityUser) return true;

    final sharedPhone = _forwardPhoneKey(shared.phone);
    if (sharedPhone.isNotEmpty &&
        sharedPhone == _forwardPhoneKey(identity.phone ?? '')) {
      return true;
    }

    if (!allowNameMatch) return false;
    final sharedName = _cleanDisplayName(shared.name).toLowerCase();
    return sharedName.isNotEmpty &&
        <String?>[identity.savedName, identity.profileName].any(
          (name) => _cleanDisplayName(name ?? '').toLowerCase() == sharedName,
        );
  }

  Future<ContactIdentity?> _identityForSharedContact(
    _SharedContactData shared,
  ) async {
    try {
      final identities = (await ContactIdentityCache.instance.loadAll(
        ownerUserId: widget.currentUserId,
      )).values.toList(growable: false);
      for (final identity in identities) {
        if (_sameSharedIdentity(shared, identity, allowNameMatch: false)) {
          return identity;
        }
      }
      final nameMatches = identities
          .where(
            (identity) =>
                _sameSharedIdentity(shared, identity, allowNameMatch: true),
          )
          .toList(growable: false);
      return nameMatches.length == 1 ? nameMatches.single : null;
    } catch (error) {
      apkLog(
        'ChatScreen.contact',
        'identity cache lookup failed error="$error"',
      );
      return null;
    }
  }

  Future<_SharedContactData> _enrichSharedContactData(
    _SharedContactData seed,
  ) async {
    var name = seed.name.trim();
    var phone = seed.phone.trim();
    var avatarUrl = seed.avatarUrl?.trim() ?? '';
    var userId = seed.userId?.trim() ?? '';

    final saved = await _savedContactForSharedContact(seed);
    if (saved != null) {
      final savedName = _cleanDisplayName(saved.formattedName);
      if (_sharedContactNameIsFallback(seed) && savedName.isNotEmpty) {
        name = savedName;
      }
      if (phone.isEmpty) phone = _firstPhoneFrom(saved.phones);
      if (avatarUrl.isEmpty) avatarUrl = saved.avatarUrl?.trim() ?? '';
      if (userId.isEmpty) userId = saved.wrytteUserId?.trim() ?? '';
    }

    final afterSaved = _SharedContactData(
      name: name,
      phone: phone,
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      userId: userId.isEmpty ? null : userId,
    );
    final identity = await _identityForSharedContact(afterSaved);
    if (identity != null) {
      final identityName = _cleanDisplayName(
        identity.savedName ?? identity.profileName ?? '',
      );
      if (_sharedContactNameIsFallback(afterSaved) && identityName.isNotEmpty) {
        name = identityName;
      }
      if (phone.isEmpty) phone = _firstPhoneFrom([identity.phone]);
      if (avatarUrl.isEmpty) avatarUrl = identity.avatarUrl?.trim() ?? '';
      if (userId.isEmpty) userId = identity.matrixUserId.trim();
    }

    // Keep the locally cached avatar for the first paint. The profile lookup
    // below is the refresh path: it replaces this value when Matrix returns a
    // newer avatar and clears it when Matrix says the user has no avatar.
    // Clearing this here caused a placeholder flash even though the local
    // contact identity already contained a valid avatar URL.

    if (userId.isNotEmpty) {
      var profileResolved = false;
      try {
        final profile = await UserProfileService.instance.getProfileByUid(
          userId,
          phone: phone,
          // Resolve the current profile for a contact card. The service
          // deduplicates in-flight requests and caches the result, while this
          // prevents an old cached avatar from surviving a profile change.
          forceRefresh: true,
        );
        if (profile != null) {
          profileResolved = true;
          final profileName = _cleanDisplayName(profile.displayName);
          final current = _SharedContactData(
            name: name,
            phone: phone,
            avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
            userId: userId,
          );
          if (_sharedContactNameIsFallback(current) && profileName.isNotEmpty) {
            name = profileName;
          }
          if (phone.isEmpty) phone = _firstPhoneFrom([profile.phone]);
          // An authoritative profile without an avatar must clear the old
          // local URL; otherwise deleted avatars remain visible forever.
          avatarUrl = profile.hasProfileImage
              ? profile.profileImage.trim()
              : '';
        }
      } catch (error) {
        apkLog(
          'ChatScreen.contact',
          'public profile lookup failed user_id="$userId" error="$error"',
        );
      }

      if (!profileResolved &&
          avatarUrl.isEmpty &&
          MatrixClientService.instance.isLoggedIn) {
        try {
          final matrixId = _toMatrixUserId(userId);
          final profile = await MatrixClientService.instance.client
              .getProfileFromUserId(
                matrixId,
                timeout: const Duration(seconds: 2),
              );
          avatarUrl = profile.avatarUrl?.toString().trim() ?? '';
          final matrixName = _cleanDisplayName(profile.displayName ?? '');
          final current = _SharedContactData(
            name: name,
            phone: phone,
            avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
            userId: matrixId,
          );
          if (_sharedContactNameIsFallback(current) && matrixName.isNotEmpty) {
            name = matrixName;
          }
          userId = matrixId;
        } catch (error) {
          apkLog(
            'ChatScreen.contact',
            'Matrix profile lookup failed user_id="$userId" error="$error"',
          );
        }
      }
    }

    if (name.isEmpty) name = phone.isNotEmpty ? phone : 'Contact';
    final resolved = _SharedContactData(
      name: name,
      phone: phone,
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      userId: userId.isEmpty ? null : _toMatrixUserId(userId),
    );
    if (resolved.userId?.isNotEmpty == true) {
      try {
        await ContactIdentityCache.instance.upsert(
          ownerUserId: widget.currentUserId,
          matrixUserId: resolved.userId!,
          phone: resolved.phone,
          profileName: resolved.name,
          savedName: saved?.formattedName,
          avatarUrl: resolved.avatarUrl,
        );
      } catch (error) {
        apkLog(
          'ChatScreen.contact',
          'identity cache update failed user_id="${resolved.userId}" error="$error"',
        );
      }
    }
    return resolved;
  }

  Future<_SharedContactData> _resolveSharedContactData(
    ChatMessage message, {
    bool forceRefresh = false,
  }) {
    final cached = _resolvedSharedContacts[message.id];
    if (!forceRefresh && cached != null) {
      return Future<_SharedContactData>.value(cached);
    }
    final inFlight = _sharedContactResolutionsInFlight[message.id];
    if (inFlight != null) return inFlight;
    final lastFailure = _sharedContactResolutionFailures[message.id];
    if (!forceRefresh &&
        lastFailure != null &&
        DateTime.now().difference(lastFailure) < const Duration(seconds: 30)) {
      return Future<_SharedContactData>.value(_localSharedContactData(message));
    }

    late final Future<_SharedContactData> tracked;
    tracked = _resolveSharedContactDataFromSources(message).whenComplete(() {
      if (identical(_sharedContactResolutionsInFlight[message.id], tracked)) {
        _sharedContactResolutionsInFlight.remove(message.id);
      }
    });
    _sharedContactResolutionsInFlight[message.id] = tracked;
    return tracked;
  }

  Future<_SharedContactData> _resolveSharedContactDataFromSources(
    ChatMessage message,
  ) async {
    final local = _localSharedContactData(message);
    if (local.phone.isNotEmpty &&
        local.userId?.trim().isNotEmpty == true &&
        local.avatarUrl?.trim().isNotEmpty == true) {
      _resolvedSharedContacts[message.id] = local;
      return local;
    }

    var directoryResolved = local;
    try {
      if (local.phone.isNotEmpty) {
        final matches = await ContactDirectoryService.instance.resolvePhones([
          local.phone,
        ]);
        directoryResolved = _mergeDirectoryContact(
          local,
          _directoryContactForPhone(matches, local.phone),
        );
      }
    } catch (error) {
      apkLog(
        'ChatScreen.contact',
        'directory resolution failed phone="${local.phone}" error="$error"',
      );
    }

    try {
      final resolved = await _enrichSharedContactData(directoryResolved);
      _resolvedSharedContacts[message.id] = resolved;
      _sharedContactResolutionFailures.remove(message.id);
      _refreshState();
      return resolved;
    } catch (error) {
      apkLog(
        'ChatScreen.contact',
        'identity enrichment failed name="${local.name}" error="$error"',
      );
      _sharedContactResolutionFailures[message.id] = DateTime.now();
      return directoryResolved;
    }
  }

  Future<void> _addSharedContactPage(ChatMessage message) async {
    final data = await _resolveSharedContactData(message, forceRefresh: true);
    final token = await AuthService.instance.getToken();
    if (!mounted) return;
    final userId = data.userId?.trim() ?? '';
    final phone = data.phone.trim();
    final identifier =
        phone.isNotEmpty ? phone : (userId.isNotEmpty ? userId : null);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) => NewContactPage(
              token: token ?? '',
              initialIdentifier: identifier,
              initialWrytteUserId: userId.isEmpty ? null : userId,
              initialName: data.name,
              initialBio: null,
            ),
      ),
    );
  }

  Future<void> _openSharedContactChat(ChatMessage message) async {
    final data = await _resolveSharedContactData(message, forceRefresh: true);
    if (!mounted) return;
    final userId = data.userId?.trim() ?? '';
    if (userId.isEmpty) {
      _showCopyToast('This contact is not on Wrytte');
      return;
    }
    if (_matrixLocalpart(userId) == _matrixLocalpart(widget.currentUserId)) {
      _showCopyToast('This is your contact');
      return;
    }

    try {
      final conversationId = await _chat.getMatrixConversationId(userId);
      if (!mounted) return;
      if (conversationId == null || conversationId.isEmpty) {
        _showCopyToast('Could not open chat');
        return;
      }
      if (conversationId == _activeConversationId) return;
      final initialMessages = await _chat.loadInitialMessageWindow(
        conversationId,
      );
      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder:
              (_) => ChatScreen(
                conversationId: conversationId,
                receiverId: userId,
                currentUserId: widget.currentUserId,
                title: data.name,
                avatarUrl: data.avatarUrl,
                initialMessages: initialMessages,
                conversationKind: ConversationKind.direct,
              ),
        ),
      );
    } catch (error) {
      apkLog(
        'ChatScreen.contact',
        'open chat failed user_id="$userId" error="$error"',
      );
      if (mounted) _showCopyToast('Could not open chat');
    }
  }

  Future<void> _openSharedContactProfile(ChatMessage message) async {
    final data = await _resolveSharedContactData(message, forceRefresh: true);
    if (!mounted) return;
    final userId = data.userId?.trim() ?? '';
    if (userId.isEmpty) {
      _showCopyToast('Profile unavailable');
      return;
    }

    try {
      final conversationId = await _chat.findMatrixConversationId(userId);
      await AvatarPreloadService.warm(
        data.avatarUrl,
        cacheIdentity: 'user:${userId.trim().toLowerCase()}',
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder:
              (_) => ProfileScreen(
                uid: userId,
                conversationId: conversationId,
                savedNameHint: data.name,
                initialAvatarUrl: data.avatarUrl,
              ),
        ),
      );
    } catch (error) {
      apkLog(
        'ChatScreen.contact',
        'open profile failed user_id="$userId" error="$error"',
      );
      if (mounted) _showCopyToast('Could not open profile');
    }
  }

  Future<String> _resolveConversationId() async {
    if (_resolvedConversationId != null) return _resolvedConversationId!;

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    apkLog(
      'ChatScreen._resolveConv',
      'raw="${widget.receiverId}"  '
          'normalised="$normalisedReceiverId"  '
          'passedConvId="${widget.conversationId}"',
    );

    final suppliedRoomIsAllowed =
        widget.conversationId.startsWith('!') && _suppliedRoomMatchesScreenKind;
    if (suppliedRoomIsAllowed) {
      _resolvedConversationId = widget.conversationId;
      _chat.activateConversationRead(widget.conversationId);
      apkLog(
        'ChatScreen._resolveConv',
        'used passedConvId → "$_resolvedConversationId"',
      );
      return _resolvedConversationId!;
    }

    if (!_matrixAvailable) {
      apkLog(
        'ChatScreen._resolveConv',
        'Matrix unavailable; using local convId "${widget.conversationId}"',
      );
      return widget.conversationId;
    }

    final matrixConversationId = await _chat.findMatrixConversationId(
      normalisedReceiverId,
    );
    if (matrixConversationId == null) {
      apkLog(
        'ChatScreen._resolveConv',
        'Matrix direct room unavailable; using local convId "${widget.conversationId}"',
      );
      return widget.conversationId;
    }

    _resolvedConversationId = matrixConversationId;
    _chat.activateConversationRead(matrixConversationId);
    apkLog(
      'ChatScreen._resolveConv',
      'Matrix direct room -> "$_resolvedConversationId"',
    );

    return _resolvedConversationId!;
  }

  Future<String?> _resolveMatrixConversationIdForSend() async {
    if (_isSelfConversation) {
      _logSelfConversationBlocked('resolve/send room');
      return null;
    }

    final normalisedReceiverId = _normaliseId(widget.receiverId);
    final suppliedRoomIsAllowed =
        widget.conversationId.startsWith('!') && _suppliedRoomMatchesScreenKind;
    if (suppliedRoomIsAllowed) {
      _resolvedConversationId = widget.conversationId;
      _chat.activateConversationRead(widget.conversationId);
      return widget.conversationId;
    }

    try {
      apkLog('ChatScreen._resolveSendConv', 'validating Matrix before send...');
      await _chat.connect();
      _matrixAvailable = true;
    } catch (e) {
      _matrixAvailable = false;
      apkLog('ChatScreen._resolveSendConv', 'Matrix connect failed: $e');
      return null;
    }

    final matrixConversationId = await _chat.getMatrixConversationId(
      normalisedReceiverId,
    );
    if (matrixConversationId == null) {
      apkLog(
        'ChatScreen._resolveSendConv',
        'failed to create/reuse Matrix direct room',
      );
      return null;
    }
    _resolvedConversationId = matrixConversationId;
    _chat.activateConversationRead(matrixConversationId);
    return matrixConversationId;
  }

  // ─── INIT ──────────────────────────────────────────────────────────────────
}
