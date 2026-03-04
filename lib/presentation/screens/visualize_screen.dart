import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/text_styles.dart';
import '../widgets/common/notion_card.dart';
import '../widgets/common/notion_button.dart';
import '../widgets/common/notion_header.dart';
import '../widgets/charts/accelerometer_chart.dart';
import '../widgets/charts/gyroscope_chart.dart';
import '../widgets/charts/trajectory_chart.dart';
import '../viewmodels/visualize_viewmodel.dart';

class VisualizeScreen extends StatefulWidget {
  const VisualizeScreen({Key? key}) : super(key: key);

  @override
  State<VisualizeScreen> createState() => _VisualizeScreenState();
}

class _VisualizeScreenState extends State<VisualizeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeViewModel();
  }

  Future<void> _initializeViewModel() async {
    final viewModel = Provider.of<VisualizeViewModel>(context, listen: false);
    await viewModel.initialize();
    await viewModel.loadRecordings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualisation'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Temps réel'),
            Tab(text: 'Historique'),
            Tab(text: 'Trajectoire'),
          ],
          indicatorColor: AppColors.accentBlue,
          labelColor: AppColors.accentBlue,
          unselectedLabelColor: AppColors.textSecondary,
        ),
      ),
      body: Consumer<VisualizeViewModel>(
        builder: (context, viewModel, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildRealtimeTab(viewModel),
              _buildHistoryTab(viewModel),
              _buildTrajectoryTab(viewModel),
            ],
          );
        },
      ),
    );
  }

  // 📡 Onglet Temps réel
  Widget _buildRealtimeTab(VisualizeViewModel viewModel) {
    return Column(
      children: [
        // Contrôles
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: NotionButton(
                  label: viewModel.isLive ? 'Arrêter' : 'Démarrer',
                  icon: viewModel.isLive ? Icons.stop : Icons.play_arrow,
                  type: viewModel.isLive
                      ? NotionButtonType.destructive
                      : NotionButtonType.primary,
                  onPressed: viewModel.toggleLive,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NotionButton(
                  label: 'Réinitialiser',
                  icon: Icons.refresh,
                  type: NotionButtonType.secondary,
                  onPressed: viewModel.resetCharts,
                ),
              ),
            ],
          ),
        ),

        // Graphiques
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Accéléromètre
              NotionHeader(
                title: 'Accéléromètre (m/s²)',
                subtitle: 'Données en temps réel',
                showDivider: false,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: AccelerometerChart(
                  data: viewModel.liveAccelerometerData,
                  isLive: viewModel.isLive,
                ),
              ),

              const SizedBox(height: 24),

              // Gyroscope
              NotionHeader(
                title: 'Gyroscope (rad/s)',
                subtitle: 'Données en temps réel',
                showDivider: false,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: GyroscopeChart(
                  data: viewModel.liveGyroscopeData,
                  isLive: viewModel.isLive,
                ),
              ),

              const SizedBox(height: 16),

              // Stats en direct
              NotionCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLiveStat(
                      'Fréquence',
                      '${viewModel.liveFrequency.toStringAsFixed(1)} Hz',
                      Icons.speed,
                    ),
                    _buildLiveStat(
                      'Échantillons',
                      viewModel.liveSampleCount.toString(),
                      Icons.numbers,
                    ),
                    _buildLiveStat(
                      'Temps',
                      _formatDuration(viewModel.liveDuration),
                      Icons.timer,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.accentGray),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.bodyLarge),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    );
  }

  // 📁 Onglet Historique
  Widget _buildHistoryTab(VisualizeViewModel viewModel) {
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viewModel.recordings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: AppColors.border),
            const SizedBox(height: 16),
            Text('Aucun enregistrement', style: AppTextStyles.headline3),
            const SizedBox(height: 8),
            Text(
              'Commencez par enregistrer des données',
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: viewModel.recordings.length,
      itemBuilder: (context, index) {
        final recording = viewModel.recordings[index];
        return _buildRecordingCard(recording, viewModel);
      },
    );
  }

  Widget _buildRecordingCard(
    Map<String, dynamic> recording,
    VisualizeViewModel viewModel,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NotionCard(
        onTap: () => viewModel.loadRecording(recording['path']),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.insert_drive_file,
                    color: AppColors.accentBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording['name'],
                        style: AppTextStyles.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${recording['samples']} échantillons • ${recording['duration']}s',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppColors.accentGray),
                  onSelected: (value) async {
                    if (value == 'delete') {
                      await viewModel.deleteRecording(recording['path']);
                    } else if (value == 'export') {
                      viewModel.exportRecording(recording['path']);
                    } else if (value == 'analyze') {
                      viewModel.analyzeDrift(recording['path']);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'analyze',
                      child: Row(
                        children: [
                          Icon(Icons.analytics, size: 18),
                          SizedBox(width: 8),
                          Text('Analyser la dérive'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.share, size: 18),
                          SizedBox(width: 8),
                          Text('Exporter'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete,
                            color: AppColors.accentRed,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Supprimer',
                            style: TextStyle(color: AppColors.accentRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (recording['selected'] == true) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Mini visualisation
              SizedBox(
                height: 100,
                child: AccelerometerChart(
                  data: recording['previewData'] ?? [],
                  isLive: false,
                  showLegend: false,
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: NotionButton(
                      label: 'Voir trajectoire',
                      icon: Icons.show_chart,
                      type: NotionButtonType.secondary,
                      onPressed: () {
                        _tabController.animateTo(2);
                        viewModel.loadRecording(recording['path']);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  NotionButton(
                    label: 'Fusionner',
                    icon: Icons.merge,
                    type: NotionButtonType.text,
                    onPressed: () =>
                        viewModel.processWithFusion(recording['path']),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 🗺️ Onglet Trajectoire
  Widget _buildTrajectoryTab(VisualizeViewModel viewModel) {
    if (viewModel.selectedRecording == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: AppColors.border),
            const SizedBox(height: 16),
            Text('Aucune donnée sélectionnée', style: AppTextStyles.headline3),
            const SizedBox(height: 8),
            Text(
              'Choisissez un enregistrement dans l\'onglet Historique',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Infos fichier
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      viewModel.selectedRecording!['name'],
                      style: AppTextStyles.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${viewModel.selectedRecording!['samples']} échantillons',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              NotionButton(
                label: 'Recalculer',
                icon: Icons.refresh,
                type: NotionButtonType.secondary,
                onPressed: () => viewModel.recomputeTrajectory(),
              ),
            ],
          ),
        ),

        // Graphique trajectoire
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TrajectoryChart(
              trajectory: viewModel.trajectoryPoints,
              reference: viewModel.referencePoints,
              drift: viewModel.driftAmount,
            ),
          ),
        ),

        // Analyse de la dérive
        if (viewModel.driftAnalysis != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                NotionHeader(title: 'Analyse de la dérive', showDivider: false),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildDriftMetric(
                      'Erreur finale',
                      '${viewModel.driftAnalysis!['finalError']?.toStringAsFixed(2)} m',
                      Icons.location_on,
                    ),
                    _buildDriftMetric(
                      'Dérive relative',
                      '${viewModel.driftAnalysis!['relativeError']?.toStringAsFixed(1)}%',
                      Icons.percent,
                    ),
                    _buildDriftMetric(
                      'Distance totale',
                      '${viewModel.driftAnalysis!['totalDistance']?.toStringAsFixed(1)} m',
                      Icons.straighten,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                NotionButton(
                  label: 'Exporter le rapport',
                  icon: Icons.description,
                  type: NotionButtonType.primary,
                  onPressed: () => viewModel.exportDriftReport(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDriftMetric(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.accentBlue),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.headline3),
          Text(label, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
