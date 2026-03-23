import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:sensorite/core/utils/utls.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'package:sensorite/data/mode_key.dart';
import 'package:sensorite/presentation/map/marker.dart';
import 'package:sensorite/data/services/fake_service.dart';
import 'package:sensorite/presentation/viewmodels/recording_viewmodel.dart';
import 'package:provider/provider.dart';

class OSMFlutterMap extends StatefulWidget {
  final void Function(loc.LocationData location, SensorData? sensorData)?
  onRealtimeData;

  const OSMFlutterMap({super.key, this.onRealtimeData});

  @override
  State<OSMFlutterMap> createState() => _OSMFlutterMapState();
}

class _OSMFlutterMapState extends State<OSMFlutterMap> {
  final MapController _mapController = MapController();
  final loc.Location _location = loc.Location();

  loc.LocationData? _currentLocation;
  StreamSubscription<loc.LocationData>? _locationSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _interpolationTimer;

  SensorData? _latestAccel;
  SensorData? _latestGyro;
  SensorData? _latestCompleteSensorData;
  bool _hasCentered = false;
  DateTime? _lastGpsUpdateTime;
  double _lastValidGpsHeading =
      0.0; // dernier cap GPS fiable (vitesse suffisante)

  // Traces pour comparaison GPS vs dead-reckoning
  final List<LatLng> _gpsTrack = [];
  final List<LatLng> _drTrack = [];
  static const int _maxTrackPoints = 500;

  // Mode VS : DR tourne en parallèle du GPS sans correction
  bool _vsMode = false;
  loc.LocationData? _drLocation;

  @override
  void initState() {
    super.initState();
    _startSensorFusion();
    _startInterpolationLoop();
    _startRealtimeLocation();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _interpolationTimer?.cancel();
    super.dispose();
  }

  void _startSensorFusion() {
    _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      _latestAccel = SensorData(
        timestamp: DateTime.now(),
        accelX: event.x,
        accelY: event.y,
        accelZ: event.z,
      );
      _tryFuseSensors();
    });

    _gyroSub = gyroscopeEventStream().listen((GyroscopeEvent event) {
      _latestGyro = SensorData(
        timestamp: DateTime.now(),
        gyroX: event.x,
        gyroY: event.y,
        gyroZ: event.z,
      );
      _tryFuseSensors();
    });
  }

  void _tryFuseSensors() {
    if (_latestAccel == null || _latestGyro == null) return;
    _latestCompleteSensorData = SensorData(
      timestamp: DateTime.now(),
      accelX: _latestAccel!.accelX,
      accelY: _latestAccel!.accelY,
      accelZ: _latestAccel!.accelZ,
      gyroX: _latestGyro!.gyroX,
      gyroY: _latestGyro!.gyroY,
      gyroZ: _latestGyro!.gyroZ,
    );

    final location = _currentLocation;
    if (location != null) {
      widget.onRealtimeData?.call(location, _latestCompleteSensorData);
    }
  }

  void _startInterpolationLoop() {
    _interpolationTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) {
      final sensorData = _latestCompleteSensorData;
      if (sensorData == null) return;

      if (_vsMode) {
        // Mode VS : DR tourne librement sans jamais être corrigé par le GPS
        final base = _drLocation ?? _currentLocation;
        if (base == null || base.latitude == null || base.longitude == null)
          return;

        final predicted = interpolPosition(base, sensorData);
        if (!mounted) return;
        _drTrack.add(LatLng(predicted.latitude!, predicted.longitude!));
        if (_drTrack.length > _maxTrackPoints) _drTrack.removeAt(0);
        setState(() => _drLocation = predicted);
      } else {
        // Mode normal : DR uniquement quand le GPS est perdu
        final gpsAge = _lastGpsUpdateTime == null
            ? null
            : DateTime.now().difference(_lastGpsUpdateTime!);
        if (gpsAge != null && gpsAge < const Duration(seconds: 1)) return;

        final currentLocation = _currentLocation;
        if (currentLocation == null ||
            currentLocation.latitude == null ||
            currentLocation.longitude == null)
          return;

        final interpolatedLocation = interpolPosition(
          currentLocation,
          sensorData,
        );
        if (!mounted) return;
        _drTrack.add(
          LatLng(
            interpolatedLocation.latitude!,
            interpolatedLocation.longitude!,
          ),
        );
        if (_drTrack.length > _maxTrackPoints) _drTrack.removeAt(0);
        setState(() => _currentLocation = interpolatedLocation);
        widget.onRealtimeData?.call(interpolatedLocation, sensorData);
      }
    });
  }

  void _toggleVsMode() {
    setState(() {
      _vsMode = !_vsMode;
      if (_vsMode) {
        // Ancrer le DR sur la position GPS actuelle, le cap est déjà bon (GPS le maintient)
        _drTrack.clear();
        _drLocation = _currentLocation;
      } else {
        _drLocation = null;
        _drTrack.clear();
      }
    });
  }

  Future<void> _startRealtimeLocation() async {
    final firstLocation = await getLocationCoordinates();
    if (!mounted) return;

    if (firstLocation != null) {
      syncDeadReckoning(firstLocation);
      setState(() => _currentLocation = firstLocation);
    }

    _locationSub = _location.onLocationChanged.listen((
      loc.LocationData currentLocation,
    ) {
      if (!mounted) return;
      if (currentLocation.latitude == null || currentLocation.longitude == null)
        return;

      _lastGpsUpdateTime = DateTime.now();
      syncDeadReckoning(currentLocation);
      // Ne garder le cap GPS que si la vitesse est suffisante (évite les resets à 0 à l'arrêt)
      final spd = currentLocation.speed ?? 0.0;
      final hdg = currentLocation.heading ?? 0.0;
      if (spd > 0.5 && hdg.isFinite) _lastValidGpsHeading = hdg;
      _gpsTrack.add(
        LatLng(currentLocation.latitude!, currentLocation.longitude!),
      );
      if (_gpsTrack.length > _maxTrackPoints) _gpsTrack.removeAt(0);
      setState(() {
        _currentLocation = currentLocation;
      });
      if (!Sks.isNetworkAvailable) {
        myprint("Offline mode active, interpolation driven by timer.");
      } else {
        myprint(
          "Real Location: ${currentLocation.latitude}, ${currentLocation.longitude}, heading: ${currentLocation.heading}",
        );
      }

      setState(() {
        _currentLocation = currentLocation;
      });
      widget.onRealtimeData?.call(currentLocation, _latestCompleteSensorData);
      myprint(
        "Sensor Data: accel=(${_latestCompleteSensorData?.accelX}, ${_latestCompleteSensorData?.accelY}, ${_latestCompleteSensorData?.accelZ}), gyro=(${_latestCompleteSensorData?.gyroX}, ${_latestCompleteSensorData?.gyroY}, ${_latestCompleteSensorData?.gyroZ})",
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final lat = _currentLocation?.latitude;
    final lng = _currentLocation?.longitude;
    final heading = _lastValidGpsHeading;

    final drLat = _drLocation?.latitude;
    final drLng = _drLocation?.longitude;
    final drHeading = _drLocation?.heading ?? 0.0;

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
            if (_gpsTrack.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _gpsTrack,
                    color: Colors.blue,
                    strokeWidth: 3.0,
                  ),
                ],
              ),
            if (_drTrack.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _drTrack,
                    color: Colors.orange,
                    strokeWidth: 3.0,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (lat != null && lng != null)
                  Marker(
                    point: LatLng(lat, lng),
                    width: 56,
                    height: 56,
                    child: RealtimeUserMarker(heading: heading),
                  ),
                if (_vsMode && drLat != null && drLng != null)
                  Marker(
                    point: LatLng(drLat, drLng),
                    width: 56,
                    height: 56,
                    child: RealtimeUserMarker(
                      heading: drHeading,
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _toggleVsMode,
            backgroundColor: _vsMode ? Colors.orange : Colors.blueGrey,
            icon: Icon(_vsMode ? Icons.pause : Icons.compare_arrows),
            label: Text(_vsMode ? 'VS ON' : 'VS'),
          ),
        ),
      ],
    );
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
