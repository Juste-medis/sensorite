import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../app/theme/colors.dart';
import '../../../app/theme/text_styles.dart';
import '../common/notion_card.dart';

class GyroscopeChart extends StatefulWidget {
  final List<Map<String, double>> data;
  final bool isLive;
  final bool showLegend;
  final double height;

  const GyroscopeChart({
    Key? key,
    required this.data,
    this.isLive = false,
    this.showLegend = true,
    this.height = 200,
  }) : super(key: key);

  @override
  State<GyroscopeChart> createState() => _GyroscopeChartState();
}

class _GyroscopeChartState extends State<GyroscopeChart> {
  late List<FlSpot> _spotsX;
  late List<FlSpot> _spotsY;
  late List<FlSpot> _spotsZ;
  double _minX = 0;
  double _maxX = 100;
  double _minY = -5;
  double _maxY = 5;

  @override
  void didUpdateWidget(GyroscopeChart oldWidget) {
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

    _spotsX = [];
    _spotsY = [];
    _spotsZ = [];

    double firstX = widget.data.first['x'] ?? 0;
    double lastX = widget.data.last['x'] ?? 100;

    for (var point in widget.data) {
      final x = (point['x'] ?? 0) - firstX;

      if (point.containsKey('gyroX')) {
        _spotsX.add(FlSpot(x, point['gyroX'] ?? 0));
      }
      if (point.containsKey('gyroY')) {
        _spotsY.add(FlSpot(x, point['gyroY'] ?? 0));
      }
      if (point.containsKey('gyroZ')) {
        _spotsZ.add(FlSpot(x, point['gyroZ'] ?? 0));
      }
    }

    _minX = 0;
    _maxX = (lastX - firstX).clamp(10, 10000);

    final allValues = [
      ..._spotsX.map((s) => s.y),
      ..._spotsY.map((s) => s.y),
      ..._spotsZ.map((s) => s.y),
    ];

    if (allValues.isNotEmpty) {
      final minVal = allValues.reduce((a, b) => a < b ? a : b);
      final maxVal = allValues.reduce((a, b) => a > b ? a : b);
      final range = (maxVal - minVal).abs();
      final margin = range * 0.1 + 0.5;

      _minY = (minVal - margin).floorToDouble();
      _maxY = (maxVal + margin).ceilToDouble();
    }

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
                _buildLegendItem('X (roll)', Colors.purple),
                const SizedBox(width: 16),
                _buildLegendItem('Y (pitch)', Colors.orange),
                const SizedBox(width: 16),
                _buildLegendItem('Z (yaw)', Colors.teal),
                const Spacer(),
                Text('rad/s', style: AppTextStyles.bodySmall),
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
                  horizontalInterval: 1,
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
                    color: Colors.purple,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: _spotsY,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: _spotsZ,
                    isCurved: true,
                    color: Colors.teal,
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
                        String label =
                            'Roll: ${spot.y.toStringAsFixed(3)} rad/s';
                        if (spot.barIndex == 1) {
                          label = 'Pitch: ${spot.y.toStringAsFixed(3)} rad/s';
                        } else if (spot.barIndex == 2) {
                          label = 'Yaw: ${spot.y.toStringAsFixed(3)} rad/s';
                        }
                        return LineTooltipItem(
                          label,
                          TextStyle(
                            color: spot.barIndex == 0
                                ? Colors.purple
                                : (spot.barIndex == 1
                                      ? Colors.orange
                                      : Colors.teal),
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
