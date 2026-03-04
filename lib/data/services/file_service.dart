import 'dart:io';
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/sensor_data.dart';
import '../../core/utils/timestamp_helper.dart';

class FileService {
  // Singleton
  static final FileService _instance = FileService._internal();
  factory FileService() => _instance;
  FileService._internal();

  static const String _recordsDirectory = 'imu_records';
  Directory? _baseDirectory;

  /// Initialise le répertoire de base
  Future<void> initialize() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    _baseDirectory = Directory('${appDocDir.path}/$_recordsDirectory');

    if (!await _baseDirectory!.exists()) {
      await _baseDirectory!.create(recursive: true);
    }
  }

  /// Crée un nouveau fichier d'enregistrement
  Future<File> createRecordFile({String? customName}) async {
    if (_baseDirectory == null) await initialize();

    final fileName =
        customName ?? 'record_${TimestampHelper.formattedForFilename()}.csv';
    final filePath = '${_baseDirectory!.path}/$fileName';

    final file = File(filePath);

    // Écrire l'en-tête CSV
    await file.writeAsString(
      'timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z\n',
    );

    return file;
  }

  /// Ajoute une ligne de données au fichier
  Future<void> appendData(File file, SensorData data) async {
    final csvLine = _sensorDataToCsvLine(data);
    await file.writeAsString('$csvLine\n', mode: FileMode.append);
  }

  /// Ajoute plusieurs lignes (optimisé)
  Future<void> appendBatch(File file, List<SensorData> batch) async {
    if (batch.isEmpty) return;

    final csvLines = batch.map(_sensorDataToCsvLine).join('\n');
    await file.writeAsString('$csvLines\n', mode: FileMode.append);
  }

  String _sensorDataToCsvLine(SensorData data) {
    final List<String> fields = [
      data.timestamp.millisecondsSinceEpoch.toString(),
      data.accelX?.toStringAsFixed(6) ?? '',
      data.accelY?.toStringAsFixed(6) ?? '',
      data.accelZ?.toStringAsFixed(6) ?? '',
      data.gyroX?.toStringAsFixed(6) ?? '',
      data.gyroY?.toStringAsFixed(6) ?? '',
      data.gyroZ?.toStringAsFixed(6) ?? '',
    ];

    return fields.join(',');
  }

  /// Liste tous les enregistrements disponibles
  Future<List<File>> listRecordings() async {
    if (_baseDirectory == null) await initialize();

    final List<FileSystemEntity> entities = _baseDirectory!.listSync();
    return entities
        .whereType<File>()
        .where((file) => file.path.endsWith('.csv'))
        .toList();
  }

  /// Lit un fichier CSV et retourne les données
  Future<List<SensorData>> readRecordFile(File file) async {
    final content = await file.readAsString();
    final List<List<dynamic>> rows = const CsvToListConverter().convert(
      content,
    );

    // Ignorer l'en-tête (première ligne)
    return rows.skip(1).map((row) {
      return SensorData(
        timestamp: DateTime.fromMillisecondsSinceEpoch(row[0] as int),
        accelX: row[1] == '' ? null : (row[1] as double),
        accelY: row[2] == '' ? null : (row[2] as double),
        accelZ: row[3] == '' ? null : (row[3] as double),
        gyroX: row[4] == '' ? null : (row[4] as double),
        gyroY: row[5] == '' ? null : (row[5] as double),
        gyroZ: row[6] == '' ? null : (row[6] as double),
      );
    }).toList();
  }

  /// Supprime un fichier
  Future<void> deleteRecord(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Obtient les métadonnées d'un fichier
  Future<Map<String, dynamic>> getFileMetadata(File file) async {
    final stat = await file.stat();
    final data = await readRecordFile(file);

    return {
      'name': file.path.split('/').last,
      'size': stat.size,
      'modified': stat.modified,
      'samples': data.length,
      'duration': data.isNotEmpty
          ? data.last.timestamp.difference(data.first.timestamp).inSeconds
          : 0,
      'path': file.path,
    };
  }

  /// Obtient le répertoire des enregistrements
  Future<Directory> getRecordsDirectory() async {
    if (_baseDirectory == null) await initialize();
    return _baseDirectory!;
  }
}
