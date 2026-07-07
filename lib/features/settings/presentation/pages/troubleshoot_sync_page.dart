import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/features/settings/presentation/providers/sync_providers.dart';

/// Recovery actions for a wedged Cloud Sync state (issue #509). Reached from
/// the Cloud Sync page's Advanced section and by tapping the sync-error banner.
/// Actions escalate in severity; each explains itself in plain language.
class TroubleshootSyncPage extends ConsumerWidget {
  const TroubleshootSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Troubleshoot Sync')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.healing),
            title: const Text('Repair Sync'),
            subtitle: const Text(
              'Fix a stuck sync. Clears this device’s sync state and gives it '
              'a fresh sync identity, then reconnects on the next sync. Your '
              'dive data is not affected.',
            ),
            onTap: () => _confirmRepair(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRepair(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair Sync?'),
        content: const Text(
          'This clears all local sync state and gives this device a new sync '
          'identity, then reconnects fresh on the next sync. Your dive data is '
          'safe and is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Repair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(syncStateProvider.notifier).repairSync();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync repaired')));
    }
  }
}
