import 'dart:convert';

import '../config/server_config.dart';

/// Invite that opens Share List and joins a host session.
class SessionInvite {
  const SessionInvite({
    required this.sessionId,
    required this.serverUrl,
  });

  final String sessionId;
  final String serverUrl;

  /// HTTPS link suitable for sharing in other apps / browsers.
  Uri get httpsUri {
    return Uri.parse('${ServerConfig.joinOrigin}/join').replace(
      queryParameters: {
        'session': sessionId,
        // Always include the relay the host is on so connectors do not depend
        // on matching build-time ServerConfig defaults.
        'server': serverUrl,
      },
    );
  }

  /// Custom-scheme link that opens the app directly.
  Uri get appUri {
    return Uri(
      scheme: ServerConfig.appScheme,
      host: 'join',
      queryParameters: {
        'session': sessionId,
        'server': serverUrl,
      },
    );
  }

  String get shareText =>
      'Join my Share List session:\n${httpsUri.toString()}';

  /// Canonical payload to persist and re-parse on reconnect (same as a shared link).
  String get payload => httpsUri.toString();

  static String normalizeServerUrl(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.startsWith('https://')) {
      value = 'wss://${value.substring('https://'.length)}';
    } else if (value.startsWith('http://')) {
      value = 'ws://${value.substring('http://'.length)}';
    }
    return value;
  }

  static SessionInvite? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Legacy QR JSON: {"serverUrl":"...","sessionId":"..."}
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final sessionId = decoded['sessionId']?.toString().trim();
          final serverUrl = decoded['serverUrl']?.toString();
          if (sessionId != null &&
              sessionId.isNotEmpty &&
              serverUrl != null &&
              serverUrl.trim().isNotEmpty) {
            return SessionInvite(
              sessionId: sessionId,
              serverUrl: normalizeServerUrl(serverUrl),
            );
          }
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    return tryParseUri(uri);
  }

  static SessionInvite? tryParseUri(Uri uri) {
    final isAppScheme = uri.scheme == ServerConfig.appScheme;
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    if (!isAppScheme && !isHttp) return null;

    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    final isJoinPath =
        path == '/join' || path.startsWith('/join/') || uri.host == 'join';
    if (!isJoinPath && !(isAppScheme && (uri.host == 'join' || path.isEmpty))) {
      return null;
    }

    var sessionId = uri.queryParameters['session'] ??
        uri.queryParameters['sessionId'] ??
        '';
    sessionId = sessionId.trim();
    if (sessionId.isEmpty && path.startsWith('/join/')) {
      sessionId = Uri.decodeComponent(
        path.substring('/join/'.length).split('/').first,
      ).trim();
    }
    if (sessionId.isEmpty) return null;

    final rawServer = (uri.queryParameters['server'] ??
            uri.queryParameters['serverUrl'] ??
            ServerConfig.url)
        .trim();
    if (rawServer.isEmpty) return null;

    return SessionInvite(
      sessionId: sessionId,
      serverUrl: normalizeServerUrl(rawServer),
    );
  }
}
