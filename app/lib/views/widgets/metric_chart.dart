import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:repiq/services/local_recommendation_engine.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/theme/app_theme.dart';

/// A (date, metric-value) pair mapped to one spot on a [MetricChart].
class ChartPoint {
  final DateTime date;
  final double value;
  const ChartPoint(this.date, this.value);
}

/// Accumulates per-session strength metrics as history sets are iterated.
class _SessionAgg {
  final DateTime date;
  double maxOneRM = 0;
  double maxWeight = 0;
  double totalVolume = 0;
  _SessionAgg(this.date);
}

/// Builds a per-session [ChartPoint] series for one strength exercise —
/// estimated 1RM, max weight, or total volume, whichever [metric] names.
List<ChartPoint> computeExerciseSeries(
  List<WorkoutSet> history,
  String exercise,
  String metric,
  int? daysBack,
) {
  final cutoff = daysBack != null
      ? DateTime.now().subtract(Duration(days: daysBack))
      : null;

  final relevant = history.where(
    (s) =>
        s.exercise == exercise &&
        s.weight > 0 &&
        s.reps > 0 &&
        (cutoff == null || s.date.isAfter(cutoff)),
  );

  final sessions = <String, _SessionAgg>{};
  for (final s in relevant) {
    final key = WorkoutSet.fmtDateStatic(s.date);
    sessions.putIfAbsent(key, () => _SessionAgg(s.date));
    final oneRM = LocalRecommendationEngine.calcOneRM(s.weight, s.reps);
    final vol = s.weight * s.reps;
    sessions[key]!.maxOneRM = max(sessions[key]!.maxOneRM, oneRM);
    sessions[key]!.maxWeight = max(sessions[key]!.maxWeight, s.weight);
    sessions[key]!.totalVolume += vol;
  }

  final sorted = sessions.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  return sorted.map((e) {
    double val;
    switch (metric) {
      case 'Max Weight':
        val = e.value.maxWeight;
      case 'Volume':
        val = e.value.totalVolume;
      default:
        val = e.value.maxOneRM;
    }
    return ChartPoint(e.value.date, val);
  }).toList();
}

/// fl_chart line chart with a dashed linear trend line overlaid on the data.
/// Shared by the Progress tab and the per-exercise detail view.
class MetricChart extends StatelessWidget {
  final List<ChartPoint> data;
  final String Function(double value) axisLabel;
  final String Function(DateTime date) bottomLabel;
  final String Function(DateTime date) tooltipTitle;
  final String Function(double value) tooltipValue;

  const MetricChart({
    super.key,
    required this.data,
    required this.axisLabel,
    required this.bottomLabel,
    required this.tooltipTitle,
    required this.tooltipValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final values = data.map((p) => p.value).toList();
    final trend = _trendSpots(values);
    final allValues = [...values, ...trend.map((s) => s.y)];
    final minY = allValues.reduce(min) * 0.95;
    final rawMaxY = allValues.reduce(max) * 1.05;
    final maxY = rawMaxY > minY ? rawMaxY : minY + 1;
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: palette.chartGridLine, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (val, _) => Text(
                axisLabel(val),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: max(1, (data.length / 4).roundToDouble()),
              getTitlesWidget: (val, _) {
                final i = val.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    bottomLabel(data[i].date),
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => palette.raisedSurface,
            getTooltipItems: (spots) => spots.map((s) {
              if (s.barIndex != 0) return null;
              final i = s.x.toInt();
              final d = data[i].date;
              return LineTooltipItem(
                '${tooltipTitle(d)}\n',
                const TextStyle(color: Colors.grey, fontSize: 11),
                children: [
                  TextSpan(
                    text: tooltipValue(s.y),
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: cs.secondary,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: cs.secondary,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  cs.secondary.withValues(alpha: 0.3),
                  cs.secondary.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          if (trend.length == 2)
            LineChartBarData(
              spots: trend,
              isCurved: false,
              color: cs.primary,
              barWidth: 1.5,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  /// Least-squares linear trend line spanning the first and last x-index.
  static List<FlSpot> _trendSpots(List<double> values) {
    final n = values.length;
    if (n < 2) return const [];
    final xMean = (n - 1) / 2;
    final yMean = values.reduce((a, b) => a + b) / n;
    double num = 0, den = 0;
    for (var i = 0; i < n; i++) {
      num += (i - xMean) * (values[i] - yMean);
      den += (i - xMean) * (i - xMean);
    }
    final slope = num / den;
    final intercept = yMean - slope * xMean;
    return [
      FlSpot(0, intercept),
      FlSpot((n - 1).toDouble(), slope * (n - 1) + intercept),
    ];
  }
}

class NotEnoughChartData extends StatelessWidget {
  const NotEnoughChartData({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Not enough sessions to draw a chart.\nLog at least 2 sessions.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}
