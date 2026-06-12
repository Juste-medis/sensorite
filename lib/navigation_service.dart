import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'kalman_filter.dart';
import 'data_recorder.dart';

/// Instantané immuable de l'état de navigation à un instant donné.
///
/// Regroupe la position estimée (issue de la fusion GPS + IMU par le filtre de
/// Kalman étendu), la vitesse, le cap, les indicateurs de confiance/incertitude,
/// l'état des capteurs (GPS disponible, calibration, immobilité), le mode courant
/// ([NavigationMode]) ainsi que les traces de position estimée ([trail]) et GPS
/// brute ([gpsTrail]). Construit par le getter [NavigationService.state] et
/// consommé par l'interface utilisateur.
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

  /// Construit un état de navigation.
  ///
  /// Prend en paramètres tous les champs décrivant l'état courant : position
  /// ([latitude], [longitude]), [speed], [heading], [confidence], [uncertainty],
  /// disponibilité GPS ([gpsAvailable]), calibration ([isCalibrated],
  /// [calibrationProgress]), immobilité ([isStationary]), temps écoulé depuis le
  /// dernier point GPS ([timeSinceGPS]), [mode] courant et les traces ([trail],
  /// [gpsTrail]). Renvoie une instance immuable. Appelé par le getter
  /// [NavigationService.state].
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

/// Point de trajectoire horodaté.
///
/// Représente une position unique (latitude [lat], longitude [lon]) à un instant
/// [timestamp], avec son origine ([fromGPS] : vrai si issue d'un point GPS brut,
/// faux si issue de l'estimation du filtre), sa [speed], son [heading], sa
/// [confidence] et son [uncertainty]. Sert à constituer les traces estimée et GPS
/// affichées sur la carte.
class PositionRecord {
  final double lat;
  final double lon;
  final DateTime timestamp;
  final bool fromGPS;
  final double speed;
  final double heading;
  final double confidence;
  final double uncertainty;

  /// Construit un point de trajectoire.
  ///
  /// Prend en paramètres la position ([lat], [lon]), l'horodatage [timestamp],
  /// l'origine [fromGPS], la [speed], le [heading], la [confidence] et
  /// l'[uncertainty]. Renvoie une instance immuable. Appelé chaque fois qu'un
  /// nouveau point est ajouté à une trace (estimée ou GPS).
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

/// Archive d'une session de "mode VS" terminée.
///
/// Conserve une copie figée des traces d'une session VS (estimée [trail] et GPS
/// de référence [gpsTrail]), accompagnée de sa date de création [createdAt] et de
/// la [reason] de son arrêt (ex. arrêt manuel, fin de navigation). Permet de
/// revoir a posteriori une course IMU pure comparée à la vérité-terrain GPS.
class ArchivedVSTrace {
  final DateTime createdAt;
  final String reason;
  final List<PositionRecord> trail;
  final List<PositionRecord> gpsTrail;

  /// Construit une archive de trace VS.
  ///
  /// Prend en paramètres la date de création [createdAt], la [reason] de l'arrêt
  /// et les copies des traces [trail] (estimée) et [gpsTrail] (GPS de référence).
  /// Renvoie une instance immuable. Appelé par
  /// [NavigationService._archiveCurrentVSTrace].
  ArchivedVSTrace({
    required this.createdAt,
    required this.reason,
    required this.trail,
    required this.gpsTrail,
  });
}

/// Session de trajectoire reconstruite à partir d'un fichier CSV exporté.
///
/// Décrit un enregistrement CSV chargé depuis le disque : nom ([fileName]) et
/// chemin ([filePath]) du fichier, date de dernière modification [modifiedAt],
/// nombre de lignes de données [rowCount], et les traces reconstituées à la
/// lecture : estimée ([trail]) et GPS ([gpsTrail]). Produite par
/// [NavigationService.loadCsvTraceSessions] pour rejouer/visualiser d'anciennes
/// sessions.
class CsvTraceSession {
  final String fileName;
  final String filePath;
  final DateTime modifiedAt;
  final List<PositionRecord> trail;
  final List<PositionRecord> gpsTrail;
  final int rowCount;

  /// Construit une session de trace CSV.
  ///
  /// Prend en paramètres le nom [fileName] et le chemin [filePath] du fichier, sa
  /// date de modification [modifiedAt], les traces reconstruites [trail] et
  /// [gpsTrail], et le nombre de lignes [rowCount]. Renvoie une instance
  /// immuable. Appelé par [NavigationService._parseCsvTraceFile].
  CsvTraceSession({
    required this.fileName,
    required this.filePath,
    required this.modifiedAt,
    required this.trail,
    required this.gpsTrail,
    required this.rowCount,
  });
}

/// Modes de fonctionnement du service de navigation.
///
/// - [idle] : à l'arrêt, aucun traitement en cours.
/// - [calibrating] : calibration de l'IMU en cours (pas encore prêt à naviguer).
/// - [gps] : fusion normale GPS + IMU, le GPS corrige le filtre.
/// - [deadReckoning] : navigation à l'estime sur IMU seule (GPS perdu).
/// - [gpsDenied] : GPS indisponible/refusé et filtre non calibré.
/// - [vsMode] : mode VS, le GPS est enregistré comme vérité-terrain mais ne
///   corrige pas le filtre (course IMU pure comparée au GPS).
enum NavigationMode { idle, calibrating, gps, deadReckoning, gpsDenied, vsMode }

/// Orchestrateur central de la navigation fusionnant GPS et IMU.
///
/// Pilote les capteurs (accéléromètre/gyroscope via `sensors_plus`, GPS via
/// `geolocator`), cadence le filtre de Kalman étendu ([IMUKalmanFilter]) à 50 Hz
/// (toutes les 20 ms), et expose l'état courant via le getter [state]. Gère le
/// "mode VS" (où le GPS est enregistré comme vérité-terrain mais ne corrige pas
/// le filtre) ainsi que l'auto-collecte de segments de données exportés en CSV.
/// Étend [ChangeNotifier] : notifie l'interface à chaque mise à jour d'état.
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
  // Évite de recaler sur un point GPS périmé quand les mises à jour GPS sont
  // rares. Si le dernier point est ancien, la prédiction du EKF est en général
  // plus à jour.
  static const Duration _maxSnapAge = Duration(milliseconds: 1200);
  Timer? _gpsWatchdog;
  bool _gpsAvailable = false;

  // Trace de la position estimée (un point toutes les 500 ms)
  final List<PositionRecord> _trail = [];
  // Trace de la position GPS brute (un point par fix GPS)
  final List<PositionRecord> _gpsTrail = [];
  static const int maxTrailLength = 1000;

  NavigationMode _mode = NavigationMode.idle;
  Timer? _imuTimer;

  // Auto-collecte
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

  // Dernières valeurs GPS brutes connues, utilisées pour l'enregistrement CSV
  double? _lastGpsLat,
      _lastGpsLon,
      _lastGpsSpeed,
      _lastGpsHeading,
      _lastGpsAccuracy;

  // Mode VS : le GPS est enregistré comme référence mais ne corrige PAS le EKF
  bool _vsMode = false;
  int _vsSessionCounter = 0;
  final List<ArchivedVSTrace> _archivedVSTraces = [];
  static const int _maxArchivedVSTraces = 20;

  /// Construit et renvoie un instantané [NavigationState] de l'état courant.
  ///
  /// Ne prend aucun paramètre. Agrège les valeurs du filtre de Kalman (position,
  /// vitesse, cap, confiance, incertitude, calibration, immobilité), l'état GPS
  /// et le [_mode], et fournit des copies non modifiables des traces estimée et
  /// GPS. Appelé par l'interface utilisateur (et les listeners de
  /// [ChangeNotifier]) à chaque rafraîchissement de l'affichage.
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

  /// Démarre une nouvelle session de navigation.
  ///
  /// Ne prend aucun paramètre. Réinitialise le filtre de Kalman, les traces, les
  /// compteurs et les valeurs GPS, passe en mode [NavigationMode.calibrating],
  /// lance l'écoute des capteurs IMU ([_startIMU]) et du GPS ([_startGPS]),
  /// démarre l'enregistrement des données et arme le timer périodique (20 ms,
  /// 50 Hz) qui cadence [_processIMU]. Renvoie un [Future] qui se complète quand
  /// l'initialisation du GPS est terminée. Appelé par l'UI au lancement de la
  /// navigation.
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

  /// Arrête la session de navigation en cours.
  ///
  /// Ne prend aucun paramètre. Stoppe l'auto-collecte, archive et exporte la
  /// course VS courante si nécessaire, annule tous les abonnements (capteurs,
  /// GPS, watchdog) et les timers, arrête l'enregistrement, puis repasse en mode
  /// [NavigationMode.idle]. Ne renvoie rien. Appelé par l'UI à l'arrêt de la
  /// navigation et par [dispose].
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

  /// Démarre l'écoute des capteurs inertiels (accéléromètre et gyroscope).
  ///
  /// Ne prend aucun paramètre. S'abonne aux flux `accelerometerEventStream` et
  /// `gyroscopeEventStream` (période d'échantillonnage 20 ms) et met à jour en
  /// continu les dernières valeurs brutes ([_ax]/[_ay]/[_az] et
  /// [_gx]/[_gy]/[_gz]). Ne renvoie rien. Appelé par [start].
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

  /// Initialise et démarre l'écoute du flux de positions GPS.
  ///
  /// Ne prend aucun paramètre. Vérifie l'activation du service de localisation et
  /// les permissions (les demande si nécessaire) ; en cas de refus, passe en mode
  /// [NavigationMode.gpsDenied] et sort. Sinon s'abonne au flux GPS (réglages via
  /// [_buildLocationSettings]) en routant les positions vers [_onGPSUpdate] et
  /// les erreurs vers [_onGPSLost], puis arme un watchdog périodique (2 s) qui
  /// déclenche [_onGPSLost] si aucun point n'est reçu au-delà de
  /// [gpsLossThreshold]. Renvoie un [Future] qui se complète une fois l'écoute
  /// mise en place. Appelé par [start] et [restoreGPS].
  Future<void> _startGPS() async {
    // Annule tout abonnement existant avant d'en créer un nouveau
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

  /// Construit les réglages de localisation adaptés à la plateforme courante.
  ///
  /// Ne prend aucun paramètre. Selon la plateforme ([defaultTargetPlatform]),
  /// renvoie un `AndroidSettings`, un `AppleSettings` (type d'activité navigation
  /// automobile) ou un `LocationSettings` générique, tous configurés en précision
  /// `bestForNavigation` avec le filtre de distance [_gpsDistanceFilterMeters].
  /// Renvoie l'objet [LocationSettings] correspondant. Appelé par [_startGPS].
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

  /// Traite un cycle du filtre à la cadence de 50 Hz (toutes les 20 ms).
  ///
  /// Ne prend aucun paramètre (lit les dernières valeurs capteurs en champs).
  /// Calcule le pas de temps `dt` écoulé depuis le dernier cycle. Si le filtre
  /// n'est pas calibré, ajoute un échantillon de calibration et reste en mode
  /// [NavigationMode.calibrating]. Sinon exécute la prédiction du EKF
  /// (`predict`) et la contrainte non-holonome (`updateNHC`), enregistre la
  /// donnée brute via le [DataRecorder], ajoute un point à la trace estimée
  /// [_trail] au plus toutes les 500 ms, et notifie l'UI un cycle sur cinq. Ne
  /// renvoie rien. Appelé par le timer périodique armé dans [start].
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

    // Enregistre la donnée brute à la pleine cadence de l'IMU
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

    // Trace de la position estimée (un point toutes les 500 ms)
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

  /// Traite la réception d'un nouveau point GPS.
  ///
  /// Prend en paramètre la [position] GPS reçue. Met à jour l'horodatage du
  /// dernier point, l'indicateur [_gpsAvailable] et les dernières valeurs GPS
  /// brutes. En mode VS, n'applique aucune correction au filtre (le GPS reste une
  /// simple référence) ; sinon passe en mode [NavigationMode.gps] (si calibré) et
  /// corrige le filtre via `updateGPS`. Dans tous les cas, ajoute le point brut à
  /// la trace GPS [_gpsTrail], alimente l'auto-collecte ([_onAutoCollectGPS]) si
  /// active, incrémente le compteur et notifie l'UI. Ne renvoie rien. Appelé par
  /// le flux GPS abonné dans [_startGPS].
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

    // Enregistre toujours le point GPS brut comme référence
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

  /// Recale instantanément le filtre de Kalman sur le dernier point GPS connu.
  ///
  /// Ne prend aucun paramètre. Ne fait rien si le filtre n'est pas calibré, si
  /// aucune valeur GPS n'est disponible, ou si le dernier point est plus ancien
  /// que [_maxSnapAge] (auquel cas la prédiction du EKF est jugée plus fiable).
  /// Sinon appelle `snapToGPS` pour repositionner l'état du filtre sur la
  /// dernière position/vitesse/cap GPS. Ne renvoie rien. Appelé par [_onGPSLost],
  /// [startVSMode] et [simulateGPSLoss].
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

  /// Gère la perte du signal GPS.
  ///
  /// Ne prend aucun paramètre. N'agit que si le GPS était disponible : recale le
  /// filtre sur le dernier point ([_snapKalmanToLastGPS]), marque le GPS comme
  /// indisponible, efface les dernières valeurs GPS brutes et, hors mode VS,
  /// bascule en mode [NavigationMode.deadReckoning] (si calibré) ou
  /// [NavigationMode.gpsDenied]. Notifie l'UI. Ne renvoie rien. Appelé par le
  /// watchdog/erreur de [_startGPS] et par [simulateGPSLoss].
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


  /// Démarre le "mode VS" (vérité-terrain GPS sans correction du filtre).
  ///
  /// Ne prend aucun paramètre. Ne fait rien si le filtre n'est pas calibré ou si
  /// le GPS n'est pas disponible. Incrémente le compteur de session VS, recale le
  /// filtre sur le dernier point GPS ([_snapKalmanToLastGPS]), vide les traces,
  /// (re)démarre l'enregistrement, active [_vsMode], passe en mode
  /// [NavigationMode.vsMode] et remet à zéro `timeSinceLastGPS` pour que la
  /// confiance reparte à 100 % sur une course IMU pure. Notifie l'UI. Ne renvoie
  /// rien. Appelé par l'UI, [restartVSMode] et [_startAutoSession].
  void startVSMode() {
    if (!_kalman.isCalibrated || !_gpsAvailable) return;
    _vsSessionCounter++;
    _snapKalmanToLastGPS();
    _trail.clear();
    _gpsTrail.clear();
    _recorder.startRecording();
    _vsMode = true;
    _mode = NavigationMode.vsMode;
    // Remet à zéro timeSinceLastGPS pour que la confiance reparte à 100 % sur
    // une course en IMU pure
    _kalman.timeSinceLastGPS = 0;
    notifyListeners();
  }

  /// Arrête le mode VS et revient à la fusion GPS normale.
  ///
  /// Ne prend aucun paramètre. Si le mode VS est actif et que l'auto-collecte ne
  /// l'est pas, archive ([_archiveCurrentVSTrace]) et exporte
  /// ([_exportCurrentVSRun]) la course courante. Désactive [_vsMode] et bascule
  /// en mode [NavigationMode.gps] (si GPS disponible) ou
  /// [NavigationMode.deadReckoning]. Notifie l'UI. Ne renvoie rien. Appelé par
  /// l'UI, [restartVSMode], [startAutoCollection], [stopAutoCollection] et
  /// [_exportAutoSession].
  void stopVSMode() {
    if (_vsMode && !_autoActive) {
      _archiveCurrentVSTrace(reason: 'manual_stop_vs');
      unawaited(_exportCurrentVSRun(reason: 'manual_stop'));
    }
    _vsMode = false;
    _mode = _gpsAvailable ? NavigationMode.gps : NavigationMode.deadReckoning;
    notifyListeners();
  }

  /// Arrête la session VS courante et en démarre immédiatement une nouvelle.
  ///
  /// Ne prend aucun paramètre. Ne fait rien si le filtre n'est pas calibré ou si
  /// le GPS n'est pas disponible. La trace VS précédente est archivée (via
  /// [stopVSMode]) et reste consultable, puis une nouvelle session est lancée via
  /// [startVSMode]. Ne renvoie rien. Appelé par l'UI.
  void restartVSMode() {
    if (!_kalman.isCalibrated || !_gpsAvailable) return;
    if (_vsMode) stopVSMode();
    startVSMode();
  }

  /// Simule une perte de signal GPS (pour les tests/démonstrations).
  ///
  /// Ne prend aucun paramètre. Recale d'abord le filtre sur le dernier point
  /// ([_snapKalmanToLastGPS]), annule l'abonnement GPS et le watchdog, puis
  /// déclenche [_onGPSLost] pour basculer en navigation à l'estime. Ne renvoie
  /// rien. Appelé par l'UI.
  void simulateGPSLoss() {
    _snapKalmanToLastGPS();
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _onGPSLost();
  }

  /// Rétablit l'écoute du GPS après une perte (réelle ou simulée).
  ///
  /// Ne prend aucun paramètre. Relance l'initialisation du GPS via [_startGPS].
  /// Renvoie un [Future] qui se complète quand l'écoute est rétablie. Appelé par
  /// l'UI.
  Future<void> restoreGPS() async {
    await _startGPS();
  }

  /// Exporte les données enregistrées au format CSV.
  ///
  /// Ne prend aucun paramètre. Délègue au [DataRecorder] l'écriture du CSV.
  /// Renvoie un [Future] contenant le chemin du fichier exporté, ou `null` en cas
  /// d'échec/absence de données. Appelé par l'UI (export manuel).
  Future<String?> exportData() => _recorder.exportCSV();

  //  Auto-collecte

  /// Démarre le cyclage automatique du mode VS.
  ///
  /// Ne prend aucun paramètre. Ne fait rien si l'auto-collecte est déjà active,
  /// si le filtre n'est pas calibré ou si le GPS n'est pas disponible. Arrête un
  /// éventuel mode VS manuel, active [_autoActive], remet le compteur de session
  /// à zéro et lance le premier segment via [_startAutoSession]. Chaque segment
  /// s'arrête à 1 km de distance GPS ou au bout d'1 minute, exporte un CSV, puis
  /// le segment suivant démarre immédiatement. Ne renvoie rien. Appelé par l'UI.
  void startAutoCollection() {
    if (_autoActive || !_kalman.isCalibrated || !_gpsAvailable) return;
    if (_vsMode) stopVSMode();
    _autoActive = true;
    _autoSession = 0;
    _startAutoSession();
  }

  /// Arrête le cyclage automatique du mode VS.
  ///
  /// Ne prend aucun paramètre. Ne fait rien si l'auto-collecte n'est pas active.
  /// Désactive [_autoActive], annule le timer de décompte et réinitialise les
  /// états de session. Si un segment en cours contient des données, exporte un
  /// CSV partiel via [_exportAutoSession]. Arrête le mode VS si nécessaire et
  /// notifie l'UI. Ne renvoie rien. Appelé par l'UI, [stop] et [reset].
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

  /// Démarre un nouveau segment d'auto-collecte.
  ///
  /// Ne prend aucun paramètre. Ne fait rien si l'auto-collecte est inactive ou
  /// qu'un export est en cours. Si le filtre n'est pas calibré ou le GPS
  /// indisponible, réinitialise les états de session et attend. Sinon incrémente
  /// le numéro de session, initialise le suivi de distance/temps, démarre le mode
  /// VS ([startVSMode]), (re)démarre l'enregistrement et lance le décompte
  /// ([_startAutoCountdown]). Notifie l'UI. Ne renvoie rien. Appelé par
  /// [startAutoCollection] et [_exportAutoSession] (enchaînement des segments).
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

  /// Exporte le segment d'auto-collecte courant en CSV et enchaîne le suivant.
  ///
  /// Prend en paramètres [partial] (vrai si l'export est partiel/interrompu) et
  /// [reason] (motif de l'arrêt, utilisé dans le nom de fichier). Ne fait rien si
  /// un export est déjà en cours. Construit une étiquette de session, réinitialise
  /// les états, arrête le mode VS, écrit le CSV via le [DataRecorder], puis — si
  /// l'auto-collecte est toujours active — relance immédiatement un segment via
  /// [_startAutoSession]. Renvoie un [Future] complété en fin d'export. Appelé par
  /// [stopAutoCollection], [_startAutoCountdown] (limite de temps) et
  /// [_onAutoCollectGPS] (limite de distance).
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
      // Démarre immédiatement le segment suivant.
      _startAutoSession();
      return;
    }

    // Conserve le dernier index de session visible dans l'UI de debug.
    _autoSession = sessionIndex;
    notifyListeners();
  }

  /// Arme le décompte d'1 minute du segment d'auto-collecte courant.
  ///
  /// Ne prend aucun paramètre. Démarre un timer périodique (1 s) qui met à jour
  /// le décompte restant [_autoCountdown] et notifie l'UI ; il s'annule si
  /// l'auto-collecte/l'enregistrement s'arrête. Quand la durée maximale
  /// [_autoMaxRecordDuration] est atteinte, déclenche l'export du segment via
  /// [_exportAutoSession] (motif `time_1min`). Ne renvoie rien. Appelé par
  /// [_startAutoSession].
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

  /// Met à jour la distance GPS parcourue pendant l'auto-collecte.
  ///
  /// Prend en paramètre la [position] GPS courante. Ne fait rien si
  /// l'auto-collecte ou l'enregistrement n'est pas actif. Cumule la distance
  /// parcourue (via `Geolocator.distanceBetween`) dans
  /// [_autoSessionGpsDistance] et mémorise la dernière position. Quand le seuil
  /// [_autoMaxGpsDistanceMeters] (1 km) est atteint, déclenche l'export du
  /// segment via [_exportAutoSession] (motif `dist_1km`). Ne renvoie rien.
  /// Appelé par [_onGPSUpdate] lorsque l'auto-collecte enregistre.
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

  /// Exporte en CSV la course VS courante (hors auto-collecte).
  ///
  /// Prend en paramètre [reason] (motif de l'export, intégré au nom de fichier).
  /// Renvoie un [Future] contenant le chemin du CSV exporté, ou `null` si aucun
  /// enregistrement n'est disponible. Appelé par [stop] et [stopVSMode].
  Future<String?> _exportCurrentVSRun({required String reason}) async {
    if (_recorder.recordCount == 0) return null;
    final tag =
        'vs${_vsSessionCounter.toString().padLeft(2, '0')}_$reason';
    return _recorder.exportCSV(sessionTag: tag);
  }

  /// Charge et reconstruit toutes les sessions de trace depuis les CSV exportés.
  ///
  /// Ne prend aucun paramètre. Liste les fichiers `imu_*.csv` du répertoire
  /// d'export, les trie du plus récent au plus ancien, puis analyse chacun via
  /// [_parseCsvTraceFile]. Renvoie un [Future] contenant la liste des
  /// [CsvTraceSession] reconstituées (vide si le répertoire n'existe pas).
  /// Appelé par l'UI pour afficher l'historique des sessions.
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

  /// Analyse un fichier CSV et reconstruit la session de trace correspondante.
  ///
  /// Prend en paramètre le [file] CSV à lire. Lit l'en-tête pour localiser les
  /// colonnes utiles, puis parcourt les lignes pour reconstruire la trace
  /// estimée (sous-échantillonnée à au plus un point toutes les 500 ms) et la
  /// trace GPS (filtrée par écart temporel d'au moins 800 ms ou déplacement
  /// supérieur à 0,7 m). Renvoie un [Future] contenant la [CsvTraceSession]
  /// reconstruite, ou `null` si le fichier est vide, mal formé ou sans données
  /// exploitables. Appelé par [loadCsvTraceSessions].
  Future<CsvTraceSession?> _parseCsvTraceFile(File file) async {
    final lines = await file.readAsLines();
    if (lines.length <= 1) return null;

    final header = lines.first.split(',');
    final index = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      index[header[i].trim()] = i;
    }

    /// Renvoie l'index de la colonne dont l'en-tête est [name], ou -1 si absente.
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

  /// Analyse de façon sûre une valeur `double` dans une ligne CSV.
  ///
  /// Prend en paramètres la liste de colonnes [cols] et l'index [idx] de la
  /// colonne visée. Renvoie le `double` analysé, ou `null` si l'index est hors
  /// limites, la cellule vide ou la valeur non convertible. Appelé par
  /// [_parseCsvTraceFile] pour extraire les champs numériques.
  double? _parseDoubleSafe(List<String> cols, int idx) {
    if (idx < 0 || idx >= cols.length) return null;
    final v = cols[idx].trim();
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  /// Archive une copie figée de la trace VS courante.
  ///
  /// Prend en paramètre [reason] (motif de l'archivage). Ne fait rien si les deux
  /// traces sont vides. Ajoute une [ArchivedVSTrace] (copies des traces estimée
  /// et GPS) à la liste d'archives, en bornant celle-ci à [_maxArchivedVSTraces]
  /// entrées (suppression de la plus ancienne au-delà). Ne renvoie rien. Appelé
  /// par [stop] et [stopVSMode].
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

  //  Réinitialisation / getters

  /// Réinitialise entièrement le service de navigation.
  ///
  /// Ne prend aucun paramètre. Arrête l'auto-collecte, réinitialise le filtre de
  /// Kalman, vide les traces, efface l'enregistreur et tous les compteurs/états
  /// (GPS, VS, archives), puis repasse en mode [NavigationMode.idle]. Notifie
  /// l'UI. Ne renvoie rien. Appelé par l'UI pour repartir d'un état vierge.
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

  /// Renvoie le nombre total de cycles IMU traités depuis le dernier démarrage.
  int get imuUpdateCount => _imuUpdates;

  /// Renvoie le nombre total de points GPS reçus depuis le dernier démarrage.
  int get gpsUpdateCount => _gpsUpdates;

  /// Renvoie le nombre d'enregistrements actuellement détenus par l'enregistreur.
  int get recordCount => _recorder.recordCount;

  /// Renvoie vrai si le mode VS est actuellement actif.
  bool get isVSMode => _vsMode;

  /// Renvoie vrai si l'auto-collecte est en cours.
  bool get isAutoCollecting => _autoActive;

  /// Renvoie vrai si un segment d'auto-collecte enregistre actuellement.
  bool get autoIsRecording => _autoRecording;

  /// Renvoie le numéro du segment d'auto-collecte courant.
  int get autoSession => _autoSession;

  /// Renvoie le nombre de secondes restantes avant la fin du segment courant.
  int get autoCountdown => _autoCountdown;

  /// Renvoie la distance GPS (en mètres) parcourue dans le segment courant.
  double get autoDistanceMeters => _autoSessionGpsDistance;

  /// Renvoie la distance GPS cible (en mètres) déclenchant la fin d'un segment.
  double get autoDistanceTargetMeters => _autoMaxGpsDistanceMeters;

  /// Renvoie le nombre de traces VS archivées.
  int get archivedVSTraceCount => _archivedVSTraces.length;

  /// Renvoie la dernière trace VS archivée, ou `null` s'il n'y en a aucune.
  ArchivedVSTrace? get lastArchivedVSTrace =>
      _archivedVSTraces.isNotEmpty ? _archivedVSTraces.last : null;

  /// Libère les ressources du service avant sa destruction.
  ///
  /// Ne prend aucun paramètre. Appelle [stop] pour fermer capteurs, GPS et
  /// timers, puis délègue à `super.dispose()`. Ne renvoie rien. Appelé
  /// automatiquement par le framework Flutter lorsque le service n'est plus
  /// utilisé.
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
