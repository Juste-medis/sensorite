# Rapport technique - Version hybride sans double integration

Date: 24/04/2026  
Projet: Positionnement inertiel smartphone en perte GPS (cas tunnel)  
Auteur: Youssef

## 1) Objectif du document

Ce document decrit la logique de la version hybride (sans double integration accel complete), en expliquant:

- pourquoi ce choix a ete fait,
- comment le code fonctionne exactement,
- quels filtres/contraintes sont appliques,
- a quel moment la derive est mesuree.

Le but est d'avoir un document clair et defendable devant un encadrant.

## 2) Pourquoi ne pas utiliser la double integration pure

La double integration inertielle pure (acceleration -> vitesse -> position) est mathematiquement correcte, mais en pratique smartphone elle derive tres vite a cause de:

- biais capteurs (gyro/accel) meme faibles,
- bruit haute frequence des IMU grand public,
- orientation telephone imparfaite (pas toujours rigidement alignee vehicule),
- vibrations chassis et micro-chocs.

Consequence: un biais accel tres faible cree une erreur de vitesse puis une erreur de position quadratique dans le temps.

Donc, pour une solution exploitable terrain, la version precedente a utilise une approche hybride:

- cap inertiel (gyro),
- contrainte vehicule NHC (vitesse laterale proche de zero),
- vitesse/etat stabilises par la fusion GPS tant que GPS disponible,
- prediction IMU seule pendant VS/perte GPS.

## 3) Architecture logicielle (version hybride)

Fichiers principaux:

- `lib/navigation_service.dart`: orchestration capteurs, modes, enregistrement, flux runtime.
- `lib/kalman_filter.dart`: EKF, prediction, fusion GPS, NHC, calibration.
- `lib/trace_screen.dart`: affiche trace session et calcule l'ecart final.
- `lib/live_map_screen.dart`: affiche GPS vs IMU en direct et drift live.
- `lib/data_recorder.dart`: ecriture CSV.

## 4) Machine d'etat et modes

Modes utilises:

- `idle`: arret.
- `calibrating`: estimation biais IMU au repos.
- `gps`: fusion GPS + IMU.
- `vsMode`: GPS en reference uniquement, EKF non corrige par GPS.
- `deadReckoning`: perte GPS hors VS (prediction inertielle).
- `gpsDenied`: GPS indisponible.

Transitions principales:

1. `start()` -> `calibrating`
2. calibration terminee + GPS OK -> `gps`
3. lancement VS -> `vsMode`
4. perte GPS hors VS -> `deadReckoning`
5. stop -> `idle`

## 5) Fonctionnement exact du runtime

### 5.1 Demarrage session

`NavigationService.start()`:

- reset complet etat Kalman + trails + compteurs,
- demarrage flux IMU (20 ms),
- demarrage flux GPS,
- demarrage enregistrement CSV,
- timer IMU periodique qui appelle `_processIMU()`.

### 5.2 Calibration

Dans `IMUKalmanFilter.addCalibrationSample(...)`:

- collecte `calibrationTarget = 100` echantillons,
- calcul moyenne de `ax, ay, az, gx, gy, gz`,
- biais fixes:
  - `biasAx = mean(ax)`
  - `biasAy = mean(ay)`
  - `biasAz = mean(az) - gravity`
  - `biasGx = mean(gx)`, `biasGy = mean(gy)`, `biasGz = mean(gz)`

Utilite: compenser l'offset capteur avant prediction.

### 5.3 Boucle IMU

`_processIMU()`:

1. calcule `dt` via timestamp.
2. si non calibre: continue calibration.
3. sinon:
   - `_kalman.predict(...)`
   - `_kalman.updateNHC()`
   - enregistre une ligne CSV
   - ajoute un point de trace estimee toutes ~500 ms
4. `notifyListeners()` periodique pour UI.

### 5.4 Prediction EKF - logique hybride (sans double integration accel)

Dans la version hybride, la prediction suit cette logique:

1. retrait biais IMU:
   - `ax -= biasAx`, `...`, `gz -= biasGz`
2. filtrage passe-bas accel.
3. detection stationnaire.
4. integration cap:
   - `yaw = x[6] + gz * dt`
5. vitesse predite:
   - `currentSpeed = sqrt(vx^2 + vy^2)`
   - `predictedSpeed = currentSpeed`
   - si stationnaire et vitesse faible: amortissement.
6. projection vitesse sur cap:
   - `predVx = predictedSpeed * cos(yaw)`
   - `predVy = predictedSpeed * sin(yaw)`
7. integration position:
   - `x = x + predVx * dt`
   - `y = y + predVy * dt`
8. covariance:
   - `P = F * P * F^T + Q * dt`

Point cle: la vitesse n'est pas pilotee par une integration accel pure continue.  
C'est volontaire pour limiter la derive rapide.

### 5.5 Fusion GPS

Quand GPS dispo et hors VS:

- `updateGPS(lat, lon, speed, bearing, accuracy)`
- conversion GPS -> ENU local.
- mesure EKF: `[x, y, vx, vy]`
- bruit position adapte avec `accuracy^2`.
- correction Kalman standard.
- cap corrige avec bearing GPS si exploitable.

### 5.6 VS mode (ce qui est IMU et ce qui est GPS)

Au `startVSMode()`:

- recalage initial optionnel sur derniere fix GPS valide (`snapToGPS`),
- purge des traces IMU/GPS pour comparaison propre,
- passage mode `vsMode`.

Pendant `vsMode`:

- IMU continue a predire l'etat.
- GPS continue a etre enregistre comme reference.
- MAIS `updateGPS` n'est pas applique au filtre (pas de correction EKF).

Donc la trajectoire IMU en VS est bien une prediction inertielle libre apres initialisation.

## 6) Filtres et contraintes appliques (et pourquoi)

### 6.1 Filtre passe-bas accelerometre

- coefficient `alpha = 0.1`
- but: retirer bruit rapide/vibrations.

### 6.2 Detection stationnaire

Parametres:

- fenetre variance `20`,
- seuil variance `0.02`,
- seuil gyro `0.03 rad/s`,
- tolerance gravite `0.35`,
- validation sur `50` echantillons.

But:

- eviter d'integrer du bruit quand vehicule quasi immobile.

### 6.3 NHC (Non-Holonomic Constraint)

Hypothese vehicule routier:

- vitesse laterale (perpendiculaire au cap) proche de zero.

Implementation:

- pseudo-mesure `v_lateral = 0` injectee comme update Kalman.

But:

- limiter derive transversale.

### 6.4 Snap GPS avec garde-fou d'age

- avant VS/perte GPS, `snapToGPS` peut recaler position/vitesse/cap.
- garde-fou `_maxSnapAge = 1.2 s` pour ignorer les fixes trop anciennes.

But:

- eviter un decalage initial si la derniere fix est retardee.

### 6.5 GPS plus frequent (Android)

- `intervalDuration = 500 ms`, `distanceFilter = 0`.

But:

- meilleure fraicheur des corrections en phase GPS.

## 7) Quand et comment la derive est mesuree

Important: la derive n'est pas une variable EKF unique en interne.  
Elle est calculee au niveau affichage a partir des traces.

### 7.1 Dans `TraceScreen`

Calcul de `ECART`:

- prend dernier point IMU,
- cherche point GPS le plus proche en temps,
- calcule distance metrique entre ces deux points.

Interpretation:

- ecart final (ou courant) de la sequence analysee.

### 7.2 Dans `LiveMapScreen`

Calcul de `DRIFT`:

- distance entre derniere fix GPS disponible et estimation courante IMU.

Interpretation:

- ecart live instantane.

## 8) Limites connues de la version hybride

- Le modele suppose un montage telephone relativement stable.
- En cas de choc/chute telephone, le cap peut etre perturbe.
- Sans recalages externes (balises), une derive reste ineluctable sur longues durees.

## 9) Pourquoi cette version reste pertinente

Malgre l'absence de double integration accel pure, cette version:

- respecte l'objectif "prediction en perte GPS",
- utilise effectivement l'IMU en continu,
- est plus robuste en pratique que l'inertiel pur smartphone,
- constitue une base coherente pour la suite avec balises tunnel
  (vitesse recalee entre balises, cap IMU entre balises, correction position aux balises).

## 10) Conclusion

La version hybride sans double integration pure est un compromis "ingenierie terrain":

- moins academique qu'un strapdown pur,
- mais plus stable et defendable pour un systeme realiste smartphone + tunnel.

Le passage futur par des balises permettra de contraindre la derive residuelle
et d'ameliorer fortement la qualite de positionnement.
