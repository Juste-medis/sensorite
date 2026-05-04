import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_service.dart';

class TraceScreen extends StatefulWidget {
  final List<PositionRecord> trail;
  final List<PositionRecord> gpsTrail;

  const TraceScreen({
    super.key,
    required this.trail,
    required this.gpsTrail,
  });

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  late final MapController _mapController;
  bool _showStats = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<LatLng> get _gpsPoints =>
      widget.gpsTrail.map((p) => LatLng(p.lat, p.lon)).toList();

  List<LatLng> get _imuPoints => widget.trail
      .where((p) => !p.fromGPS)
      .map((p) => LatLng(p.lat, p.lon))
      .toList();

  LatLng? get _center {
    final all = [...widget.gpsTrail, ...widget.trail.where((p) => !p.fromGPS)];
    if (all.isEmpty) return null;
    final lat = all.map((p) => p.lat).reduce((a, b) => a + b) / all.length;
    final lon = all.map((p) => p.lon).reduce((a, b) => a + b) / all.length;
    return LatLng(lat, lon);
  }

  Map<String, String> get _stats {
    final imu = _imuPoints;
    final gps = _gpsPoints;

    double imuDist = 0;
    for (int i = 1; i < imu.length; i++) {
      imuDist += _distMeters(imu[i - 1], imu[i]);
    }

    double gpsDist = 0;
    for (int i = 1; i < gps.length; i++) {
      gpsDist += _distMeters(gps[i - 1], gps[i]);
    }

    String driftStr = '-';
    if (gps.isNotEmpty && imu.isNotEmpty) {
      // Find closest GPS point in time to last IMU point
      final lastImuTime = widget.trail.lastWhere((p) => !p.fromGPS).timestamp;
      PositionRecord closest = widget.gpsTrail.first;
      for (final g in widget.gpsTrail) {
        if (g.timestamp.difference(lastImuTime).abs() <
            closest.timestamp.difference(lastImuTime).abs()) {
          closest = g;
        }
      }
      final drift = _distMeters(imu.last, LatLng(closest.lat, closest.lon));
      driftStr = '${drift.toStringAsFixed(1)} m';
    }

    String fmtDist(double d) =>
        d >= 1000 ? '${(d / 1000).toStringAsFixed(2)} km' : '${d.toStringAsFixed(0)} m';

    return {
      'GPS': '${gps.length} pts',
      'IMU': '${imu.length} pts',
      'DIST. GPS': fmtDist(gpsDist),
      'DIST. IMU': fmtDist(imuDist),
      'ÉCART': driftStr,
    };
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
    final center = _center;
    final gpsPoints = _gpsPoints;
    final imuPoints = _imuPoints;
    final hasData = gpsPoints.isNotEmpty || imuPoints.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1220),
        foregroundColor: Colors.white,
        title: const Text(
          'TRACÉ DE SESSION',
          style: TextStyle(fontSize: 15, letterSpacing: 3, fontWeight: FontWeight.w600),
        ),
        actions: [
          // Legend
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                _legendDot(const Color(0xFF00E676), 'GPS'),
                const SizedBox(width: 10),
                _legendDot(const Color(0xFFFF6B35), 'IMU'),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _showStats ? Icons.info : Icons.info_outline,
                    color: _showStats ? const Color(0xFF00E5FF) : Colors.white38,
                  ),
                  onPressed: () => setState(() => _showStats = !_showStats),
                ),
              ],
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
                      'Aucune donnée enregistrée.\nLancer une session et activer le mode VS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center ?? const LatLng(48.8566, 2.3522),
                      initialZoom: 16,
                    ),
                    children: [
                      // OpenStreetMap tiles (free, no API key)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sensoritetest',
                      ),
                      // GPS track (green)
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
                      // IMU track (orange)
                      if (imuPoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: imuPoints,
                              color: const Color(0xFFFF6B35),
                              strokeWidth: 3.0,
                              pattern: StrokePattern.dashed(
                                segments: const [12, 6],
                              ),
                            ),
                          ],
                        ),
                      // Markers: start GPS, end GPS, end IMU
                      MarkerLayer(
                        markers: [
                          if (gpsPoints.isNotEmpty)
                            _marker(gpsPoints.first, const Color(0xFF00E676), 'D'),
                          if (gpsPoints.isNotEmpty)
                            _marker(gpsPoints.last, Colors.white70, 'A'),
                          if (imuPoints.isNotEmpty)
                            _marker(imuPoints.last, const Color(0xFFFF6B35), '?'),
                        ],
                      ),
                    ],
                  ),
          ),
          if (_showStats && hasData) _buildStatsPanel(),
        ],
      ),
      floatingActionButton: hasData
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF141B2D),
              foregroundColor: const Color(0xFF00E5FF),
              onPressed: () {
                final all = [...gpsPoints, ...imuPoints];
                if (all.isEmpty) return;
                final bounds = LatLngBounds.fromPoints(all);
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                );
              },
              child: const Icon(Icons.fit_screen),
            )
          : null,
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, letterSpacing: 1)),
      ],
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
          border: Border.all(color: Colors.white, width: 1.5),
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

  Widget _buildStatsPanel() {
    final stats = _stats;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1220),
        border: Border(top: BorderSide(color: Color(0xFF1A2540))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stats.entries
            .map((e) => _statCell(e.key, e.value))
            .toList(),
      ),
    );
  }

  Widget _statCell(String label, String value) {
    final isEcart = label == 'ÉCART';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: isEcart ? const Color(0xFFFF6B35) : Colors.white,
            fontSize: 14,
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
