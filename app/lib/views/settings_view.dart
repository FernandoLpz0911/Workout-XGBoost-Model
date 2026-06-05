import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;
import 'package:repiq/views/legal_view.dart';
import 'package:repiq/viewmodels/auth_viewmodel.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/viewmodels/subscription_viewmodel.dart';
import 'package:repiq/views/paywall_view.dart';

/// Settings screen: account info, subscription status, local data,
/// FitNotes CSV import, optional cloud model retraining, and data deletion.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final sub = context.watch<SubscriptionViewModel>();
    final vm = context.watch<LogViewModel>();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader('Account'),
        _AccountCard(auth: auth),

        const SizedBox(height: 24),
        _SectionHeader('Subscription'),
        _SubscriptionCard(sub: sub),

        const SizedBox(height: 24),
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

        const SizedBox(height: 24),
        _SectionHeader('Model Training'),
        Card(
          color: Colors.blue.withValues(alpha: 0.08),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.offline_bolt, color: Colors.blueAccent),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fully offline',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text(
                        'Recommendations are computed on-device from your '
                        'local history. No server or internet required.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.cloud_upload_outlined,
          title: 'Sync to Cloud',
          subtitle: sub.isPremium
              ? 'Uploads your ${vm.localSetCount} sets and retrains the XGBoost model.'
              : 'Premium feature — upgrade to retrain the cloud model.',
          loading: vm.isTraining,
          enabled: vm.localSetCount > 0 && sub.isPremium,
          lockIcon: !sub.isPremium,
          onTap: sub.isPremium
              ? () => _confirmRetrain(context, vm)
              : () => PaywallView.show(context),
        ),

        if (vm.lastActionMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: vm.lastActionMessage!.contains('fail') ||
                      vm.lastActionMessage!.contains('Error')
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  vm.lastActionMessage!.contains('fail') ||
                          vm.lastActionMessage!.contains('Error')
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: vm.lastActionMessage!.contains('fail') ||
                          vm.lastActionMessage!.contains('Error')
                      ? Colors.redAccent
                      : Colors.green,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(vm.lastActionMessage!)),
              ],
            ),
          ),
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

  void _confirmRetrain(BuildContext context, LogViewModel vm) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retrain model?'),
        content: Text(
            'This will upload your ${vm.localSetCount} local sets to the server '
            'and retrain the AI. This may take a moment.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              vm.trainOnLocalData();
            },
            child: const Text('Retrain'),
          ),
        ],
      ),
    );
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

class _AccountCard extends StatelessWidget {
  final AuthViewModel auth;
  const _AccountCard({required this.auth});

  @override
  Widget build(BuildContext context) {
    final user = auth.user;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
              backgroundImage: user?.photoURL != null
                  ? NetworkImage(user!.photoURL!)
                  : null,
              child: user?.photoURL == null
                  ? const Icon(Icons.person, color: Colors.redAccent)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user?.displayName ?? 'Signed in',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (user?.email != null)
                    Text(user!.email!,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => auth.signOut(),
              child: const Text('Sign out',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final SubscriptionViewModel sub;
  const _SubscriptionCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    if (sub.isPremium) {
      return Card(
        color: Colors.greenAccent.withValues(alpha: 0.08),
        child: ListTile(
          leading: const Icon(Icons.star, color: Colors.greenAccent),
          title: const Text('Premium Active',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('All features unlocked',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          trailing: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(
                  'https://play.google.com/store/account/subscriptions'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Manage',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.star_border, color: Colors.amber),
        title: const Text('Free Plan'),
        subtitle: const Text('Upgrade to unlock AI insights, charts & more',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: ElevatedButton(
          onPressed: () => PaywallView.show(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text('Upgrade'),
        ),
      ),
    );
  }
}

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

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;
  final bool enabled;
  final bool lockIcon;
  final VoidCallback onTap;
  final Color? iconColor;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.lockIcon = false,
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
            : Icon(icon, color: lockIcon ? Colors.grey : (iconColor ?? Colors.blueAccent)),
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: lockIcon
            ? const Icon(Icons.lock_outline, color: Colors.grey, size: 18)
            : const Icon(Icons.chevron_right, color: Colors.grey),
        enabled: enabled && !loading,
        onTap: onTap,
      ),
    );
  }
}
