import 'package:flutter/material.dart';
import '../../data/services/file_service.dart';

class SettingsViewModel extends ChangeNotifier {
  final FileService _fileService = FileService();

  // Thème
  bool _darkMode = false;

  // Paramètres capteurs
  String _accelerometerFrequency = '100 Hz';
  String _gyroscopeFrequency = '100 Hz';
  bool _highPrecisionMode = false;

  // Paramètres algorithme
  String _fusionAlgorithm = 'madgwick'; // madgwick, mahony, complementary
  double _filterGain = 0.5;
  bool _zuptEnabled = true;
  double _zuptThreshold = 0.5;

  // Informations stockage
  String _storagePath = '...';
  String _availableSpace = '...';
  int _recordingsCount = 0;

  // Getters
  bool get darkMode => _darkMode;
  String get accelerometerFrequency => _accelerometerFrequency;
  String get gyroscopeFrequency => _gyroscopeFrequency;
  bool get highPrecisionMode => _highPrecisionMode;
  String get fusionAlgorithm => _fusionAlgorithm;
  double get filterGain => _filterGain;
  bool get zuptEnabled => _zuptEnabled;
  double get zuptThreshold => _zuptThreshold;
  String get storagePath => _storagePath;
  String get availableSpace => _availableSpace;
  int get recordingsCount => _recordingsCount;

  SettingsViewModel() {
    _loadSettings();
    _loadStorageInfo();
  }

  Future<void> _loadSettings() async {
    // À implémenter : charger depuis SharedPreferences
    notifyListeners();
  }

  Future<void> _loadStorageInfo() async {
    try {
      await _fileService.initialize();

      // Chemin de stockage
      final dir = await _fileService.getRecordsDirectory();
      _storagePath = dir.path;

      // Espace disponible (simplifié)
      // À implémenter avec des stats du système de fichiers
      _availableSpace = '> 100 MB';

      // Nombre d'enregistrements
      final files = await _fileService.listRecordings();
      _recordingsCount = files.length;

      notifyListeners();
    } catch (e) {
      print('Error loading storage info: $e');
    }
  }

  // Setters
  void setDarkMode(bool value) {
    _darkMode = value;
    _saveSettings();
    notifyListeners();
  }

  void setAccelerometerFrequency(String value) {
    _accelerometerFrequency = value;
    _saveSettings();
    notifyListeners();
  }

  void setGyroscopeFrequency(String value) {
    _gyroscopeFrequency = value;
    _saveSettings();
    notifyListeners();
  }

  void setHighPrecisionMode(bool value) {
    _highPrecisionMode = value;
    _saveSettings();
    notifyListeners();
  }

  void setFusionAlgorithm(String value) {
    _fusionAlgorithm = value;
    _saveSettings();
    notifyListeners();
  }

  void setFilterGain(double value) {
    _filterGain = value;
    _saveSettings();
    notifyListeners();
  }

  void setZuptEnabled(bool value) {
    _zuptEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setZuptThreshold(double value) {
    _zuptThreshold = value;
    _saveSettings();
    notifyListeners();
  }

  void openStorageFolder() {
    // À implémenter : ouvrir le dossier avec un Intent
  }

  Future<void> cleanOldRecordings() async {
    // À implémenter : supprimer les vieux fichiers
    // Par exemple : garder seulement les 10 derniers
    await _loadStorageInfo();
  }

  void resetToDefaults() {
    _darkMode = false;
    _accelerometerFrequency = '100 Hz';
    _gyroscopeFrequency = '100 Hz';
    _highPrecisionMode = false;
    _fusionAlgorithm = 'madgwick';
    _filterGain = 0.5;
    _zuptEnabled = true;
    _zuptThreshold = 0.5;

    _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    // À implémenter : sauvegarder dans SharedPreferences
  }
}
