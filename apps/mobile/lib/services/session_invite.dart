import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/server_config.dart';

/// Invite that opens Share List and joins a host session.
class SessionInvite {
  const SessionInvite({
    required this.sessionId,
    required this.serverUrl,
    this.joinCode,
  });

  final String sessionId;
  final String serverUrl;

  /// Optional 6-character public join code (A–Z0–9).
  final String? joinCode;

  /// HTTPS link that opens the installed app (via `/join` bridge page).
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

  /// Short join link: `https://host/join/ABC123` (opens app bridge page).
  Uri get webUri {
    final code = joinCode?.trim().toUpperCase();
    if (code != null && isJoinCode(code)) {
      return Uri.parse('${ServerConfig.joinOrigin}/join/$code');
    }
    // Fallback when the relay has not assigned a short code yet.
    return httpsUri;
  }

  String get shareTextApp =>
      'Join my Share List session (app):\n${httpsUri.toString()}';

  String get shareTextWeb {
    final code = joinCode?.trim().toUpperCase();
    if (code != null && isJoinCode(code)) {
      return 'Join my Share List session:\n'
          '${webUri.toString()}\n'
          'Or enter code: $code';
    }
    return 'Join my Share List session:\n${webUri.toString()}';
  }

  String get shareText =>
      'Join my Share List session:\n'
      'App: ${httpsUri.toString()}\n'
      'Web: ${webUri.toString()}'
      '${joinCode != null ? '\nCode: ${joinCode!.toUpperCase()}' : ''}';

  /// Canonical payload to persist and re-parse on reconnect (same as a shared link).
  String get payload => httpsUri.toString();

  static bool isJoinCode(String raw) =>
      RegExp(r'^[A-Z0-9]{6}$').hasMatch(raw.trim().toUpperCase());

  static String normalizeJoinCode(String raw) => raw.trim().toUpperCase();

  /// Extracts a 6-char join code from raw text or a `/join/XXXXXX` URL.
  static String? tryParseJoinCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final asCode = normalizeJoinCode(trimmed);
    if (isJoinCode(asCode)) return asCode;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    final match = RegExp(r'^/join/([A-Za-z0-9]{6})$').firstMatch(path);
    if (match != null) {
      return normalizeJoinCode(match.group(1)!);
    }
    final codeParam = uri.queryParameters['code'];
    if (codeParam != null && isJoinCode(codeParam)) {
      return normalizeJoinCode(codeParam);
    }
    return null;
  }

  /// HTTP origin for a WebSocket relay URL (`wss://host` → `https://host`).
  static String httpOriginFromServerUrl(String serverUrl) {
    var value = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.startsWith('wss://')) {
      value = 'https://${value.substring('wss://'.length)}';
    } else if (value.startsWith('ws://')) {
      value = 'http://${value.substring('ws://'.length)}';
    } else if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    // Strip a trailing /session path if present.
    value = value.replaceAll(RegExp(r'/session$'), '');
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  /// Host-only: fetch the live join code for an active session.
  static Future<String?> fetchHostJoinCode({
    required String sessionId,
    required String sessionToken,
    required String serverUrl,
  }) async {
    final origin = httpOriginFromServerUrl(serverUrl);
    final uri = Uri.parse('$origin/api/host/join-code').replace(
      queryParameters: {
        'sessionId': sessionId,
        'sessionToken': sessionToken,
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    final code = (body['joinCode']?.toString() ?? '').trim().toUpperCase();
    return isJoinCode(code) ? code : null;
  }

  /// Resolves a short join code via the central relay HTTP API.
  static Future<SessionInvite> resolveJoinCode(String rawCode) async {
    final code = normalizeJoinCode(rawCode);
    if (!isJoinCode(code)) {
      throw StateError('Enter a 6-character code (A–Z, 0–9)');
    }
    final uri = Uri.parse('${ServerConfig.joinOrigin}/api/join/$code');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) {
      throw StateError('No active session for code $code');
    }
    if (response.statusCode != 200) {
      throw StateError('Could not look up code $code (${response.statusCode})');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw StateError('Invalid join response');
    }
    final sessionId = (body['sessionId'] as String?)?.trim() ?? '';
    final serverUrl = (body['serverUrl'] as String?)?.trim() ?? '';
    if (sessionId.isEmpty || serverUrl.isEmpty) {
      throw StateError('Invalid join response');
    }
    return SessionInvite(
      sessionId: sessionId,
      serverUrl: normalizeServerUrl(serverUrl),
      joinCode: (body['joinCode'] as String?)?.toUpperCase() ?? code,
    );
  }

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
              joinCode: decoded['joinCode']?.toString(),
            );
          }
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    // Short web link needs an async API lookup — signal via null here;
    // callers should use [tryParseJoinCode] + [resolveJoinCode].
    if (tryParseJoinCode(trimmed) != null &&
        !uri.queryParameters.containsKey('session') &&
        !uri.queryParameters.containsKey('sessionId')) {
      return null;
    }

    return tryParseWebLocation(uri) ?? tryParseUri(uri);
  }

  /// Parses invites from the Flutter / React web URL, e.g.
  /// `https://host/app/?session=…&server=…`, `https://host/web/?session=…&server=…`
  /// (QR-safe) or `https://host/app/#/connect?session=…&server=…` (legacy hash).
  static SessionInvite? tryParseWebLocation(Uri uri) {
    // Preferred / QR-safe: query on /app/ or /web/
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path == '/app' ||
        path.endsWith('/app') ||
        path == '/web' ||
        path.endsWith('/web')) {
      final fromQuery = _fromQueryParameters(uri.queryParameters);
      if (fromQuery != null) return fromQuery;
    }

    // Legacy hash style: #/connect?session=…&server=…
    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) return null;

    final fragUri = Uri.parse(
      fragment.startsWith('/') ? fragment : '/$fragment',
    );
    final fragPath = fragUri.path.replaceAll(RegExp(r'/+$'), '');
    if (fragPath != '/connect' && !fragPath.startsWith('/connect/')) {
      return null;
    }
    return _fromQueryParameters({
      ...uri.queryParameters,
      ...fragUri.queryParameters,
    });
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

    // `/join/ABC123` without query is a short code — resolve asynchronously.
    if (isHttp &&
        RegExp(r'^/join/[A-Za-z0-9]{6}$').hasMatch(path) &&
        uri.queryParameters['session'] == null &&
        uri.queryParameters['sessionId'] == null) {
      return null;
    }

    return _fromQueryParameters({
      ...uri.queryParameters,
      if (uri.queryParameters['session'] == null &&
          uri.queryParameters['sessionId'] == null &&
          path.startsWith('/join/') &&
          !RegExp(r'^/join/[A-Za-z0-9]{6}$').hasMatch(path))
        'session': Uri.decodeComponent(
          path.substring('/join/'.length).split('/').first,
        ),
    });
  }

  static SessionInvite? _fromQueryParameters(Map<String, String> params) {
    var sessionId =
        (params['session'] ?? params['sessionId'] ?? '').trim();
    if (sessionId.isEmpty) return null;

    final rawServer =
        (params['server'] ?? params['serverUrl'] ?? ServerConfig.url).trim();
    if (rawServer.isEmpty) return null;

    final code = params['code'];
    return SessionInvite(
      sessionId: sessionId,
      serverUrl: normalizeServerUrl(rawServer),
      joinCode: code != null && isJoinCode(code) ? normalizeJoinCode(code) : null,
    );
  }
}
