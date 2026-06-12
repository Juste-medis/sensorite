import 'dart:math';

/// Extended Kalman Filter for 2D position estimation from IMU data.
///
/// State vector: [x, y, vx, vy, ax, ay, yaw]
/// - x, y: position in meters (local ENU frame)
/// - vx, vy: velocity in m/s
/// - ax, ay: acceleration in m/s²
/// - yaw: heading in radians
///
/// When GPS is available, it fuses GPS position + velocity as observations.
/// When GPS is lost, it relies on accelerometer + gyroscope predictions only.
class IMUKalmanFilter {
  // State dimension
  static const int n = 7;

  // State vector [x, y, vx, vy, ax, ay, yaw]
  List<double> x;

  // State covariance matrix (n x n)
  List<List<double>> P;

  // Process noise covariance
  List<List<double>> Q;

  // GPS measurement noise covariance (for position + velocity: 4x4)
  List<List<double>> R_gps;

  // IMU measurement noise covariance (for accel + gyro: 3x3)
  List<List<double>> R_imu;

  // Gravity vector magnitude
  static const double gravity = 9.81;
  // Reject tiny yaw-rate bias that accumulates into large heading drift in VS mode.
  static const double _yawRateDeadband = 0.03; // rad/s
  // Reject unrealistic spikes (phone movement / shock) that can corrupt heading.
  static const double _yawRateClip = 1.2; // rad/s
  // Reject tiny linear acceleration that would integrate into speed drift.
  static const double _accelDeadband = 0.08; // m/s²
  // Clip unrealistic linear acceleration bursts.
  static const double _accelClip = 6.0; // m/sÂ²
  // Keep predicted speed close to the latest reliable GPS speed.
  static const double _speedLockRate = 3.0; // 1/s
  static const double _speedLockMaxDeltaPerSec = 1.6; // m/s per second
  // In straight-line motion, ignore tiny yaw rates to avoid heading creep.
  static const double _turnYawRateThreshold = 0.07; // rad/s
  static const double _turnLateralAccelThreshold = 0.30; // m/s²

  // NHC measurement noise variance (m/s)² - tight since vehicles can't slide sideways
  static const double _rNhc = 0.01;

  // Low-pass filter coefficient for accelerometer noise reduction
  final double _alphaLowPass = 0.1;

  // Previous filtered accelerometer values
  double _filteredAx = 0.0;
  double _filteredAy = 0.0;
  double _filteredAz = 0.0;
  bool _lowPassInitialized = false;

  // Bias estimates for accelerometer
  double biasAx = 0.0;
  double biasAy = 0.0;
  double biasAz = 0.0;

  // Bias estimates for gyroscope
  double biasGx = 0.0;
  double biasGy = 0.0;
  double biasGz = 0.0;

  // Calibration state
  bool isCalibrated = false;
  int _calibrationSamples = 0;
  static const int calibrationTarget = 100;
  final List<double> _calAx = [], _calAy = [], _calAz = [];
  final List<double> _calGx = [], _calGy = [], _calGz = [];

  // Stationary detection
  final List<double> _recentAccelMagnitudes = [];
  static const int varianceWindow = 20;
  static const double stationaryThreshold = 0.02;
  int _stationarySamples = 0;
  static const int _stationarySampleTarget = 50;
  static const double _stationaryGyroThreshold = 0.03;
  static const double _stationaryGravityTolerance = 0.35;
  bool isStationary = false;

  // GPS reference point for local coordinate conversion
  double? refLat;
  double? refLon;

  // Track total distance for drift estimation
  double totalDistance = 0.0;
  double timeSinceLastGPS = 0.0;

  // Confidence metric (0-1)
  double confidence = 1.0;

  // Latest speed reference from GPS (used during dead reckoning).
  double _speedRefMps = 0.0;
  bool _hasSpeedRef = false;

  /// Construit le filtre : état `x` initialisé à zéro, covariance `P` à forte
  /// incertitude (identité × 100), matrices de bruit `Q`, `R_gps`, `R_imu`
  /// préparées via [_initProcessNoise] et [_initMeasurementNoise].
  ///
  /// Appelé une seule fois, à la création de `NavigationService`.
  IMUKalmanFilter()
      : x = List.filled(n, 0.0),
        P = _identity(n, 100.0),
        Q = _zeros(n),
        R_gps = _zeros(4),
        R_imu = _zeros(3) {
    _initProcessNoise();
    _initMeasurementNoise();
  }

  /// Remplit la matrice de bruit de process `Q` : l'incertitude que le modèle
  /// ajoute à la covariance `P` à chaque prédiction (position / vitesse /
  /// accélération / cap). Valeurs réglées pour un mouvement piéton-véhicule.
  ///
  /// Ne prend rien, ne renvoie rien. Appelé par le constructeur.
  void _initProcessNoise() {
    // Process noise - tuned for pedestrian/vehicle motion
    Q[0][0] = 0.5; // x position noise
    Q[1][1] = 0.5; // y position noise
    Q[2][2] = 1.0; // vx velocity noise
    Q[3][3] = 1.0; // vy velocity noise
    Q[4][4] = 2.0; // ax acceleration noise
    Q[5][5] = 2.0; // ay acceleration noise
    Q[6][6] = 0.1; // yaw noise
  }

  /// Remplit les matrices de bruit de mesure : `R_gps` (confiance dans le GPS,
  /// position + vitesse) et `R_imu` (confiance dans l'accéléromètre + gyro).
  /// Plus la valeur est grande, moins on fait confiance à la mesure.
  ///
  /// Ne prend rien, ne renvoie rien. Appelé par le constructeur.
  void _initMeasurementNoise() {
    // GPS measurement noise (position in meters, velocity in m/s)
    R_gps[0][0] = 4.0; // x position (2m std dev)
    R_gps[1][1] = 4.0; // y position
    R_gps[2][2] = 0.5; // vx velocity
    R_gps[3][3] = 0.5; // vy velocity

    // IMU measurement noise (accelerometer + gyroscope)
    R_imu[0][0] = 0.5; // ax
    R_imu[1][1] = 0.5; // ay
    R_imu[2][2] = 0.01; // yaw rate
  }

  /// Accumule un échantillon de calibration (à appeler téléphone immobile).
  ///
  /// Paramètres : [ax],[ay],[az] accéléromètre brut (m/s²), [gx],[gy],[gz]
  /// gyroscope brut (rad/s).
  ///
  /// Au bout de [calibrationTarget] (100) échantillons, calcule les **biais**
  /// = moyenne de chaque axe (la gravité est retirée sur Z), puis passe
  /// `isCalibrated` à `true`. Ne fait plus rien une fois calibré.
  ///
  /// Ne renvoie rien. Appelé par `_processIMU()` tant que le filtre n'est pas
  /// calibré (phase de démarrage, à l'arrêt).
  void addCalibrationSample(
      double ax, double ay, double az, double gx, double gy, double gz) {
    if (isCalibrated) return;

    _calAx.add(ax);
    _calAy.add(ay);
    _calAz.add(az);
    _calGx.add(gx);
    _calGy.add(gy);
    _calGz.add(gz);
    _calibrationSamples++;

    if (_calibrationSamples >= calibrationTarget) {
      biasAx = _mean(_calAx);
      biasAy = _mean(_calAy);
      biasAz = _mean(_calAz) - gravity; // Remove gravity from Z bias
      biasGx = _mean(_calGx);
      biasGy = _mean(_calGy);
      biasGz = _mean(_calGz);
      _lowPassInitialized = false;
      _recentAccelMagnitudes.clear();
      _stationarySamples = 0;
      isCalibrated = true;
    }
  }

  /// Avancement de la calibration, entre 0 et 1
  /// (`_calibrationSamples / 100`). Lu par l'UI pour la barre de progression.
  double get calibrationProgress => _calibrationSamples / calibrationTarget;

  /// Filtre passe-bas (moyenne mobile exponentielle) sur l'accéléromètre, pour
  /// atténuer le bruit haute fréquence (vibrations) : `filtré = 0,1·brut +
  /// 0,9·ancien`.
  ///
  /// Paramètres : [ax],[ay],[az] accélération brute des 3 axes.
  /// Renvoie la liste `[ax, ay, az]` filtrée.
  /// Appelé par [predict] à chaque pas.
  List<double> _lowPassFilter(double ax, double ay, double az) {
    if (!_lowPassInitialized) {
      _filteredAx = ax;
      _filteredAy = ay;
      _filteredAz = az;
      _lowPassInitialized = true;
      return [_filteredAx, _filteredAy, _filteredAz];
    }

    _filteredAx = _alphaLowPass * ax + (1 - _alphaLowPass) * _filteredAx;
    _filteredAy = _alphaLowPass * ay + (1 - _alphaLowPass) * _filteredAy;
    _filteredAz = _alphaLowPass * az + (1 - _alphaLowPass) * _filteredAz;
    return [_filteredAx, _filteredAy, _filteredAz];
  }

  /// Détecte l'immobilité du véhicule (ex. feu rouge) pour éviter la dérive
  /// à l'arrêt.
  ///
  /// Paramètres : mesure accéléromètre [ax],[ay],[az] et gyroscope [gx],[gy],
  /// [gz]. Calcule la **variance** de la norme d'accélération sur une fenêtre
  /// de 20 échantillons ; met `isStationary` à `true` si variance faible ET
  /// norme ≈ g ET gyroscope faible, de façon stable (50 échantillons).
  ///
  /// Ne renvoie rien (met à jour le champ `isStationary`).
  /// Appelé par [predict] à chaque pas.
  void _updateStationaryDetection(
      double ax, double ay, double az, double gx, double gy, double gz) {
    double mag = sqrt(ax * ax + ay * ay + az * az);
    _recentAccelMagnitudes.add(mag);
    if (_recentAccelMagnitudes.length > varianceWindow) {
      _recentAccelMagnitudes.removeAt(0);
    }

    if (_recentAccelMagnitudes.length >= varianceWindow) {
      double mean = _mean(_recentAccelMagnitudes);
      double variance = _recentAccelMagnitudes.fold(
              0.0, (sum, v) => sum + (v - mean) * (v - mean)) /
          _recentAccelMagnitudes.length;
      final gyroMagnitude = sqrt(gx * gx + gy * gy + gz * gz);
      final looksStationary = variance < stationaryThreshold &&
          (mag - gravity).abs() < _stationaryGravityTolerance &&
          gyroMagnitude < _stationaryGyroThreshold;

      _stationarySamples = looksStationary ? _stationarySamples + 1 : 0;
      isStationary = _stationarySamples >= _stationarySampleTarget;
    }
  }

  /// **Étape de prédiction — ma dérivation hybride.** Fait avancer l'état d'un
  /// pas de temps à partir des capteurs inertiels, SANS double-intégrer
  /// l'accélération (qui divergerait en t²).
  ///
  /// Paramètres : [ax],[ay],[az] accéléromètre (m/s², repère téléphone),
  /// [gx],[gy],[gz] gyroscope (rad/s, repère téléphone), [dt] pas de temps (s).
  ///
  /// Déroulé : (1) rejette un [dt] invalide ; (2) retire les biais ;
  /// (3) deadband + clip du gyro `gz` ; (4) passe-bas accéléro ; (5) détection
  /// d'immobilité ; (6) **hybride** : cap intégré depuis `gz`, vitesse
  /// verrouillée sur la dernière vitesse GPS (`_speedRefMps`), projection
  /// module × direction, puis intégration unique de la position ; (7) propage
  /// la covariance `P = F·P·Fᵀ + Q·dt` ; (8) fait décroître `confidence`.
  ///
  /// Ne renvoie rien (met à jour `x` et `P`).
  /// Appelé par `_processIMU()` à **50 Hz**.
  void predict(double ax, double ay, double az, double gx, double gy, double gz,
      double dt) {
    if (dt <= 0 || dt > 1.0) return; // Reject invalid time steps

    // Remove bias
    ax -= biasAx;
    ay -= biasAy;
    az -= biasAz;
    gx -= biasGx;
    gy -= biasGy;
    gz -= biasGz;

    if (gz.abs() < _yawRateDeadband) {
      gz = 0.0;
    } else if (gz > _yawRateClip) {
      gz = _yawRateClip;
    } else if (gz < -_yawRateClip) {
      gz = -_yawRateClip;
    }

    // Low-pass filter 
    var filtered = _lowPassFilter(ax, ay, az);
    ax = filtered[0];
    ay = filtered[1];
    az = filtered[2];

    // Stationary detection
    _updateStationaryDetection(ax, ay, az, gx, gy, gz);

    // Hybrid propagation (no full accel double-integration):
    // 1) integrate yaw from gyro
    // 2) keep speed mostly driven by last reliable GPS speed
    // 3) project speed on yaw, then integrate position
    double aLateral = ax;
    if (aLateral.abs() < _accelDeadband) aLateral = 0.0;
    aLateral = aLateral.clamp(-_accelClip, _accelClip);

    // If the vehicle is likely going straight, suppress tiny yaw-rate residues.
    final bool likelyStraight = gz.abs() < _turnYawRateThreshold &&
        aLateral.abs() < _turnLateralAccelThreshold;
    final double yawRateUsed = likelyStraight ? 0.0 : gz;
    final double yaw = _normalizeAngle(x[6] + yawRateUsed * dt);

    final double currentSpeed = sqrt(x[2] * x[2] + x[3] * x[3]);
    double predictedSpeed = currentSpeed;
    if (_hasSpeedRef) {
      final double targetSpeed = isStationary ? 0.0 : _speedRefMps;
      final double alpha = 1.0 - exp(-_speedLockRate * dt);
      final double blended =
          predictedSpeed + alpha * (targetSpeed - predictedSpeed);
      final double maxDelta = _speedLockMaxDeltaPerSec * dt;
      predictedSpeed =
          blended.clamp(predictedSpeed - maxDelta, predictedSpeed + maxDelta);
    }

    if (isStationary && predictedSpeed < 1.0) {
      predictedSpeed *= exp(-4.0 * dt);
    }

    final double predVx = predictedSpeed * cos(yaw);
    final double predVy = predictedSpeed * sin(yaw);
    final double predX = x[0] + predVx * dt;
    final double predY = x[1] + predVy * dt;

    // State transition with explicit acceleration states.
    List<double> xPred = List.from(x);
    xPred[0] = predX; // x position
    xPred[1] = predY; // y position
    xPred[2] = predVx; // vx
    xPred[3] = predVy; // vy
    xPred[4] = 0.0; // ax (unused in hybrid propagation)
    xPred[5] = 0.0; // ay (unused in hybrid propagation)
    xPred[6] = yaw; // yaw

    // State transition Jacobian F
    var F = _identity(n, 1.0);
    F[0][2] = dt;
    F[1][3] = dt;
    // Acceleration states are not used to propagate velocity in this hybrid mode.

    // Propagate covariance: P = F * P * F^T + Q
    var FP = _matMul(F, P);
    var FT = _transpose(F);
    var FPFT = _matMul(FP, FT);
    P = _matAdd(FPFT, _matScale(Q, dt));

    x = xPred;

    // Update tracking metrics
    timeSinceLastGPS += dt;
    double dDist = sqrt(pow(x[2] * dt, 2) + pow(x[3] * dt, 2));
    totalDistance += dDist;

    // Confidence decays over time without GPS
    confidence = max(0.05, exp(-0.02 * timeSinceLastGPS));
  }

  /// **Étape de correction** : fusionne une mesure GPS avec la prédiction.
  ///
  /// Paramètres : [lat],[lon] position GPS (degrés), [speed] vitesse (m/s),
  /// [bearing] cap (degrés), [accuracy] précision horizontale (m).
  ///
  /// Convertit le GPS en local, construit la mesure `z = [x,y,vx,vy]`, calcule
  /// l'innovation `y = z − H·x`, le gain de Kalman `K`, met à jour `x` et `P`,
  /// puis recale le cap depuis le bearing (ou le vecteur vitesse si le bearing
  /// est indisponible). Le bruit `R` est adapté à [accuracy]. Au tout premier
  /// fix, pose le point de référence et délègue à [snapToGPS].
  ///
  /// Ne renvoie rien. Appelé par `_onGPSUpdate()` à chaque fix GPS,
  /// **hors mode VS**.
  void updateGPS(
      double lat, double lon, double speed, double bearing, double accuracy) {
    setSpeedReference(speed);
    // Set reference point if not set
    if (refLat == null || refLon == null) {
      refLat = lat;
      refLon = lon;
      snapToGPS(lat, lon, speed, bearing, accuracy);
      return;
    }

    // Convert GPS to local coordinates (meters from reference)
    var local = gpsToLocal(lat, lon);
    double zx = local[0];
    double zy = local[1];

    // GPS velocity from speed + bearing
    double bearingRad = bearing * pi / 180.0;
    double zvx = speed * sin(bearingRad);
    double zvy = speed * cos(bearingRad);

    // Measurement vector
    List<double> z = [zx, zy, zvx, zvy];

    // Measurement matrix H (4x7): maps state to measurement
    var H = _zeros2(4, n);
    H[0][0] = 1; // x
    H[1][1] = 1; // y
    H[2][2] = 1; // vx
    H[3][3] = 1; // vy

    // Adjust measurement noise based on GPS accuracy
    var R = List.generate(4, (i) => List<double>.from(R_gps[i]));
    double accSq = accuracy * accuracy;
    R[0][0] = accSq;
    R[1][1] = accSq;

    // Innovation: y = z - H*x
    var Hx = _matVecMul(H, x);
    var y = List.generate(4, (i) => z[i] - Hx[i]);

    // Innovation covariance: S = H*P*H^T + R
    var HP = _matMul(H, P);
    var HT = _transpose(H);
    var HPHT = _matMul(HP, HT);
    var S = _matAdd(HPHT, R);

    // Kalman gain
    var PHT = _matMul(P, HT);
    var Sinv = _invertMatrix(S);
    if (Sinv == null) return; // Singular matrix, skip update
    var K = _matMul(PHT, Sinv);

    // State update: x = x + K*y
    var Ky = _matVecMul(K, y);
    for (int i = 0; i < n; i++) {
      x[i] += Ky[i];
    }

    // Covariance update: P = (I - K*H)*P
    var KH = _matMul(K, H);
    var IKH = _matSub(_identity(n, 1.0), KH);
    P = _matMul(IKH, P);

    if (_hasUsableBearing(speed, bearing)) {
      x[6] = _blendAngle(x[6], _navBearingToYaw(bearing), 0.35);
    } else {
      // GPS bearing unavailable (Android returns -1) - derive yaw from the
      // velocity vector that the Kalman update just set.
      final double vMag = sqrt(x[2] * x[2] + x[3] * x[3]);
      if (vMag > 0.5) {
        x[6] = _blendAngle(x[6], atan2(x[3], x[2]), 0.35);
      }
    }

    // Reset tracking
    timeSinceLastGPS = 0;
    confidence = 1.0;
  }

  /// **Écrase** l'état pour le coller exactement sur le dernier fix GPS fiable,
  /// avant d'entrer en navigation à l'estime. Donne au mode tunnel un point de
  /// départ propre (position, vitesse, cap), contrairement à [updateGPS] qui
  /// *mélange* prédiction et mesure.
  ///
  /// Paramètres : identiques à [updateGPS] ([lat],[lon],[speed],[bearing],
  /// [accuracy]). Resserre la covariance `P` et remet `confidence` à 1.
  ///
  /// Ne renvoie rien. Appelé par `_snapKalmanToLastGPS()` (perte GPS, début de
  /// mode VS, simulation) et par [updateGPS] au premier fix.
  void snapToGPS(
      double lat, double lon, double speed, double bearing, double accuracy) {
    setSpeedReference(speed);
    if (refLat == null || refLon == null) {
      refLat = lat;
      refLon = lon;
    }

    final local = gpsToLocal(lat, lon);
    x[0] = local[0];
    x[1] = local[1];

    if (_hasUsableBearing(speed, bearing)) {
      final bearingRad = bearing * pi / 180.0;
      x[2] = speed * sin(bearingRad);
      x[3] = speed * cos(bearingRad);
      x[6] = _navBearingToYaw(bearing);
    } else if (speed <= 0.5) {
      x[2] = 0.0;
      x[3] = 0.0;
    }
    // Always reconcile yaw with the velocity vector that was just set,
    // so dead-reckoning starts in the right direction even if GPS bearing
    // was unavailable (Android heading = -1).
    final double vMag = sqrt(x[2] * x[2] + x[3] * x[3]);
    if (vMag > 0.5) {
      x[6] = atan2(x[3], x[2]);
    }

    final posVariance = max(accuracy * accuracy, 4.0);
    P[0][0] = posVariance;
    P[1][1] = posVariance;
    P[2][2] = 1.0;
    P[3][3] = 1.0;
    P[6][6] = 0.05;
    timeSinceLastGPS = 0;
    confidence = 1.0;
  }

  /// **Contrainte non-holonome** : une voiture ne peut pas glisser de côté.
  /// Impose que la composante de vitesse perpendiculaire au cap soit ≈ 0.
  ///
  /// Ne prend pas de paramètre (lit l'état courant). Correction de Kalman
  /// scalaire (mesure 1D) : covariance d'innovation `S`, gain `K`, mise à jour
  /// `x -= K·vitesseLatérale`, puis réduction de `P`. Ne fait rien si non
  /// calibré ou à l'arrêt.
  ///
  /// Ne renvoie rien. Appelé par `_processIMU()`, juste après chaque [predict].
  void updateNHC() {
    if (!isCalibrated || isStationary) return;

    final double yaw = x[6];
    // Lateral unit vector in world frame: perpendicular to forward direction (cos yaw, sin yaw)
    final double hs = -sin(yaw); // H[vx]
    final double hc = cos(yaw); // H[vy]

    final double lateralVel = x[2] * hs + x[3] * hc;

    // Innovation covariance S (scalar)
    final double S =
        hs * hs * P[2][2] + 2 * hs * hc * P[2][3] + hc * hc * P[3][3] + _rNhc;
    if (S.abs() < 1e-12) return;

    // Kalman gain K (n×1): K = P * H^T / S
    final K = List.generate(n, (i) => (P[i][2] * hs + P[i][3] * hc) / S);

    // State update: x = x - K * lateralVel
    for (int i = 0; i < n; i++) {
      x[i] -= K[i] * lateralVel;
    }

    // Covariance update: P = P - K * (H * P)
    final hp = List.generate(n, (j) => hs * P[2][j] + hc * P[3][j]);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        P[i][j] -= K[i] * hp[j];
      }
    }
  }

  /// Projette des coordonnées GPS en repère local plan **ENU** (East-North-Up),
  /// en mètres par rapport au point de référence (`refLat`, `refLon`).
  ///
  /// Paramètres : [lat],[lon] en degrés.
  /// Renvoie `[x_est, y_nord]` en mètres (`[0,0]` si pas de référence).
  /// Appelé par [updateGPS] et [snapToGPS].
  List<double> gpsToLocal(double lat, double lon) {
    if (refLat == null || refLon == null) return [0, 0];

    double dLat = (lat - refLat!) * pi / 180.0;
    double dLon = (lon - refLon!) * pi / 180.0;
    double meanLat = (lat + refLat!) / 2.0 * pi / 180.0;

    // Earth radius in meters
    const double R = 6371000;

    double x = dLon * R * cos(meanLat); // East
    double y = dLat * R; // North

    return [x, y];
  }

  /// Conversion inverse de [gpsToLocal] : du repère local (mètres) vers le GPS.
  ///
  /// Paramètres : [localX],[localY] en mètres.
  /// Renvoie `[lat, lon]` en degrés.
  /// Appelé par le getter [estimatedPosition].
  List<double> localToGPS(double localX, double localY) {
    if (refLat == null || refLon == null) return [0, 0];

    const double R = 6371000;
    double meanLat = refLat! * pi / 180.0;

    double dLat = localY / R;
    double dLon = localX / (R * cos(meanLat));

    return [refLat! + dLat * 180.0 / pi, refLon! + dLon * 180.0 / pi];
  }

  /// Position estimée actuelle convertie en GPS `[lat, lon]`.
  /// Lue par `NavigationService` (état, trace, CSV).
  List<double> get estimatedPosition => localToGPS(x[0], x[1]);

  /// Module de la vitesse actuelle en m/s (`sqrt(vx² + vy²)`).
  double get speed => sqrt(x[2] * x[2] + x[3] * x[3]);

  /// Cap actuel en degrés (cap navigation : 0° = Nord), converti depuis le yaw.
  double get heading => _yawToNavBearing(x[6]);

  /// Rayon d'incertitude sur la position en mètres (`sqrt(P[0][0] + P[1][1])`).
  /// Sert à dessiner le cercle d'incertitude sur la carte.
  double get positionUncertainty => sqrt(P[0][0] + P[1][1]);

  /// Mémorise la dernière vitesse GPS fiable dans `_speedRefMps` (bornée
  /// 0–70 m/s). **C'est l'entrée de la dérivation hybride** : la cible de
  /// vitesse vers laquelle [predict] relaxe pendant la perte GPS.
  ///
  /// Paramètre : [speedMps] vitesse GPS (m/s) ; ignorée si négative/non finie.
  /// Ne renvoie rien. Appelé par [updateGPS] et [snapToGPS].
  void setSpeedReference(double speedMps) {
    if (!speedMps.isFinite || speedMps < 0) return;
    _speedRefMps = speedMps.clamp(0.0, 70.0);
    _hasSpeedRef = true;
  }


  /// Matrice identité `size × size` multipliée par [scale]
  /// (diagonale = [scale], reste = 0). Outil d'algèbre linéaire interne.
  static List<List<double>> _identity(int size, double scale) {
    return List.generate(
        size, (i) => List.generate(size, (j) => i == j ? scale : 0.0));
  }

  /// Matrice nulle carrée `size × size`.
  static List<List<double>> _zeros(int size) {
    return List.generate(size, (_) => List.filled(size, 0.0));
  }

  /// Matrice nulle rectangulaire `rows × cols`.
  static List<List<double>> _zeros2(int rows, int cols) {
    return List.generate(rows, (_) => List.filled(cols, 0.0));
  }

  /// Transposée de la matrice [m] (lignes ↔ colonnes).
  static List<List<double>> _transpose(List<List<double>> m) {
    int rows = m.length;
    int cols = m[0].length;
    return List.generate(cols, (i) => List.generate(rows, (j) => m[j][i]));
  }

  /// Produit matriciel `A · B` ([a] de taille m×k, [b] de taille k×p).
  static List<List<double>> _matMul(
      List<List<double>> a, List<List<double>> b) {
    int rows = a.length;
    int cols = b[0].length;
    int inner = b.length;
    var result = _zeros2(rows, cols);
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        for (int k = 0; k < inner; k++) {
          result[i][j] += a[i][k] * b[k][j];
        }
      }
    }
    return result;
  }

  /// Produit matrice × vecteur `M · v`. Renvoie un vecteur.
  static List<double> _matVecMul(List<List<double>> m, List<double> v) {
    return List.generate(m.length, (i) {
      double sum = 0;
      for (int j = 0; j < v.length; j++) {
        sum += m[i][j] * v[j];
      }
      return sum;
    });
  }

  /// Somme matricielle terme à terme `A + B`.
  static List<List<double>> _matAdd(
      List<List<double>> a, List<List<double>> b) {
    return List.generate(
        a.length, (i) => List.generate(a[0].length, (j) => a[i][j] + b[i][j]));
  }

  /// Différence matricielle terme à terme `A − B`.
  static List<List<double>> _matSub(
      List<List<double>> a, List<List<double>> b) {
    return List.generate(
        a.length, (i) => List.generate(a[0].length, (j) => a[i][j] - b[i][j]));
  }

  /// Multiplie chaque terme de la matrice [m] par le scalaire [s].
  static List<List<double>> _matScale(List<List<double>> m, double s) {
    return List.generate(
        m.length, (i) => List.generate(m[0].length, (j) => m[i][j] * s));
  }

  /// Inverse une petite matrice par élimination de Gauss-Jordan (pivot partiel).
  ///
  /// Paramètre : [matrix] carrée.
  /// Renvoie la matrice inverse, ou **`null`** si la matrice est singulière
  /// (non inversible) — l'appelant saute alors la mise à jour.
  /// Utilisé par [updateGPS] pour inverser la covariance d'innovation `S`.
  static List<List<double>>? _invertMatrix(List<List<double>> matrix) {
    int n = matrix.length;
    var aug = List.generate(
        n,
        (i) => List.generate(
            2 * n, (j) => j < n ? matrix[i][j] : (i == j - n ? 1.0 : 0.0)));

    for (int col = 0; col < n; col++) {
      // Find pivot
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > maxVal) {
          maxVal = aug[row][col].abs();
          maxRow = row;
        }
      }
      if (maxVal < 1e-12) return null; // Singular

      // Swap rows
      var temp = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = temp;

      // Scale pivot row
      double pivot = aug[col][col];
      for (int j = 0; j < 2 * n; j++) {
        aug[col][j] /= pivot;
      }

      // Eliminate column
      for (int row = 0; row < n; row++) {
        if (row == col) continue;
        double factor = aug[row][col];
        for (int j = 0; j < 2 * n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    return List.generate(n, (i) => List.generate(n, (j) => aug[i][j + n]));
  }

  /// Moyenne arithmétique d'une liste de valeurs.
  static double _mean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Indique si le cap GPS est exploitable : vrai si [speed] > 1,5 m/s et
  /// [bearing] valide (0–360). À basse vitesse, le cap GPS est trop bruité.
  /// Utilisé par [updateGPS] et [snapToGPS].
  static bool _hasUsableBearing(double speed, double bearing) {
    return speed > 1.5 && bearing.isFinite && bearing >= 0 && bearing <= 360;
  }

  /// Convertit un **cap navigation** (0° = Nord, sens horaire) en **yaw
  /// mathématique** (0° = Est, sens trigo) : `(90 − bearing)·π/180`. En rad.
  static double _navBearingToYaw(double bearingDeg) {
    return _normalizeAngle((90.0 - bearingDeg) * pi / 180.0);
  }

  /// Conversion inverse de [_navBearingToYaw] : yaw (rad) → cap navigation
  /// (degrés, 0–360). Utilisé par le getter [heading].
  static double _yawToNavBearing(double yawRad) {
    final bearing = 90.0 - yawRad * 180.0 / pi;
    return (bearing % 360.0 + 360.0) % 360.0;
  }

  /// Interpole entre deux angles [from] et [to] en gérant le passage par ±180°.
  /// [alpha] = poids du nouvel angle (0 = reste à [from], 1 = va à [to]).
  /// Sert à recaler doucement le cap dans [updateGPS]. Renvoie un angle en rad.
  static double _blendAngle(double from, double to, double alpha) {
    final delta = _normalizeAngle(to - from);
    return _normalizeAngle(from + alpha * delta);
  }

  /// Ramène un angle dans l'intervalle ]−π, π]. Appelé partout où on manipule
  /// le cap pour éviter l'accumulation hors bornes.
  static double _normalizeAngle(double angle) {
    while (angle > pi) {
      angle -= 2 * pi;
    }
    while (angle <= -pi) {
      angle += 2 * pi;
    }
    return angle;
  }

  /// Réinitialise **tout** le filtre à son état de départ : état `x`,
  /// covariance `P`, biais, calibration, références GPS et métriques.
  ///
  /// Ne prend rien, ne renvoie rien. Appelé par `NavigationService.start()`
  /// et `NavigationService.reset()` en début de session.
  void reset() {
    x = List.filled(n, 0.0);
    P = _identity(n, 100.0);
    refLat = null;
    refLon = null;
    isCalibrated = false;
    _calibrationSamples = 0;
    _calAx.clear();
    _calAy.clear();
    _calAz.clear();
    _calGx.clear();
    _calGy.clear();
    _calGz.clear();
    _filteredAx = 0;
    _filteredAy = 0;
    _filteredAz = 0;
    _lowPassInitialized = false;
    _recentAccelMagnitudes.clear();
    _stationarySamples = 0;
    isStationary = false;
    totalDistance = 0;
    timeSinceLastGPS = 0;
    confidence = 1.0;
    _speedRefMps = 0.0;
    _hasSpeedRef = false;
  }
}
