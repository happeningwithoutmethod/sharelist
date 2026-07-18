import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/session_controller.dart';

class HostSettingsScreen extends ConsumerWidget {
  const HostSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(hostSessionProvider).state.settings;

    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Allow playlist songs to be voted for'),
          value: settings.allowVoting,
          onChanged: (value) {
            ref.read(hostSessionProvider.notifier).updateSettings(
                  settings.copyWith(allowVoting: value),
                );
          },
        ),
        SwitchListTile(
          title: const Text('Auto move songs based on votes'),
          subtitle: const Text('Queue below now-playing reorders by vote score'),
          value: settings.autoReorderByVotes,
          onChanged: settings.allowVoting
              ? (value) {
                  ref.read(hostSessionProvider.notifier).updateSettings(
                        settings.copyWith(autoReorderByVotes: value),
                      );
                }
              : null,
        ),
        SwitchListTile(
          title: const Text('Auto playlist advance'),
          subtitle: const Text('Play the next song when the current one finishes'),
          value: settings.autoPlaylistAdvance,
          onChanged: (value) {
            ref.read(hostSessionProvider.notifier).updateSettings(
                  settings.copyWith(autoPlaylistAdvance: value),
                );
          },
        ),
        SwitchListTile(
          title: const Text('Auto approve requests'),
          subtitle: const Text(
            'Add requested songs to the bottom of the playlist automatically',
          ),
          value: settings.autoApproveRequests,
          onChanged: (value) {
            ref.read(hostSessionProvider.notifier).updateSettings(
                  settings.copyWith(autoApproveRequests: value),
                );
          },
        ),
        SwitchListTile(
          title: const Text('New connections need approval'),
          subtitle: const Text(
            'Approve connectors on the Request tab before they can request songs',
          ),
          value: settings.requireConnectionApproval,
          onChanged: (value) {
            ref.read(hostSessionProvider.notifier).updateSettings(
                  settings.copyWith(requireConnectionApproval: value),
                );
          },
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: OutlinedButton.icon(
            onPressed: () async {
              await ref.read(hostSessionProvider.notifier).restoreDefaultSettings();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Host settings restored to defaults')),
                );
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restore defaults'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Text(
            'Settings are remembered for the next session you start.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
