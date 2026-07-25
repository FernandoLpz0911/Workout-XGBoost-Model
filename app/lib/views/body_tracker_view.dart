import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/body_measurement.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/utils/date_format.dart';
import 'package:repiq/viewmodels/body_tracker_viewmodel.dart';
import 'package:repiq/views/widgets/metric_chart.dart';

const _typeLabel = {
  BodyMeasurementType.weight: 'Bodyweight',
  BodyMeasurementType.bodyFat: 'Body Fat',
};

/// Body fat readings are always a plain percentage; bodyweight readings are
/// stored canonically in lbs and converted for display via [units].
String _unitFor(BodyMeasurementType type, UnitsController units) =>
    type == BodyMeasurementType.weight ? units.label : '%';

double _toDisplay(
  double value,
  BodyMeasurementType type,
  UnitsController units,
) => type == BodyMeasurementType.weight ? units.toDisplay(value) : value;

double _toStored(
  double value,
  BodyMeasurementType type,
  UnitsController units,
) => type == BodyMeasurementType.weight ? units.toLbs(value) : value;

/// Body Tracker: log and chart bodyweight / body fat % readings over time.
/// Owns its own [BodyTrackerViewModel] instance, scoped to this screen only.
class BodyTrackerView extends StatelessWidget {
  const BodyTrackerView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BodyTrackerViewModel(),
      child: const _BodyTrackerScaffold(),
    );
  }
}

class _BodyTrackerScaffold extends StatefulWidget {
  const _BodyTrackerScaffold();

  @override
  State<_BodyTrackerScaffold> createState() => _BodyTrackerScaffoldState();
}

class _BodyTrackerScaffoldState extends State<_BodyTrackerScaffold> {
  BodyMeasurementType _type = BodyMeasurementType.weight;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Body Tracker'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'History'),
              Tab(text: 'Graph'),
            ],
          ),
        ),
        body: Consumer<BodyTrackerViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SegmentedButton<BodyMeasurementType>(
                    segments: const [
                      ButtonSegment(
                        value: BodyMeasurementType.weight,
                        label: Text('Bodyweight'),
                        icon: Icon(Icons.monitor_weight_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: BodyMeasurementType.bodyFat,
                        label: Text('Body Fat'),
                        icon: Icon(Icons.percent, size: 16),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _HistoryTab(type: _type),
                      _GraphTab(type: _type),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddDialog(context, _type),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, BodyMeasurementType type) {
    final vm = context.read<BodyTrackerViewModel>();
    final units = context.read<UnitsController>();
    showDialog<void>(
      context: context,
      builder: (_) => _AddMeasurementDialog(
        type: type,
        unitLabel: _unitFor(type, units),
        onSave: (value) =>
            vm.addMeasurement(type, _toStored(value, type, units)),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final BodyMeasurementType type;
  const _HistoryTab({required this.type});

  @override
  Widget build(BuildContext context) {
    final units = context.watch<UnitsController>();
    return Consumer<BodyTrackerViewModel>(
      builder: (context, vm, _) {
        final entries = vm.forType(type).reversed.toList();
        if (entries.isEmpty) {
          return Center(
            child: Text(
              'No ${_typeLabel[type]!.toLowerCase()} readings yet.\n'
              'Tap + to log one.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        final unit = _unitFor(type, units);
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final m = entries[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  '${_toDisplay(m.value, type, units).toStringAsFixed(1)} $unit',
                ),
                subtitle: Text(
                  '${monthAbbrev(m.date.month)} ${m.date.day}, ${m.date.year}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () =>
                      context.read<BodyTrackerViewModel>().deleteMeasurement(m),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GraphTab extends StatelessWidget {
  final BodyMeasurementType type;
  const _GraphTab({required this.type});

  @override
  Widget build(BuildContext context) {
    final units = context.watch<UnitsController>();
    return Consumer<BodyTrackerViewModel>(
      builder: (context, vm, _) {
        final data = vm
            .forType(type)
            .map((m) => ChartPoint(m.date, _toDisplay(m.value, type, units)))
            .toList();
        if (data.length < 2) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: NotEnoughChartData(),
          );
        }
        final unit = _unitFor(type, units);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: MetricChart(
            data: data,
            axisLabel: (v) => v.toStringAsFixed(0),
            bottomLabel: (d) => '${monthAbbrev(d.month)} ${d.day}',
            tooltipTitle: (d) => '${monthAbbrev(d.month)} ${d.day}, ${d.year}',
            tooltipValue: (v) => '${v.toStringAsFixed(1)} $unit',
          ),
        );
      },
    );
  }
}

class _AddMeasurementDialog extends StatefulWidget {
  final BodyMeasurementType type;
  final String unitLabel;
  final ValueChanged<double> onSave;
  const _AddMeasurementDialog({
    required this.type,
    required this.unitLabel,
    required this.onSave,
  });

  @override
  State<_AddMeasurementDialog> createState() => _AddMeasurementDialogState();
}

class _AddMeasurementDialogState extends State<_AddMeasurementDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a valid number');
      return;
    }
    widget.onSave(value);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Log ${_typeLabel[widget.type]}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Value (${widget.unitLabel})',
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
