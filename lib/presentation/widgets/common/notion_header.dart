import 'package:flutter/material.dart';
import 'package:sensorite/presentation/widgets/common/notion_button.dart';
import '../../../app/theme/colors.dart';
import '../../../app/theme/text_styles.dart';

enum NotionHeaderSize { small, medium, large }

class NotionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final bool showDivider;
  final double? dividerIndent;
  final NotionHeaderSize size;
  final EdgeInsetsGeometry padding;

  const NotionHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.showDivider = true,
    this.dividerIndent,
    this.size = NotionHeaderSize.medium,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final titleStyle = _getTitleStyle();
    final subtitleStyle = _getSubtitleStyle();
    final verticalSpacing = _getSpacing();

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    if (subtitle != null) ...[
                      SizedBox(height: verticalSpacing),
                      Text(subtitle!, style: subtitleStyle),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (showDivider) ...[
            SizedBox(height: verticalSpacing * 2),
            Divider(
              color: AppColors.border,
              thickness: 1,
              height: 1,
              indent: dividerIndent,
            ),
          ],
        ],
      ),
    );
  }

  TextStyle _getTitleStyle() {
    switch (size) {
      case NotionHeaderSize.small:
        return AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600);
      case NotionHeaderSize.medium:
        return AppTextStyles.headline3;
      case NotionHeaderSize.large:
        return AppTextStyles.headline2;
    }
  }

  TextStyle _getSubtitleStyle() {
    switch (size) {
      case NotionHeaderSize.small:
        return AppTextStyles.bodySmall;
      case NotionHeaderSize.medium:
        return AppTextStyles.bodyMedium;
      case NotionHeaderSize.large:
        return AppTextStyles.bodyLarge;
    }
  }

  double _getSpacing() {
    switch (size) {
      case NotionHeaderSize.small:
        return 2;
      case NotionHeaderSize.medium:
        return 4;
      case NotionHeaderSize.large:
        return 6;
    }
  }
}

// Version avec action principale
class NotionActionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onActionPressed;
  final IconData? actionIcon;

  const NotionActionHeader({
    Key? key,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onActionPressed,
    this.actionIcon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return NotionHeader(
      title: title,
      subtitle: subtitle,
      trailing: TextButton.icon(
        onPressed: onActionPressed,
        icon: Icon(actionIcon ?? Icons.add, size: 18),
        label: Text(actionLabel),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentBlue,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
    );
  }
}

// Version pour page
class NotionPageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const NotionPageHeader({
    Key? key,
    required this.title,
    this.onBack,
    this.actions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            NotionIconButton(icon: Icons.arrow_back, onPressed: onBack!),
          if (onBack != null) const SizedBox(width: 8),
          Expanded(child: Text(title, style: AppTextStyles.headline3)),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
