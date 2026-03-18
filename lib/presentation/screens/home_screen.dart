import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:sensorite/presentation/map/mapview.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../widgets/common/notion_card.dart';
import '../widgets/common/notion_header.dart';
import 'record_screen.dart';
import 'visualize_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensorite'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // const NotionHeader(
            //   title: 'Navigation à l\'estime',
            //   subtitle: 'Analyse de la dérive en tunnel',
            //   showDivider: false,
            // ),
            // const SizedBox(height: 24),
            Expanded(flex: 5, child: SizedBox.expand(child: OSMFlutterMap())),
            10.height,
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                children: [
                  _buildFeatureCard(
                    context,
                    title: 'Enregistrement',
                    icon: Icons.fiber_manual_record,
                    color: AppColors.accentRed,
                    description: 'Acquérir des données IMU',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecordScreen()),
                    ),
                  ),
                  _buildFeatureCard(
                    context,
                    title: 'Visualisation',
                    icon: Icons.show_chart,
                    color: AppColors.accentBlue,
                    description: 'Trajectoires et graphiques',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VisualizeScreen(),
                      ),
                    ),
                  ),
                  _buildFeatureCard(
                    context,
                    title: 'Données',
                    icon: Icons.folder_outlined,
                    color: AppColors.accentGray,
                    description: 'Fichiers enregistrés',
                    onTap: () {},
                  ),
                  _buildFeatureCard(
                    context,
                    title: 'Analyse',
                    icon: Icons.analytics_outlined,
                    color: AppColors.accentGreen,
                    description: 'Rapports de dérive',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String description,
    required VoidCallback onTap,
  }) {
    return NotionCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
