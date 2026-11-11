import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'providers/charts_provider.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/error_widget.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/utils/csv_exporter.dart';
import '../devices/providers/devices_provider.dart';
import '../../models/sensor_data.dart';
import '../../models/device.dart';

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

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
      actions: [
        IconButton(
          tooltip: 'Сравнить устройства',
          icon: const Icon(Icons.compare_arrows),
          onPressed: () => _openCompareDialog(context),
        ),
        IconButton(
          tooltip: 'Экспорт CSV',
          icon: const Icon(Icons.save_alt),
          onPressed: () => _exportCsv(context),
        ),
      ],
      body: Consumer<ChartsProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              if (provider.isComparing) _buildCompareBanner(context, provider),
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

  Widget _buildCompareBanner(BuildContext context, ChartsProvider provider) {
    final names = provider.compareNames.values.join(', ');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.compare_arrows, size: 16, color: AppTheme.infoColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Сравнение: $names',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Остановить сравнение',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => provider.clearComparison(),
          ),
        ],
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
    if (provider.isLoading || provider.isLoadingComparison) {
      return const LoadingIndicator(message: 'Загрузка данных...');
    }

    if (provider.error != null && !provider.isComparing) {
      return AppErrorWidget(
        message: provider.error!,
        onRetry: () => provider.loadData(),
      );
    }

    if (provider.isComparing) {
      final series = provider.compareSeries;
      if (series.isEmpty) {
        return const Center(
          child: Text(
            'Нет данных для сравнения',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompareLegend(context, provider),
            const SizedBox(height: 16),
            Expanded(
              child: _buildCompareChart(context, provider),
            ),
          ],
        ),
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
        color: color.withValues(alpha: 0.1),
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
              color: Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey.withValues(alpha: 0.2),
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
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
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
                AppTheme.primaryColor.withValues(alpha: 0.5),
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
                  AppTheme.primaryColor.withValues(alpha: 0.3),
                  AppTheme.primaryColor.withValues(alpha: 0.0),
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

  static const List<Color> _comparePalette = [
    Color(0xFF4C9AFF),
    Color(0xFFFFB020),
    Color(0xFF3BD38C),
    Color(0xFFFF5C7A),
    Color(0xFF9B6BEF),
    Color(0xFF2FC3CC),
  ];

  Widget _buildCompareLegend(BuildContext context, ChartsProvider provider) {
    final entries = provider.compareSeries.entries.toList();
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var i = 0; i < entries.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _comparePalette[i % _comparePalette.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                provider.compareNames[entries[i].key] ?? entries[i].key,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCompareChart(BuildContext context, ChartsProvider provider) {
    final entries = provider.compareSeries.entries.toList();
    var minValue = 0.0;
    var maxValue = 1.0;
    var maxLength = 0;
    for (final entry in entries) {
      final series = entry.value;
      if (series.points.isEmpty) continue;
      if (series.points.length > maxLength) maxLength = series.points.length;
      minValue = minValue == 0 ? series.minValue : minValue <= series.minValue ? minValue : series.minValue;
      maxValue = maxValue == 1 ? series.maxValue : maxValue >= series.maxValue ? maxValue : series.maxValue;
    }
    final safeRange = maxValue - minValue == 0 ? 1.0 : maxValue - minValue;
    final safeLength = maxLength == 0 ? 1.0 : maxLength.toDouble();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: safeRange / 5,
          verticalInterval: safeLength / 5,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
          getDrawingVerticalLine: (value) =>
              FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: safeLength / 5,
              getTitlesWidget: (value, meta) {
                final longest = _longestSeries(entries);
                if (longest == null || value.toInt() >= longest.points.length) {
                  return const Text('');
                }
                final point = longest.points[value.toInt()];
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
              getTitlesWidget: (value, meta) =>
                  Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        minX: 0,
        maxX: safeLength - 1,
        minY: minValue - safeRange * 0.1,
        maxY: maxValue + safeRange * 0.1,
        lineBarsData: [
          for (var i = 0; i < entries.length; i++)
            LineChartBarData(
              spots: entries[i]
                  .value
                  .points
                  .asMap()
                  .entries
                  .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value))
                  .toList(),
              isCurved: true,
              color: _comparePalette[i % _comparePalette.length],
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  SensorDataSeries? _longestSeries(List<MapEntry<String, SensorDataSeries>> entries) {
    SensorDataSeries? longest;
    for (final entry in entries) {
      if (longest == null || entry.value.points.length > longest.points.length) {
        longest = entry.value;
      }
    }
    return longest;
  }

  Future<void> _openCompareDialog(BuildContext context) async {
    final devicesProvider = context.read<DevicesProvider>();
    if (devicesProvider.devices.isEmpty) {
      devicesProvider.loadDevices();
    }
    final devices = devicesProvider.devices.toList();

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _CompareDevicesDialog(
        devices: devices,
        selectedIds: context.read<ChartsProvider>().compareSeries.keys.toSet(),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final provider = context.read<ChartsProvider>();
    final sensorType = provider.selectedSensorType;
    final unit = provider.getSensorUnit(sensorType);

    final buffer = StringBuffer('timestamp,device,value_$sensorType($unit)\n');
    var rows = 0;

    if (provider.isComparing) {
      provider.compareSeries.forEach((deviceId, series) {
        final name = provider.compareNames[deviceId] ?? deviceId;
        for (final point in series.points) {
          buffer
            ..write(point.timestamp.toIso8601String())
            ..write(',')
            ..write(_csvField(name))
            ..write(',')
            ..write(point.value)
            ..write('\n');
          rows++;
        }
      });
    } else {
      final series = provider.currentSeries;
      if (series != null) {
        final deviceName = provider.compareNames[provider.selectedDeviceId] ??
            provider.selectedDeviceId ??
            'device';
        for (final point in series.points) {
          buffer
            ..write(point.timestamp.toIso8601String())
            ..write(',')
            ..write(_csvField(deviceName))
            ..write(',')
            ..write(point.value)
            ..write('\n');
          rows++;
        }
      }
    }

    if (rows == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет данных для экспорта')),
        );
      }
      return;
    }

    final date = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = 'chart_${sensorType}_$date.csv';

    try {
      final path = await exportCsv(fileName, buffer.toString());
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('График сохранён: $path')),
        );
      } else if (path == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Экспорт доступен только в настольной версии')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

class _CompareDevicesDialog extends StatefulWidget {
  final List<Device> devices;
  final Set<String> selectedIds;

  const _CompareDevicesDialog({
    required this.devices,
    required this.selectedIds,
  });

  @override
  State<_CompareDevicesDialog> createState() => _CompareDevicesDialogState();
}

class _CompareDevicesDialogState extends State<_CompareDevicesDialog> {
  late final Map<String, bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = {
      for (final device in widget.devices)
        device.id: widget.selectedIds.contains(device.id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ChartsProvider>();
    return AlertDialog(
      title: const Text('Сравнить устройства'),
      content: SizedBox(
        width: 360,
        child: widget.devices.isEmpty
            ? const Text('Нет устройств в реестре', style: TextStyle(color: Colors.grey))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.devices.length,
                itemBuilder: (context, index) {
                  final device = widget.devices[index];
                  return CheckboxListTile(
                    value: _checked[device.id] ?? false,
                    title: Text(device.name),
                    subtitle: Text(device.id, style: const TextStyle(fontSize: 12)),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) {
                      setState(() => _checked[device.id] = value ?? false);
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: widget.devices.isEmpty
              ? null
              : () {
                  final selected = widget.devices
                      .where((d) => _checked[d.id] == true)
                      .toList();
                  Navigator.of(context).pop();
                  if (selected.length >= 2) {
                    provider.loadComparison(
                      selected,
                      provider.selectedSensorType,
                      range: provider.timeRange,
                    );
                  }
                },
          child: const Text('Сравнить'),
        ),
      ],
    );
  }
}
