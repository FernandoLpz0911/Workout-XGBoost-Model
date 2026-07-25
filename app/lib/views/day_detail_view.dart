import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/history_view.dart';
import 'package:repiq/views/widgets/day_metadata_dialogs.dart';

/// Full-screen view of everything logged on one day, reached by "Go To"
/// from [CalendarView]'s day preview.
class DayDetailView extends StatelessWidget {
  final String dateLabel;
  const DayDetailView({super.key, required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(dateLabel),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              final vm = context.read<LogViewModel>();
              if (value == 'comment') {
                showWorkoutCommentDialog(context, vm, dateLabel);
              } else if (value == 'time') {
                showWorkoutTimeDialog(context, vm, dateLabel);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'comment', child: Text('Workout Comment')),
              PopupMenuItem(value: 'time', child: Text('Workout Time')),
            ],
          ),
        ],
      ),
      body: Consumer<LogViewModel>(
        builder: (context, vm, _) {
          final sets = vm.historyByDate[dateLabel] ?? const <WorkoutSet>[];
          if (sets.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DayMetaBanner(dateKey: dateLabel),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Nothing logged on this day.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final byExercise = <String, List<WorkoutSet>>{};
          for (final s in sets) {
            byExercise.putIfAbsent(s.exercise, () => []).add(s);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DayMetaBanner(dateKey: dateLabel),
              Text(
                '${byExercise.length} exercise${byExercise.length == 1 ? '' : 's'}'
                '  ·  ${sets.length} set${sets.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...byExercise.entries.map(
                (e) => ExerciseHistorySection(exercise: e.key, sets: e.value),
              ),
            ],
          );
        },
      ),
    );
  }
}
