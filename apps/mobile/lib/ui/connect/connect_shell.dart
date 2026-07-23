import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';

import '../../services/session_controller.dart';
import '../widgets/track_search_sheet.dart';
import 'connect_now_playing_screen.dart';
import 'connect_playlist_screen.dart';

class ConnectShell extends ConsumerStatefulWidget {
  const ConnectShell({super.key});

  @override
  ConsumerState<ConnectShell> createState() => _ConnectShellState();
}

class _ConnectShellState extends ConsumerState<ConnectShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _navigatingAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(connectSessionProvider.notifier).handleAppResumed());
    }
  }

  Future<void> _leaveTo({
    required String location,
    String? message,
  }) async {
    if (_navigatingAway || !mounted) return;
    _navigatingAway = true;
    final snackMessage = message ?? ref.read(connectSessionProvider).error;
    try {
      await ref.read(connectSessionProvider.notifier).leaveSession();
    } finally {
      if (mounted) {
        context.go(location);
        if (snackMessage != null && snackMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(snackMessage)),
          );
        }
      }
    }
  }

  Future<void> _returnToConnectJoin({String? message}) =>
      _leaveTo(location: '/connect', message: message);

  Future<void> _leaveToHome() => _leaveTo(location: '/');

  @override
  Widget build(BuildContext context) {
    ref.listen<ConnectSessionState>(connectSessionProvider, (previous, next) {
      if (next.forceReturnHome) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _returnToConnectJoin(message: next.error);
        });
      }
    });

    final connect = ref.watch(connectSessionProvider);

    if (connect.forceReturnHome) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (connect.isReconnecting && !connect.connected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reconnecting…')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Rejoining the host session…'),
            ],
          ),
        ),
      );
    }

    if (connect.error != null && !connect.connected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Disconnected')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(connect.error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _returnToConnectJoin(message: connect.error),
                child: const Text('Back to connect'),
              ),
            ],
          ),
        ),
      );
    }

    final pages = [
      ConnectNowPlayingScreen(state: connect.state),
      ConnectPlaylistScreen(state: connect.state, votedSongIds: connect.votedSongIds),
      _ConnectRequestTab(connect: connect),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(connect.state.sessionName),
            if (connect.displayName != null)
              Text(
                'Connected as ${connect.displayName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (connect.isReconnecting)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: Text('Reconnecting…')),
            ),
          IconButton(
            onPressed: _leaveToHome,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Now Playing'),
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlist'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Request'),
        ],
      ),
    );
  }
}

class _ConnectRequestTab extends ConsumerWidget {
  const _ConnectRequestTab({required this.connect});

  final ConnectSessionState connect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (connect.isAwaitingConnectionApproval) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_top, size: 48),
              SizedBox(height: 16),
              Text(
                'Waiting for the host to approve your connection',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'You can browse the playlist, but song requests stay locked until you are approved.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final enabled = connect.state.settings.allowSuggestions;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              enabled
                  ? 'Search for a song to request from the host'
                  : 'The host has disabled song suggestions',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: enabled
                  ? () async {
                      final track = await showModalBottomSheet<Track>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => TrackSearchSheet(
                          provider: ref.read(connectSessionProvider.notifier).musicProvider,
                        ),
                      );
                      if (track != null) {
                        ref.read(connectSessionProvider.notifier).requestTrack(track);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Requested ${track.title}')),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.search),
              label: const Text('Search & request'),
            ),
          ],
        ),
      ),
    );
  }
}
