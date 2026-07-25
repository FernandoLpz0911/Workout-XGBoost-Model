import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/day_metadata.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Shows a dialog to add/edit the whole-day comment for [dateKey].
Future<void> showWorkoutCommentDialog(
  BuildContext context,
  LogViewModel vm,
  String dateKey,
) {
  final existing = vm.dayMetadataFor(dateKey);
  return showDialog<void>(
    context: context,
    builder: (_) => _WorkoutCommentDialog(
      initialComment: existing.comment,
      onSave: (comment) => vm.setDayMetadata(
        dateKey,
        DayMetadata(
          comment: comment,
          startTime: existing.startTime,
          endTime: existing.endTime,
        ),
      ),
    ),
  );
}

/// Content of [showWorkoutCommentDialog]. Owns its [TextEditingController]
/// so it's only disposed once the dialog widget itself is unmounted — not
/// immediately after [Navigator.pop], which returns before the dialog's
/// exit animation (and its last rebuild) has finished.
class _WorkoutCommentDialog extends StatefulWidget {
  final String initialComment;
  final ValueChanged<String> onSave;
  const _WorkoutCommentDialog({
    required this.initialComment,
    required this.onSave,
  });

  @override
  State<_WorkoutCommentDialog> createState() => _WorkoutCommentDialogState();
}

class _WorkoutCommentDialogState extends State<_WorkoutCommentDialog> {
  late final _ctrl = TextEditingController(text: widget.initialComment);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Workout Comment'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'Comment text...'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_ctrl.text.trim());
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Shows a dialog to set/edit the start and end time for [dateKey].
Future<void> showWorkoutTimeDialog(
  BuildContext context,
  LogViewModel vm,
  String dateKey,
) async {
  final existing = vm.dayMetadataFor(dateKey);
  TimeOfDay? start = _parseTime(existing.startTime);
  TimeOfDay? end = _parseTime(existing.endTime);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Workout Time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start Time'),
              subtitle: Text(start?.format(dialogContext) ?? 'Not set'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: dialogContext,
                  initialTime: start ?? TimeOfDay.now(),
                );
                if (picked != null) setState(() => start = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('End Time'),
              subtitle: Text(end?.format(dialogContext) ?? 'Not set'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: dialogContext,
                  initialTime: end ?? TimeOfDay.now(),
                );
                if (picked != null) setState(() => end = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              vm.setDayMetadata(
                dateKey,
                DayMetadata(
                  comment: existing.comment,
                  startTime: _formatTime(start),
                  endTime: _formatTime(end),
                ),
              );
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

TimeOfDay? _parseTime(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String? _formatTime(TimeOfDay? t) {
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Small banner showing a day's comment and/or time range, if either is set.
/// Renders nothing otherwise.
class DayMetaBanner extends StatelessWidget {
  final String dateKey;
  const DayMetaBanner({super.key, required this.dateKey});

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        final meta = vm.dayMetadataFor(dateKey);
        if (meta.isEmpty) return const SizedBox.shrink();

        final start = _parseTime(meta.startTime);
        final end = _parseTime(meta.endTime);
        final timeLabel = (start != null || end != null)
            ? '${start?.format(context) ?? '?'} – ${end?.format(context) ?? '?'}'
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (timeLabel != null)
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      timeLabel,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              if (meta.comment.isNotEmpty) ...[
                if (timeLabel != null) const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        meta.comment,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
