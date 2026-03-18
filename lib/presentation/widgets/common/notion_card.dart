import 'package:flutter/material.dart';
import 'package:sensorite/theme/text_styles.dart';
import '../../../theme/colors.dart';

enum NotionCardVariant { elevated, outlined, flat }

class NotionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double? elevation;
  final NotionCardVariant variant;
  final BorderRadius? borderRadius;
  final bool hasShadow;

  const NotionCard({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.elevation,
    this.variant = NotionCardVariant.outlined,
    this.borderRadius,
    this.hasShadow = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? _getBackgroundColor();
    final cardElevation = elevation ?? _getElevation();
    final cardBorder = _getBorder();
    final cardBorderRadius = borderRadius ?? BorderRadius.circular(8);

    Widget card = Material(
      color: cardColor,
      elevation: cardElevation,
      shadowColor: hasShadow
          ? Colors.black.withOpacity(0.1)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: cardBorderRadius,
        side: cardBorder,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: cardBorderRadius,
        splashColor: AppColors.hover,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }

  Color _getBackgroundColor() {
    switch (variant) {
      case NotionCardVariant.elevated:
        return AppColors.surface;
      case NotionCardVariant.outlined:
        return AppColors.surface;
      case NotionCardVariant.flat:
        return Colors.transparent;
    }
  }

  double _getElevation() {
    switch (variant) {
      case NotionCardVariant.elevated:
        return 2;
      case NotionCardVariant.outlined:
        return 0;
      case NotionCardVariant.flat:
        return 0;
    }
  }

  BorderSide _getBorder() {
    switch (variant) {
      case NotionCardVariant.elevated:
        return BorderSide.none;
      case NotionCardVariant.outlined:
        return const BorderSide(color: AppColors.border, width: 1);
      case NotionCardVariant.flat:
        return BorderSide.none;
    }
  }
}

// Version avec en-tête
class NotionCardWithHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget child;
  final VoidCallback? onTap;
  final bool showDivider;

  const NotionCardWithHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.headerTrailing,
    required this.child,
    this.onTap,
    this.showDivider = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return NotionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: AppTextStyles.bodySmall),
                    ],
                  ],
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
          if (showDivider) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

// Version cliquable
class NotionClickableCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;

  const NotionClickableCard({
    Key? key,
    required this.child,
    required this.onTap,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return NotionCard(
      onTap: onTap,
      padding: padding ?? const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: child),
          Icon(Icons.chevron_right, size: 20, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }
}
