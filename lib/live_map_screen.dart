import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_service.dart';

class LiveMapScreen extends StatefulWidget {
  final NavigationService navService;

  const LiveMapScreen({
    super.key,
    required this.navService,
  });

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  late final MapController _mapController;
  bool _followEstimate = true;
  bool _showStats = true;
  bool _didInitialCenter = false;
  DateTime _lastFollowMove = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    widget.navService.addListener(_onNavUpdate);
  }

  @override
  void dispose() {
    widget.navService.removeListener(_onNavUpdate);
    _mapController.dispose();
    super.dispose();
  }

  void _onNavUpdate() {
    if (!mounted) return;
    if (_followEstimate) _moveToEstimate();
    setState(() {});
  }

  void _moveToEstimate({bool force = false}) {
    final s = widget.navService.state;
    if (s.latitude == 0 && s.longitude == 0) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastFollowMove).inMilliseconds < 350) return;
    _lastFollowMove = now;
    try {
      _mapController.move(LatLng(s.latitude, s.longitude), 17);
    } catch (_) {
      // Map can be briefly unavailable during first frame.
    }
  }

  void _fitAll(List<LatLng> points) {
    if (points.isEmpty) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(44),
        ),
      );
    } catch (_) {
      // Ignore transient map lifecycle errors.
    }
  }

  static double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final mLat = (a.latitude + b.latitude) / 2 * pi / 180;
    return sqrt(pow(dLat * r, 2) + pow(dLon * r * cos(mLat), 2));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.navService.state;
    final gpsPoints = s.gpsTrail.map((p) => LatLng(p.lat, p.lon)).toList();
    final imuPoints = s.trail
        .where((p) => !p.fromGPS)
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    final estimate = (s.latitude != 0 || s.longitude != 0)
        ? LatLng(s.latitude, s.longitude)
        : null;
    final imuLinePoints = [
      ...imuPoints,
      if (estimate != null &&
          (imuPoints.isEmpty || _distMeters(imuPoints.last, estimate) > 0.5))
        estimate,
    ];
    final allPoints = [...gpsPoints, ...imuLinePoints];
    final hasData = allPoints.isNotEmpty;

    if (!_didInitialCenter && hasData) {
      _didInitialCenter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_followEstimate) {
          _moveToEstimate(force: true);
        } else {
          _fitAll(allPoints);
        }
      });
    }

    String driftText = '-';
    if (gpsPoints.isNotEmpty && estimate != null) {
      driftText =
          '${_distMeters(gpsPoints.last, estimate).toStringAsFixed(1)} m';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1220),
        foregroundColor: Colors.white,
        title: const Text(
          'LIVE MAP GPS VS IMU',
          style: TextStyle(
              fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Follow',
            onPressed: () {
              setState(() => _followEstimate = !_followEstimate);
              if (_followEstimate) _moveToEstimate(force: true);
            },
            icon: Icon(
              _followEstimate ? Icons.my_location : Icons.location_searching,
              color: _followEstimate ? const Color(0xFF00E5FF) : Colors.white54,
            ),
          ),
          IconButton(
            tooltip: 'Stats',
            onPressed: () => setState(() => _showStats = !_showStats),
            icon: Icon(
              _showStats ? Icons.info : Icons.info_outline,
              color: _showStats ? const Color(0xFF00E5FF) : Colors.white54,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !hasData
                ? const Center(
                    child: Text(
                      'No GPS/IMU points yet.\nStart a run to see live comparison.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: estimate ??
                          (gpsPoints.isNotEmpty
                              ? gpsPoints.last
                              : const LatLng(48.8566, 2.3522)),
                      initialZoom: 16,
                      onMapEvent: (event) {
                        if (event is MapEventMove &&
                            event.source == MapEventSource.dragStart) {
                          if (_followEstimate) {
                            setState(() => _followEstimate = false);
                          }
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sensoritetest',
                      ),
                      if (gpsPoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: gpsPoints,
                              color: const Color(0xFF00E676),
                              strokeWidth: 3.5,
                            ),
                          ],
                        ),
                      if (imuLinePoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: imuLinePoints,
                              color: const Color(0xFFFF6B35),
                              strokeWidth: 3,
                              pattern: StrokePattern.dashed(
                                segments: const [12, 6],
                              ),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (gpsPoints.isNotEmpty)
                            _marker(gpsPoints.first, Colors.white70, 'A'),
                          if (gpsPoints.isNotEmpty)
                            _marker(
                                gpsPoints.last, const Color(0xFF00E676), 'G'),
                          if (estimate != null)
                            _marker(estimate, const Color(0xFFFF6B35), 'I'),
                        ],
                      ),
                    ],
                  ),
          ),
          if (_showStats && hasData)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0D1220),
                border: Border(top: BorderSide(color: Color(0xFF1A2540))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCell('MODE', s.mode.name.toUpperCase()),
                  _statCell('GPS', '${gpsPoints.length} pts'),
                  _statCell('IMU', '${imuLinePoints.length} pts'),
                  _statCell('NO GPS', '${s.timeSinceGPS.toStringAsFixed(1)} s'),
                  _statCell('DRIFT', driftText, highlight: true),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: hasData
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF141B2D),
              foregroundColor: const Color(0xFF00E5FF),
              onPressed: () => _fitAll(allPoints),
              child: const Icon(Icons.fit_screen),
            )
          : null,
    );
  }

  Marker _marker(LatLng point, Color color, String label) {
    return Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.4),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCell(String label, String value, {bool highlight = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFFFF6B35) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
