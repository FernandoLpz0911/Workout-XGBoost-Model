import '../models/workout_set.dart';

/// A (category, exercise) pair shown in the add-exercise picker.
class PickerEntry {
  final String category;
  final String exercise;
  const PickerEntry(this.category, this.exercise);
}

/// A category row in the picker with its exercise count.
class CategorySummary {
  final String name;
  final int count;
  const CategorySummary(this.name, this.count);
}

/// Up to [limit] distinct exercises, most recently logged first.
List<PickerEntry> recentExercises(List<WorkoutSet> history, {int limit = 8}) {
  final sorted = [...history]..sort((a, b) => b.date.compareTo(a.date));
  final seen = <String>{};
  final out = <PickerEntry>[];
  for (final s in sorted) {
    if (seen.add('${s.category}\u0000${s.exercise}')) {
      out.add(PickerEntry(s.category, s.exercise));
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// One summary per category, in the map's iteration order.
List<CategorySummary> categorySummaries(
  Map<String, List<String>> exercisesByCategory,
) => [
  for (final e in exercisesByCategory.entries)
    CategorySummary(e.key, e.value.length),
];

/// Case-insensitive alphabetical copy of [exercises].
List<String> sortedExercises(List<String> exercises) =>
    [...exercises]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

/// Exercises across all categories whose name contains [query]
/// (case-insensitive). A blank query yields no results.
List<PickerEntry> searchExercises(
  Map<String, List<String>> exercisesByCategory,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  return [
    for (final e in exercisesByCategory.entries)
      for (final ex in sortedExercises(e.value))
        if (ex.toLowerCase().contains(q)) PickerEntry(e.key, ex),
  ];
}
