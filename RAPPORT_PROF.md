# RAPPORT PROF - Projet 806 (positionnement tunnel smartphone)

Date: 24/04/2026  
Etudiant: Thomas Cabot  
Application: `sensoritetest` (Flutter)

## 1. Sujet et objectif

Sujet de base: quand le GPS est perdu (ex: tunnel), predire la trajectoire a partir des capteurs du telephone (IMU), puis analyser la derive.

Objectif pratique du projet:
- maintenir une estimation continue de position,
- comparer IMU vs GPS quand possible,
- quantifier la derive,
- identifier une architecture robuste pour la suite (avec balises tunnel).

## 2. Capteurs, donnees et frequence

Capteurs utilises:
- accelerometre (`sensors_plus`) ~50 Hz (20 ms)
- gyroscope (`sensors_plus`) ~50 Hz (20 ms)
- GPS (`geolocator`, `bestForNavigation`, intervalle Android 500 ms)

Champs CSV enregistres:
- brut IMU: `ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw`
- etat estime: `est_lat, est_lon, est_vx, est_vy, est_speed, est_heading`
- GPS brut: `gps_lat, gps_lon, gps_speed, gps_accuracy`
- contexte: `mode, is_stationary, confidence, uncertainty`

## 3. Architecture logicielle

Fichiers principaux:
- `lib/navigation_service.dart`: orchestration runtime (capteurs, modes, sessions)
- `lib/kalman_filter.dart`: EKF, prediction, fusion GPS, NHC, calibration
- `lib/data_recorder.dart`: enregistrement CSV
- `lib/trace_screen.dart`: trace fin de session + ecart final
- `lib/live_map_screen.dart`: comparaison GPS vs IMU en direct

### 3.1 Modes

`NavigationMode`:
- `idle`
- `calibrating`
- `gps`
- `vsMode`
- `deadReckoning`
- `gpsDenied`

## 4. Pipeline exact de l'application

### 4.1 Demarrage (`start()`)

1. reset complet du filtre + trails + compteurs
2. demarrage flux IMU (accel + gyro)
3. demarrage flux GPS
4. demarrage enregistrement CSV
5. timer IMU a 20 ms -> `_processIMU()`

### 4.2 Calibration IMU

Pendant `calibrating`, collecte de `calibrationTarget = 100` echantillons.

Biais estimes:
- `biasAx = mean(ax)`
- `biasAy = mean(ay)`
- `biasAz = mean(az) - g`
- `biasGx = mean(gx)`
- `biasGy = mean(gy)`
- `biasGz = mean(gz)`

Raison: retirer l'offset capteur avant propagation.

### 4.3 Boucle IMU (`_processIMU()`)

A chaque tick:
1. calcul `dt`
2. `predict(ax, ay, az, gx, gy, gz, dt)`
3. `updateNHC()`
4. enregistrement CSV
5. ajout point de trace estimee toutes ~500 ms

### 4.4 Fusion GPS (`updateGPS()`)

Hors `vsMode`, chaque fix GPS corrige l'EKF.
En `vsMode`, GPS est conserve comme reference visuelle mais ne corrige pas l'EKF.

## 5. Modele mathematique (equations exactes)

## 5.1 Etat EKF

Etat:
`x = [x, y, vx, vy, ax, ay, yaw]`

- `(x, y)` en ENU local (metres)
- `(vx, vy)` en m/s
- `yaw` en radians

## 5.2 Pre-traitement IMU

1. Debiaisage:
- `ax <- ax - biasAx`, idem `ay, az, gx, gy, gz`

2. Filtre passe-bas accelerometre (`alpha = 0.1`):
- `a_f(k) = alpha * a(k) + (1 - alpha) * a_f(k-1)`

3. Filtre yaw-rate:
- deadband: si `|gz| < 0.03`, alors `gz = 0`
- clipping: `gz in [-1.2, +1.2]`

## 5.3 Detection stationnaire

Sur fenetre glissante (20 echantillons):
- magnitude: `m = sqrt(ax^2 + ay^2 + az^2)`
- variance de `m` sur la fenetre

`looksStationary = (variance < 0.02) AND (|m - g| < 0.35) AND (||gyro|| < 0.03)`

Stationnaire valide si `looksStationary` tient 50 echantillons consecutifs.

## 5.4 Prediction HYBRIDE (version retenue)

Cette version est volontairement **sans double integration accel->vitesse->position**.

1. Cap:
- `yaw_k = normalize(yaw_{k-1} + yawRateUsed * dt)`
- avec blocage des micro-virages en ligne droite:
  - si `|gz| < 0.07` et `|ax_lateral| < 0.30`, alors `yawRateUsed = 0`

2. Vitesse scalaire:
- `v_curr = sqrt(vx^2 + vy^2)`
- reference vitesse GPS maintenue (`v_ref`)
- lissage vers reference:
  - `alpha_v = 1 - exp(-3.0 * dt)`
  - `v_blend = v_curr + alpha_v * (v_ref - v_curr)`
  - contrainte variation max:
    - `maxDelta = 1.6 * dt`
    - `v_pred = clamp(v_blend, v_curr - maxDelta, v_curr + maxDelta)`
- si stationnaire et `v_pred < 1`, amortissement:
  - `v_pred <- v_pred * exp(-4 * dt)`

3. Projection par le cap:
- `vx_pred = v_pred * cos(yaw_k)`
- `vy_pred = v_pred * sin(yaw_k)`

4. Position:
- `x_pred = x + vx_pred * dt`
- `y_pred = y + vy_pred * dt`

5. Covariance:
- `P <- F * P * F^T + Q * dt`

## 5.5 Update GPS (EKF)

Mesure GPS convertie ENU:
- `z = [x_gps, y_gps, vx_gps, vy_gps]`
- `vx_gps = speed * sin(bearing)`
- `vy_gps = speed * cos(bearing)`

Update EKF standard:
- innovation: `y = z - Hx`
- covariance innovation: `S = HPH^T + R`
- gain: `K = PH^T S^-1`
- etat: `x <- x + Ky`
- covariance: `P <- (I - KH)P`

Bruit position GPS adapte:
- `R_xx = R_yy = accuracy^2`

Cap recale par bearing GPS si exploitable (`speed > 1.5` et bearing valide), sinon par direction de vitesse estimee.

## 5.6 Contrainte NHC (Non-Holonomic Constraint)

Hypothese vehicule routier: vitesse laterale proche de 0.

- vecteur lateral monde: `h = [-sin(yaw), cos(yaw)]`
- vitesse laterale:
  - `v_lat = vx * (-sin(yaw)) + vy * cos(yaw)`
- pseudo-mesure: `v_lat = 0`

Update scalaire Kalman applique a chaque pas IMU.

## 5.7 Conversion GPS <-> ENU

`gpsToLocal`:
- `dLat = (lat - lat_ref) * pi/180`
- `dLon = (lon - lon_ref) * pi/180`
- `x = dLon * R * cos(lat_moy)`
- `y = dLat * R`

`localToGPS` (inverse):
- `dLat = y / R`
- `dLon = x / (R * cos(lat_ref))`

avec `R = 6371000 m`.

## 6. Mesure de la derive (dans l'app)

Il y a 2 mesures d'ecart:

1. `TraceScreen` (`ECART`):
- dernier point IMU vs point GPS le plus proche en temps
- distance metrique locale:
  - `d = sqrt((dLat*R)^2 + (dLon*R*cos(lat_moy))^2)`

2. `LiveMapScreen` (`DRIFT`):
- estimation courante IMU vs derniere fix GPS
- meme formule de distance

## 7. Choix techniques et justification

### 7.1 Pourquoi l'hybride est retenu

La double integration pure est theoriquement INS, mais sur smartphone elle est tres sensible:
- biais gyro/accel,
- bruit,
- micro-mouvements du telephone,
- vibrations vehicule.

Resultat constate: oscillations, aller-retours, derive rapide.

La version hybride garde:
- cap inertiel (gyro),
- vitesse recalee par GPS (et demain par balises),
- NHC,
- EKF.

=> Plus robuste et plus exploitable pour le cas tunnel reel.

### 7.2 Alignement avec la suite "balises 100 m"

Le schema attendu par l'encadrement est coherent avec cette architecture:
- vitesse initiale GPS,
- puis recalage vitesse par balises: `v = distance_connue / delta_t`,
- propagation entre balises via `v + cap`.

## 8. Statistiques de tests obtenues

## 8.1 Tests de reference (23/04/2026)

| CSV | Duree VS | Dist IMU (m) | Dist GPS VS (m) | Ratio IMU/GPS | Ecart fin (m) |
|---|---:|---:|---:|---:|---:|
| `imu_2026-04-23_13-22-04.csv` | 70.5 s | 575.7 | 622.8 | 0.924 | 190.4 |
| `imu_2026-04-23_14-23-43.csv` | 63.2 s | 337.9 | 448.9 | 0.753 | 197.0 |
| `imu_2026-04-23_14-25-51.csv` | 69.4 s | 364.2 | 661.5 | 0.551 | 286.8 |
| `imu_2026-04-23_14-29-14_auto01.csv` | 60.0 s | 843.9 | 539.5 | 1.564 | 124.7 |

## 8.2 Nouveaux tests (24/04/2026)

| CSV | Contexte | Mode | Duree sans GPS | Dist IMU (m) | Dist GPS (m) | Ecart fin (m) | Observation |
|---|---|---|---:|---:|---:|---:|---|
| `imu_2026-04-24_04-45-32.csv` | VS classique | `vsMode` | 65.3 s | 725.7 | 885.8 | 156.7 | Amelioration globale, derive contenue |
| `imu_2026-04-24_04-50-11.csv` | Simulation tunnel (GPS OFF + avion) | `deadReckoning` | 70.6 s | 759.8 | 234.5 | 570.6 | Scenario reel sans reference GPS continue |

## 8.3 Lecture honnete des resultats

- En `vsMode`, comparaison IMU vs GPS pertinente et directement exploitable.
- En `deadReckoning` pur (GPS coupe), la distance GPS n'est plus une verite continue de meme nature: interpretation plus delicate.
- Les resultats montrent une amelioration nette par rapport aux runs les plus instables, mais une derive residuelle subsiste.

## 9. Limites actuelles

- Sensibilite a la qualite de pose du telephone.
- Biais gyro residuel sur longues phases sans recalage.
- Absence actuelle de balises physiques dans la boucle.

## 10. Conclusion pour le professeur

1. Le projet traite bien le sujet "prediction en perte GPS" avec capteurs smartphone.  
2. Deux approches ont ete evaluees (double integration pure vs hybride).  
3. L'approche retenue est l'hybride, car elle est plus robuste sur capteurs smartphone reels.  
4. Le pipeline est deja pret pour la suite balises (recalage vitesse/position periodique).  

En bref: le systeme actuel est une base technique credible pour la phase suivante de positionnement tunnel.

## 11. Annexes - Dossier `DATA/` (preuves experimentales)

### 11.1 CSV recents disponibles

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

### 11.2 Captures ecran recentes disponibles

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

### 11.3 Fichiers les plus utilises pour la synthese actuelle

- `DATA/imu_2026-04-24_04-45-32.csv` (run VS prometteur)
- `DATA/imu_2026-04-24_04-50-11.csv` (simulation tunnel, GPS coupe)
- `DATA/imu_2026-04-24_06-38-34.csv` (run double integration, derive marquee)
