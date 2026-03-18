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
  final SensorService _sensorService = SensorService();

  loc.LocationData? _currentLocation;
  StreamSubscription<loc.LocationData>? _locationSub;
  StreamSubscription<SensorData>? _sensorSub;
  Timer? _interpolationTimer;

  SensorData? _latestAccel;
  SensorData? _latestGyro;
  SensorData? _latestCompleteSensorData;
  bool _hasCentered = false;

  @override
  void initState() {
    super.initState();
    _startSensorFusion();
    _startInterpolationLoop();
    _initializeViewModel();
    _startRealtimeLocation();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _sensorSub?.cancel();
    _interpolationTimer?.cancel();
    super.dispose();
  }

  void _startSensorFusion() {
    _sensorSub = _sensorService.sensorDataStream.listen((SensorData data) {
      final hasAccel =
          data.accelX != null && data.accelY != null && data.accelZ != null;
      final hasGyro =
          data.gyroX != null && data.gyroY != null && data.gyroZ != null;

      if (hasAccel) {
        _latestAccel = data;
      }

      if (hasGyro) {
        _latestGyro = data;
      }

      if (_latestAccel != null && _latestGyro != null) {
        _latestCompleteSensorData = SensorData(
          timestamp: data.timestamp,
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
    });
  }

  void _startInterpolationLoop() {
    _interpolationTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) {
      if (Sks.isNetworkAvailable) return;

      final currentLocation = _currentLocation;
      final sensorData = _latestCompleteSensorData;

      if (currentLocation == null || sensorData == null) return;
      if (currentLocation.latitude == null ||
          currentLocation.longitude == null) {
        return;
      }

      final interpolatedLocation = interpolPosition(
        currentLocation,
        sensorData,
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = interpolatedLocation;
      });
      widget.onRealtimeData?.call(interpolatedLocation, sensorData);
    });
  }

  Future<void> _initializeViewModel() async {
    final viewModel = Provider.of<RecordingViewModel>(context, listen: false);
    await viewModel.initialize();

    final customName = "recording_${DateTime.now().millisecondsSinceEpoch}";
    await viewModel.startRecording(customName: customName);
  }

  Future<void> _startRealtimeLocation() async {
    final firstLocation = await getLocationCoordinates();
    if (!mounted) return;

    if (firstLocation != null) {
      setState(() => _currentLocation = firstLocation);
    }

    _locationSub = _location.onLocationChanged.listen((
      loc.LocationData currentLocation,
    ) {
      if (!mounted) return;
      if (currentLocation.latitude == null || currentLocation.longitude == null)
        return;

      setState(() {
        _currentLocation = currentLocation;
      });
      if (!Sks.isNetworkAvailable) {
        currentLocation = interpolPosition(
          currentLocation,
          _latestCompleteSensorData ??
              SensorData(
                timestamp: DateTime.now(),
                accelX: 0,
                accelY: 0,
                accelZ: 0,
                gyroX: 0,
                gyroY: 0,
                gyroZ: 0,
              ),
        );
        myprint(
          "Interpolated Location: ${currentLocation.latitude}, ${currentLocation.longitude}, heading: ${currentLocation.heading}",
        );
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
    final heading = _currentLocation?.heading ?? 0.0;

    return FlutterMap(
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
