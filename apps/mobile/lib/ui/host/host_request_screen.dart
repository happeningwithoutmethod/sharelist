import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/session_controller.dart';

class HostRequestScreen extends ConsumerWidget {
  const HostRequestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(hostSessionProvider);
    final pendingConnections = host.pendingConnections;
    final requests = host.state.pendingRequests;
    final approvalRequired = host.state.settings.requireConnectionApproval;

    if (pendingConnections.isEmpty && requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            approvalRequired
                ? 'No pending connection or song requests.\nNew connectors will show up here for approval.'
                : 'No pending requests',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (approvalRequired || pendingConnections.isNotEmpty) ...[
          Text(
            'Connection requests',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (pendingConnections.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No connectors waiting for approval',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            ...pendingConnections.map((connector) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: Text(connector.displayName),
                  subtitle: const Text('Wants to join this session'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      FilledButton(
                        onPressed: () => ref
                            .read(hostSessionProvider.notifier)
                            .approveConnector(connector.deviceId),
                        child: const Text('Approve'),
                      ),
                      IconButton(
                        tooltip: 'Reject connection',
                        onPressed: () => ref
                            .read(hostSessionProvider.notifier)
                            .rejectConnector(connector.deviceId),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (requests.isNotEmpty) const SizedBox(height: 16),
        ],
        if (requests.isNotEmpty) ...[
          Text(
            'Song requests',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...requests.map((request) {
            return Card(
              child: ListTile(
                title: Text(request.track.title),
                subtitle:
                    Text('${request.track.artist} · ${request.requestedBy}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Approve to top',
                      onPressed: () => ref
                          .read(hostSessionProvider.notifier)
                          .approveRequest(request.id, 'top'),
                      icon: const Icon(Icons.vertical_align_top),
                    ),
                    IconButton(
                      tooltip: 'Approve to bottom',
                      onPressed: () => ref
                          .read(hostSessionProvider.notifier)
                          .approveRequest(request.id, 'bottom'),
                      icon: const Icon(Icons.vertical_align_bottom),
                    ),
                    IconButton(
                      tooltip: 'Reject',
                      onPressed: () => ref
                          .read(hostSessionProvider.notifier)
                          .rejectRequest(request.id),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
