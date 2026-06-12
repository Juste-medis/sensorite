import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_service.dart';

/// Écran de carte en temps réel comparant la trajectoire estimée (filtre de
/// Kalman, fusion GPS+IMU) au tracé GPS réel.
///
/// Ce widget s'abonne au [NavigationService] fourni et redessine la carte à
/// chaque mise à jour de l'état de navigation. Il affiche le tracé GPS, le
/// tracé estimé par l'IMU, des marqueurs de départ/fin et un bandeau de
/// statistiques (mode, nombre de points, temps sans GPS, dérive).
// StatefulWidget : widget dont l'apparence peut évoluer dans le temps. Il est
// immuable lui-même ; tout ce qui change est stocké dans un objet State séparé.
class LiveMapScreen extends StatefulWidget {
  /// Service de navigation qui fournit l'état courant (position, traces, mode)
  /// et notifie ce widget à chaque nouvelle mise à jour.
  final NavigationService navService;

  /// Construit l'écran de carte en temps réel.
  ///
  /// Prend en paramètre [navService], le service de navigation à observer.
  const LiveMapScreen({
    super.key,
    required this.navService,
  });

  /// Crée l'état mutable associé à ce widget.
  ///
  /// Appelé automatiquement par le framework Flutter lors de l'insertion du
  /// widget dans l'arbre. Renvoie une instance de [_LiveMapScreenState].
  @override
  // createState : Flutter appelle cette méthode pour créer l'objet State qui
  // contiendra les données mutables et la logique de rendu de ce widget.
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

/// État de [LiveMapScreen].
///
/// Gère le contrôleur de carte, les options d'affichage (suivi automatique de
/// la position, affichage des statistiques) et l'abonnement aux mises à jour du
/// [NavigationService]. Reconstruit l'interface à chaque notification reçue.
// State : conserve l'état entre les reconstructions. Appeler setState(...) ici
// signale à Flutter de rappeler build() pour redessiner l'interface.
class _LiveMapScreenState extends State<LiveMapScreen> {
  // MapController : permet de piloter la carte par code (déplacer le centre,
  // changer le zoom) en dehors des gestes de l'utilisateur.
  // `late final` : initialisé plus tard (dans initState) mais une seule fois.
  /// Contrôleur permettant de déplacer et d'ajuster la caméra de la carte.
  late final MapController _mapController;

  /// Indique si la caméra suit automatiquement la position estimée.
  bool _followEstimate = true;

  /// Indique si le bandeau de statistiques est affiché.
  bool _showStats = true;

  /// Mémorise si le premier centrage automatique de la carte a déjà eu lieu.
  bool _didInitialCenter = false;

  /// Horodatage du dernier recentrage en mode suivi, utilisé pour limiter la
  /// fréquence des déplacements de caméra (throttling).
  DateTime _lastFollowMove = DateTime.fromMillisecondsSinceEpoch(0);

  /// Initialise l'état du widget.
  ///
  /// Appelé une seule fois par le framework lors de la création de l'état.
  /// Instancie le [MapController] et abonne [_onNavUpdate] aux notifications du
  /// service de navigation.
  @override
  // initState : appelée une seule fois à la création de l'état, avant le premier
  // build. Idéale pour les initialisations et l'abonnement aux flux de données.
  void initState() {
    super.initState();
    _mapController = MapController();
    // addListener : on s'abonne au service. À chaque notification (nouvel état
    // de navigation), _onNavUpdate sera appelée pour redessiner la carte.
    widget.navService.addListener(_onNavUpdate);
  }

  /// Libère les ressources de l'état.
  ///
  /// Appelé par le framework lorsque le widget est retiré de l'arbre de façon
  /// permanente. Désabonne [_onNavUpdate] du service de navigation et libère le
  /// [MapController].
  @override
  // dispose : appelée quand le widget quitte l'arbre définitivement. On y libère
  // les ressources. Oublier de se désabonner ici provoquerait des fuites mémoire.
  void dispose() {
    widget.navService.removeListener(_onNavUpdate);
    _mapController.dispose();
    super.dispose();
  }

  /// Réagit à une mise à jour de l'état de navigation.
  ///
  /// Ne prend aucun paramètre. Appelé automatiquement par le
  /// [NavigationService] à chaque notification. Si le mode suivi est actif,
  /// recentre la carte sur la position estimée, puis déclenche une
  /// reconstruction de l'interface via [setState]. Ne fait rien si le widget
  /// n'est plus monté.
  void _onNavUpdate() {
    // mounted : vrai tant que le widget est dans l'arbre. On vérifie avant
    // setState car une notification peut arriver après la destruction du widget.
    if (!mounted) return;
    if (_followEstimate) _moveToEstimate();
    // setState avec un corps vide : on n'a rien à modifier ici, mais l'appel
    // suffit à demander à Flutter de reconstruire l'UI avec le nouvel état.
    setState(() {});
  }

  /// Recentre la caméra de la carte sur la position estimée courante.
  ///
  /// Prend en paramètre optionnel [force] : si `true`, ignore la limitation de
  /// fréquence (350 ms) et déplace immédiatement la caméra. Appelé par
  /// [_onNavUpdate] (mode suivi), par le bouton « Follow » et lors du premier
  /// centrage. Ne renvoie rien. Ignore les positions nulles (0,0) et les
  /// erreurs transitoires de la carte (indisponible à la première frame).
  void _moveToEstimate({bool force = false}) {
    final s = widget.navService.state;
    if (s.latitude == 0 && s.longitude == 0) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastFollowMove).inMilliseconds < 350) return;
    _lastFollowMove = now;
    try {
      // move : recentre la caméra sur une coordonnée (LatLng = latitude/longitude)
      // avec un niveau de zoom donné (17). LatLng vient de la librairie latlong2.
      _mapController.move(LatLng(s.latitude, s.longitude), 17);
    } catch (_) {
      // La carte peut être momentanément indisponible lors de la première frame.
    }
  }

  /// Ajuste la caméra pour afficher l'ensemble des points fournis.
  ///
  /// Prend en paramètre [points] : la liste des coordonnées à englober. Calcule
  /// les limites géographiques de ces points et adapte le zoom et le centre
  /// avec une marge de 44 px. Appelé par le bouton flottant « fit screen » et
  /// lors du premier centrage hors mode suivi. Ne renvoie rien. Ne fait rien si
  /// la liste est vide et ignore les erreurs transitoires de cycle de vie de la
  /// carte.
  void _fitAll(List<LatLng> points) {
    if (points.isEmpty) return;
    try {
      // fitCamera : ajuste automatiquement zoom et centre pour que tous les
      // points tiennent à l'écran, avec une marge (padding) autour.
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(44),
        ),
      );
    } catch (_) {
      // Ignore les erreurs transitoires de cycle de vie de la carte.
    }
  }

  /// Calcule la distance approximative en mètres entre deux coordonnées.
  ///
  /// Prend en paramètres [a] et [b], deux positions géographiques. Utilise une
  /// approximation plane équirectangulaire (rayon terrestre 6371 km) adaptée
  /// aux petites distances. Renvoie la distance en mètres sous forme de
  /// `double`. Appelée dans [build] pour déterminer la dérive GPS/IMU et pour
  /// éviter d'ajouter des points redondants au tracé.
  static double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final mLat = (a.latitude + b.latitude) / 2 * pi / 180;
    return sqrt(pow(dLat * r, 2) + pow(dLon * r * cos(mLat), 2));
  }

  /// Construit l'interface de l'écran de carte en temps réel.
  ///
  /// Prend en paramètre [context], le contexte de construction Flutter. Appelée
  /// par le framework à chaque reconstruction (notamment après chaque
  /// [setState] déclenché par [_onNavUpdate]).
  ///
  /// Récupère l'état courant du service, en extrait le tracé GPS, le tracé IMU
  /// (filtre de Kalman) et la position estimée. Au premier rendu disposant de
  /// données, déclenche le centrage initial de la carte. Renvoie un [Scaffold]
  /// contenant :
  /// - une [AppBar] avec les boutons « Follow » (suivi) et « Stats » ;
  /// - une [FlutterMap] affichant le fond OpenStreetMap, la polyligne GPS
  ///   (verte, continue), la polyligne IMU (orange, pointillés) et les
  ///   marqueurs de départ (A), de fin GPS (G) et de position estimée (I) ;
  /// - un bandeau de statistiques optionnel (mode, points GPS/IMU, temps sans
  ///   GPS, dérive) ;
  /// - un bouton flottant pour ajuster la vue sur l'ensemble des points.
  ///
  /// Affiche un message d'invite tant qu'aucune donnée n'est disponible.
  @override
  // build : Flutter appelle cette méthode pour (re)construire l'UI à chaque
  // setState. Elle doit renvoyer l'arbre de widgets décrivant l'écran.
  Widget build(BuildContext context) {
    final s = widget.navService.state;
    final gpsPoints = s.gpsTrail.map((p) => LatLng(p.lat, p.lon)).toList();
    final imuPoints = s.trail
        .where((p) => !p.fromGPS)
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    // Ternaire condition ? a : b : si une position estimée existe (non 0,0) on
    // crée un LatLng, sinon `null` (pas de position connue pour l'instant).
    final estimate = (s.latitude != 0 || s.longitude != 0)
        ? LatLng(s.latitude, s.longitude)
        : null;
    final imuLinePoints = [
      // ... (spread) : insère ici tous les éléments de imuPoints dans la liste.
      ...imuPoints,
      // if-élément dans une liste (collection-if) : ajoute `estimate` seulement
      // si la condition est vraie. != null garantit qu'on n'ajoute pas null.
      if (estimate != null &&
          (imuPoints.isEmpty || _distMeters(imuPoints.last, estimate) > 0.5))
        estimate,
    ];
    final allPoints = [...gpsPoints, ...imuLinePoints];
    final hasData = allPoints.isNotEmpty;

    if (!_didInitialCenter && hasData) {
      _didInitialCenter = true;
      // addPostFrameCallback : exécute le code juste APRÈS la fin du build/rendu.
      // Nécessaire ici car la carte n'est pleinement utilisable qu'une fois
      // affichée : on ne peut pas la déplacer pendant build().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_followEstimate) {
          _moveToEstimate(force: true);
        } else {
          _fitAll(allPoints);
        }
      });
    }

    String driftText = '-';
    if (gpsPoints.isNotEmpty && estimate != null) {
      driftText =
          '${_distMeters(gpsPoints.last, estimate).toStringAsFixed(1)} m';
    }

    // Scaffold : squelette d'une page (barre du haut, corps, bouton flottant).
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1220),
        foregroundColor: Colors.white,
        title: const Text(
          'LIVE MAP GPS VS IMU',
          style: TextStyle(
              fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Follow',
            onPressed: () {
              setState(() => _followEstimate = !_followEstimate);
              if (_followEstimate) _moveToEstimate(force: true);
            },
            icon: Icon(
              _followEstimate ? Icons.my_location : Icons.location_searching,
              color: _followEstimate ? const Color(0xFF00E5FF) : Colors.white54,
            ),
          ),
          IconButton(
            tooltip: 'Stats',
            onPressed: () => setState(() => _showStats = !_showStats),
            icon: Icon(
              _showStats ? Icons.info : Icons.info_outline,
              color: _showStats ? const Color(0xFF00E5FF) : Colors.white54,
            ),
          ),
        ],
      ),
      // Column : empile ses enfants verticalement (carte en haut, stats en bas).
      body: Column(
        children: [
          // Expanded : l'enfant occupe tout l'espace vertical restant.
          Expanded(
            // Ternaire : si pas de données on affiche un message, sinon la carte.
            child: !hasData
                ? const Center(
                    child: Text(
                      'No GPS/IMU points yet.\nStart a run to see live comparison.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                // FlutterMap : le widget de carte. On lui passe le contrôleur,
                // des options, et une liste de couches (children) superposées.
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      // ?? (si-null) : utilise `estimate` s'il existe, sinon la
                      // valeur de droite (dernier point GPS, ou Paris par défaut).
                      initialCenter: estimate ??
                          (gpsPoints.isNotEmpty
                              ? gpsPoints.last
                              : const LatLng(48.8566, 2.3522)),
                      initialZoom: 16,
                      onMapEvent: (event) {
                        if (event is MapEventMove &&
                            event.source == MapEventSource.dragStart) {
                          if (_followEstimate) {
                            setState(() => _followEstimate = false);
                          }
                        }
                      },
                    ),
                    // children : les couches de la carte, empilées du fond vers
                    // le dessus (fond de carte, puis tracés, puis marqueurs).
                    children: [
                      // TileLayer : fond de carte composé de tuiles images
                      // téléchargées depuis OpenStreetMap (gratuit, libre).
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sensoritetest',
                      ),
                      // PolylineLayer : trace une ligne reliant une suite de
                      // points. Ici le tracé GPS réel (vert, continu).
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
                      // Second tracé : estimation IMU/Kalman (orange, pointillés).
                      if (imuLinePoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: imuLinePoints,
                              color: const Color(0xFFFF6B35),
                              strokeWidth: 3,
                              pattern: StrokePattern.dashed(
                                segments: const [12, 6],
                              ),
                            ),
                          ],
                        ),
                      // MarkerLayer : place des widgets (épingles) à des
                      // coordonnées précises sur la carte.
                      MarkerLayer(
                        markers: [
                          if (gpsPoints.isNotEmpty)
                            _marker(gpsPoints.first, Colors.white70, 'A'),
                          if (gpsPoints.isNotEmpty)
                            _marker(
                                gpsPoints.last, const Color(0xFF00E676), 'G'),
                          if (estimate != null)
                            _marker(estimate, const Color(0xFFFF6B35), 'I'),
                        ],
                      ),
                    ],
                  ),
          ),
          // collection-if : la bannière de stats n'est ajoutée à la Column que
          // si l'option est activée et que des données existent.
          if (_showStats && hasData)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0D1220),
                border: Border(top: BorderSide(color: Color(0xFF1A2540))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCell('MODE', s.mode.name.toUpperCase()),
                  _statCell('GPS', '${gpsPoints.length} pts'),
                  _statCell('IMU', '${imuLinePoints.length} pts'),
                  _statCell('NO GPS', '${s.timeSinceGPS.toStringAsFixed(1)} s'),
                  _statCell('DRIFT', driftText, highlight: true),
                ],
              ),
            ),
        ],
      ),
      // floatingActionButton : bouton rond flottant au-dessus du contenu.
      // Ternaire : on ne l'affiche (sinon null = aucun bouton) que s'il y a des
      // données ; il sert à recadrer la vue sur l'ensemble du parcours.
      floatingActionButton: hasData
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF141B2D),
              foregroundColor: const Color(0xFF00E5FF),
              onPressed: () => _fitAll(allPoints),
              child: const Icon(Icons.fit_screen),
            )
          : null,
    );
  }

  /// Construit un marqueur circulaire à placer sur la carte.
  ///
  /// Prend en paramètres [point] (position du marqueur), [color] (couleur de
  /// remplissage) et [label] (lettre affichée au centre). Appelée depuis
  /// [build] pour créer les marqueurs de départ (A), de fin GPS (G) et de
  /// position estimée IMU (I). Renvoie un [Marker] : un disque coloré bordé de
  /// blanc affichant la lettre [label] en son centre.
  Marker _marker(LatLng point, Color color, String label) {
    // Marker : associe un widget (ici un disque coloré avec une lettre) à une
    // position géographique ; width/height fixent sa taille à l'écran.
    return Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.4),
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

  /// Construit une cellule de statistique du bandeau inférieur.
  ///
  /// Prend en paramètres [label] (intitulé en petit, ex. « DRIFT »), [value]
  /// (valeur affichée en gras au-dessus) et le paramètre optionnel [highlight] :
  /// si `true`, la valeur est colorée en orange pour la mettre en évidence.
  /// Appelée depuis [build] pour chaque statistique du bandeau. Renvoie une
  /// [Column] empilant la valeur puis l'intitulé.
  Widget _statCell(String label, String value, {bool highlight = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFFFF6B35) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        // SizedBox : boîte vide servant ici simplement d'espace (2 px) entre
        // la valeur et son intitulé.
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
