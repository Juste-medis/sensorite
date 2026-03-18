import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../widgets/common/notion_card.dart';
import '../widgets/common/notion_button.dart';
import '../widgets/common/notion_header.dart';
import '../viewmodels/settings_viewmodel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SettingsViewModel>(
        builder: (context, viewModel, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Section Apparence
              NotionHeader(
                title: 'Apparence',
                subtitle: 'Personnalisation de l\'interface',
              ),
              const SizedBox(height: 16),

              NotionCard(
                child: _buildSwitchSetting(
                  label: 'Mode sombre',
                  value: viewModel.darkMode,
                  onChanged: viewModel.setDarkMode,
                  description:
                      'Activer le thème sombre pour réduire la fatigue oculaire',
                ),
              ),

              const SizedBox(height: 24),

              // Section Fréquence d'échantillonnage
              NotionHeader(
                title: 'Capteurs',
                subtitle: 'Configuration de l\'acquisition',
              ),
              const SizedBox(height: 16),

              NotionCard(
                child: Column(
                  children: [
                    _buildDropdownSetting(
                      label: 'Fréquence accéléromètre',
                      value: viewModel.accelerometerFrequency,
                      items: const ['50 Hz', '100 Hz', '200 Hz'],
                      onChanged: viewModel.setAccelerometerFrequency,
                    ),
                    const Divider(height: 24),
                    _buildDropdownSetting(
                      label: 'Fréquence gyroscope',
                      value: viewModel.gyroscopeFrequency,
                      items: const ['50 Hz', '100 Hz', '200 Hz'],
                      onChanged: viewModel.setGyroscopeFrequency,
                    ),
                    const Divider(height: 24),
                    _buildSwitchSetting(
                      label: 'Mode haute précision',
                      value: viewModel.highPrecisionMode,
                      onChanged: viewModel.setHighPrecisionMode,
                      description:
                          'Augmente la précision mais consomme plus de batterie',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section Algorithme
              NotionHeader(
                title: 'Fusion de capteurs',
                subtitle: 'Algorithme d\'estimation d\'orientation',
              ),
              const SizedBox(height: 16),

              NotionCard(
                child: Column(
                  children: [
                    _buildRadioSetting<String>(
                      label: 'Algorithme',
                      value: viewModel.fusionAlgorithm,
                      options: [
                        RadioOption(value: 'madgwick', label: 'Madgwick'),
                        RadioOption(value: 'mahony', label: 'Mahony'),
                        RadioOption(
                          value: 'complementary',
                          label: 'Complémentaire',
                        ),
                      ],
                      onChanged: viewModel.setFusionAlgorithm,
                    ),
                    const Divider(height: 24),

                    // Paramètres spécifiques à Madgwick/Mahony
                    if (viewModel.fusionAlgorithm != 'complementary') ...[
                      _buildSliderSetting(
                        label: 'Gain (Kp)',
                        value: viewModel.filterGain,
                        min: 0.1,
                        max: 2.0,
                        divisions: 19,
                        onChanged: viewModel.setFilterGain,
                        description: 'Vitesse de convergence du filtre',
                      ),
                      const Divider(height: 24),
                    ],

                    _buildSwitchSetting(
                      label: 'Détection d\'arrêts (ZUPT)',
                      value: viewModel.zuptEnabled,
                      onChanged: viewModel.setZuptEnabled,
                      description:
                          'Réinitialise la vitesse lors des phases statiques',
                    ),

                    if (viewModel.zuptEnabled) ...[
                      const SizedBox(height: 16),
                      _buildSliderSetting(
                        label: 'Seuil de détection',
                        value: viewModel.zuptThreshold,
                        min: 0.1,
                        max: 2.0,
                        divisions: 19,
                        onChanged: viewModel.setZuptThreshold,
                        description: 'Sensibilité de détection des arrêts',
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section Stockage
              NotionHeader(title: 'Stockage', subtitle: 'Gestion des données'),
              const SizedBox(height: 16),

              NotionCard(
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Dossier d\'enregistrement',
                      viewModel.storagePath,
                      icon: Icons.folder_outlined,
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      'Espace disponible',
                      viewModel.availableSpace,
                      icon: Icons.storage_outlined,
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      'Nombre d\'enregistrements',
                      '${viewModel.recordingsCount}',
                      icon: Icons.description_outlined,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: NotionButton(
                            label: 'Ouvrir le dossier',
                            icon: Icons.folder_open,
                            type: NotionButtonType.secondary,
                            onPressed: viewModel.openStorageFolder,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: NotionButton(
                            label: 'Nettoyer',
                            icon: Icons.clean_hands,
                            type: NotionButtonType.text,
                            onPressed: viewModel.cleanOldRecordings,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section À propos
              NotionHeader(
                title: 'À propos',
                subtitle: 'Version et informations',
              ),
              const SizedBox(height: 16),

              NotionCard(
                child: Column(
                  children: [
                    _buildAboutRow('Version', '1.0.0'),
                    const Divider(height: 24),
                    _buildAboutRow('Développé avec', 'Flutter 3.x'),
                    const Divider(height: 24),
                    _buildAboutRow('Capteurs', 'sensors_plus'),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Bouton de réinitialisation
              Center(
                child: NotionButton(
                  label: 'Réinitialiser les paramètres',
                  type: NotionButtonType.text,
                  onPressed: viewModel.resetToDefaults,
                ),
              ),

              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdownSetting({
    required String label,
    required String value,
    required List<String> items,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(item, style: AppTextStyles.bodyLarge),
                );
              }).toList(),
              onChanged: (val) => onChanged(val!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting({
    required String label,
    required bool value,
    required Function(bool) onChanged,
    String? description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.bodyLarge),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(description, style: AppTextStyles.bodySmall),
              ],
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.accentBlue,
        ),
      ],
    );
  }

  Widget _buildRadioSetting<T>({
    required String label,
    required T value,
    required List<RadioOption<T>> options,
    required Function(T) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        const SizedBox(height: 12),
        ...options.map(
          (option) => RadioListTile<T>(
            title: Text(option.label, style: AppTextStyles.bodyLarge),
            value: option.value,
            groupValue: value,
            onChanged: (val) => onChanged(val as T),
            activeColor: AppColors.accentBlue,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSliderSetting({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double) onChanged,
    String? description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.bodyMedium),
            Text(value.toStringAsFixed(2), style: AppTextStyles.bodyLarge),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description, style: AppTextStyles.bodySmall),
        ],
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: AppColors.accentBlue,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.accentGray),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
          Text(value, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }

  Widget _buildAboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(value, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }
}

class RadioOption<T> {
  final T value;
  final String label;

  RadioOption({required this.value, required this.label});
}
