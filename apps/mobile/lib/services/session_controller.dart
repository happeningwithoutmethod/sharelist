import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_providers/music_providers.dart';
import 'package:shared_models/shared_models.dart';
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'device_service.dart';
import 'host_country.dart';
import 'local_relay_server.dart';
import 'session_client.dart';
import 'session_invite.dart';

MusicProvider createMusicProvider(String serverUrl, {bool useRemoteSearch = false}) {
  // Prefer relay `/api/music/search` (YouTube Data API v3 + server-side key).
  // Direct YouTubeMusicProvider needs --dart-define=YOUTUBE_API_KEY=...
  if (kIsWeb || useRemoteSearch) {
    return RemoteMusicProvider(httpBaseUrl: httpBaseUrlFromWs(serverUrl));
  }
  return YouTubeMusicProvider();
}

/// Shared in-process LAN relay used when local mode is enabled.
final localRelayServerProvider = Provider<LocalRelayServer>((ref) {
  final server = LocalRelayServer();
  ref.onDispose(() {
    unawaited(server.stop());
  });
  return server;
});

class HostSessionState {
  HostSessionState({
    this.sessionId,
    this.sessionToken,
    this.hostGoogleSub,
    String? serverUrl,
    this.connected = false,
    this.state = const HostState(
      sessionName: 'Share List Session',
      playlist: [],
      nowPlayingIndex: -1,
      isPlaying: false,
      positionMs: 0,
      durationMs: 0,
      settings: HostSettings(),
      voteScores: {},
      pendingRequests: [],
      connectors: [],
    ),
    this.error,
    this.isReconnecting = false,
    this.pendingConnections = const [],
  }) : serverUrl = serverUrl ?? defaultServerUrl;

  final String? sessionId;
  final String? sessionToken;
  final String? hostGoogleSub;
  final String serverUrl;
  final bool connected;
  final HostState state;
  final String? error;
  final bool isReconnecting;

  /// Connectors waiting for host approval (Request tab).
  final List<ConnectorInfo> pendingConnections;

  int get requestTabBadgeCount =>
      pendingConnections.length + state.pendingRequests.length;

  HostSessionState copyWith({
    String? sessionId,
    String? sessionToken,
    String? hostGoogleSub,
    String? serverUrl,
    bool? connected,
    HostState? state,
    String? error,
    bool? isReconnecting,
    List<ConnectorInfo>? pendingConnections,
    bool clearError = false,
  }) {
    return HostSessionState(
      sessionId: sessionId ?? this.sessionId,
      sessionToken: sessionToken ?? this.sessionToken,
      hostGoogleSub: hostGoogleSub ?? this.hostGoogleSub,
      serverUrl: serverUrl ?? this.serverUrl,
      connected: connected ?? this.connected,
      state: state ?? this.state,
      error: clearError ? null : (error ?? this.error),
      isReconnecting: isReconnecting ?? this.isReconnecting,
      pendingConnections: pendingConnections ?? this.pendingConnections,
    );
  }
}

class HostSessionController extends StateNotifier<HostSessionState> {
  HostSessionController(this.ref) : super(HostSessionState()) {
    // Default central server URL — prefer relay search on native host.
    _musicProvider = createMusicProvider(
      state.serverUrl,
      useRemoteSearch: !kIsWeb,
    );
    _messageHandler = _handleServerMessage;
    _disconnectListener = _onHostSocketDisconnected;
  }

  final Ref ref;
  late MusicProvider _musicProvider;
  SessionClient? _client;
  late final void Function(Map<String, dynamic>) _messageHandler;
  late final VoidCallback _disconnectListener;
  Timer? _reorderTimer;
  Timer? _ensureTimer;
  bool _endingSession = false;
  bool _recoverInFlight = false;
  /// WebSocket URL used to dial the relay (may differ from advertised share URL).
  String? _dialServerUrl;
  final _trackAddedAt = <String, int>{};
  final _votesByDevice = <String, Set<String>>{};

  MusicProvider get musicProvider => _musicProvider;

  void _setMusicProviderForServer(
    String serverUrl, {
    bool useRemoteSearch = false,
  }) {
    final current = _musicProvider;
    if (current is YouTubeMusicProvider) {
      current.dispose();
    }
    _musicProvider = createMusicProvider(
      serverUrl,
      useRemoteSearch: useRemoteSearch,
    );
  }

  Future<void> startSession({
    required AuthUser user,
    String? sessionName,
    String? serverUrl,
  }) async {
    final localMode = await ref.read(localModeProvider.future);
    late final String resolvedServerUrl;

    if (localMode) {
      if (kIsWeb) {
        throw UnsupportedError(
          'Local mode cannot host from the browser. Use the Android/desktop app on the same Wi‑Fi.',
        );
      }
      final lanIp = await resolveLanIPv4();
      final relay = ref.read(localRelayServerProvider);
      await relay.start(advertiseHost: lanIp);
      resolvedServerUrl = relay.loopbackUrl;
    } else {
      resolvedServerUrl = serverUrl ?? state.serverUrl;
    }

    // Prefer loopback for the host music provider so search hits this device's relay.
    _setMusicProviderForServer(
      localMode
          ? ref.read(localRelayServerProvider).loopbackUrl
          : resolvedServerUrl,
      useRemoteSearch: true,
    );
    final persistence = await ref.read(sessionPersistenceProvider.future);
    final savedSettings = await persistence.loadHostSettings();
    state = state.copyWith(
      clearError: true,
      isReconnecting: false,
      hostGoogleSub: user.id,
      serverUrl: localMode
          ? ref.read(localRelayServerProvider).advertiseUrl
          : resolvedServerUrl,
      pendingConnections: const [],
      state: HostState.empty(
        sessionName: sessionName ?? 'Share List Session',
        settings: savedSettings,
      ),
    );
    await _connect(serverUrl: resolvedServerUrl);
    final countryCode = await resolveHostCountryCode();
    _client!.send(
      HostStartMessage(
        hostGoogleSub: user.id,
        sessionName: sessionName,
        countryCode: countryCode,
      ).toJson(),
    );
    await _waitUntilConnected();
  }

  Future<void> reconnectSession({
    required StoredHostSession stored,
    required AuthUser user,
  }) async {
    final localMode = await ref.read(localModeProvider.future);
    if (localMode) {
      throw StateError(
        'Local mode sessions cannot be resumed after leaving. Start a new session instead.',
      );
    }

    if (stored.hostGoogleSub != user.id) {
      state = state.copyWith(error: 'Google account does not match session host');
      throw StateError('Google account does not match session host');
    }

    state = state.copyWith(isReconnecting: true, clearError: true);
    _setMusicProviderForServer(stored.serverUrl, useRemoteSearch: true);
    state = state.copyWith(
      sessionId: stored.sessionId,
      sessionToken: stored.sessionToken,
      hostGoogleSub: stored.hostGoogleSub,
      serverUrl: stored.serverUrl,
    );
    await _connect(serverUrl: stored.serverUrl);
    await _ensureSessionOnServer(
      sessionId: stored.sessionId,
      sessionToken: stored.sessionToken,
      hostGoogleSub: stored.hostGoogleSub,
      waitForAck: true,
    );
    state = state.copyWith(
      connected: true,
      isReconnecting: false,
      clearError: true,
    );
    _startEnsureTimer();
    _broadcastState();
  }

  /// Called when the host app returns to the foreground.
  Future<void> handleAppResumed() async {
    if (_endingSession || _recoverInFlight) return;
    if (state.sessionId == null || state.sessionToken == null) return;

    final client = _client;
    if (client == null || !client.isConnected) {
      await _recoverHostSession(reason: 'app_resumed');
      return;
    }

    final alive = await client.probe();
    if (!alive || !client.isHealthy) {
      await _recoverHostSession(reason: 'app_resumed_probe_failed');
      return;
    }

    try {
      await _ensureSessionOnServer(waitForAck: true);
      _broadcastState();
    } catch (error) {
      debugPrint('Host ensure after resume failed: $error');
      await _recoverHostSession(reason: 'app_resumed_ensure_failed');
    }
  }

  Future<void> _waitUntilConnected({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (state.connected) return;
      if (state.error != null) {
        throw StateError(state.error!);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Timed out waiting for session connection');
  }

  Future<void> _connect({required String serverUrl}) async {
    _client?.removeDisconnectListener(_disconnectListener);
    _client?.removeHandler(_messageHandler);
    await _client?.disconnect();

    _dialServerUrl = serverUrl;
    _client = SessionClient(serverUrl: serverUrl);
    _client!.addHandler(_messageHandler);
    _client!.addDisconnectListener(_disconnectListener);
    await _client!.connect();
  }

  void _onHostSocketDisconnected() {
    if (_endingSession || _recoverInFlight) return;
    if (state.sessionId == null || state.sessionToken == null) return;
    unawaited(_recoverHostSession(reason: 'socket_closed'));
  }

  String get _recoverDialUrl =>
      _dialServerUrl ?? state.serverUrl;

  Future<void> _recoverHostSession({required String reason}) async {
    if (_endingSession || _recoverInFlight) return;
    final sessionId = state.sessionId;
    final sessionToken = state.sessionToken;
    final hostGoogleSub = state.hostGoogleSub ?? ref.read(authUserProvider)?.id;
    final serverUrl = _recoverDialUrl;
    if (sessionId == null ||
        sessionToken == null ||
        hostGoogleSub == null ||
        hostGoogleSub.isEmpty) {
      debugPrint('Host recover skipped ($reason): missing credentials');
      return;
    }

    _recoverInFlight = true;
    _stopEnsureTimer();
    state = state.copyWith(
      connected: false,
      isReconnecting: true,
      clearError: true,
    );
    debugPrint('Host session recovering ($reason) via $serverUrl');

    Object? lastError;
    try {
      for (var attempt = 1; attempt <= 8; attempt++) {
        if (_endingSession) return;
        try {
          await _connect(serverUrl: serverUrl);
          await _ensureSessionOnServer(
            sessionId: sessionId,
            sessionToken: sessionToken,
            hostGoogleSub: hostGoogleSub,
            waitForAck: true,
          );
          state = state.copyWith(
            connected: true,
            isReconnecting: false,
            clearError: true,
          );
          _startEnsureTimer();
          _broadcastState();
          debugPrint('Host session recovered on attempt $attempt');
          return;
        } catch (error) {
          lastError = error;
          debugPrint('Host recover attempt $attempt failed: $error');
          await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
        }
      }
      if (mounted) {
        state = state.copyWith(
          connected: false,
          isReconnecting: false,
          error: lastError?.toString() ?? 'Could not restore host session',
        );
      }
    } finally {
      _recoverInFlight = false;
    }
  }

  void _startEnsureTimer() {
    _ensureTimer?.cancel();
    _ensureTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_tickEnsureSession());
    });
  }

  void _stopEnsureTimer() {
    _ensureTimer?.cancel();
    _ensureTimer = null;
  }

  Future<void> _tickEnsureSession() async {
    if (_endingSession || _recoverInFlight) return;
    if (state.sessionId == null || state.sessionToken == null) return;

    final client = _client;
    if (client == null || !client.isConnected || !client.isHealthy) {
      await _recoverHostSession(reason: 'ensure_unhealthy');
      return;
    }

    try {
      await _ensureSessionOnServer(waitForAck: true);
      // If the relay had to recreate the session, push live playlist/state.
      _broadcastState();
    } catch (error) {
      debugPrint('Host ensure failed: $error');
      await _recoverHostSession(reason: 'ensure_failed');
    }
  }

  Future<void> _ensureSessionOnServer({
    String? sessionId,
    String? sessionToken,
    String? hostGoogleSub,
    bool waitForAck = false,
  }) async {
    final id = sessionId ?? state.sessionId;
    final token = sessionToken ?? state.sessionToken;
    final hostId =
        hostGoogleSub ?? state.hostGoogleSub ?? ref.read(authUserProvider)?.id;
    final client = _client;
    if (id == null || token == null || hostId == null || client == null) {
      throw StateError('Missing host session credentials');
    }
    if (!client.isConnected) {
      throw StateError('Host socket is not connected');
    }

    Completer<void>? ack;
    late final void Function(Map<String, dynamic>) handler;
    if (waitForAck) {
      ack = Completer<void>();
      handler = (message) {
        final type = message['type'] as String?;
        if (type == 'host.reconnected' || type == 'host.started') {
          if (!ack!.isCompleted) ack.complete();
        } else if (type == 'error' && !ack!.isCompleted) {
          final payload = message['payload'] as Map<String, dynamic>?;
          ack.completeError(
            StateError(payload?['message'] as String? ?? 'Ensure failed'),
          );
        }
      };
      client.addHandler(handler);
    }

    // Credentials only — playlist is pushed afterward via host.state so a
    // schema mismatch cannot block session restore after a relay restart.
    client.send(
      HostReconnectMessage(
        sessionId: id,
        sessionToken: token,
        hostGoogleSub: hostId,
      ).toJson(),
    );

    if (ack == null) return;
    try {
      await ack.future.timeout(const Duration(seconds: 10));
    } finally {
      client.removeHandler(handler);
    }
  }

  void _handleServerMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case 'host.started':
        final payload = message['payload'] as Map<String, dynamic>;
        final sessionId = payload['sessionId'] as String;
        final sessionToken = payload['sessionToken'] as String;
        state = state.copyWith(
          sessionId: sessionId,
          sessionToken: sessionToken,
          connected: true,
          clearError: true,
        );
        _persistSession();
        _broadcastState();
        _startReorderTimer();
        _startEnsureTimer();
      case 'host.reconnected':
        state = state.copyWith(
          connected: true,
          isReconnecting: false,
          clearError: true,
        );
        _startReorderTimer();
        _startEnsureTimer();
        // Always push live state after reconnect/ensure — covers recreate and
        // keeps connectors in sync after a relay blip.
        _broadcastState();
      case 'host.state':
        // Host is the source of truth — ignore echoed/state snapshots meant for
        // connectors so local playback metadata cannot be overwritten.
        break;
      case 'relay':
        final original =
            (message['payload'] as Map<String, dynamic>)['original']
                as Map<String, dynamic>;
        _handleRelay(original);
      case 'session.ended':
        if (_recoverInFlight || _endingSession) break;
        final reason =
            (message['payload'] as Map<String, dynamic>?)?['reason'];
        if (reason == 'host_ended') {
          state = state.copyWith(connected: false, error: 'Session ended');
          _stopReorderTimer();
          _stopEnsureTimer();
        } else {
          unawaited(_recoverHostSession(reason: 'session_ended_$reason'));
        }
      case 'error':
        final payload = message['payload'] as Map<String, dynamic>;
        final code = payload['code'] as String?;
        final errorMessage = payload['message'] as String?;
        if (code == 'SESSION_NOT_FOUND' &&
            state.sessionId != null &&
            !_endingSession) {
          unawaited(_recoverHostSession(reason: 'session_not_found'));
          break;
        }
        if (!_recoverInFlight) {
          state = state.copyWith(error: errorMessage);
        }
      default:
        break;
    }
  }

  void _handleRelay(Map<String, dynamic> original) {
    final type = original['type'] as String?;
    switch (type) {
      case 'connector.join':
        final payload = original['payload'] as Map<String, dynamic>? ?? {};
        final from = original['from'] as Map<String, dynamic>?;
        final deviceId =
            (from?['deviceId'] ?? payload['deviceId'])?.toString() ?? '';
        final displayName =
            (from?['displayName'] ?? payload['displayName'])?.toString() ??
                'Guest';
        if (deviceId.isEmpty) return;
        _registerConnector(
          deviceId: deviceId,
          displayName: displayName,
          fromJoin: true,
        );
      case 'connector.leave':
        final payload = original['payload'] as Map<String, dynamic>?;
        final from = original['from'] as Map<String, dynamic>?;
        final deviceId =
            (payload?['deviceId'] ?? from?['deviceId'])?.toString();
        if (deviceId != null && deviceId.isNotEmpty) {
          final connectors =
              state.state.connectors.where((c) => c.deviceId != deviceId).toList();
          final pending = state.pendingConnections
              .where((c) => c.deviceId != deviceId)
              .toList();
          state = state.copyWith(pendingConnections: pending);
          _updateState(state.state.copyWith(connectors: connectors));
        }
      case 'connector.request':
        final payload = original['payload'] as Map<String, dynamic>;
        final track = Track.fromJson(payload['track'] as Map<String, dynamic>);
        final from = original['from'] as Map<String, dynamic>?;
        final deviceId = from?['deviceId']?.toString() ?? '';
        final displayName = from?['displayName']?.toString() ?? 'Guest';
        if (deviceId.isEmpty) return;

        if (state.state.settings.requireConnectionApproval &&
            !_isConnectorApproved(deviceId)) {
          // Surface this person on the Request tab even if join was missed.
          _registerConnector(
            deviceId: deviceId,
            displayName: displayName,
            fromJoin: false,
          );
          return;
        }

        final request = SongRequest(
          id: const Uuid().v4(),
          track: track,
          requestedBy: displayName,
          deviceId: deviceId,
          requestedAt: DateTime.now().millisecondsSinceEpoch,
        );
        if (state.state.settings.allowSuggestions) {
          _updateState(
            state.state.copyWith(
              pendingRequests: [...state.state.pendingRequests, request],
            ),
          );
          if (state.state.settings.autoApproveRequests) {
            approveRequest(request.id, 'bottom');
          }
        }
      case 'connector.vote':
        if (!state.state.settings.allowVoting) return;
        final payload = original['payload'] as Map<String, dynamic>;
        final songId = payload['songId'] as String;
        final action = payload['action'] as String;
        final from = original['from'] as Map<String, dynamic>?;
        final deviceId = from?['deviceId']?.toString() ?? '';
        if (deviceId.isEmpty || !_isConnectorApproved(deviceId)) return;

        final deviceVotes = _votesByDevice.putIfAbsent(deviceId, () => {});
        final scores = Map<String, int>.from(state.state.voteScores);

        if (action == 'add' && !deviceVotes.contains(songId)) {
          deviceVotes.add(songId);
          scores[songId] = (scores[songId] ?? 0) + 1;
        } else if (action == 'remove' && deviceVotes.contains(songId)) {
          deviceVotes.remove(songId);
          scores[songId] = (scores[songId] ?? 1) - 1;
          if (scores[songId]! <= 0) scores.remove(songId);
        }

        _updateState(state.state.copyWith(voteScores: scores));
        if (state.state.settings.autoReorderByVotes) {
          _applyVoteReorder();
        }
      default:
        break;
    }
  }

  void _registerConnector({
    required String deviceId,
    required String displayName,
    required bool fromJoin,
  }) {
    final needsApproval = state.state.settings.requireConnectionApproval;
    final connector = ConnectorInfo(
      deviceId: deviceId,
      displayName: displayName,
      approved: !needsApproval,
    );

    final connectors = [...state.state.connectors];
    connectors.removeWhere((c) => c.deviceId == deviceId);
    connectors.add(connector);

    var pending = [...state.pendingConnections];
    pending.removeWhere((c) => c.deviceId == deviceId);
    if (needsApproval) {
      pending = [...pending, connector];
    }

    state = state.copyWith(pendingConnections: pending);
    _updateState(state.state.copyWith(connectors: connectors));
    debugPrint(
      'connector ${fromJoin ? "join" : "request"}: $displayName '
      'needsApproval=$needsApproval pending=${pending.length}',
    );
  }

  void _startReorderTimer() {
    _reorderTimer?.cancel();
    _reorderTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (state.state.settings.autoReorderByVotes) {
        _applyVoteReorder();
      }
    });
  }

  void _stopReorderTimer() {
    _reorderTimer?.cancel();
    _reorderTimer = null;
  }

  void _applyVoteReorder() {
    final playlist = List<Track>.from(state.state.playlist);
    if (playlist.isEmpty) return;

    final currentIndex = state.state.nowPlayingIndex;
    if (currentIndex < 0 || currentIndex >= playlist.length) return;

    final upcoming = playlist.sublist(currentIndex + 1);
    if (upcoming.isEmpty) return;

    upcoming.sort((a, b) {
      final scoreCompare =
          (state.state.voteScores[b.id] ?? 0).compareTo(state.state.voteScores[a.id] ?? 0);
      if (scoreCompare != 0) return scoreCompare;
      return (_trackAddedAt[a.id] ?? 0).compareTo(_trackAddedAt[b.id] ?? 0);
    });

    _updateState(
      state.state.copyWith(
        playlist: [
          ...playlist.sublist(0, currentIndex + 1),
          ...upcoming,
        ],
      ),
    );
  }

  Future<void> endSession() async {
    _endingSession = true;
    _stopEnsureTimer();
    final sessionId = state.sessionId;
    if (sessionId != null) {
      _client?.send(HostEndMessage(sessionId: sessionId).toJson());
    }
    await _cleanupSession(persist: false);
    _endingSession = false;
  }

  Future<void> _cleanupSession({required bool persist}) async {
    _stopReorderTimer();
    _stopEnsureTimer();
    _client?.removeDisconnectListener(_disconnectListener);
    _client?.removeHandler(_messageHandler);
    await _client?.disconnect();
    _client = null;
    _dialServerUrl = null;
    final relay = ref.read(localRelayServerProvider);
    if (relay.isRunning) {
      await relay.stop();
    }
    if (!persist) {
      final persistence = await ref.read(sessionPersistenceProvider.future);
      await persistence.clearHostSession();
    }
    state = HostSessionState();
  }

  Future<void> _persistSession() async {
    final user = ref.read(authUserProvider);
    if (state.sessionId == null || state.sessionToken == null) {
      return;
    }
    final hostId = user?.id ?? state.sessionId!;
    final persistence = await ref.read(sessionPersistenceProvider.future);
    await persistence.saveHostSession(
      sessionId: state.sessionId!,
      sessionToken: state.sessionToken!,
      serverUrl: state.serverUrl,
      hostGoogleSub: hostId,
    );
  }

  void _broadcastState() {
    final sessionId = state.sessionId;
    if (sessionId == null || _client == null) return;
    _client!.send(HostStateMessage(sessionId: sessionId, state: state.state).toJson());
  }

  void _updateState(HostState newState) {
    state = state.copyWith(state: newState);
    _broadcastState();
  }

  void setAllowSuggestions(bool value) {
    final settings = state.state.settings.copyWith(allowSuggestions: value);
    _updateState(state.state.copyWith(settings: settings));
    unawaited(_persistHostSettings(settings));
  }

  void updateSettings(HostSettings settings) {
    var connectors = state.state.connectors;
    var pending = state.pendingConnections;
    if (!settings.requireConnectionApproval &&
        state.state.settings.requireConnectionApproval) {
      connectors = connectors
          .map((connector) => connector.copyWith(approved: true))
          .toList();
      pending = const [];
    }
    state = state.copyWith(pendingConnections: pending);
    _updateState(
      state.state.copyWith(settings: settings, connectors: connectors),
    );
    unawaited(_persistHostSettings(settings));
  }

  Future<void> restoreDefaultSettings() async {
    updateSettings(HostSettings.defaults);
  }

  Future<void> _persistHostSettings(HostSettings settings) async {
    final persistence = await ref.read(sessionPersistenceProvider.future);
    await persistence.saveHostSettings(settings);
  }

  void addTrack(Track track) {
    _trackAddedAt[track.id] = DateTime.now().millisecondsSinceEpoch;
    _updateState(state.state.copyWith(playlist: [...state.state.playlist, track]));
  }

  void replacePlaylist(List<Track> tracks) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _trackAddedAt
      ..clear()
      ..addEntries(
        tracks.map((track) => MapEntry(track.id, now)),
      );
    _updateState(
      state.state.copyWith(
        playlist: List<Track>.from(tracks),
        nowPlayingIndex: tracks.isEmpty ? -1 : 0,
        isPlaying: false,
        positionMs: 0,
        durationMs: 0,
        voteScores: {},
      ),
    );
  }

  void removeTrackAt(int index) {
    final playlist = List<Track>.from(state.state.playlist);
    if (index < 0 || index >= playlist.length) return;
    playlist.removeAt(index);
    var nowPlayingIndex = state.state.nowPlayingIndex;
    if (index < nowPlayingIndex) nowPlayingIndex--;
    if (index == nowPlayingIndex) nowPlayingIndex = playlist.isEmpty ? -1 : nowPlayingIndex.clamp(0, playlist.length - 1);
    _updateState(state.state.copyWith(playlist: playlist, nowPlayingIndex: nowPlayingIndex));
  }

  void moveTrack(int oldIndex, int newIndex) {
    final playlist = List<Track>.from(state.state.playlist);
    if (oldIndex < 0 ||
        oldIndex >= playlist.length ||
        newIndex < 0 ||
        newIndex >= playlist.length) {
      return;
    }
    final track = playlist.removeAt(oldIndex);
    playlist.insert(newIndex, track);

    var nowPlayingIndex = state.state.nowPlayingIndex;
    if (nowPlayingIndex == oldIndex) {
      nowPlayingIndex = newIndex;
    } else if (oldIndex < nowPlayingIndex && newIndex >= nowPlayingIndex) {
      nowPlayingIndex--;
    } else if (oldIndex > nowPlayingIndex && newIndex <= nowPlayingIndex) {
      nowPlayingIndex++;
    }

    _updateState(state.state.copyWith(playlist: playlist, nowPlayingIndex: nowPlayingIndex));
  }

  void moveTrackToTop(int index) {
    if (index <= 0) return;
    moveTrack(index, 0);
  }

  void moveTrackToBottom(int index) {
    final last = state.state.playlist.length - 1;
    if (index < 0 || index >= last) return;
    moveTrack(index, last);
  }

  void approveRequest(String requestId, String placement) {
    final requests = List<SongRequest>.from(state.state.pendingRequests);
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index == -1) return;
    final request = requests.removeAt(index);
    _trackAddedAt[request.track.id] = DateTime.now().millisecondsSinceEpoch;

    final playlist = List<Track>.from(state.state.playlist);
    if (placement == 'top') {
      playlist.insert(0, request.track);
    } else {
      playlist.add(request.track);
    }

    _updateState(state.state.copyWith(playlist: playlist, pendingRequests: requests));
    _client?.send(
      HostApproveMessage(
        sessionId: state.sessionId!,
        requestId: requestId,
        placement: placement,
      ).toJson(),
    );
  }

  void rejectRequest(String requestId) {
    final requests =
        state.state.pendingRequests.where((r) => r.id != requestId).toList();
    _updateState(state.state.copyWith(pendingRequests: requests));
  }

  bool _isConnectorApproved(String deviceId) {
    if (deviceId.isEmpty) return false;
    if (!state.state.settings.requireConnectionApproval) return true;
    final connector = state.state.connectors
        .where((c) => c.deviceId == deviceId)
        .firstOrNull;
    return connector?.approved ?? false;
  }

  void approveConnector(String deviceId) {
    final connectors = state.state.connectors.map((connector) {
      if (connector.deviceId != deviceId) return connector;
      return connector.copyWith(approved: true);
    }).toList();
    final pending =
        state.pendingConnections.where((c) => c.deviceId != deviceId).toList();
    state = state.copyWith(pendingConnections: pending);
    _updateState(state.state.copyWith(connectors: connectors));
  }

  void rejectConnector(String deviceId) {
    final connectors =
        state.state.connectors.where((c) => c.deviceId != deviceId).toList();
    final pending =
        state.pendingConnections.where((c) => c.deviceId != deviceId).toList();
    final requests = state.state.pendingRequests
        .where((r) => r.deviceId != deviceId)
        .toList();
    _votesByDevice.remove(deviceId);
    state = state.copyWith(pendingConnections: pending);
    _updateState(
      state.state.copyWith(connectors: connectors, pendingRequests: requests),
    );
  }

  void updatePlayback({
    int? nowPlayingIndex,
    bool? isPlaying,
    int? positionMs,
    int? durationMs,
    bool broadcast = true,
  }) {
    state = state.copyWith(
      state: state.state.copyWith(
        nowPlayingIndex: nowPlayingIndex,
        isPlaying: isPlaying,
        positionMs: positionMs,
        durationMs: durationMs,
      ),
    );
    if (broadcast) {
      _broadcastState();
    }
  }

  QrPayload get qrPayload => QrPayload(
        serverUrl: state.serverUrl,
        sessionId: state.sessionId ?? '',
      );

  @override
  void dispose() {
    _endingSession = true;
    _stopReorderTimer();
    _stopEnsureTimer();
    _client?.removeDisconnectListener(_disconnectListener);
    _client?.removeHandler(_messageHandler);
    _client?.disconnect();
    final relay = ref.read(localRelayServerProvider);
    if (relay.isRunning) {
      unawaited(relay.stop());
    }
    final current = _musicProvider;
    if (current is YouTubeMusicProvider) {
      current.dispose();
    }
    super.dispose();
  }
}

final hostSessionProvider =
    StateNotifierProvider<HostSessionController, HostSessionState>((ref) {
  return HostSessionController(ref);
});

class ConnectSessionState {
  ConnectSessionState({
    this.connected = false,
    this.sessionId,
    String? serverUrl,
    this.displayName,
    this.deviceId,
    this.invitePayload,
    this.state = const HostState(
      sessionName: 'Share List Session',
      playlist: [],
      nowPlayingIndex: -1,
      isPlaying: false,
      positionMs: 0,
      durationMs: 0,
      settings: HostSettings(),
      voteScores: {},
      pendingRequests: [],
      connectors: [],
    ),
    this.error,
    this.votedSongIds = const {},
    this.isReconnecting = false,
    this.forceReturnHome = false,
  }) : serverUrl = serverUrl ?? defaultServerUrl;

  final bool connected;
  final String? sessionId;
  final String serverUrl;
  final String? displayName;
  final String? deviceId;

  /// Raw QR / join-link text for this live session (replayed on reconnect).
  final String? invitePayload;
  final HostState state;
  final String? error;
  final Set<String> votedSongIds;
  final bool isReconnecting;
  /// When true, ConnectShell should leave and navigate to `/`.
  final bool forceReturnHome;

  ConnectorInfo? get selfConnector {
    final id = deviceId;
    if (id == null) return null;
    for (final connector in state.connectors) {
      if (connector.deviceId == id) return connector;
    }
    return null;
  }

  bool get isConnectionApproved {
    if (!state.settings.requireConnectionApproval) return true;
    return selfConnector?.approved ?? false;
  }

  bool get isAwaitingConnectionApproval {
    if (!connected || !state.settings.requireConnectionApproval) return false;
    final self = selfConnector;
    return self == null || !self.approved;
  }

  ConnectSessionState copyWith({
    bool? connected,
    String? sessionId,
    String? serverUrl,
    String? displayName,
    String? deviceId,
    String? invitePayload,
    HostState? state,
    String? error,
    Set<String>? votedSongIds,
    bool? isReconnecting,
    bool? forceReturnHome,
    bool clearError = false,
  }) {
    return ConnectSessionState(
      connected: connected ?? this.connected,
      sessionId: sessionId ?? this.sessionId,
      serverUrl: serverUrl ?? this.serverUrl,
      displayName: displayName ?? this.displayName,
      deviceId: deviceId ?? this.deviceId,
      invitePayload: invitePayload ?? this.invitePayload,
      state: state ?? this.state,
      error: clearError ? null : (error ?? this.error),
      votedSongIds: votedSongIds ?? this.votedSongIds,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      forceReturnHome: forceReturnHome ?? this.forceReturnHome,
    );
  }
}

class ConnectSessionController extends StateNotifier<ConnectSessionState> {
  ConnectSessionController(this.ref) : super(ConnectSessionState()) {
    _musicProvider = createMusicProvider(
      state.serverUrl,
      useRemoteSearch: !kIsWeb,
    );
    _messageHandler = _handleServerMessage;
    _disconnectListener = _onSocketDisconnected;
  }

  final Ref ref;
  late MusicProvider _musicProvider;
  SessionClient? _client;
  late final void Function(Map<String, dynamic>) _messageHandler;
  late final VoidCallback _disconnectListener;
  bool _appearedInConnectorList = false;
  bool _suppressDisconnectHandling = false;
  bool _reconnectInFlight = false;
  Completer<void>? _joinCompleter;

  MusicProvider get musicProvider => _musicProvider;

  /// Join exactly like scanning a QR / opening a share link.
  Future<void> joinFromInvite({
    required SessionInvite invite,
    required String displayName,
    required String deviceId,
    String? invitePayload,
    bool preserveVotes = false,
  }) async {
    final payload = (invitePayload ?? invite.payload).trim();
    final parsed = SessionInvite.tryParse(payload) ?? invite;

    state = state.copyWith(
      invitePayload: payload,
      displayName: displayName,
      deviceId: deviceId,
      clearError: true,
    );

    try {
      final persistence = await ref.read(sessionPersistenceProvider.future);
      await persistence.saveActiveConnectorInvite(
        ActiveConnectorInvite(
          invitePayload: payload,
          displayName: displayName,
          deviceId: deviceId,
        ),
      );
    } catch (_) {
      // Persistence failures should not block joining.
    }

    await _attachAndJoin(
      serverUrl: parsed.serverUrl,
      sessionId: parsed.sessionId,
      displayName: displayName,
      deviceId: deviceId,
      preserveVotes: preserveVotes,
    );
  }

  /// Back-compat for call sites that still pass discrete fields.
  Future<void> joinSession({
    required String serverUrl,
    required String sessionId,
    required String displayName,
    required String deviceId,
    String? invitePayload,
  }) async {
    final invite = SessionInvite(
      sessionId: sessionId,
      serverUrl: SessionInvite.normalizeServerUrl(serverUrl),
    );
    await joinFromInvite(
      invite: invite,
      displayName: displayName,
      deviceId: deviceId,
      invitePayload: invitePayload ?? invite.payload,
    );
  }

  /// Called when the app returns to the foreground while in connect mode.
  Future<void> handleAppResumed() async {
    if (state.forceReturnHome) return;
    if (state.sessionId == null && state.invitePayload == null) return;
    if (_reconnectInFlight) return;

    final client = _client;
    if (client != null && client.isConnected) {
      final alive = await client.probe();
      if (alive && client.isHealthy) return;
      debugPrint('Connect probe failed after resume — rejoining via invite');
    }

    await _recoverConnection(reason: 'app_resumed');
  }

  void _onSocketDisconnected() {
    if (_suppressDisconnectHandling) return;
    if (state.forceReturnHome) return;
    if (state.sessionId == null && state.invitePayload == null) return;
    if (_reconnectInFlight) return;
    unawaited(_recoverConnection(reason: 'socket_closed'));
  }

  /// Reconnect by replaying the same invite join used after scanning the QR.
  Future<void> _recoverConnection({required String reason}) async {
    if (_reconnectInFlight || _suppressDisconnectHandling || state.forceReturnHome) {
      return;
    }

    _reconnectInFlight = true;
    state = state.copyWith(
      connected: false,
      isReconnecting: true,
      clearError: true,
    );
    debugPrint('Connect rejoining via saved invite ($reason)');

    Object? lastError;
    try {
      for (var attempt = 1; attempt <= 8; attempt++) {
        if (state.forceReturnHome) return;

        final active = await _resolveActiveInvite();
        if (active == null) {
          lastError = StateError('No saved invite to rejoin');
          break;
        }
        final invite = active.invite;
        if (invite == null) {
          lastError = StateError('Saved invite is invalid');
          break;
        }

        try {
          await joinFromInvite(
            invite: invite,
            displayName: active.displayName,
            deviceId: active.deviceId,
            invitePayload: active.invitePayload,
            preserveVotes: true,
          );
          if (state.forceReturnHome) return;
          state = state.copyWith(
            connected: true,
            isReconnecting: false,
            clearError: true,
          );
          debugPrint('Connect rejoined on attempt $attempt');
          return;
        } catch (error) {
          if (state.forceReturnHome) return;
          lastError = error;
          debugPrint('Connect rejoin attempt $attempt failed: $error');
          final message = error.toString().toLowerCase();
          final hostGone = message.contains('no longer available') ||
              message.contains('session not found') ||
              message.contains('session has ended') ||
              message.contains('host ended');
          if (hostGone && attempt >= 3) break;
          await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
        }
      }

      if (!state.forceReturnHome) {
        await _markSessionLost(
          lastError?.toString() ?? 'Host is no longer available',
        );
      }
    } finally {
      _reconnectInFlight = false;
      if (mounted && !state.forceReturnHome) {
        state = state.copyWith(isReconnecting: false);
      }
    }
  }

  Future<ActiveConnectorInvite?> _resolveActiveInvite() async {
    final payload = state.invitePayload;
    final displayName = state.displayName;
    final deviceId = state.deviceId;
    if (payload != null &&
        payload.isNotEmpty &&
        displayName != null &&
        displayName.isNotEmpty &&
        deviceId != null &&
        deviceId.isNotEmpty) {
      return ActiveConnectorInvite(
        invitePayload: payload,
        displayName: displayName,
        deviceId: deviceId,
      );
    }

    try {
      final persistence = await ref.read(sessionPersistenceProvider.future);
      return persistence.loadActiveConnectorInvite();
    } catch (_) {
      return null;
    }
  }

  Future<void> _attachAndJoin({
    required String serverUrl,
    required String sessionId,
    required String displayName,
    required String deviceId,
    required bool preserveVotes,
  }) async {
    _suppressDisconnectHandling = true;
    final previousClient = _client;
    try {
      previousClient?.removeDisconnectListener(_disconnectListener);
      previousClient?.removeHandler(_messageHandler);
      await previousClient?.disconnect();
      _appearedInConnectorList = false;

      final current = _musicProvider;
      if (current is YouTubeMusicProvider) {
        current.dispose();
      }
      _musicProvider = createMusicProvider(
        serverUrl,
        useRemoteSearch: !kIsWeb,
      );

      final client = SessionClient(serverUrl: serverUrl);
      _client = client;
      client.addHandler(_messageHandler);
      client.addDisconnectListener(_disconnectListener);
      await client.connect();

      if (state.forceReturnHome) {
        throw StateError('Session already ended');
      }

      final votes = preserveVotes ? state.votedSongIds : const <String>{};
      state = state.copyWith(
        serverUrl: serverUrl,
        sessionId: sessionId,
        displayName: displayName,
        deviceId: deviceId,
        votedSongIds: votes,
        clearError: true,
      );

      final join = Completer<void>();
      _joinCompleter = join;
      client.send(
        ConnectorJoinMessage(
          sessionId: sessionId,
          displayName: displayName,
          deviceId: deviceId,
        ).toJson(),
      );

      try {
        await join.future.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        _joinCompleter = null;
        throw StateError('Timed out rejoining the host session');
      } finally {
        if (identical(_joinCompleter, join)) {
          _joinCompleter = null;
        }
      }
    } finally {
      if (!state.forceReturnHome) {
        _suppressDisconnectHandling = false;
      }
    }
  }

  void _completeJoin([Object? error]) {
    final join = _joinCompleter;
    if (join == null || join.isCompleted) return;
    if (error != null) {
      join.completeError(error);
    } else {
      join.complete();
    }
  }

  Future<void> _markSessionLost(String message) async {
    _suppressDisconnectHandling = true;
    // Flip this first so UI exits reconnecting and recover loops stop.
    if (mounted) {
      state = state.copyWith(
        forceReturnHome: true,
        isReconnecting: false,
        connected: false,
        error: _friendlyLostMessage(message),
      );
    }
    _completeJoin(StateError(message));
    final sessionId = state.sessionId;
    final client = _client;
    client?.removeDisconnectListener(_disconnectListener);
    client?.removeHandler(_messageHandler);
    if (sessionId != null && client != null && client.isConnected) {
      client.send(ConnectorLeaveMessage(sessionId: sessionId).toJson());
    }
    await client?.disconnect();
    if (identical(_client, client)) {
      _client = null;
    }
    _appearedInConnectorList = false;
    _reconnectInFlight = false;
    unawaited(_clearActiveInvite());
  }

  String _friendlyLostMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('no longer available') ||
        lower.contains('session not found') ||
        lower.contains('session has ended') ||
        lower.contains('host ended') ||
        lower.contains('could not connect')) {
      return 'Host is no longer available';
    }
    return 'Connection to the session was lost';
  }

  void _handleServerMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case 'connector.joined':
        if (state.forceReturnHome) return;
        final payload = message['payload'] as Map<String, dynamic>;
        state = state.copyWith(
          connected: true,
          isReconnecting: false,
          state: HostState.fromJson(payload['state'] as Map<String, dynamic>),
          clearError: true,
        );
        _syncApprovalStatus();
        _completeJoin();
        unawaited(_rememberCurrentConnection());
      case 'host.state':
        if (state.forceReturnHome) return;
        final payload = message['payload'] as Map<String, dynamic>;
        state = state.copyWith(state: HostState.fromJson(payload));
        _syncApprovalStatus();
      case 'relay':
        final original =
            (message['payload'] as Map<String, dynamic>)['original'] as Map<String, dynamic>;
        if (original['type'] == 'host.approve') {
          // State will arrive via host.state broadcast.
        }
      case 'session.ended':
        final payload = message['payload'] as Map<String, dynamic>?;
        final reason = payload?['message'] as String? ?? 'Session ended by host';
        unawaited(_markSessionLost(reason));
      case 'error':
        final payload = message['payload'] as Map<String, dynamic>;
        final errorMessage =
            payload['message'] as String? ?? 'Connection error';
        _completeJoin(StateError(errorMessage));
        if (!_reconnectInFlight) {
          state = state.copyWith(error: errorMessage);
        }
      default:
        break;
    }
  }

  void _syncApprovalStatus() {
    if (state.isReconnecting || state.forceReturnHome || !state.connected) {
      return;
    }
    final self = state.selfConnector;
    if (self != null) {
      _appearedInConnectorList = true;
      return;
    }
    // Only treat disappearance as a decline after we were listed and the host
    // requires approval. Skip while the membership list may still be catching up
    // after a soft rejoin.
    if (_appearedInConnectorList &&
        state.state.settings.requireConnectionApproval) {
      unawaited(_markSessionLost('Host declined your connection'));
    }
  }

  Future<void> leaveSession() async {
    _suppressDisconnectHandling = true;
    _completeJoin(StateError('left'));
    final sessionId = state.sessionId;
    if (sessionId != null) {
      _client?.send(ConnectorLeaveMessage(sessionId: sessionId).toJson());
    }
    _client?.removeDisconnectListener(_disconnectListener);
    _client?.removeHandler(_messageHandler);
    await _client?.disconnect();
    _client = null;
    _appearedInConnectorList = false;
    _reconnectInFlight = false;
    await _clearActiveInvite();
    state = ConnectSessionState();
    _suppressDisconnectHandling = false;
  }

  Future<void> _clearActiveInvite() async {
    try {
      final persistence = await ref.read(sessionPersistenceProvider.future);
      await persistence.clearActiveConnectorInvite();
    } catch (_) {}
  }

  Future<void> _rememberCurrentConnection() async {
    final sessionId = state.sessionId;
    if (sessionId == null || !state.connected) return;
    try {
      final persistence = await ref.read(sessionPersistenceProvider.future);
      await persistence.rememberConnection(
        sessionId: sessionId,
        serverUrl: state.serverUrl,
        sessionName: state.state.sessionName,
        invitePayload: state.invitePayload,
      );
      ref.invalidate(savedConnectionsProvider);
    } catch (_) {
      // Persistence failures should not break the live session.
    }
  }

  void requestTrack(Track track) {
    final sessionId = state.sessionId;
    if (sessionId == null ||
        !state.state.settings.allowSuggestions ||
        !state.isConnectionApproved) {
      return;
    }
    _client?.send(
      ConnectorRequestMessage(sessionId: sessionId, track: track).toJson(),
    );
  }

  void toggleVote(String songId) {
    final sessionId = state.sessionId;
    if (sessionId == null ||
        !state.state.settings.allowVoting ||
        !state.isConnectionApproved) {
      return;
    }

    final voted = Set<String>.from(state.votedSongIds);
    final hasVoted = voted.contains(songId);
    if (hasVoted) {
      voted.remove(songId);
      _client?.send(
        ConnectorVoteMessage(
          sessionId: sessionId,
          songId: songId,
          action: 'remove',
        ).toJson(),
      );
    } else {
      voted.add(songId);
      _client?.send(
        ConnectorVoteMessage(
          sessionId: sessionId,
          songId: songId,
          action: 'add',
        ).toJson(),
      );
    }
    state = state.copyWith(votedSongIds: voted);
  }

  @override
  void dispose() {
    _suppressDisconnectHandling = true;
    _client?.removeDisconnectListener(_disconnectListener);
    _client?.removeHandler(_messageHandler);
    _client?.disconnect();
    final current = _musicProvider;
    if (current is YouTubeMusicProvider) {
      current.dispose();
    }
    super.dispose();
  }
}

final connectSessionProvider =
    StateNotifierProvider<ConnectSessionController, ConnectSessionState>((ref) {
  return ConnectSessionController(ref);
});
