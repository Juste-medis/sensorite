import 'package:location/location.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'dart:math' as math;

const double _earthR    = 6378137.0;
const double _defaultDt = 0.2;
const double _maxDt     = 1.0;
const double _gravAlpha = 0.98;
const double _zuptThreshold = 0.8;  // bruit réel d'un accéléromètre MEMS ≈ 0.3–0.6 m/s²
const double _zuptDecay     = 0.5;  // décroissance agressive : vitesse divisée par 2 chaque seconde

// ─────────────────────────────────────────────────────────────────────────────
/// Moteur de dead-reckoning par double intégration accéléromètre + quaternion.
///
/// Chaque instance a son propre état (quaternion, vitesse, gravité) :
/// instancier une fois pour le mode DR normal et une autre pour le mode VS.
// ─────────────────────────────────────────────────────────────────────────────
class DeadReckoning {
  // Quaternion [w, x, y, z] — rotation repère capteur → monde (ENU)
  double _qw = 1.0, _qx = 0.0, _qy = 0.0, _qz = 0.0;
  bool   _qInit = false;

  // Vitesse dans le repère monde (Nord, Est) m/s
  double _velN = 0.0, _velE = 0.0;

  // Gravité LP dans le repère capteur
  double _gx = 0.0, _gy = 0.0, _gz = 9.81;
  bool   _gInit = false;

  DateTime? _lastTs;
  int _warmupTicks = 0; // nb de ticks avant que le filtre gravité soit stable
  static const int _warmupRequired = 25; // 25 × 200 ms = 5 s

  // ── Utilitaires ─────────────────────────────────────────────────────────────
  static double _toRad(double d) => d * math.pi / 180.0;
  static double _toDeg(double r) => r * 180.0 / math.pi;
  static bool   _ok(double? v)   => v != null && v.isFinite;

  static double _norm360(double d) {
    var v = d % 360.0;
    if (v < 0) v += 360.0;
    return v;
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  // ── Quaternion ──────────────────────────────────────────────────────────────
  void _updateQuat(double gx, double gy, double gz, double dt) {
    final h = 0.5 * dt;
    final dw = -_qx*gx - _qy*gy - _qz*gz;
    final dx =  _qw*gx + _qy*gz - _qz*gy;
    final dy =  _qw*gy - _qx*gz + _qz*gx;
    final dz =  _qw*gz + _qx*gy - _qy*gx;
    _qw += h*dw; _qx += h*dx; _qy += h*dy; _qz += h*dz;
    _normalizeQuat();
  }

  void _normalizeQuat() {
    final n = math.sqrt(_qw*_qw + _qx*_qx + _qy*_qy + _qz*_qz);
    if (n > 1e-9) { _qw/=n; _qx/=n; _qy/=n; _qz/=n; }
  }

  /// Rotation d'un vecteur repère capteur → monde, retourne [Est, Nord].
  List<double> _rotateToWorld(double vx, double vy, double vz) {
    final qw=_qw, qx=_qx, qy=_qy, qz=_qz;
    final wx = (1-2*(qy*qy+qz*qz))*vx + 2*(qx*qy-qw*qz)*vy + 2*(qx*qz+qw*qy)*vz;
    final wy =     2*(qx*qy+qw*qz)*vx + (1-2*(qx*qx+qz*qz))*vy + 2*(qy*qz-qw*qx)*vz;
    return [wx, wy]; // [Est, Nord]
  }

  /// Cap estimé en degrés (0=Nord, sens horaire) depuis le quaternion.
  double get headingDeg {
    final yaw = math.atan2(
      2.0*(_qw*_qz + _qx*_qy),
      1.0 - 2.0*(_qy*_qy + _qz*_qz),
    );
    return _norm360(-_toDeg(yaw));
  }

  void _initQuat(double ax, double ay, double az, double headingDeg) {
    final mag = math.sqrt(ax*ax + ay*ay + az*az);
    if (mag < 0.5) return;
    final roll  = math.atan2(ay, az);
    final pitch = math.atan2(-ax, math.sqrt(ay*ay + az*az));
    final yaw   = -_toRad(headingDeg);
    final cr=math.cos(roll/2),  sr=math.sin(roll/2);
    final cp=math.cos(pitch/2), sp=math.sin(pitch/2);
    final cy=math.cos(yaw/2),   sy=math.sin(yaw/2);
    _qw = cr*cp*cy + sr*sp*sy;
    _qx = sr*cp*cy - cr*sp*sy;
    _qy = cr*sp*cy + sr*cp*sy;
    _qz = cr*cp*sy - sr*sp*cy;
    _normalizeQuat();
    _qInit = true;
  }

  // ── API publique ─────────────────────────────────────────────────────────────

  void reset() {
    _qw=1; _qx=0; _qy=0; _qz=0; _qInit=false;
    _velN=0; _velE=0;
    _gx=0; _gy=0; _gz=9.81; _gInit=false;
    _lastTs=null;
    _warmupTicks=0;
  }

  /// Corrige uniquement le cap depuis un fix GPS, sans toucher à la vitesse.
  /// À utiliser en mode VS pour garder la prédiction de vitesse indépendante.
  void syncHeadingOnly(LocationData gps) {
    final spd = gps.speed ?? 0.0;
    final hdg = gps.heading;
    if (!_qInit && _ok(hdg) && _gInit) {
      _initQuat(_gx, _gy, _gz, hdg!);
    }
    if (_qInit && _ok(hdg) && spd > 1.0) {
      final diff = ((hdg! - headingDeg + 540) % 360) - 180;
      final corrRad = -_toRad(diff * 0.1);
      final c = math.cos(corrRad/2), s = math.sin(corrRad/2);
      final nw=c*_qw-s*_qz, nx=c*_qx-s*_qy,
            ny=c*_qy+s*_qx, nz=c*_qz+s*_qw;
      _qw=nw; _qx=nx; _qy=ny; _qz=nz;
      _normalizeQuat();
    }
    _lastTs = null;
  }

  /// Recale depuis un fix GPS (yaw + vitesse).
  void sync(LocationData gps) {
    final spd = gps.speed ?? 0.0;
    final hdg = gps.heading;

    if (!_qInit && _ok(hdg) && _gInit) {
      _initQuat(_gx, _gy, _gz, hdg!);
    }

    // Correction douce du yaw si on se déplace
    if (_qInit && _ok(hdg) && spd > 1.0) {
      final diff = ((hdg! - headingDeg + 540) % 360) - 180;
      final corrRad = -_toRad(diff * 0.1);
      final c = math.cos(corrRad/2), s = math.sin(corrRad/2);
      final nw=c*_qw - s*_qz, nx=c*_qx - s*_qy,
            ny=c*_qy + s*_qx, nz=c*_qz + s*_qw;
      _qw=nw; _qx=nx; _qy=ny; _qz=nz;
      _normalizeQuat();
    }

    // Vitesse initiale (composantes Nord/Est)
    if (_ok(hdg) && spd >= 0) {
      final hRad = _toRad(hdg!);
      _velN = spd * math.cos(hRad);
      _velE = spd * math.sin(hRad);
    }

    _lastTs = null;
  }

  /// Double intégration → nouvelle position prédite.
  LocationData predict(LocationData pos, SensorData data) {
    final lat = pos.latitude;
    final lng = pos.longitude;
    if (lat == null || lng == null) return pos;

    final now = data.timestamp;
    final elapsed = _lastTs == null
        ? _defaultDt
        : now.difference(_lastTs!).inMicroseconds / 1e6;
    final dt = _clamp(elapsed, 0.001, _maxDt);
    _lastTs = now;

    final ax = data.accelX ?? 0.0;
    final ay = data.accelY ?? 0.0;
    final az = data.accelZ ?? 0.0;
    final gx = data.gyroX  ?? 0.0;
    final gy = data.gyroY  ?? 0.0;
    final gz = data.gyroZ  ?? 0.0;

    // 1. Gravité LP
    if (!_gInit) { _gx=ax; _gy=ay; _gz=az; _gInit=true; }
    _gx = _gravAlpha*_gx + (1-_gravAlpha)*ax;
    _gy = _gravAlpha*_gy + (1-_gravAlpha)*ay;
    _gz = _gravAlpha*_gz + (1-_gravAlpha)*az;

    if (!_qInit && _gInit) _initQuat(_gx, _gy, _gz, 0.0);

    // 2. Orientation 3D via les 3 axes gyro
    _updateQuat(gx, gy, gz, dt);

    // Warmup : on laisse le filtre gravité se stabiliser avant d'intégrer
    if (_warmupTicks < _warmupRequired) {
      _warmupTicks++;
      return LocationData.fromMap({
        'latitude': lat, 'longitude': lng,
        'accuracy': pos.accuracy, 'altitude': pos.altitude,
        'speed': 0.0, 'heading': headingDeg,
        'time': pos.time ?? now.millisecondsSinceEpoch.toDouble(),
      });
    }

    // 3. Accél linéaire (gravité retirée)
    final world = _rotateToWorld(ax-_gx, ay-_gy, az-_gz);
    final aE = world[0], aN = world[1];

    // 4. ZUPT / intégration vitesse
    final aHoriz = math.sqrt(aN*aN + aE*aE);
    if (aHoriz < _zuptThreshold) {
      final decay = math.pow(_zuptDecay, dt).toDouble();
      _velN *= decay;
      _velE *= decay;
    } else {
      _velN += aN * dt;
      _velE += aE * dt;
    }
    _velN = _clamp(_velN, -60, 60);
    _velE = _clamp(_velE, -60, 60);

    // 5. Position
    final dNorth = _velN * dt;
    final dEast  = _velE * dt;
    final latRad = lat * math.pi / 180.0;
    final dLat   = dNorth / _earthR * (180.0 / math.pi);
    final denom  = (_earthR * math.cos(latRad)).abs();
    final dLng   = dEast / (denom < 1e-6 ? 1e-6 : denom) * (180.0 / math.pi);

    return LocationData.fromMap({
      'latitude':       lat + dLat,
      'longitude':      lng + dLng,
      'accuracy':       pos.accuracy,
      'altitude':       pos.altitude,
      'speed':          math.sqrt(_velN*_velN + _velE*_velE),
      'speed_accuracy': pos.speedAccuracy,
      'heading':        headingDeg,
      'time':           pos.time ?? now.millisecondsSinceEpoch.toDouble(),
    });
  }
}
