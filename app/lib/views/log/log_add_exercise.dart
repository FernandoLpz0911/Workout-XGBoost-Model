part of '../log_view.dart';

/// Full-screen picker for adding an exercise to today's session: search,
/// recent exercises, then categories -> exercises, plus custom creation.
class _AddExerciseDialog extends StatefulWidget {
  final LogViewModel vm;
  const _AddExerciseDialog({required this.vm});

  @override
  State<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<_AddExerciseDialog> {
  String? _category;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, List<String>> get _byCategory => {
    for (final c in widget.vm.allCategories) c: widget.vm.exercisesFor(c),
  };

  bool get _searching => _searchCtrl.text.trim().isNotEmpty;

  void _pick(String category, String exercise, {ProgressionAlgorithm? algo}) {
    final isStrength = exerciseTypeOf(category) == ExerciseType.strength;
    Navigator.pop(context);
    widget.vm.addExercise(
      category,
      exercise,
      algorithm: isStrength
          ? (algo ?? widget.vm.progressionAlgorithmFor(exercise))
          : ProgressionAlgorithm.standard,
    );
  }

  Future<void> _createCustom() async {
    final result = await showDialog<_CustomExercise>(
      context: context,
      builder: (_) => _CustomExerciseDialog(initialCategory: _category),
    );
    if (result != null && mounted) {
      _pick(result.category, result.exercise, algo: result.algorithm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inCategory = _category != null && !_searching;
    return Dialog.fullscreen(
      child: PopScope(
        canPop: !inCategory,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _category = null);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(inCategory ? Icons.arrow_back : Icons.close),
              onPressed: () {
                if (inCategory) {
                  setState(() => _category = null);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            title: Text(inCategory ? _category! : 'Add Exercise'),
            actions: [
              IconButton(
                tooltip: 'Create custom exercise',
                icon: const Icon(Icons.add),
                onPressed: _createCustom,
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search exercises',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () =>
                                setState(() => _searchCtrl.clear()),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final byCat = _byCategory;
    if (_searching) {
      final results = searchExercises(byCat, _searchCtrl.text);
      if (results.isEmpty) {
        return Center(
          child: TextButton.icon(
            onPressed: _createCustom,
            icon: const Icon(Icons.add),
            label: const Text('No matches - create custom exercise'),
          ),
        );
      }
      return ListView(children: [for (final e in results) _entryTile(e, true)]);
    }
    if (_category != null) {
      final exs = sortedExercises(byCat[_category!] ?? const []);
      return ListView(
        children: [
          for (final e in exs) _entryTile(PickerEntry(_category!, e), false),
        ],
      );
    }
    final recent = recentExercises(widget.vm.history);
    return ListView(
      children: [
        if (recent.isNotEmpty) ...[
          _header('Recent'),
          for (final e in recent) _entryTile(e, true),
        ],
        _header('Categories'),
        for (final c in categorySummaries(byCat))
          ListTile(
            title: Text(c.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${c.count}'),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => setState(() => _category = c.name),
          ),
      ],
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    ),
  );

  Widget _entryTile(PickerEntry e, bool showCategory) => ListTile(
    title: Text(e.exercise),
    subtitle: showCategory ? Text(e.category) : null,
    onTap: () => _pick(e.category, e.exercise),
  );
}

class _CustomExercise {
  final String category;
  final String exercise;
  final ProgressionAlgorithm algorithm;
  const _CustomExercise(this.category, this.exercise, this.algorithm);
}

/// Form for typing a brand-new category/exercise pair.
class _CustomExerciseDialog extends StatefulWidget {
  final String? initialCategory;
  const _CustomExerciseDialog({this.initialCategory});

  @override
  State<_CustomExerciseDialog> createState() => _CustomExerciseDialogState();
}

class _CustomExerciseDialogState extends State<_CustomExerciseDialog> {
  late final _catCtrl = TextEditingController(text: widget.initialCategory);
  final _exCtrl = TextEditingController();
  ProgressionAlgorithm _algorithm = ProgressionAlgorithm.standard;

  @override
  void dispose() {
    _catCtrl.dispose();
    _exCtrl.dispose();
    super.dispose();
  }

  bool get _canAdd =>
      _catCtrl.text.trim().isNotEmpty && _exCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isStrength =
        exerciseTypeOf(_catCtrl.text.trim()) == ExerciseType.strength;
    return AlertDialog(
      title: const Text('Custom Exercise'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _catCtrl,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. Chest, Cardio, Passive...',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _exCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Exercise',
                hintText: 'e.g. General Running',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (isStrength) ...[
              const SizedBox(height: 12),
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
              ),
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
              ? () => Navigator.pop(
                  context,
                  _CustomExercise(
                    _catCtrl.text.trim(),
                    _exCtrl.text.trim(),
                    isStrength ? _algorithm : ProgressionAlgorithm.standard,
                  ),
                )
              : null,
          child: const Text('Add'),
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
