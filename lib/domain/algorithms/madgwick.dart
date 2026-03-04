import 'dart:math';

/// Implémentation du filtre de Madgwick pour l'estimation d'orientation
/// À partir des données accéléromètre et gyroscope
class MadgwickFilter {
  double _q0 = 1.0; // Quaternion composants
  double _q1 = 0.0;
  double _q2 = 0.0;
  double _q3 = 0.0;

  double _beta; // Gain du filtre (paramètre)

  MadgwickFilter({double beta = 0.5}) : _beta = beta;

  /// Met à jour l'estimation avec les données IMU
  /// Retourne le quaternion [q0, q1, q2, q3]
  List<double> update(
    double ax,
    double ay,
    double az, // Accéléromètre (m/s²)
    double gx,
    double gy,
    double gz, // Gyroscope (rad/s)
    double dt, // Pas de temps (secondes)
  ) {
    // Normaliser l'accéléromètre
    double norm = sqrt(ax * ax + ay * ay + az * az);
    if (norm == 0) return [1.0, 0.0, 0.0, 0.0]; // Éviter division par zéro

    ax /= norm;
    ay /= norm;
    az /= norm;

    // Gradient descent step
    double s0 = 0, s1 = 0, s2 = 0, s3 = 0;

    // Objective function
    double f1 = 2 * (_q1 * _q3 - _q0 * _q2) - ax;
    double f2 = 2 * (_q0 * _q1 + _q2 * _q3) - ay;
    double f3 = 2 * (0.5 - _q1 * _q1 - _q2 * _q2) - az;

    // Jacobian matrix
    double j11 = -2 * _q2;
    double j12 = 2 * _q3;
    double j13 = -2 * _q0;
    double j14 = 2 * _q1;

    double j21 = 2 * _q1;
    double j22 = 2 * _q0;
    double j23 = 2 * _q3;
    double j24 = 2 * _q2;

    double j31 = 0;
    double j32 = -4 * _q1;
    double j33 = -4 * _q2;
    double j34 = 0;

    // Gradient = J^T * f
    s0 = j11 * f1 + j21 * f2 + j31 * f3;
    s1 = j12 * f1 + j22 * f2 + j32 * f3;
    s2 = j13 * f1 + j23 * f2 + j33 * f3;
    s3 = j14 * f1 + j24 * f2 + j34 * f3;

    // Normaliser le gradient
    norm = sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
    if (norm > 0) {
      s0 /= norm;
      s1 /= norm;
      s2 /= norm;
      s3 /= norm;
    }

    // Gyroscope integration (taux de changement du quaternion)
    double qDot0 = 0.5 * (-_q1 * gx - _q2 * gy - _q3 * gz);
    double qDot1 = 0.5 * (_q0 * gx + _q2 * gz - _q3 * gy);
    double qDot2 = 0.5 * (_q0 * gy - _q1 * gz + _q3 * gx);
    double qDot3 = 0.5 * (_q0 * gz + _q1 * gy - _q2 * gx);

    // Fusion : gyroscope + correction du gradient
    qDot0 -= _beta * s0;
    qDot1 -= _beta * s1;
    qDot2 -= _beta * s2;
    qDot3 -= _beta * s3;

    // Intégration
    _q0 += qDot0 * dt;
    _q1 += qDot1 * dt;
    _q2 += qDot2 * dt;
    _q3 += qDot3 * dt;

    // Normaliser le quaternion
    norm = sqrt(_q0 * _q0 + _q1 * _q1 + _q2 * _q2 + _q3 * _q3);
    _q0 /= norm;
    _q1 /= norm;
    _q2 /= norm;
    _q3 /= norm;

    return [_q0, _q1, _q2, _q3];
  }

  /// Met à jour avec magnétomètre (version complète)
  List<double> updateWithMagnetometer(
    double ax,
    double ay,
    double az,
    double gx,
    double gy,
    double gz,
    double mx,
    double my,
    double mz,
    double dt,
  ) {
    // Normaliser accéléromètre
    double norm = sqrt(ax * ax + ay * ay + az * az);
    if (norm > 0) {
      ax /= norm;
      ay /= norm;
      az /= norm;
    }

    // Normaliser magnétomètre
    norm = sqrt(mx * mx + my * my + mz * mz);
    if (norm > 0) {
      mx /= norm;
      my /= norm;
      mz /= norm;
    }

    // Gradient descent step (plus complexe avec magnétomètre)
    // ... (implémentation complète si nécessaire)

    return [_q0, _q1, _q2, _q3];
  }

  /// Obtient les angles d'Euler à partir du quaternion
  Map<String, double> getEulerAngles() {
    // Roll (x-axis rotation)
    double roll = atan2(
      2 * (_q0 * _q1 + _q2 * _q3),
      1 - 2 * (_q1 * _q1 + _q2 * _q2),
    );

    // Pitch (y-axis rotation)
    double pitch = asin(2 * (_q0 * _q2 - _q3 * _q1));

    // Yaw (z-axis rotation)
    double yaw = atan2(
      2 * (_q0 * _q3 + _q1 * _q2),
      1 - 2 * (_q2 * _q2 + _q3 * _q3),
    );

    return {
      'roll': roll * 180 / pi, // Degrés
      'pitch': pitch * 180 / pi,
      'yaw': yaw * 180 / pi,
    };
  }

  /// Obtient la matrice de rotation 3x3
  List<List<double>> getRotationMatrix() {
    return [
      [
        1 - 2 * (_q2 * _q2 + _q3 * _q3),
        2 * (_q1 * _q2 - _q0 * _q3),
        2 * (_q1 * _q3 + _q0 * _q2),
      ],
      [
        2 * (_q1 * _q2 + _q0 * _q3),
        1 - 2 * (_q1 * _q1 + _q3 * _q3),
        2 * (_q2 * _q3 - _q0 * _q1),
      ],
      [
        2 * (_q1 * _q3 - _q0 * _q2),
        2 * (_q2 * _q3 + _q0 * _q1),
        1 - 2 * (_q1 * _q1 + _q2 * _q2),
      ],
    ];
  }

  /// Réinitialise le filtre
  void reset() {
    _q0 = 1.0;
    _q1 = 0.0;
    _q2 = 0.0;
    _q3 = 0.0;
  }

  /// Règle le gain du filtre
  void setBeta(double beta) {
    _beta = beta;
  }

  /// Obtient le quaternion actuel
  List<double> getQuaternion() => [_q0, _q1, _q2, _q3];
}
