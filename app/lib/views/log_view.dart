import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/rest_timer.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/theme/app_theme.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/widgets/app_card.dart';
import 'package:repiq/views/widgets/day_metadata_dialogs.dart';
import 'package:repiq/views/widgets/note_indicator.dart';
import 'package:repiq/views/widgets/pr_badge.dart';

export 'package:repiq/viewmodels/log_viewmodel.dart' show TrainingMode;
part 'log/log_exercise_page.dart';
part 'log/log_add_exercise.dart';

/// Main log tab. Shows today's exercises as a tappable list.
/// Tap an exercise to open its detail page and log sets.
class LogView extends StatelessWidget {
  const LogView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        if (vm.isDictLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: DayMetaBanner(
                  dateKey: LogViewModel.fmtDate(DateTime.now()),
                ),
              ),
              Expanded(
                child: vm.session.isEmpty
                    ? _EmptySessionView(
                        onAdd: () => _showAddExercise(context, vm),
                        onRepeat: vm.canRepeatLastWorkout
                            ? vm.repeatLastWorkout
                            : null,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: vm.session.length,
                        itemBuilder: (context, i) {
                          final ex = vm.session[i];
                          final setCount = ex.sets.length;
                          final cs = Theme.of(context).colorScheme;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: IconAvatar(
                                icon: _exerciseIcon(
                                  exerciseTypeOf(ex.category),
                                ),
                                color: cs.secondary,
                              ),
                              title: Text(
                                ex.exercise,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Text(
                                setCount == 0
                                    ? ex.category
                                    : '${ex.category}  ·  $setCount ${setCount == 1 ? "set" : "sets"}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                tooltip: 'Remove exercise',
                                onPressed: () => _confirmRemove(context, vm, i),
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _ExerciseDetailPage(exerciseIndex: i),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddExercise(context, vm),
            icon: const Icon(Icons.fitness_center),
            label: const Text('Add Exercise'),
          ),
        );
      },
    );
  }

  static Future<void> _showAddExercise(
    BuildContext context,
    LogViewModel vm,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddExerciseDialog(vm: vm),
    );
  }

  static IconData _exerciseIcon(ExerciseType type) => switch (type) {
    ExerciseType.strength => Icons.fitness_center,
    ExerciseType.cardio => Icons.directions_run,
    ExerciseType.passive => Icons.self_improvement,
  };

  static void _confirmRemove(BuildContext context, LogViewModel vm, int index) {
    final errorColor = Theme.of(context).colorScheme.error;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove exercise?'),
        content: Text(
          'Remove ${vm.session[index].exercise} and all its logged entries?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              vm.removeExercise(index);
            },
            child: Text('Remove', style: TextStyle(color: errorColor)),
          ),
        ],
      ),
    );
  }
}

/// Shown when no exercises have been added for the current day.
class _EmptySessionView extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback? onRepeat;
  const _EmptySessionView({required this.onAdd, this.onRepeat});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateStr,
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          IconAvatar(
            icon: Icons.fitness_center,
            color: Colors.grey,
            radius: 40,
          ),
          const SizedBox(height: 16),
          const Text(
            'No exercises yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the button below to start logging.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add First Exercise'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          if (onRepeat != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRepeat,
              icon: const Icon(Icons.replay),
              label: const Text('Repeat Last Workout'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen logging page for a single exercise.
/// Shows the machine learning recommendation, training mode toggle, weight/reps steppers,
/// and the running list of sets logged so far today.
