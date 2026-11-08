import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wrytte/services/permissions/location_permission_service.dart';
import 'package:http/http.dart' as http;
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/models/chat_models/ui/chat_location_selection.dart';

export 'package:wrytte/models/chat_models/ui/chat_location_selection.dart';

class _NearbyPlace {
  final String id;
  final String name;
  final String detail;
  final String category;
  final LatLng point;
  final double distanceMeters;

  const _NearbyPlace({
    required this.id,
    required this.name,
    required this.detail,
    required this.category,
    required this.point,
    required this.distanceMeters,
  });
}

class ChatLocationPicker extends StatefulWidget {
  final ScrollController scrollController;
  final ValueChanged<ChatLocationSelection>? onLocationSelected;

  const ChatLocationPicker({
    super.key,
    required this.scrollController,
    this.onLocationSelected,
  });

  @override
  State<ChatLocationPicker> createState() => _ChatLocationPickerState();
}

class _ChatLocationPickerState extends State<ChatLocationPicker> {
  static const Color _blue = Color(0xFF4D92FF);
  static const Color _orange = Color(0xFFFF9418);
  static const LatLng _kigaliCenter = LatLng(-1.9441, 30.0619);
  // Palette sampled from the Telegram iOS location picker reference:
  // land #304058, roads #607088, major roads #7888A0, labels #C4CEDC.
  static const String _telegramMapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#304058"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#C4CEDC"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#304058"},{"weight":2}]},
    {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#7888A0"}]},
    {"featureType":"landscape","elementType":"geometry.fill","stylers":[{"color":"#304058"}]},
    {"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#182838"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#384860"}]},
    {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#385848"}]},
    {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#607088"}]},
    {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#405068"}]},
    {"featureType":"road.local","elementType":"geometry.fill","stylers":[{"color":"#506078"}]},
    {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#708098"}]},
    {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#8090B0"}]},
    {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#586880"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#405878"}]}
  ]''';

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  LatLng? _selectedPosition;
  bool _mapReady = false;
  bool _followLiveLocation = true;
  bool _useSatelliteMap = false;
  bool _loading = true;
  bool _serviceDisabled = false;
  bool _permissionDeniedForever = false;
  bool _mockLocationDetected = false;
  String? _errorMessage;
  bool _nearbyLoading = false;
  String? _nearbyError;
  List<_NearbyPlace> _nearbyPlaces = const [];
  int _nearbyRequestId = 0;
  LatLng? _lastNearbyOrigin;

  LatLng get _mapPosition {
    final selected = _selectedPosition;
    if (selected != null) return selected;
    final current = _currentPosition;
    if (current != null) return LatLng(current.latitude, current.longitude);
    return _kigaliCenter;
  }

  bool get _usesCurrentPosition {
    final current = _currentPosition;
    final selected = _selectedPosition;
    if (current == null || selected == null) return current != null;
    final currentPoint = LatLng(current.latitude, current.longitude);
    return Geolocator.distanceBetween(
          currentPoint.latitude,
          currentPoint.longitude,
          selected.latitude,
          selected.longitude,
        ) <
        8;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_locateUser());
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _mapController?.dispose();
    super.dispose();
  }

  LocationSettings _locationSettings({required bool live}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: live ? 5 : 0,
        intervalDuration: live ? const Duration(seconds: 4) : null,
        timeLimit: live ? null : const Duration(seconds: 12),
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: live ? 5 : 0,
      timeLimit: live ? null : const Duration(seconds: 12),
    );
  }

  Future<void> _locateUser() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _serviceDisabled = false;
        _permissionDeniedForever = false;
        _errorMessage = null;
      });
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _serviceDisabled = true;
        });
        return;
      }

      final permission =
          await LocationPermissionService.instance.ensureForegroundGranted();
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _permissionDeniedForever = true;
        });
        return;
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMessage =
              'Location permission is needed to show your position.';
        });
        return;
      }

      Position? cached;
      try {
        cached = await Geolocator.getLastKnownPosition();
      } catch (_) {
        // A cached fix is optional; the fresh high-accuracy request continues.
      }

      final cachedIsRecent =
          cached != null &&
          DateTime.now().difference(cached.timestamp).abs() <
              const Duration(minutes: 5);
      if (cachedIsRecent) {
        _applyPosition(cached, recenter: true);
      }

      Position? fresh;
      try {
        fresh = await Geolocator.getCurrentPosition(
          locationSettings: _locationSettings(live: false),
        );
      } catch (error) {
        debugPrint('Fresh location lookup failed: $error');
      }

      final position = fresh ?? (cachedIsRecent ? cached : null);
      if (position == null) {
        throw StateError('No device location fix is available.');
      }

      _applyPosition(position, recenter: true);
      await _startLiveLocation();
    } catch (error) {
      debugPrint('Chat location lookup failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not get your location. Please try again.';
      });
    }
  }

  void _applyPosition(Position position, {required bool recenter}) {
    if (!mounted) return;
    final target = LatLng(position.latitude, position.longitude);
    final shouldFollow = _followLiveLocation || _selectedPosition == null;
    final previous = _currentPosition;
    final movedSincePrevious =
        previous == null ||
        Geolocator.distanceBetween(
              previous.latitude,
              previous.longitude,
              position.latitude,
              position.longitude,
            ) >
            100;
    final shouldLoadNearby =
        (_nearbyPlaces.isEmpty || movedSincePrevious) && _nearbyError == null;
    setState(() {
      _currentPosition = position;
      _mockLocationDetected = position.isMocked;
      if (shouldFollow) _selectedPosition = target;
      _loading = false;
    });
    if (recenter && shouldFollow) {
      _moveMap(target, 16.5);
    }
    if (shouldLoadNearby) {
      // Start as soon as the first cached or fresh fix is available. Waiting
      // for the fresh lookup caused the first-open list to remain empty.
      unawaited(_fetchNearbyPlaces(target));
    }
  }

  Future<void> _startLiveLocation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _locationSettings(live: true),
    ).listen(
      (position) {
        final previous = _currentPosition;
        _applyPosition(position, recenter: _followLiveLocation);
        final movedFarEnough =
            previous == null ||
            Geolocator.distanceBetween(
                  previous.latitude,
                  previous.longitude,
                  position.latitude,
                  position.longitude,
                ) >
                180;
        if (movedFarEnough) {
          unawaited(
            _fetchNearbyPlaces(
              LatLng(position.latitude, position.longitude),
              silently: true,
            ),
          );
        }
      },
      onError: (Object error) {
        debugPrint('Live location stream failed: $error');
      },
    );
  }

  void _moveMap(LatLng target, double zoom) {
    final controller = _mapController;
    if (!_mapReady || controller == null) return;
    unawaited(
      controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom)),
    );
  }

  Future<void> _centerOnCurrentPosition() async {
    final current = _currentPosition;
    if (current == null) {
      await _locateUser();
      return;
    }
    final target = LatLng(current.latitude, current.longitude);
    setState(() {
      _followLiveLocation = true;
      _selectedPosition = target;
    });
    _moveMap(target, 16.5);
    unawaited(_fetchNearbyPlaces(target));
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _followLiveLocation = false;
      _selectedPosition = point;
    });
    unawaited(HapticFeedback.selectionClick());
    unawaited(_fetchNearbyPlaces(point));
  }

  void _selectNearbyPlace(_NearbyPlace place) {
    setState(() {
      _followLiveLocation = false;
      _selectedPosition = place.point;
    });
    unawaited(HapticFeedback.selectionClick());
    _moveMap(place.point, 17);
  }

  void _selectLocation() {
    final selected = _selectedPosition;
    if (selected == null) return;
    unawaited(HapticFeedback.selectionClick());
    widget.onLocationSelected?.call(
      ChatLocationSelection(
        latitude: selected.latitude,
        longitude: selected.longitude,
        accuracyMeters:
            _usesCurrentPosition ? _currentPosition?.accuracy : null,
        isCurrentPosition: _usesCurrentPosition,
      ),
    );
  }

  Future<void> _fetchNearbyPlaces(
    LatLng origin, {
    bool silently = false,
  }) async {
    final previousOrigin = _lastNearbyOrigin;
    if (silently &&
        previousOrigin != null &&
        Geolocator.distanceBetween(
              previousOrigin.latitude,
              previousOrigin.longitude,
              origin.latitude,
              origin.longitude,
            ) <
            150) {
      return;
    }

    _lastNearbyOrigin = origin;
    final requestId = ++_nearbyRequestId;
    if (mounted && (!silently || _nearbyPlaces.isEmpty)) {
      setState(() {
        _nearbyLoading = true;
        _nearbyError = null;
      });
    }

    final query = '''
[out:json][timeout:20];
(
  nwr(around:2200,${origin.latitude},${origin.longitude})["name"]["amenity"];
  nwr(around:2200,${origin.latitude},${origin.longitude})["name"]["shop"];
  nwr(around:2200,${origin.latitude},${origin.longitude})["name"]["tourism"];
  nwr(around:2200,${origin.latitude},${origin.longitude})["name"]["leisure"];
  nwr(around:2200,${origin.latitude},${origin.longitude})["name"]["historic"];
  nwr(around:2200,${origin.latitude},${origin.longitude})["name"]["place"];
);
out center 60;
''';
    final endpoints = <Uri>[
      Uri.https('overpass-api.de', '/api/interpreter'),
      Uri.https('overpass.kumi.systems', '/api/interpreter'),
      Uri.https('overpass.private.coffee', '/api/interpreter'),
    ];

    Object? lastError;
    List<_NearbyPlace>? places;
    for (final endpoint in endpoints) {
      try {
        final response = await http
            .post(
              endpoint,
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/x-www-form-urlencoded',
                'User-Agent': 'Wrytte/1.0 (location picker)',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode != 200) {
          throw StateError('Place service returned ${response.statusCode}.');
        }
        places = _parseNearbyPlaces(response.body, origin);
        break;
      } catch (error) {
        lastError = error;
        debugPrint('Nearby endpoint failed ($endpoint): $error');
      }
    }

    if (!mounted || requestId != _nearbyRequestId) return;
    if (places == null) {
      debugPrint('Nearby place lookup failed: $lastError');
      setState(() {
        _nearbyLoading = false;
        _nearbyError =
            'Nearby places could not be loaded. Check internet access and tap to retry.';
      });
      return;
    }

    setState(() {
      _nearbyLoading = false;
      _nearbyError = null;
      _nearbyPlaces = places!;
    });
  }

  List<_NearbyPlace> _parseNearbyPlaces(String body, LatLng origin) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final elements = decoded['elements'];
    if (elements is! List) return const [];

    final places = <_NearbyPlace>[];
    final seen = <String>{};
    for (final value in elements) {
      if (value is! Map) continue;
      final element = Map<String, dynamic>.from(value);
      final rawTags = element['tags'];
      if (rawTags is! Map) continue;
      final tags = Map<String, dynamic>.from(rawTags);
      final name = tags['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;

      final center = element['center'];
      final latitude = _asDouble(
        element['lat'] ?? (center is Map ? center['lat'] : null),
      );
      final longitude = _asDouble(
        element['lon'] ?? (center is Map ? center['lon'] : null),
      );
      if (latitude == null || longitude == null) continue;

      final point = LatLng(latitude, longitude);
      final category =
          (tags['amenity'] ??
                  tags['shop'] ??
                  tags['tourism'] ??
                  tags['leisure'] ??
                  'place')
              .toString();
      final uniqueKey =
          '${name.toLowerCase()}:${latitude.toStringAsFixed(5)}:'
          '${longitude.toStringAsFixed(5)}';
      if (!seen.add(uniqueKey)) continue;

      final distance = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        latitude,
        longitude,
      );
      final street = tags['addr:street']?.toString();
      final houseNumber = tags['addr:housenumber']?.toString();
      final address = [
        if (street != null && street.isNotEmpty) street,
        if (houseNumber != null && houseNumber.isNotEmpty) houseNumber,
      ].join(' ');
      final distanceText =
          distance < 1000
              ? '${distance.round()} m away'
              : '${(distance / 1000).toStringAsFixed(1)} km away';

      places.add(
        _NearbyPlace(
          id: '${element['type'] ?? 'place'}-${element['id'] ?? uniqueKey}',
          name: name,
          detail:
              address.isEmpty
                  ? '${_prettyCategory(category)} · $distanceText'
                  : '$address · $distanceText',
          category: category,
          point: point,
          distanceMeters: distance,
        ),
      );
    }

    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places.take(8).toList(growable: false);
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _prettyCategory(String value) {
    final words = value.replaceAll('_', ' ').split(' ');
    return words
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  IconData _placeIcon(String category) {
    if (category.contains('restaurant') || category.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (category.contains('cafe')) return Icons.local_cafe_rounded;
    if (category.contains('hospital') || category.contains('clinic')) {
      return Icons.local_hospital_rounded;
    }
    if (category.contains('school') || category.contains('university')) {
      return Icons.school_rounded;
    }
    if (category.contains('fuel')) return Icons.local_gas_station_rounded;
    if (category.contains('hotel') || category.contains('guest')) {
      return Icons.hotel_rounded;
    }
    if (category.contains('shop') || category.contains('supermarket')) {
      return Icons.storefront_rounded;
    }
    if (category.contains('art') ||
        category.contains('museum') ||
        category.contains('gallery')) {
      return Icons.palette_outlined;
    }
    if (category.contains('bar') || category.contains('pub')) {
      return Icons.local_bar_rounded;
    }
    if (category.contains('park') || category.contains('garden')) {
      return Icons.park_rounded;
    }
    return Icons.place_rounded;
  }

  // Google Maps applies the Telegram-style palette through the native SDK.

  Widget _map() {
    final current = _currentPosition;
    final accuracy = current?.accuracy ?? 0;
    final selected = _selectedPosition;
    final currentPoint =
        current == null ? null : LatLng(current.latitude, current.longitude);
    final circles = <Circle>{};
    if (currentPoint != null && accuracy > 0) {
      circles.add(
        Circle(
          circleId: const CircleId('current-accuracy'),
          center: currentPoint,
          radius: accuracy.clamp(8, 250).toDouble(),
          fillColor: _blue.withValues(alpha: 0.14),
          strokeColor: _blue.withValues(alpha: 0.55),
          strokeWidth: 1,
        ),
      );
    }
    if (currentPoint != null) {
      circles.add(
        Circle(
          circleId: const CircleId('current-dot'),
          center: currentPoint,
          radius: 5,
          fillColor: _blue,
          strokeColor: Colors.white,
          strokeWidth: 2,
        ),
      );
    }

    final markers = <Marker>{};
    if (selected != null && !_usesCurrentPosition) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected-location'),
          position: selected,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _mapPosition,
            zoom: 16.5,
          ),
          mapType: _useSatelliteMap ? MapType.hybrid : MapType.normal,
          style: _useSatelliteMap ? null : _telegramMapStyle,
          myLocationEnabled: currentPoint != null && !_mockLocationDetected,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          trafficEnabled: false,
          buildingsEnabled: true,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          minMaxZoomPreference: const MinMaxZoomPreference(3, 20),
          circles: circles,
          markers: markers,
          onMapCreated: (controller) {
            _mapController = controller;
            _mapReady = true;
            _moveMap(_mapPosition, 16.5);
          },
          onTap: _onMapTap,
          onLongPress: _onMapTap,
        ),
        Positioned(right: 14, bottom: 14, child: _combinedMapControl()),
        if (_loading)
          const Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox.square(
                dimension: 25,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: _blue,
                ),
              ),
            ),
          ),
        if (!_loading &&
            (_serviceDisabled ||
                _permissionDeniedForever ||
                _errorMessage != null))
          ColoredBox(
            color: const Color(0xFF11161D).withValues(alpha: 0.93),
            child: _locationError(),
          ),
      ],
    );
  }

  Widget _combinedMapControl() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Material(
          color: const Color(0x80313F50),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() => _useSatelliteMap = !_useSatelliteMap);
                },
                child: const SizedBox.square(
                  dimension: 46,
                  child: Icon(
                    Icons.map_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              InkWell(
                onTap: _centerOnCurrentPosition,
                child: const SizedBox.square(
                  dimension: 46,
                  child: Icon(
                    Icons.near_me_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationError() {
    final title =
        _serviceDisabled
            ? 'Location is turned off'
            : _permissionDeniedForever
            ? 'Location access is blocked'
            : 'Location unavailable';
    final detail =
        _serviceDisabled
            ? 'Turn on device location to share where you are.'
            : _permissionDeniedForever
            ? 'Allow location access from the app settings.'
            : (_errorMessage ?? 'Please try again.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 54, 28, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off_rounded,
              color: WrytteColors.textSecondary,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WrytteColors.textPrimary,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WrytteColors.textMuted,
                fontFamily: WrytteTypography.primaryFontFamily,
                fontSize: 14,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 13),
            TextButton(
              onPressed:
                  _permissionDeniedForever
                      ? Geolocator.openAppSettings
                      : _serviceDisabled
                      ? Geolocator.openLocationSettings
                      : _locateUser,
              style: TextButton.styleFrom(foregroundColor: _blue),
              child: Text(
                _permissionDeniedForever
                    ? 'Open app settings'
                    : _serviceDisabled
                    ? 'Open location settings'
                    : 'Try again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationDetails() {
    final layout = WrytteAttachmentMetrics.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final position = _currentPosition;
    final selected = _selectedPosition;
    final ready = selected != null && !_loading;
    final accuracy = position?.accuracy.round();
    final accuracyText =
        _usesCurrentPosition && accuracy != null
            ? 'Accurate to ${accuracy.clamp(1, 999)} meters'
            : 'Pinned location';

    return ColoredBox(
      color: const Color(0xFF07090C),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.bodyHorizontalPadding,
          8 * layout.scale,
          layout.bodyHorizontalPadding,
          layout.bottomNavHeight + 56 + bottomInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: ready ? _selectLocation : null,
                borderRadius: BorderRadius.circular(18),
                splashColor: _blue.withValues(alpha: 0.10),
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40 + (2 * layout.progress),
                        height: 40 + (2 * layout.progress),
                        decoration: const BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          color: Colors.white,
                          size: 23 * layout.scale,
                        ),
                      ),
                      SizedBox(width: 13 * layout.scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _usesCurrentPosition
                                  ? 'Send My Current Location'
                                  : 'Send Selected Location',
                              style: TextStyle(
                                color: WrytteColors.textPrimary,
                                fontFamily: WrytteTypography.primaryFontFamily,
                                fontSize: 16 + layout.progress,
                                height: 1.12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ready ? accuracyText : 'Finding your location…',
                              style: const TextStyle(
                                color: WrytteColors.textMuted,
                                fontFamily: WrytteTypography.primaryFontFamily,
                                fontSize: 13.5,
                                height: 1.1,
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
            const SizedBox(height: 6),
            if (_mockLocationDetected) ...[
              _mockLocationWarning(),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'OR CHOOSE A PLACE',
                    style: TextStyle(
                      color: Color(0xFF858990),
                      fontFamily: WrytteTypography.primaryFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.25,
                    ),
                  ),
                ),
                if (_nearbyLoading)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: _blue,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_nearbyError != null)
              _nearbyErrorTile()
            else if (_nearbyLoading && _nearbyPlaces.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.travel_explore_rounded,
                      color: Color(0xFF9DA2AA),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Finding places around this location…',
                      style: TextStyle(
                        color: Color(0xFF9DA2AA),
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              )
            else if (!_nearbyLoading && _nearbyPlaces.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  'Tap anywhere on the map to find places around that point.',
                  style: TextStyle(
                    color: Color(0xFF92969D),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 13.5,
                  ),
                ),
              )
            else
              ..._nearbyPlaces.map(_nearbyPlaceTile),
          ],
        ),
      ),
    );
  }

  Widget _mockLocationWarning() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WrytteColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WrytteColors.warning.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.developer_mode_rounded,
              color: WrytteColors.warning,
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Android reports that this GPS fix is simulated. Live updates '
                'still work, but the emulator controls the displayed position.',
                style: const TextStyle(
                  color: Color(0xFFE2C89E),
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nearbyErrorTile() {
    final layout = WrytteAttachmentMetrics.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(_fetchNearbyPlaces(_mapPosition)),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38 + (2 * layout.progress),
                height: 38 + (2 * layout.progress),
                decoration: const BoxDecoration(
                  color: Color(0xFF24282E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFD6D8DB),
                  size: 21,
                ),
              ),
              SizedBox(width: 12 * layout.scale),
              Expanded(
                child: Text(
                  _nearbyError!,
                  style: const TextStyle(
                    color: Color(0xFFB6BAC0),
                    fontFamily: WrytteTypography.primaryFontFamily,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nearbyPlaceTile(_NearbyPlace place) {
    final layout = WrytteAttachmentMetrics.of(context);
    final selected =
        _selectedPosition != null &&
        Geolocator.distanceBetween(
              _selectedPosition!.latitude,
              _selectedPosition!.longitude,
              place.point.latitude,
              place.point.longitude,
            ) <
            4;
    return Material(
      key: ValueKey<String>(place.id),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectNearbyPlace(place),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 40 + (2 * layout.progress),
                height: 40 + (2 * layout.progress),
                decoration: BoxDecoration(
                  color: selected ? _blue : _orange,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _placeIcon(place.category),
                  color: Colors.white,
                  size: 21 * layout.scale,
                ),
              ),
              SizedBox(width: 13 * layout.scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WrytteColors.textPrimary,
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      place.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8F939A),
                        fontFamily: WrytteTypography.primaryFontFamily,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = WrytteAttachmentMetrics.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.20,
      child: CustomScrollView(
        key: const ValueKey<String>('location-page'),
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: layout.mapHeight(MediaQuery.sizeOf(context).height),
              child: _map(),
            ),
          ),
          SliverToBoxAdapter(child: _locationDetails()),
        ],
      ),
    );
  }
}
