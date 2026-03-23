import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensorite/core/utils/utls.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'package:sensorite/data/mode_key.dart';
import 'package:sensorite/presentation/map/marker.dart';
import 'package:sensorite/data/services/fake_service.dart';
import 'package:sensorite/data/services/sensor_service.dart';

class OSMFlutterMap extends StatefulWidget {
  final void Function(loc.LocationData location, SensorData? sensorData)?
  onRealtimeData;

  const OSMFlutterMap({super.key, this.onRealtimeData});

  @override
  State<OSMFlutterMap> createState() => _OSMFlutterMapState();
}

class _OSMFlutterMapState extends State<OSMFlutterMap> with ChangeNotifier {
  final MapController _mapController = MapController();
  final loc.Location _location = loc.Location();
  final SensorService _sensorService = SensorService();
  final NavigateurUniversel _NavigateurUniversel = NavigateurUniversel();

  loc.LocationData? _currentLocation;
  StreamSubscription<loc.LocationData>? _locationSub;
  Timer? _interpolationTimer;
  Timer? _trackingTimer;

  bool _hasCentered = false;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _isOfflineMode = !Sks.isNetworkAvailable;
    initializeSensor();
    _startRealtimeLocation();
    _startTracking();
  }

  Future<void> _startTracking() async {
    _trackingTimer = Timer.periodic(const Duration(milliseconds: 300), (
      _,
    ) async {
      final shouldBeOffline = !Sks.isNetworkAvailable;

      if (shouldBeOffline == _isOfflineMode) return;

      if (!mounted) return;
      setState(() {
        _isOfflineMode = shouldBeOffline;
      });

      if (_isOfflineMode) {
        _locationSub?.cancel();
        _locationSub = null;
        _startInterpolationLoop();
      } else {
        _interpolationTimer?.cancel();
        _interpolationTimer = null;
        _startRealtimeLocation();
      }
    });
  }

  Future<void> _startInterpolationLoop() async {
    if (_interpolationTimer != null) return;

    _interpolationTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) async {
      final currentLocation = _currentLocation;
      final sensorData =
          _sensorService.latestCompleteSensorData; //getFusedSensorData();

      if (currentLocation == null || sensorData == null) return;
      if (currentLocation.latitude == null ||
          currentLocation.longitude == null) {
        return;
      }
      final interpolatedLocation =
          _NavigateurUniversel.calculerNouvellePosition(
            positionActuelle: currentLocation,
            donneesCapteurs: sensorData,
          );
      myprint(
        "Interpolated : ${interpolatedLocation.latitude}, ${interpolatedLocation.longitude}, heading: ${interpolatedLocation.heading}",
      );
      propagatePosition(interpolatedLocation);
    });
  }

  Future<void> _startRealtimeLocation() async {
    if (_locationSub != null) return;

    _locationSub = _location.onLocationChanged.listen((
      loc.LocationData currentLocation,
    ) {
      if (!mounted) return;
      if (_isOfflineMode) return;
      if (currentLocation.latitude == null ||
          currentLocation.longitude == null) {
        return;
      }
      myprint(
        " real: ${currentLocation.latitude}, ${currentLocation.longitude}, ${currentLocation.heading}",
      );
      propagatePosition(currentLocation);
    });
  }

  void propagatePosition(loc.LocationData currentLocation) {
    setState(() {
      _currentLocation = currentLocation;
    });

    widget.onRealtimeData?.call(
      currentLocation,
      _sensorService.latestCompleteSensorData,
    );

    final currentPoint = LatLng(
      currentLocation.latitude!,
      currentLocation.longitude!,
    );

    // Recentre la carte une seule fois au premier fix
    if (!_hasCentered) {
      _mapController.move(currentPoint, 18);
      _hasCentered = true;
    }
  }

  ///=========================Senseurite core logic================================================================

  Future<void> initializeSensor() async {
    _sensorService.startRecording();
    _sensorService.onDataReceived = (SensorData data) {
      myprint(
        "Handling sensor data: accel=(${data.accelX}, ${data.accelY}, ${data.accelZ}), "
        "gyro=(${data.gyroX}, ${data.gyroY}, ${data.gyroZ}), timestamp=${data.timestamp}",
      );
    };
    _sensorService.onStatusChanged = () {
      notifyListeners();
    };
    await _sensorService.initialize();
    await _sensorService.startSensorFusion();
    notifyListeners();
  }

  ///=========================Senseurite core logic================================================================

  @override
  Widget build(BuildContext context) {
    final lat = _currentLocation?.latitude;
    final lng = _currentLocation?.longitude;
    final heading = _currentLocation?.heading ?? 0.0;
    final modeColor = _isOfflineMode
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    final modeLabel = _isOfflineMode ? 'OFFLINE' : 'ONLINE';

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(lat ?? 0.0, lng ?? 0.0),
            initialZoom: 20,
          ),
          children: [
            TileLayer(
              urlTemplate: 'http://82.29.175.22:8080/tile/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sensorite.map.sensorite',
            ),
            if (lat != null && lng != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(lat, lng),
                    width: 20,
                    height: 20,
                    child: RealtimeUserMarker(heading: heading),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(
            child: FilledButton.icon(
              onPressed: null,
              style: FilledButton.styleFrom(
                disabledBackgroundColor: modeColor,
                disabledForegroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimary,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                _isOfflineMode ? Icons.cloud_off : Icons.cloud_done,
                size: 16,
              ),
              label: Text(modeLabel),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _interpolationTimer?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }
}

Future<loc.LocationData?> getLocationCoordinates() async {
  loc.Location location = loc.Location();
  try {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        throw Exception("Location services are disabled.");
      }
    }

    final coordinates = await location.getLocation();
    return coordinates;
  } catch (e) {
    if (e is PlatformException) {
      loc.PermissionStatus permissionGranted = await location.hasPermission();

      if (e.code == "PERMISSION_DENIED_NEVER_ASK") {
        await openAppSettings();
        throw Exception("Permission denied forever. Redirected to settings.");
      } else if (permissionGranted == loc.PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != loc.PermissionStatus.granted) {
          throw Exception("Location permission denied.");
        }
      }
    }

    return null;
  }
}
