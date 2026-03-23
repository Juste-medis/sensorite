import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/services/sensor_service.dart';
import '../../core/models/sensor_data.dart';

class RecordingViewModel extends ChangeNotifier {
  final SensorService _sensorService = SensorService();

  // État
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isPaused = false;
  int _sampleCount = 0;
  Duration _recordingDuration = Duration.zero;
  File? _currentFile;
  Timer? _durationTimer;

  // Buffer pour optimiser les écritures
  final List<SensorData> _dataBuffer = [];
  static const int _bufferSize = 100; // Écriture par lots de 100

  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  int get sampleCount => _sampleCount;
  Duration get recordingDuration => _recordingDuration;
  String? get currentFileName => _currentFile?.path.split('/').last;

  /// Initialisation
  Future<void> initialize() async {
    if (_isInitialized) return;

    // _sensorService.onDataReceived = _handleSensorData;
    _sensorService.onStatusChanged = _handleStatusChange;
    await _sensorService.initialize();

    _isInitialized = true;
    notifyListeners();
  }

  void _handleStatusChange() {
    _isRecording = _sensorService.status == SensorStatus.recording;
    _isPaused = _sensorService.status == SensorStatus.paused;
    _sampleCount = _sensorService.sampleCount;
    notifyListeners();
  }

  /// Démarrer un nouvel enregistrement
  Future<void> startRecording({String? customName}) async {
    try {
      _dataBuffer.clear();

      await _sensorService.startRecording();
      _startDurationTimer();

      notifyListeners();
    } catch (e) {
      print('Error starting recording: $e');
      rethrow;
    }
  }

  /// Mettre en pause
  Future<void> pauseRecording() async {
    await _sensorService.pauseRecording();
    _durationTimer?.cancel();
    // await _flushBuffer(); // Écrire les données en attente
    notifyListeners();
  }

  /// Reprendre
  Future<void> resumeRecording() async {
    await _sensorService.resumeRecording();
    _startDurationTimer();
    notifyListeners();
  }

  /// Arrêter et sauvegarder
  Future<File?> stopRecording() async {
    await _sensorService.stopRecording();
    _durationTimer?.cancel();
    _recordingDuration = Duration.zero;

    final file = _currentFile;
    _currentFile = null;
    _sampleCount = 0;

    notifyListeners();
    return file;
  }

  /// Abandonner sans sauvegarder
  Future<void> cancelRecording() async {
    await _sensorService.stopRecording();
    _durationTimer?.cancel();
    _recordingDuration = Duration.zero;

    // Supprimer le fichier partiel
    if (_currentFile != null && await _currentFile!.exists()) {
      await _currentFile!.delete();
    }

    _currentFile = null;
    _dataBuffer.clear();
    _sampleCount = 0;

    notifyListeners();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _recordingDuration = Duration.zero;

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isRecording && !_isPaused) {
        _recordingDuration = _recordingDuration + const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }

  /// Traiter les données du capteur
  void _handleSensorData(SensorData data) {
    if (!_isRecording || _isPaused || _currentFile == null) return;

    _dataBuffer.add(data);

    // Écrire par lots pour optimiser les performances
    if (_dataBuffer.length >= _bufferSize) {
      // _flushBuffer();
    }
  }

  /// Nettoyage
  @override
  void dispose() {
    _durationTimer?.cancel();
    _dataBuffer.clear();
    super.dispose();
  }
}
