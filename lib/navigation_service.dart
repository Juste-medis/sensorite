import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'kalman_filter.dart';
import 'data_recorder.dart';

class NavigationState {
  final double latitude;
  final double longitude;
  final double speed;
  final double heading;
  final double confidence;
  final double uncertainty;
  final bool gpsAvailable;
  final bool isCalibrated;
  final double calibrationProgress;
  final bool isStationary;
  final double timeSinceGPS;
  final NavigationMode mode;
  final List<PositionRecord> trail;
  final List<PositionRecord> gpsTrail;

  NavigationState({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    required this.confidence,
    required this.uncertainty,
    required this.gpsAvailable,
    required this.isCalibrated,
    required this.calibrationProgress,
    required this.isStationary,
    required this.timeSinceGPS,
    required this.mode,
    required this.trail,
    required this.gpsTrail,
  });
}

class PositionRecord {
  final double lat;
  final double lon;
  final DateTime timestamp;
  final bool fromGPS;
  final double speed;
  final double heading;
  final double confidence;
  final double uncertainty;

  PositionRecord({
    required this.lat,
    required this.lon,
    required this.timestamp,
    required this.fromGPS,
    required this.speed,
    required this.heading,
    required this.confidence,
    required this.uncertainty,
  });
}

class ArchivedVSTrace {
  final DateTime createdAt;
  final String reason;
  final List<PositionRecord> trail;
  final List<PositionRecord> gpsTrail;

  ArchivedVSTrace({
    required this.createdAt,
    required this.reason,
    required this.trail,
    required this.gpsTrail,
  });
}

class CsvTraceSession {
  final String fileName;
  final String filePath;
  final DateTime modifiedAt;
  final List<PositionRecord> trail;
  final List<PositionRecord> gpsTrail;
  final int rowCount;

  CsvTraceSession({
    required this.fileName,
    required this.filePath,
    required this.modifiedAt,
    required this.trail,
    required this.gpsTrail,
    required this.rowCount,
  });
}

enum NavigationMode { idle, calibrating, gps, deadReckoning, gpsDenied, vsMode }

class NavigationService extends ChangeNotifier {
  final IMUKalmanFilter _kalman = IMUKalmanFilter();
  final DataRecorder _recorder = DataRecorder();

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _gpsSub;

  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;

  DateTime? _lastIMUUpdate;
  DateTime? _lastGPSUpdate;

  static const Duration gpsLossThreshold = Duration(seconds: 8);
  static const Duration _gpsInterval = Duration(milliseconds: 500);
  static const int _gpsDistanceFilterMeters = 0;
  // Avoid snapping to stale GPS fixes when GPS updates are sparse.
  // If the last fix is old, the EKF prediction is usually more current.
  static const Duration _maxSnapAge = Duration(milliseconds: 1200);
  Timer? _gpsWatchdog;
  bool _gpsAvailable = false;

  // Estimated position trail (every 500 ms)
  final List<PositionRecord> _trail = [];
  // Raw GPS position trail (one entry per GPS fix)
  final List<PositionRecord> _gpsTrail = [];
  static const int maxTrailLength = 1000;

  NavigationMode _mode = NavigationMode.idle;
  Timer? _imuTimer;

  // Auto-collection
  static const Duration _autoMaxRecordDuration = Duration(minutes: 1);
  static const double _autoMaxGpsDistanceMeters = 1000.0;
  bool _autoActive = false;
  bool _autoRecording = false;
  bool _autoExportInProgress = false;
  int _autoSession = 0;
  int _autoCountdown = 0;
  Timer? _autoCountdownTimer;
  DateTime? _autoSessionStart;
  double _autoSessionGpsDistance = 0.0;
  double? _autoLastGpsLat;
  double? _autoLastGpsLon;

  int _imuUpdates = 0;
  int _gpsUpdates = 0;

  // Last known raw GPS values for CSV recording
  double? _lastGpsLat,
      _lastGpsLon,
      _lastGpsSpeed,
      _lastGpsHeading,
      _lastGpsAccuracy;

  // VS mode: GPS recorded as reference but does NOT correct the EKF
  bool _vsMode = false;
  int _vsSessionCounter = 0;
  final List<ArchivedVSTrace> _archivedVSTraces = [];
  static const int _maxArchivedVSTraces = 20;

  NavigationState get state => NavigationState(
        latitude: _kalman.estimatedPosition[0],
        longitude: _kalman.estimatedPosition[1],
        speed: _kalman.speed,
        heading: _kalman.heading,
        confidence: _kalman.confidence,
        uncertainty: _kalman.positionUncertainty,
        gpsAvailable: _gpsAvailable,
        isCalibrated: _kalman.isCalibrated,
        calibrationProgress: _kalman.calibrationProgress,
        isStationary: _kalman.isStationary,
        timeSinceGPS: _kalman.timeSinceLastGPS,
        mode: _mode,
        trail: List.unmodifiable(_trail),
        gpsTrail: List.unmodifiable(_gpsTrail),
      );

  Future<void> start() async {
    _kalman.reset();
    _trail.clear();
    _gpsTrail.clear();
    _imuUpdates = 0;
    _gpsUpdates = 0;
    _lastIMUUpdate = null;
    _lastGPSUpdate = null;
    _lastGpsLat = null;
    _lastGpsLon = null;
    _lastGpsSpeed = null;
    _lastGpsHeading = null;
    _lastGpsAccuracy = null;
    _gpsAvailable = false;
    _vsMode = false;
    _vsSessionCounter = 0;
    _archivedVSTraces.clear();

    _mode = NavigationMode.calibrating;
    notifyListeners();

    _startIMU();
    await _startGPS();

    _recorder.startRecording();

    _imuTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _processIMU();
    });
  }

  void stop() {
    stopAutoCollection();
    if (_vsMode && !_autoActive) {
      _archiveCurrentVSTrace(reason: 'stop_navigation');
      unawaited(_exportCurrentVSRun(reason: 'stop_navigation'));
    }
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _gpsSub?.cancel();
    _gpsWatchdog?.cancel();
    _imuTimer?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _gpsSub = null;
    _gpsWatchdog = null;
    _imuTimer = null;
    _recorder.stopRecording();
    _vsMode = false;
    _mode = NavigationMode.idle;
    notifyListeners();
  }

  void _startIMU() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      _ax = event.x;
      _ay = event.y;
      _az = event.z;
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      _gx = event.x;
      _gy = event.y;
      _gz = event.z;
    });
  }

  Future<void> _startGPS() async {
    // Cancel any existing subscription before creating a new one
    await _gpsSub?.cancel();
    _gpsSub = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _mode = NavigationMode.gpsDenied;
      notifyListeners();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _mode = NavigationMode.gpsDenied;
      notifyListeners();
      return;
    }

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(
      _onGPSUpdate,
      onError: (_) => _onGPSLost(),
    );

    _gpsWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_lastGPSUpdate != null &&
          DateTime.now().difference(_lastGPSUpdate!) > gpsLossThreshold) {
        _onGPSLost();
      }
    });
  }

  LocationSettings _buildLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _gpsDistanceFilterMeters,
        intervalDuration: _gpsInterval,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: _gpsDistanceFilterMeters,
        pauseLocationUpdatesAutomatically: false,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: _gpsDistanceFilterMeters,
    );
  }

  void _processIMU() {
    final now = DateTime.now();
    double dt = 0.02;

    if (_lastIMUUpdate != null) {
      dt = now.difference(_lastIMUUpdate!).inMicroseconds / 1e6;
    }
    _lastIMUUpdate = now;

    if (!_kalman.isCalibrated) {
      _kalman.addCalibrationSample(_ax, _ay, _az, _gx, _gy, _gz);
      _mode = NavigationMode.calibrating;
      notifyListeners();
      return;
    }

    _kalman.predict(_ax, _ay, _az, _gx, _gy, _gz, dt);
    _kalman.updateNHC();
    _imuUpdates++;

    // Record raw data at full IMU rate
    _recorder.addRecord(RawDataRecord(
      timestampMs: now.millisecondsSinceEpoch,
      axRaw: _ax,
      ayRaw: _ay,
      azRaw: _az,
      gxRaw: _gx,
      gyRaw: _gy,
      gzRaw: _gz,
      estLat: _kalman.estimatedPosition[0],
      estLon: _kalman.estimatedPosition[1],
      estVx: _kalman.x[2],
      estVy: _kalman.x[3],
      speed: _kalman.speed,
      heading: _kalman.heading,
      confidence: _kalman.confidence,
      uncertainty: _kalman.positionUncertainty,
      gpsLat: _lastGpsLat,
      gpsLon: _lastGpsLon,
      gpsSpeed: _lastGpsSpeed,
      gpsAccuracy: _lastGpsAccuracy,
      mode: _mode.name,
      isStationary: _kalman.isStationary,
    ));

    // Estimated position trail (every 500 ms)
    if (_trail.isEmpty ||
        now.difference(_trail.last.timestamp).inMilliseconds > 500) {
      final pos = _kalman.estimatedPosition;
      if (pos[0] != 0 || pos[1] != 0) {
        _trail.add(PositionRecord(
          lat: pos[0],
          lon: pos[1],
          timestamp: now,
          fromGPS: _gpsAvailable && !_vsMode,
          speed: _kalman.speed,
          heading: _kalman.heading,
          confidence: _kalman.confidence,
          uncertainty: _kalman.positionUncertainty,
        ));
        if (_trail.length > maxTrailLength) _trail.removeAt(0);
      }
    }

    if (_imuUpdates % 5 == 0) notifyListeners();
  }

  void _onGPSUpdate(Position position) {
    _lastGPSUpdate = DateTime.now();
    _gpsAvailable = true;
    _lastGpsLat = position.latitude;
    _lastGpsLon = position.longitude;
    _lastGpsSpeed = position.speed;
    _lastGpsHeading = position.heading;
    _lastGpsAccuracy = position.accuracy;

    if (_vsMode) {

    } else {
      if (_kalman.isCalibrated) {
        _mode = NavigationMode.gps;
      }
      _kalman.updateGPS(
        position.latitude,
        position.longitude,
        position.speed,
        position.heading,
        position.accuracy,
      );
    }

    // Always record raw GPS fix as reference
    _gpsTrail.add(PositionRecord(
      lat: position.latitude,
      lon: position.longitude,
      timestamp: _lastGPSUpdate!,
      fromGPS: true,
      speed: position.speed,
      heading: position.heading,
      confidence: 1.0,
      uncertainty: position.accuracy,
    ));
    if (_gpsTrail.length > maxTrailLength) _gpsTrail.removeAt(0);

    if (_autoActive && _autoRecording) {
      _onAutoCollectGPS(position);
    }

    _gpsUpdates++;
    notifyListeners();
  }

  void _snapKalmanToLastGPS() {
    if (!_kalman.isCalibrated ||
        _lastGPSUpdate == null ||
        _lastGpsLat == null ||
        _lastGpsLon == null ||
        _lastGpsSpeed == null ||
        _lastGpsHeading == null ||
        _lastGpsAccuracy == null) {
      return;
    }

    final snapAge = DateTime.now().difference(_lastGPSUpdate!);
    if (snapAge > _maxSnapAge) {
      return;
    }

    _kalman.snapToGPS(
      _lastGpsLat!,
      _lastGpsLon!,
      _lastGpsSpeed!,
      _lastGpsHeading!,
      _lastGpsAccuracy!,
    );
  }

  void _onGPSLost() {
    if (_gpsAvailable) {
      _snapKalmanToLastGPS();
      _gpsAvailable = false;
      _lastGpsLat = null;
      _lastGpsLon = null;
      _lastGpsSpeed = null;
      _lastGpsHeading = null;
      _lastGpsAccuracy = null;
      if (!_vsMode) {
        _mode = _kalman.isCalibrated
            ? NavigationMode.deadReckoning
            : NavigationMode.gpsDenied;
      }
      notifyListeners();
    }
  }


  void startVSMode() {
    if (!_kalman.isCalibrated || !_gpsAvailable) return;
    _vsSessionCounter++;
    _snapKalmanToLastGPS();
    _trail.clear();
    _gpsTrail.clear();
    _recorder.startRecording();
    _vsMode = true;
    _mode = NavigationMode.vsMode;
    // Reset IMU timeSinceLastGPS so confidence starts at 100% for pure IMU run
    _kalman.timeSinceLastGPS = 0;
    notifyListeners();
  }

  /// Stop VS mode and return to normal GPS fusion.
  void stopVSMode() {
    if (_vsMode && !_autoActive) {
      _archiveCurrentVSTrace(reason: 'manual_stop_vs');
      unawaited(_exportCurrentVSRun(reason: 'manual_stop'));
    }
    _vsMode = false;
    _mode = _gpsAvailable ? NavigationMode.gps : NavigationMode.deadReckoning;
    notifyListeners();
  }

  /// Stop current VS session and immediately start a new one.
  /// The previous VS trace is archived and can still be viewed.
  void restartVSMode() {
    if (!_kalman.isCalibrated || !_gpsAvailable) return;
    if (_vsMode) stopVSMode();
    startVSMode();
  }

  void simulateGPSLoss() {
    _snapKalmanToLastGPS();
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _onGPSLost();
  }

  Future<void> restoreGPS() async {
    await _startGPS();
  }

  Future<String?> exportData() => _recorder.exportCSV();

  //  Auto-collection

  /// Start automatic VS-mode cycling.
  /// Each segment stops on 1 km GPS distance or 1 minute, exports CSV,
  /// then starts the next segment immediately.
  void startAutoCollection() {
    if (_autoActive || !_kalman.isCalibrated || !_gpsAvailable) return;
    if (_vsMode) stopVSMode();
    _autoActive = true;
    _autoSession = 0;
    _startAutoSession();
  }

  void stopAutoCollection() {
    if (!_autoActive) return;
    _autoActive = false;
    _autoCountdownTimer?.cancel();
    _autoCountdownTimer = null;
    _autoCountdown = 0;
    final shouldExportPartial = _autoRecording && _recorder.recordCount > 0;
    _autoRecording = false;
    _autoSessionStart = null;
    _autoSessionGpsDistance = 0.0;
    _autoLastGpsLat = null;
    _autoLastGpsLon = null;
    if (shouldExportPartial) {
      unawaited(_exportAutoSession(partial: true, reason: 'manual_stop'));
    }
    if (_vsMode) stopVSMode();
    notifyListeners();
  }

  void _startAutoSession() {
    if (!_autoActive || _autoExportInProgress) return;
    if (!_kalman.isCalibrated || !_gpsAvailable) {
      _autoRecording = false;
      _autoCountdown = 0;
      _autoSessionStart = null;
      _autoSessionGpsDistance = 0.0;
      _autoLastGpsLat = null;
      _autoLastGpsLon = null;
      _autoCountdownTimer?.cancel();
      _autoCountdownTimer = null;
      notifyListeners();
      return;
    }

    _autoSession++;
    _autoRecording = true;
    _autoSessionStart = DateTime.now();
    _autoSessionGpsDistance = 0.0;
    _autoLastGpsLat = _lastGpsLat;
    _autoLastGpsLon = _lastGpsLon;
    _autoCountdown = _autoMaxRecordDuration.inSeconds;
    startVSMode();
    _recorder.startRecording();
    _startAutoCountdown();
    notifyListeners();
  }

  Future<void> _exportAutoSession(
      {required bool partial, required String reason}) async {
    if (_autoExportInProgress) return;
    _autoExportInProgress = true;
    final sessionIndex = _autoSession;
    final tagSuffix = partial ? 'partial' : reason;
    final tag = 'auto${_autoSession.toString().padLeft(2, '0')}';
    final tagged = '${tag}_$tagSuffix';

    _autoRecording = false;
    _autoSessionStart = null;
    _autoSessionGpsDistance = 0.0;
    _autoLastGpsLat = null;
    _autoLastGpsLon = null;
    _autoCountdown = 0;
    _autoCountdownTimer?.cancel();
    _autoCountdownTimer = null;
    notifyListeners();

    if (_vsMode) {
      stopVSMode();
    }
    await _recorder.exportCSV(sessionTag: tagged);

    _autoExportInProgress = false;
    if (_autoActive) {
      // Start the next segment immediately.
      _startAutoSession();
      return;
    }

    // Keep the latest session index visible in debug UI.
    _autoSession = sessionIndex;
    notifyListeners();
  }

  void _startAutoCountdown() {
    _autoCountdownTimer?.cancel();
    _autoCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_autoActive || !_autoRecording || _autoSessionStart == null) {
        t.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_autoSessionStart!);
      final remaining = _autoMaxRecordDuration.inSeconds - elapsed.inSeconds;
      _autoCountdown = remaining > 0 ? remaining : 0;
      notifyListeners();

      if (elapsed >= _autoMaxRecordDuration) {
        t.cancel();
        unawaited(
          _exportAutoSession(partial: false, reason: 'time_1min'),
        );
      }
    });
  }

  void _onAutoCollectGPS(Position position) {
    if (!_autoActive || !_autoRecording) return;

    if (_autoLastGpsLat != null && _autoLastGpsLon != null) {
      final d = Geolocator.distanceBetween(
        _autoLastGpsLat!,
        _autoLastGpsLon!,
        position.latitude,
        position.longitude,
      );
      if (d.isFinite && d > 0) {
        _autoSessionGpsDistance += d;
      }
    }

    _autoLastGpsLat = position.latitude;
    _autoLastGpsLon = position.longitude;

    if (_autoSessionGpsDistance >= _autoMaxGpsDistanceMeters) {
      unawaited(
        _exportAutoSession(partial: false, reason: 'dist_1km'),
      );
    }
  }

  Future<String?> _exportCurrentVSRun({required String reason}) async {
    if (_recorder.recordCount == 0) return null;
    final tag =
        'vs${_vsSessionCounter.toString().padLeft(2, '0')}_$reason';
    return _recorder.exportCSV(sessionTag: tag);
  }

  Future<List<CsvTraceSession>> loadCsvTraceSessions() async {
    final dir = await _recorder.getExportDirectory();
    if (!dir.existsSync()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
          return name.startsWith('imu_') && name.endsWith('.csv');
        })
        .toList()
      ..sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

    final sessions = <CsvTraceSession>[];
    for (final file in files) {
      final parsed = await _parseCsvTraceFile(file);
      if (parsed != null) {
        sessions.add(parsed);
      }
    }
    return sessions;
  }

  Future<CsvTraceSession?> _parseCsvTraceFile(File file) async {
    final lines = await file.readAsLines();
    if (lines.length <= 1) return null;

    final header = lines.first.split(',');
    final index = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      index[header[i].trim()] = i;
    }

    int idx(String name) => index[name] ?? -1;

    final iTs = idx('timestamp_ms');
    final iEstLat = idx('est_lat');
    final iEstLon = idx('est_lon');
    final iSpeed = idx('est_speed');
    final iHeading = idx('est_heading');
    final iConf = idx('confidence');
    final iUnc = idx('uncertainty');
    final iGpsLat = idx('gps_lat');
    final iGpsLon = idx('gps_lon');
    final iGpsSpeed = idx('gps_speed');
    final iGpsAcc = idx('gps_accuracy');

    if (iTs < 0 || iEstLat < 0 || iEstLon < 0) return null;

    final trail = <PositionRecord>[];
    final gpsTrail = <PositionRecord>[];

    int? lastTrailTs;
    int? lastGpsTs;
    double? lastGpsLat;
    double? lastGpsLon;

    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final cols = line.split(',');
      if (cols.length <= iEstLon || cols.length <= iTs) continue;

      int? ts;
      try {
        ts = int.parse(cols[iTs].trim());
      } catch (_) {
        ts = null;
      }
      if (ts == null) continue;
      final tsDate = DateTime.fromMillisecondsSinceEpoch(ts);

      final estLat = _parseDoubleSafe(cols, iEstLat);
      final estLon = _parseDoubleSafe(cols, iEstLon);
      if (estLat != null && estLon != null && (estLat != 0 || estLon != 0)) {
        final prevTrailTs = lastTrailTs;
        final enoughTrailGap = prevTrailTs == null || (ts - prevTrailTs) >= 500;
        if (enoughTrailGap) {
          trail.add(
            PositionRecord(
              lat: estLat,
              lon: estLon,
              timestamp: tsDate,
              fromGPS: false,
              speed: _parseDoubleSafe(cols, iSpeed) ?? 0.0,
              heading: _parseDoubleSafe(cols, iHeading) ?? 0.0,
              confidence: _parseDoubleSafe(cols, iConf) ?? 0.0,
              uncertainty: _parseDoubleSafe(cols, iUnc) ?? 0.0,
            ),
          );
          lastTrailTs = ts;
        }
      }

      final gpsLat = _parseDoubleSafe(cols, iGpsLat);
      final gpsLon = _parseDoubleSafe(cols, iGpsLon);
      if (gpsLat != null && gpsLon != null && (gpsLat != 0 || gpsLon != 0)) {
        final prevGpsTs = lastGpsTs;
        final enoughGpsGap = prevGpsTs == null || (ts - prevGpsTs) >= 800;
        final prevGpsLat = lastGpsLat;
        final prevGpsLon = lastGpsLon;
        final movedGps = prevGpsLat == null ||
            prevGpsLon == null ||
            Geolocator.distanceBetween(
                  prevGpsLat,
                  prevGpsLon,
                  gpsLat,
                  gpsLon,
                ) >
                0.7;
        if (enoughGpsGap || movedGps) {
          gpsTrail.add(
            PositionRecord(
              lat: gpsLat,
              lon: gpsLon,
              timestamp: tsDate,
              fromGPS: true,
              speed: _parseDoubleSafe(cols, iGpsSpeed) ?? 0.0,
              heading: 0.0,
              confidence: 1.0,
              uncertainty: _parseDoubleSafe(cols, iGpsAcc) ?? 0.0,
            ),
          );
          lastGpsTs = ts;
          lastGpsLat = gpsLat;
          lastGpsLon = gpsLon;
        }
      }
    }

    if (trail.isEmpty && gpsTrail.isEmpty) return null;

    return CsvTraceSession(
      fileName: file.path.split(Platform.pathSeparator).last,
      filePath: file.path,
      modifiedAt: file.lastModifiedSync(),
      trail: trail,
      gpsTrail: gpsTrail,
      rowCount: lines.length - 1,
    );
  }

  double? _parseDoubleSafe(List<String> cols, int idx) {
    if (idx < 0 || idx >= cols.length) return null;
    final v = cols[idx].trim();
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  void _archiveCurrentVSTrace({required String reason}) {
    if (_trail.isEmpty && _gpsTrail.isEmpty) return;
    _archivedVSTraces.add(
      ArchivedVSTrace(
        createdAt: DateTime.now(),
        reason: reason,
        trail: List<PositionRecord>.from(_trail),
        gpsTrail: List<PositionRecord>.from(_gpsTrail),
      ),
    );
    if (_archivedVSTraces.length > _maxArchivedVSTraces) {
      _archivedVSTraces.removeAt(0);
    }
  }

  //  Reset / getters

  void reset() {
    stopAutoCollection();
    _kalman.reset();
    _trail.clear();
    _gpsTrail.clear();
    _recorder.clear();
    _imuUpdates = 0;
    _gpsUpdates = 0;
    _lastIMUUpdate = null;
    _lastGPSUpdate = null;
    _lastGpsLat = null;
    _lastGpsLon = null;
    _lastGpsSpeed = null;
    _lastGpsHeading = null;
    _lastGpsAccuracy = null;
    _gpsAvailable = false;
    _vsMode = false;
    _vsSessionCounter = 0;
    _archivedVSTraces.clear();
    _mode = NavigationMode.idle;
    notifyListeners();
  }

  int get imuUpdateCount => _imuUpdates;
  int get gpsUpdateCount => _gpsUpdates;
  int get recordCount => _recorder.recordCount;
  bool get isVSMode => _vsMode;
  bool get isAutoCollecting => _autoActive;
  bool get autoIsRecording => _autoRecording;
  int get autoSession => _autoSession;
  int get autoCountdown => _autoCountdown;
  double get autoDistanceMeters => _autoSessionGpsDistance;
  double get autoDistanceTargetMeters => _autoMaxGpsDistanceMeters;
  int get archivedVSTraceCount => _archivedVSTraces.length;
  ArchivedVSTrace? get lastArchivedVSTrace =>
      _archivedVSTraces.isNotEmpty ? _archivedVSTraces.last : null;

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
