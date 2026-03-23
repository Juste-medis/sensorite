import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VsDataPoint {
  final DateTime timestamp;
  final double gpsLat, gpsLng;
  final double pdrLat, pdrLng;
  final double diLat, diLng;

  const VsDataPoint({
    required this.timestamp,
    required this.gpsLat,
    required this.gpsLng,
    required this.pdrLat,
    required this.pdrLng,
    required this.diLat,
    required this.diLng,
  });
}

class VsComparisonStorage {
  final List<VsDataPoint> _points = [];

  void record({
    required double gpsLat,
    required double gpsLng,
    required double pdrLat,
    required double pdrLng,
    required double diLat,
    required double diLng,
  }) {
    _points.add(VsDataPoint(
      timestamp: DateTime.now(),
      gpsLat: gpsLat,
      gpsLng: gpsLng,
      pdrLat: pdrLat,
      pdrLng: pdrLng,
      diLat: diLat,
      diLng: diLng,
    ));
  }

  int get length => _points.length;

  void clear() => _points.clear();

  /// Sauvegarde en CSV et retourne le chemin du fichier.
  Future<String> saveToFile() async {
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();

    final name =
        'vs_comparison_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$name');

    final buf = StringBuffer();
    buf.writeln('timestamp,gps_lat,gps_lng,pdr_lat,pdr_lng,di_lat,di_lng');
    for (final p in _points) {
      buf.writeln(
        '${p.timestamp.toIso8601String()},'
        '${p.gpsLat},${p.gpsLng},'
        '${p.pdrLat},${p.pdrLng},'
        '${p.diLat},${p.diLng}',
      );
    }

    await file.writeAsString(buf.toString());
    return file.path;
  }
}
