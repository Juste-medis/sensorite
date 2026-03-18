import 'package:location/location.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'dart:math' as math;

const double _earthRadiusMeters = 6378137.0;
const double _defaultDtSeconds = 0.2;
const double _maxDtSeconds = 1.0;
const double _maxSpeedMps = 3.5; // ~12 km/h max walking/jogging
const double _strideLength = 0.72; // longueur de pas moyenne en mètres

// ─── État global dead-reckoning ───────────────────────────────────────────────
DateTime? _lastSensorTimestamp;
double _estimatedHeadingDeg = 0.0;
double _estimatedSpeedMps = 0.0;

// ─── Filtre de Kalman scalaire pour le cap ────────────────────────────────────
// État    : cap en degrés
// Prédict : cap += gyroZ * dt
// Correct : fusion avec heading GPS quand disponible
bool _headingInitialized = false; // true après le premier fix GPS

// ─── Détection de pas ─────────────────────────────────────────────────────────
double _smoothedMag = 0.0;
bool _smoothedMagInit = false;
double _prevMagLinear = 0.0;
DateTime? _lastStepTime;
double _stepIntervalSeconds = 0.65; // intervalle initial (≈1.5 pas/s)

double _toRadians(double degrees) => degrees * math.pi / 180.0;
double _toDegrees(double radians) => radians * 180.0 / math.pi;
bool _isFinite(double? value) => value != null && value.isFinite;

double _normalizeAngleDegrees(double value) {
  var normalized = value % 360.0;
  if (normalized < 0) normalized += 360.0;
  return normalized;
}


double _clamp(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

void resetDeadReckoning() {
  _lastSensorTimestamp = null;
  _estimatedHeadingDeg = 0.0;
  _estimatedSpeedMps = 0.0;
  _headingInitialized = false;
  _smoothedMag = 0.0;
  _smoothedMagInit = false;
  _prevMagLinear = 0.0;
  _lastStepTime = null;
  _stepIntervalSeconds = 0.65;
}

/// Synchronise la vitesse et le pas depuis un fix GPS.
/// Le cap est géré uniquement par le gyroscope — pas de correction GPS.
void syncDeadReckoning(LocationData referencePosition) {
  // Initialisation du cap au premier fix si pas encore fait
  if (!_headingInitialized) {
    final heading = referencePosition.heading;
    if (_isFinite(heading)) {
      _estimatedHeadingDeg = _normalizeAngleDegrees(heading!);
      _headingInitialized = true;
    }
  }

  final speed = referencePosition.speed;
  if (_isFinite(speed) && speed! >= 0) {
    _estimatedSpeedMps = _clamp(speed, 0.0, _maxSpeedMps);
    if (speed > 0.3) {
      _stepIntervalSeconds = _clamp(_strideLength / speed, 0.25, 2.0);
    }
  }

  _lastSensorTimestamp = null;
}

LocationData interpolPosition(LocationData currentPosition, SensorData data) {
  final latitude = currentPosition.latitude;
  final longitude = currentPosition.longitude;
  if (latitude == null || longitude == null) return currentPosition;

  final now = data.timestamp;
  final elapsed = _lastSensorTimestamp == null
      ? _defaultDtSeconds
      : now.difference(_lastSensorTimestamp!).inMicroseconds / 1e6;
  final dt = _clamp(elapsed, 0.001, _maxDtSeconds);
  _lastSensorTimestamp = now;

  // ── 1. Cap — prédiction Kalman via gyroscope ─────────────────────────────
  final gyroZ = data.gyroZ ?? 0.0;
  _estimatedHeadingDeg = _normalizeAngleDegrees(
    _estimatedHeadingDeg - _toDegrees(gyroZ) * dt,
  );
  // Covariance croît avec le temps (dérive du gyro)

  // ── 2. Détection de pas par magnitude accéléromètre ─────────────────────
  final ax = data.accelX ?? 0.0;
  final ay = data.accelY ?? 0.0;
  final az = data.accelZ ?? 0.0;
  final mag = math.sqrt(ax * ax + ay * ay + az * az);

  if (!_smoothedMagInit) {
    _smoothedMag = mag;
    _smoothedMagInit = true;
  }

  // Filtre passe-bas : suit la composante DC (gravité + posture)
  const smoothAlpha = 0.85;
  _smoothedMag = smoothAlpha * _smoothedMag + (1.0 - smoothAlpha) * mag;

  final magLinear = mag - _smoothedMag;

  // Détection front descendant après un pic de pas
  const stepThreshold = 1.0; // m/s²
  if (_prevMagLinear > stepThreshold && magLinear <= stepThreshold) {
    final timeSinceLastStep = _lastStepTime == null
        ? double.infinity
        : now.difference(_lastStepTime!).inMicroseconds / 1e6;

    if (timeSinceLastStep > 0.30) {
      if (timeSinceLastStep < 2.0) {
        _stepIntervalSeconds = timeSinceLastStep;
      }
      _estimatedSpeedMps = _strideLength / _stepIntervalSeconds;
      _estimatedSpeedMps = _clamp(_estimatedSpeedMps, 0.2, _maxSpeedMps);
      _lastStepTime = now;
    }
  }
  _prevMagLinear = magLinear;

  // Décroissance rapide si aucun pas depuis 1.5 s
  if (_lastStepTime != null) {
    final idle = now.difference(_lastStepTime!).inMicroseconds / 1e6;
    if (idle > 1.5) {
      _estimatedSpeedMps *= math.pow(0.55, dt).toDouble();
    }
  }

  // ── 3. Mise à jour de la position ────────────────────────────────────────
  final headingRad = _toRadians(_estimatedHeadingDeg);
  final distance = _estimatedSpeedMps * dt;

  final deltaNorth = distance * math.cos(headingRad);
  final deltaEast = distance * math.sin(headingRad);

  final latRad = _toRadians(latitude);
  final deltaLat = deltaNorth / _earthRadiusMeters * (180.0 / math.pi);
  final denom = (_earthRadiusMeters * math.cos(latRad)).abs();
  final safeDenom = denom < 1e-6 ? 1e-6 : denom;
  final deltaLng = deltaEast / safeDenom * (180.0 / math.pi);

  return LocationData.fromMap({
    'latitude': latitude + deltaLat,
    'longitude': longitude + deltaLng,
    'accuracy': currentPosition.accuracy,
    'altitude': currentPosition.altitude,
    'speed': _estimatedSpeedMps,
    'speed_accuracy': currentPosition.speedAccuracy,
    'heading': _estimatedHeadingDeg,
    'time': currentPosition.time ?? now.millisecondsSinceEpoch.toDouble(),
  });
}
