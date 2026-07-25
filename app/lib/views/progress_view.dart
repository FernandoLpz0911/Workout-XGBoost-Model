import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/services/local_recommendation_engine.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/theme/app_theme.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Progress charts. Two scopes:
/// - **Exercise**: estimated 1RM, max weight, or volume for one exercise.
/// - **Overview**: volume, sets, reps, or workout count aggregated per
///   workout/week/month/year across the whole log.
/// Both draw a linear trend line alongside the data.
class ProgressView extends StatefulWidget {
  const ProgressView({super.key});

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

enum _Scope { exercise, overview }

enum _Period { workout, week, month, year }

enum _OverviewMetric { workouts, volume, sets, reps }

const _periodLabel = {
  _Period.workout: 'Workout',
  _Period.week: 'Week',
  _Period.month: 'Month',
  _Period.year: 'Year',
};

const _metricLabel = {
  _OverviewMetric.workouts: 'Workouts',
  _OverviewMetric.volume: 'Volume',
  _OverviewMetric.sets: 'Sets',
  _OverviewMetric.reps: 'Reps',
};

class _ProgressViewState extends State<ProgressView> {
  _Scope _scope = _Scope.exercise;

  // Exercise scope
  String? _selectedExercise;
  String _metric = 'Est. 1RM';
  static const _metrics = ['Est. 1RM', 'Max Weight', 'Volume'];

  // Overview scope
  _Period _period = _Period.workout;
  _OverviewMetric _overviewMetric = _OverviewMetric.volume;

  // Shared time range
  int? _daysBack = 90;
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
        if (vm.history.isEmpty) {
          return const _EmptyState(
            title: 'No workout data yet.',
            subtitle:
                'Import your FitNotes CSV or log some sets to see progress charts.',
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<_Scope>(
                segments: const [
                  ButtonSegment(
                    value: _Scope.exercise,
                    label: Text('Exercise'),
                    icon: Icon(Icons.fitness_center, size: 16),
                  ),
                  ButtonSegment(
                    value: _Scope.overview,
                    label: Text('Overview'),
                    icon: Icon(Icons.bar_chart, size: 16),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _scope == _Scope.exercise
                    ? _buildExercise(vm)
                    : _buildOverview(vm),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExercise(LogViewModel vm) {
    final exercises =
        vm.exerciseDict.entries
            .where((e) => exerciseTypeOf(e.key) == ExerciseType.strength)
            .expand((e) => e.value)
            .toList()
          ..sort();

    if (exercises.isEmpty) {
      return const _EmptyState(
        title: 'No strength data yet.',
        subtitle:
            'Import your FitNotes CSV or log some sets to see progress charts.',
      );
    }

    if (_selectedExercise == null || !exercises.contains(_selectedExercise)) {
      _selectedExercise = exercises.first;
    }

    final data = _computeExerciseData(
      vm.history,
      _selectedExercise!,
      _metric,
      _daysBack,
    );

    return Column(
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
        _rangeRow(),
        const SizedBox(height: 20),
        Expanded(
          child: data.length < 2
              ? const _NotEnoughData()
              : _Chart(
                  data: data,
                  axisLabel: (v) => _metric == 'Volume'
                      ? '${(v / 1000).toStringAsFixed(1)}k'
                      : v.toStringAsFixed(0),
                  bottomLabel: (d) => '${_mon(d.month)} ${d.day}',
                  tooltipTitle: (d) => '${_mon(d.month)} ${d.day}, ${d.year}',
                  tooltipValue: (v) => _metric == 'Volume'
                      ? '${v.toStringAsFixed(0)} lbs·reps'
                      : '${v.toStringAsFixed(1)} lbs',
                ),
        ),
      ],
    );
  }

  Widget _buildOverview(LogViewModel vm) {
    final availableMetrics = _period == _Period.workout
        ? const [
            _OverviewMetric.volume,
            _OverviewMetric.sets,
            _OverviewMetric.reps,
          ]
        : _OverviewMetric.values;
    if (!availableMetrics.contains(_overviewMetric)) {
      _overviewMetric = _OverviewMetric.volume;
    }

    final data = _computeOverviewData(
      vm.history,
      _period,
      _overviewMetric,
      _daysBack,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: _Period.values.map((p) {
            final selected = p == _period;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_periodLabel[p]!),
                selected: selected,
                onSelected: (_) => setState(() => _period = p),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: availableMetrics.map((m) {
            final selected = m == _overviewMetric;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_metricLabel[m]!),
                selected: selected,
                onSelected: (_) => setState(() => _overviewMetric = m),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _rangeRow(),
        const SizedBox(height: 20),
        Expanded(
          child: data.length < 2
              ? const _NotEnoughData()
              : _Chart(
                  data: data,
                  axisLabel: (v) => _overviewMetric == _OverviewMetric.volume
                      ? '${(v / 1000).toStringAsFixed(1)}k'
                      : v.toStringAsFixed(0),
                  bottomLabel: (d) => _period == _Period.year
                      ? '${d.year}'
                      : _period == _Period.month
                      ? '${_mon(d.month)} ${d.year}'
                      : '${_mon(d.month)} ${d.day}',
                  tooltipTitle: (d) => _period == _Period.year
                      ? '${d.year}'
                      : _period == _Period.month
                      ? '${_mon(d.month)} ${d.year}'
                      : '${_mon(d.month)} ${d.day}, ${d.year}',
                  tooltipValue: (v) => switch (_overviewMetric) {
                    _OverviewMetric.volume =>
                      '${v.toStringAsFixed(0)} lbs·reps',
                    _OverviewMetric.sets => '${v.toStringAsFixed(0)} sets',
                    _OverviewMetric.reps => '${v.toStringAsFixed(0)} reps',
                    _OverviewMetric.workouts =>
                      '${v.toStringAsFixed(0)} workout${v == 1 ? '' : 's'}',
                  },
                ),
        ),
      ],
    );
  }

  Widget _rangeRow() {
    return Row(
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
    );
  }

  static List<_Point> _computeExerciseData(
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

  static List<_Point> _computeOverviewData(
    List<WorkoutSet> history,
    _Period period,
    _OverviewMetric metric,
    int? daysBack,
  ) {
    final cutoff = daysBack != null
        ? DateTime.now().subtract(Duration(days: daysBack))
        : null;

    final perDay = <String, _DayAgg>{};
    for (final s in history) {
      if (cutoff != null && !s.date.isAfter(cutoff)) continue;
      final day = DateTime(s.date.year, s.date.month, s.date.day);
      final key = WorkoutSet.fmtDateStatic(day);
      final agg = perDay.putIfAbsent(key, () => _DayAgg(day));
      agg.sets += 1;
      agg.reps += s.reps;
      agg.volume += s.weight * s.reps;
    }

    if (period == _Period.workout) {
      final days = perDay.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      return days.map((d) => _Point(d.date, _valueFor(metric, d, 1))).toList();
    }

    final buckets = <String, _DayAgg>{};
    for (final d in perDay.values) {
      final DateTime bucketDate;
      switch (period) {
        case _Period.week:
          bucketDate = d.date.subtract(Duration(days: d.date.weekday - 1));
        case _Period.month:
          bucketDate = DateTime(d.date.year, d.date.month, 1);
        case _Period.year:
          bucketDate = DateTime(d.date.year, 1, 1);
        case _Period.workout:
          bucketDate = d.date; // unreachable
      }
      final key = WorkoutSet.fmtDateStatic(bucketDate);
      final b = buckets.putIfAbsent(key, () => _DayAgg(bucketDate));
      b.sets += d.sets;
      b.reps += d.reps;
      b.volume += d.volume;
      b.workouts += 1;
    }

    final sorted = buckets.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return sorted
        .map((b) => _Point(b.date, _valueFor(metric, b, b.workouts)))
        .toList();
  }

  static double _valueFor(
    _OverviewMetric metric,
    _DayAgg agg,
    double workouts,
  ) {
    switch (metric) {
      case _OverviewMetric.volume:
        return agg.volume;
      case _OverviewMetric.sets:
        return agg.sets;
      case _OverviewMetric.reps:
        return agg.reps;
      case _OverviewMetric.workouts:
        return workouts;
    }
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

/// Accumulates per-session metrics as history sets are iterated.
class _SessionAgg {
  final DateTime date;
  double maxOneRM = 0;
  double maxWeight = 0;
  double totalVolume = 0;
  _SessionAgg(this.date);
}

/// Accumulates per-day (or per-bucket) totals for the Overview scope.
class _DayAgg {
  final DateTime date;
  double volume = 0;
  double sets = 0;
  double reps = 0;
  double workouts = 0;
  _DayAgg(this.date);
}

/// A (date, metric-value) pair mapped to one spot on the line chart.
class _Point {
  final DateTime date;
  final double value;
  const _Point(this.date, this.value);
}

/// Centered icon + title + subtitle message, used for all "nothing to show
/// yet" states across both scopes.
class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.show_chart, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData();

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

/// fl_chart line chart with a dashed linear trend line overlaid on the data.
class _Chart extends StatelessWidget {
  final List<_Point> data;
  final String Function(double value) axisLabel;
  final String Function(DateTime date) bottomLabel;
  final String Function(DateTime date) tooltipTitle;
  final String Function(double value) tooltipValue;

  const _Chart({
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
            isCurved: true,
            curveSmoothness: 0.3,
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
