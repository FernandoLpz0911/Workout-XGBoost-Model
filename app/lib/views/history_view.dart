import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/exercise_detail_view.dart';
import 'package:repiq/views/log_view.dart';
import 'package:repiq/views/widgets/app_card.dart';
import 'package:repiq/views/widgets/note_indicator.dart';

/// Displays the full workout history grouped by date, then by exercise.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        if (vm.isHistoryLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.history.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconAvatar(icon: Icons.history, color: Colors.grey, radius: 40),
                SizedBox(height: 16),
                Text(
                  'No workout history yet.',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Finish a session or import a FitNotes CSV in Settings.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final byDate = vm.historyByDate;
        final dates = byDate.keys.toList(); // already sorted desc in VM

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: dates.length,
          itemBuilder: (context, i) {
            final date = dates[i];
            final sets = byDate[date]!;
            return _DayCard(date: date, sets: sets);
          },
        );
      },
    );
  }
}

/// Collapsible card showing all exercises and sets logged on a single day.
class _DayCard extends StatelessWidget {
  final String date;
  final List<WorkoutSet> sets;
  const _DayCard({required this.date, required this.sets});

  @override
  Widget build(BuildContext context) {
    final byExercise = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exercise, () => []).add(s);
    }
    final cs = Theme.of(context).colorScheme;
    final dotColors = [cs.primary, cs.secondary, cs.tertiary];
    final categories = sets.map((s) => s.category).toSet().take(3).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Row(
          children: [
            Text(
              date,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            for (var c = 0; c < categories.length; c++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: dotColors[c % dotColors.length],
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${byExercise.length} exercise${byExercise.length == 1 ? '' : 's'}'
          '  ·  ${sets.length} set${sets.length == 1 ? '' : 's'}',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        children: byExercise.entries
            .map((e) => ExerciseHistorySection(exercise: e.key, sets: e.value))
            .toList(),
      ),
    );
  }
}

/// Exercise name with its logged set rows for one day. Shared by the History
/// tab's day cards and [DayDetailView].
class ExerciseHistorySection extends StatelessWidget {
  final String exercise;
  final List<WorkoutSet> sets;
  const ExerciseHistorySection({
    super.key,
    required this.exercise,
    required this.sets,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final unit = context.watch<UnitsController>().unit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExerciseDetailView(
                  exercise: exercise,
                  category: sets.first.category,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    sets.first.category,
                    style: TextStyle(fontSize: 11, color: primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exercise,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...sets.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${s.category == 'Cardio' ? 'Lap' : 'Set'} ${i + 1}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.displayTextIn(unit),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 4),
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
                    onPressed: () =>
                        context.read<LogViewModel>().deleteHistorySet(s),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
