import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/server_config.dart';
import 'session_invite.dart';

/// Default relay URL.
/// Prefer editing [ServerConfig] / `config/server.json`; optional override:
/// `--dart-define=SERVER_URL=ws://192.168.1.10:3000`
String resolveDefaultServerUrl() => ServerConfig.url;

final defaultServerUrl = resolveDefaultServerUrl();

final deviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('device_id');
  if (deviceId == null) {
    deviceId = const Uuid().v4();
    await prefs.setString('device_id', deviceId);
  }
  return deviceId;
});

class SessionPersistence {
  SessionPersistence(this._prefs);

  final SharedPreferences _prefs;

  static const _sessionIdKey = 'host_session_id';
  static const _sessionTokenKey = 'host_session_token';
  static const _serverUrlKey = 'host_server_url';
  static const _hostSubKey = 'host_google_sub';
  static const _savedConnectionsKey = 'saved_connections';
  static const _maxSavedConnections = 20;
  static const _activeConnectorInviteKey = 'active_connector_invite';

  Future<void> saveHostSession({
    required String sessionId,
    required String sessionToken,
    required String serverUrl,
    required String hostGoogleSub,
  }) async {
    await _prefs.setString(_sessionIdKey, sessionId);
    await _prefs.setString(_sessionTokenKey, sessionToken);
    await _prefs.setString(_serverUrlKey, serverUrl);
    await _prefs.setString(_hostSubKey, hostGoogleSub);
  }

  Future<StoredHostSession?> loadHostSession() async {
    final sessionId = _prefs.getString(_sessionIdKey);
    final sessionToken = _prefs.getString(_sessionTokenKey);
    final serverUrl = _prefs.getString(_serverUrlKey);
    final hostSub = _prefs.getString(_hostSubKey);
    if (sessionId == null ||
        sessionToken == null ||
        serverUrl == null ||
        hostSub == null) {
      return null;
    }
    return StoredHostSession(
      sessionId: sessionId,
      sessionToken: sessionToken,
      serverUrl: serverUrl,
      hostGoogleSub: hostSub,
    );
  }

  Future<void> clearHostSession() async {
    await _prefs.remove(_sessionIdKey);
    await _prefs.remove(_sessionTokenKey);
    await _prefs.remove(_serverUrlKey);
    await _prefs.remove(_hostSubKey);
  }

  Future<List<SavedConnection>> loadSavedConnections() async {
    final raw = _prefs.getString(_savedConnectionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => SavedConnection.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> rememberConnection({
    required String sessionId,
    required String serverUrl,
    required String sessionName,
    String? invitePayload,
  }) async {
    final connections = await loadSavedConnections();
    connections.removeWhere(
      (c) => c.sessionId == sessionId && c.serverUrl == serverUrl,
    );
    connections.insert(
      0,
      SavedConnection(
        sessionId: sessionId,
        serverUrl: serverUrl,
        sessionName: sessionName,
        lastConnectedAt: DateTime.now(),
        invitePayload: invitePayload,
      ),
    );
    if (connections.length > _maxSavedConnections) {
      connections.removeRange(_maxSavedConnections, connections.length);
    }
    await _prefs.setString(
      _savedConnectionsKey,
      jsonEncode(connections.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> saveActiveConnectorInvite(ActiveConnectorInvite invite) async {
    await _prefs.setString(
      _activeConnectorInviteKey,
      jsonEncode(invite.toJson()),
    );
  }

  Future<ActiveConnectorInvite?> loadActiveConnectorInvite() async {
    final raw = _prefs.getString(_activeConnectorInviteKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ActiveConnectorInvite.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearActiveConnectorInvite() async {
    await _prefs.remove(_activeConnectorInviteKey);
  }

  Future<void> removeSavedConnection({
    required String sessionId,
    required String serverUrl,
  }) async {
    final connections = await loadSavedConnections();
    connections.removeWhere(
      (c) => c.sessionId == sessionId && c.serverUrl == serverUrl,
    );
    await _prefs.setString(
      _savedConnectionsKey,
      jsonEncode(connections.map((c) => c.toJson()).toList()),
    );
  }

  static const _relayHostKey = 'relay_host';
  static const _relayPortKey = 'relay_port';

  Future<RelayEndpoint> loadRelayEndpoint({
    required String fallbackHost,
    required int fallbackPort,
  }) async {
    final host = _prefs.getString(_relayHostKey)?.trim();
    final port = _prefs.getInt(_relayPortKey);
    return RelayEndpoint(
      host: (host == null || host.isEmpty) ? fallbackHost : host,
      port: (port == null || port <= 0 || port > 65535) ? fallbackPort : port,
    );
  }

  Future<void> saveRelayEndpoint(RelayEndpoint endpoint) async {
    await _prefs.setString(_relayHostKey, endpoint.host);
    await _prefs.setInt(_relayPortKey, endpoint.port);
  }

  static const _localModeKey = 'local_mode_enabled';

  Future<bool> loadLocalModeEnabled() async {
    return _prefs.getBool(_localModeKey) ?? false;
  }

  Future<void> saveLocalModeEnabled(bool enabled) async {
    await _prefs.setBool(_localModeKey, enabled);
  }

  static const _hostSettingsKey = 'host_settings';

  Future<HostSettings> loadHostSettings() async {
    final raw = _prefs.getString(_hostSettingsKey);
    if (raw == null || raw.isEmpty) return HostSettings.defaults;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return HostSettings.fromJson(decoded);
    } catch (_) {
      return HostSettings.defaults;
    }
  }

  Future<void> saveHostSettings(HostSettings settings) async {
    await _prefs.setString(_hostSettingsKey, jsonEncode(settings.toJson()));
  }

  static const _savedPlaylistsKey = 'saved_playlists';
  static const _maxSavedPlaylists = 50;

  Future<List<SavedPlaylist>> loadSavedPlaylists() async {
    final raw = _prefs.getString(_savedPlaylistsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final playlists = decoded
          .map((item) => SavedPlaylist.fromJson(item as Map<String, dynamic>))
          .toList();
      playlists.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return playlists;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePlaylist(SavedPlaylist playlist) async {
    final playlists = await loadSavedPlaylists();
    playlists.removeWhere(
      (item) =>
          item.id == playlist.id ||
          item.name.toLowerCase() == playlist.name.toLowerCase(),
    );
    playlists.insert(0, playlist);
    if (playlists.length > _maxSavedPlaylists) {
      playlists.removeRange(_maxSavedPlaylists, playlists.length);
    }
    await _prefs.setString(
      _savedPlaylistsKey,
      jsonEncode(playlists.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> deleteSavedPlaylist(String id) async {
    final playlists = await loadSavedPlaylists();
    playlists.removeWhere((item) => item.id == id);
    await _prefs.setString(
      _savedPlaylistsKey,
      jsonEncode(playlists.map((item) => item.toJson()).toList()),
    );
  }
}

class RelayEndpoint {
  const RelayEndpoint({
    required this.host,
    required this.port,
  });

  final String host;
  final int port;

  /// WebSocket base URL, e.g. `wss://sharelist.example.com` or `ws://192.168.1.10:3000`.
  String get serverUrl {
    final normalizedHost = host
        .trim()
        .replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '')
        .split('/')
        .first
        .split(':')
        .first;
    final secure = port == 443;
    final scheme = secure ? 'wss' : 'ws';
    if (port == 443 || port == 80) {
      return '$scheme://$normalizedHost';
    }
    return '$scheme://$normalizedHost:$port';
  }

  RelayEndpoint copyWith({String? host, int? port}) => RelayEndpoint(
        host: host ?? this.host,
        port: port ?? this.port,
      );
}

class StoredHostSession {
  const StoredHostSession({
    required this.sessionId,
    required this.sessionToken,
    required this.serverUrl,
    required this.hostGoogleSub,
  });

  final String sessionId;
  final String sessionToken;
  final String serverUrl;
  final String hostGoogleSub;
}

class SavedConnection {
  const SavedConnection({
    required this.sessionId,
    required this.serverUrl,
    required this.sessionName,
    required this.lastConnectedAt,
    this.invitePayload,
  });

  final String sessionId;
  final String serverUrl;
  final String sessionName;
  final DateTime lastConnectedAt;

  /// Raw QR / join-link text used when the connector first joined.
  final String? invitePayload;

  SessionInvite get invite =>
      SessionInvite.tryParse(invitePayload ?? '') ??
      SessionInvite(sessionId: sessionId, serverUrl: serverUrl);

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'serverUrl': serverUrl,
        'sessionName': sessionName,
        'lastConnectedAt': lastConnectedAt.toIso8601String(),
        if (invitePayload != null) 'invitePayload': invitePayload,
      };

  factory SavedConnection.fromJson(Map<String, dynamic> json) =>
      SavedConnection(
        sessionId: json['sessionId'] as String,
        serverUrl: json['serverUrl'] as String,
        sessionName: json['sessionName'] as String? ?? 'Share List Session',
        lastConnectedAt:
            DateTime.tryParse(json['lastConnectedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        invitePayload: json['invitePayload'] as String?,
      );
}

/// Live connector session invite — enough to rejoin exactly like a QR scan.
class ActiveConnectorInvite {
  const ActiveConnectorInvite({
    required this.invitePayload,
    required this.displayName,
    required this.deviceId,
  });

  final String invitePayload;
  final String displayName;
  final String deviceId;

  SessionInvite? get invite => SessionInvite.tryParse(invitePayload);

  Map<String, dynamic> toJson() => {
        'invitePayload': invitePayload,
        'displayName': displayName,
        'deviceId': deviceId,
      };

  factory ActiveConnectorInvite.fromJson(Map<String, dynamic> json) =>
      ActiveConnectorInvite(
        invitePayload: json['invitePayload'] as String,
        displayName: json['displayName'] as String,
        deviceId: json['deviceId'] as String,
      );
}

class SavedPlaylist {
  const SavedPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.savedAt,
  });

  final String id;
  final String name;
  final List<Track> tracks;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((track) => track.toJson()).toList(),
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedPlaylist.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? 'Playlist').trim();
    return SavedPlaylist(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: name.isEmpty ? 'Playlist' : name,
      tracks: (json['tracks'] as List<dynamic>? ?? [])
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList(),
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

final sessionPersistenceProvider = FutureProvider<SessionPersistence>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SessionPersistence(prefs);
});

final savedConnectionsProvider = FutureProvider<List<SavedConnection>>((ref) async {
  final persistence = await ref.watch(sessionPersistenceProvider.future);
  return persistence.loadSavedConnections();
});

final savedPlaylistsProvider = FutureProvider<List<SavedPlaylist>>((ref) async {
  final persistence = await ref.watch(sessionPersistenceProvider.future);
  return persistence.loadSavedPlaylists();
});

/// Parses `ws(s)://host:port` (or similar) into host + port.
RelayEndpoint relayEndpointFromServerUrl(String serverUrl) {
  final trimmed = serverUrl.trim();
  final secure = RegExp(r'^(wss|https)://', caseSensitive: false)
      .hasMatch(trimmed);
  final withoutScheme =
      trimmed.replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '');
  final hostPort = withoutScheme.split('/').first;
  final parts = hostPort.split(':');
  final host = parts.first.isEmpty ? ServerConfig.hostname : parts.first;
  final defaultPort = secure ? 443 : 3000;
  final port = parts.length > 1 ? int.tryParse(parts[1]) ?? defaultPort : defaultPort;
  return RelayEndpoint(host: host, port: port);
}

/// Build-time configured relay (from [ServerConfig]).
RelayEndpoint configuredRelayEndpoint() =>
    relayEndpointFromServerUrl(ServerConfig.url);

bool _isLegacyRelayHost(String host) {
  final normalized = host
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^(wss?|https?)://'), '')
      .split('/')
      .first
      .split(':')
      .first;
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '10.0.2.2' ||
      normalized == '0.0.0.0' ||
      normalized.isEmpty;
}

/// Replaces legacy/dev defaults and keeps the configured production host on the
/// correct port/scheme from [ServerConfig].
RelayEndpoint normalizeRelayEndpoint(RelayEndpoint endpoint) {
  final configured = configuredRelayEndpoint();
  final host = endpoint.host
      .trim()
      .replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '')
      .split('/')
      .first
      .split(':')
      .first;

  if (_isLegacyRelayHost(host)) {
    return configured;
  }

  if (host.toLowerCase() == ServerConfig.hostname.toLowerCase()) {
    return configured;
  }

  return RelayEndpoint(host: host, port: endpoint.port);
}

class RelaySettingsNotifier extends AsyncNotifier<RelayEndpoint> {
  @override
  Future<RelayEndpoint> build() async {
    final fallback = configuredRelayEndpoint();
    final persistence = await ref.watch(sessionPersistenceProvider.future);
    final loaded = await persistence.loadRelayEndpoint(
      fallbackHost: fallback.host,
      fallbackPort: fallback.port,
    );
    final normalized = normalizeRelayEndpoint(loaded);
    if (normalized.host != loaded.host || normalized.port != loaded.port) {
      await persistence.saveRelayEndpoint(normalized);
    }
    return normalized;
  }

  Future<void> save(RelayEndpoint endpoint) async {
    final cleaned = normalizeRelayEndpoint(
      RelayEndpoint(
        host: endpoint.host
            .trim()
            .replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '')
            .split('/')
            .first
            .split(':')
            .first,
        port: endpoint.port,
      ),
    );
    if (cleaned.host.isEmpty) {
      throw ArgumentError('Host cannot be empty');
    }
    if (cleaned.port <= 0 || cleaned.port > 65535) {
      throw ArgumentError('Port must be between 1 and 65535');
    }

    final persistence = await ref.read(sessionPersistenceProvider.future);
    await persistence.saveRelayEndpoint(cleaned);
    state = AsyncValue.data(cleaned);
  }
}

final relaySettingsProvider =
    AsyncNotifierProvider<RelaySettingsNotifier, RelayEndpoint>(
  RelaySettingsNotifier.new,
);

class LocalModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final persistence = await ref.watch(sessionPersistenceProvider.future);
    return persistence.loadLocalModeEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    final persistence = await ref.read(sessionPersistenceProvider.future);
    await persistence.saveLocalModeEnabled(enabled);
    state = AsyncValue.data(enabled);
  }
}

final localModeProvider = AsyncNotifierProvider<LocalModeNotifier, bool>(
  LocalModeNotifier.new,
);
