part of '../log_view.dart';

class _AddExerciseDialog extends StatefulWidget {
  final LogViewModel vm;
  const _AddExerciseDialog({required this.vm});

  @override
  State<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<_AddExerciseDialog> {
  String? _category;
  String? _exercise;
  bool _customMode = false;
  ProgressionAlgorithm _algorithm = ProgressionAlgorithm.standard;
  final _catCtrl = TextEditingController();
  final _exCtrl = TextEditingController();

  bool get _hasHistory => widget.vm.allCategories.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _customMode = !_hasHistory;
    if (_hasHistory) {
      _category = widget.vm.allCategories.first;
      final exs = widget.vm.exercisesFor(_category!);
      if (exs.isNotEmpty) {
        _exercise = exs.first;
        _algorithm = widget.vm.progressionAlgorithmFor(_exercise!);
      }
    }
  }

  @override
  void dispose() {
    _catCtrl.dispose();
    _exCtrl.dispose();
    super.dispose();
  }

  String? get _resolvedCategory =>
      _customMode ? _catCtrl.text.trim() : _category;
  String? get _resolvedExercise =>
      _customMode ? _exCtrl.text.trim() : _exercise;

  bool get _canAdd {
    final cat = _resolvedCategory;
    final ex = _resolvedExercise;
    return cat != null && cat.isNotEmpty && ex != null && ex.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isStrength =
        exerciseTypeOf(_resolvedCategory ?? '') == ExerciseType.strength;
    return AlertDialog(
      title: const Text('Add Exercise'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_customMode) _buildCustomFields() else _buildDropdowns(),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _customMode = !_customMode;
                  if (_customMode) {
                    _catCtrl.text = _category ?? '';
                    _exCtrl.text = _exercise ?? '';
                  }
                }),
                child: Text(
                  _customMode ? 'Pick from history' : 'Enter custom exercise',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (isStrength) ...[
              const SizedBox(height: 12),
              _buildAlgorithmPicker(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canAdd
              ? () {
                  Navigator.pop(context);
                  widget.vm.addExercise(
                    _resolvedCategory!,
                    _resolvedExercise!,
                    algorithm: isStrength
                        ? _algorithm
                        : ProgressionAlgorithm.standard,
                  );
                }
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildAlgorithmPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'PROGRESSION STYLE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<ProgressionAlgorithm>(
          segments: const [
            ButtonSegment(
              value: ProgressionAlgorithm.standard,
              label: Text('Standard'),
            ),
            ButtonSegment(
              value: ProgressionAlgorithm.plateauBreaker,
              label: Text('Plateau Breaker'),
            ),
          ],
          selected: {_algorithm},
          onSelectionChanged: (s) => setState(() => _algorithm = s.first),
          style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity(horizontal: -2, vertical: -2),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _algorithm == ProgressionAlgorithm.plateauBreaker
              ? 'For exercises that stall for you — cycles intensity in waves instead of a straight line up.'
              : 'Add weight when you hit the rep target, hold and build reps otherwise.',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildDropdowns() {
    final categories = widget.vm.allCategories;
    final exercises = _category != null
        ? widget.vm.exercisesFor(_category!)
        : <String>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Category'),
          initialValue: _category,
          items: categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (val) => setState(() {
            _category = val;
            final exs = widget.vm.exercisesFor(val ?? '');
            _exercise = exs.isNotEmpty ? exs.first : null;
            _algorithm = widget.vm.progressionAlgorithmFor(_exercise ?? '');
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(_category),
          decoration: const InputDecoration(labelText: 'Exercise'),
          initialValue: _exercise,
          items: exercises
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (val) => setState(() {
            _exercise = val;
            _algorithm = widget.vm.progressionAlgorithmFor(val ?? '');
          }),
        ),
      ],
    );
  }

  Widget _buildCustomFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _catCtrl,
          decoration: const InputDecoration(
            labelText: 'Category',
            hintText: 'e.g. Chest, Cardio, Passive…',
          ),
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _exCtrl,
          decoration: const InputDecoration(
            labelText: 'Exercise',
            hintText: 'e.g. General Running',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

/// Opens the edit-set dialog for an already-logged [existingSet], calling
/// [onSave] with the updated set when confirmed. Used by History, Calendar,
/// and the per-exercise detail view to correct past entries.
Future<void> showEditSetDialog(
  BuildContext context, {
  required WorkoutSet existingSet,
  required void Function(WorkoutSet) onSave,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _LogSetDialog(
      exercise: existingSet.exercise,
      category: existingSet.category,
      recommendation: null,
      existingSet: existingSet,
      onSave: onSave,
    ),
  );
}

/// Dialog for editing an already-logged set. Supports strength, cardio, and
/// passive exercise types.
