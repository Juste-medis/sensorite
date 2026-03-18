import 'dart:math';

/// Implémentation du filtre de Mahony (complémentaire non-linéaire)
/// Alternative plus robuste au filtre de Madgwick
class MahonyFilter {
  double _q0 = 1.0; // Quaternion
  double _q1 = 0.0;
  double _q2 = 0.0;
  double _q3 = 0.0;

  double _integralFBx = 0.0; // Termes intégraux pour correction
  double _integralFBy = 0.0;
  double _integralFBz = 0.0;

  double _kp; // Gain proportionnel
  double _ki; // Gain intégral

  MahonyFilter({double kp = 0.5, double ki = 0.0}) : _kp = kp, _ki = ki;

  /// Met à jour avec accéléromètre et gyroscope
  List<double> update(
    double ax,
    double ay,
    double az,
    double gx,
    double gy,
    double gz,
    double dt,
  ) {
    // Normaliser l'accéléromètre
    double norm = sqrt(ax * ax + ay * ay + az * az);
    if (norm == 0) return [1.0, 0.0, 0.0, 0.0];

    ax /= norm;
    ay /= norm;
    az /= norm;

    // Erreur estimée par l'accéléromètre
    double vx = 2 * (_q1 * _q3 - _q0 * _q2);
    double vy = 2 * (_q0 * _q1 + _q2 * _q3);
    double vz = _q0 * _q0 - _q1 * _q1 - _q2 * _q2 + _q3 * _q3;

    // Produit vectoriel (erreur)
    double ex = ay * vz - az * vy;
    double ey = az * vx - ax * vz;
    double ez = ax * vy - ay * vx;

    // Terme intégral
    if (_ki > 0) {
      _integralFBx += _ki * ex * dt;
      _integralFBy += _ki * ey * dt;
      _integralFBz += _ki * ez * dt;

      // Appliquer correction
      gx += _integralFBx;
      gy += _integralFBy;
      gz += _integralFBz;
    }

    // Correction proportionnelle
    gx += _kp * ex;
    gy += _kp * ey;
    gz += _kp * ez;

    // Taux de changement du quaternion
    double qDot0 = 0.5 * (-_q1 * gx - _q2 * gy - _q3 * gz);
    double qDot1 = 0.5 * (_q0 * gx + _q2 * gz - _q3 * gy);
    double qDot2 = 0.5 * (_q0 * gy - _q1 * gz + _q3 * gx);
    double qDot3 = 0.5 * (_q0 * gz + _q1 * gy - _q2 * gx);

    // Intégration
    _q0 += qDot0 * dt;
    _q1 += qDot1 * dt;
    _q2 += qDot2 * dt;
    _q3 += qDot3 * dt;

    // Normalisation
    norm = sqrt(_q0 * _q0 + _q1 * _q1 + _q2 * _q2 + _q3 * _q3);
    _q0 /= norm;
    _q1 /= norm;
    _q2 /= norm;
    _q3 /= norm;

    return [_q0, _q1, _q2, _q3];
  }

  /// Met à jour avec magnétomètre
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

    // Calculer la direction de référence
    double hx =
        2 * mx * (0.5 - _q2 * _q2 - _q3 * _q3) +
        2 * my * (_q1 * _q2 - _q0 * _q3) +
        2 * mz * (_q1 * _q3 + _q0 * _q2);

    double hy =
        2 * mx * (_q1 * _q2 + _q0 * _q3) +
        2 * my * (0.5 - _q1 * _q1 - _q3 * _q3) +
        2 * mz * (_q2 * _q3 - _q0 * _q1);

    double bx = sqrt(hx * hx + hy * hy);
    double bz =
        2 * mx * (_q1 * _q3 - _q0 * _q2) +
        2 * my * (_q2 * _q3 + _q0 * _q1) +
        2 * mz * (0.5 - _q1 * _q1 - _q2 * _q2);

    // Estimations
    double wx =
        2 * bx * (0.5 - _q2 * _q2 - _q3 * _q3) +
        2 * bz * (_q1 * _q3 - _q0 * _q2);
    double wy =
        2 * bx * (_q1 * _q2 - _q0 * _q3) + 2 * bz * (_q0 * _q1 + _q2 * _q3);
    double wz =
        2 * bx * (_q0 * _q2 + _q1 * _q3) +
        2 * bz * (0.5 - _q1 * _q1 - _q2 * _q2);

    // Erreur
    double ex = ay * wz - az * wy + (my * wz - mz * wy);
    double ey = az * wx - ax * wz + (mz * wx - mx * wz);
    double ez = ax * wy - ay * wx + (mx * wy - my * wx);

    // Intégral et correction (similaire à update simple)
    if (_ki > 0) {
      _integralFBx += _ki * ex * dt;
      _integralFBy += _ki * ey * dt;
      _integralFBz += _ki * ez * dt;

      gx += _integralFBx;
      gy += _integralFBy;
      gz += _integralFBz;
    }

    gx += _kp * ex;
    gy += _kp * ey;
    gz += _kp * ez;

    // Intégration quaternion (identique)
    double qDot0 = 0.5 * (-_q1 * gx - _q2 * gy - _q3 * gz);
    double qDot1 = 0.5 * (_q0 * gx + _q2 * gz - _q3 * gy);
    double qDot2 = 0.5 * (_q0 * gy - _q1 * gz + _q3 * gx);
    double qDot3 = 0.5 * (_q0 * gz + _q1 * gy - _q2 * gx);

    _q0 += qDot0 * dt;
    _q1 += qDot1 * dt;
    _q2 += qDot2 * dt;
    _q3 += qDot3 * dt;

    norm = sqrt(_q0 * _q0 + _q1 * _q1 + _q2 * _q2 + _q3 * _q3);
    _q0 /= norm;
    _q1 /= norm;
    _q2 /= norm;
    _q3 /= norm;

    return [_q0, _q1, _q2, _q3];
  }

  /// Obtient les angles d'Euler
  Map<String, double> getEulerAngles() {
    double roll = atan2(
      2 * (_q0 * _q1 + _q2 * _q3),
      1 - 2 * (_q1 * _q1 + _q2 * _q2),
    );

    double pitch = asin(2 * (_q0 * _q2 - _q3 * _q1));

    double yaw = atan2(
      2 * (_q0 * _q3 + _q1 * _q2),
      1 - 2 * (_q2 * _q2 + _q3 * _q3),
    );

    return {
      'roll': roll * 180 / pi,
      'pitch': pitch * 180 / pi,
      'yaw': yaw * 180 / pi,
    };
  }

  /// Réinitialise
  void reset() {
    _q0 = 1.0;
    _q1 = 0.0;
    _q2 = 0.0;
    _q3 = 0.0;
    _integralFBx = 0.0;
    _integralFBy = 0.0;
    _integralFBz = 0.0;
  }

  /// Règle les gains
  void setGains(double kp, double ki) {
    _kp = kp;
    _ki = ki;
  }
}
