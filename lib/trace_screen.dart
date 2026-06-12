import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_service.dart';

/// Écran affichant le tracé d'une session de navigation enregistrée.
///
/// Compare visuellement, sur une carte, la trajectoire estimée par l'IMU
/// (centrale inertielle) à la trajectoire de référence du GPS, et affiche
/// des statistiques (nombre de points, distances parcourues, écart final).
///
/// Reçoit en paramètres :
/// - [trail] : la liste complète des enregistrements de position estimés
///   (mélange de points IMU et éventuellement GPS, distingués via `fromGPS`).
/// - [gpsTrail] : la liste des enregistrements de position issus du GPS.
///
/// Cet écran est typiquement ouvert (via une navigation) à la fin ou pendant
/// une session pour visualiser et comparer les deux trajectoires.
// StatefulWidget : widget dont l'apparence peut changer au cours du temps.
// Il se découpe en 2 classes : le widget lui-même (immuable, ne contient que
// les paramètres) et son State (mutable, contient les données qui évoluent).
class TraceScreen extends StatefulWidget {
  // `final` : ces paramètres sont fixés à la construction et ne changent plus.
  // C'est le State (plus bas) qui porte ce qui est modifiable.
  /// Liste des enregistrements de position estimés (trace IMU/fusion).
  final List<PositionRecord> trail;

  /// Liste des enregistrements de position de référence issus du GPS.
  final List<PositionRecord> gpsTrail;

  /// Construit l'écran de tracé.
  ///
  /// Prend [trail] (trace estimée) et [gpsTrail] (trace GPS), tous deux
  /// obligatoires. Appelé par le widget parent qui navigue vers cet écran.
  const TraceScreen({
    super.key,
    required this.trail,
    required this.gpsTrail,
  });

  /// Crée l'état mutable [_TraceScreenState] associé à ce widget.
  ///
  /// Appelé automatiquement par le framework Flutter lors de l'insertion
  /// du widget dans l'arbre. Renvoie l'instance d'état qui gère la carte.
  // createState() : appelé une fois par Flutter pour relier le widget à son
  // objet d'état. C'est le pont obligatoire entre StatefulWidget et State.
  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

/// État de [TraceScreen] : gère le contrôleur de carte, l'affichage des
/// statistiques et la construction de la vue cartographique des trajectoires.
// Le State contient l'état mutable et la méthode build(). Depuis ici, on accède
// aux paramètres du widget via `widget.xxx` (ex. widget.trail).
class _TraceScreenState extends State<TraceScreen> {
  // `late final` : la valeur sera affectée plus tard (dans initState), mais une
  // seule fois. `late` permet de différer l'initialisation après la déclaration.
  /// Contrôleur de la carte [FlutterMap], utilisé pour recentrer/zoomer.
  late final MapController _mapController;

  /// Indique si le panneau de statistiques est actuellement affiché.
  bool _showStats = true;

  /// Initialise l'état du widget.
  ///
  /// Ne prend pas de paramètre et ne renvoie rien. Crée le [MapController].
  /// Appelé une seule fois par le framework lors de la création de l'état,
  /// avant le premier `build`.
  // initState() : appelé une seule fois à la création du State, avant le premier
  // build. Idéal pour initialiser des contrôleurs. On appelle toujours
  // super.initState() en premier.
  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  /// Libère les ressources de l'état.
  ///
  /// Ne prend pas de paramètre et ne renvoie rien. Détruit le [MapController]
  /// pour éviter les fuites mémoire. Appelé par le framework lorsque le widget
  /// est retiré définitivement de l'arbre.
  // dispose() : symétrique de initState, appelé quand le widget disparaît
  // définitivement. On y libère les ressources (ici le MapController) pour éviter
  // les fuites mémoire. super.dispose() est appelé en dernier.
  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Convertit la trace GPS en liste de coordonnées [LatLng].
  ///
  /// Ne prend pas de paramètre. Renvoie la liste des points GPS prêts à être
  /// tracés sur la carte. Utilisé par `build` et `_stats`.
  // Getter calculé : ce n'est pas une variable stockée, mais une propriété
  // recalculée à chaque accès. `.map(...)` transforme chaque élément de la liste
  // et `.toList()` matérialise le résultat (map renvoie un Iterable paresseux).
  // LatLng = type de coordonnée (latitude, longitude) attendu par flutter_map.
  List<LatLng> get _gpsPoints =>
      widget.gpsTrail.map((p) => LatLng(p.lat, p.lon)).toList();

  /// Convertit la trace estimée (IMU) en liste de coordonnées [LatLng].
  ///
  /// Ne prend pas de paramètre. Filtre [TraceScreen.trail] pour ne garder que
  /// les points non issus du GPS (`fromGPS == false`), puis les convertit en
  /// [LatLng]. Renvoie la liste des points IMU. Utilisé par `build` et `_stats`.
  // `.where(...)` filtre la liste (garde les éléments où le test est vrai).
  // Ici on ne conserve que les points NON issus du GPS (donc estimés par l'IMU).
  List<LatLng> get _imuPoints => widget.trail
      .where((p) => !p.fromGPS)
      .map((p) => LatLng(p.lat, p.lon))
      .toList();

  /// Calcule le centre géographique moyen des deux trajectoires.
  ///
  /// Ne prend pas de paramètre. Fait la moyenne des latitudes et longitudes de
  /// tous les points GPS et IMU. Renvoie le [LatLng] central, ou `null` si
  /// aucune donnée n'est disponible. Utilisé par `build` pour centrer la carte.
  // Type de retour `LatLng?` : le `?` indique que la valeur peut être null
  // (cas où il n'y a aucune donnée). Dart force alors à gérer ce cas null.
  LatLng? get _center {
    // `...` (spread) déverse le contenu de plusieurs listes dans une nouvelle.
    // Ici on fusionne tous les points GPS + tous les points IMU.
    final all = [...widget.gpsTrail, ...widget.trail.where((p) => !p.fromGPS)];
    if (all.isEmpty) return null;
    // `.reduce(...)` combine tous les éléments en une seule valeur : ici la
    // somme de toutes les latitudes, divisée par le nombre => moyenne.
    final lat = all.map((p) => p.lat).reduce((a, b) => a + b) / all.length;
    final lon = all.map((p) => p.lon).reduce((a, b) => a + b) / all.length;
    return LatLng(lat, lon);
  }

  /// Calcule les statistiques de comparaison entre les traces IMU et GPS.
  ///
  /// Ne prend pas de paramètre. Calcule le nombre de points, la distance
  /// parcourue (somme des distances entre points consécutifs) pour chaque
  /// trace, et l'écart final (distance entre le dernier point IMU et le point
  /// GPS le plus proche dans le temps). Renvoie une map libellé -> valeur
  /// formatée. Utilisé par `_buildStatsPanel` pour alimenter le panneau.
  Map<String, String> get _stats {
    final imu = _imuPoints;
    final gps = _gpsPoints;

    double imuDist = 0;
    for (int i = 1; i < imu.length; i++) {
      imuDist += _distMeters(imu[i - 1], imu[i]);
    }

    double gpsDist = 0;
    for (int i = 1; i < gps.length; i++) {
      gpsDist += _distMeters(gps[i - 1], gps[i]);
    }

    String driftStr = '-';
    if (gps.isNotEmpty && imu.isNotEmpty) {
      // Trouve le point GPS le plus proche dans le temps du dernier point IMU
      final lastImuTime = widget.trail.lastWhere((p) => !p.fromGPS).timestamp;
      PositionRecord closest = widget.gpsTrail.first;
      for (final g in widget.gpsTrail) {
        if (g.timestamp.difference(lastImuTime).abs() <
            closest.timestamp.difference(lastImuTime).abs()) {
          closest = g;
        }
      }
      final drift = _distMeters(imu.last, LatLng(closest.lat, closest.lon));
      driftStr = '${drift.toStringAsFixed(1)} m';
    }

    String fmtDist(double d) =>
        d >= 1000 ? '${(d / 1000).toStringAsFixed(2)} km' : '${d.toStringAsFixed(0)} m';

    return {
      'GPS': '${gps.length} pts',
      'IMU': '${imu.length} pts',
      'DIST. GPS': fmtDist(gpsDist),
      'DIST. IMU': fmtDist(imuDist),
      'ÉCART': driftStr,
    };
  }

  /// Calcule la distance en mètres entre deux points géographiques.
  ///
  /// Prend en paramètres [a] et [b], deux coordonnées [LatLng]. Utilise une
  /// approximation équirectangulaire (rayon terrestre 6371 km) pour calculer
  /// la distance. Renvoie cette distance en mètres. Méthode statique appelée
  /// par `_stats` pour cumuler les distances et mesurer l'écart final.
  static double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final mLat = (a.latitude + b.latitude) / 2 * pi / 180;
    return sqrt(pow(dLat * r, 2) + pow(dLon * r * cos(mLat), 2));
  }

  /// Construit l'interface de l'écran de tracé.
  ///
  /// Prend en paramètre le [context] de construction. Renvoie un [Scaffold]
  /// composé de : une barre supérieure avec la légende (GPS/IMU) et un bouton
  /// pour afficher/masquer les statistiques ; un corps contenant soit un
  /// message si aucune donnée n'est disponible, soit une carte [FlutterMap]
  /// affichant les tuiles OpenStreetMap, la polyligne GPS (verte), la
  /// polyligne IMU (orange pointillée) et les marqueurs (départ/arrivée GPS,
  /// fin IMU) ; le panneau de statistiques en bas si activé ; et un bouton
  /// flottant pour ajuster le cadrage de la carte sur l'ensemble des points.
  /// Appelé par le framework Flutter à chaque (re)construction de l'écran.
  // build() : décrit l'interface à partir de l'état courant. Flutter le rappelle
  // à chaque rafraîchissement (notamment après un setState). On y construit un
  // arbre de widgets imbriqués.
  @override
  Widget build(BuildContext context) {
    final center = _center;
    final gpsPoints = _gpsPoints;
    final imuPoints = _imuPoints;
    final hasData = gpsPoints.isNotEmpty || imuPoints.isNotEmpty;

    // Scaffold : squelette d'écran Material. Il fournit des emplacements
    // prêts à l'emploi : appBar (barre du haut), body (contenu), floatingActionButton...
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1220),
        foregroundColor: Colors.white,
        title: const Text(
          'TRACÉ DE SESSION',
          style: TextStyle(fontSize: 15, letterSpacing: 3, fontWeight: FontWeight.w600),
        ),
        actions: [
          // Légende
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                _legendDot(const Color(0xFF00E676), 'GPS'),
                const SizedBox(width: 10),
                _legendDot(const Color(0xFFFF6B35), 'IMU'),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _showStats ? Icons.info : Icons.info_outline,
                    color: _showStats ? const Color(0xFF00E5FF) : Colors.white38,
                  ),
                  // setState(...) : prévient Flutter qu'une donnée d'état a
                  // changé. Le framework reconstruit alors le widget (build) pour
                  // refléter la nouvelle valeur de _showStats à l'écran.
                  onPressed: () => setState(() => _showStats = !_showStats),
                ),
              ],
            ),
          ),
        ],
      ),
      // Column : empile ses enfants verticalement (du haut vers le bas).
      body: Column(
        children: [
          // Expanded : à l'intérieur d'une Column, cet enfant prend tout
          // l'espace vertical restant (ici la carte occupe le reste de l'écran).
          Expanded(
            // Opérateur ternaire `condition ? A : B` : choisit le widget à
            // afficher. Sans données -> message ; sinon -> la carte FlutterMap.
            child: !hasData
                ? const Center(
                    child: Text(
                      'Aucune donnée enregistrée.\nLancer une session et activer le mode VS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                // FlutterMap : widget de carte. Il fonctionne par empilement de
                // couches (children) dessinées les unes au-dessus des autres :
                // le fond de carte d'abord, puis les tracés, puis les marqueurs.
                : FlutterMap(
                    // On lui passe le contrôleur créé dans initState pour pouvoir
                    // piloter la carte (recadrer) depuis le code.
                    mapController: _mapController,
                    options: MapOptions(
                      // `??` (si-null) : utilise center, ou Paris par défaut si
                      // center vaut null (aucune donnée pour calculer le centre).
                      initialCenter: center ?? const LatLng(48.8566, 2.3522),
                      initialZoom: 16,
                    ),
                    children: [
                      // Couche 1 (fond) : tuiles OpenStreetMap (gratuites, sans
                      // clé d'API). Le template {z}/{x}/{y} = zoom/colonne/ligne.
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sensoritetest',
                      ),
                      // `if (...)` dans une liste (collection-if) : ajoute la
                      // couche seulement si la condition est vraie. Ici on ne
                      // trace la ligne GPS que s'il y a au moins 2 points.
                      // PolylineLayer dessine une ou plusieurs lignes brisées
                      // reliant des coordonnées. Trace GPS (verte).
                      if (gpsPoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: gpsPoints,
                              color: const Color(0xFF00E676),
                              strokeWidth: 3.5,
                            ),
                          ],
                        ),
                      // Seconde polyligne, dessinée par-dessus la GPS : trace
                      // IMU (orange, en pointillés pour la distinguer).
                      if (imuPoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: imuPoints,
                              color: const Color(0xFFFF6B35),
                              strokeWidth: 3.0,
                              pattern: StrokePattern.dashed(
                                segments: const [12, 6],
                              ),
                            ),
                          ],
                        ),
                      // Couche du dessus : MarkerLayer place des widgets
                      // (épingles/pastilles) à des coordonnées précises.
                      // Marqueurs : départ GPS, arrivée GPS, fin IMU.
                      MarkerLayer(
                        markers: [
                          if (gpsPoints.isNotEmpty)
                            _marker(gpsPoints.first, const Color(0xFF00E676), 'D'),
                          if (gpsPoints.isNotEmpty)
                            _marker(gpsPoints.last, Colors.white70, 'A'),
                          if (imuPoints.isNotEmpty)
                            _marker(imuPoints.last, const Color(0xFFFF6B35), '?'),
                        ],
                      ),
                    ],
                  ),
          ),
          // collection-if à nouveau : le panneau de stats n'est ajouté à la
          // Column que si l'utilisateur l'a activé ET qu'il y a des données.
          if (_showStats && hasData) _buildStatsPanel(),
        ],
      ),
      // floatingActionButton : bouton rond flottant en bas à droite (Scaffold).
      // null = aucun bouton (cas sans données).
      floatingActionButton: hasData
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF141B2D),
              foregroundColor: const Color(0xFF00E5FF),
              onPressed: () {
                final all = [...gpsPoints, ...imuPoints];
                if (all.isEmpty) return;
                // Calcule la zone rectangulaire englobant tous les points, puis
                // demande au contrôleur de carte d'y ajuster la caméra (zoom +
                // recentrage automatiques) pour que tout soit visible.
                final bounds = LatLngBounds.fromPoints(all);
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                );
              },
              child: const Icon(Icons.fit_screen),
            )
          : null,
    );
  }

  /// Construit un élément de légende (trait coloré + libellé).
  ///
  /// Prend en paramètres [color] (couleur du trait et du texte) et [label]
  /// (texte affiché, ex. « GPS » ou « IMU »). Renvoie une [Row] affichant un
  /// petit trait coloré suivi du libellé. Appelé par `build` pour composer la
  /// légende dans la barre supérieure.
  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, letterSpacing: 1)),
      ],
    );
  }

  /// Construit un marqueur circulaire à placer sur la carte.
  ///
  /// Prend en paramètres [point] (position [LatLng] du marqueur), [color]
  /// (couleur de fond du cercle) et [label] (lettre affichée au centre, ex.
  /// « D » pour départ, « A » pour arrivée). Renvoie un [Marker] rond à bordure
  /// blanche contenant le libellé. Appelé par `build` pour marquer le départ et
  /// l'arrivée GPS ainsi que la fin de la trace IMU.
  // Marker : décrit un point de la carte par sa position (point) et le widget
  // (child) à y afficher. Sa taille est fixée en pixels écran (width/height).
  Marker _marker(LatLng point, Color color, String label) {
    return Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  /// Construit le panneau de statistiques affiché en bas de l'écran.
  ///
  /// Ne prend pas de paramètre. Récupère les statistiques via `_stats` et
  /// renvoie un [Container] (bandeau sombre) contenant une cellule par
  /// statistique, réparties horizontalement. Appelé par `build` lorsque le
  /// panneau est activé et que des données sont disponibles.
  Widget _buildStatsPanel() {
    final stats = _stats;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1220),
        border: Border(top: BorderSide(color: Color(0xFF1A2540))),
      ),
      // Row : aligne ses enfants horizontalement. spaceAround répartit
      // l'espace libre autour de chaque cellule de statistique.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        // On transforme chaque entrée (clé -> valeur) de la map de stats en un
        // widget cellule. `.map(...).toList()` produit la liste d'enfants de la
        // Row. e.key = libellé, e.value = valeur formatée.
        children: stats.entries
            .map((e) => _statCell(e.key, e.value))
            .toList(),
      ),
    );
  }

  /// Construit une cellule de statistique (valeur au-dessus du libellé).
  ///
  /// Prend en paramètres [label] (libellé de la statistique, ex. « DIST. GPS »)
  /// et [value] (valeur formatée à afficher). Renvoie une [Column] affichant la
  /// valeur en gras puis le libellé ; la valeur est mise en évidence en orange
  /// lorsque le libellé est « ÉCART ». Appelé par `_buildStatsPanel` pour
  /// chaque statistique du panneau.
  Widget _statCell(String label, String value) {
    final isEcart = label == 'ÉCART';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: isEcart ? const Color(0xFFFF6B35) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
