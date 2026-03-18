import 'package:location/location.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'dart:math' as math;

const double _earthRadiusMeters = 6378137.0;
const double _defaultDtSeconds = 0.2;
const double _maxDtSeconds = 1.0;
const double _speedDamping = 0.92;
const double _maxSpeedMps = 8.0;

DateTime? _lastSensorTimestamp;
double _estimatedHeadingDeg = 0.0;
double _estimatedSpeedMps = 0.0;

double _toRadians(double degrees) => degrees * math.pi / 180.0;
double _toDegrees(double radians) => radians * 180.0 / math.pi;

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

  final currentHeading = currentPosition.heading ?? _estimatedHeadingDeg;
  final gyroZ = data.gyroZ ?? 0.0;

  // Gyroscope gyroz is in rad/s. Positive z rotates around vertical axis.
  // In screen coordinates yaw sign may vary by device orientation; this
  // convention keeps a stable heading update for dead-reckoning.
  final deltaHeading = _toDegrees(gyroZ) * dt;
  _estimatedHeadingDeg = _normalizeAngleDegrees(currentHeading + deltaHeading);

  // Use accelY as forward acceleration proxy. This is a simplified model
  // (device orientation not compensated). A small dead-zone reduces drift.
  final accelForward = data.accelY ?? 0.0;
  final accelThreshold = 0.12;
  final correctedAccel = accelForward.abs() < accelThreshold
      ? 0.0
      : accelForward;

  _estimatedSpeedMps += correctedAccel * dt;
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
