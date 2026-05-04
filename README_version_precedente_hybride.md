# README - Version precedente (hybride IMU/GPS)

Ce document decrit la version precedente de l'application (avant le passage a la double integration inertielle pure), avec le detail du fonctionnement et du calcul de derive.

## 1) Idee generale

La version precedente est une approche **inertielle contrainte**:

- IMU (accelerometre + gyroscope) utilisee en continu.
- GPS utilise pour corriger l'etat quand disponible.
- En VS mode, le GPS n'est plus utilise pour corriger l'EKF (il reste seulement une reference de comparaison).
- Le modele de prediction etait volontairement robuste:
  - cap (yaw) pilote par gyro `gz`
  - vitesse surtout conservee via l'etat precedent (pas de double integration accel complete)
  - contrainte NHC pour limiter la vitesse laterale

## 2) Capteurs et frequences

- IMU: ~50 Hz (`20 ms`) via `sensors_plus`
- GPS: stream `geolocator` (`bestForNavigation`, puis intervalle Android 500 ms dans les dernieres iter)

Fichier principal runtime: `lib/navigation_service.dart`

## 3) Pipeline complet

### 3.1 Start session

Au `start()`:

- reset complet du filtre et des buffers
- demarrage flux IMU + GPS
- demarrage enregistrement CSV
- mode initial `calibrating`

### 3.2 Calibration

Pendant calibration:

- collecte 100 echantillons
- estimation des biais accel/gyro
- passage en mode navigation quand calibration terminee

### 3.3 Prediction IMU (version precedente)

Dans `_processIMU()`:

1. calcul de `dt`
2. appel `predict(ax, ay, az, gx, gy, gz, dt)`
3. appel `updateNHC()`
4. enregistrement CSV
5. ajout d'un point de trace estimee toutes les ~500 ms

Logique `predict()` de la version precedente (hybride):

- integration du cap: `yaw = yaw + gz * dt`
- vitesse majoritairement conservee (surtout entre fixes GPS)
- projection vitesse sur cap pour obtenir `(vx, vy)`
- integration position avec cette vitesse

Donc:

- ce n'etait pas une double integration accel pure,
- mais c'etait bien une prediction inertielle (IMU + modele vehicule + contraintes).

### 3.4 Fusion GPS

Quand GPS dispo et hors VS mode:

- `updateGPS(...)` corrige position/vitesse EKF
- covariance ajustee par `gps_accuracy`

Quand VS mode actif:

- `updateGPS` n'est pas applique a l'EKF
- GPS est conserve pour la reference d'affichage (`gpsTrail`)

### 3.5 VS mode

`startVSMode()`:

- snap initial optionnel sur derniere fix GPS valide
- purge des traces pour comparer proprement la nouvelle sequence
- passage en `vsMode`

## 4) A quel moment la derive est mesuree ?

Important: la derive n'est pas stockee en continu dans `NavigationService`.
Elle est calculee dans l'UI a partir des traces.

### 4.1 Ecart dans `TraceScreen`

Fichier: `lib/trace_screen.dart`

Calcul dans `_stats`:

- prend le dernier point IMU (`imu.last`)
- trouve le point GPS le plus proche en temps (timestamp)
- derive = distance metrique entre ces 2 points

En pratique:

- c'est un **ecart final** de session/sequence (ou ecart courant selon ce qui est affiche)
- c'est la valeur affichee dans la case `ECART`

### 4.2 Drift dans `LiveMapScreen`

Fichier: `lib/live_map_screen.dart`

Calcul live:

- drift = distance entre la derniere position GPS et l'estimation courante IMU

Donc:

- `TraceScreen` = comparaison temporelle (point GPS le plus proche du dernier IMU)
- `LiveMapScreen` = comparaison instantanee a la derniere fix GPS disponible

## 5) Filtres/contraintes utilises dans cette version

- Calibration biais IMU
- Filtre passe-bas accel
- Detection stationnaire
- EKF 2D
- NHC (vitesse laterale proche de zero)
- Snap initial sur GPS (avec garde-fou d'age max dans les versions recentes)

## 6) Pourquoi cette version etait souvent plus stable que la version "double integration pure"

- La double integration accel pure derive tres vite sur smartphone (bruit + biais + orientation imparfaite).
- La version precedente imposait plus de structure:
  - vitesse moins libre
  - trajectoire guidee par cap + contraintes vehicule
  - corrections GPS plus structurantes avant la perte

Conclusion:

- Version precedente = moins "academique pure IMU", mais plus robuste en pratique terrain.
- Version double integration = plus "inertielle pure", mais derive fortement sans recalages externes.

## 7) Donnees recentes integrees (dossier `DATA/`)

Les fichiers de test les plus recents sont centralises dans le dossier local `DATA/`.
Ils servent de base factuelle pour le rapport et la comparaison VS/IMU.

### 7.1 CSV disponibles

- `DATA/imu_2026-04-23_14-23-43.csv`
- `DATA/imu_2026-04-23_14-25-51.csv`
- `DATA/imu_2026-04-23_14-29-14_auto01.csv`
- `DATA/imu_2026-04-24_04-03-53.csv`
- `DATA/imu_2026-04-24_04-06-34.csv`
- `DATA/imu_2026-04-24_04-24-33.csv`
- `DATA/imu_2026-04-24_04-31-52.csv`
- `DATA/imu_2026-04-24_04-45-32.csv`
- `DATA/imu_2026-04-24_04-50-11.csv`
- `DATA/imu_2026-04-24_06-38-34.csv`

### 7.2 Captures disponibles

- `DATA/Screenshot_2026-04-23-14-22-58-003_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-23-14-25-47-164_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-23-14-33-08-707_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-04-03-49-150_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-04-06-43-996_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-04-24-37-044_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-04-31-56-591_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-04-45-57-429_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-04-50-04-653_com.example.sensoritetest.jpg`
- `DATA/Screenshot_2026-04-24-06-38-37-715_com.example.sensoritetest.jpg`

### 7.3 Fichiers references pour la synthese actuelle

Pour la synthese du 24/04 (rapport + conclusions techniques), les runs les plus utilises sont:

- `DATA/imu_2026-04-24_04-45-32.csv` (run VS prometteur)
- `DATA/imu_2026-04-24_04-50-11.csv` (simulation tunnel, GPS coupe)
- `DATA/imu_2026-04-24_06-38-34.csv` (run double integration, derive marquee)
