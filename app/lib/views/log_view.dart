import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/rest_timer.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

export 'package:repiq/viewmodels/log_viewmodel.dart' show TrainingMode;

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
          body: vm.session.isEmpty
              ? _EmptySessionView(onAdd: () => _showAddExercise(context, vm))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: vm.session.length,
                  itemBuilder: (context, i) {
                    final ex = vm.session[i];
                    final setCount = ex.sets.length;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
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
                          builder: (_) => _ExerciseDetailPage(exerciseIndex: i),
                        ),
                      ),
                    );
                  },
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

  static void _confirmRemove(BuildContext context, LogViewModel vm, int index) {
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
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when no exercises have been added for the current day.
class _EmptySessionView extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptySessionView({required this.onAdd});

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
          const Icon(Icons.fitness_center, size: 64, color: Colors.grey),
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
        ],
      ),
    );
  }
}

/// Full-screen logging page for a single exercise.
/// Shows the AI recommendation, training mode toggle, weight/reps steppers,
/// and the running list of sets logged so far today.
class _ExerciseDetailPage extends StatefulWidget {
  final int exerciseIndex;
  const _ExerciseDetailPage({required this.exerciseIndex});

  @override
  State<_ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends State<_ExerciseDetailPage> {
  double _weight = 0;
  int _reps = 0;
  final _distCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  String _distUnit = 'mi';
  final _noteCtrl = TextEditingController();
  bool _initialized = false;

  void _maybeInit(SessionExercise ex) {
    if (_initialized) return;
    _initialized = true;
    final rec = ex.recommendation;
    _weight = rec?.targetWeight ?? 0.0;
    _reps = rec?.targetReps ?? 8;
  }

  @override
  void dispose() {
    _distCtrl.dispose();
    _durCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool _canSave(ExerciseType type) {
    switch (type) {
      case ExerciseType.strength:
        return _weight > 0 && _reps > 0;
      case ExerciseType.cardio:
        return double.tryParse(_distCtrl.text) != null &&
            _durCtrl.text.trim().isNotEmpty;
      case ExerciseType.passive:
        return _durCtrl.text.trim().isNotEmpty;
    }
  }

  void _save(LogViewModel vm, SessionExercise ex, ExerciseType type) {
    final date = DateTime.now();
    final WorkoutSet set;
    switch (type) {
      case ExerciseType.strength:
        set = WorkoutSet(
          date: date,
          exercise: ex.exercise,
          category: ex.category,
          weight: _weight,
          reps: _reps,
          comment: _noteCtrl.text.trim(),
        );
      case ExerciseType.cardio:
        set = WorkoutSet(
          date: date,
          exercise: ex.exercise,
          category: ex.category,
          distance: double.parse(_distCtrl.text),
          distanceUnit: _distUnit,
          duration: _durCtrl.text.trim(),
          comment: _noteCtrl.text.trim(),
        );
      case ExerciseType.passive:
        set = WorkoutSet(
          date: date,
          exercise: ex.exercise,
          category: ex.category,
          duration: _durCtrl.text.trim(),
          comment: _noteCtrl.text.trim(),
        );
    }
    vm.logSet(widget.exerciseIndex, set);
    _noteCtrl.clear();
    final timer = context.read<RestTimer>();
    if (timer.autoStartEnabled) timer.start();
  }

  void _showEditSet(
    BuildContext context,
    int setIndex,
    SessionExercise ex,
    LogViewModel vm,
  ) {
    showDialog<bool>(
      context: context,
      builder: (_) => _LogSetDialog(
        exercise: ex.exercise,
        category: ex.category,
        recommendation: ex.recommendation,
        existingSet: ex.sets[setIndex],
        onSave: (updated) =>
            vm.updateSet(widget.exerciseIndex, setIndex, updated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        if (widget.exerciseIndex >= vm.session.length) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => Navigator.pop(context),
          );
          return const Scaffold();
        }

        final ex = vm.session[widget.exerciseIndex];
        _maybeInit(ex);
        final type = exerciseTypeOf(ex.category);

        return Scaffold(
          backgroundColor: const Color(0xFF0E1117),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0E1117),
            surfaceTintColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ex.exercise),
                Text(
                  ex.category,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              if (type == ExerciseType.strength) ...[
                _TrainingModeToggle(
                  mode: ex.trainingMode,
                  onChanged: (m) => vm.setTrainingMode(widget.exerciseIndex, m),
                ),
                const SizedBox(height: 16),
              ],
              _RecBanner(ex: ex),
              const SizedBox(height: 24),
              if (type == ExerciseType.strength)
                ..._buildStrengthInputs()
              else if (type == ExerciseType.cardio)
                ..._buildCardioInputs()
              else
                ..._buildPassiveInputs(),
              const SizedBox(height: 16),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. "forearms tired"',
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSave(type) ? () => _save(vm, ex, type) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    type == ExerciseType.cardio
                        ? 'Save Lap'
                        : type == ExerciseType.passive
                        ? 'Save Session'
                        : 'Save Set',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (ex.sets.isNotEmpty) ...[
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 4),
                ...ex.sets.asMap().entries.map(
                  (e) => _SetRow(
                    setNum: e.key + 1,
                    set: e.value,
                    onEdit: () => _showEditSet(context, e.key, ex, vm),
                    onDelete: () => vm.removeSet(widget.exerciseIndex, e.key),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildStrengthInputs() => [
    _StepperRow(
      label: 'WEIGHT (lbs)',
      value: _weight.toStringAsFixed(1),
      onDecrement: () =>
          setState(() => _weight = (_weight - 2.5).clamp(0, 9999)),
      onIncrement: () => setState(() => _weight += 2.5),
      onTap: () => _editValue(
        context,
        label: 'Weight (lbs)',
        initial: _weight.toStringAsFixed(1),
        isDecimal: true,
        onConfirm: (v) => setState(() => _weight = v),
      ),
    ),
    const SizedBox(height: 20),
    _StepperRow(
      label: 'REPS',
      value: _reps.toString(),
      onDecrement: () => setState(() => _reps = (_reps - 1).clamp(0, 999)),
      onIncrement: () => setState(() => _reps++),
      onTap: () => _editValue(
        context,
        label: 'Reps',
        initial: _reps.toString(),
        isDecimal: false,
        onConfirm: (v) => setState(() => _reps = v.toInt()),
      ),
    ),
  ];

  List<Widget> _buildCardioInputs() => [
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _distCtrl,
            decoration: const InputDecoration(labelText: 'Distance'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _distUnit,
          items: const [
            DropdownMenuItem(value: 'mi', child: Text('mi')),
            DropdownMenuItem(value: 'km', child: Text('km')),
          ],
          onChanged: (v) => setState(() => _distUnit = v ?? 'mi'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _durCtrl,
      decoration: const InputDecoration(labelText: 'Time', hintText: '0:00:00'),
      onChanged: (_) => setState(() {}),
    ),
  ];

  List<Widget> _buildPassiveInputs() => [
    TextField(
      controller: _durCtrl,
      decoration: const InputDecoration(
        labelText: 'Duration',
        hintText: '0:15:00',
      ),
      onChanged: (_) => setState(() {}),
    ),
  ];
}

/// Displays the AI recommendation for strength exercises, or a last-session
/// summary for cardio/passive exercises.
class _RecBanner extends StatelessWidget {
  final SessionExercise ex;
  const _RecBanner({required this.ex});

  @override
  Widget build(BuildContext context) {
    final type = exerciseTypeOf(ex.category);

    if (type != ExerciseType.strength) {
      final summary = ex.lastSessionSummary;
      if (summary == null || summary.isEmpty) return const SizedBox.shrink();
      return _InfoChip(color: Colors.blue, icon: Icons.history, text: summary);
    }

    if (ex.recError != null) {
      return _InfoChip(
        color: Colors.grey,
        icon: Icons.info_outline,
        text: ex.recError!,
      );
    }
    final rec = ex.recommendation;
    if (rec == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recommendation: ${rec.targetWeight.toStringAsFixed(1)} lbs × ${rec.targetReps} reps',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          rec.status,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (rec.notesInsight.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InfoChip(
            color: Colors.amber,
            icon: Icons.notes,
            text: rec.notesInsight,
          ),
        ],
      ],
    );
  }
}

/// Colored pill used for notes insight, history summaries, and error messages.
class _InfoChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _InfoChip({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// One logged set row with set number, display text, and edit/delete actions.
class _SetRow extends StatelessWidget {
  final int setNum;
  final WorkoutSet set;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SetRow({
    required this.setNum,
    required this.set,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '${set.category == 'Cardio' ? 'Lap' : 'Set'} $setNum',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Text(
            set.displayText,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (set.comment.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"${set.comment}"',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            onPressed: onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.grey,
            ),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Dialog for picking or typing an exercise to add to today's session.
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
      if (exs.isNotEmpty) _exercise = exs.first;
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
    return AlertDialog(
      title: const Text('Add Exercise'),
      content: Column(
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
        ],
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
                  widget.vm.addExercise(_resolvedCategory!, _resolvedExercise!);
                }
              : null,
          child: const Text('Add'),
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
          value: _category,
          items: categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (val) => setState(() {
            _category = val;
            final exs = widget.vm.exercisesFor(val ?? '');
            _exercise = exs.isNotEmpty ? exs.first : null;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Exercise'),
          value: _exercise,
          items: exercises
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (val) => setState(() => _exercise = val),
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

/// Dialog for editing an already-logged set. Supports strength, cardio, and
/// passive exercise types.
class _LogSetDialog extends StatefulWidget {
  final String exercise;
  final String category;
  final Recommendation? recommendation;
  final WorkoutSet? existingSet;
  final void Function(WorkoutSet) onSave;

  const _LogSetDialog({
    required this.exercise,
    required this.category,
    required this.recommendation,
    this.existingSet,
    required this.onSave,
  });

  @override
  State<_LogSetDialog> createState() => _LogSetDialogState();
}

class _LogSetDialogState extends State<_LogSetDialog> {
  double _weight = 0;
  int _reps = 0;
  final _distCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  String _distUnit = 'mi';
  final _noteCtrl = TextEditingController();

  ExerciseType get _type => exerciseTypeOf(widget.category);

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSet;
    if (existing != null) {
      _weight = existing.weight;
      _reps = existing.reps;
      _distCtrl.text = existing.distance != null
          ? existing.distance!.toStringAsFixed(2)
          : '';
      _distUnit = existing.distanceUnit ?? 'mi';
      _durCtrl.text = existing.duration ?? '';
      _noteCtrl.text = existing.comment;
    } else {
      final rec = widget.recommendation;
      _weight = rec?.targetWeight ?? 0.0;
      _reps = rec?.targetReps ?? 8;
    }
  }

  @override
  void dispose() {
    _distCtrl.dispose();
    _durCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isValid {
    switch (_type) {
      case ExerciseType.strength:
        return _weight > 0 && _reps > 0;
      case ExerciseType.cardio:
        return double.tryParse(_distCtrl.text) != null &&
            _durCtrl.text.trim().isNotEmpty;
      case ExerciseType.passive:
        return _durCtrl.text.trim().isNotEmpty;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Set'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_type == ExerciseType.strength) ..._strengthFields(),
            if (_type == ExerciseType.cardio) ..._cardioFields(),
            if (_type == ExerciseType.passive) ..._passiveFields(),
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. "forearms tired"',
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  List<Widget> _strengthFields() => [
    _StepperRow(
      label: 'WEIGHT (lbs)',
      value: _weight.toStringAsFixed(1),
      onDecrement: () =>
          setState(() => _weight = (_weight - 2.5).clamp(0, 9999)),
      onIncrement: () => setState(() => _weight += 2.5),
      onTap: () => _editValue(
        context,
        label: 'Weight (lbs)',
        initial: _weight.toStringAsFixed(1),
        isDecimal: true,
        onConfirm: (v) => setState(() => _weight = v),
      ),
    ),
    const SizedBox(height: 20),
    _StepperRow(
      label: 'REPS',
      value: _reps.toString(),
      onDecrement: () => setState(() => _reps = (_reps - 1).clamp(0, 999)),
      onIncrement: () => setState(() => _reps++),
      onTap: () => _editValue(
        context,
        label: 'Reps',
        initial: _reps.toString(),
        isDecimal: false,
        onConfirm: (v) => setState(() => _reps = v.toInt()),
      ),
    ),
  ];

  List<Widget> _cardioFields() => [
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _distCtrl,
            decoration: const InputDecoration(labelText: 'Distance'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _distUnit,
          items: const [
            DropdownMenuItem(value: 'mi', child: Text('mi')),
            DropdownMenuItem(value: 'km', child: Text('km')),
          ],
          onChanged: (v) => setState(() => _distUnit = v ?? 'mi'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _durCtrl,
      decoration: const InputDecoration(labelText: 'Time', hintText: '0:00:00'),
      onChanged: (_) => setState(() {}),
    ),
  ];

  List<Widget> _passiveFields() => [
    TextField(
      controller: _durCtrl,
      decoration: const InputDecoration(
        labelText: 'Duration',
        hintText: '0:15:00',
      ),
      autofocus: true,
      onChanged: (_) => setState(() {}),
    ),
  ];

  void _save() {
    final date = widget.existingSet?.date ?? DateTime.now();
    final WorkoutSet set;
    switch (_type) {
      case ExerciseType.strength:
        set = WorkoutSet(
          date: date,
          exercise: widget.exercise,
          category: widget.category,
          weight: _weight,
          reps: _reps,
          comment: _noteCtrl.text.trim(),
        );
      case ExerciseType.cardio:
        set = WorkoutSet(
          date: date,
          exercise: widget.exercise,
          category: widget.category,
          distance: double.parse(_distCtrl.text),
          distanceUnit: _distUnit,
          duration: _durCtrl.text.trim(),
          comment: _noteCtrl.text.trim(),
        );
      case ExerciseType.passive:
        set = WorkoutSet(
          date: date,
          exercise: widget.exercise,
          category: widget.category,
          duration: _durCtrl.text.trim(),
          comment: _noteCtrl.text.trim(),
        );
    }
    widget.onSave(set);
    Navigator.pop(context, true);
  }
}

/// Labeled stepper: a large value display flanked by − and + buttons.
/// Tapping the value opens a text dialog for direct entry.
class _StepperRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onTap;
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.blueAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StepBtn(icon: Icons.remove, onTap: onDecrement),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            _StepBtn(icon: Icons.add, onTap: onIncrement),
          ],
        ),
      ],
    );
  }
}

/// Square tap target used as the − / + buttons in [_StepperRow].
class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C1C26),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

/// Segmented button for switching between Hypertrophy and Strength modes.
class _TrainingModeToggle extends StatelessWidget {
  final TrainingMode mode;
  final void Function(TrainingMode) onChanged;
  const _TrainingModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TrainingMode>(
      segments: const [
        ButtonSegment(
          value: TrainingMode.hypertrophy,
          label: Text('Hypertrophy'),
        ),
        ButtonSegment(value: TrainingMode.strength, label: Text('Strength')),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity(horizontal: -2, vertical: -2),
      ),
    );
  }
}

/// Shows a dialog to type a numeric value directly into a stepper field.
void _editValue(
  BuildContext context, {
  required String label,
  required String initial,
  required bool isDecimal,
  required void Function(double) onConfirm,
}) {
  final ctrl = TextEditingController(text: initial);
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
        decoration: InputDecoration(hintText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text);
            if (v != null) {
              onConfirm(v);
              Navigator.pop(context);
            }
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String _weekday(int d) =>
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
String _month(int m) => [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][m - 1];
