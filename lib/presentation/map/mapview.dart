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
import 'package:sensorite/presentation/map/marker.dart';
import 'package:sensorite/data/services/fake_service.dart';
import 'package:sensorite/data/services/vs_comparison_storage.dart';
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
  double _lastValidGpsHeading = 0.0;
  bool _isDrMode = false;

  // Instance DR unique
  final _dr = DeadReckoning();

  // Tracés
  static const int _maxTrackPoints = 500;
  final List<LatLng> _gpsTrack = [];
  final List<LatLng> _drTrack  = []; // violet, actif en GPS perdu ET en VS

  // Mode VS
  bool _vsMode = false;
  loc.LocationData? _drVsLocation; // position DR indépendante en VS
  final VsComparisonStorage _storage = VsComparisonStorage();

  @override
  void initState() {
    super.initState();
    _startSensorFusion();
    _startDrLoop();
    _initializeViewModel();
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
    _accelSub = accelerometerEventStream().listen((e) {
      _latestAccel = SensorData(
        timestamp: DateTime.now(),
        accelX: e.x, accelY: e.y, accelZ: e.z,
      );
      _tryFuse();
    });
    _gyroSub = gyroscopeEventStream().listen((e) {
      _latestGyro = SensorData(
        timestamp: DateTime.now(),
        gyroX: e.x, gyroY: e.y, gyroZ: e.z,
      );
      _tryFuse();
    });
  }

  void _tryFuse() {
    if (_latestAccel == null || _latestGyro == null) return;
    _latestCompleteSensorData = SensorData(
      timestamp: DateTime.now(),
      accelX: _latestAccel!.accelX, accelY: _latestAccel!.accelY, accelZ: _latestAccel!.accelZ,
      gyroX:  _latestGyro!.gyroX,  gyroY:  _latestGyro!.gyroY,  gyroZ:  _latestGyro!.gyroZ,
    );
    final l = _currentLocation;
    if (l != null) widget.onRealtimeData?.call(l, _latestCompleteSensorData);
  }

  void _startDrLoop() {
    _interpolationTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final sensors = _latestCompleteSensorData;
      if (sensors == null) return;

      final gpsAge  = _lastGpsUpdateTime == null
          ? null
          : DateTime.now().difference(_lastGpsUpdateTime!);
      final gpsLost = gpsAge == null || gpsAge > const Duration(seconds: 5);

      if (_vsMode) {
        // VS : DR tourne indépendamment du GPS (position séparée)
        final base = _drVsLocation ?? _currentLocation;
        if (base?.latitude == null || base?.longitude == null) return;
        final predicted = _dr.predict(base!, sensors);
        if (!mounted) return;
        _drTrack.add(LatLng(predicted.latitude!, predicted.longitude!));
        if (_drTrack.length > _maxTrackPoints) _drTrack.removeAt(0);
        setState(() => _drVsLocation = predicted);

        // Enregistrement comparaison
        final gps = _currentLocation;
        if (gps?.latitude != null) {
          _storage.record(
            gpsLat: gps!.latitude!, gpsLng: gps.longitude!,
            pdrLat: predicted.latitude!, pdrLng: predicted.longitude!,
            diLat: predicted.latitude!,  diLng: predicted.longitude!,
          );
        }
      } else if (gpsLost) {
        // GPS perdu : DR remplace le GPS (même marqueur)
        final cur = _currentLocation;
        if (cur?.latitude == null || cur?.longitude == null) return;
        final predicted = _dr.predict(cur!, sensors);
        if (!mounted) return;
        _drTrack.add(LatLng(predicted.latitude!, predicted.longitude!));
        if (_drTrack.length > _maxTrackPoints) _drTrack.removeAt(0);
        setState(() {
          _currentLocation = predicted;
          _isDrMode = true;
        });
        widget.onRealtimeData?.call(predicted, sensors);
      }
    });
  }

  void _toggleVsMode() async {
    if (_vsMode) {
      final count = _storage.length;
      String? path;
      if (count > 0) {
        try { path = await _storage.saveToFile(); } catch (_) {}
        _storage.clear();
      }
      setState(() {
        _vsMode = false;
        _drVsLocation = null;
        _drTrack.clear();
      });
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count points → $path'),
          duration: const Duration(seconds: 6),
        ));
      }
    } else {
      _dr.reset();
      if (_currentLocation != null) _dr.sync(_currentLocation!);
      setState(() {
        _vsMode = true;
        _drTrack.clear();
        _drVsLocation = _currentLocation;
      });
    }
  }

  Future<void> _initializeViewModel() async {
    final vm = Provider.of<RecordingViewModel>(context, listen: false);
    await vm.initialize();
    await vm.startRecording(customName: 'recording_${DateTime.now().millisecondsSinceEpoch}');
  }

  Future<void> _startRealtimeLocation() async {
    final first = await getLocationCoordinates();
    if (!mounted) return;
    if (first != null) {
      _dr.sync(first);
      setState(() => _currentLocation = first);
    }

    _locationSub = _location.onLocationChanged.listen((cur) {
      if (!mounted) return;
      if (cur.latitude == null || cur.longitude == null) return;

      _lastGpsUpdateTime = DateTime.now();

      // En VS : correction cap seulement (vitesse libre)
      // Hors VS : sync complet pour être prêt si GPS se perd
      if (_vsMode) {
        _dr.syncHeadingOnly(cur);
      } else {
        _dr.sync(cur);
      }

      final spd = cur.speed ?? 0.0;
      final hdg = cur.heading ?? 0.0;
      if (spd > 0.5 && hdg.isFinite) _lastValidGpsHeading = hdg;

      _gpsTrack.add(LatLng(cur.latitude!, cur.longitude!));
      if (_gpsTrack.length > _maxTrackPoints) _gpsTrack.removeAt(0);

      setState(() {
        _currentLocation = cur;
        _isDrMode = false;
      });
      widget.onRealtimeData?.call(cur, _latestCompleteSensorData);
      myprint('GPS: ${cur.latitude?.toStringAsFixed(6)}, spd=${cur.speed?.toStringAsFixed(1)} m/s');

      if (!_hasCentered) {
        _mapController.move(LatLng(cur.latitude!, cur.longitude!), 18);
        _hasCentered = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lat = _currentLocation?.latitude;
    final lng = _currentLocation?.longitude;
    final drLat = _drVsLocation?.latitude;
    final drLng = _drVsLocation?.longitude;
    final drHdg = _drVsLocation?.heading ?? 0.0;

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
              PolylineLayer(polylines: [
                Polyline(points: _gpsTrack, color: Colors.blue, strokeWidth: 3),
              ]),
            if (_drTrack.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: _drTrack, color: Colors.purple, strokeWidth: 3),
              ]),
            MarkerLayer(markers: [
              // Marqueur principal (GPS ou DR quand perdu)
              if (lat != null && lng != null)
                Marker(
                  point: LatLng(lat, lng),
                  width: 56, height: 56,
                  child: RealtimeUserMarker(
                    heading: _isDrMode
                        ? (_currentLocation?.heading ?? _lastValidGpsHeading)
                        : _lastValidGpsHeading,
                    color: _isDrMode ? Colors.purple : const Color(0xFF007AFF),
                  ),
                ),
              // Marqueur DR indépendant (VS uniquement)
              if (_vsMode && drLat != null && drLng != null)
                Marker(
                  point: LatLng(drLat, drLng),
                  width: 56, height: 56,
                  child: RealtimeUserMarker(heading: drHdg, color: Colors.purple),
                ),
            ]),
          ],
        ),

        // Bandeau GPS perdu
        if (_isDrMode && !_vsMode)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Material(
              color: Colors.purple.shade700,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gps_off, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text('PRÉDICTION — GPS perdu',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),

        // Légende VS
        if (_vsMode)
          Positioned(
            top: 12, left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LegendItem(color: Colors.blue,   label: 'GPS (réel)'),
                  SizedBox(height: 4),
                  _LegendItem(color: Colors.purple, label: 'DR (prédiction)'),
                ],
              ),
            ),
          ),

        Positioned(
          bottom: 24, right: 16,
          child: FloatingActionButton.extended(
            onPressed: _toggleVsMode,
            backgroundColor: _vsMode ? Colors.purple : Colors.blueGrey,
            icon: Icon(_vsMode ? Icons.stop : Icons.compare_arrows),
            label: Text(_vsMode ? 'VS (${_storage.length}pts)' : 'VS'),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 16, height: 4, color: color),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ],
  );
}

Future<loc.LocationData?> getLocationCoordinates() async {
  final location = loc.Location();
  try {
    bool ok = await location.serviceEnabled();
    if (!ok) {
      ok = await location.requestService();
      if (!ok) throw Exception('Location services disabled.');
    }
    return await location.getLocation();
  } catch (e) {
    if (e is PlatformException) {
      final perm = await location.hasPermission();
      if (e.code == 'PERMISSION_DENIED_NEVER_ASK') {
        await openAppSettings();
      } else if (perm == loc.PermissionStatus.denied) {
        final granted = await location.requestPermission();
        if (granted != loc.PermissionStatus.granted) return null;
      }
    }
    return null;
  }
}
