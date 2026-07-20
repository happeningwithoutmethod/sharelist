import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../config/server_config.dart';
import '../../services/device_service.dart';
import '../../services/playback_service.dart';
import '../../services/session_controller.dart';
import '../../services/session_invite.dart';
import 'host_control_screen.dart';
import 'host_lists_screen.dart';
import 'host_request_screen.dart';
import 'host_settings_screen.dart';

class HostShell extends ConsumerStatefulWidget {
  const HostShell({super.key});

  @override
  ConsumerState<HostShell> createState() => _HostShellState();
}

class _HostShellState extends ConsumerState<HostShell>
    with WidgetsBindingObserver {
  int _index = 0;
  final _youtubeBarKey = GlobalKey();

  static const _pages = <Widget>[
    _HostSessionTab(),
    HostControlScreen(),
    HostListsScreen(),
    HostRequestScreen(),
    HostSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      final host = ref.read(hostSessionProvider);
      if (!host.connected && !host.isReconnecting) {
        if (mounted) context.go('/host');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(hostSessionProvider.notifier).handleAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostSessionProvider);
    // Keep the playback controller alive for the whole host session, not only
    // while the Control tab is visible.
    ref.watch(playbackProvider);
    final onControlTab = _index == 1;
    final onListsTab = _index == 2;
    final hasActiveTrack =
        ref.read(playbackProvider.notifier).activeTrackId != null;
    // On non-control tabs, only keep the mini iframe while a track is loaded.
    final showMiniPlayer = !onControlTab && hasActiveTrack;

    return Scaffold(
      appBar: AppBar(
        title: Text(host.state.sessionName),
        leading: BackButton(
          onPressed: () async {
            final shouldLeave = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Leave host session?'),
                content: const Text(
                  'Leaving returns to the start screen. The session stays active on the server for 30 minutes if you do not end it.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Leave'),
                  ),
                ],
              ),
            );
            if (shouldLeave == true && context.mounted) {
              await ref.read(playbackProvider.notifier).stopPlayback();
              if (context.mounted) context.go('/host');
            }
          },
        ),
        actions: [
          if (host.isReconnecting)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: Text('Reconnecting…')),
            )
          else if (!host.connected)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: Text('Disconnected')),
            ),
        ],
      ),
      floatingActionButton: onListsTab && host.error == null
          ? FloatingActionButton(
              onPressed: () => HostListsScreen.showAddTrackSheet(context, ref),
              tooltip: 'Add song',
              child: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: host.error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(host.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        await ref.read(playbackProvider.notifier).stopPlayback();
                        if (context.mounted) context.go('/host');
                      },
                      child: const Text('Back to start'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Player stays at the top on every tab (compact when not Control).
                if (onControlTab)
                  _PersistentYoutubeBar(key: _youtubeBarKey, expanded: true),
                if (showMiniPlayer)
                  _PersistentYoutubeBar(key: _youtubeBarKey, expanded: false),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    sizing: StackFit.expand,
                    children: _pages,
                  ),
                ),
                if (onControlTab) const _PlaybackTransportBar(),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.qr_code_2), label: 'Session'),
          const NavigationDestination(icon: Icon(Icons.play_circle), label: 'Control'),
          const NavigationDestination(icon: Icon(Icons.queue_music), label: 'Lists'),
          NavigationDestination(
            icon: Badge(
              label: Text('${host.requestTabBadgeCount}'),
              isLabelVisible: host.requestTabBadgeCount > 0,
              child: const Icon(Icons.inbox),
            ),
            label: 'Request',
          ),
          const NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _PlaybackTransportBar extends ConsumerWidget {
  const _PlaybackTransportBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(hostSessionProvider);
    final playback = ref.watch(playbackProvider);
    final controller = ref.read(playbackProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    final durationMs = host.state.durationMs;
    final positionMs = host.state.positionMs;
    final progress = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0);

    return Material(
      elevation: 2,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    _formatMs(positionMs),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Expanded(
                    child: Slider(
                      value: progress,
                      onChanged: durationMs <= 0
                          ? null
                          : (value) {
                              final ms = (value * durationMs).round();
                              controller.seek(Duration(milliseconds: ms));
                            },
                    ),
                  ),
                  Text(
                    _formatMs(durationMs),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    onPressed: () => controller.previous(),
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    iconSize: 52,
                    onPressed: () => controller.togglePlayPause(),
                    icon: Icon(
                      host.state.isPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle,
                    ),
                  ),
                  IconButton(
                    iconSize: 36,
                    onPressed: () => controller.next(),
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
              if (playback.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Playback error: ${playback.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMs(int ms) {
    final duration = Duration(milliseconds: ms < 0 ? 0 : ms);
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PersistentYoutubeBar extends ConsumerWidget {
  const _PersistentYoutubeBar({
    super.key,
    required this.expanded,
  });

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackProvider.notifier).youtubeController;
    final media = MediaQuery.sizeOf(context);
    final height = expanded
        ? (media.width * 9 / 16).clamp(160.0, 240.0)
        : 88.0;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: YoutubePlayer(
          controller: controller,
          aspectRatio: 16 / 9,
        ),
      ),
    );
  }
}

class _HostSessionTab extends ConsumerStatefulWidget {
  const _HostSessionTab();

  @override
  ConsumerState<_HostSessionTab> createState() => _HostSessionTabState();
}

enum _JoinShareMode { app, web, code }

class _HostSessionTabState extends ConsumerState<_HostSessionTab> {
  var _mode = _JoinShareMode.app;
  var _requestedJoinCode = false;

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _share(SessionInvite invite, {required bool web}) async {
    await SharePlus.instance.share(
      ShareParams(
        text: web ? invite.shareTextWeb : invite.shareTextApp,
        subject: 'Join my Share List session',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostSessionProvider);
    final sessionId = host.sessionId;
    final joinCode = host.joinCode?.toUpperCase();
    final hasCode = joinCode != null && SessionInvite.isJoinCode(joinCode);
    final invite = sessionId == null
        ? null
        : SessionInvite(
            sessionId: sessionId,
            serverUrl: host.serverUrl,
            joinCode: joinCode,
          );
    final localMode = ref.watch(localModeProvider).valueOrNull ?? false;
    final canShare = invite != null && host.connected;
    // Web QR + short codes need the central relay (internet mode).
    final internetJoins = !localMode;

    if (internetJoins &&
        host.connected &&
        !hasCode &&
        sessionId != null &&
        !_requestedJoinCode) {
      _requestedJoinCode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(ref.read(hostSessionProvider.notifier).refreshJoinCode());
      });
    }
    if (hasCode) {
      _requestedJoinCode = false;
    }

    // Keep selection valid when internet joins are unavailable.
    final mode = (!internetJoins && _mode != _JoinShareMode.app)
        ? _JoinShareMode.app
        : _mode;

    final appUrl = invite?.httpsUri.toString();
    final webUrl = invite?.webUri.toString();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (invite == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Center(
            child: SegmentedButton<_JoinShareMode>(
              segments: [
                const ButtonSegment<_JoinShareMode>(
                  value: _JoinShareMode.app,
                  label: Text('App'),
                  icon: Icon(Icons.smartphone),
                ),
                ButtonSegment<_JoinShareMode>(
                  value: _JoinShareMode.web,
                  label: const Text('Web'),
                  icon: const Icon(Icons.language),
                  enabled: internetJoins,
                ),
                ButtonSegment<_JoinShareMode>(
                  value: _JoinShareMode.code,
                  label: const Text('Code'),
                  icon: const Icon(Icons.pin),
                  enabled: internetJoins,
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selected) {
                setState(() => _mode = selected.first);
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            switch (mode) {
              _JoinShareMode.app =>
                'Scan to join with the Share List app.',
              _JoinShareMode.web => hasCode
                  ? 'Scan to open ${ServerConfig.hostname}/join/$joinCode in a browser.'
                  : 'Scan to open the web join link in a browser.',
              _JoinShareMode.code => hasCode
                  ? 'Share this 6-character code. Connectors enter it manually.'
                  : 'Waiting for a join code from the relay…',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (mode == _JoinShareMode.code) ...[
            if (hasCode) ...[
              Center(
                child: SelectableText(
                  joinCode,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        letterSpacing: 8,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _copy(context, 'Join code', joinCode),
                icon: const Icon(Icons.copy),
                label: const Text('Copy join code'),
              ),
              if (webUrl != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: canShare
                      ? () => _share(invite, web: true)
                      : null,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share code + web link'),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Waiting for a join code from the relay…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _requestedJoinCode = false;
                        unawaited(
                          ref
                              .read(hostSessionProvider.notifier)
                              .refreshJoinCode(),
                        );
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
          ] else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  key: ValueKey(
                    mode == _JoinShareMode.web ? webUrl : appUrl,
                  ),
                  data: (mode == _JoinShareMode.web ? webUrl : appUrl)!,
                  size: 220,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canShare
                  ? () => _share(invite, web: mode == _JoinShareMode.web)
                  : null,
              icon: Icon(
                mode == _JoinShareMode.web
                    ? Icons.language
                    : Icons.ios_share,
              ),
              label: Text(
                mode == _JoinShareMode.web
                    ? 'Share web join link'
                    : 'Share app join link',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    (mode == _JoinShareMode.web ? webUrl : appUrl)!,
                  ),
                ),
                IconButton(
                  tooltip: mode == _JoinShareMode.web
                      ? 'Copy web join link'
                      : 'Copy app join link',
                  onPressed: () => _copy(
                    context,
                    mode == _JoinShareMode.web
                        ? 'Web join link'
                        : 'App join link',
                    (mode == _JoinShareMode.web ? webUrl : appUrl)!,
                  ),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ],
          if (localMode) ...[
            const SizedBox(height: 8),
            Text(
              'Local mode — connectors must be on the same Wi‑Fi. Web join codes need internet mode.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ] else if (!hasCode && host.connected) ...[
            const SizedBox(height: 8),
            Text(
              'Waiting for a join code from the relay…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        Text('Connectors: ${host.state.connectors.length}'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow suggestions'),
          value: host.state.settings.allowSuggestions,
          onChanged: host.connected
              ? (value) =>
                  ref.read(hostSessionProvider.notifier).setAllowSuggestions(value)
              : null,
        ),
        const SizedBox(height: 8),
        Text('Session ID', style: Theme.of(context).textTheme.labelLarge),
        SelectableText(sessionId ?? 'Starting…'),
        if (hasCode) ...[
          const SizedBox(height: 8),
          Text('Join code', style: Theme.of(context).textTheme.labelLarge),
          SelectableText(joinCode),
        ],
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: host.connected
              ? () async {
                  await ref.read(playbackProvider.notifier).stopPlayback();
                  await ref.read(hostSessionProvider.notifier).endSession();
                  if (context.mounted) context.go('/host');
                }
              : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('End Session'),
        ),
      ],
    );
  }
}
