import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensorite/core/utils/utls.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../core/models/sensor_data.dart';
import '../../core/utils/timestamp_helper.dart';

enum SensorStatus { idle, recording, paused }

class SensorService {
  // Singleton
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // Stream controllers
  final _accelerometerController =
      StreamController<AccelerometerEvent>.broadcast();
  final _gyroscopeController = StreamController<GyroscopeEvent>.broadcast();
  final _sensorDataController = StreamController<SensorData>.broadcast();
  SensorData? _latestCompleteSensorData;

  // Subscriptions
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // State
  SensorStatus _status = SensorStatus.idle;
  DateTime? _recordingStartTime;
  int _sampleCount = 0;

  SensorData? latestAccel;
  SensorData? latestGyro;

  // Getters
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  SensorData? get latestCompleteSensorData => _latestCompleteSensorData;
  Stream<AccelerometerEvent> get accelerometerStream =>
      _accelerometerController.stream;
  Stream<GyroscopeEvent> get gyroscopeStream => _gyroscopeController.stream;
  SensorStatus get status => _status;
  DateTime? get recordingStartTime => _recordingStartTime;
  int get sampleCount => _sampleCount;

  // Callbacks pour l'UI
  VoidCallback? onStatusChanged;
  ValueChanged<SensorData>? onDataReceived;

  /// Initialise les écouteurs capteurs
  Future<void> initialize() async {
    // S'assurer que les streams sont écoutés
    _accelerometerSubscription = accelerometerEventStream().listen(
      _handleAccelerometerEvent,
      onError: _handleError,
      cancelOnError: false,
    );

    _gyroscopeSubscription = gyroscopeEventStream().listen(
      _handleGyroscopeEvent,
      onError: _handleError,
      cancelOnError: false,
    );
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    _accelerometerController.add(event);

    if (_status == SensorStatus.recording) {
      _sampleCount++;

      latestAccel = SensorData(
        timestamp: TimestampHelper.now(),
        accelX: event.x,
        accelY: event.y,
        accelZ: event.z,
        gyroX: null,
        gyroY: null,
        gyroZ: null,
      );
      _sensorDataController.add(latestAccel!);
      onDataReceived?.call(latestAccel!);
    }
  }

  void _handleGyroscopeEvent(GyroscopeEvent event) {
    _gyroscopeController.add(event);

    myprintnet(
      "  Handling gyroscope event: x=${event.x}, y=${event.y}, z=${event.z}, status=$_status",
    );
    if (_status == SensorStatus.recording) {
      latestGyro = SensorData(
        timestamp: TimestampHelper.now(),
        accelX: null,
        accelY: null,
        accelZ: null,
        gyroX: event.x,
        gyroY: event.y,
        gyroZ: event.z,
      );
      _sensorDataController.add(latestGyro!);
      onDataReceived?.call(latestGyro!);
    }
  }

  void _handleError(Object error) {
    print('Sensor error: $error');
  }

  /// Démarre l'enregistrement
  Future<void> startRecording() async {
    if (_status == SensorStatus.recording) return;

    _status = SensorStatus.recording;
    _recordingStartTime = DateTime.now();
    _sampleCount = 0;

    onStatusChanged?.call();
  }

  /// Met en pause l'enregistrement
  Future<void> pauseRecording() async {
    if (_status != SensorStatus.recording) return;

    _status = SensorStatus.paused;
    onStatusChanged?.call();
  }

  /// Reprend l'enregistrement
  Future<void> resumeRecording() async {
    if (_status != SensorStatus.paused) return;

    _status = SensorStatus.recording;
    onStatusChanged?.call();
  }

  /// Arrête l'enregistrement
  Future<void> stopRecording() async {
    _status = SensorStatus.idle;
    _recordingStartTime = null;
    _sampleCount = 0;

    onStatusChanged?.call();
  }

  /// Nettoie les ressources
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _accelerometerController.close();
    _gyroscopeController.close();
    _sensorDataController.close();
  }

  // fusion sensors
  Future<void> startSensorFusion() async {
    sensorDataStream.listen(
      (SensorData data) {
        myprint(
          'Fusiongyrox = ${latestGyro?.gyroX}, accelX = ${latestAccel?.accelX}, timestamp: ${data.timestamp.toIso8601String()}',
        );
        _latestCompleteSensorData = SensorData(
          timestamp: data.timestamp,
          accelX: latestAccel?.accelX,
          accelY: latestAccel?.accelY,
          accelZ: latestAccel?.accelZ,
          gyroX: latestGyro?.gyroX,
          gyroY: latestGyro?.gyroY,
          gyroZ: latestGyro?.gyroZ,
        );
        onDataReceived?.call(_latestCompleteSensorData!);
      },
      onError: (error) {
        my_print_err("Error in sensor fusion: $error");
      },
    );
  }
}
