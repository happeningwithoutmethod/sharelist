import 'dart:convert';

import 'models.dart';

abstract class ClientMessage {
  const ClientMessage({required this.type, this.sessionId});

  final String type;
  final String? sessionId;

  Map<String, dynamic> toJson();
}

class HostStartMessage extends ClientMessage {
  HostStartMessage({
    required this.hostGoogleSub,
    this.sessionName,
    this.countryCode,
  }) : super(type: 'host.start');

  final String hostGoogleSub;
  final String? sessionName;
  /// ISO 3166-1 alpha-2, or "unknown" when location is unavailable/denied.
  final String? countryCode;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': {
          'hostGoogleSub': hostGoogleSub,
          if (sessionName != null) 'sessionName': sessionName,
          if (countryCode != null) 'countryCode': countryCode,
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class HostReconnectMessage extends ClientMessage {
  HostReconnectMessage({
    required String sessionId,
    required this.sessionToken,
    required this.hostGoogleSub,
    this.countryCode,
    this.state,
  }) : super(type: 'host.reconnect', sessionId: sessionId);

  final String sessionToken;
  final String hostGoogleSub;
  final String? countryCode;
  final HostState? state;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {
          'sessionId': sessionId,
          'sessionToken': sessionToken,
          'hostGoogleSub': hostGoogleSub,
          if (countryCode != null) 'countryCode': countryCode,
          if (state != null) 'state': state!.toJson(),
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class HostEndMessage extends ClientMessage {
  HostEndMessage({required String sessionId}) : super(type: 'host.end', sessionId: sessionId);

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {},
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class HostStateMessage extends ClientMessage {
  HostStateMessage({required String sessionId, required this.state})
      : super(type: 'host.state', sessionId: sessionId);

  final HostState state;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': state.toJson(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class HostApproveMessage extends ClientMessage {
  HostApproveMessage({
    required String sessionId,
    required this.requestId,
    required this.placement,
  }) : super(type: 'host.approve', sessionId: sessionId);

  final String requestId;
  final String placement;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {
          'requestId': requestId,
          'placement': placement,
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class HostPlaybackMessage extends ClientMessage {
  HostPlaybackMessage({
    required String sessionId,
    required this.action,
    this.positionMs,
  }) : super(type: 'host.playback', sessionId: sessionId);

  final String action;
  final int? positionMs;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {
          'action': action,
          if (positionMs != null) 'positionMs': positionMs,
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class HostSettingsMessage extends ClientMessage {
  HostSettingsMessage({required String sessionId, required this.settings})
      : super(type: 'host.settings', sessionId: sessionId);

  final HostSettings settings;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': settings.toJson(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class ConnectorJoinMessage extends ClientMessage {
  ConnectorJoinMessage({
    required String sessionId,
    required this.displayName,
    required this.deviceId,
  }) : super(type: 'connector.join', sessionId: sessionId);

  final String displayName;
  final String deviceId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {
          'displayName': displayName,
          'deviceId': deviceId,
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class ConnectorLeaveMessage extends ClientMessage {
  ConnectorLeaveMessage({required String sessionId})
      : super(type: 'connector.leave', sessionId: sessionId);

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {},
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class ConnectorRequestMessage extends ClientMessage {
  ConnectorRequestMessage({required String sessionId, required this.track})
      : super(type: 'connector.request', sessionId: sessionId);

  final Track track;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {'track': track.toJson()},
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class ConnectorVoteMessage extends ClientMessage {
  ConnectorVoteMessage({
    required String sessionId,
    required this.songId,
    required this.action,
  }) : super(type: 'connector.vote', sessionId: sessionId);

  final String songId;
  final String action;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'payload': {
          'songId': songId,
          'action': action,
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class PingMessage extends ClientMessage {
  PingMessage({String? sessionId}) : super(type: 'ping', sessionId: sessionId);

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (sessionId != null) 'sessionId': sessionId,
        'payload': {},
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
}

class QrPayload {
  const QrPayload({
    required this.serverUrl,
    required this.sessionId,
    this.sessionToken,
  });

  final String serverUrl;
  final String sessionId;
  final String? sessionToken;

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'sessionId': sessionId,
        if (sessionToken != null) 'sessionToken': sessionToken,
      };

  factory QrPayload.fromJson(Map<String, dynamic> json) => QrPayload(
        serverUrl: json['serverUrl'] as String,
        sessionId: json['sessionId'] as String,
        sessionToken: json['sessionToken'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());

  static QrPayload fromJsonString(String raw) =>
      QrPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
