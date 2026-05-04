import 'dart:math';
import 'package:flutter/material.dart' hide NavigationMode;
import 'navigation_service.dart';
import 'live_map_screen.dart';
import 'trace_screen.dart';
import 'csv_traces_screen.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  final NavigationService _navService = NavigationService();
  late AnimationController _pulseController;
  bool _isRunning = false;
  bool _showDebug = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _navService.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _navService.removeListener(_onStateChanged);
    _navService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleNavigation() async {
    if (_isRunning) {
      _navService.stop();
    } else {
      await _navService.start();
    }
    setState(() => _isRunning = !_isRunning);
  }

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

  void _openLiveMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMapScreen(navService: _navService),
      ),
    );
  }

  void _openCsvTraces() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CsvTracesScreen(navService: _navService),
      ),
    );
  }

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

  Widget _buildControlButtons(NavigationState state) {
    final bool hasData = state.trail.isNotEmpty || state.gpsTrail.isNotEmpty;
    final int archivedCount = _navService.archivedVSTraceCount;

    return Column(
      children: [
        // Start / Stop
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
        // VS mode + auto-collect buttons (shown when running and calibrated)
        if (_isRunning && state.isCalibrated) ...[
          const SizedBox(height: 10),
          // Manual VS button — hidden during auto-collect
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
          // Auto-collect button
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
        // GPS simulation buttons (only while running, not in VS mode, not auto-collecting)
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
        // Live map button (available while running or when data exists)
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
        // Trace + Export buttons (always shown when data is available)
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


