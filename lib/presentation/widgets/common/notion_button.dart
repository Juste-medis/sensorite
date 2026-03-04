import 'package:flutter/material.dart';
import '../../../app/theme/colors.dart';
import '../../../app/theme/text_styles.dart';

enum NotionButtonType { primary, secondary, destructive, text }

enum NotionButtonSize { small, medium, large }

class NotionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final NotionButtonType type;
  final NotionButtonSize size;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isLoading;
  final bool expanded;
  final double? width;
  final EdgeInsetsGeometry? padding;

  const NotionButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.type = NotionButtonType.primary,
    this.size = NotionButtonSize.medium,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.expanded = false,
    this.width,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final buttonStyle = _getButtonStyle();
    final buttonSize = _getSize();

    final buttonChild = _buildContent();

    final button = type == NotionButtonType.text
        ? TextButton(
            onPressed: isLoading ? null : onPressed,
            style: TextButton.styleFrom(
              foregroundColor: buttonStyle.textColor,
              padding: padding ?? buttonSize.padding,
              minimumSize: Size(
                expanded ? double.infinity : buttonSize.minWidth,
                buttonSize.height,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: buttonSize.textStyle,
            ),
            child: buttonChild,
          )
        : ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonStyle.backgroundColor,
              foregroundColor: buttonStyle.textColor,
              elevation: 0,
              padding: padding ?? buttonSize.padding,
              minimumSize: Size(
                expanded ? double.infinity : buttonSize.minWidth,
                buttonSize.height,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: type == NotionButtonType.secondary
                    ? const BorderSide(color: AppColors.border)
                    : BorderSide.none,
              ),
              textStyle: buttonSize.textStyle,
            ),
            child: buttonChild,
          );

    if (width != null) {
      return SizedBox(width: width, child: button);
    }

    return button;
  }

  Widget _buildContent() {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            type == NotionButtonType.primary
                ? Colors.white
                : AppColors.accentBlue,
          ),
        ),
      );
    }

    if (iconWidget != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget!,
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _getIconSize()),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
    }

    return Text(label, overflow: TextOverflow.ellipsis);
  }

  double _getIconSize() {
    switch (size) {
      case NotionButtonSize.small:
        return 14;
      case NotionButtonSize.medium:
        return 18;
      case NotionButtonSize.large:
        return 20;
    }
  }

  _ButtonStyle _getButtonStyle() {
    switch (type) {
      case NotionButtonType.primary:
        return _ButtonStyle(
          backgroundColor: AppColors.accentBlue,
          textColor: Colors.white,
        );
      case NotionButtonType.secondary:
        return _ButtonStyle(
          backgroundColor: Colors.transparent,
          textColor: AppColors.textPrimary,
        );
      case NotionButtonType.destructive:
        return _ButtonStyle(
          backgroundColor: AppColors.accentRed,
          textColor: Colors.white,
        );
      case NotionButtonType.text:
        return _ButtonStyle(
          backgroundColor: Colors.transparent,
          textColor: AppColors.textPrimary,
        );
    }
  }

  _ButtonSize _getSize() {
    switch (size) {
      case NotionButtonSize.small:
        return _ButtonSize(
          height: 32,
          minWidth: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          textStyle: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
          ),
        );
      case NotionButtonSize.medium:
        return _ButtonSize(
          height: 40,
          minWidth: 88,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTextStyles.button,
        );
      case NotionButtonSize.large:
        return _ButtonSize(
          height: 48,
          minWidth: 120,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w500,
          ),
        );
    }
  }
}

class _ButtonStyle {
  final Color backgroundColor;
  final Color textColor;

  _ButtonStyle({required this.backgroundColor, required this.textColor});
}

class _ButtonSize {
  final double height;
  final double minWidth;
  final EdgeInsetsGeometry padding;
  final TextStyle textStyle;

  _ButtonSize({
    required this.height,
    required this.minWidth,
    required this.padding,
    required this.textStyle,
  });
}

// Version icon only button
class NotionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final double size;
  final String? tooltip;

  const NotionIconButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.size = 20,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: size, color: color ?? AppColors.textSecondary),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
