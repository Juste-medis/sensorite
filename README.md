# IMU Navigator — Navigation Inertielle avec Filtre de Kalman

Application Flutter de navigation hybride GPS + IMU qui prédit la position par **dead reckoning** (navigation à l'estime) lorsque le signal GPS est perdu, en utilisant la double intégration de l'accéléromètre et du gyroscope avec un **filtre de Kalman étendu**.

---

## Architecture du Système

```
┌──────────────┐     ┌──────────────┐
│ Accéléromètre│     │  Gyroscope   │
│   (50 Hz)    │     │   (50 Hz)    │
└──────┬───────┘     └──────┬───────┘
       │                     │
       ▼                     ▼
┌──────────────────────────────────────┐
│        Pré-traitement IMU            │
│  • Soustraction des biais            │
│  • Filtre passe-bas                  │
│  • Suppression de la gravité         │
│  • Transformation repère monde       │
│  • Détection d'immobilité (ZUPT)     │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│      Filtre de Kalman Étendu         │
│                                      │
│  État: [x, y, vx, vy, ax, ay, yaw]  │
│                                      │
│  Prédiction: modèle cinématique      │
│    x = x + v·dt + ½·a·dt²           │
│    v = v + a·dt                      │
│                                      │
│  Correction: GPS (quand disponible)  │
│    K = P·Hᵀ·(H·P·Hᵀ + R)⁻¹        │
│    x = x + K·(z - H·x)              │
│    P = (I - K·H)·P                   │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│         Position Estimée             │
│  • Coordonnées GPS (lat/lon)         │
│  • Vitesse et cap                    │
│  • Indice de confiance               │
│  • Rayon d'incertitude               │
└──────────────────────────────────────┘
```

## Fichiers Principaux

| Fichier | Rôle |
|---------|------|
| `lib/kalman_filter.dart` | Filtre de Kalman étendu — prédiction IMU + correction GPS, opérations matricielles, calibration, ZUPT |
| `lib/navigation_service.dart` | Service de navigation — gestion des capteurs, fusion GPS/IMU, détection perte GPS |
| `lib/navigation_screen.dart` | Interface utilisateur — boussole, métriques, contrôles |
| `lib/main.dart` | Point d'entrée de l'application |

## Algorithmes Implémentés

### 1. Filtre de Kalman Étendu (EKF)
- **Vecteur d'état (7D)** : position (x,y), vitesse (vx,vy), accélération (ax,ay), cap (yaw)
- **Prédiction** : intégration cinématique des données IMU
- **Correction** : fusion avec le GPS quand disponible
- **Matrice de covariance** adaptative selon la qualité GPS

### 2. Pré-traitement des Capteurs
- **Calibration** : estimation des biais accéléromètre/gyroscope au repos (100 échantillons)
- **Filtre passe-bas** : atténuation du bruit haute fréquence (α = 0.1)
- **Suppression de la gravité** : projection basée sur pitch/roll
- **Transformation body → world** : rotation par le yaw estimé

### 3. ZUPT (Zero Velocity Update)
- Détection d'immobilité via la variance de la magnitude de l'accéléromètre
- Remise à zéro de la vitesse quand le dispositif est stationnaire
- Empêche la dérive de position au repos

### 4. Gestion de la Confiance
- Décroissance exponentielle de la confiance sans GPS
- Réinitialisation à 100% à chaque correction GPS
- Affichage visuel de l'incertitude de position

## Installation

```bash
# Cloner le projet
git clone <repo>
cd imu_navigator

# Installer les dépendances
flutter pub get

# Lancer sur appareil physique (REQUIS pour les capteurs IMU)
flutter run
```

> ⚠️ **IMPORTANT** : Cette application nécessite un **appareil physique** (pas un émulateur) car elle utilise l'accéléromètre et le gyroscope matériels.

## Permissions Requises

### Android (`AndroidManifest.xml`)
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `HIGH_SAMPLING_RATE_SENSORS`

### iOS (`Info.plist`)
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSMotionUsageDescription`

## Utilisation

1. **Démarrer** → L'app commence la calibration (gardez le téléphone immobile ~2s)
2. **Mode GPS** → Position par GPS avec fusion IMU (indicateur vert)
3. **Simuler perte GPS** → Passe en navigation inertielle (indicateur orange)
4. **Observer** → La position continue d'être estimée par double intégration
5. **Restaurer GPS** → Le filtre de Kalman corrige la dérive accumulée

## Limitations Connues

- **Dérive inertielle** : sans GPS, l'erreur de position croît quadratiquement (~1-5m après 30s selon le mouvement)
- **Calibration nécessaire** : les biais capteurs doivent être estimés au démarrage
- **Orientation du téléphone** : la transformation body→world suppose un téléphone tenu verticalement
- Le filtre complémentaire pour le yaw est simplifié (pas de magnétomètre)
