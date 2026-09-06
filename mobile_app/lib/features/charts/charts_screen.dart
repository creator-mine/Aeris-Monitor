import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'providers/charts_provider.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/error_widget.dart';
import '../../shared/theme/app_theme.dart';

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({Key? key}) : super(key: key);

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ChartsProvider>();
      if (provider.selectedDeviceId != null) {
        provider.loadData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Графики',
      body: Consumer<ChartsProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildSensorTypeSelector(context, provider),
              _buildTimeRangeSelector(context, provider),
              Expanded(
                child: _buildChartArea(context, provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSensorTypeSelector(BuildContext context, ChartsProvider provider) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: provider.availableSensorTypes.length,
        itemBuilder: (context, index) {
          final sensorType = provider.availableSensorTypes[index];
          final isSelected = provider.selectedSensorType == sensorType;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(provider.getSensorName(sensorType)),
              selected: isSelected,
              onSelected: (selected) {
                provider.setSelectedSensorType(sensorType);
              },
              selectedColor: AppTheme.primaryColor,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeRangeSelector(BuildContext context, ChartsProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTimeRangeButton(context, provider, '1ч', const Duration(hours: 1)),
          _buildTimeRangeButton(context, provider, '6ч', const Duration(hours: 6)),
          _buildTimeRangeButton(context, provider, '24ч', const Duration(hours: 24)),
          _buildTimeRangeButton(context, provider, '7д', const Duration(days: 7)),
          _buildTimeRangeButton(context, provider, '30д', const Duration(days: 30)),
        ],
      ),
    );
  }

  Widget _buildTimeRangeButton(
    BuildContext context,
    ChartsProvider provider,
    String label,
    Duration duration,
  ) {
    final isSelected = provider.timeRange.end.difference(provider.timeRange.start) == duration;
    
    return OutlinedButton(
      onPressed: () {
        provider.setTimeRange(DateTimeRange(
          start: DateTime.now().subtract(duration),
          end: DateTime.now(),
        ));
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? AppTheme.primaryColor : null,
        foregroundColor: isSelected ? Colors.white : null,
        side: BorderSide(
          color: isSelected ? AppTheme.primaryColor : Colors.grey,
        ),
      ),
      child: Text(label),
    );
  }

  Widget _buildChartArea(BuildContext context, ChartsProvider provider) {
    if (provider.isLoading) {
      return const LoadingIndicator(message: 'Загрузка данных...');
    }

    if (provider.error != null) {
      return AppErrorWidget(
        message: provider.error!,
        onRetry: () => provider.loadData(),
      );
    }

    final series = provider.currentSeries;
    if (series == null || series.points.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Нет данных для отображения',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(context, provider, series),
          const SizedBox(height: 16),
          Expanded(
            child: _buildLineChart(context, provider, series),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, ChartsProvider provider, series) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatCard(
          context,
          'Минимум',
          '${series.minValue.toStringAsFixed(1)} ${provider.getSensorUnit(provider.selectedSensorType)}',
          AppTheme.infoColor,
        ),
        _buildStatCard(
          context,
          'Среднее',
          '${series.avgValue.toStringAsFixed(1)} ${provider.getSensorUnit(provider.selectedSensorType)}',
          AppTheme.successColor,
        ),
        _buildStatCard(
          context,
          'Максимум',
          '${series.maxValue.toStringAsFixed(1)} ${provider.getSensorUnit(provider.selectedSensorType)}',
          AppTheme.warningColor,
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(BuildContext context, ChartsProvider provider, series) {
    final range = series.maxValue - series.minValue;
    final safeRange = range == 0 ? 1.0 : range;
    final pointCount = series.points.length;
    final safePointCount = pointCount == 0 ? 1.0 : pointCount.toDouble();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: safeRange / 5,
          verticalInterval: safePointCount / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: safePointCount / 5,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= series.points.length) {
                  return const Text('');
                }
                final point = series.points[value.toInt()];
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${point.timestamp.hour}:${point.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: safeRange / 5,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        minX: 0,
        maxX: pointCount > 0 ? pointCount.toDouble() - 1 : 1,
        minY: series.minValue - safeRange * 0.1,
        maxY: series.maxValue + safeRange * 0.1,
        lineBarsData: [
          LineChartBarData(
            spots: series.points
                .asMap()
                .entries
                .map((entry) {
                  return FlSpot(entry.key.toDouble(), entry.value.value);
                })
                .toList(),
            isCurved: true,
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withOpacity(0.5),
                AppTheme.primaryColor,
              ],
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withOpacity(0.3),
                  AppTheme.primaryColor.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
