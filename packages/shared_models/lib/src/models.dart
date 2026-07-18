class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.sourceUrl,
    required this.provider,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String sourceUrl;
  final String provider;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        if (artworkUrl != null) 'artworkUrl': artworkUrl,
        'sourceUrl': sourceUrl,
        'provider': provider,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        artworkUrl: json['artworkUrl'] as String?,
        sourceUrl: json['sourceUrl'] as String,
        provider: json['provider'] as String,
      );

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? artworkUrl,
    String? sourceUrl,
    String? provider,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      provider: provider ?? this.provider,
    );
  }
}

class HostSettings {
  const HostSettings({
    this.allowSuggestions = true,
    this.allowVoting = true,
    this.autoReorderByVotes = false,
    this.autoPlaylistAdvance = true,
    this.autoApproveRequests = false,
    this.requireConnectionApproval = false,
  });

  /// Factory defaults used by new sessions and "Restore defaults".
  static const defaults = HostSettings();

  final bool allowSuggestions;
  final bool allowVoting;
  final bool autoReorderByVotes;
  final bool autoPlaylistAdvance;
  final bool autoApproveRequests;
  final bool requireConnectionApproval;

  Map<String, dynamic> toJson() => {
        'allowSuggestions': allowSuggestions,
        'allowVoting': allowVoting,
        'autoReorderByVotes': autoReorderByVotes,
        'autoPlaylistAdvance': autoPlaylistAdvance,
        'autoApproveRequests': autoApproveRequests,
        'requireConnectionApproval': requireConnectionApproval,
      };

  factory HostSettings.fromJson(Map<String, dynamic> json) => HostSettings(
        allowSuggestions: json['allowSuggestions'] as bool? ?? true,
        allowVoting: json['allowVoting'] as bool? ?? true,
        autoReorderByVotes: json['autoReorderByVotes'] as bool? ?? false,
        autoPlaylistAdvance: json['autoPlaylistAdvance'] as bool? ?? true,
        autoApproveRequests: json['autoApproveRequests'] as bool? ?? false,
        requireConnectionApproval:
            json['requireConnectionApproval'] as bool? ?? false,
      );

  HostSettings copyWith({
    bool? allowSuggestions,
    bool? allowVoting,
    bool? autoReorderByVotes,
    bool? autoPlaylistAdvance,
    bool? autoApproveRequests,
    bool? requireConnectionApproval,
  }) {
    return HostSettings(
      allowSuggestions: allowSuggestions ?? this.allowSuggestions,
      allowVoting: allowVoting ?? this.allowVoting,
      autoReorderByVotes: autoReorderByVotes ?? this.autoReorderByVotes,
      autoPlaylistAdvance: autoPlaylistAdvance ?? this.autoPlaylistAdvance,
      autoApproveRequests: autoApproveRequests ?? this.autoApproveRequests,
      requireConnectionApproval:
          requireConnectionApproval ?? this.requireConnectionApproval,
    );
  }
}

class SongRequest {
  const SongRequest({
    required this.id,
    required this.track,
    required this.requestedBy,
    required this.deviceId,
    required this.requestedAt,
  });

  final String id;
  final Track track;
  final String requestedBy;
  final String deviceId;
  final int requestedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': track.toJson(),
        'requestedBy': requestedBy,
        'deviceId': deviceId,
        'requestedAt': requestedAt,
      };

  factory SongRequest.fromJson(Map<String, dynamic> json) => SongRequest(
        id: json['id'] as String,
        track: Track.fromJson(json['track'] as Map<String, dynamic>),
        requestedBy: json['requestedBy'] as String,
        deviceId: json['deviceId'] as String,
        requestedAt: json['requestedAt'] as int,
      );
}

class ConnectorInfo {
  const ConnectorInfo({
    required this.deviceId,
    required this.displayName,
    this.approved = true,
  });

  final String deviceId;
  final String displayName;
  final bool approved;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'displayName': displayName,
        'approved': approved,
      };

  factory ConnectorInfo.fromJson(Map<String, dynamic> json) => ConnectorInfo(
        deviceId: json['deviceId'] as String,
        displayName: json['displayName'] as String,
        approved: json['approved'] as bool? ?? true,
      );

  ConnectorInfo copyWith({
    String? deviceId,
    String? displayName,
    bool? approved,
  }) {
    return ConnectorInfo(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      approved: approved ?? this.approved,
    );
  }
}

class HostState {
  const HostState({
    required this.sessionName,
    required this.playlist,
    required this.nowPlayingIndex,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.settings,
    required this.voteScores,
    required this.pendingRequests,
    required this.connectors,
  });

  final String sessionName;
  final List<Track> playlist;
  final int nowPlayingIndex;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final HostSettings settings;
  final Map<String, int> voteScores;
  final List<SongRequest> pendingRequests;
  final List<ConnectorInfo> connectors;

  Track? get nowPlaying =>
      nowPlayingIndex >= 0 && nowPlayingIndex < playlist.length
          ? playlist[nowPlayingIndex]
          : null;

  Map<String, dynamic> toJson() => {
        'sessionName': sessionName,
        'playlist': playlist.map((t) => t.toJson()).toList(),
        'nowPlayingIndex': nowPlayingIndex,
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'settings': settings.toJson(),
        'voteScores': voteScores,
        'pendingRequests': pendingRequests.map((r) => r.toJson()).toList(),
        'connectors': connectors.map((c) => c.toJson()).toList(),
      };

  factory HostState.fromJson(Map<String, dynamic> json) => HostState(
        sessionName: json['sessionName'] as String,
        playlist: (json['playlist'] as List<dynamic>)
            .map((e) => Track.fromJson(e as Map<String, dynamic>))
            .toList(),
        nowPlayingIndex: json['nowPlayingIndex'] as int,
        isPlaying: json['isPlaying'] as bool,
        positionMs: json['positionMs'] as int,
        durationMs: json['durationMs'] as int,
        settings: HostSettings.fromJson(
          json['settings'] as Map<String, dynamic>,
        ),
        voteScores: (json['voteScores'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        pendingRequests: (json['pendingRequests'] as List<dynamic>)
            .map((e) => SongRequest.fromJson(e as Map<String, dynamic>))
            .toList(),
        connectors: (json['connectors'] as List<dynamic>)
            .map((e) => ConnectorInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  factory HostState.empty({
    String sessionName = 'Share List Session',
    HostSettings settings = HostSettings.defaults,
  }) =>
      HostState(
        sessionName: sessionName,
        playlist: const [],
        nowPlayingIndex: -1,
        isPlaying: false,
        positionMs: 0,
        durationMs: 0,
        settings: settings,
        voteScores: const {},
        pendingRequests: const [],
        connectors: const [],
      );

  HostState copyWith({
    String? sessionName,
    List<Track>? playlist,
    int? nowPlayingIndex,
    bool? isPlaying,
    int? positionMs,
    int? durationMs,
    HostSettings? settings,
    Map<String, int>? voteScores,
    List<SongRequest>? pendingRequests,
    List<ConnectorInfo>? connectors,
  }) {
    return HostState(
      sessionName: sessionName ?? this.sessionName,
      playlist: playlist ?? this.playlist,
      nowPlayingIndex: nowPlayingIndex ?? this.nowPlayingIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      settings: settings ?? this.settings,
      voteScores: voteScores ?? this.voteScores,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      connectors: connectors ?? this.connectors,
    );
  }
}
