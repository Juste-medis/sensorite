# Rapport d'etat des lieux - Projet 806 (positionnement inertiel)

Date: 24/04/2026  
Etudiant: Youssef  
Sujet: estimation de position en perte GPS (cas tunnel) avec smartphone IMU + GPS

## 1) Objectif et contexte

L'objectif est de maintenir une estimation de position quand le GPS est absent (tunnel ou zone masquee), puis de recaler la trajectoire quand le GPS revient.

Les essais ont ete faits sur smartphone Android, avec enregistrement CSV des donnees IMU/GPS et comparaison visuelle sur trace GPS (vert) vs trace IMU (orange).

## 2) Capteurs utilises

- Accelerometre (sensors_plus), environ 50 Hz
- Gyroscope (sensors_plus), environ 50 Hz
- GPS (geolocator, bestForNavigation)

Donnees enregistrees par echantillon:
- IMU brute: `ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw`
- Etat estime: `est_lat, est_lon, est_vx, est_vy, est_speed, est_heading`
- GPS brut: `gps_lat, gps_lon, gps_speed, gps_accuracy`
- Mode: `calibrating`, `gps`, `vsMode`, `deadReckoning`

## 3) Methode et filtres utilises

### 3.1 Filtre principal

- Filtre de Kalman etendu (EKF) 2D
- Etat: `[x, y, vx, vy, ax, ay, yaw]`
- Cadre local ENU (x Est, y Nord)

### 3.2 Pre-traitement

- Calibration biais IMU au demarrage (100 echantillons)
- Filtre passe-bas accelero
- Detection stationnaire plus stricte (variance accel + gyro + gravite)

### 3.3 Contraintes et fusion

- Propagation inertielle en perte GPS par double integration:
  - gyroscope `gz` integre en cap (`yaw`)
  - accelerations lineaires projetees dans le repere monde
  - integration accel -> vitesse -> position
- Contrainte NHC (Non-Holonomic Constraint): vitesse laterale attendue proche de zero pour vehicule
- Fusion GPS des positions/vitesses quand GPS disponible
- Recalage de l'etat au dernier GPS avant VS/perte GPS (`snapToGPS`) si la fix est recente

### 3.4 Mode VS et mode auto

- `VS mode`: GPS conserve comme reference, EKF non corrige pendant la fenetre de test
- `Auto`: cycles d'acquisition VS automatiques (attente + enregistrement + export)

Point important (reponse explicite):
- En `vsMode`, la prediction de trajectoire n'utilise plus de correction GPS (`updateGPS` est sautee).
- La propagation repose sur les capteurs internes du telephone (IMU: accelerometre + gyroscope) + contraintes du modele (NHC).
- Le GPS sert uniquement de reference d'affichage/comparaison pendant le VS.
- L'etat initial au debut du VS (position/vitesse/cap) reste initialise a partir de la derniere fix GPS valide.

### 3.5 Fonctionnement de l'app (pipeline runtime)

1. Demarrage session (`START`)
- reset complet d'etat (Kalman + trails + compteurs)
- ouverture flux IMU + GPS
- lancement enregistrement CSV

2. Calibration
- collecte ~100 echantillons IMU a l'arret
- estimation biais accelero/gyro
- passage en mode `gps` quand calibration terminee

3. Navigation GPS fusionnee
- chaque fix GPS corrige l'EKF (`updateGPS`)
- la prediction IMU tourne en continu (`predict` + `updateNHC`)

4. VS / perte GPS
- `startVSMode`: snapshot etat + purge traces de comparaison
- pendant VS: prediction IMU seule, GPS conserve uniquement comme verite terrain
- perte GPS hors VS: passage en `deadReckoning`

5. Fin de session
- arret des flux
- export CSV
- visualisation `Trace` et `Live Map`

### 3.6 Filtres utilises et justification (pourquoi)

- Calibration des biais IMU au demarrage (100 echantillons)  
  Pourquoi: supprimer l'offset capteurs au repos (sinon derive immediate en vitesse/cap).
- Filtre passe-bas accelerometre (alpha = 0.1)  
  Pourquoi: attenuer les vibrations vehicule et le bruit haute frequence avant la prediction.
- Detection stationnaire (fenetre de variance + seuil gyro + tolerance gravite)  
  Pourquoi: eviter d'integrer du bruit quand le vehicule est quasi a l'arret.
- EKF 2D (etat position/vitesse/cap)  
  Pourquoi: fusionner mesure et modele de mouvement avec une incertitude explicite.
- Double integration inertielle en phase sans GPS  
  Pourquoi: repondre a l'objectif "navigation autonome en tunnel" sans correction externe continue.
- Fusion GPS adaptative (bruit position ajuste via `gps_accuracy`)  
  Pourquoi: diminuer la confiance GPS quand la precision se degrade.
- NHC (Non-Holonomic Constraint: vitesse laterale ~ 0)  
  Pourquoi: imposer une contrainte physique vehicule pour limiter la derive transversale.
- `snapToGPS` conditionne a une fix recente (`_maxSnapAge = 1.2 s`)  
  Pourquoi: eviter un recalage sur un GPS trop vieux qui decale la trajectoire au debut du VS/DR.
- GPS plus frequent (`intervalDuration = 500 ms` sous Android)  
  Pourquoi: reduire la latence de correction en phase GPS.
- Filtrage yaw-rate gyro (`gz`): deadband + clipping  
  Pourquoi: couper le biais lent integre (courbure parasite) et rejeter les pics (choc/chute telephone).

## 4) Modifications realisees cette semaine

- Ajout et activation du NHC dans la boucle IMU (`updateNHC` apres `predict`)
- Passage calibration de 5 a 100 echantillons
- Correction de la conversion yaw interne <-> cap navigation
- Ajout de `snapToGPS` avant `vsMode` / perte GPS
- Allongement watchdog perte GPS (`gpsLossThreshold`) a 8 s
- Mode auto de collecte (sessions automatiques)
- Correctif important: reset complet de la session au `start()` pour eviter les etats herites d'un run precedent

Dernieres modifications (24/04) et justification:
- Ajout `Live Map` (GPS vs IMU en direct)  
  Justification: diagnostiquer la derive des les premieres secondes au lieu d'attendre l'analyse post-run.
- Rejet des snaps GPS trop anciens (`_maxSnapAge = 1.2 s`)  
  Justification: eviter un recalage sur une fix retardee qui introduit un decalage lateral initial.
- Demande GPS plus frequente (`AndroidSettings intervalDuration = 500 ms`)  
  Justification: reduire la latence des fixes et ameliorer la qualite du point de depart VS.
- Filtrage yaw-rate (`gz`) par deadband + clipping dans l'EKF  
  Justification: limiter la derive de cap provoquee par un biais gyro faible mais integre longtemps, et ignorer les pics (choc/chute telephone).
- Passage de la propagation DR a une vraie double integration inertielle (`a -> v -> p`)  
  Justification: alignement avec la methode attendue (estimation position sans GPS a partir de l'IMU seule), tout en conservant des garde-fous anti-bruit.

## 5) Resultats de tests (semaine)

### 5.1 Tests de reference (23/04/2026)

| CSV | Duree VS | Dist IMU (m) | Dist GPS VS (m) | Ratio IMU/GPS | Ecart fin (m) | Vitesse IMU moy (m/s) | Vitesse GPS moy VS (m/s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `imu_2026-04-23_13-22-04.csv` | 70.5 s | 575.7 | 622.8 | 0.924 | 190.4 | 8.17 | 9.39 |
| `imu_2026-04-23_14-23-43.csv` | 63.2 s | 337.9 | 448.9 | 0.753 | 197.0 | 5.38 | 7.61 |
| `imu_2026-04-23_14-25-51.csv` | 69.4 s | 364.2 | 661.5 | 0.551 | 286.8 | 5.27 | 10.08 |
| `imu_2026-04-23_14-29-14_auto01.csv` | 60.0 s | 843.9 | 539.5 | 1.564 | 124.7 | 14.13 | 10.62 |

### 5.2 Nouveaux tests (24/04/2026)

| CSV | Contexte de test | Mode principal de test | Duree sans GPS | Dist IMU (m) | Dist GPS (m) | Ecart fin (m) | Observation |
|---|---|---|---:|---:|---:|---:|---|
| `imu_2026-04-24_04-45-32.csv` | VS classique (GPS actif en reference) | `vsMode` | 65.3 s | 725.7 | 885.8 | 156.7 | Resultat globalement prometteur; derive encore presente mais contenue |
| `imu_2026-04-24_04-50-11.csv` | Simulation tunnel (position OFF + mode avion) | `deadReckoning` (pas de `vsMode`) | 70.6 s | 759.8 | 234.5 | 570.6 | Test valide pour scenario reel de perte GPS, mais non comparable numeriquement a un VS pur |

### 5.3 Lecture des nouveaux essais

- Le test `04-45-32` montre une amelioration nette de stabilite.
- Le test `04-50-11` presente une derive plus forte, mais il n'a pas tourne en `vsMode` (CSV: 0 point en `vsMode`, majorite en `deadReckoning`) car GPS volontairement coupe.
- L'incident "telephone tombe" explique les pics d'orientation transitoires observes sur un des runs.

### 5.4 Comment lire correctement VS vs DR simule

- `vsMode`: GPS actif en fond, mais non utilise pour corriger l'EKF. Sert a comparer proprement IMU vs reference GPS.
- `deadReckoning` simule (mode avion / GPS OFF): cas d'usage tunnel realiste, mais sans reference GPS continue pendant le run.
- Consequence: les metriques "distance IMU vs distance GPS" sont tres utiles en VS, mais plus delicates a interpreter en DR simule pur.

## 6) Probleme principal identifie

Le point limitant principal reste la stabilite du cap (heading) dans la duree:
- certains runs gardent une bonne coherence directionnelle;
- d'autres partent correct puis derivent progressivement.

Deux causes techniques ont ete traitees:
- etat session non remis a zero au `start()` (corrige);
- recalage sur GPS trop ancien a l'entree VS/perte GPS (corrige).

Cause encore sensible selon run:
- petit biais gyro integre sur longue duree (attenue avec deadband/clipping, a confirmer sur plus de campagnes).

## 7) Positionnement pour la suite (balises)

Pour la suite du projet (avec balises), la strategie la plus robuste est:
- vitesse estimee a partir du temps entre balises (distance connue / delta t),
- recalage position sur balise,
- IMU utilisee principalement pour l'orientation entre balises.

Cette approche reduit fortement l'impact des derivees de vitesse IMU.

## 8) Conclusion (etat des lieux)

- Le pipeline IMU+GPS est operationnel et instrumente (CSV complets + traces + live map).
- Le NHC est integre et actif.
- Les derniers runs sont plus prometteurs, avec une derive reduite sur certains scenarios VS.
- La stabilite run-to-run n'est pas encore totalement verrouillee, mais la trajectoire d'amelioration est claire.

## 9) Annexes a joindre (captures et CSV)

Captures principales:
- `C:\\Users\\yucce\\Downloads\\Screenshot_2026-04-23-13-21-54-742_com.example.sensoritetest.jpg`
- `C:\\Users\\yucce\\Downloads\\Screenshot_2026-04-23-13-03-24-042_com.example.sensoritetest.jpg`
- `C:\\Users\\yucce\\Documents\\DATA\\Screenshot_2026-04-23-14-22-58-003_com.example.sensoritetest.jpg`
- `C:\\Users\\yucce\\Documents\\DATA\\Screenshot_2026-04-23-14-25-47-164_com.example.sensoritetest.jpg`
- `C:\\Users\\yucce\\Documents\\DATA\\Screenshot_2026-04-23-14-33-08-707_com.example.sensoritetest.jpg`
- `C:\\Users\\yucce\\Documents\\DATA\\Screenshot_2026-04-24-04-45-57-429_com.example.sensoritetest.jpg`
- `C:\\Users\\yucce\\Documents\\DATA\\Screenshot_2026-04-24-04-50-04-653_com.example.sensoritetest.jpg`

CSV de reference:
- `C:\\Users\\yucce\\Downloads\\imu_2026-04-23_13-22-04.csv`
- `C:\\Users\\yucce\\Documents\\DATA\\imu_2026-04-23_14-23-43.csv`
- `C:\\Users\\yucce\\Documents\\DATA\\imu_2026-04-23_14-25-51.csv`
- `C:\\Users\\yucce\\Documents\\DATA\\imu_2026-04-23_14-29-14_auto01.csv`
- `C:\\Users\\yucce\\Documents\\DATA\\imu_2026-04-24_04-45-32.csv`
- `C:\\Users\\yucce\\Documents\\DATA\\imu_2026-04-24_04-50-11.csv`
