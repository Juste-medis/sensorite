import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';
import '../common/notion_card.dart';

class AccelerometerChart extends StatefulWidget {
  final List<Map<String, double>> data;
  final bool isLive;
  final bool showLegend;
  final double height;
  final Duration? timeWindow;

  const AccelerometerChart({
    Key? key,
    required this.data,
    this.isLive = false,
    this.showLegend = true,
    this.height = 200,
    this.timeWindow,
  }) : super(key: key);

  @override
  State<AccelerometerChart> createState() => _AccelerometerChartState();
}

class _AccelerometerChartState extends State<AccelerometerChart> {
  late List<FlSpot> _spotsX;
  late List<FlSpot> _spotsY;
  late List<FlSpot> _spotsZ;
  double _minX = 0;
  double _maxX = 100;
  double _minY = -10;
  double _maxY = 10;

  @override
  void didUpdateWidget(AccelerometerChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _processData();
    }
  }

  @override
  void initState() {
    super.initState();
    _processData();
  }

  void _processData() {
    if (widget.data.isEmpty) {
      _spotsX = [];
      _spotsY = [];
      _spotsZ = [];
      return;
    }

    // Extraire les points
    _spotsX = [];
    _spotsY = [];
    _spotsZ = [];

    double firstX = widget.data.first['x'] ?? 0;
    double lastX = widget.data.last['x'] ?? 100;

    for (var point in widget.data) {
      final x = (point['x'] ?? 0) - firstX; // Normaliser le temps

      if (point.containsKey('accelX')) {
        _spotsX.add(FlSpot(x, point['accelX'] ?? 0));
      }
      if (point.containsKey('accelY')) {
        _spotsY.add(FlSpot(x, point['accelY'] ?? 0));
      }
      if (point.containsKey('accelZ')) {
        _spotsZ.add(FlSpot(x, point['accelZ'] ?? 0));
      }
    }

    // Calculer les limites
    _minX = 0;
    _maxX =
        widget.timeWindow?.inMilliseconds?.toDouble() ??
        (lastX - firstX).clamp(10, 10000);

    // Calculer les limites Y avec une marge
    final allValues = [
      ..._spotsX.map((s) => s.y),
      ..._spotsY.map((s) => s.y),
      ..._spotsZ.map((s) => s.y),
    ];

    if (allValues.isNotEmpty) {
      final minVal = allValues.reduce((a, b) => a < b ? a : b);
      final maxVal = allValues.reduce((a, b) => a > b ? a : b);
      final range = (maxVal - minVal).abs();
      final margin = range * 0.1 + 1;

      _minY = (minVal - margin).floorToDouble();
      _maxY = (maxVal + margin).ceilToDouble();
    }

    // Pour les données live, garder une fenêtre glissante
    if (widget.isLive && _maxX - _minX > 10000) {
      _minX = _maxX - 10000;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLegend) ...[
            Row(
              children: [
                _buildLegendItem('X', AppColors.accentRed),
                const SizedBox(width: 16),
                _buildLegendItem('Y', AppColors.accentGreen),
                const SizedBox(width: 16),
                _buildLegendItem('Z', AppColors.accentBlue),
                const Spacer(),
                Text(
                  widget.isLive ? 'Temps réel' : 'Historique',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: widget.height - (widget.showLegend ? 60 : 20),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 2,
                  verticalInterval: _maxX / 5,
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
                      interval: _maxX / 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${(value / 1000).toStringAsFixed(1)}s',
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
                  LineChartBarData(
                    spots: _spotsX,
                    isCurved: true,
                    color: AppColors.accentRed,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: _spotsY,
                    isCurved: true,
                    color: AppColors.accentGreen,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: _spotsZ,
                    isCurved: true,
                    color: AppColors.accentBlue,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
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
                        String label = 'X: ${spot.y.toStringAsFixed(3)} m/s²';
                        if (spot.barIndex == 1) {
                          label = 'Y: ${spot.y.toStringAsFixed(3)} m/s²';
                        } else if (spot.barIndex == 2) {
                          label = 'Z: ${spot.y.toStringAsFixed(3)} m/s²';
                        }
                        return LineTooltipItem(
                          label,
                          TextStyle(
                            color: spot.barIndex == 0
                                ? AppColors.accentRed
                                : (spot.barIndex == 1
                                      ? AppColors.accentGreen
                                      : AppColors.accentBlue),
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
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
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
}
