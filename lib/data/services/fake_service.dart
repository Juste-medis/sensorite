
import 'package:location/location.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'dart:math' as mathematiques;

/// Navigateur universel : détecte automatiquement le mode de transport
/// et applique la bonne physique (voiture vs piéton).
class NavigateurUniversel {
  // ═════════════════════════════════════════════════════════════════
  // CONSTANTES PHYSIQUES
  // ═════════════════════════════════════════════════════════════════

  static const double _RAYON_TERRE_METRES = 6378137.0;
  static const double _TEMPS_PAR_DEFAUT_S = 0.2;
  static const double _TEMPS_MAX_ENTRE_LECTURES_S = 1.0;

  // Limites selon le mode
  static const double _VITESSE_MAX_VOITURE_MS = 36.5; // 130 km/h
  static const double _VITESSE_MAX_PIED_MS = 3.5; // 12.6 km/h
  static const double _ACCELERATION_MAX_VOITURE_MS2 = 12.0;
  static const double _ACCELERATION_MAX_PIED_MS2 = 8.0; // Sprint/démarrage

  // Paramètres spécifiques marche
  static const double _LONGUEUR_PAS_MOYENNE = 0.72; // 72 cm
  static const double _SEUIL_DETECTION_PAS_MS2 = 1.0; // Choc au sol
  static const double _TEMPS_MIN_ENTRE_PAS_S = 0.30; // 200 pas/min max
  static const double _TEMPS_MAX_ENTRE_PAS_S = 2.0; // Au-delà = arrêt

  // ═════════════════════════════════════════════════════════════════
  // ÉTAT INTERNe
  // ═════════════════════════════════════════════════════════════════

  PositionGeo? _dernierePositionConnue;
  DateTime? _horodatageDernierCalcul;
  double _capActuelDegres = 0.0;
  double _vitesseActuelleMs = 0.0;
  bool _estInitialise = false;
  double _dureeNavigationAveugleSecondes = 0.0;

  /// Mode actuel détecté automatiquement
  ModeTransport _modeActuel = ModeTransport.pieton;

  // ═════════════════════════════════════════════════════════════════
  // VARIABLES SPÉCIFIQUES MARCHE (détection de pas)
  // ═════════════════════════════════════════════════════════════════

  double _accelerationLissee = 0.0; // Filtre passe-bas pour isoler la gravité
  bool _accelerationLisseeInitialisee = false;
  double _accelerationPrecedente = 0.0;
  DateTime? _horodatageDernierPas;
  double _intervalleMoyenEntrePasS = 0.65; // ~1.5 pas/seconde par défaut

  // ═════════════════════════════════════════════════════════════════
  // PARAMÈTRES RÉGLABLES
  // ═════════════════════════════════════════════════════════════════

  /// Coefficient de lissage pour la marche (85% ancienne valeur)
  static const double _LISSEUR_ACCELERATION = 0.85;

  /// Frottement : voiture perd 2%/s, piéton perd 45%/s quand arrêté
  static const double _FROTTEMENT_VOITURE = 0.98;
  static const double _FROTTEMENT_PIED = 0.55;

  // ═════════════════════════════════════════════════════════════════
  // MÉTHODES PUBLIQUES
  // ═════════════════════════════════════════════════════════════════

  void reinitialiser() {
    _dernierePositionConnue = null;
    _horodatageDernierCalcul = null;
    _capActuelDegres = 0.0;
    _vitesseActuelleMs = 0.0;
    _estInitialise = false;
    _dureeNavigationAveugleSecondes = 0.0;
    _modeActuel = ModeTransport.pieton;

    // Reset marche
    _accelerationLissee = 0.0;
    _accelerationLisseeInitialisee = false;
    _accelerationPrecedente = 0.0;
    _horodatageDernierPas = null;
    _intervalleMoyenEntrePasS = 0.65;
  }

  void synchroniserAvecGPS(LocationData positionGPS) {
    if (positionGPS.latitude != null && positionGPS.longitude != null) {
      _dernierePositionConnue = PositionGeo(
        latitude: positionGPS.latitude!,
        longitude: positionGPS.longitude!,
        altitude: positionGPS.altitude ?? 0.0,
      );
    }

    // DÉTECTION DU MODE DE TRANSPORT (basée sur la vitesse GPS)
    if (positionGPS.speed != null && positionGPS.speed!.isFinite) {
      final double vitesse = positionGPS.speed!;

      // Heuristique simple : > 15 km/h (4.2 m/s) = voiture
      // Entre 0.5 et 4.2 m/s = piéton (ou vélo, traité comme piéton rapide)
      // < 0.5 m/s = arrêt
      if (vitesse > 4.2) {
        if (_modeActuel != ModeTransport.voiture) {
          _modeActuel = ModeTransport.voiture;
          _basculerMode(ModeTransport.voiture);
        }
      } else if (vitesse > 0.5) {
        if (_modeActuel != ModeTransport.pieton) {
          _modeActuel = ModeTransport.pieton;
          _basculerMode(ModeTransport.pieton);
        }
      }

      // Mise à jour vitesse avec plafond selon le mode
      final double vitesseMax = (_modeActuel == ModeTransport.voiture)
          ? _VITESSE_MAX_VOITURE_MS
          : _VITESSE_MAX_PIED_MS;
      _vitesseActuelleMs = _limiter(valeur: vitesse, min: 0.0, max: vitesseMax);
    }

    // Initialisation/correction du cap
    if (positionGPS.heading != null && positionGPS.heading!.isFinite) {
      if (!_estInitialise) {
        _capActuelDegres = _normaliserAngle(positionGPS.heading!);
        _estInitialise = true;
      } else {
        _capActuelDegres = _interpolerAngles(
          _capActuelDegres,
          positionGPS.heading!,
          0.3,
        );
      }
    }

    _dureeNavigationAveugleSecondes = 0.0;
    _horodatageDernierCalcul = DateTime.now();
  }

  LocationData calculerNouvellePosition({
    required LocationData positionActuelle,
    required SensorData donneesCapteurs,
  }) { 
    print("Mode: $_modeActuel");
    print(
      "Position entrée: ${positionActuelle.latitude}, ${positionActuelle.longitude}",
    );

    if (positionActuelle.latitude == null ||
        positionActuelle.longitude == null) {
      print("❌ ERREUR: position nulle");
      return positionActuelle;
    }

    final DateTime maintenant = donneesCapteurs.timestamp;
    final double deltaTempsS = _calculerTempsEcoule(maintenant);
    _horodatageDernierCalcul = maintenant;
    _dureeNavigationAveugleSecondes += deltaTempsS;

    print("⏱️ deltaTempsS: $deltaTempsS");

    // CAP (commun)
    final double vitesseRotationGyro = donneesCapteurs.gyroZ ?? 0.0;
    final double changementCap =
        _convertirRadiansEnDegres(vitesseRotationGyro) * deltaTempsS;
    _capActuelDegres = _normaliserAngle(_capActuelDegres - changementCap);
    print("🧭 Cap: $_capActuelDegres° (gyroZ=$vitesseRotationGyro)");

    // VITESSE selon mode
    if (_modeActuel == ModeTransport.pieton) {
      _mettreAJourVitesseModePieton(donneesCapteurs, deltaTempsS);
    } else {
      _mettreAJourVitesseModeVoiture(donneesCapteurs, deltaTempsS);
    }

    print("🚗 Vitesse après calcul: $_vitesseActuelleMs m/s");

    // DÉPLACEMENT
    final double distanceParcourue = _vitesseActuelleMs * deltaTempsS;
    print(
      "📏 Distance: $distanceParcourue m (v×t=${_vitesseActuelleMs}×$deltaTempsS)",
    );

    if (distanceParcourue <= 0) {
      print("⚠️ Distance nulle ou négative, position inchangée");
      return positionActuelle;
    }

    // CONVERSION GPS
    final DeplacementGPS deplacement = _convertirDeplacementEnCoordonnees(
      latitudeDepart: positionActuelle.latitude!,
      longitudeDepart: positionActuelle.longitude!,
      capDegres: _capActuelDegres,
      distanceMetres: distanceParcourue,
    );

    print(
      "🗺️ NOUVELLE POSITION: ${deplacement.nouvelleLatitude}, ${deplacement.nouvelleLongitude}",
    );
    print(
      "Δlat: ${(deplacement.nouvelleLatitude - positionActuelle.latitude!).toStringAsFixed(8)}",
    );
    print(
      "Δlng: ${(deplacement.nouvelleLongitude - positionActuelle.longitude!).toStringAsFixed(8)}",
    );
    print("====================================\n");

    return LocationData.fromMap({
      'latitude': deplacement.nouvelleLatitude,
      'longitude': deplacement.nouvelleLongitude,
      'accuracy': _estimerPrecisionActuelle(),
      'altitude': positionActuelle.altitude,
      'speed': _vitesseActuelleMs,
      'speed_accuracy': _dureeNavigationAveugleSecondes * 0.5,
      'heading': _capActuelDegres,
      'time': maintenant.millisecondsSinceEpoch.toDouble(),
    });
  }
  // ═════════════════════════════════════════════════════════════════
  // MÉTHODES PRIVÉES PAR MODE
  // ═════════════════════════════════════════════════════════════════

  /// Mode VOITURE : Intégration de l'accéléromètre avec frottement faible
  void _mettreAJourVitesseModeVoiture(SensorData donnees, double deltaTempsS) {
    // On utilise l'axe Y (avant-arrière) comme accélérateur/frein
    final double accelY = donnees.accelY ?? 0.0;
    final double accelZ = donnees.accelZ ?? 0.0;

    // Compensation gravité simple
    double acceleration = _estimerAccelerationReelle(
      accelerationBrute: accelY,
      graviteMesuree: accelZ,
    );

    // Limitation selon physique automobile
    acceleration = _limiter(
      valeur: acceleration,
      min: -10.0, // Freinage fort
      max: _ACCELERATION_MAX_VOITURE_MS2,
    );

    // Intégration : V = V₀ + a×t
    double nouvelleVitesse = _vitesseActuelleMs + (acceleration * deltaTempsS);

    // Frottement aérodynamique/roulement (perte lente)
    nouvelleVitesse =
        nouvelleVitesse *
        mathematiques.pow(_FROTTEMENT_VOITURE, deltaTempsS).toDouble();

    _vitesseActuelleMs = _limiter(
      valeur: nouvelleVitesse,
      min: 0.0,
      max: _VITESSE_MAX_VOITURE_MS,
    );
  }

  /// Mode PIÉTON : Détection de pas instrumentée pour debug
  void _mettreAJourVitesseModePieton(SensorData donnees, double deltaTempsS) {
    final double accelX = donnees.accelX ?? 0.0;
    final double accelY = donnees.accelY ?? 0.0;
    final double accelZ = donnees.accelZ ?? 0.0;

    final double normeAcceleration = mathematiques.sqrt(
      accelX * accelX + accelY * accelY + accelZ * accelZ,
    );

    // Initialisation au premier appel
    if (!_accelerationLisseeInitialisee) {
      _accelerationLissee = normeAcceleration;
      _accelerationLisseeInitialisee = true;
      print("🟢 INIT: accelLissee = ${normeAcceleration.toStringAsFixed(2)}");
    }

    // Filtre passe-bas
    _accelerationLissee =
        _LISSEUR_ACCELERATION * _accelerationLissee +
        (1.0 - _LISSEUR_ACCELERATION) * normeAcceleration;

    final double accelNette = normeAcceleration - _accelerationLissee;

    print(
      "📊 RAW: norme=${normeAcceleration.toStringAsFixed(2)}, "
      "lissee=${_accelerationLissee.toStringAsFixed(2)}, "
      "nette=${accelNette.toStringAsFixed(2)}",
    );

    // ═══════════════════════════════════════════════════════════════
    // DÉTECTION DE PAS
    // ═══════════════════════════════════════════════════════════════

    final bool estPicDePas =
        (_accelerationPrecedente > _SEUIL_DETECTION_PAS_MS2) &&
        (accelNette <= _SEUIL_DETECTION_PAS_MS2);

    if (estPicDePas) {
      final double tempsDepuisDernierPas = (_horodatageDernierPas == null)
          ? double.infinity
          : donnees.timestamp
                    .difference(_horodatageDernierPas!)
                    .inMicroseconds /
                1000000.0;

      print(
        "⚡ PIC DÉTECTÉ! tempsDepuisDernierPas=${tempsDepuisDernierPas.toStringAsFixed(3)}s "
        "(min=$_TEMPS_MIN_ENTRE_PAS_S)",
      );

      if (tempsDepuisDernierPas > _TEMPS_MIN_ENTRE_PAS_S) {
        if (tempsDepuisDernierPas < _TEMPS_MAX_ENTRE_PAS_S) {
          _intervalleMoyenEntrePasS = tempsDepuisDernierPas;
          print(
            "✅ PAS VALIDE! intervalle=${_intervalleMoyenEntrePasS.toStringAsFixed(3)}s",
          );
        } else {
          print(
            "⚠️ Trop long (>$_TEMPS_MAX_ENTRE_PAS_S), on garde l'ancien intervalle",
          );
        }

        // CALCUL VITESSE
        final double ancienneVitesse = _vitesseActuelleMs;
        _vitesseActuelleMs = _LONGUEUR_PAS_MOYENNE / _intervalleMoyenEntrePasS;
        _vitesseActuelleMs = _limiter(
          valeur: _vitesseActuelleMs,
          min: 0.2,
          max: _VITESSE_MAX_PIED_MS,
        );

        print(
          "🚀 VITESSE: $ancienneVitesse → $_vitesseActuelleMs m/s "
          "(${(_vitesseActuelleMs * 3.6).toStringAsFixed(1)} km/h)",
        );

        _horodatageDernierPas = donnees.timestamp;
      } else {
        print("❌ REJETÉ: trop rapide (rebond?)");
      }
    }

    _accelerationPrecedente = accelNette;

    // ═══════════════════════════════════════════════════════════════
    // DÉTECTION D'ARRÊT
    // ═══════════════════════════════════════════════════════════════

    if (_horodatageDernierPas != null) {
      final double tempsSansPas =
          donnees.timestamp.difference(_horodatageDernierPas!).inMicroseconds /
          1000000.0;

      if (tempsSansPas > 1.5) {
        final double vitesseAvant = _vitesseActuelleMs;
        _vitesseActuelleMs =
            _vitesseActuelleMs *
            mathematiques.pow(_FROTTEMENT_PIED, deltaTempsS).toDouble();

        print(
          "😴 DÉCROISSANCE: $vitesseAvant → $_vitesseActuelleMs "
          "(sans pas depuis ${tempsSansPas.toStringAsFixed(2)}s)",
        );

        if (_vitesseActuelleMs < 0.1) {
          _vitesseActuelleMs = 0.0;
          print("🛑 ARRÊT COMPLET");
        }
      }
    } else {
      print("🕐 Jamais eu de pas depuis le début");
    }

    print("🏁 VITESSE FINALE: $_vitesseActuelleMs m/s");
  }
  // ═════════════════════════════════════════════════════════════════
  // MÉTHODES UTILITAIRES
  // ═════════════════════════════════════════════════════════════════

  void _basculerMode(ModeTransport nouveauMode) {
    // Réinitialisation des variables spécifiques lors du changement
    if (nouveauMode == ModeTransport.pieton) {
      _accelerationLisseeInitialisee = false;
      _horodatageDernierPas = null;
    }
    // Log optionnel : print('Mode changé : $nouveauMode');
  }

  double _calculerTempsEcoule(DateTime heureActuelle) {
    if (_horodatageDernierCalcul == null) return _TEMPS_PAR_DEFAUT_S;

    final double ecoule =
        heureActuelle.difference(_horodatageDernierCalcul!).inMicroseconds /
        1000000.0;

    return _limiter(
      valeur: ecoule,
      min: 0.001,
      max: _TEMPS_MAX_ENTRE_LECTURES_S,
    );
  }

  double _convertirRadiansEnDegres(double radians) =>
      radians * 180.0 / mathematiques.pi;

  double _normaliserAngle(double angle) {
    double normalise = angle % 360.0;
    if (normalise < 0) normalise += 360.0;
    return normalise;
  }

  double _interpolerAngles(double actuel, double cible, double coef) {
    double diff = cible - actuel;
    while (diff > 180.0) diff -= 360.0;
    while (diff < -180.0) diff += 360.0;
    return _normaliserAngle(actuel + (diff * coef));
  }

  double _limiter({
    required double valeur,
    required double min,
    required double max,
  }) {
    if (valeur < min) return min;
    if (valeur > max) return max;
    return valeur;
  }

  double _estimerAccelerationReelle({
    required double accelerationBrute,
    required double graviteMesuree,
  }) {
    if (_vitesseActuelleMs < 0.5) return 0.0; // Considéré à l'arrêt
    return accelerationBrute; // Simplifié : en voiture on suppose route plate
  }

  DeplacementGPS _convertirDeplacementEnCoordonnees({
    required double latitudeDepart,
    required double longitudeDepart,
    required double capDegres,
    required double distanceMetres,
  }) {
    final double capRad = capDegres * mathematiques.pi / 180.0;
    final double latRad = latitudeDepart * mathematiques.pi / 180.0;

    final double deplacementNord = distanceMetres * mathematiques.cos(capRad);
    final double deplacementEst = distanceMetres * mathematiques.sin(capRad);

    final double deltaLat =
        (deplacementNord / _RAYON_TERRE_METRES) * (180.0 / mathematiques.pi);
    final double rayonLng = (_RAYON_TERRE_METRES * mathematiques.cos(latRad))
        .abs();
    final double deltaLng =
        (deplacementEst / (rayonLng < 0.001 ? 0.001 : rayonLng)) *
        (180.0 / mathematiques.pi);

    return DeplacementGPS(
      nouvelleLatitude: latitudeDepart + deltaLat,
      nouvelleLongitude: longitudeDepart + deltaLng,
    );
  }

  double _estimerPrecisionActuelle() {
    final double erreurBase = 5.0;
    final double erreurVitesse =
        _dureeNavigationAveugleSecondes * _vitesseActuelleMs * 0.1;
    final double erreurRotation = _dureeNavigationAveugleSecondes * 0.5;
    return erreurBase + erreurVitesse + erreurRotation;
  }
}

// ═════════════════════════════════════════════════════════════════
// ÉNUMÉRATIONS ET CLASSES
// ═════════════════════════════════════════════════════════════════

enum ModeTransport { pieton, voiture }

class PositionGeo {
  final double latitude;
  final double longitude;
  final double altitude;
  PositionGeo({
    required this.latitude,
    required this.longitude,
    required this.altitude,
  });
}

class DeplacementGPS {
  final double nouvelleLatitude;
  final double nouvelleLongitude;
  DeplacementGPS({
    required this.nouvelleLatitude,
    required this.nouvelleLongitude,
  });
}


