import 'dart:io';
import 'package:path_provider/path_provider.dart';

class RawDataRecord {
  final int timestampMs;
  final double axRaw, ayRaw, azRaw;
  final double gxRaw, gyRaw, gzRaw;
  final double estLat, estLon;
  final double estVx, estVy;
  final double speed, heading;
  final double confidence, uncertainty;
  final double? gpsLat, gpsLon, gpsSpeed, gpsAccuracy;
  final String mode;
  final bool isStationary;

  RawDataRecord({
    required this.timestampMs,
    required this.axRaw,
    required this.ayRaw,
    required this.azRaw,
    required this.gxRaw,
    required this.gyRaw,
    required this.gzRaw,
    required this.estLat,
    required this.estLon,
    required this.estVx,
    required this.estVy,
    required this.speed,
    required this.heading,
    required this.confidence,
    required this.uncertainty,
    this.gpsLat,
    this.gpsLon,
    this.gpsSpeed,
    this.gpsAccuracy,
    required this.mode,
    required this.isStationary,
  });

  String toCsvRow() {
    return [
      timestampMs,
      axRaw.toStringAsFixed(6),
      ayRaw.toStringAsFixed(6),
      azRaw.toStringAsFixed(6),
      gxRaw.toStringAsFixed(6),
      gyRaw.toStringAsFixed(6),
      gzRaw.toStringAsFixed(6),
      estLat.toStringAsFixed(8),
      estLon.toStringAsFixed(8),
      estVx.toStringAsFixed(5),
      estVy.toStringAsFixed(5),
      speed.toStringAsFixed(4),
      heading.toStringAsFixed(2),
      confidence.toStringAsFixed(4),
      uncertainty.toStringAsFixed(4),
      gpsLat?.toStringAsFixed(8) ?? '',
      gpsLon?.toStringAsFixed(8) ?? '',
      gpsSpeed?.toStringAsFixed(4) ?? '',
      gpsAccuracy?.toStringAsFixed(2) ?? '',
      mode,
      isStationary ? '1' : '0',
    ].join(',');
  }
}

class DataRecorder {
  static const String _csvHeader =
      'timestamp_ms,'
      'ax_raw,ay_raw,az_raw,'
      'gx_raw,gy_raw,gz_raw,'
      'est_lat,est_lon,'
      'est_vx,est_vy,'
      'est_speed,est_heading,'
      'confidence,uncertainty,'
      'gps_lat,gps_lon,gps_speed,gps_accuracy,'
      'mode,is_stationary';

  final List<RawDataRecord> _records = [];
  bool _isRecording = false;
  DateTime? _sessionStart;

  void startRecording() {
    _records.clear();
    _isRecording = true;
    _sessionStart = DateTime.now();
  }

  void stopRecording() {
    _isRecording = false;
  }

  void addRecord(RawDataRecord record) {
    if (!_isRecording) return;
    _records.add(record);
  }

  int get recordCount => _records.length;
  bool get isRecording => _isRecording;
  Duration get sessionDuration =>
      _sessionStart != null ? DateTime.now().difference(_sessionStart!) : Duration.zero;

  Future<Directory> getExportDirectory() async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    return dir;
  }

  Future<String?> exportCSV({String sessionTag = ''}) async {
    if (_records.isEmpty) return null;

    try {
      final dir = await getExportDirectory();

      final now = DateTime.now();
      final tag = sessionTag.isNotEmpty ? '_$sessionTag' : '';
      final filename =
          'imu_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}$tag.csv';
      final file = File('${dir.path}/$filename');

      final buffer = StringBuffer();
      buffer.writeln(_csvHeader);
      for (final record in _records) {
        buffer.writeln(record.toCsvRow());
      }

      await file.writeAsString(buffer.toString());
      return file.path;
    } catch (e) {
      return null;
    }
  }

  void clear() {
    _records.clear();
    _sessionStart = null;
  }
}
