import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Trophy shown next to a set that was a personal record when logged.
class PrBadge extends StatelessWidget {
  final WorkoutSet set;
  const PrBadge({super.key, required this.set});

  @override
  Widget build(BuildContext context) {
    final isPr = context.select<LogViewModel, bool>(
      (vm) => vm.prSetDates.contains(set.date),
    );
    if (!isPr) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'Personal record',
        child: Icon(Icons.emoji_events, size: 16, color: Colors.amber),
      ),
    );
  }
}
