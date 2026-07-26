import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/day_detail_view.dart';
import 'package:repiq/views/history_view.dart';

/// Month calendar with a dot per logged workout day. Tapping a day previews
/// what was logged, with a "Go To" action that opens the full [DayDetailView].
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  static const _weekdayLabels = [
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        final byDate = vm.historyByDate;
        final cs = Theme.of(context).colorScheme;
        final dotColors = [cs.primary, cs.secondary, cs.tertiary];

        final first = DateTime(_month.year, _month.month, 1);
        final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
        final leadingBlanks = first.weekday % 7; // Sunday-first grid
        final today = DateTime.now();

        return Scaffold(
          appBar: AppBar(
            title: Text('${_monthNames[_month.month - 1]} ${_month.year}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: Card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                          child: Row(
                            children: _weekdayLabels
                                .map(
                                  (w) => Expanded(
                                    child: Center(
                                      child: Text(
                                        w,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                ),
                            itemCount: leadingBlanks + daysInMonth,
                            itemBuilder: (context, i) {
                              if (i < leadingBlanks) {
                                return const SizedBox.shrink();
                              }
                              final day = i - leadingBlanks + 1;
                              final date = DateTime(
                                _month.year,
                                _month.month,
                                day,
                              );
                              final key = WorkoutSet.fmtDateStatic(date);
                              final sets = byDate[key];
                              final isToday =
                                  date.year == today.year &&
                                  date.month == today.month &&
                                  date.day == today.day;
                              final categories = sets == null
                                  ? const <String>[]
                                  : sets
                                        .map((s) => s.category)
                                        .toSet()
                                        .take(3)
                                        .toList();

                              return InkWell(
                                onTap: sets == null
                                    ? null
                                    : () => _showPreview(context, key, sets),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      decoration: isToday
                                          ? BoxDecoration(
                                              color: cs.primary,
                                              shape: BoxShape.circle,
                                            )
                                          : null,
                                      child: Text(
                                        '$day',
                                        style: TextStyle(
                                          color: isToday ? Colors.white : null,
                                          fontWeight: isToday
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    SizedBox(
                                      height: 6,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          for (
                                            var c = 0;
                                            c < categories.length;
                                            c++
                                          )
                                            Container(
                                              width: 5,
                                              height: 5,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    dotColors[c %
                                                        dotColors.length],
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${byDate.length} workout day${byDate.length == 1 ? '' : 's'} total',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPreview(
    BuildContext context,
    String dateLabel,
    List<WorkoutSet> sets,
  ) {
    final byExercise = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exercise, () => []).add(s);
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dateLabel),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: byExercise.entries
                  .map(
                    (e) =>
                        ExerciseHistorySection(exercise: e.key, sets: e.value),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DayDetailView(dateLabel: dateLabel),
                ),
              );
            },
            child: const Text('Go To'),
          ),
        ],
      ),
    );
  }
}
