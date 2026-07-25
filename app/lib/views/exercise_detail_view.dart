import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/weight_unit.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/utils/date_format.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/log_view.dart';
import 'package:repiq/views/widgets/metric_chart.dart';
import 'package:repiq/views/widgets/note_indicator.dart';

/// Single-exercise deep dive: every past set (grouped by day) alongside a
/// progress chart, reached by tapping an exercise in the History tab.
class ExerciseDetailView extends StatefulWidget {
  final String exercise;
  final String category;
  const ExerciseDetailView({
    super.key,
    required this.exercise,
    required this.category,
  });

  @override
  State<ExerciseDetailView> createState() => _ExerciseDetailViewState();
}

class _ExerciseDetailViewState extends State<ExerciseDetailView> {
  String _metric = 'Est. 1RM';
  static const _metrics = ['Est. 1RM', 'Max Weight', 'Volume'];

  int? _daysBack; // null = All, matches the Graph tab's default range
  static const _ranges = <String, int?>{
    '1m': 30,
    '3m': 90,
    '6m': 180,
    '1y': 365,
    'All': null,
  };

  @override
  Widget build(BuildContext context) {
    final isStrength = exerciseTypeOf(widget.category) == ExerciseType.strength;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.exercise),
              Text(
                widget.category,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'History'),
              Tab(text: 'Graph'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _HistoryTab(exercise: widget.exercise),
            isStrength ? _buildGraphTab() : const _GraphUnavailable(),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphTab() {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        final unit = context.watch<UnitsController>().unit;
        final rawData = computeExerciseSeries(
          vm.history,
          widget.exercise,
          _metric,
          _daysBack,
        );
        final data = unit == WeightUnit.kg
            ? rawData.map((p) => ChartPoint(p.date, p.value * kgPerLb)).toList()
            : rawData;
        final unitLabel = weightUnitLabel(unit);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Expanded(
                child: data.length < 2
                    ? const NotEnoughChartData()
                    : MetricChart(
                        data: data,
                        axisLabel: (v) => _metric == 'Volume'
                            ? '${(v / 1000).toStringAsFixed(1)}k'
                            : v.toStringAsFixed(0),
                        bottomLabel: (d) => '${monthAbbrev(d.month)} ${d.day}',
                        tooltipTitle: (d) =>
                            '${monthAbbrev(d.month)} ${d.day}, ${d.year}',
                        tooltipValue: (v) => _metric == 'Volume'
                            ? '${v.toStringAsFixed(0)} $unitLabel·reps'
                            : '${v.toStringAsFixed(1)} $unitLabel',
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GraphUnavailable extends StatelessWidget {
  const _GraphUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Graphs are available for strength exercises.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String exercise;
  const _HistoryTab({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<UnitsController>().unit;
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        final sets = vm.history.where((s) => s.exercise == exercise).toList();
        if (sets.isEmpty) {
          return const Center(
            child: Text(
              'No sets logged for this exercise yet.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final byDay = <String, List<WorkoutSet>>{};
        for (final s in sets) {
          byDay.putIfAbsent(WorkoutSet.fmtDateStatic(s.date), () => []).add(s);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: days.length,
          itemBuilder: (context, i) {
            final day = days[i];
            final daySets = byDay[day]!
              ..sort((a, b) => a.date.compareTo(b.date));
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...daySets.asMap().entries.map((entry) {
                      final n = entry.key + 1;
                      final s = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${s.category == 'Cardio' ? 'Lap' : 'Set'} $n',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              s.displayTextIn(unit),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            NoteIndicator(comment: s.comment),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: Colors.grey,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Edit',
                              onPressed: () => showEditSetDialog(
                                context,
                                existingSet: s,
                                onSave: (updated) => context
                                    .read<LogViewModel>()
                                    .updateHistorySet(s, updated),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.grey,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete',
                              onPressed: () => context
                                  .read<LogViewModel>()
                                  .deleteHistorySet(s),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
