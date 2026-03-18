import 'dart:math';
import 'package:flutter/material.dart';

/// Gère l'intégration pour passer de l'accélération à la position
class TrajectoryIntegrator {
  // État
  double _vx = 0.0; // Vitesse selon X
  double _vy = 0.0; // Vitesse selon Y
  double _vz = 0.0; // Vitesse selon Z

  double _px = 0.0; // Position selon X
  double _py = 0.0; // Position selon Y
  double _pz = 0.0; // Position selon Z

  double _lastTimestamp = 0.0;

  // Détection d'arrêt (ZUPT)
  bool _isStationary = false;
  double _stationaryThreshold = 0.5; // m/s²
  int _stationaryCounter = 0;
  static const int _stationaryFrames = 10; // Frames pour confirmer arrêt

  // Filtrage
  final List<double> _velocityBuffer = [];
  static const int _velocityBufferSize = 5;

  // Biais estimés
  double _biasX = 0.0;
  double _biasY = 0.0;
  double _biasZ = 0.0;
  final List<double> _accelerationBuffer = [];
  static const int _calibrationFrames = 100;

  /// Calibration initiale (téléphone immobile)
  void calibrate(List<double> accelerations) {
    if (accelerations.length < 10) return;

    // Calculer la moyenne pour estimer le biais
    double sumX = 0, sumY = 0, sumZ = 0;
    for (int i = 0; i < accelerations.length; i += 3) {
      sumX += accelerations[i];
      sumY += accelerations[i + 1];
      sumZ += accelerations[i + 2];
    }

    int count = accelerations.length ~/ 3;
    _biasX = sumX / count;
    _biasY = sumY / count;
    _biasZ = sumZ / count - 9.81; // Soustraire gravité
  }

  /// Intègre l'accélération pour obtenir la position
  /// [ax, ay, az] : accélérations dans le repère global (déjà gravité soustraite)
  /// [q0, q1, q2, q3] : quaternion d'orientation
  /// [dt] : pas de temps en secondes
  Offset integrate(
    double ax,
    double ay,
    double az,
    List<double> quaternion,
    double dt,
  ) {
    // Appliquer la rotation pour passer du repère capteur au repère global
    final rotated = _rotateVector(ax, ay, az, quaternion);

    // Soustraire le biais
    double accX = rotated[0] - _biasX;
    double accY = rotated[1] - _biasY;
    double accZ = rotated[2] - _biasZ;

    // Détection d'arrêt (ZUPT)
    double magnitude = sqrt(accX * accX + accY * accY + accZ * accZ);

    if (magnitude < _stationaryThreshold) {
      _stationaryCounter++;
      if (_stationaryCounter > _stationaryFrames) {
        _isStationary = true;
        // Remettre les vitesses à zéro
        _vx = 0;
        _vy = 0;
        _vz = 0;
      }
    } else {
      _stationaryCounter = 0;
      _isStationary = false;
    }

    if (!_isStationary) {
      // Intégration vitesse (méthode des trapèzes)
      _vx += accX * dt;
      _vy += accY * dt;
      _vz += accZ * dt;

      // Filtrage de la vitesse
      _velocityBuffer.add(_vx);
      if (_velocityBuffer.length > _velocityBufferSize) {
        _velocityBuffer.removeAt(0);
      }

      // Utiliser la vitesse filtrée
      double filteredVx =
          _velocityBuffer.reduce((a, b) => a + b) / _velocityBuffer.length;

      // Intégration position
      _px += filteredVx * dt;
      _py += _vy * dt; // Simplifié pour l'exemple
      _pz += _vz * dt;
    }

    _lastTimestamp = DateTime.now().millisecondsSinceEpoch.toDouble();

    return Offset(_px, _py);
  }

  /// Rotation d'un vecteur par un quaternion
  List<double> _rotateVector(double x, double y, double z, List<double> q) {
    double q0 = q[0], q1 = q[1], q2 = q[2], q3 = q[3];

    // Formule: v' = q * v * q_conj
    double rx =
        (q0 * q0 + q1 * q1 - q2 * q2 - q3 * q3) * x +
        2 * (q1 * q2 - q0 * q3) * y +
        2 * (q1 * q3 + q0 * q2) * z;

    double ry =
        2 * (q1 * q2 + q0 * q3) * x +
        (q0 * q0 - q1 * q1 + q2 * q2 - q3 * q3) * y +
        2 * (q2 * q3 - q0 * q1) * z;

    double rz =
        2 * (q1 * q3 - q0 * q2) * x +
        2 * (q2 * q3 + q0 * q1) * y +
        (q0 * q0 - q1 * q1 - q2 * q2 + q3 * q3) * z;

    return [rx, ry, rz];
  }

  /// Intègre avec détection de pas (pour la marche)
  Offset integrateWithStepDetection(
    double ax,
    double ay,
    double az,
    List<double> quaternion,
    double dt,
  ) {
    // Version simplifiée pour la marche
    // Détecter les pics d'accélération pour compter les pas
    double magnitude = sqrt(ax * ax + ay * ay + az * az);

    // Détection de pas simple (à améliorer)
    if (magnitude > 12.0) {
      // Seuil de détection de pas
      // Avancer d'une longueur de pas moyenne
      double stepLength = 0.7; // 70 cm par pas

      // Utiliser le cap pour déterminer la direction
      double yaw = _getYawFromQuaternion(quaternion);

      _px += stepLength * sin(yaw);
      _py += stepLength * cos(yaw);
    }

    return Offset(_px, _py);
  }

  double _getYawFromQuaternion(List<double> q) {
    return atan2(
      2 * (q[0] * q[3] + q[1] * q[2]),
      1 - 2 * (q[2] * q[2] + q[3] * q[3]),
    );
  }

  /// Réinitialise la position
  void resetPosition() {
    _px = 0;
    _py = 0;
    _pz = 0;
    _vx = 0;
    _vy = 0;
    _vz = 0;
    _velocityBuffer.clear();
  }

  /// Réinitialise complètement
  void reset() {
    resetPosition();
    _biasX = 0;
    _biasY = 0;
    _biasZ = 0;
    _stationaryCounter = 0;
    _isStationary = false;
  }

  // Getters
  double get vx => _vx;
  double get vy => _vy;
  double get vz => _vz;
  double get px => _px;
  double get py => _py;
  double get pz => _pz;
  bool get isStationary => _isStationary;

  /// Configure le seuil de détection d'arrêt
  void setStationaryThreshold(double threshold) {
    _stationaryThreshold = threshold;
  }
}

/// Version avec filtre de Kalman simplifié pour meilleure précision
class KalmanIntegrator {
  // État: [px, py, vx, vy]
  List<double> _state = [0, 0, 0, 0];

  // Matrice de covariance
  List<List<double>> _covariance = [
    [1, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 1, 0],
    [0, 0, 0, 1],
  ];

  double _dt = 0.01; // Pas de temps par défaut

  /// Met à jour avec mesure d'accélération
  void update(double ax, double ay, double dt) {
    _dt = dt;

    // Matrice de transition
    List<List<double>> F = [
      [1, 0, dt, 0],
      [0, 1, 0, dt],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ];

    // Prédiction
    _state = _multiplyMatrixVector(F, _state);

    // Bruit de processus
    List<List<double>> Q = [
      [dt * dt * dt / 3, 0, dt * dt / 2, 0],
      [0, dt * dt * dt / 3, 0, dt * dt / 2],
      [dt * dt / 2, 0, dt, 0],
      [0, dt * dt / 2, 0, dt],
    ];

    // Mettre à jour covariance
    _covariance = _addMatrix(
      _multiplyMatrix(_multiplyMatrix(F, _covariance), _transpose(F)),
      Q,
    );

    // Mesure (accélération)
    List<List<double>> H = [
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ];

    List<double> z = [ax, ay];
    List<List<double>> R = [
      [0.1, 0],
      [0, 0.1],
    ]; // Bruit de mesure

    // Innovation
    List<double> y = _subtractVector(z, _multiplyMatrixVector(H, _state));

    // Gain de Kalman
    List<List<double>> S = _addMatrix(
      _multiplyMatrix(_multiplyMatrix(H, _covariance), _transpose(H)),
      R,
    );
    List<List<double>> K = _multiplyMatrix(
      _multiplyMatrix(_covariance, _transpose(H)),
      _inverse2x2(S),
    );

    // Correction
    _state = _addVector(_state, _multiplyMatrixVector(K, y));

    // Mettre à jour covariance
    _covariance = _multiplyMatrix(
      _subtractMatrix(_identity(4), _multiplyMatrix(K, H)),
      _covariance,
    );
  }

  // Opérations matricielles (simplifiées)
  List<double> _multiplyMatrixVector(List<List<double>> M, List<double> v) {
    List<double> result = List.filled(v.length, 0);
    for (int i = 0; i < M.length; i++) {
      for (int j = 0; j < v.length; j++) {
        result[i] += M[i][j] * v[j];
      }
    }
    return result;
  }

  List<List<double>> _multiplyMatrix(
    List<List<double>> A,
    List<List<double>> B,
  ) {
    int n = A.length;
    int m = B[0].length;
    int p = B.length;

    List<List<double>> result = List.generate(n, (_) => List.filled(m, 0));

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < m; j++) {
        for (int k = 0; k < p; k++) {
          result[i][j] += A[i][k] * B[k][j];
        }
      }
    }
    return result;
  }

  List<List<double>> _transpose(List<List<double>> M) {
    int rows = M.length;
    int cols = M[0].length;

    List<List<double>> result = List.generate(
      cols,
      (_) => List.filled(rows, 0),
    );

    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        result[j][i] = M[i][j];
      }
    }
    return result;
  }

  List<List<double>> _addMatrix(List<List<double>> A, List<List<double>> B) {
    int rows = A.length;
    int cols = A[0].length;

    List<List<double>> result = List.generate(
      rows,
      (_) => List.filled(cols, 0),
    );

    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        result[i][j] = A[i][j] + B[i][j];
      }
    }
    return result;
  }

  List<List<double>> _subtractMatrix(
    List<List<double>> A,
    List<List<double>> B,
  ) {
    int rows = A.length;
    int cols = A[0].length;

    List<List<double>> result = List.generate(
      rows,
      (_) => List.filled(cols, 0),
    );

    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        result[i][j] = A[i][j] - B[i][j];
      }
    }
    return result;
  }

  List<double> _addVector(List<double> a, List<double> b) {
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]];
  }

  List<double> _subtractVector(List<double> a, List<double> b) {
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]];
  }

  List<List<double>> _identity(int n) {
    return List.generate(n, (i) => List.generate(n, (j) => i == j ? 1.0 : 0.0));
  }

  List<List<double>> _inverse2x2(List<List<double>> M) {
    double det = M[0][0] * M[1][1] - M[0][1] * M[1][0];
    return [
      [M[1][1] / det, -M[0][1] / det],
      [-M[1][0] / det, M[0][0] / det],
    ];
  }

  // Getters
  Offset get position => Offset(_state[0], _state[1]);
  double get vx => _state[2];
  double get vy => _state[3];
}
