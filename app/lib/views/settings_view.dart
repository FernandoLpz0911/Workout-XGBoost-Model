import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/weight_unit.dart';
import 'package:repiq/services/share_service.dart';
import 'package:repiq/services/theme_controller.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/theme/app_theme.dart';
import 'package:repiq/views/body_tracker_view.dart';
import 'package:repiq/views/legal_view.dart';
import 'package:repiq/views/widgets/app_card.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Settings screen with local data stats, appearance/theme picker, FitNotes
/// CSV import, legal links, and a danger-zone clear action.
///
/// Every row shares one visual language — a colored circular icon avatar,
/// title, optional subtitle, and a chevron or inline control — grouped into
/// a handful of cards so it reads as one cohesive screen rather than a
/// stack of differently-styled rows.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LogViewModel>();
    final themeController = context.watch<ThemeController>();
    final unitsController = context.watch<UnitsController>();
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                IconAvatar(icon: Icons.storage_rounded, color: cs.secondary),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vm.localSetCount} sets stored locally',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${vm.historyByDate.length} workout day${vm.historyByDate.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 28),
        SectionHeader('Appearance'),
        GroupedCard(
          children: [
            RadioGroup<AppThemeId>(
              groupValue: themeController.themeId,
              onChanged: (id) {
                if (id != null) context.read<ThemeController>().setTheme(id);
              },
              child: Column(
                children: [
                  for (final id in AppThemes.all) _ThemeOptionTile(id: id),
                ],
              ),
            ),
            AppListRow(
              icon: Icons.scale_outlined,
              iconColor: cs.secondary,
              title: 'Weight Unit',
              trailing: SegmentedButton<WeightUnit>(
                segments: const [
                  ButtonSegment(value: WeightUnit.lbs, label: Text('lbs')),
                  ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                ],
                selected: {unitsController.unit},
                onSelectionChanged: (s) =>
                    context.read<UnitsController>().setUnit(s.first),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),
        SectionHeader('Data'),
        GroupedCard(
          children: [
            AppListRow(
              icon: Icons.monitor_weight_outlined,
              iconColor: cs.secondary,
              title: 'Body Tracker',
              subtitle: 'Log and chart bodyweight and body fat % over time',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BodyTrackerView()),
              ),
            ),
            AppListRow(
              icon: Icons.upload_file_rounded,
              iconColor: cs.secondary,
              title: 'Import FitNotes CSV',
              subtitle:
                  'Merge an existing FitNotes export into your local history',
              loading: vm.isImporting,
              onTap: () => _importCsv(context, vm),
            ),
            AppListRow(
              icon: Icons.download_rounded,
              iconColor: cs.secondary,
              title: 'Export Workout CSV',
              subtitle: 'Save your full history as a CSV for later analysis',
              loading: vm.isExporting,
              enabled: vm.localSetCount > 0,
              onTap: () => _exportCsv(context, vm),
            ),
          ],
        ),

        if (vm.lastActionMessage != null) ...[
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final msg = vm.lastActionMessage!;
              final isError =
                  msg.contains('fail') ||
                  msg.contains('Error') ||
                  msg.contains('required');
              final errorColor = Theme.of(context).colorScheme.error;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isError
                      ? errorColor.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: isError ? errorColor : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(msg)),
                    GestureDetector(
                      onTap: () => vm.dismissLastActionMessage(),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],

        const SizedBox(height: 28),
        SectionHeader('Legal'),
        GroupedCard(
          children: [
            AppListRow(
              icon: Icons.privacy_tip_outlined,
              iconColor: cs.secondary,
              title: 'Privacy Policy',
              onTap: () => LegalView.showPrivacy(context),
            ),
            AppListRow(
              icon: Icons.gavel_outlined,
              iconColor: cs.secondary,
              title: 'Terms of Service',
              onTap: () => LegalView.showTerms(context),
            ),
          ],
        ),

        const SizedBox(height: 28),
        SectionHeader('Danger Zone'),
        GroupedCard(
          children: [
            AppListRow(
              icon: Icons.delete_forever_rounded,
              iconColor: cs.error,
              title: 'Clear All Local Data',
              subtitle: 'Permanently deletes all locally stored sets',
              enabled: vm.localSetCount > 0,
              onTap: () => _confirmClear(context, vm),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _importCsv(BuildContext context, LogViewModel vm) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.first.bytes == null) return;
      final csvText = utf8.decode(result.files.first.bytes!);
      await vm.importCsvText(csvText);
    } catch (e) {
      vm.reportImportFailure('Import failed: $e');
    }
  }

  Future<void> _exportCsv(BuildContext context, LogViewModel vm) async {
    final bytes = await vm.exportCsvBytes();
    if (bytes == null) return;
    try {
      await ShareService.shareCsvExport(bytes);
    } catch (e) {
      vm.reportImportFailure('Export failed: $e');
    }
  }

  void _confirmClear(BuildContext context, LogViewModel vm) {
    final errorColor = Theme.of(context).colorScheme.error;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This will permanently delete all locally stored sets. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              vm.clearLocalData();
            },
            child: Text('Delete', style: TextStyle(color: errorColor)),
          ),
        ],
      ),
    );
  }
}

/// One selectable row in the Appearance card — a color-swatch preview,
/// theme name, and a radio indicating the active theme. Reads its
/// selection state from the ancestor [RadioGroup].
class _ThemeOptionTile extends StatelessWidget {
  final AppThemeId id;
  const _ThemeOptionTile({required this.id});

  @override
  Widget build(BuildContext context) {
    final theme = AppThemes.of(id);
    final themeColors = theme.data.colorScheme;
    return RadioListTile<AppThemeId>(
      value: id,
      title: Text(theme.label),
      secondary: CircleAvatar(
        radius: 20,
        backgroundColor: themeColors.primary,
        child: Icon(theme.icon, size: 20, color: Colors.white),
      ),
    );
  }
}
