import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrytte/models/user_models/user_profile.dart';
import 'package:wrytte/models/user_models/wrytte_profile.dart';
import 'package:wrytte/services/auth/api_service.dart';
import 'package:wrytte/services/auth/auth_service.dart';
import 'package:wrytte/services/contacts/contact_identity_cache.dart';
import 'package:wrytte/services/user/user_profile_api_service.dart';
import 'package:wrytte/services/matrix/matrix_client.dart';
import 'package:wrytte/services/matrix/matrix_profile_service.dart';
import 'package:wrytte/utils/apk_debug_logger.dart';

/// Production-grade local-only UserProfileService.
/// Source of truth is FlutterSecureStorage via AuthService.
class UserProfileService {
  UserProfileService._() {
    MatrixClientService.instance.profileUpdateStream.listen(
      _handlePublicProfileUpdated,
    );
    for (final userId
        in MatrixClientService.instance.takePendingProfileUpdates()) {
      _handlePublicProfileUpdated(userId);
    }
  }
  static final UserProfileService instance = UserProfileService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static const _nameKey = 'username';
  static const _firstNameKey = 'profile_first_name';
  static const _lastNameKey = 'profile_last_name';
  static const _phoneKey = 'phone';
  static const _profileImageKey = 'profile_image';
  static const _bioKey = 'user_bio';
  static const _localProfileImagePrefix = 'profile_image_local_path_';
  static const _pendingProfileImagePrefix = 'profile_image_pending_upload_';
  static const _avatarVersionPrefix = 'profile_avatar_version_';

  // In-memory cache — survives the widget lifecycle, cleared on logout
  UserProfile? _cache;
  DateTime? _lastPendingAvatarAttemptAt;
  final Map<String, UserProfile> _publicProfileCache = {};
  final Map<String, Future<UserProfile?>> _publicProfileInFlight = {};
  final Map<String, DateTime> _publicProfileFetchedAt = {};
  final Set<String> _publicProfileMisses = {};
  final Set<String> _avatarDeletionsInProgress = {};
  Future<UserProfile?>? _loginProfileInFlight;
  DateTime? _currentProfileBackendFetchedAt;
  int _sessionGeneration = 0;
  String? _activeAccountUid;
  bool _logoutInProgress = false;
  static const _currentProfileFreshness = Duration(minutes: 5);
  bool _suppressBackendProfileReads = false;
  final StreamController<UserProfile?> _profileController =
      StreamController<UserProfile?>.broadcast();
  final StreamController<String> _publicProfileUpdateController =
      StreamController<String>.broadcast();
  final Set<String> _publicProfileRefreshInFlight = <String>{};

  Stream<String> get publicProfileUpdateStream =>
      _publicProfileUpdateController.stream;

  bool isPublicProfileRefreshing(String userId) => _publicProfileRefreshInFlight
      .contains(_matrixLocalpart(userId).toLowerCase());

  void _handlePublicProfileUpdated(String userId) {
    final localpart = _matrixLocalpart(userId).toLowerCase();
    if (localpart.isEmpty) return;
    MatrixProfileService.instance.clearCachedProfile(userId);
    _publicProfileCache.removeWhere(
      (key, _) => _matrixLocalpart(key).toLowerCase() == localpart,
    );
    _publicProfileMisses.removeWhere(
      (key) => _matrixLocalpart(key).toLowerCase() == localpart,
    );
    _publicProfileUpdateController.add(userId);
    debugPrint(
      '[UserProfileService] invalidated public profile user_id="$userId"',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  void setFirstSignupMode(bool enabled) {
    _suppressBackendProfileReads = enabled;
    _logoutInProgress = false;
    if (enabled) {
      // A signup starts a different account. Do not let a prior account's
      // in-flight profile read or in-memory identity reach the new account.
      clearCache();
    }
  }

  /// Returns the current user's profile, using the in-memory cache when
  /// available. Pass [forceRefresh] = true to always re-read from storage.
  Future<UserProfile?> getCurrentUserProfile({
    bool forceRefresh = false,
  }) async {
    if (_cache != null && !forceRefresh) {
      final uid = await AuthService.instance.getCurrentUserId();
      if (uid != null && uid.isNotEmpty && _cache!.uid == uid) return _cache;
    }
    return _readFromStorage(forceRefresh: forceRefresh);
  }

  /// First-signup bootstrap. No backend profile/avatar read is performed
  /// because the account has not created an avatar yet.
  Future<UserProfile?> getCurrentUserProfileLocalOnly() {
    return _readFromStorage(allowBackendRefresh: false);
  }

  /// Returning-login bootstrap. The avatar is intentionally not read from
  /// local storage: logout removes it and the authenticated backend profile is
  /// the only source allowed to repopulate it for this session.
  Future<UserProfile?> getCurrentUserProfileForLogin() {
    _suppressBackendProfileReads = false;
    _logoutInProgress = false;
    final pending = _loginProfileInFlight;
    if (pending != null) return pending;
    _cache = null;
    final future = _readFromStorage(
      forceRefresh: true,
      allowBackendRefresh: true,
      ignoreStoredAvatar: true,
      ignoreStoredProfile: true,
    );
    _loginProfileInFlight = future;
    return future
        .then((profile) {
          if (profile != null) {
            _currentProfileBackendFetchedAt = DateTime.now();
            apkLog(
              'Profile.bootstrap',
              'backend profile ready user_id="${profile.uid}" '
                  'avatar=${profile.hasProfileImage} '
                  'avatar_version=${profile.avatarVersion}',
            );
          }
          return profile;
        })
        .whenComplete(() {
          if (identical(_loginProfileInFlight, future)) {
            _loginProfileInFlight = null;
          }
        });
  }

  /// Persists an updated display name and invalidates the cache.
  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _storage.write(key: _nameKey, value: trimmed);
    final parts = _splitName(trimmed);
    await _storage.write(key: _firstNameKey, value: parts.$1);
    await _storage.write(key: _lastNameKey, value: parts.$2);
    // Also keep AuthService in sync (it owns the same key)
    await AuthService.instance.updateStoredUsername(trimmed);
    await _saveBackendProfileBestEffort({
      'FirstName': parts.$1,
      if (parts.$2.isNotEmpty) 'LastName': parts.$2,
    });
    _cache = null;
    debugPrint('[UserProfileService] Display name updated: "$trimmed"');
  }

  /// Persists a profile image URL and invalidates the cache.
  Future<void> updateProfileImage(String url) async {
    await _storage.write(
      key: _profileImageKey,
      value: _resolveAvatarUrl(url.trim()),
    );
    _cache = null;
    await _refreshAndNotify();
  }

  Future<void> deleteProfileImage() async {
    final uid = await AuthService.instance.getCurrentUserId();
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Not authenticated.');
    }
    _avatarDeletionsInProgress.add(uid);
    try {
      // Clear local/cache sources before any network operation. Other profile
      // reads may already be running while the delete request is in flight.
      MatrixProfileService.instance.clearCachedProfile(uid);
      await ContactIdentityCache.instance.upsert(
        ownerUserId: uid,
        matrixUserId: uid,
        clearAvatar: true,
      );
      await MatrixProfileService.instance.deleteAvatar(uid);
      await _storage.delete(key: _profileImageKey);
      await _writeAvatarVersion(uid, 0);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localProfileImageKey(uid));
      await prefs.remove(_pendingProfileImageKey(uid));
      _cache = null;
      await _refreshAndNotify(forceRefresh: true);
    } finally {
      _avatarDeletionsInProgress.remove(uid);
    }
  }

  Future<String> uploadProfileImage(File file) async {
    final uid = await AuthService.instance.getCurrentUserId();
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated.');
    }

    final localPath = await _cacheProfileImageFile(uid, file);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localProfileImageKey(uid), localPath);
    await prefs.setString(_pendingProfileImageKey(uid), localPath);
    _cache = null;
    await _refreshAndNotify();

    try {
      final uploadedPath = await UserProfileApiService.instance
          .uploadAvatarImage(File(localPath));
      final avatarVersion = await UserProfileApiService.instance
          .incrementAvatarVersion();
      final avatarUrl = _withAvatarFetchVersion(
        _resolveAvatarUrl(uploadedPath),
        uid,
        avatarVersion,
      );
      if (avatarUrl.isEmpty) {
        throw Exception('Avatar upload completed without an image URL.');
      }
      // The backend avatar service stores files under /usrimg/...; it does
      // not create Matrix media (mxc://) objects. Persist the returned HTTP
      // URL in the Wrytte Matrix profile so other users request the same
      // backend resource instead of a non-existent Synapse media ID.
      await MatrixProfileService.instance.setAvatarImageUrl(uid, avatarUrl);
      await _storage.write(key: _profileImageKey, value: avatarUrl);
      await _writeAvatarVersion(uid, avatarVersion);
      await prefs.remove(_pendingProfileImageKey(uid));
      _cache = null;
      await _refreshAndNotify(forceRefresh: true);
      return avatarUrl;
    } catch (e) {
      _lastPendingAvatarAttemptAt = DateTime.now();
      debugPrint('[UserProfileService] Avatar upload pending: $e');
      rethrow;
    }
  }

  Future<void> syncPendingAvatarUpload() async {
    final uid = await AuthService.instance.getCurrentUserId();
    if (uid == null || uid.isEmpty) return;
    final uploaded = await _syncPendingAvatarUploadForUid(uid);
    if (uploaded) {
      _cache = null;
      await _refreshAndNotify(forceRefresh: true);
    }
  }

  /// Persists a bio and invalidates the cache.
  Future<void> updateBio(String bio) async {
    await _storage.write(key: _bioKey, value: bio.trim());
    await _saveBackendProfileBestEffort({'Bio': bio.trim()});
    _cache = null;
    await _refreshAndNotify(forceRefresh: true);
  }

  /// Convenience: update multiple fields in one write pass.
  Future<void> updateProfile({
    String? name,
    String? firstName,
    String? lastName,
    String? profileImage,
    String? bio,
    List<String>? links,
    String? channelAlias,
    String? groupAlias,
    Map<String, String>? visibilitySettings,
  }) async {
    final backendFields = <String, String>{};
    if (name != null && name.trim().isNotEmpty) {
      await _storage.write(key: _nameKey, value: name.trim());
      await AuthService.instance.updateStoredUsername(name.trim());
      final parts = _splitName(name.trim());
      await _storage.write(key: _firstNameKey, value: firstName ?? parts.$1);
      await _storage.write(key: _lastNameKey, value: lastName ?? parts.$2);
      backendFields['FirstName'] = firstName?.trim() ?? parts.$1;
      if ((lastName?.trim() ?? parts.$2).isNotEmpty) {
        backendFields['LastName'] = lastName?.trim() ?? parts.$2;
      }
    } else {
      if (firstName != null) {
        await _storage.write(key: _firstNameKey, value: firstName.trim());
        backendFields['FirstName'] = firstName.trim();
      }
      if (lastName != null) {
        await _storage.write(key: _lastNameKey, value: lastName.trim());
        backendFields['LastName'] = lastName.trim();
      }
    }
    if (profileImage != null) {
      await _storage.write(
        key: _profileImageKey,
        value: _resolveAvatarUrl(profileImage.trim()),
      );
    }
    if (bio != null) {
      await _storage.write(key: _bioKey, value: bio.trim());
      backendFields['Bio'] = bio.trim();
    }
    if (links != null) {
      await _storage.write(key: 'user_links', value: links.join('\n'));
    }
    if (channelAlias != null) {
      await _storage.write(key: 'channel_alias', value: channelAlias.trim());
    }
    if (groupAlias != null) {
      await _storage.write(key: 'group_alias', value: groupAlias.trim());
    }
    if (visibilitySettings != null) {
      await _storage.write(
        key: 'profile_visibility',
        value: visibilitySettings.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(';'),
      );
    }

    // Persist profile fields in the Matrix profile module as well as local
    // storage. Local storage is cleared on logout, so links, channel, and
    // group aliases must be written to the account-backed profile service.
    final ownerUserId = await AuthService.instance.getCurrentUserId();
    if (ownerUserId != null && ownerUserId.trim().isNotEmpty) {
      try {
        final firstLink = links == null
            ? null
            : (links.isNotEmpty ? links.first.trim() : '');
        await MatrixProfileService.instance.updateOwnerProfile(
          userId: ownerUserId,
          displayName: name,
          bio: bio,
          link: firstLink,
          channelAlias: channelAlias,
          groupAlias: groupAlias,
          visibilitySettings: visibilitySettings,
        );
      } catch (error) {
        debugPrint(
          '[UserProfileService] Matrix profile save skipped: $error',
        );
      }
    }
    if (backendFields.isNotEmpty) {
      await _saveBackendProfileBestEffort(backendFields);
    }
    if (name != null && name.trim().isNotEmpty) {
      final ownerUserId = await AuthService.instance.getCurrentUserId();
      if (ownerUserId != null && ownerUserId.trim().isNotEmpty) {
        try {
          // Keep Matrix's public display name in sync with the registered
          // Wrytte profile name so other users do not see the Wrytte ID.
          await MatrixProfileService.instance.setDisplayName(
            ownerUserId,
            name.trim(),
          );
        } catch (error) {
          apkLog(
            'ProfileName.sync',
            'Matrix display-name sync failed user_id="$ownerUserId" error="$error"',
          );
        }
      }
    }
    _cache = null;
    await _refreshAndNotify(forceRefresh: true);
  }

  /// Stream that emits the current user's profile immediately from cache,
  /// then re-reads from storage. Use this in widgets that need live updates
  /// (e.g. after the user saves a new name or avatar).
  Stream<UserProfile?> getCurrentUserProfileStream({
    bool backendFirst = false,
    bool refreshFromBackend = true,
  }) async* {
    if (backendFirst && !_suppressBackendProfileReads) {
      final backendProfile = await getCurrentUserProfileForLogin();
      if (backendProfile != null) yield backendProfile;
      yield* _profileController.stream;
      return;
    }

    // Emit cached value instantly so the UI has zero-latency first frame
    final uid = await AuthService.instance.getCurrentUserId();
    if (_cache != null && uid != null && uid.isNotEmpty && _cache!.uid == uid) {
      yield _cache;
    }

    // Then yield a local-only read. Network/profile refresh must not block
    // avatar paint in the bottom nav.
    final fresh = await _readFromStorage(allowBackendRefresh: false);
    if (fresh != null) yield fresh;
    if (refreshFromBackend &&
        !_suppressBackendProfileReads &&
        !_currentBackendProfileIsFresh) {
      unawaited(_refreshAndNotify(forceRefresh: true));
    }
    yield* _profileController.stream;
  }

  /// Warm the cache on app start — call from main.dart after auth restore.
  Future<void> warmUp() async {
    _cache = await _readFromStorage(allowBackendRefresh: false);
    _profileController.add(_cache);
    unawaited(_syncPendingAvatarAndRefresh());
  }

  /// Fetches another user's profile by their UID.
  /// For the current user, delegates to [getCurrentUserProfile].
  /// For other users, returns a minimal stub built from what we know locally
  /// (contacts, Matrix display name, etc.) — extend as your contact store grows.
  Future<UserProfile?> getProfileByUid(
    String uid, {
    String? phone,
    bool forceRefresh = false,
  }) async {
    final requestedUid = uid.trim();
    if (requestedUid.isEmpty ||
        requestedUid.startsWith('!') ||
        requestedUid.startsWith('@!')) {
      debugPrint(
        '[UserProfileService] skipped room-scoped profile lookup: "$requestedUid"',
      );
      return null;
    }
    final currentUid = await AuthService.instance.getCurrentUserId();

    // If it's the current user, use the full local profile
    if (currentUid != null &&
        _matrixLocalpart(currentUid) == _matrixLocalpart(uid)) {
      return getCurrentUserProfile(forceRefresh: true);
    }

    final cacheKey = _publicProfileCacheKey(uid, phone);
    if (!forceRefresh) {
      final cached = _publicProfileCache[cacheKey];
      if (cached != null) return cached;
      if (_publicProfileMisses.contains(cacheKey)) return null;

      final pending = _publicProfileInFlight[cacheKey];
      if (pending != null) return pending;
    } else {
      _publicProfileMisses.remove(cacheKey);
      final pending = _publicProfileInFlight[cacheKey];
      if (pending != null) return pending;
    }

    final localpart = _matrixLocalpart(uid).toLowerCase();
    _publicProfileRefreshInFlight.add(localpart);
    final future = _getProfileByUidRemote(uid, phone: phone);
    _publicProfileInFlight[cacheKey] = future;
    return future.whenComplete(() {
      if (identical(_publicProfileInFlight[cacheKey], future)) {
        _publicProfileInFlight.remove(cacheKey);
      }
      _publicProfileRefreshInFlight.remove(localpart);
      _publicProfileUpdateController.add(uid);
    });
  }

  Future<UserProfile?> _getProfileByUidRemote(
    String uid, {
    String? phone,
  }) async {
    final generation = _sessionGeneration;
    final cacheKey = _publicProfileCacheKey(uid, phone);
    final backendRemote = await _readPublicBackendProfileBestEffort(
      uid,
      phone: phone,
    );
    final remote = <String, String>{...backendRemote};

    // Public backend profiles do not always contain the avatar saved through
    // the Matrix/Wrytte Module API. Merge that source before constructing the
    // profile so other users' avatars are not lost merely because the legacy
    // profile endpoint returned name/phone fields only.
    final hasAvatar = <String>[
      'AvatarImg',
      'avatarImg',
      'AvatarUrl',
      'avatarUrl',
      'ProfileImage',
      'profileImage',
      WrytteProfile.avatarImageUrl,
    ].any((key) => remote[key]?.trim().isNotEmpty == true);
    // The Wrytte profile API is authoritative when it returns a profile,
    // including an explicit profile with no avatar. Only consult Matrix when
    // the Wrytte profile endpoint returned no profile data at all; otherwise
    // Matrix can resurrect a stale/deleted avatar URL.
    if (backendRemote.isNotEmpty || !hasAvatar) {
      try {
        final matrixProfile = await MatrixProfileService.instance.getProfile(
          uid,
        );
        debugPrint(
          '[ProfileModuleRead] user_id="$uid" '
          'avatar="${matrixProfile[WrytteProfile.avatarImageUrl] ?? ''}" '
          'version="${matrixProfile[WrytteProfile.avatarVersion] ?? ''}" '
          'bio_present=${(matrixProfile[WrytteProfile.bio] ?? '').trim().isNotEmpty} '
          'link_present=${(matrixProfile[WrytteProfile.link] ?? '').trim().isNotEmpty} '
          'channel="${matrixProfile[WrytteProfile.channelAlias] ?? ''}" '
          'group="${matrixProfile[WrytteProfile.groupAlias] ?? ''}" '
          'visibility_present=${matrixProfile.fields[WrytteProfile.visibility] != null} '
          'online_status="${matrixProfile[WrytteProfile.onlineVisibilitySetting] ?? ''}"',
        );
        final matrixAvatar = matrixProfile.avatarUrl?.trim() ?? '';
        if (matrixAvatar.isNotEmpty) {
          remote['UserId'] = uid;
          remote['AvatarImg'] = matrixAvatar;
          final version = matrixProfile.fields[WrytteProfile.avatarVersion];
          if (version != null) remote['AvatarVersion'] = version.toString();
        }
        final moduleBio = matrixProfile[WrytteProfile.bio]?.trim() ?? '';
        final moduleLink = matrixProfile[WrytteProfile.link]?.trim() ?? '';
        final moduleChannel =
            matrixProfile[WrytteProfile.channelAlias]?.trim() ?? '';
        final moduleGroup =
            matrixProfile[WrytteProfile.groupAlias]?.trim() ?? '';
        if (moduleBio.isNotEmpty) remote['Bio'] = moduleBio;
        if (moduleLink.isNotEmpty) remote['Link'] = moduleLink;
        if (moduleChannel.isNotEmpty) {
          remote['ChannelAlias'] = moduleChannel;
        }
        if (moduleGroup.isNotEmpty) remote['GroupAlias'] = moduleGroup;
        final visibility = matrixProfile.fields[WrytteProfile.visibility];
        if (visibility is Map) {
          remote['ProfileVisibility'] = jsonEncode(visibility);
        }
      } catch (error) {
        debugPrint(
          '[UserProfileService] Matrix avatar fallback skipped '
          'user_id="$uid" error=$error',
        );
      }
    }
    if (generation != _sessionGeneration) return null;
    if (remote.isEmpty) {
      final fallback = _fallbackPublicProfile(uid, phone: phone);
      _publicProfileCache[cacheKey] = fallback;
      return fallback;
    }
    if (!_matchesRequestedPublicProfile(remote, uid: uid, phone: phone)) {
      debugPrint(
        '[UserProfileService] rejected unverified public profile for "$uid"',
      );
      final fallback = _fallbackPublicProfile(uid, phone: phone);
      _publicProfileCache[cacheKey] = fallback;
      return fallback;
    }
    final fetchedAt = DateTime.now();
    var profile = _profileFromBackendFields(uid, remote, fallbackPhone: phone);
    if (profile.hasProfileImage) {
      profile = profile.copyWith(
        profileImage: _withAvatarFetchVersion(
          profile.profileImage,
          uid,
          profile.avatarVersion,
        ),
      );
    }
    profile = _reuseStablePublicAvatar(cacheKey, profile);
    // Public/member avatars remain URL-backed and are cached lazily by
    // CachedNetworkImage when rendered. Eager file downloads here duplicated
    // that cache and repeatedly timed out for profiles not on screen.
    _publicProfileCache[cacheKey] = profile;
    _publicProfileFetchedAt[cacheKey] = fetchedAt;
    return profile;
  }

  /// Wipe cache on logout.
  void clearCache() {
    _sessionGeneration += 1;
    _activeAccountUid = null;
    _cache = null;
    _publicProfileCache.clear();
    _publicProfileInFlight.clear();
    _publicProfileFetchedAt.clear();
    _publicProfileMisses.clear();
    _publicProfileRefreshInFlight.clear();
    _loginProfileInFlight = null;
    _currentProfileBackendFetchedAt = null;
    _profileController.add(null);
  }

  /// Called before the logout storage purge starts. It prevents outgoing
  /// widgets from starting another read against the former account while its
  /// shared legacy storage keys are being deleted.
  void beginLogout() {
    _logoutInProgress = true;
    clearCache();
  }

  // Expose cached value synchronously for widgets that need it immediately
  UserProfile? get cachedProfile => _cache;

  UserProfile? cachedPublicProfileByUid(String uid, {String? phone}) {
    final localpart = _matrixLocalpart(uid).toLowerCase();
    if (localpart.isEmpty) return null;

    final cacheKey = _publicProfileCacheKey(uid, phone);
    final exact = _publicProfileCache[cacheKey];
    if (exact != null) {
      if (_hasIdentifierOnlyName(exact)) {
        _removeCachedPublicProfile(cacheKey);
        return null;
      }
      return exact;
    }

    for (final entry in _publicProfileCache.entries) {
      if (entry.key.startsWith('$localpart|')) {
        if (_hasIdentifierOnlyName(entry.value)) {
          _removeCachedPublicProfile(entry.key);
          return null;
        }
        return entry.value;
      }
    }
    return null;
  }

  bool _hasIdentifierOnlyName(UserProfile profile) {
    bool looksLikePhone(String value) {
      final compact = value.replaceAll(RegExp(r'[\s\-()+]'), '');
      return compact.isNotEmpty && RegExp(r'^\d{7,}$').hasMatch(compact);
    }

    final name = profile.name.trim();
    final username = profile.username.trim();
    return (name.isNotEmpty && looksLikePhone(name)) ||
        (username.isNotEmpty && looksLikePhone(username));
  }

  void _removeCachedPublicProfile(String cacheKey) {
    _publicProfileCache.remove(cacheKey);
    _publicProfileFetchedAt.remove(cacheKey);
    _publicProfileMisses.remove(cacheKey);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────────────────────

  Future<UserProfile?> _readFromStorage({
    bool forceRefresh = false,
    bool allowBackendRefresh = true,
    bool ignoreStoredAvatar = false,
    bool ignoreStoredProfile = false,
  }) async {
    try {
      if (_logoutInProgress) return null;
      final uid = await AuthService.instance.getCurrentUserId();
      if (uid == null || uid.isEmpty) return null;
      final generation = _bindActiveAccount(uid);
      if (_logoutInProgress || !_isActiveSession(generation, uid)) return null;

      final phone = _normalizePhone(await _storage.read(key: _phoneKey) ?? '');
      var name = ignoreStoredProfile
          ? ''
          : await _storage.read(key: _nameKey) ?? '';
      var firstName = ignoreStoredProfile
          ? ''
          : await _storage.read(key: _firstNameKey) ?? '';
      var lastName = ignoreStoredProfile
          ? ''
          : await _storage.read(key: _lastNameKey) ?? '';
      var bio = ignoreStoredProfile
          ? ''
          : await _storage.read(key: _bioKey) ?? '';
      var profileImage = ignoreStoredAvatar || ignoreStoredProfile
          ? ''
          : await _storage.read(key: _profileImageKey) ?? '';
      var localProfileImagePath = ignoreStoredAvatar || ignoreStoredProfile
          ? ''
          : await _readLocalProfileImagePath(uid);
      var avatarVersion = ignoreStoredAvatar || ignoreStoredProfile
          ? 0
          : await _readAvatarVersion(uid);

      if (forceRefresh && !ignoreStoredProfile) {
        final uploaded = await _syncPendingAvatarUploadForUid(uid);
        if (uploaded) {
          profileImage = await _storage.read(key: _profileImageKey) ?? '';
          localProfileImagePath = await _readLocalProfileImagePath(uid);
        }
      }

      if (allowBackendRefresh &&
          !_suppressBackendProfileReads &&
          (forceRefresh || !_hasRealName(name) || profileImage.isEmpty)) {
        final remote = await _readBackendProfileBestEffort();
        if (!_isActiveSession(generation, uid)) return null;
        if (remote.isNotEmpty) {
          firstName = _field(remote, 'FirstName') ?? firstName;
          lastName = _field(remote, 'LastName') ?? lastName;
          bio = _field(remote, 'Bio') ?? bio;
          final remoteAvatar = _resolveAvatarUrl(
            _field(remote, 'AvatarImg') ?? profileImage,
          );
          if (remoteAvatar.isNotEmpty &&
              !_avatarUrlBelongsToUid(remoteAvatar, uid)) {
            debugPrint(
              '[UserProfileService] rejected cross-account current avatar '
              'active_user="$uid" avatar_url="$remoteAvatar"',
            );
            profileImage = '';
          } else {
            profileImage = remoteAvatar;
          }
          avatarVersion = _avatarVersionFromFields(remote);
          if (profileImage.isNotEmpty) {
            profileImage = _withAvatarFetchVersion(
              profileImage,
              uid,
              avatarVersion,
            );
          }
          final remoteName = [
            firstName,
            lastName,
          ].where((part) => part.trim().isNotEmpty).join(' ').trim();
          if (_hasRealName(remoteName)) {
            if (!_isActiveSession(generation, uid)) return null;
            name = remoteName;
            await _storage.write(key: _nameKey, value: name);
            await _storage.write(key: _firstNameKey, value: firstName);
            await _storage.write(key: _lastNameKey, value: lastName);
            await AuthService.instance.updateStoredUsername(name);
          }
          if (!_isActiveSession(generation, uid)) return null;
          await _storage.write(key: _bioKey, value: bio);
          if (profileImage.isNotEmpty) {
            await _storage.write(key: _profileImageKey, value: profileImage);
            await _writeAvatarVersion(uid, avatarVersion);
          }
        }
      }
      if (!_hasRealName(name) && !ignoreStoredProfile) {
        await AuthService.instance.getValidBackendToken();
        name = await _storage.read(key: _nameKey) ?? name;
      }
      if (!_hasRealName(name) && !ignoreStoredProfile) {
        final restored = await AuthService.instance.hydrateStoredProfile(uid);
        if (restored != null && restored.hasUsableName) {
          name = restored.username;
          await _storage.write(key: _nameKey, value: name);
        }
      }
      var linksRaw = ignoreStoredProfile
          ? ''
          : await _storage.read(key: 'user_links') ?? '';
      var channelAlias = ignoreStoredProfile
          ? ''
          : await _storage.read(key: 'channel_alias') ?? '';
      var groupAlias = ignoreStoredProfile
          ? ''
          : await _storage.read(key: 'group_alias') ?? '';

      // Module API is the account-backed source for Wrytte custom fields.
      // Restore these fields after login because local storage is cleared on
      // logout.
      if (!ignoreStoredProfile) {
        try {
          final moduleProfile = await MatrixProfileService.instance.getProfile(
            uid,
          );
          final moduleBio = moduleProfile[WrytteProfile.bio]?.trim() ?? '';
          final moduleLink = moduleProfile[WrytteProfile.link]?.trim() ?? '';
          final moduleChannel =
              moduleProfile[WrytteProfile.channelAlias]?.trim() ?? '';
          final moduleGroup =
              moduleProfile[WrytteProfile.groupAlias]?.trim() ?? '';
          if (moduleBio.isNotEmpty) bio = moduleBio;
          if (moduleLink.isNotEmpty) linksRaw = moduleLink;
          if (moduleChannel.isNotEmpty) channelAlias = moduleChannel;
          if (moduleGroup.isNotEmpty) groupAlias = moduleGroup;
        } catch (error) {
          debugPrint(
            '[UserProfileService] Module profile restore skipped: $error',
          );
        }
      }

      // Keep the owner profile consistent across Profile, Edit Profile, and
      // BottomNavBar. Older sessions may have the avatar only in the identity
      // cache while secure storage/backend still return an empty image field.
      // The identity cache is keyed by the authenticated owner and is the
      // same source ProfileScreen already uses for its first paint.
      final deletionInProgress = _avatarDeletionsInProgress.contains(uid);
      if (deletionInProgress) {
        profileImage = '';
        localProfileImagePath = '';
      } else if (profileImage.trim().isEmpty) {
        final identity = await ContactIdentityCache.instance.findByMatrixId(
          ownerUserId: uid,
          matrixUserId: uid,
        );
        final cachedAvatar = identity?.avatarUrl?.trim() ?? '';
        if (cachedAvatar.isNotEmpty) {
          profileImage = cachedAvatar;
          debugPrint(
            '[UserProfileService] owner avatar restored from identity cache '
            'uid="$uid" url="$profileImage"',
          );
        }
      }

      final profile = UserProfile(
        uid: uid,
        name: name,
        username: name, // username == display name in this app
        phone: phone,
        bio: bio,
        profileImage: profileImage,
        avatarVersion: avatarVersion,
        localProfileImagePath: localProfileImagePath,
        channelAlias: channelAlias.trim(),
        groupAlias: groupAlias.trim(),
        links: linksRaw
            .split('\n')
            .map((link) => link.trim())
            .where((link) => link.isNotEmpty)
            .toList(),
      );

      // A logout/account switch may finish while a backend request from the
      // previous screen is still in flight. Never allow that stale completion
      // to repopulate the process-wide profile cache for the next account.
      if (!_isActiveSession(generation, uid)) return null;
      _cache = profile;
      _profileController.add(profile);
      return profile;
    } catch (e) {
      debugPrint('[UserProfileService] _readFromStorage error: $e');
      return null;
    }
  }

  String _normalizePhone(String phone) {
    var cleaned = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('00') && cleaned.length > 4) {
      cleaned = '+${cleaned.substring(2)}';
    }
    if (!cleaned.startsWith('+') && cleaned.isNotEmpty) cleaned = '+$cleaned';
    cleaned = _stripInvalidNorthAmericaPrefix(cleaned);
    return cleaned;
  }

  /// Binds all current-profile reads to one authenticated account. Secure
  /// storage uses a few legacy shared keys, so an async read that belongs to
  /// a former account must become invalid as soon as another account starts.
  int _bindActiveAccount(String uid) {
    final normalizedUid = _matrixLocalpart(uid).toLowerCase();
    if (_activeAccountUid == normalizedUid) return _sessionGeneration;

    _sessionGeneration += 1;
    _activeAccountUid = normalizedUid;
    _cache = null;
    _loginProfileInFlight = null;
    _currentProfileBackendFetchedAt = null;
    _profileController.add(null);
    debugPrint(
      '[UserProfileService] profile session bound '
      'user_id="$normalizedUid" generation=$_sessionGeneration',
    );
    return _sessionGeneration;
  }

  bool _isActiveSession(int generation, String uid) {
    return generation == _sessionGeneration &&
        _activeAccountUid == _matrixLocalpart(uid).toLowerCase();
  }

  /// Backend avatar paths are account-owned (for example
  /// `/usrimg/<user-id>/avatar_img.jpg`). Never display an avatar whose path
  /// identifies another account, even if a stale response reaches this code.
  bool _avatarUrlBelongsToUid(String avatarUrl, String uid) {
    final owner = _matrixLocalpart(uid).toLowerCase();
    final path =
        Uri.tryParse(avatarUrl)?.path.toLowerCase() ??
        avatarUrl.toLowerCase().split('?').first;
    return path.contains('/$owner/');
  }

  bool get _currentBackendProfileIsFresh {
    final fetchedAt = _currentProfileBackendFetchedAt;
    return fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _currentProfileFreshness;
  }

  String _stripInvalidNorthAmericaPrefix(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (!phone.startsWith('+1')) return phone;
    if (digits.length <= 11) return phone;
    return '+${digits.substring(1)}';
  }

  String _trustedPhone(String backendPhone, {String? fallbackPhone}) {
    final normalizedBackend = _normalizePhone(backendPhone);
    final normalizedFallback = _normalizePhone(fallbackPhone ?? '');
    if (normalizedBackend.isEmpty) return normalizedFallback;
    if (normalizedFallback.isEmpty) return normalizedBackend;

    final backendDigits = normalizedBackend.replaceAll(RegExp(r'[^\d]'), '');
    final fallbackDigits = normalizedFallback.replaceAll(RegExp(r'[^\d]'), '');
    final backendLooksLikePrefixedFallback =
        backendDigits.startsWith('1') &&
        backendDigits.substring(1) == fallbackDigits;
    if (backendLooksLikePrefixedFallback) {
      return normalizedFallback;
    }

    return normalizedBackend;
  }

  String _matrixLocalpart(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('@') && trimmed.contains(':')) {
      return trimmed.substring(1, trimmed.indexOf(':'));
    }
    return trimmed;
  }

  bool _looksLikePhone(String value) {
    final s = value.trim().replaceAll(RegExp(r'[\s\-()+]'), '');
    return RegExp(r'^\d{6,}$').hasMatch(s);
  }

  bool _hasRealName(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return false;
    final lowered = trimmed.toLowerCase();
    if (lowered == 'user' || lowered == 'uder' || lowered == 'unknown') {
      return false;
    }
    if (_looksLikePhone(trimmed)) return false;
    final localpart = trimmed.startsWith('@')
        ? trimmed.substring(1).split(':').first
        : trimmed.split(':').first;
    return !RegExp(
      r'^[a-f0-9]{24,}$',
      caseSensitive: false,
    ).hasMatch(localpart);
  }

  (String, String) _splitName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return ('', '');
    return (parts.first, parts.length > 1 ? parts.sublist(1).join(' ') : '');
  }

  String? _field(Map<String, String> fields, String wanted) {
    for (final entry in fields.entries) {
      if (entry.key.toLowerCase() == wanted.toLowerCase()) {
        return entry.value.trim();
      }
    }
    return null;
  }

  String _resolveAvatarUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    if (trimmed.startsWith('/')) return '${ApiService.baseUrl}$trimmed';
    return '${ApiService.baseUrl}/$trimmed';
  }

  String _localProfileImageKey(String uid) =>
      '$_localProfileImagePrefix${_matrixLocalpart(uid)}';

  String _pendingProfileImageKey(String uid) =>
      '$_pendingProfileImagePrefix${_matrixLocalpart(uid)}';

  String _avatarVersionKey(String uid) =>
      '$_avatarVersionPrefix${_matrixLocalpart(uid)}';

  Future<int> _readAvatarVersion(String uid) async {
    final raw = await _storage.read(key: _avatarVersionKey(uid)) ?? '';
    final parsed = int.tryParse(raw) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  Future<void> _writeAvatarVersion(String uid, int version) {
    return _storage.write(
      key: _avatarVersionKey(uid),
      value: (version < 0 ? 0 : version).toString(),
    );
  }

  Future<String> _readLocalProfileImagePath(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_localProfileImageKey(uid))?.trim() ?? '';
    if (path.isEmpty) return '';
    return File(path).existsSync() ? path : '';
  }

  Future<String> _cacheProfileImageFile(String uid, File source) async {
    final supportDir = await getApplicationSupportDirectory();
    final avatarDir = Directory('${supportDir.path}/profile_avatars');
    if (!avatarDir.existsSync()) {
      await avatarDir.create(recursive: true);
    }
    final ext = _imageExtension(source.path);
    final safeUid = _matrixLocalpart(
      uid,
    ).replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destination = File('${avatarDir.path}/$safeUid-$stamp$ext');
    if (source.path == destination.path) return destination.path;
    await source.copy(destination.path);
    unawaited(_deleteOlderLocalAvatarFiles(avatarDir, safeUid, destination));
    return destination.path;
  }

  Future<void> _deleteOlderLocalAvatarFiles(
    Directory avatarDir,
    String safeUid,
    File keep,
  ) async {
    try {
      if (!avatarDir.existsSync()) return;
      await for (final entity in avatarDir.list()) {
        if (entity is! File) continue;
        if (entity.path == keep.path) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('$safeUid-')) continue;
        await entity.delete();
      }
    } catch (e) {
      debugPrint('[UserProfileService] Old local avatar cleanup skipped: $e');
    }
  }

  String _imageExtension(String path) {
    final lower = path.toLowerCase();
    for (final ext in const ['.jpg', '.jpeg', '.png', '.webp']) {
      if (lower.endsWith(ext)) return ext;
    }
    return '.jpg';
  }

  Future<bool> _syncPendingAvatarUploadForUid(String uid) async {
    final lastAttempt = _lastPendingAvatarAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < const Duration(seconds: 30)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final pendingPath = prefs.getString(_pendingProfileImageKey(uid)) ?? '';
    if (pendingPath.trim().isEmpty) return false;
    final file = File(pendingPath);
    if (!file.existsSync()) {
      await prefs.remove(_pendingProfileImageKey(uid));
      return false;
    }
    try {
      _lastPendingAvatarAttemptAt = DateTime.now();
      final uploadedPath = await UserProfileApiService.instance
          .uploadAvatarImage(file);
      final avatarVersion = await UserProfileApiService.instance
          .incrementAvatarVersion();
      final avatarUrl = _withAvatarFetchVersion(
        _resolveAvatarUrl(uploadedPath),
        uid,
        avatarVersion,
      );
      if (avatarUrl.isEmpty) return false;
      await MatrixProfileService.instance.setAvatarImageUrl(uid, avatarUrl);
      await _storage.write(key: _profileImageKey, value: avatarUrl);
      await _writeAvatarVersion(uid, avatarVersion);
      await prefs.remove(_pendingProfileImageKey(uid));
      return true;
    } catch (e) {
      debugPrint(
        '[UserProfileService] Pending avatar upload retry skipped: $e',
      );
      return false;
    }
  }

  UserProfile _profileFromBackendFields(
    String uid,
    Map<String, String> fields, {
    String? fallbackPhone,
  }) {
    final firstName = _field(fields, 'FirstName') ?? '';
    final lastName = _field(fields, 'LastName') ?? '';
    final joinedName = [
      firstName,
      lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
    final displayName =
        _field(fields, 'DisplayName') ??
        _field(fields, 'displayName') ??
        _field(fields, 'Name') ??
        _field(fields, 'name') ??
        _field(fields, 'Username') ??
        joinedName;
    final avatar =
        _field(fields, 'AvatarImg') ??
        _field(fields, 'avatarImg') ??
        _field(fields, 'AvatarUrl') ??
        _field(fields, 'avatarUrl') ??
        _field(fields, 'ProfileImage') ??
        '';
    final backendPhone =
        _field(fields, 'Phone') ?? _field(fields, 'phone') ?? '';
    final channelAlias =
        _field(fields, 'ChannelAlias') ?? _field(fields, 'channelAlias') ?? '';
    final groupAlias =
        _field(fields, 'GroupAlias') ?? _field(fields, 'groupAlias') ?? '';

    return UserProfile(
      uid: uid,
      name: displayName.trim(),
      username: displayName.trim(),
      phone: _trustedPhone(backendPhone, fallbackPhone: fallbackPhone),
      bio: _field(fields, 'Bio') ?? _field(fields, 'bio') ?? '',
      profileImage: _resolveAvatarUrl(avatar),
      avatarVersion: _avatarVersionFromFields(fields),
      channelAlias: channelAlias.trim(),
      groupAlias: groupAlias.trim(),
      links: [
        _field(fields, 'Link'),
        _field(fields, 'link'),
        _field(fields, 'Website'),
        _field(fields, 'website'),
      ].whereType<String>().where((link) => link.trim().isNotEmpty).toList(),
    );
  }

  UserProfile _reuseStablePublicAvatar(String cacheKey, UserProfile fresh) {
    final cached = _publicProfileCache[cacheKey];
    if (cached == null) return fresh;

    final freshAvatar = fresh.profileImage.trim();
    final cachedAvatar = cached.profileImage.trim();
    if (freshAvatar.isEmpty) {
      // An empty avatar from the authoritative profile is a deletion. Never
      // resurrect a previously cached URL here.
      return fresh;
    }

    if (_stripAvatarVersion(freshAvatar) == _stripAvatarVersion(cachedAvatar)) {
      return fresh.copyWith(
        // The backend currently reuses filenames such as `avatar_img.jpg`.
        // Keep the fresh fetch version so CachedNetworkImage cannot serve an
        // older file merely because the base path did not change.
        profileImage: freshAvatar,
        localProfileImagePath: cached.localProfileImagePath.trim().isNotEmpty
            ? cached.localProfileImagePath
            : null,
      );
    }

    return fresh;
  }

  String _stripAvatarVersion(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasQuery) return url;
    final params = Map<String, String>.from(uri.queryParameters)..remove('v');
    return uri
        .replace(queryParameters: params.isEmpty ? null : params)
        .toString();
  }

  String _withAvatarFetchVersion(String url, String userId, int avatarVersion) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.startsWith('mxc://')) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed;
    // A fetch timestamp is not an avatar version. Using it here changed the
    // URL on every profile read, bypassed the image cache, and made the same
    // avatar download again when opening the header/profile. Version zero is
    // deliberately stable for older backend records. A real backend
    // AvatarVersion still changes the URL immediately after an upload.
    final version = avatarVersion.toString();
    final params = Map<String, String>.from(uri.queryParameters)
      ..['v'] =
          '${_matrixLocalpart(userId).toLowerCase()}-'
          '$version';
    return uri.replace(queryParameters: params).toString();
  }

  int _avatarVersionFromFields(Map<String, String> fields) {
    final raw =
        _field(fields, 'AvatarVersion') ??
        _field(fields, 'avatar_version') ??
        '';
    final parsed = int.tryParse(raw) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  UserProfile _fallbackPublicProfile(String uid, {String? phone}) {
    return UserProfile(
      uid: uid,
      name: '',
      username: '',
      phone: _normalizePhone(phone ?? ''),
      bio: '',
      profileImage: '',
      links: const [],
    );
  }

  bool _matchesRequestedPublicProfile(
    Map<String, String> fields, {
    required String uid,
    String? phone,
  }) {
    final targetLocalpart = _matrixLocalpart(uid);
    final idFields = [
      'UserId',
      'userid',
      'userId',
      'Uid',
      'uid',
      'Id',
      'id',
      'MatrixUserId',
      'matrixUserId',
      'maxtrixUserId',
    ];
    for (final key in idFields) {
      final value = _field(fields, key);
      if (value == null || value.isEmpty) continue;
      if (_matrixLocalpart(value) == targetLocalpart) return true;
    }

    final requestedPhone = _normalizePhone(phone ?? '');
    final returnedPhone = _normalizePhone(
      _field(fields, 'Phone') ?? _field(fields, 'phone') ?? '',
    );
    if (requestedPhone.isNotEmpty &&
        returnedPhone.isNotEmpty &&
        requestedPhone == returnedPhone) {
      return true;
    }

    return false;
  }

  Future<Map<String, String>> _readBackendProfileBestEffort() async {
    try {
      return await UserProfileApiService.instance.getProfile();
    } catch (e) {
      debugPrint('[UserProfileService] Backend profile get skipped: $e');
      return const {};
    }
  }

  Future<UserProfile?> _refreshAndNotify({bool forceRefresh = false}) async {
    final fresh = await _readFromStorage(forceRefresh: forceRefresh);
    _profileController.add(fresh);
    return fresh;
  }

  Future<void> _syncPendingAvatarAndRefresh() async {
    try {
      await syncPendingAvatarUpload();
      await _refreshAndNotify(forceRefresh: true);
    } catch (e) {
      debugPrint('[UserProfileService] Warmup avatar refresh skipped: $e');
    }
  }

  Future<Map<String, String>> _readPublicBackendProfileBestEffort(
    String uid, {
    String? phone,
  }) async {
    try {
      return await UserProfileApiService.instance.getPublicProfile(
        userId: uid,
        matrixUserId: uid,
        phone: phone,
      );
    } catch (e) {
      debugPrint('[UserProfileService] Public backend profile get skipped: $e');
      return const {};
    }
  }

  String _publicProfileCacheKey(String uid, String? phone) {
    return '${_matrixLocalpart(uid).toLowerCase()}|${_normalizePhone(phone ?? '')}';
  }

  Future<void> _saveBackendProfileBestEffort(Map<String, String> fields) async {
    try {
      await UserProfileApiService.instance.saveProfileFields(fields);
    } catch (e) {
      debugPrint('[UserProfileService] Backend profile save skipped: $e');
    }
  }
}
