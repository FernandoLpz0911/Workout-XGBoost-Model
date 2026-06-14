import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:repiq/views/legal_view.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';

/// Settings screen with local data stats, FitNotes CSV import, legal links,
/// and a danger-zone clear action.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LogViewModel>();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader('Local Data'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.storage, color: Colors.blueAccent),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${vm.localSetCount} sets stored locally',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                        '${vm.historyByDate.length} workout day${vm.historyByDate.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
            ),
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
          Builder(builder: (context) {
            final msg = vm.lastActionMessage!;
            final isError = msg.contains('fail') ||
                msg.contains('Error') ||
                msg.contains('required');
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isError
                    ? Colors.redAccent.withValues(alpha: 0.15)
                    : Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: isError ? Colors.redAccent : Colors.green,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(msg)),
                  GestureDetector(
                    onTap: () => vm.dismissLastActionMessage(),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 24),
        _SectionHeader('Legal'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined,
                    color: Colors.blueAccent),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => LegalView.showPrivacy(context),
              ),
              const Divider(height: 1, indent: 16),
              ListTile(
                leading: const Icon(Icons.gavel_outlined,
                    color: Colors.blueAccent),
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
          iconColor: Colors.redAccent,
          enabled: vm.localSetCount > 0,
          onTap: () => _confirmClear(context, vm),
        ),
      ],
    );
  }

  Future<void> _importCsv(BuildContext context, LogViewModel vm) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.first.bytes == null) return;
    final csvText = utf8.decode(result.files.first.bytes!);
    await vm.importCsvText(csvText);
  }

  void _confirmClear(BuildContext context, LogViewModel vm) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
            'This will permanently delete all locally stored sets. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              vm.clearLocalData();
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
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
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.grey)),
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
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, color: iconColor ?? Colors.blueAccent),
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        enabled: enabled && !loading,
        onTap: onTap,
      ),
    );
  }
}
