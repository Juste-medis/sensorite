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

  IMUKalmanFilter()
      : x = List.filled(n, 0.0),
        P = _identity(n, 100.0),
        Q = _zeros(n),
        R_gps = _zeros(4),
        R_imu = _zeros(3) {
    _initProcessNoise();
    _initMeasurementNoise();
  }

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

  /// Add calibration sample (call while device is stationary)
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

  double get calibrationProgress => _calibrationSamples / calibrationTarget;

  /// Low-pass filter for accelerometer data
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

  /// Detect if the device is stationary using accelerometer variance
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

  /// Predict step using IMU data
  /// [ax, ay, az]: accelerometer in m/s² (device frame)
  /// [gx, gy, gz]: gyroscope in rad/s (device frame)
  /// [dt]: time step in seconds
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

  /// Update step with GPS measurement
  /// [lat, lon]: GPS coordinates in degrees
  /// [speed]: GPS speed in m/s
  /// [bearing]: GPS bearing in degrees
  /// [accuracy]: GPS horizontal accuracy in meters
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

  /// Force the EKF state to the latest reliable GPS fix before entering
  /// dead reckoning. This gives tunnel mode a clean position, velocity and yaw.
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

  /// Non-Holonomic Constraint update: vehicle cannot move laterally.
  /// Constrains the velocity component perpendicular to the heading to ~0.
  /// Call this after each predict() step at IMU rate.
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

  /// Convert GPS coordinates to local ENU (East-North-Up) coordinates
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

  /// Convert local ENU coordinates back to GPS
  List<double> localToGPS(double localX, double localY) {
    if (refLat == null || refLon == null) return [0, 0];

    const double R = 6371000;
    double meanLat = refLat! * pi / 180.0;

    double dLat = localY / R;
    double dLon = localX / (R * cos(meanLat));

    return [refLat! + dLat * 180.0 / pi, refLon! + dLon * 180.0 / pi];
  }

  /// Get current estimated GPS position
  List<double> get estimatedPosition => localToGPS(x[0], x[1]);

  /// Get current velocity magnitude in m/s
  double get speed => sqrt(x[2] * x[2] + x[3] * x[3]);

  /// Get current heading in degrees
  double get heading => _yawToNavBearing(x[6]);

  /// Get position uncertainty radius in meters
  double get positionUncertainty => sqrt(P[0][0] + P[1][1]);

  /// Refresh speed reference from latest reliable GPS speed.
  /// Used to stabilize dead-reckoning velocity scale.
  void setSpeedReference(double speedMps) {
    if (!speedMps.isFinite || speedMps < 0) return;
    _speedRefMps = speedMps.clamp(0.0, 70.0);
    _hasSpeedRef = true;
  }


  static List<List<double>> _identity(int size, double scale) {
    return List.generate(
        size, (i) => List.generate(size, (j) => i == j ? scale : 0.0));
  }

  static List<List<double>> _zeros(int size) {
    return List.generate(size, (_) => List.filled(size, 0.0));
  }

  static List<List<double>> _zeros2(int rows, int cols) {
    return List.generate(rows, (_) => List.filled(cols, 0.0));
  }

  static List<List<double>> _transpose(List<List<double>> m) {
    int rows = m.length;
    int cols = m[0].length;
    return List.generate(cols, (i) => List.generate(rows, (j) => m[j][i]));
  }

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

  static List<double> _matVecMul(List<List<double>> m, List<double> v) {
    return List.generate(m.length, (i) {
      double sum = 0;
      for (int j = 0; j < v.length; j++) {
        sum += m[i][j] * v[j];
      }
      return sum;
    });
  }

  static List<List<double>> _matAdd(
      List<List<double>> a, List<List<double>> b) {
    return List.generate(
        a.length, (i) => List.generate(a[0].length, (j) => a[i][j] + b[i][j]));
  }

  static List<List<double>> _matSub(
      List<List<double>> a, List<List<double>> b) {
    return List.generate(
        a.length, (i) => List.generate(a[0].length, (j) => a[i][j] - b[i][j]));
  }

  static List<List<double>> _matScale(List<List<double>> m, double s) {
    return List.generate(
        m.length, (i) => List.generate(m[0].length, (j) => m[i][j] * s));
  }

  /// Invert a small matrix using Gauss-Jordan elimination
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

  static double _mean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  static bool _hasUsableBearing(double speed, double bearing) {
    return speed > 1.5 && bearing.isFinite && bearing >= 0 && bearing <= 360;
  }

  static double _navBearingToYaw(double bearingDeg) {
    return _normalizeAngle((90.0 - bearingDeg) * pi / 180.0);
  }

  static double _yawToNavBearing(double yawRad) {
    final bearing = 90.0 - yawRad * 180.0 / pi;
    return (bearing % 360.0 + 360.0) % 360.0;
  }

  static double _blendAngle(double from, double to, double alpha) {
    final delta = _normalizeAngle(to - from);
    return _normalizeAngle(from + alpha * delta);
  }

  static double _normalizeAngle(double angle) {
    while (angle > pi) {
      angle -= 2 * pi;
    }
    while (angle <= -pi) {
      angle += 2 * pi;
    }
    return angle;
  }

  /// Reset the filter state
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
