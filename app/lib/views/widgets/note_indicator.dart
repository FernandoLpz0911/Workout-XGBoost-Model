import 'package:flutter/material.dart';

/// Small tappable comment-bubble icon shown next to a logged set that has a
/// note. Tapping it opens a dialog with the full note text. Renders nothing
/// when there's no comment, so it's safe to drop into any set row.
class NoteIndicator extends StatelessWidget {
  final String comment;
  const NoteIndicator({super.key, required this.comment});

  @override
  Widget build(BuildContext context) {
    if (comment.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Comment'),
          content: Text(comment),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.chat_bubble_outline,
          size: 15,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}
