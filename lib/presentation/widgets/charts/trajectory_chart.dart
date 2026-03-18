import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';
import '../common/notion_card.dart';

class TrajectoryChart extends StatefulWidget {
  final List<Offset> trajectory;
  final List<Offset>? reference;
  final double? drift;
  final double height;

  const TrajectoryChart({
    Key? key,
    required this.trajectory,
    this.reference,
    this.drift,
    this.height = 300,
  }) : super(key: key);

  @override
  State<TrajectoryChart> createState() => _TrajectoryChartState();
}

class _TrajectoryChartState extends State<TrajectoryChart> {
  late List<FlSpot> _trajectorySpots;
  late List<FlSpot> _referenceSpots;
  double _minX = 0;
  double _maxX = 10;
  double _minY = 0;
  double _maxY = 10;

  @override
  void didUpdateWidget(TrajectoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trajectory != widget.trajectory) {
      _processData();
    }
  }

  @override
  void initState() {
    super.initState();
    _processData();
  }

  void _processData() {
    // Convertir les offsets en FlSpot
    _trajectorySpots = widget.trajectory
        .asMap()
        .entries
        .map((e) => FlSpot(e.value.dx, e.value.dy))
        .toList();

    _referenceSpots =
        widget.reference
            ?.asMap()
            .entries
            .map((e) => FlSpot(e.value.dx, e.value.dy))
            .toList() ??
        [];

    // Calculer les limites avec une marge
    if (_trajectorySpots.isNotEmpty) {
      final allX = [
        ..._trajectorySpots.map((s) => s.x),
        ..._referenceSpots.map((s) => s.x),
      ];
      final allY = [
        ..._trajectorySpots.map((s) => s.y),
        ..._referenceSpots.map((s) => s.y),
      ];

      if (allX.isNotEmpty) {
        final minX = allX.reduce(min);
        final maxX = allX.reduce(max);
        final rangeX = maxX - minX;
        final marginX = rangeX * 0.1 + 0.5;

        _minX = (minX - marginX).floorToDouble();
        _maxX = (maxX + marginX).ceilToDouble();
      }

      if (allY.isNotEmpty) {
        final minY = allY.reduce(min);
        final maxY = allY.reduce(max);
        final rangeY = maxY - minY;
        final marginY = rangeY * 0.1 + 0.5;

        _minY = (minY - marginY).floorToDouble();
        _maxY = (maxY + marginY).ceilToDouble();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Légende
          Row(
            children: [
              _buildLegendItem('Trajectoire estimée', AppColors.accentBlue),
              if (_referenceSpots.isNotEmpty) ...[
                const SizedBox(width: 16),
                _buildLegendItem(
                  'Trajectoire référence',
                  AppColors.accentGreen,
                ),
              ],
              const Spacer(),
              if (widget.drift != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Dérive: ${widget.drift!.toStringAsFixed(2)} m',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.accentRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Graphique
          SizedBox(
            height: widget.height - 60,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: (_maxY - _minY) / 5,
                  verticalInterval: (_maxX - _minX) / 5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppColors.border,
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                      color: AppColors.border,
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (_maxX - _minX) / 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toStringAsFixed(1)} m',
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      interval: (_maxY - _minY) / 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(1),
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                minX: _minX,
                maxX: _maxX,
                minY: _minY,
                maxY: _maxY,
                lineBarsData: [
                  // Trajectoire de référence (pointillés)
                  if (_referenceSpots.isNotEmpty)
                    LineChartBarData(
                      spots: _referenceSpots,
                      isCurved: false,
                      color: AppColors.accentGreen,
                      barWidth: 2,
                      dashArray: [5, 5],
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: AppColors.accentGreen,
                            strokeWidth: 0,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),

                  // Trajectoire estimée
                  LineChartBarData(
                    spots: _trajectorySpots,
                    isCurved: true,
                    color: AppColors.accentBlue,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) {
                        return FlDotCirclePainter(
                          radius: 2,
                          color: AppColors.accentBlue,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: AppColors.surface,
                    tooltipRoundedRadius: 6,
                    tooltipBorder: BorderSide(color: AppColors.border),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final isReference =
                            spot.barIndex == 0 && _referenceSpots.isNotEmpty;
                        return LineTooltipItem(
                          '(${spot.x.toStringAsFixed(2)}, ${spot.y.toStringAsFixed(2)})',
                          TextStyle(
                            color: isReference
                                ? AppColors.accentGreen
                                : AppColors.accentBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),

          // Informations complémentaires
          if (_trajectorySpots.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat(
                  'Distance',
                  '${_calculateDistance().toStringAsFixed(1)} m',
                  Icons.straighten,
                ),
                _buildStat(
                  'Points',
                  '${_trajectorySpots.length}',
                  Icons.location_on,
                ),
                if (_referenceSpots.isNotEmpty)
                  _buildStat(
                    'Erreur max',
                    '${_calculateMaxError().toStringAsFixed(2)} m',
                    Icons.error_outline,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.accentGray),
        const SizedBox(width: 4),
        Text('$label: ', style: AppTextStyles.bodySmall),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  double _calculateDistance() {
    if (_trajectorySpots.length < 2) return 0;

    double distance = 0;
    for (int i = 0; i < _trajectorySpots.length - 1; i++) {
      final p1 = _trajectorySpots[i];
      final p2 = _trajectorySpots[i + 1];
      distance += sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2));
    }
    return distance;
  }

  double _calculateMaxError() {
    if (_referenceSpots.isEmpty || _trajectorySpots.isEmpty) return 0;

    double maxError = 0;
    for (
      int i = 0;
      i < min(_referenceSpots.length, _trajectorySpots.length);
      i++
    ) {
      final ref = _referenceSpots[i];
      final est = _trajectorySpots[i];
      final error = sqrt(pow(ref.x - est.x, 2) + pow(ref.y - est.y, 2));
      maxError = max(maxError, error);
    }
    return maxError;
  }
}
