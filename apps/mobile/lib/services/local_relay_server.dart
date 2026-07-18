import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'local_music_api.dart';

const maxLocalConnectors = 50;
const localRelayDefaultPort = 3847;
const orphanTtl = Duration(minutes: 30);

/// Minimal in-app WebSocket relay so connectors can join the host on LAN.
class LocalRelayServer {
  LocalRelayServer({
    this.port = localRelayDefaultPort,
  });

  final int port;
  HttpServer? _server;
  String? _advertiseUrl;
  String? _loopbackUrl;

  final _sessions = <String, _LocalSession>{};
  final _meta = <WebSocket, _ClientMeta>{};

  bool get isRunning => _server != null;

  /// URL connectors should use (LAN IP), e.g. `ws://192.168.1.12:3847`.
  String get advertiseUrl {
    final url = _advertiseUrl;
    if (url == null) {
      throw StateError('Local relay is not running');
    }
    return url;
  }

  /// URL the host app should dial on loopback.
  String get loopbackUrl {
    final url = _loopbackUrl;
    if (url == null) {
      throw StateError('Local relay is not running');
    }
    return url;
  }

  Future<void> start({required String advertiseHost}) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Local mode cannot run in the browser — the host must be a phone or desktop app.',
      );
    }
    await stop();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    _loopbackUrl = 'ws://127.0.0.1:$port';
    _advertiseUrl = 'ws://$advertiseHost:$port';
    debugPrint('Local relay listening on 0.0.0.0:$port (advertise $_advertiseUrl)');

    server.listen(_handleHttpRequest, onError: (Object error) {
      debugPrint('Local relay server error: $error');
    });
  }

  Future<void> stop() async {
    final sessions = List<_LocalSession>.from(_sessions.values);
    for (final session in sessions) {
      _destroySession(session.id, reason: 'host_ended');
    }
    _sessions.clear();

    for (final socket in List<WebSocket>.from(_meta.keys)) {
      await socket.close();
    }
    _meta.clear();

    await _server?.close(force: true);
    _server = null;
    _advertiseUrl = null;
    _loopbackUrl = null;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (request.uri.path == '/session' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _handleSocket(socket);
      return;
    }

    if (request.method == 'GET' &&
        (request.uri.path == '/' || request.uri.path == '/health')) {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'ok': true,
          'mode': 'local',
          'advertiseUrl': _advertiseUrl,
        }),
      );
      await request.response.close();
      return;
    }

    if (await handleLocalMusicApi(request)) {
      return;
    }

    request.response.statusCode = 404;
    await request.response.close();
  }

  void _handleSocket(WebSocket socket) {
    _meta[socket] = const _ClientMeta(role: _ClientRole.unknown);

    socket.listen(
      (data) {
        try {
          final parsed = jsonDecode(data as String);
          if (parsed is! Map<String, dynamic>) {
            throw const FormatException('Message must be a JSON object');
          }
          _handleMessage(socket, parsed);
        } catch (error) {
          _send(socket, {
            'type': 'error',
            'payload': {
              'code': 'INVALID_MESSAGE',
              'message': error is FormatException
                  ? error.message
                  : 'Invalid message',
            },
          });
        }
      },
      onDone: () => _handleDisconnect(socket),
      onError: (_) => _handleDisconnect(socket),
      cancelOnError: true,
    );
  }

  void _handleMessage(WebSocket socket, Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case 'ping':
        _send(socket, {
          'type': 'pong',
          if (message['sessionId'] != null) 'sessionId': message['sessionId'],
        });
      case 'host.start':
        _handleHostStart(socket, message);
      case 'host.reconnect':
        _handleHostReconnect(socket, message);
      case 'host.end':
        _handleHostEnd(socket, message);
      case 'connector.join':
        _handleConnectorJoin(socket, message);
      case 'connector.leave':
        _handleConnectorLeave(socket, message);
      case 'host.state':
        _handleHostState(socket, message);
      default:
        if (type != null) {
          _relayMessage(socket, message);
        }
    }
  }

  void _handleHostStart(WebSocket socket, Map<String, dynamic> message) {
    final payload = message['payload'] as Map<String, dynamic>? ?? {};
    final hostGoogleSub = payload['hostGoogleSub'] as String? ?? '';
    final sessionName = payload['sessionName'] as String?;

    final session = _LocalSession(
      id: const Uuid().v4(),
      sessionToken: const Uuid().v4(),
      hostGoogleSub: hostGoogleSub,
      stateSnapshot: _emptyHostState(sessionName),
    );
    session.hostSocket = socket;
    _sessions[session.id] = session;
    _meta[socket] = _ClientMeta(role: _ClientRole.host, sessionId: session.id);

    _send(socket, {
      'type': 'host.started',
      'sessionId': session.id,
      'payload': {
        'sessionId': session.id,
        'sessionToken': session.sessionToken,
        'serverUrl': advertiseUrl,
      },
    });
  }

  void _handleHostReconnect(WebSocket socket, Map<String, dynamic> message) {
    final payload = message['payload'] as Map<String, dynamic>? ?? {};
    final sessionId = payload['sessionId'] as String? ?? '';
    final sessionToken = payload['sessionToken'] as String? ?? '';
    final hostGoogleSub = payload['hostGoogleSub'] as String? ?? '';
    var session = _sessions[sessionId];
    var recreated = false;

    if (session == null) {
      if (sessionId.isEmpty || sessionToken.isEmpty || hostGoogleSub.isEmpty) {
        _send(socket, {
          'type': 'error',
          'payload': {
            'code': 'SESSION_NOT_FOUND',
            'message': 'Session not found or expired',
          },
        });
        return;
      }
      final stateJson = payload['state'] as Map<String, dynamic>?;
      session = _LocalSession(
        id: sessionId,
        sessionToken: sessionToken,
        hostGoogleSub: hostGoogleSub,
        stateSnapshot: stateJson ?? _emptyHostState(null),
      );
      _sessions[sessionId] = session;
      recreated = true;
    } else {
      if (session.sessionToken != sessionToken) {
        _send(socket, {
          'type': 'error',
          'payload': {
            'code': 'INVALID_TOKEN',
            'message': 'Invalid session token',
          },
        });
        return;
      }
      if (session.hostGoogleSub != hostGoogleSub) {
        _send(socket, {
          'type': 'error',
          'payload': {
            'code': 'UNAUTHORIZED',
            'message': 'Host account mismatch',
          },
        });
        return;
      }
      if (session.status == _SessionStatus.ended) {
        _send(socket, {
          'type': 'error',
          'payload': {
            'code': 'SESSION_ENDED',
            'message': 'Session has ended',
          },
        });
        return;
      }
    }

    session.destroyTimer?.cancel();
    session.destroyTimer = null;
    session.hostSocket = socket;
    session.status = _SessionStatus.active;
    session.orphanedAt = null;
    if (recreated) {
      final stateJson = payload['state'] as Map<String, dynamic>?;
      if (stateJson != null) {
        session.stateSnapshot = stateJson;
      }
    }
    _meta[socket] = _ClientMeta(role: _ClientRole.host, sessionId: session.id);

    _send(socket, {
      'type': 'host.reconnected',
      'sessionId': session.id,
      'payload': {
        'state': session.stateSnapshot,
        'recreated': recreated,
      },
    });
  }

  void _handleHostEnd(WebSocket socket, Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final session = _sessions[sessionId];
    if (session == null || session.hostSocket != socket) {
      _send(socket, {
        'type': 'error',
        'payload': {'code': 'UNAUTHORIZED', 'message': 'Not the session host'},
      });
      return;
    }
    _destroySession(sessionId, reason: 'host_ended');
  }

  void _handleConnectorJoin(WebSocket socket, Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final payload = message['payload'] as Map<String, dynamic>? ?? {};
    final deviceId = payload['deviceId'] as String? ?? '';
    final displayName = payload['displayName'] as String? ?? 'Guest';
    final session = _sessions[sessionId];

    if (session == null) {
      _send(socket, {
        'type': 'error',
        'sessionId': sessionId,
        'payload': {'code': 'JOIN_FAILED', 'message': 'Session not found'},
      });
      return;
    }
    if (session.status == _SessionStatus.ended) {
      _send(socket, {
        'type': 'error',
        'sessionId': sessionId,
        'payload': {'code': 'JOIN_FAILED', 'message': 'Session has ended'},
      });
      return;
    }
    final alreadyJoined = session.connectors.containsKey(deviceId);
    if (!alreadyJoined &&
        (session.status == _SessionStatus.orphaned ||
            session.hostSocket == null)) {
      _send(socket, {
        'type': 'error',
        'sessionId': sessionId,
        'payload': {
          'code': 'JOIN_FAILED',
          'message': 'Host is no longer available',
        },
      });
      return;
    }
    if (!alreadyJoined && session.connectors.length >= maxLocalConnectors) {
      _send(socket, {
        'type': 'error',
        'sessionId': sessionId,
        'payload': {'code': 'JOIN_FAILED', 'message': 'Session is full'},
      });
      return;
    }

    session.connectors[deviceId] = _LocalConnector(
      deviceId: deviceId,
      displayName: displayName,
      socket: socket,
    );
    _meta[socket] = _ClientMeta(
      role: _ClientRole.connector,
      sessionId: sessionId,
      deviceId: deviceId,
    );

    _send(socket, {
      'type': 'connector.joined',
      'sessionId': sessionId,
      'payload': {
        'deviceId': deviceId,
        'displayName': displayName,
        'state': session.stateSnapshot,
      },
    });

    if (!alreadyJoined) {
      _relayToHost(sessionId, {
        ...message,
        'from': {'deviceId': deviceId, 'displayName': displayName},
      });
    }
  }

  void _handleConnectorLeave(WebSocket socket, Map<String, dynamic> message) {
    final meta = _meta[socket];
    final deviceId = meta?.deviceId;
    final sessionId = message['sessionId'] as String? ?? meta?.sessionId;
    if (deviceId == null || sessionId == null) return;

    final connector = _removeConnector(sessionId, deviceId);
    _relayToHost(sessionId, {
      ...message,
      'payload': {
        'deviceId': deviceId,
        'displayName': connector?.displayName,
      },
    });
  }

  void _handleHostState(WebSocket socket, Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final session = _sessions[sessionId];
    if (session == null || session.hostSocket != socket) {
      _send(socket, {
        'type': 'error',
        'payload': {'code': 'UNAUTHORIZED', 'message': 'Not the session host'},
      });
      return;
    }

    final payload = message['payload'];
    if (payload is Map<String, dynamic>) {
      session.stateSnapshot = payload;
    }

    _broadcastToConnectors(sessionId, {
      'type': 'host.state',
      'sessionId': sessionId,
      'payload': session.stateSnapshot,
    });
  }

  void _relayMessage(WebSocket socket, Map<String, dynamic> message) {
    final meta = _meta[socket];
    final sessionId = meta?.sessionId;
    if (sessionId == null) {
      _send(socket, {
        'type': 'error',
        'payload': {
          'code': 'NOT_IN_SESSION',
          'message': 'Not connected to a session',
        },
      });
      return;
    }

    final session = _sessions[sessionId];
    if (session == null) {
      _send(socket, {
        'type': 'error',
        'sessionId': sessionId,
        'payload': {
          'code': 'SESSION_NOT_FOUND',
          'message': 'Session not found',
        },
      });
      return;
    }

    if (meta!.role == _ClientRole.connector) {
      final host = session.hostSocket;
      if (host != null) {
        final connector = session.connectors[meta.deviceId ?? ''];
        _send(host, {
          'type': 'relay',
          'sessionId': sessionId,
          'payload': {
            'original': {
              ...message,
              'from': {
                'deviceId': meta.deviceId,
                'displayName': connector?.displayName,
              },
            },
          },
        });
      }
      return;
    }

    if (meta.role == _ClientRole.host) {
      _broadcastToConnectors(sessionId, {
        'type': 'relay',
        'sessionId': sessionId,
        'payload': {'original': message},
      });
    }
  }

  void _relayToHost(String sessionId, Map<String, dynamic> message) {
    final session = _sessions[sessionId];
    final host = session?.hostSocket;
    if (host == null) return;
    _send(host, {
      'type': 'relay',
      'sessionId': sessionId,
      'payload': {'original': message},
    });
  }

  void _handleDisconnect(WebSocket socket) {
    final meta = _meta.remove(socket);
    final sessionId = meta?.sessionId;
    if (meta == null || sessionId == null) return;

    if (meta.role == _ClientRole.host) {
      final session = _sessions[sessionId];
      if (session?.hostSocket == socket) {
        _orphanSession(sessionId);
      }
      return;
    }

    if (meta.role == _ClientRole.connector && meta.deviceId != null) {
      // Soft-detach so reconnect can reuse membership without re-approval.
      final session = _sessions[sessionId];
      final connector = session?.connectors[meta.deviceId!];
      if (connector != null && identical(connector.socket, socket)) {
        session!.connectors[meta.deviceId!] = _LocalConnector(
          deviceId: connector.deviceId,
          displayName: connector.displayName,
          socket: null,
        );
      }
    }
  }

  void _orphanSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null || session.status == _SessionStatus.ended) return;

    session.status = _SessionStatus.orphaned;
    session.hostSocket = null;
    session.orphanedAt = DateTime.now();
    session.destroyTimer?.cancel();
    session.destroyTimer = Timer(orphanTtl, () {
      _destroySession(sessionId, reason: 'expired');
    });
  }

  void _destroySession(String sessionId, {required String reason}) {
    final session = _sessions.remove(sessionId);
    if (session == null) return;

    session.status = _SessionStatus.ended;
    session.destroyTimer?.cancel();
    session.destroyTimer = null;

    final message = {
      'type': 'session.ended',
      'sessionId': sessionId,
      'payload': {
        'reason': reason,
        'message': reason == 'expired'
            ? 'Session expired after host disconnect'
            : reason == 'host_ended'
                ? 'Host ended the session'
                : 'Session ended due to an error',
      },
    };

    final host = session.hostSocket;
    if (host != null) {
      _send(host, message);
    }
    for (final connector in session.connectors.values) {
      final socket = connector.socket;
      if (socket != null) {
        _send(socket, message);
      }
    }
  }

  _LocalConnector? _removeConnector(String sessionId, String deviceId) {
    final session = _sessions[sessionId];
    if (session == null) return null;
    return session.connectors.remove(deviceId);
  }

  void _broadcastToConnectors(String sessionId, Map<String, dynamic> message) {
    final session = _sessions[sessionId];
    if (session == null) return;
    for (final connector in session.connectors.values) {
      final socket = connector.socket;
      if (socket != null) {
        _send(socket, message);
      }
    }
  }

  void _send(WebSocket socket, Map<String, dynamic> message) {
    if (socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({...message, 'ts': DateTime.now().millisecondsSinceEpoch}));
    }
  }
}

enum _ClientRole { unknown, host, connector }

enum _SessionStatus { active, orphaned, ended }

class _ClientMeta {
  const _ClientMeta({
    required this.role,
    this.sessionId,
    this.deviceId,
  });

  final _ClientRole role;
  final String? sessionId;
  final String? deviceId;
}

class _LocalConnector {
  _LocalConnector({
    required this.deviceId,
    required this.displayName,
    required this.socket,
  });

  final String deviceId;
  final String displayName;
  final WebSocket? socket;
}

class _LocalSession {
  _LocalSession({
    required this.id,
    required this.sessionToken,
    required this.hostGoogleSub,
    required this.stateSnapshot,
  });

  final String id;
  final String sessionToken;
  final String hostGoogleSub;
  _SessionStatus status = _SessionStatus.active;
  WebSocket? hostSocket;
  final connectors = <String, _LocalConnector>{};
  Map<String, dynamic> stateSnapshot;
  DateTime? orphanedAt;
  Timer? destroyTimer;
}

Map<String, dynamic> _emptyHostState(String? sessionName) => {
      'sessionName': sessionName ?? 'Share List Session',
      'playlist': <dynamic>[],
      'nowPlayingIndex': -1,
      'isPlaying': false,
      'positionMs': 0,
      'durationMs': 0,
      'settings': {
        'allowSuggestions': true,
        'allowVoting': true,
        'autoReorderByVotes': false,
        'autoPlaylistAdvance': true,
        'autoApproveRequests': false,
        'requireConnectionApproval': false,
      },
      'voteScores': <String, dynamic>{},
      'pendingRequests': <dynamic>[],
      'connectors': <dynamic>[],
    };

/// Picks a LAN IPv4 address for QR codes / connector dialing.
Future<String> resolveLanIPv4() async {
  if (kIsWeb) {
    throw UnsupportedError('LAN discovery is unavailable on web');
  }

  final interfaces = await NetworkInterface.list(
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );

  final candidates = <String>[];
  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (addr.isLoopback) continue;
      final ip = addr.address;
      // Prefer common private ranges.
      if (ip.startsWith('192.168.') ||
          ip.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(ip)) {
        candidates.add(ip);
      } else {
        candidates.add(ip);
      }
    }
  }

  if (candidates.isEmpty) {
    throw StateError(
      'No LAN IP found. Connect this device to Wi‑Fi and try again.',
    );
  }

  // Prefer 192.168.* then 10.* then anything else.
  candidates.sort((a, b) {
    int rank(String ip) {
      if (ip.startsWith('192.168.')) return 0;
      if (ip.startsWith('10.')) return 1;
      if (RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(ip)) return 2;
      return 3;
    }

    return rank(a).compareTo(rank(b));
  });

  return candidates.first;
}
