import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/recording_viewmodel.dart';
import '../widgets/common/notion_card.dart';
import '../widgets/common/notion_button.dart';
import '../widgets/common/notion_header.dart';
import '../widgets/sensors/recording_indicator.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/text_styles.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({Key? key}) : super(key: key);

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeViewModel();
  }

  Future<void> _initializeViewModel() async {
    final viewModel = Provider.of<RecordingViewModel>(context, listen: false);
    await viewModel.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enregistrement IMU')),
      body: Consumer<RecordingViewModel>(
        builder: (context, viewModel, child) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NotionHeader(
                  title: 'Acquisition de données',
                  subtitle: viewModel.isRecording
                      ? 'Enregistrement en cours'
                      : 'Prêt à enregistrer',
                ),
                const SizedBox(height: 24),

                if (!viewModel.isRecording) ...[
                  _buildPreparationView(viewModel),
                ] else ...[
                  _buildRecordingView(viewModel),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreparationView(RecordingViewModel viewModel) {
    return Expanded(
      child: Column(
        children: [
          NotionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nom du fichier (optionnel)',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fileNameController,
                  decoration: const InputDecoration(
                    hintText: 'ex: tunnel_essai_1',
                    prefixIcon: Icon(Icons.edit_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Les données seront enregistrées au format CSV avec :',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 12),
                _buildFeatureRow(Icons.timer, 'Timestamp (ms)'),
                _buildFeatureRow(
                  Icons.sensors,
                  'Accéléromètre (X, Y, Z) en m/s²',
                ),
                _buildFeatureRow(Icons.bolt, 'Gyroscope (X, Y, Z) en rad/s'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          NotionButton(
            label: 'Démarrer l\'enregistrement',
            icon: Icons.fiber_manual_record,
            type: NotionButtonType.primary,
            onPressed: () => _startRecording(viewModel),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.accentGray),
          const SizedBox(width: 8),
          Text(text, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildRecordingView(RecordingViewModel viewModel) {
    return Expanded(
      child: Column(
        children: [
          RecordingIndicator(
            isRecording: viewModel.isRecording,
            isPaused: viewModel.isPaused,
            duration: viewModel.recordingDuration,
            sampleCount: viewModel.sampleCount,
          ),
          const SizedBox(height: 24),

          NotionCard(
            child: Column(
              children: [
                _buildInfoRow('Fichier', viewModel.currentFileName ?? '...'),
                const Divider(height: 24),
                _buildInfoRow('Fréquence', '~100 Hz'),
                _buildInfoRow(
                  'Buffer',
                  '${viewModel.sampleCount} échantillons',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              if (!viewModel.isPaused) ...[
                Expanded(
                  child: NotionButton(
                    label: 'Pause',
                    icon: Icons.pause,
                    type: NotionButtonType.secondary,
                    onPressed: viewModel.pauseRecording,
                  ),
                ),
              ] else ...[
                Expanded(
                  child: NotionButton(
                    label: 'Reprendre',
                    icon: Icons.play_arrow,
                    type: NotionButtonType.primary,
                    onPressed: viewModel.resumeRecording,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: NotionButton(
                  label: 'Arrêter',
                  icon: Icons.stop,
                  type: NotionButtonType.destructive,
                  onPressed: () => _stopRecording(viewModel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          NotionButton(
            label: 'Annuler',
            type: NotionButtonType.text,
            onPressed: () => _cancelRecording(viewModel),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(value, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }

  Future<void> _startRecording(RecordingViewModel viewModel) async {
    final customName = _fileNameController.text.trim().isEmpty
        ? null
        : _fileNameController.text.trim();

    await viewModel.startRecording(customName: customName);
  }

  Future<void> _stopRecording(RecordingViewModel viewModel) async {
    final file = await viewModel.stopRecording();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Enregistrement sauvegardé : ${file?.path.split('/').last}',
        ),
        backgroundColor: AppColors.accentGreen,
        duration: const Duration(seconds: 3),
      ),
    );

    Navigator.pop(context);
  }

  Future<void> _cancelRecording(RecordingViewModel viewModel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler ?'),
        content: const Text('Les données non sauvegardées seront perdues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          NotionButton(
            label: 'Annuler',
            type: NotionButtonType.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await viewModel.cancelRecording();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }
}
