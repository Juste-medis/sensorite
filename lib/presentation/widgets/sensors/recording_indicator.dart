import 'package:flutter/material.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

class RecordingIndicator extends StatelessWidget {
  final bool isRecording;
  final bool isPaused;
  final Duration duration;
  final int sampleCount;

  const RecordingIndicator({
    Key? key,
    required this.isRecording,
    required this.isPaused,
    required this.duration,
    required this.sampleCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final timeString = hours > 0
        ? '$hours:${_twoDigits(minutes)}:${_twoDigits(seconds)}'
        : '${_twoDigits(minutes)}:${_twoDigits(seconds)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPaused
            ? AppColors.hover
            : (isRecording
                  ? AppColors.accentRed.withOpacity(0.1)
                  : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRecording
              ? (isPaused ? AppColors.accentGray : AppColors.accentRed)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPaused
                  ? AppColors.accentGray
                  : (isRecording ? AppColors.accentRed : Colors.transparent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPaused ? 'En pause' : 'Enregistrement',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$timeString • $sampleCount échantillons',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
