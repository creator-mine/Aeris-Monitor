import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import 'providers/charts_provider.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/error_widget.dart';
import '../../shared/widgets/ui_kit.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/config/app_config.dart';
import '../../core/config/pressure_unit.dart';
import '../../core/utils/csv_exporter.dart';
import '../devices/providers/devices_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../../models/sensor_data.dart';
import '../../models/device.dart';

import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

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
          tooltip: L10n.of(context, 'Сравнить устройства'),
          icon: const Icon(Icons.compare_arrows),
          onPressed: () => _openCompareDialog(context),
        ),
        IconButton(
          tooltip: L10n.of(context, 'Экспорт CSV'),
          icon: const Icon(Icons.save_alt),
          onPressed: () => _exportCsv(context),
        ),
      ],
      body: Consumer<ChartsProvider>(
        builder: (context, provider, child) {
          final pressureUnit = context.select<SettingsProvider, PressureUnit>(
            (settings) => settings.pressureUnit,
          );
          return Column(
            children: [
              if (provider.isComparing) _buildCompareBanner(context, provider),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: AppSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDeviceSelector(context, provider),
                      const SizedBox(height: 12),
                      _buildSensorTypeSelector(context, provider),
                      const SizedBox(height: 10),
                      _buildTimeRangeSelector(context, provider),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _buildChartArea(context, provider, pressureUnit),
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
            child: TrText(
              'Сравнение: $names',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: L10n.of(context, 'Остановить сравнение'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => provider.clearComparison(),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector(BuildContext context, ChartsProvider provider) {
    final dashboard = context.watch<DashboardProvider>();
    final devices = dashboard.devices;
    if (devices.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final ids = devices.map((device) => device.id).toSet();
    var selectedId = provider.selectedDeviceId;
    if (selectedId != null && !ids.contains(selectedId)) selectedId = null;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: palette.border),
          ),
          child: Icon(Icons.devices_other, size: 19, color: palette.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrText(
                'Устройство',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.muted,
                    ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedId,
                  isExpanded: true,
                  isDense: true,
                  padding: EdgeInsets.zero,
                  hint: const TrText('Выберите устройство'),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  icon: Icon(Icons.keyboard_arrow_down_rounded,
                      color: palette.muted),
                  items: devices.map((device) {
                    return DropdownMenuItem<String>(
                      value: device.id,
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: device.isOnline
                                  ? palette.success
                                  : palette.faint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TrText(
                              device.isOnline
                                  ? device.name
                                  : '${device.name} — офлайн',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (id) async {
                    if (id == null) return;
                    final device = devices.firstWhere((d) => d.id == id);
                    // Update charts first so the screen reacts immediately; the
                    // dashboard selection below keeps both screens in sync.
                    provider.setSelectedDevice(
                      device.id,
                      metrics: device.allMetrics,
                      device: device,
                    );
                    await dashboard.selectDevice(device);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSensorTypeSelector(
    BuildContext context,
    ChartsProvider provider,
  ) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: provider.availableSensorTypes.length,
        itemBuilder: (context, index) {
          final sensorType = provider.availableSensorTypes[index];
          final isSelected = provider.selectedSensorType == sensorType;
          final color = isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : palette.muted;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppConfig.metricIcon(sensorType),
                      size: 15, color: color),
                  const SizedBox(width: 6),
                  TrText(
                    provider.getSensorName(sensorType),
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              onSelected: (_) {
                provider.setSelectedSensorType(sensorType);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeRangeSelector(
    BuildContext context,
    ChartsProvider provider,
  ) {
    final palette = AppPalette.of(context);
    const ranges = [
      ('1ч', Duration(hours: 1)),
      ('6ч', Duration(hours: 6)),
      ('24ч', Duration(hours: 24)),
      ('7д', Duration(days: 7)),
      ('30д', Duration(days: 30)),
    ];

    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: palette.muted),
          const SizedBox(width: 10),
          Expanded(
            // Horizontal scroll like the sensor chips: the periods stay on a
            // single row instead of wrapping onto a second one, leaving more
            // vertical room for the chart itself.
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: ranges.length,
              itemBuilder: (context, index) {
                final (label, duration) = ranges[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildTimeRangeChip(
                    context,
                    provider,
                    label,
                    duration,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeChip(
    BuildContext context,
    ChartsProvider provider,
    String label,
    Duration duration,
  ) {
    final isSelected =
        provider.timeRange.end.difference(provider.timeRange.start) == duration;
    return ChoiceChip(
      label: TrText(label),
      selected: isSelected,
      onSelected: (_) {
        provider.setTimeRange(
          DateTimeRange(
            start: DateTime.now().subtract(duration),
            end: DateTime.now(),
          ),
        );
      },
    );
  }

  /// Pressure is stored in hPa; convert only for rendering. Other metrics
  /// keep the unit reported by the device.
  bool _convertsPressure(ChartsProvider provider) {
    return provider.selectedSensorType == 'pressure' &&
        provider.getSensorUnit('pressure').toLowerCase() == 'hpa';
  }

  double _displayValue(
    ChartsProvider provider,
    PressureUnit unit,
    double value,
  ) {
    return _convertsPressure(provider) ? unit.fromHpa(value) : value;
  }

  String _displayUnit(
    BuildContext context,
    ChartsProvider provider,
    PressureUnit unit,
  ) {
    if (_convertsPressure(provider)) return L10n.of(context, unit.label);
    return provider.getSensorUnit(provider.selectedSensorType);
  }

  int _displayDecimals(ChartsProvider provider, PressureUnit unit) {
    return _convertsPressure(provider) ? unit.decimals : 1;
  }

  int _axisDecimals(ChartsProvider provider, PressureUnit unit) {
    return _convertsPressure(provider) ? unit.axisDecimals : 1;
  }

  String _formatAxisTime(double milliseconds, Duration span) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds.round());
    String two(int v) => v.toString().padLeft(2, '0');
    if (span.inHours < 24) {
      return '${two(value.hour)}:${two(value.minute)}';
    }
    return '${two(value.day)}.${two(value.month)}';
  }

  int _decimalsForStep(double step) {
    if (step >= 1) return 0;
    if (step >= 0.1) return 1;
    return 2;
  }

  /// Rounds the Y axis to human-friendly steps (0.1/0.2/0.5/1/2/5…), so tick
  /// labels do not repeat and the grid does not jump when one new point lands.
  ({double min, double max, double step}) _niceAxis(double min, double max) {
    final range = max - min;
    if (!range.isFinite || range <= 0) {
      return (min: min - 0.5, max: max + 0.5, step: 0.2);
    }
    final rough = range / 5;
    final magnitude =
        math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final normalized = rough / magnitude;
    final niceNormalized = normalized <= 1
        ? 1.0
        : normalized <= 2
            ? 2.0
            : normalized <= 5
                ? 5.0
                : 10.0;
    final step = niceNormalized * magnitude;
    final niceMin = (min / step).floor() * step;
    var niceMax = (max / step).ceil() * step;
    if (niceMax <= niceMin) niceMax = niceMin + step;
    return (min: niceMin, max: niceMax, step: step);
  }

  Widget _buildChartArea(
    BuildContext context,
    ChartsProvider provider,
    PressureUnit pressureUnit,
  ) {
    if (provider.isLoading || provider.isLoadingComparison) {
      return const LoadingIndicator(message: 'Загрузка данных...');
    }

    if (!provider.isSelectedMetricSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sensors_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const TrText(
                'Датчик не подключён',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TrText(
                'Устройство не сообщает параметр «${provider.getSensorName(provider.selectedSensorType)}».',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
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
          child: TrText(
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
              child: _buildCompareChart(context, provider, pressureUnit),
            ),
          ],
        ),
      );
    }

    final series = provider.currentSeries;
    if (series == null || series.points.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              TrText(
                'Нет данных для отображения',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              TrText(
                'За выбранный период на SD-карте нет точек. '
                'Проверьте карту памяти и подключение к устройству.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(context, provider, series, pressureUnit),
          if (series.partial) ...[
            const SizedBox(height: 12),
            _buildCoverageNotice(context, series),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: AppSurface(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChartHeader(context, provider, series, pressureUnit),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _buildLineChart(
                      context,
                      provider,
                      series,
                      pressureUnit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageNotice(
    BuildContext context,
    SensorDataSeries series,
  ) {
    final palette = AppPalette.of(context);
    String two(int v) => v.toString().padLeft(2, '0');
    final since = series.coveredSince?.toLocal();
    final label = since == null
        ? 'На устройстве нет данных за весь выбранный период.'
        : 'Данные на карте начинаются с '
            '${two(since.day)}.${two(since.month)} '
            '${two(since.hour)}:${two(since.minute)} — '
            'более старые точки уже удалены.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TrText(
              label,
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartHeader(
    BuildContext context,
    ChartsProvider provider,
    SensorDataSeries series,
    PressureUnit pressureUnit,
  ) {
    final palette = AppPalette.of(context);
    final unit = _displayUnit(context, provider, pressureUnit);
    final decimals = _displayDecimals(provider, pressureUnit);
    final last = series.points.isEmpty ? null : series.points.last.value;
    final value = last == null
        ? '—'
        : '${_displayValue(provider, pressureUnit, last).toStringAsFixed(decimals)} $unit';

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: palette.primary.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            AppConfig.metricIcon(provider.selectedSensorType),
            color: palette.primary,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrText(
                provider.getSensorName(provider.selectedSensorType),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              TrText(
                '${series.points.length} точек · история с SD-карты',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.muted,
                    ),
              ),
            ],
          ),
        ),
        TrText(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    ChartsProvider provider,
    SensorDataSeries series,
    PressureUnit pressureUnit,
  ) {
    final unit = _displayUnit(context, provider, pressureUnit);
    final decimals = _displayDecimals(provider, pressureUnit);
    String format(double value) =>
        '${_displayValue(provider, pressureUnit, value).toStringAsFixed(decimals)} $unit';

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            'Минимум',
            format(series.minValue),
            AppTheme.infoColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            context,
            'Среднее',
            format(series.avgValue),
            AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            context,
            'Максимум',
            format(series.maxValue),
            AppTheme.warningColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: palette.muted),
                ),
                const SizedBox(height: 2),
                // The three cards share the row width, so scale a long value
                // down instead of letting it overflow on narrow phones.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: TrText(
                    value,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// History is expected chronological, but a clock sync or MQTT chunk
  /// reassembly can leave it slightly out of order. A single out-of-order
  /// point makes the line fold back over itself, so sort defensively.
  List<SensorDataPoint> _sortedPoints(List<SensorDataPoint> points) {
    if (points.length < 2) return points;
    final sorted = List<SensorDataPoint>.of(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return sorted;
  }

  Widget _buildLineChart(
    BuildContext context,
    ChartsProvider provider,
    SensorDataSeries series,
    PressureUnit pressureUnit,
  ) {
    final points = _sortedPoints(series.points);
    final displayMin = _displayValue(provider, pressureUnit, series.minValue);
    final displayMax = _displayValue(provider, pressureUnit, series.maxValue);
    final firstTs = points.isEmpty
        ? 0.0
        : points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final lastTs = points.isEmpty
        ? 0.0
        : points.last.timestamp.millisecondsSinceEpoch.toDouble();
    final spanMs = lastTs - firstTs;
    final safeSpan = spanMs > 0 ? spanMs : 1.0;
    final xInterval = safeSpan / 5;
    final span = Duration(milliseconds: safeSpan.round());
    final unit = _displayUnit(context, provider, pressureUnit);
    final axisDecimals = _axisDecimals(provider, pressureUnit);
    final axis = _niceAxis(displayMin, displayMax);
    final labelDecimals = _convertsPressure(provider)
        ? math.max(axisDecimals, _decimalsForStep(axis.step))
        : _decimalsForStep(axis.step);
    final palette = AppPalette.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: axis.step,
          verticalInterval: xInterval,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: palette.border.withValues(alpha: 0.7),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: palette.border.withValues(alpha: 0.35),
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
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                if (value < firstTs || value > lastTs) {
                  return const TrText('');
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TrText(
                    _formatAxisTime(value, span),
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: axis.step,
              getTitlesWidget: (value, meta) {
                return TrText(
                  value.toStringAsFixed(labelDecimals),
                  style: TextStyle(fontSize: 11, color: palette.muted),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: palette.border),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: _tooltipItems(unit, labelDecimals),
          ),
        ),
        minX: firstTs,
        maxX: lastTs > firstTs ? lastTs : firstTs + 1,
        minY: axis.min,
        maxY: axis.max,
        lineBarsData: [
          LineChartBarData(
            spots: points.map<FlSpot>((point) {
              return FlSpot(
                point.timestamp.millisecondsSinceEpoch.toDouble(),
                _displayValue(provider, pressureUnit, point.value),
              );
            }).toList(),
            // Straight segments: with irregular sampling gaps the smooth
            // Catmull-Rom approximation overshoots horizontally and the line
            // visually loops back on itself.
            isCurved: false,
            gradient: LinearGradient(
              colors: [
                primary.withValues(alpha: 0.55),
                primary,
              ],
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 80,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 2.2,
                  color: primary,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.28),
                  primary.withValues(alpha: 0.0),
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

  List<LineTooltipItem> Function(List<LineBarSpot>) _tooltipItems(
    String unit,
    int decimals,
  ) {
    return (touchedSpots) {
      return touchedSpots.map((spot) {
        return LineTooltipItem(
          '${spot.y.toStringAsFixed(decimals)} $unit',
          const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        );
      }).toList();
    };
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
              TrText(
                provider.compareNames[entries[i].key] ?? entries[i].key,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCompareChart(
    BuildContext context,
    ChartsProvider provider,
    PressureUnit pressureUnit,
  ) {
    final entries = provider.compareSeries.entries.toList();
    var minValue = 0.0;
    var maxValue = 1.0;
    var minTs = double.infinity;
    var maxTs = double.negativeInfinity;
    for (final entry in entries) {
      final series = entry.value;
      if (series.points.isEmpty) continue;
      final points = _sortedPoints(series.points);
      final firstTs = points.first.timestamp.millisecondsSinceEpoch.toDouble();
      final lastTs = points.last.timestamp.millisecondsSinceEpoch.toDouble();
      if (firstTs < minTs) minTs = firstTs;
      if (lastTs > maxTs) maxTs = lastTs;
      final seriesMin = _displayValue(provider, pressureUnit, series.minValue);
      final seriesMax = _displayValue(provider, pressureUnit, series.maxValue);
      minValue = minValue == 0
          ? seriesMin
          : minValue <= seriesMin
              ? minValue
              : seriesMin;
      maxValue = maxValue == 1
          ? seriesMax
          : maxValue >= seriesMax
              ? maxValue
              : seriesMax;
    }
    if (!minTs.isFinite) minTs = 0;
    if (!maxTs.isFinite) maxTs = 1;
    final spanMs = maxTs - minTs;
    final safeSpan = spanMs > 0 ? spanMs : 1.0;
    final xInterval = safeSpan / 5;
    final span = Duration(milliseconds: safeSpan.round());
    final unit = _displayUnit(context, provider, pressureUnit);
    final axisDecimals = _axisDecimals(provider, pressureUnit);
    final axis = _niceAxis(minValue, maxValue);
    final labelDecimals = _convertsPressure(provider)
        ? math.max(axisDecimals, _decimalsForStep(axis.step))
        : _decimalsForStep(axis.step);
    final palette = AppPalette.of(context);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: axis.step,
          verticalInterval: xInterval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: palette.border.withValues(alpha: 0.7),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: palette.border.withValues(alpha: 0.35),
            strokeWidth: 1,
          ),
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
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                if (value < minTs || value > maxTs) {
                  return const TrText('');
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TrText(
                    _formatAxisTime(value, span),
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: axis.step,
              getTitlesWidget: (value, meta) => TrText(
                value.toStringAsFixed(labelDecimals),
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: palette.border),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: _tooltipItems(unit, labelDecimals),
          ),
        ),
        minX: minTs,
        maxX: maxTs > minTs ? maxTs : minTs + 1,
        minY: axis.min,
        maxY: axis.max,
        lineBarsData: [
          for (var i = 0; i < entries.length; i++)
            LineChartBarData(
              spots: _sortedPoints(entries[i].value.points)
                  .map(
                    (point) => FlSpot(
                      point.timestamp.millisecondsSinceEpoch.toDouble(),
                      _displayValue(provider, pressureUnit, point.value),
                    ),
                  )
                  .toList(),
              isCurved: false,
              color: _comparePalette[i % _comparePalette.length],
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  Future<void> _openCompareDialog(BuildContext context) async {
    final devicesProvider = context.read<DevicesProvider>();
    if (devicesProvider.devices.isEmpty) {
      await devicesProvider.loadDevices();
    }
    if (!context.mounted) return;
    final devices = devicesProvider.devices.toList();

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
          const SnackBar(content: TrText('Нет данных для экспорта')),
        );
      }
      return;
    }

    final date =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = 'chart_${sensorType}_$date.csv';

    try {
      final path = await exportCsv(fileName, buffer.toString());
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: TrText('График сохранён: $path')));
      } else if (path == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TrText('Экспорт доступен только в настольной версии'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: TrText('Ошибка экспорта: $e')));
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
      title: const TrText('Сравнить устройства'),
      content: SizedBox(
        width: 360,
        child: widget.devices.isEmpty
            ? const TrText(
                'Нет устройств в реестре',
                style: TextStyle(color: Colors.grey),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.devices.length,
                itemBuilder: (context, index) {
                  final device = widget.devices[index];
                  return CheckboxListTile(
                    value: _checked[device.id] ?? false,
                    title: TrText(device.name),
                    subtitle: TrText(
                      device.id,
                      style: const TextStyle(fontSize: 12),
                    ),
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
          child: const TrText('Отмена'),
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
          child: const TrText('Сравнить'),
        ),
      ],
    );
  }
}
