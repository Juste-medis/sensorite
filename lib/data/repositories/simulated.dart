import 'package:sensorite/core/models/sensor_data.dart';

final fakedata = [
  SensorData(
    timestamp: DateTime.now(),
    accelX: 2,
    accelY: 0,
    accelZ: 0,
    gyroX: 0,
    gyroY: 0,
    gyroZ: 0,
  ),
  SensorData(
    timestamp: DateTime.now().add(Duration(seconds: 10)),
    accelX: 2,
    accelY: 0,
    accelZ: 0,
    gyroX: 0,
    gyroY: 0,
    gyroZ: 0,
  ),
];
