import 'package:location/location.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'dart:math' as math;

const double _earthRadiusMeters = 6378137.0;
const double _defaultDtSeconds = 0.2;
const double _maxDtSeconds = 1.0;
const double _speedDamping = 0.97;
const double _maxSpeedMps = 5.5;
const double _gpsSpeedBlend = 0.30;
const double _gpsHeadingBlend = 0.12;
const double _gravityTimeConstantSeconds = 0.75;

DateTime? _lastSensorTimestamp;
double _estimatedHeadingDeg = 0.0;
double _estimatedSpeedMps = 0.0;
double _gravityX = 0.0;
double _gravityY = 0.0;
double _gravityZ = 0.0;
bool _gravityInitialized = false;

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
  _gravityX = 0.0;
  _gravityY = 0.0;
  _gravityZ = 0.0;
  _gravityInitialized = false;
}

void syncDeadReckoning(LocationData referencePosition) {
  final heading = referencePosition.heading;
  if (_isFinite(heading)) {
    _estimatedHeadingDeg = _normalizeAngleDegrees(heading!);
  }

  final speed = referencePosition.speed;
  if (_isFinite(speed) && speed! >= 0) {
    _estimatedSpeedMps = _clamp(speed, 0.0, _maxSpeedMps);
  }

  // Reset dt to avoid a large integration jump after state resync.
  _lastSensorTimestamp = null;
}

LocationData interpolPosition(LocationData currentPosition, SensorData data) {
  final latitude = currentPosition.latitude;
  final longitude = currentPosition.longitude;

  if (latitude == null || longitude == null) {
    return currentPosition;
  }

  final now = data.timestamp;
  final elapsedSeconds = _lastSensorTimestamp == null
      ? _defaultDtSeconds
      : now.difference(_lastSensorTimestamp!).inMicroseconds / 1e6;
  final dt = _clamp(elapsedSeconds, 0.001, _maxDtSeconds);
  _lastSensorTimestamp = now;

  final locationSpeed = currentPosition.speed;
  if (_isFinite(locationSpeed) && locationSpeed! >= 0) {
    _estimatedSpeedMps = _estimatedSpeedMps * (1.0 - _gpsSpeedBlend) +
        locationSpeed * _gpsSpeedBlend;
  }

  final headingFromLocation = currentPosition.heading;
  if (_isFinite(headingFromLocation) &&
      _isFinite(locationSpeed) &&
      locationSpeed! > 0.8) {
    final normalizedHeading = _normalizeAngleDegrees(headingFromLocation!);
    _estimatedHeadingDeg = _normalizeAngleDegrees(
      _estimatedHeadingDeg * (1.0 - _gpsHeadingBlend) +
          normalizedHeading * _gpsHeadingBlend,
    );
  }

  final gyroZ = data.gyroZ ?? 0.0;

  // Gyroscope gyroz is in rad/s. Positive z rotates around vertical axis.
  // In screen coordinates yaw sign may vary by device orientation; this
  // convention keeps a stable heading update for dead-reckoning.
  final deltaHeading = _toDegrees(gyroZ) * dt;
  _estimatedHeadingDeg = _normalizeAngleDegrees(_estimatedHeadingDeg + deltaHeading);

  final accelX = data.accelX ?? 0.0;
  final accelY = data.accelY ?? 0.0;
  final accelZ = data.accelZ ?? 0.0;

  if (!_gravityInitialized) {
    _gravityX = accelX;
    _gravityY = accelY;
    _gravityZ = accelZ;
    _gravityInitialized = true;
  }

  // Low-pass estimate of gravity: g[k] = alpha*g[k-1] + (1-alpha)*a[k]
  final alpha = _gravityTimeConstantSeconds /
      (_gravityTimeConstantSeconds + dt);
  _gravityX = alpha * _gravityX + (1.0 - alpha) * accelX;
  _gravityY = alpha * _gravityY + (1.0 - alpha) * accelY;
  _gravityZ = alpha * _gravityZ + (1.0 - alpha) * accelZ;

  final linearY = accelY - _gravityY;

  // Use gravity-corrected forward acceleration with dead-zone and clamping.
  final accelThreshold = 0.18;
  final correctedAccel = linearY.abs() < accelThreshold ? 0.0 : linearY;
  final limitedAccel = _clamp(correctedAccel, -2.0, 2.0);

  _estimatedSpeedMps += limitedAccel * dt * 0.45;
  _estimatedSpeedMps *= _speedDamping;
  _estimatedSpeedMps = _clamp(_estimatedSpeedMps, 0.0, _maxSpeedMps);

  final headingRad = _toRadians(_estimatedHeadingDeg);
  final distance = _estimatedSpeedMps * dt;

  final deltaNorth = distance * math.cos(headingRad);
  final deltaEast = distance * math.sin(headingRad);

  final latRad = _toRadians(latitude);
  final deltaLat = (deltaNorth / _earthRadiusMeters) * (180.0 / math.pi);
  final denom = (_earthRadiusMeters * math.cos(latRad)).abs();
  final safeDenom = denom < 1e-6 ? 1e-6 : denom;
  final deltaLng = (deltaEast / safeDenom) * (180.0 / math.pi);

  final nextLat = latitude + deltaLat;
  final nextLng = longitude + deltaLng;

  return LocationData.fromMap({
    'latitude': nextLat,
    'longitude': nextLng,
    'accuracy': currentPosition.accuracy,
    'altitude': currentPosition.altitude,
    'speed': _estimatedSpeedMps,
    'speed_accuracy': currentPosition.speedAccuracy,
    'heading': _estimatedHeadingDeg,
    'time': currentPosition.time ?? now.millisecondsSinceEpoch.toDouble(),
  });
}
