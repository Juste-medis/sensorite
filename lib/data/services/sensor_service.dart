import 'dart:async';
import 'package:flutter/material.dart';
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

  // Subscriptions
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // State
  SensorStatus _status = SensorStatus.idle;
  DateTime? _recordingStartTime;
  int _sampleCount = 0;

  // Getters
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<AccelerometerEvent> get accelerometerStream =>
      _accelerometerController.stream;
  Stream<GyroscopeEvent> get gyroscopeStream => _gyroscopeController.stream;
  SensorStatus get status => _status;
  DateTime? get recordingStartTime => _recordingStartTime;
  int get sampleCount => _sampleCount;

  // Callbacks pour l'UI
  VoidCallback? onStatusChanged;
  VoidCallback? onDataReceived;

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
      _sensorDataController.add(
        SensorData(
          timestamp: TimestampHelper.now(),
          accelX: event.x,
          accelY: event.y,
          accelZ: event.z,
          gyroX: null, // Sera rempli par le gyroscope
          gyroY: null,
          gyroZ: null,
        ),
      );
      onDataReceived?.call();
    }
  }

  void _handleGyroscopeEvent(GyroscopeEvent event) {
    _gyroscopeController.add(event);

    if (_status == SensorStatus.recording) {
      // Idéalement on synchronise avec l'accéléromètre
      // Version simplifiée : on ajoute une entrée gyro seule
      _sensorDataController.add(
        SensorData(
          timestamp: TimestampHelper.now(),
          accelX: null,
          accelY: null,
          accelZ: null,
          gyroX: event.x,
          gyroY: event.y,
          gyroZ: event.z,
        ),
      );
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
}
