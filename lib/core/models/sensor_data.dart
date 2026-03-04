class SensorData {
  final DateTime timestamp;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;

  SensorData({
    required this.timestamp,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
  });

  // Pour savoir si c'est une donnée complète (les deux capteurs au même instant)
  bool get isComplete =>
      accelX != null &&
      accelY != null &&
      accelZ != null &&
      gyroX != null &&
      gyroY != null &&
      gyroZ != null;

  // Convertir en Map pour CSV
  Map<String, dynamic> toCsvMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'accel_x': accelX?.toStringAsFixed(6) ?? '',
      'accel_y': accelY?.toStringAsFixed(6) ?? '',
      'accel_z': accelZ?.toStringAsFixed(6) ?? '',
      'gyro_x': gyroX?.toStringAsFixed(6) ?? '',
      'gyro_y': gyroY?.toStringAsFixed(6) ?? '',
      'gyro_z': gyroZ?.toStringAsFixed(6) ?? '',
    };
  }

  // Version avec fusion (pour plus tard)
  SensorData copyWith({
    DateTime? timestamp,
    double? accelX,
    double? accelY,
    double? accelZ,
    double? gyroX,
    double? gyroY,
    double? gyroZ,
  }) {
    return SensorData(
      timestamp: timestamp ?? this.timestamp,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      gyroX: gyroX ?? this.gyroX,
      gyroY: gyroY ?? this.gyroY,
      gyroZ: gyroZ ?? this.gyroZ,
    );
  }
}
