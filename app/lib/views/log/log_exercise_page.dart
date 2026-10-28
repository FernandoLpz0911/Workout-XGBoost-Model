part of '../log_view.dart';

/// Exercise screen with three tabs: TRACK (log sets), HISTORY, GRAPH.
class _ExerciseDetailPage extends StatelessWidget {
  final int exerciseIndex;
  const _ExerciseDetailPage({required this.exerciseIndex});

  @override
  Widget build(BuildContext context) {
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        if (exerciseIndex >= vm.session.length) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => Navigator.pop(context),
          );
          return const Scaffold();
        }
        final ex = vm.session[exerciseIndex];
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
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
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'TRACK'),
                  Tab(text: 'HISTORY'),
                  Tab(text: 'GRAPH'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _TrackTab(exerciseIndex: exerciseIndex),
                ExerciseHistoryTab(exercise: ex.exercise),
                ExerciseGraphTab(exercise: ex.exercise, category: ex.category),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrackTab extends StatefulWidget {
  final int exerciseIndex;
  const _TrackTab({required this.exerciseIndex});

  @override
  State<_TrackTab> createState() => _TrackTabState();
}

class _TrackTabState extends State<_TrackTab>
    with AutomaticKeepAliveClientMixin {
  double _weight = 0;
  int _reps = 0;
  final _distCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  String _distUnit = 'mi';
  final _noteCtrl = TextEditingController();
  bool _initialized = false;

  /// Index into the exercise's logged sets being edited, or null when
  /// logging a new set.
  int? _editingIndex;

  @override
  bool get wantKeepAlive => true;

  void _maybeInit(SessionExercise ex) {
    if (_initialized) return;
    _initialized = true;
    _useSuggestion(ex);
  }

  /// Fills the steppers from the current recommendation (no setState).
  void _useSuggestion(SessionExercise ex) {
    final rec = ex.recommendation;
    _weight = rec?.targetWeight ?? 0.0;
    _reps = rec?.targetReps ?? 8;
  }

  void _clear(SessionExercise ex) {
    setState(() {
      _editingIndex = null;
      _useSuggestion(ex);
      _distCtrl.clear();
      _durCtrl.clear();
      _noteCtrl.clear();
    });
  }

  void _loadSet(int index, WorkoutSet s) {
    setState(() {
      _editingIndex = index;
      _weight = s.weight;
      _reps = s.reps;
      _distCtrl.text = s.distance != null ? s.distance!.toStringAsFixed(2) : '';
      _distUnit = s.distanceUnit ?? 'mi';
      _durCtrl.text = s.duration ?? '';
      _noteCtrl.text = s.comment;
    });
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

  WorkoutSet _buildSet(SessionExercise ex, ExerciseType type, DateTime date) {
    switch (type) {
      case ExerciseType.strength:
        return WorkoutSet(
          date: date,
          exercise: ex.exercise,
          category: ex.category,
          weight: _weight,
          reps: _reps,
          comment: _noteCtrl.text.trim(),
        );
      case ExerciseType.cardio:
        return WorkoutSet(
          date: date,
          exercise: ex.exercise,
          category: ex.category,
          distance: double.parse(_distCtrl.text),
          distanceUnit: _distUnit,
          duration: _durCtrl.text.trim(),
          comment: _noteCtrl.text.trim(),
        );
      case ExerciseType.passive:
        return WorkoutSet(
          date: date,
          exercise: ex.exercise,
          category: ex.category,
          duration: _durCtrl.text.trim(),
          comment: _noteCtrl.text.trim(),
        );
    }
  }

  void _save(LogViewModel vm, SessionExercise ex, ExerciseType type) {
    final editing = _editingIndex;
    if (editing != null && editing < ex.sets.length) {
      // Keep the original timestamp so the set stays in place.
      vm.updateSet(
        widget.exerciseIndex,
        editing,
        _buildSet(ex, type, ex.sets[editing].date),
      );
      setState(() => _editingIndex = null);
      _noteCtrl.clear();
      return;
    }
    vm.logSet(widget.exerciseIndex, _buildSet(ex, type, DateTime.now()));
    _noteCtrl.clear();
    final timer = context.read<RestTimer>();
    if (timer.autoStartEnabled) timer.start();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<LogViewModel>(
      builder: (context, vm, _) {
        if (widget.exerciseIndex >= vm.session.length) {
          return const SizedBox.shrink();
        }
        final ex = vm.session[widget.exerciseIndex];
        _maybeInit(ex);
        final type = exerciseTypeOf(ex.category);
        final units = context.watch<UnitsController>();
        final editing = _editingIndex != null;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (type == ExerciseType.strength) ...[
              _TrainingModeToggle(
                mode: ex.trainingMode,
                onChanged: (m) => vm.setTrainingMode(widget.exerciseIndex, m),
              ),
              const SizedBox(height: 12),
              _SuggestionLine(
                ex: ex,
                onUse: () => setState(() => _useSuggestion(ex)),
              ),
              const SizedBox(height: 12),
            ] else ...[
              _RecBanner(ex: ex),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (type == ExerciseType.strength)
                      ..._buildStrengthInputs(units)
                    else if (type == ExerciseType.cardio)
                      ..._buildCardioInputs()
                    else
                      ..._buildPassiveInputs(),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        hintText: 'e.g. "forearms tired"',
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canSave(type)
                          ? () => _save(vm, ex, type)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        editing ? 'UPDATE' : 'SAVE',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => _clear(ex),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'CLEAR',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (ex.sets.isNotEmpty) ...[
              const SizedBox(height: 28),
              const SectionHeader('Logged Today'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Column(
                    children: ex.sets
                        .asMap()
                        .entries
                        .map(
                          (e) => _SetRow(
                            setNum: e.key + 1,
                            set: e.value,
                            selected: _editingIndex == e.key,
                            onTap: () => _loadSet(e.key, e.value),
                            onDelete: () {
                              if (_editingIndex != null) {
                                setState(() => _editingIndex = null);
                              }
                              vm.removeSet(widget.exerciseIndex, e.key);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildStrengthInputs(UnitsController units) => [
    _StepperRow(
      label: 'WEIGHT (${units.label.toUpperCase()})',
      value: units.toDisplay(_weight).toStringAsFixed(1),
      onDecrement: () => setState(
        () => _weight = units.toLbs(
          (units.toDisplay(_weight) - units.step).clamp(0, 99999),
        ),
      ),
      onIncrement: () => setState(
        () => _weight = units.toLbs(units.toDisplay(_weight) + units.step),
      ),
      onTap: () => _editValue(
        context,
        label: 'Weight (${units.label})',
        initial: units.toDisplay(_weight).toStringAsFixed(1),
        isDecimal: true,
        onConfirm: (v) => setState(() => _weight = units.toLbs(v)),
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

/// Compact one-line suggestion for strength exercises: "Suggested: 30.0 lbs
/// × 8" with a Use button, plus the engine's reason text underneath.
class _SuggestionLine extends StatelessWidget {
  final SessionExercise ex;
  final VoidCallback onUse;
  const _SuggestionLine({required this.ex, required this.onUse});

  @override
  Widget build(BuildContext context) {
    if (ex.recError != null) {
      return _InfoChip(
        color: Colors.grey,
        icon: Icons.info_outline,
        text: ex.recError!,
      );
    }
    final rec = ex.recommendation;
    if (rec == null) return const SizedBox.shrink();
    final units = context.watch<UnitsController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Suggested: ${units.toDisplay(rec.targetWeight).toStringAsFixed(1)} '
                '${units.label} × ${rec.targetReps}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            TextButton(onPressed: onUse, child: const Text('Use')),
          ],
        ),
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

/// Last-session summary for cardio/passive exercises.
class _RecBanner extends StatelessWidget {
  final SessionExercise ex;
  const _RecBanner({required this.ex});

  @override
  Widget build(BuildContext context) {
    final summary = ex.lastSessionSummary;
    if (summary == null || summary.isEmpty) return const SizedBox.shrink();
    return _InfoChip(color: Colors.blue, icon: Icons.history, text: summary);
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

/// One logged set row: set number, display text, PR badge; tap to edit.
class _SetRow extends StatelessWidget {
  final int setNum;
  final WorkoutSet set;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SetRow({
    required this.setNum,
    required this.set,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<UnitsController>().unit;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : null,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$setNum',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            Text(
              set.displayTextIn(unit),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            NoteIndicator(comment: set.comment),
            PrBadge(set: set),
            const Spacer(),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for picking or typing an exercise to add to today's session.

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
    final units = context.watch<UnitsController>();
    return AlertDialog(
      title: const Text('Edit Set'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_type == ExerciseType.strength) ..._strengthFields(units),
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

  List<Widget> _strengthFields(UnitsController units) => [
    _StepperRow(
      label: 'WEIGHT (${units.label.toUpperCase()})',
      value: units.toDisplay(_weight).toStringAsFixed(1),
      onDecrement: () => setState(
        () => _weight = units.toLbs(
          (units.toDisplay(_weight) - units.step).clamp(0, 99999),
        ),
      ),
      onIncrement: () => setState(
        () => _weight = units.toLbs(units.toDisplay(_weight) + units.step),
      ),
      onTap: () => _editValue(
        context,
        label: 'Weight (${units.label})',
        initial: units.toDisplay(_weight).toStringAsFixed(1),
        isDecimal: true,
        onConfirm: (v) => setState(() => _weight = units.toLbs(v)),
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.secondary,
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
      color: Theme.of(context).extension<AppPalette>()!.raisedSurface,
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
  showDialog<void>(
    context: context,
    builder: (_) => _EditValueDialog(
      label: label,
      initial: initial,
      isDecimal: isDecimal,
      onConfirm: onConfirm,
    ),
  );
}

/// Numeric entry dialog used by [_editValue]. Owns its [TextEditingController]
/// so it can be disposed when the dialog closes.
class _EditValueDialog extends StatefulWidget {
  final String label;
  final String initial;
  final bool isDecimal;
  final void Function(double) onConfirm;
  const _EditValueDialog({
    required this.label,
    required this.initial,
    required this.isDecimal,
    required this.onConfirm,
  });

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: widget.isDecimal,
        ),
        decoration: InputDecoration(hintText: widget.label, errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final v = double.tryParse(_ctrl.text);
            if (v != null) {
              widget.onConfirm(v);
              Navigator.pop(context);
            } else {
              setState(() => _error = 'Enter a valid number');
            }
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
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
