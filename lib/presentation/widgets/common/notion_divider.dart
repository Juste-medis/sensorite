import 'package:flutter/material.dart';
import 'package:sensorite/app/theme/text_styles.dart';
import '../../../app/theme/colors.dart';

enum NotionDividerVariant {
  full, // Pleine largeur
  middle, // Avec marges
  inset, // Avec marge gauche (pour listes)
}

class NotionDivider extends StatelessWidget {
  final NotionDividerVariant variant;
  final double thickness;
  final double indent;
  final double endIndent;
  final Color? color;
  final String? label;

  const NotionDivider({
    Key? key,
    this.variant = NotionDividerVariant.full,
    this.thickness = 1,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dividerColor = color ?? AppColors.border;

    if (label != null) {
      return _buildLabeledDivider(dividerColor);
    }

    double horizontalIndent = indent;
    double horizontalEndIndent = endIndent;

    switch (variant) {
      case NotionDividerVariant.full:
        horizontalIndent = 0;
        horizontalEndIndent = 0;
        break;
      case NotionDividerVariant.middle:
        horizontalIndent = 16;
        horizontalEndIndent = 16;
        break;
      case NotionDividerVariant.inset:
        horizontalIndent = 72; // Pour aligner avec les icônes de liste
        horizontalEndIndent = 0;
        break;
    }

    return Divider(
      height: thickness + 16, // Espacement vertical
      thickness: thickness,
      indent: horizontalIndent,
      endIndent: horizontalEndIndent,
      color: dividerColor,
    );
  }

  Widget _buildLabeledDivider(Color dividerColor) {
    return Row(
      children: [
        Expanded(
          child: Container(height: thickness, color: dividerColor),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),

        Expanded(
          child: Container(height: thickness, color: dividerColor),
        ),
      ],
    );
  }
}

// Version verticale
class NotionVerticalDivider extends StatelessWidget {
  final double thickness;
  final double height;
  final double indent;
  final double endIndent;
  final Color? color;

  const NotionVerticalDivider({
    Key? key,
    this.thickness = 1,
    this.height = double.infinity,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: thickness,
      height: height,
      margin: EdgeInsets.symmetric(vertical: indent, horizontal: 0),
      decoration: BoxDecoration(color: color ?? AppColors.border),
    );
  }
}

// Espaceur avec divider optionnel
class NotionSectionSpacer extends StatelessWidget {
  final double height;
  final bool showDivider;

  const NotionSectionSpacer({
    Key? key,
    this.height = 24,
    this.showDivider = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (showDivider) {
      return Column(
        children: [
          const NotionDivider(),
          SizedBox(height: height),
        ],
      );
    }

    return SizedBox(height: height);
  }
}
