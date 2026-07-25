import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:repiq/models/weight_unit.dart';
import 'package:repiq/services/theme_controller.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/theme/app_theme.dart';
import 'package:repiq/views/body_tracker_view.dart';
import 'package:repiq/views/legal_view.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Settings screen with local data stats, appearance/theme picker, FitNotes
/// CSV import, legal links, and a danger-zone clear action.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LogViewModel>();
    final themeController = context.watch<ThemeController>();
    final unitsController = context.watch<UnitsController>();
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader('Local Data'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.storage, color: cs.secondary),
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

        const SizedBox(height: 24),
        _SectionHeader('Appearance'),
        Card(
          child: RadioGroup<AppThemeId>(
            groupValue: themeController.themeId,
            onChanged: (id) {
              if (id != null) context.read<ThemeController>().setTheme(id);
            },
            child: Column(
              children: [
                for (final id in AppThemes.all) ...[
                  if (id != AppThemes.all.first)
                    const Divider(height: 1, indent: 16),
                  _ThemeOptionTile(id: id),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        _SectionHeader('Units'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(child: Text('Weight')),
                SegmentedButton<WeightUnit>(
                  segments: const [
                    ButtonSegment(value: WeightUnit.lbs, label: Text('lbs')),
                    ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                  ],
                  selected: {unitsController.unit},
                  onSelectionChanged: (s) =>
                      context.read<UnitsController>().setUnit(s.first),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        _SectionHeader('Body Tracker'),
        _ActionTile(
          icon: Icons.monitor_weight_outlined,
          title: 'Body Tracker',
          subtitle: 'Log and chart bodyweight and body fat % over time',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BodyTrackerView()),
          ),
        ),

        const SizedBox(height: 24),
        _SectionHeader('Import'),
        _ActionTile(
          icon: Icons.upload_file,
          title: 'Import FitNotes CSV',
          subtitle: 'Merge an existing FitNotes export into your local history',
          loading: vm.isImporting,
          onTap: () => _importCsv(context, vm),
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
                  borderRadius: BorderRadius.circular(8),
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

        const SizedBox(height: 24),
        _SectionHeader('Legal'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined, color: cs.secondary),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => LegalView.showPrivacy(context),
              ),
              const Divider(height: 1, indent: 16),
              ListTile(
                leading: Icon(Icons.gavel_outlined, color: cs.secondary),
                title: const Text('Terms of Service'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => LegalView.showTerms(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        _SectionHeader('Danger Zone'),
        _ActionTile(
          icon: Icons.delete_forever,
          title: 'Clear All Local Data',
          subtitle: 'Permanently deletes all locally stored sets',
          iconColor: cs.error,
          enabled: vm.localSetCount > 0,
          onTap: () => _confirmClear(context, vm),
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

/// Uppercase section label used between card groups.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey,
        ),
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
        radius: 16,
        backgroundColor: themeColors.primary,
        child: Icon(theme.icon, size: 16, color: Colors.white),
      ),
    );
  }
}

/// Tappable card row with an icon, title, subtitle, and optional loading spinner.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  final Color? iconColor;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                icon,
                color: iconColor ?? Theme.of(context).colorScheme.secondary,
              ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        enabled: enabled && !loading,
        onTap: onTap,
      ),
    );
  }
}
