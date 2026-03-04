import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensorite/presentation/widgets/common/notion_button.dart';
import '../../data/services/sensor_service.dart';
import '../../data/services/file_service.dart';
import '../../core/models/sensor_data.dart';
import '../../domain/algorithms/madgwick.dart';
import '../../domain/algorithms/integrator.dart';

class VisualizeViewModel extends ChangeNotifier {
  final SensorService _sensorService = SensorService();
  final FileService _fileService = FileService();

  // État
  bool _isLoading = false;
  bool _isLive = false;
  List<Map<String, dynamic>> _recordings = [];
  Map<String, dynamic>? _selectedRecording;

  // Données temps réel
  List<SensorData> _liveData = [];
  List<Map<String, double>> _liveAccelerometerData = [];
  List<Map<String, double>> _liveGyroscopeData = [];
  double _liveFrequency = 0.0;
  int _liveSampleCount = 0;
  Duration _liveDuration = Duration.zero;
  Timer? _liveTimer;

  // Trajectoire
  List<Offset> _trajectoryPoints = [];
  List<Offset> _referencePoints = [];
  Map<String, double>? _driftAnalysis;
  double _driftAmount = 0.0;

  // Getters
  bool get isLoading => _isLoading;
  bool get isLive => _isLive;
  List<Map<String, dynamic>> get recordings => _recordings;
  Map<String, dynamic>? get selectedRecording => _selectedRecording;

  // Données live
  List<Map<String, double>> get liveAccelerometerData => _liveAccelerometerData;
  List<Map<String, double>> get liveGyroscopeData => _liveGyroscopeData;
  double get liveFrequency => _liveFrequency;
  int get liveSampleCount => _liveSampleCount;
  Duration get liveDuration => _liveDuration;

  // Trajectoire
  List<Offset> get trajectoryPoints => _trajectoryPoints;
  List<Offset> get referencePoints => _referencePoints;
  Map<String, double>? get driftAnalysis => _driftAnalysis;
  double get driftAmount => _driftAmount;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    await _fileService.initialize();
    await _sensorService.initialize();

    // Écouter les données capteurs
    _sensorService.sensorDataStream.listen(_handleLiveData);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadRecordings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final files = await _fileService.listRecordings();
      _recordings = [];

      for (var file in files) {
        final metadata = await _fileService.getFileMetadata(file);
        _recordings.add({
          ...metadata,
          'selected': false,
          'previewData': await _getPreviewData(file),
        });
      }

      // Trier du plus récent au plus ancien
      _recordings.sort(
        (a, b) =>
            (b['modified'] as DateTime).compareTo(a['modified'] as DateTime),
      );
    } catch (e) {
      print('Error loading recordings: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<List<Map<String, double>>> _getPreviewData(File file) async {
    try {
      final data = await _fileService.readRecordFile(file);
      // Prendre les 100 premiers points pour l'aperçu
      return data.take(100).map((sensorData) {
        return {
          'x': sensorData.timestamp.millisecondsSinceEpoch.toDouble(),
          'accelX': sensorData.accelX ?? 0,
          'accelY': sensorData.accelY ?? 0,
          'accelZ': sensorData.accelZ ?? 0,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // 📡 Gestion temps réel
  void toggleLive() {
    if (_isLive) {
      _stopLive();
    } else {
      _startLive();
    }
  }

  void _startLive() {
    _isLive = true;
    _liveData.clear();
    _liveAccelerometerData.clear();
    _liveGyroscopeData.clear();
    _liveSampleCount = 0;
    _liveDuration = Duration.zero;

    _liveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isLive) {
        _liveDuration += const Duration(seconds: 1);
        _updateFrequency();
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void _stopLive() {
    _isLive = false;
    _liveTimer?.cancel();
    notifyListeners();
  }

  void resetCharts() {
    _liveAccelerometerData.clear();
    _liveGyroscopeData.clear();
    _liveSampleCount = 0;
    notifyListeners();
  }

  void _handleLiveData(SensorData data) {
    if (!_isLive) return;

    _liveData.add(data);
    _liveSampleCount++;

    // Garder seulement les 200 derniers points pour l'affichage
    final timestamp = data.timestamp.millisecondsSinceEpoch.toDouble();

    if (data.accelX != null) {
      _liveAccelerometerData.add({
        'x': timestamp,
        'accelX': data.accelX!,
        'accelY': data.accelY!,
        'accelZ': data.accelZ!,
      });

      if (_liveAccelerometerData.length > 200) {
        _liveAccelerometerData.removeAt(0);
      }
    }

    if (data.gyroX != null) {
      _liveGyroscopeData.add({
        'x': timestamp,
        'gyroX': data.gyroX!,
        'gyroY': data.gyroY!,
        'gyroZ': data.gyroZ!,
      });

      if (_liveGyroscopeData.length > 200) {
        _liveGyroscopeData.removeAt(0);
      }
    }

    notifyListeners();
  }

  void _updateFrequency() {
    if (_liveData.length < 2) return;

    final now = DateTime.now();
    final oldest = _liveData.last.timestamp;
    final duration = now.difference(oldest).inMilliseconds / 1000.0;

    if (duration > 0) {
      _liveFrequency = _liveData.length / duration;
    }
  }

  // 📁 Gestion des enregistrements
  Future<void> loadRecording(String path) async {
    _isLoading = true;
    notifyListeners();

    try {
      final file = File(path);
      final data = await _fileService.readRecordFile(file);

      // Marquer l'enregistrement sélectionné
      for (var recording in _recordings) {
        recording['selected'] = recording['path'] == path;
      }

      _selectedRecording = _recordings.firstWhere((r) => r['path'] == path);

      // Traiter les données pour la trajectoire
      await _processTrajectory(data);
    } catch (e) {
      print('Error loading recording: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _processTrajectory(List<SensorData> data) async {
    // Filtrer pour garder seulement les données complètes
    final completeData = data.where((d) => d.isComplete).toList();

    if (completeData.isEmpty) return;

    // Initialiser les algorithmes
    final madgwick = MadgwickFilter(beta: 0.5);
    final integrator = TrajectoryIntegrator();

    _trajectoryPoints = [];
    Offset currentPosition = Offset.zero;

    for (int i = 0; i < completeData.length - 1; i++) {
      final current = completeData[i];
      final next = completeData[i + 1];

      final dt =
          next.timestamp.difference(current.timestamp).inMilliseconds / 1000.0;

      // Mettre à jour l'orientation
      final quaternion = madgwick.update(
        current.accelX!,
        current.accelY!,
        current.accelZ!,
        current.gyroX!,
        current.gyroY!,
        current.gyroZ!,
        dt,
      );

      // Intégrer pour obtenir la position
      currentPosition = integrator.integrate(
        current.accelX!,
        current.accelY!,
        current.accelZ!,
        quaternion,
        dt,
      );

      _trajectoryPoints.add(currentPosition);
    }

    // Simuler une trajectoire de référence (à remplacer par des données réelles)
    _generateReferenceTrajectory();

    // Analyser la dérive
    _analyzeDrift();
  }

  void _generateReferenceTrajectory() {
    // À remplacer par la vraie trajectoire mesurée
    // Ici on simule une ligne droite
    _referencePoints = [];
    if (_trajectoryPoints.isNotEmpty) {
      final end = _trajectoryPoints.last;
      for (int i = 0; i <= 10; i++) {
        _referencePoints.add(Offset(end.dx * (i / 10), end.dy * (i / 10)));
      }
    }
  }

  void _analyzeDrift() {
    if (_trajectoryPoints.isEmpty || _referencePoints.isEmpty) {
      _driftAnalysis = null;
      return;
    }

    final estimatedEnd = _trajectoryPoints.last;
    final referenceEnd = _referencePoints.last;

    final error = (estimatedEnd - referenceEnd).distance;
    final totalDistance = referenceEnd.distance;
    double relativeError = totalDistance > 0
        ? (error / totalDistance) * 100
        : 0;

    _driftAnalysis = {
      'finalError': error,
      'relativeError': relativeError,
      'totalDistance': totalDistance,
    };

    _driftAmount = error;
  }

  Future<void> deleteRecording(String path) async {
    final confirm = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          NotionButton(
            label: 'Supprimer',
            type: NotionButtonType.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final file = File(path);
      await _fileService.deleteRecord(file);
      await loadRecordings();

      if (_selectedRecording?['path'] == path) {
        _selectedRecording = null;
        _trajectoryPoints = [];
        _driftAnalysis = null;
      }
    }
  }

  void exportRecording(String path) {
    // À implémenter : partager le fichier
  }

  void analyzeDrift(String path) {
    // Charger et analyser spécifiquement la dérive
    loadRecording(path);
  }

  void processWithFusion(String path) {
    // À implémenter : appliquer différents algorithmes
  }

  void recomputeTrajectory() {
    if (_selectedRecording != null) {
      loadRecording(_selectedRecording!['path']);
    }
  }

  void exportDriftReport() {
    // À implémenter : exporter l'analyse en PDF
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}

// Global navigator key pour les dialogues
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
