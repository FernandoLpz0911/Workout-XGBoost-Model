import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/widgets/metric_chart.dart';

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
  String? _selectedCategory;
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
    final categories =
        vm.exerciseDict.keys
            .where((c) => exerciseTypeOf(c) == ExerciseType.strength)
            .toList()
          ..sort();

    if (categories.isEmpty) {
      return const _EmptyState(
        title: 'No strength data yet.',
        subtitle:
            'Import your FitNotes CSV or log some sets to see progress charts.',
      );
    }

    if (_selectedCategory == null || !categories.contains(_selectedCategory)) {
      _selectedCategory = categories.first;
    }

    final exercises = vm.exerciseDict[_selectedCategory] ?? const <String>[];
    if (_selectedExercise == null || !exercises.contains(_selectedExercise)) {
      _selectedExercise = exercises.isNotEmpty ? exercises.first : null;
    }

    final data = _selectedExercise == null
        ? const <ChartPoint>[]
        : computeExerciseSeries(
            vm.history,
            _selectedExercise!,
            _metric,
            _daysBack,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Category'),
          initialValue: _selectedCategory,
          items: categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() {
            _selectedCategory = v;
            final exs = vm.exerciseDict[v] ?? const <String>[];
            _selectedExercise = exs.isNotEmpty ? exs.first : null;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedCategory),
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
              ? const NotEnoughChartData()
              : MetricChart(
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
              ? const NotEnoughChartData()
              : MetricChart(
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

  static List<ChartPoint> _computeOverviewData(
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
      return days
          .map((d) => ChartPoint(d.date, _valueFor(metric, d, 1)))
          .toList();
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
        .map((b) => ChartPoint(b.date, _valueFor(metric, b, b.workouts)))
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

/// Accumulates per-day (or per-bucket) totals for the Overview scope.
class _DayAgg {
  final DateTime date;
  double volume = 0;
  double sets = 0;
  double reps = 0;
  double workouts = 0;
  _DayAgg(this.date);
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
