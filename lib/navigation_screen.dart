import 'dart:math';
import 'package:flutter/material.dart' hide NavigationMode;
import 'navigation_service.dart';
import 'live_map_screen.dart';
import 'trace_screen.dart';
import 'csv_traces_screen.dart';

/// Écran principal de l'application de navigation GPS+IMU.
///
/// Widget racine de l'interface : il affiche en temps réel l'état de la
/// navigation (position estimée, vitesse, temps écoulé sans GPS, niveau de
/// confiance, mode courant) ainsi que les boutons de contrôle (démarrer/arrêter,
/// mode VS, simulation de perte/restauration GPS, auto-collecte, accès à la
/// carte temps réel, aux tracés et à l'export CSV).
///
/// Étant un [StatefulWidget], il délègue la gestion de son état mutable à
/// [_NavigationScreenState], qui écoute le [NavigationService] pour se
/// reconstruire à chaque changement d'état.
class NavigationScreen extends StatefulWidget {
  /// Crée l'écran de navigation.
  ///
  /// Prend en paramètre la [key] optionnelle héritée de [StatefulWidget].
  /// Appelé par le framework Flutter lors de l'insertion de ce widget dans
  /// l'arbre (typiquement comme écran d'accueil de l'application).
  const NavigationScreen({super.key});

  /// Crée l'objet d'état associé à ce widget.
  ///
  /// Ne prend aucun paramètre et renvoie une nouvelle instance de
  /// [_NavigationScreenState]. Appelé automatiquement par le framework Flutter
  /// lors de la création du widget dans l'arbre.
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

/// État mutable de [NavigationScreen].
///
/// Gère le cycle de vie de l'écran, conserve l'instance du [NavigationService]
/// (source de vérité de toute la navigation), l'animation de pulsation des
/// bannières, et les drapeaux d'interface ([_isRunning], [_showDebug]).
/// Utilise [TickerProviderStateMixin] pour fournir le `vsync` nécessaire à
/// l'[AnimationController]. Se reconstruit à chaque notification du service.
class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  /// Service central de navigation : fournit l'état (position, vitesse, mode,
  /// confiance…) et expose les actions (start/stop, mode VS, simulation GPS,
  /// auto-collecte, export). Source de vérité écoutée par cet écran.
  final NavigationService _navService = NavigationService();

  /// Contrôleur d'animation pilotant l'effet de pulsation (clignotement
  /// d'opacité) des bannières d'état en mode dead reckoning et VS.
  late AnimationController _pulseController;

  /// Indique si la navigation est en cours d'exécution (bouton START/STOP).
  /// Conditionne l'affichage des boutons de contrôle.
  bool _isRunning = false;

  /// Indique si le panneau de debug (Kalman + NHC) est visible.
  /// Basculé via l'icône `developer_mode` de l'en-tête.
  bool _showDebug = false;

  /// Initialise l'état au montage du widget.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Crée et démarre en boucle
  /// l'[_pulseController] (cycle de 2 s) et abonne [_onStateChanged] aux
  /// notifications du [_navService]. Appelé une seule fois par le framework
  /// Flutter lors de l'insertion de l'état dans l'arbre.
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _navService.addListener(_onStateChanged);
  }

  /// Callback déclenché à chaque notification du [_navService].
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Si le widget est toujours
  /// monté ([mounted]), appelle [setState] pour reconstruire l'écran avec le
  /// nouvel état de navigation. Appelé par le [NavigationService] via le
  /// listener enregistré dans [initState].
  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  /// Libère les ressources au démontage du widget.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Désabonne [_onStateChanged],
  /// libère le [_navService] et l'[_pulseController], puis appelle le `dispose`
  /// parent. Appelé une seule fois par le framework Flutter lorsque l'état est
  /// retiré définitivement de l'arbre.
  @override
  void dispose() {
    _navService.removeListener(_onStateChanged);
    _navService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Démarre ou arrête la navigation selon l'état courant.
  ///
  /// Ne prend aucun paramètre et renvoie un [Future] qui se termine une fois
  /// l'opération effectuée. Si la navigation tourne ([_isRunning] vrai), appelle
  /// `stop()` sur le [_navService] ; sinon appelle `start()` (asynchrone). Inverse
  /// ensuite [_isRunning] via [setState]. Appelé lors d'un appui sur le bouton
  /// DÉMARRER/ARRÊTER.
  Future<void> _toggleNavigation() async {
    if (_isRunning) {
      _navService.stop();
    } else {
      await _navService.start();
    }
    setState(() => _isRunning = !_isRunning);
  }

  /// Exporte les données de navigation enregistrées vers un fichier CSV.
  ///
  /// Ne prend aucun paramètre et renvoie un [Future] qui se termine après
  /// affichage du dialogue. Demande au [_navService] d'écrire le fichier puis,
  /// si le widget est toujours monté, affiche une boîte de dialogue indiquant le
  /// succès (avec le chemin du fichier) ou l'échec de l'export. Appelé lors d'un
  /// appui sur le bouton EXPORTER CSV (uniquement quand la navigation est
  /// arrêtée).
  Future<void> _exportData() async {
    final path = await _navService.exportData();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141B2D),
        title: Text(
          path != null ? 'EXPORT RÉUSSI' : 'ERREUR EXPORT',
          style: TextStyle(
            color: path != null
                ? const Color(0xFF00E676)
                : const Color(0xFFFF4757),
            fontSize: 13,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          path != null
              ? 'Fichier sauvegardé :\n\n$path'
              : 'Impossible d\'écrire le fichier.\nAucune donnée enregistrée.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );
  }

  /// Ouvre l'écran de visualisation du tracé courant.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Récupère l'état courant du
  /// [_navService] et pousse une [TraceScreen] affichant le tracé estimé
  /// ([state.trail]) et le tracé GPS ([state.gpsTrail]). Appelé lors d'un appui
  /// sur le bouton VOIR TRACÉ.
  void _openTrace() {
    final state = _navService.state;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TraceScreen(
          trail: state.trail,
          gpsTrail: state.gpsTrail,
        ),
      ),
    );
  }

  /// Ouvre l'écran de visualisation du dernier tracé VS archivé.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Récupère le dernier tracé VS
  /// archivé du [_navService] ; s'il n'y en a aucun, ne fait rien. Sinon, pousse
  /// une [TraceScreen] affichant son tracé estimé et son tracé GPS. Appelé lors
  /// d'un appui sur le bouton DERNIER TRACE VS ARCHIVE.
  void _openLastArchivedVSTrace() {
    final archived = _navService.lastArchivedVSTrace;
    if (archived == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TraceScreen(
          trail: archived.trail,
          gpsTrail: archived.gpsTrail,
        ),
      ),
    );
  }

  /// Ouvre l'écran de carte temps réel.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Pousse une [LiveMapScreen] en
  /// lui transmettant le [_navService] afin qu'elle suive la position en direct.
  /// Appelé lors d'un appui sur le bouton LIVE MAP, ainsi qu'au lancement du mode
  /// VS et de l'auto-collecte.
  void _openLiveMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMapScreen(navService: _navService),
      ),
    );
  }

  /// Ouvre l'écran listant tous les tracés CSV enregistrés.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Pousse une [CsvTracesScreen]
  /// en lui transmettant le [_navService]. Appelé lors d'un appui sur le bouton
  /// VOIR TOUS LES TRACES CSV.
  void _openCsvTraces() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CsvTracesScreen(navService: _navService),
      ),
    );
  }

  /// Construit l'arbre de widgets de l'écran complet.
  ///
  /// Prend en paramètre le [context] de construction et renvoie le [Widget]
  /// racine. Affiche un [Scaffold] composé de l'en-tête fixe ([_buildHeader])
  /// suivi d'une zone défilante empilant verticalement : la bannière d'état, la
  /// carte de position, la ligne de métriques, la barre de confiance, la carte
  /// de calibration (uniquement en mode calibrating), les boutons de contrôle et
  /// le panneau de debug (si [_showDebug]). Appelé par le framework Flutter à
  /// chaque reconstruction (notamment après [_onStateChanged]).
  @override
  Widget build(BuildContext context) {
    final state = _navService.state;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(state),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _buildStatusBanner(state),
                    const SizedBox(height: 16),
                    _buildPositionCard(state),
                    const SizedBox(height: 12),
                    _buildMetricsRow(state),
                    const SizedBox(height: 12),
                    _buildConfidenceBar(state),
                    const SizedBox(height: 16),
                    if (state.mode == NavigationMode.calibrating)
                      _buildCalibrationCard(state),
                    _buildControlButtons(state),
                    const SizedBox(height: 12),
                    if (_showDebug) _buildDebugPanel(state),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construit l'en-tête de l'écran.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche une barre en dégradé contenant une pastille lumineuse dont la
  /// couleur reflète le mode courant ([_modeColor]), le titre « IMU NAVIGATOR »
  /// et une icône `developer_mode` qui bascule l'affichage du panneau de debug
  /// ([_showDebug]). Appelé par [build].
  Widget _buildHeader(NavigationState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0E1A), Color(0xFF141B2D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _modeColor(state.mode),
              boxShadow: [
                BoxShadow(
                  color: _modeColor(state.mode).withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'IMU NAVIGATOR',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _showDebug = !_showDebug),
            child: Icon(
              Icons.developer_mode,
              color: _showDebug ? const Color(0xFF00E5FF) : Colors.white38,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  /// Construit la bannière d'état de la navigation.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Choisit un texte, une couleur et une icône selon le mode courant
  /// ([state.mode] : idle, calibrating, gps, deadReckoning, gpsDenied, vsMode),
  /// puis affiche un encadré coloré avec ce message. En modes deadReckoning et
  /// vsMode, la bannière clignote en opacité grâce à l'[_pulseController].
  /// Appelé par [build].
  Widget _buildStatusBanner(NavigationState state) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (state.mode) {
      case NavigationMode.idle:
        statusText = 'SYSTÈME EN ATTENTE';
        statusColor = Colors.white38;
        statusIcon = Icons.pause_circle_outline;
      case NavigationMode.calibrating:
        statusText = 'CALIBRATION EN COURS...';
        statusColor = const Color(0xFFFFD93D);
        statusIcon = Icons.tune;
      case NavigationMode.gps:
        statusText = 'GPS ACTIF — FUSION IMU+GPS';
        statusColor = const Color(0xFF00E676);
        statusIcon = Icons.satellite_alt;
      case NavigationMode.deadReckoning:
        statusText = 'GPS PERDU — NAVIGATION INERTIELLE';
        statusColor = const Color(0xFFFF6B35);
        statusIcon = Icons.explore;
      case NavigationMode.gpsDenied:
        statusText = 'GPS INDISPONIBLE';
        statusColor = const Color(0xFFFF4757);
        statusIcon = Icons.gps_off;
      case NavigationMode.vsMode:
        statusText = 'MODE VS — IMU LIBRE / GPS RÉFÉRENCE';
        statusColor = const Color(0xFFB388FF);
        statusIcon = Icons.compare_arrows;
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        double opacity = (state.mode == NavigationMode.deadReckoning ||
                state.mode == NavigationMode.vsMode)
            ? 0.7 + 0.3 * sin(_pulseController.value * 2 * pi)
            : 1.0;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(statusIcon, color: statusColor, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construit la carte affichant la position estimée.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche, dans un encadré titré « POSITION ESTIMÉE », la latitude et la
  /// longitude courantes (6 décimales) via deux colonnes [_coordColumn]. En mode
  /// deadReckoning, ajoute un badge indiquant l'incertitude de position
  /// (± mètres). Appelé par [build].
  Widget _buildPositionCard(NavigationState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          const Text(
            'POSITION ESTIMÉE',
            style: TextStyle(
                fontSize: 11, color: Colors.white38, letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _coordColumn('LAT', state.latitude.toStringAsFixed(6)),
              Container(width: 1, height: 40, color: const Color(0xFF1E293B)),
              _coordColumn('LON', state.longitude.toStringAsFixed(6)),
            ],
          ),
          if (state.mode == NavigationMode.deadReckoning) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '± ${state.uncertainty.toStringAsFixed(1)} m',
                style: const TextStyle(
                  color: Color(0xFFFF6B35),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Construit une colonne affichant une coordonnée.
  ///
  /// Prend en paramètres un libellé [label] (par ex. « LAT » ou « LON ») et sa
  /// valeur formatée [value], et renvoie un [Widget]. Affiche le libellé en
  /// petit au-dessus de la valeur en grand. Appelé par [_buildPositionCard].
  Widget _coordColumn(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Colors.white38, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 1)),
      ],
    );
  }

  /// Construit la ligne de métriques de navigation.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche trois tuiles [_metricTile] côte à côte : la vitesse (convertie en
  /// km/h), le temps écoulé depuis la dernière mise à jour GPS (en secondes) et
  /// l'état de mouvement (ARRÊT ou MOUV.). Appelé par [build].
  Widget _buildMetricsRow(NavigationState state) {
    return Row(
      children: [
        Expanded(
          child: _metricTile('VITESSE', (state.speed * 3.6).toStringAsFixed(1),
              'km/h', Icons.speed),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile('SANS GPS', state.timeSinceGPS.toStringAsFixed(1),
              'sec', Icons.timer),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile('ÉTAT', state.isStationary ? 'ARRÊT' : 'MOUV.', '',
              state.isStationary ? Icons.pause : Icons.directions_car),
        ),
      ],
    );
  }

  /// Construit une tuile de métrique unique.
  ///
  /// Prend en paramètres un libellé [label], une valeur [value], une unité
  /// [unit] (peut être vide) et une icône [icon], et renvoie un [Widget].
  /// Affiche, dans un encadré, l'icône en haut, la valeur en gras, l'unité (si
  /// présente) puis le libellé en bas. Appelé par [_buildMetricsRow].
  Widget _metricTile(String label, String value, String unit, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          if (unit.isNotEmpty)
            Text(unit,
                style: const TextStyle(fontSize: 10, color: Colors.white38)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 9, color: Colors.white38, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  /// Construit la barre de confiance de la position.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche un encadré titré « CONFIANCE POSITION » avec le pourcentage de
  /// confiance et une barre de progression colorée : verte si la confiance est
  /// élevée (> 0,6), jaune si moyenne (> 0,3), rouge sinon. Appelé par [build].
  Widget _buildConfidenceBar(NavigationState state) {
    Color barColor = state.confidence > 0.6
        ? const Color(0xFF00E676)
        : state.confidence > 0.3
            ? const Color(0xFFFFD93D)
            : const Color(0xFFFF4757);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('CONFIANCE POSITION',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white38, letterSpacing: 1.5)),
              Text('${(state.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: barColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.confidence,
              minHeight: 6,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Construit la carte de calibration de l'IMU.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche une carte invitant l'utilisateur à garder le véhicule immobile, avec
  /// une barre de progression et le pourcentage d'avancement de la calibration
  /// ([state.calibrationProgress]). Appelé par [build] uniquement lorsque le mode
  /// courant est `calibrating`.
  Widget _buildCalibrationCard(NavigationState state) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD93D).withValues(alpha: 0.05),
            const Color(0xFFFFD93D).withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFFD93D).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.directions_car, color: Color(0xFFFFD93D), size: 32),
          const SizedBox(height: 12),
          const Text('CALIBRATION IMU',
              style: TextStyle(
                  color: Color(0xFFFFD93D),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2)),
          const SizedBox(height: 8),
          const Text(
            'Gardez le véhicule immobile\npendant la calibration',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.calibrationProgress,
              minHeight: 8,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD93D)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(state.calibrationProgress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
                color: Color(0xFFFFD93D),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Construit l'ensemble des boutons de contrôle de l'écran.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche, empilés verticalement et de manière conditionnelle :
  /// le bouton DÉMARRER/ARRÊTER ; quand la navigation tourne et est calibrée,
  /// les boutons du mode VS (lancer/arrêter/nouveau) et le bouton d'auto-collecte
  /// (ou son statut via [_buildAutoCollectStatus]) ; quand la navigation tourne
  /// hors mode VS et hors auto-collecte, les boutons de simulation et de
  /// restauration GPS ; le bouton LIVE MAP (si en cours ou si des données
  /// existent) ; le bouton d'accès aux tracés CSV ; les boutons VOIR TRACÉ et
  /// EXPORTER CSV (si des données existent) ; et le bouton du dernier tracé VS
  /// archivé (si au moins un archive existe). Appelé par [build].
  Widget _buildControlButtons(NavigationState state) {
    final bool hasData = state.trail.isNotEmpty || state.gpsTrail.isNotEmpty;
    final int archivedCount = _navService.archivedVSTraceCount;

    return Column(
      children: [
        // Démarrer / Arrêter
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _toggleNavigation,
            icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
            label: Text(
              _isRunning ? 'ARRÊTER' : 'DÉMARRER',
              style: const TextStyle(
                  letterSpacing: 2, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRunning
                  ? const Color(0xFFFF4757)
                  : const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF0A0E1A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Boutons mode VS + auto-collecte (affichés quand en cours et calibré)
        if (_isRunning && state.isCalibrated) ...[
          const SizedBox(height: 10),
          // Bouton VS manuel — masqué pendant l'auto-collecte
          if (!_navService.isAutoCollecting)
            SizedBox(
              width: double.infinity,
              height: _navService.isVSMode ? 52 : 48,
              child: _navService.isVSMode
                  ? Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _navService.stopVSMode(),
                            icon: const Icon(Icons.stop),
                            label: const Text(
                              'ARRETER VS',
                              style: TextStyle(
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB388FF),
                              foregroundColor: const Color(0xFF0A0E1A),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: state.gpsAvailable
                                ? () {
                                    _navService.restartVSMode();
                                    _openLiveMap();
                                  }
                                : null,
                            icon: const Icon(Icons.replay, size: 18),
                            label: const Text(
                              'NOUVEAU VS',
                              style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.0,
                                  fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB388FF),
                              disabledForegroundColor: Colors.white24,
                              side: BorderSide(
                                color: state.gpsAvailable
                                    ? const Color(0xFFB388FF)
                                    : Colors.white12,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : OutlinedButton.icon(
                      onPressed: state.gpsAvailable
                          ? () {
                              _navService.startVSMode();
                              _openLiveMap();
                            }
                          : null,
                      icon: const Icon(Icons.compare_arrows, size: 18),
                      label: const Text(
                        'LANCER MODE VS + LIVE MAP',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB388FF),
                        disabledForegroundColor: Colors.white24,
                        side: BorderSide(
                          color: state.gpsAvailable
                              ? const Color(0xFFB388FF)
                              : Colors.white12,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ),
          const SizedBox(height: 8),
          // Bouton d'auto-collecte
          if (_navService.isAutoCollecting)
            _buildAutoCollectStatus()
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: state.gpsAvailable
                    ? () {
                        _navService.startAutoCollection();
                        _openLiveMap();
                      }
                    : null,
                icon: const Icon(Icons.loop, size: 18),
                label: const Text(
                  'AUTO-COLLECTE',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00E5FF),
                  disabledForegroundColor: Colors.white24,
                  side: BorderSide(
                    color: state.gpsAvailable
                        ? const Color(0xFF00E5FF)
                        : Colors.white12,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
        // Boutons de simulation GPS (seulement en cours, hors mode VS, hors auto-collecte)
        if (_isRunning &&
            !_navService.isVSMode &&
            !_navService.isAutoCollecting)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navService.simulateGPSLoss(),
                    icon: const Icon(Icons.gps_off, size: 18),
                    label: const Text('SIMULER PERTE GPS',
                        style: TextStyle(fontSize: 11, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B35),
                      side: const BorderSide(color: Color(0xFFFF6B35)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navService.restoreGPS(),
                    icon: const Icon(Icons.satellite_alt, size: 18),
                    label: const Text('RESTAURER GPS',
                        style: TextStyle(fontSize: 11, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E676),
                      side: const BorderSide(color: Color(0xFF00E676)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Bouton carte temps réel (disponible en cours ou si des données existent)
        if (_isRunning || hasData) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openLiveMap,
              icon: const Icon(Icons.map, size: 18),
              label: const Text('LIVE MAP TEMPS REEL',
                  style: TextStyle(fontSize: 11, letterSpacing: 1)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00E676),
                side: const BorderSide(color: Color(0xFF00E676)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openCsvTraces,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('VOIR TOUS LES TRACES CSV',
                style: TextStyle(fontSize: 11, letterSpacing: 1)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB388FF),
              side: const BorderSide(color: Color(0xFFB388FF)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        // Boutons Tracé + Export (toujours affichés quand des données existent)
        if (hasData) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openTrace,
                  icon: const Icon(Icons.route, size: 18),
                  label: const Text('VOIR TRACÉ',
                      style: TextStyle(fontSize: 11, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: !_isRunning ? _exportData : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('EXPORTER CSV',
                      style: TextStyle(fontSize: 11, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD93D),
                    disabledForegroundColor: Colors.white24,
                    side: BorderSide(
                        color: !_isRunning
                            ? const Color(0xFFFFD93D)
                            : Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (archivedCount > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openLastArchivedVSTrace,
              icon: const Icon(Icons.history, size: 18),
              label: Text(
                'DERNIER TRACE VS ARCHIVE ($archivedCount)',
                style: const TextStyle(fontSize: 11, letterSpacing: 1),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB388FF),
                side: const BorderSide(color: Color(0xFFB388FF)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Construit le bandeau de statut de l'auto-collecte.
  ///
  /// Ne prend aucun paramètre et renvoie un [Widget]. Lit l'état d'auto-collecte
  /// du [_navService] (en cours d'enregistrement ou en attente GPS, numéro de
  /// session, compte à rebours, distance parcourue et distance cible) et affiche
  /// un encadré coloré indiquant la session, le libellé d'état, la progression en
  /// mètres, le minuteur (mm:ss) et un bouton d'arrêt de l'auto-collecte. Appelé
  /// par [_buildControlButtons] lorsque l'auto-collecte est active.
  Widget _buildAutoCollectStatus() {
    final isRec = _navService.autoIsRecording;
    final session = _navService.autoSession;
    final countdown = _navService.autoCountdown;
    final distance = _navService.autoDistanceMeters;
    final distanceTarget = _navService.autoDistanceTargetMeters;
    final mins = countdown ~/ 60;
    final secs = (countdown % 60).toString().padLeft(2, '0');
    final color = isRec ? const Color(0xFFFF6B35) : const Color(0xFF00E5FF);
    final label = isRec ? 'CAPTURE GPS REELLE' : 'ATTENTE GPS';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(isRec ? Icons.fiber_manual_record : Icons.hourglass_top,
              color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AUTO #${session.toString().padLeft(2, '0')} - $label\n'
              '${distance.toStringAsFixed(0)} / ${distanceTarget.toStringAsFixed(0)} m',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Text(
            '$mins:$secs',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _navService.stopAutoCollection(),
            child: Icon(Icons.stop_circle_outlined, color: color, size: 22),
          ),
        ],
      ),
    );
  }
  /// Construit le panneau de debug technique.
  ///
  /// Prend en paramètre l'état de navigation [state] et renvoie un [Widget].
  /// Affiche, dans un encadré titré « DEBUG — FILTRE DE KALMAN + NHC », une série
  /// de lignes [_debugRow] détaillant le mode, les compteurs de mises à jour IMU
  /// et GPS, le nombre d'enregistrements, l'incertitude, la confiance, l'état
  /// stationnaire, le temps sans GPS, le nombre de points des tracés et le nombre
  /// d'archives VS. Appelé par [build] uniquement lorsque [_showDebug] est vrai.
  Widget _buildDebugPanel(NavigationState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1220),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DEBUG — FILTRE DE KALMAN + NHC',
            style: TextStyle(
                fontSize: 11,
                color: Color(0xFF00E5FF),
                letterSpacing: 2,
                fontWeight: FontWeight.w600),
          ),
          const Divider(color: Color(0xFF1E293B)),
          _debugRow('Mode', state.mode.name),
          _debugRow('Updates IMU', '${_navService.imuUpdateCount}'),
          _debugRow('Updates GPS', '${_navService.gpsUpdateCount}'),
          _debugRow('Enregistrements', '${_navService.recordCount}'),
          _debugRow('Incertitude', '${state.uncertainty.toStringAsFixed(2)} m'),
          _debugRow(
              'Confiance', '${(state.confidence * 100).toStringAsFixed(1)}%'),
          _debugRow('Stationnaire', state.isStationary ? 'OUI' : 'NON'),
          _debugRow(
              'Temps sans GPS', '${state.timeSinceGPS.toStringAsFixed(1)} s'),
          _debugRow('Points tracé', '${state.trail.length}'),
          _debugRow('Points GPS', '${state.gpsTrail.length}'),
          _debugRow('VS archives', '${_navService.archivedVSTraceCount}'),
        ],
      ),
    );
  }

  /// Construit une ligne du panneau de debug.
  ///
  /// Prend en paramètres un libellé [label] et sa valeur [value], et renvoie un
  /// [Widget]. Affiche le libellé à gauche et la valeur à droite sur une même
  /// ligne. Appelé par [_buildDebugPanel].
  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          Text(value,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  /// Renvoie la couleur associée à un mode de navigation.
  ///
  /// Prend en paramètre le mode [mode] et renvoie la [Color] correspondante :
  /// gris (idle), jaune (calibrating), vert (gps), orange (deadReckoning),
  /// rouge (gpsDenied), violet (vsMode). Appelé par [_buildHeader] pour colorer
  /// la pastille d'état de l'en-tête.
  Color _modeColor(NavigationMode mode) {
    switch (mode) {
      case NavigationMode.idle:
        return Colors.white38;
      case NavigationMode.calibrating:
        return const Color(0xFFFFD93D);
      case NavigationMode.gps:
        return const Color(0xFF00E676);
      case NavigationMode.deadReckoning:
        return const Color(0xFFFF6B35);
      case NavigationMode.gpsDenied:
        return const Color(0xFFFF4757);
      case NavigationMode.vsMode:
        return const Color(0xFFB388FF);
    }
  }

}


