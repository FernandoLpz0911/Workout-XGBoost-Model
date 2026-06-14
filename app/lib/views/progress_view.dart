import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/services/local_recommendation_engine.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Progress charts for strength exercises — estimated 1RM, max weight, or
/// total volume over a selectable time range.
class ProgressView extends StatefulWidget {
  const ProgressView({super.key});

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  String? _selectedExercise;
  String _metric = 'Est. 1RM';
  int? _daysBack = 90;

  static const _metrics = ['Est. 1RM', 'Max Weight', 'Volume'];
  static const _ranges = <String, int?>{
    '1m': 30,
    '3m': 90,
    '6m': 180,
    '1y': 365,
    'All': null,
  };

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        final exercises =
            vm.exerciseDict.entries
                .where((e) => exerciseTypeOf(e.key) == ExerciseType.strength)
                .expand((e) => e.value)
                .toList()
              ..sort();

        if (exercises.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No strength data yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Import your FitNotes CSV or log some sets to see progress charts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        _selectedExercise ??= exercises.first;

        final data = _computeData(
          vm.history,
          _selectedExercise!,
          _metric,
          _daysBack,
        );

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Exercise'),
                initialValue: _selectedExercise,
                items: exercises
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedExercise = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: _metrics.map((m) {
                  final selected = m == _metric;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(m),
                      selected: selected,
                      onSelected: (_) => setState(() => _metric = m),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: _ranges.entries.map((e) {
                  final selected = e.value == _daysBack;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e.key),
                      selected: selected,
                      onSelected: (_) => setState(() => _daysBack = e.value),
                      labelStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              if (data.length < 2)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Not enough sessions to draw a chart.\nLog at least 2 sessions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _Chart(data: data, metric: _metric),
                ),
            ],
          ),
        );
      },
    );
  }

  static List<_Point> _computeData(
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
      return _Point(e.value.date, val);
    }).toList();
  }
}

/// Accumulates per-session metrics as history sets are iterated.
class _SessionAgg {
  final DateTime date;
  double maxOneRM = 0;
  double maxWeight = 0;
  double totalVolume = 0;
  _SessionAgg(this.date);
}

/// A (date, metric-value) pair mapped to one spot on the line chart.
class _Point {
  final DateTime date;
  final double value;
  const _Point(this.date, this.value);
}

/// fl_chart line chart for the selected exercise metric over the chosen date range.
class _Chart extends StatelessWidget {
  final List<_Point> data;
  final String metric;
  const _Chart({required this.data, required this.metric});

  @override
  Widget build(BuildContext context) {
    final minY = data.map((p) => p.value).reduce(min) * 0.95;
    final maxY = data.map((p) => p.value).reduce(max) * 1.05;
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
              FlLine(color: Colors.white12, strokeWidth: 1),
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
                metric == 'Volume'
                    ? '${(val / 1000).toStringAsFixed(1)}k'
                    : val.toStringAsFixed(0),
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
                final d = data[i].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_mon(d.month)} ${d.day}',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1C1C26),
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              final d = data[i].date;
              return LineTooltipItem(
                '${_mon(d.month)} ${d.day}, ${d.year}\n',
                const TextStyle(color: Colors.grey, fontSize: 11),
                children: [
                  TextSpan(
                    text: metric == 'Volume'
                        ? '${s.y.toStringAsFixed(0)} lbs·reps'
                        : '${s.y.toStringAsFixed(1)} lbs',
                    style: const TextStyle(
                      color: Colors.white,
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
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.blueAccent,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: Colors.blueAccent,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withValues(alpha: 0.3),
                  Colors.blueAccent.withValues(alpha: 0.0),
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

  static String _mon(int m) => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];
}
