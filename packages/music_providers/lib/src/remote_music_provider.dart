import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_models/shared_models.dart';

import 'music_provider.dart';

/// Music provider that calls the Share List relay server.
/// Used to search via `/api/music/search` (YouTube Data API v3 on the relay).
class RemoteMusicProvider implements MusicProvider {
  RemoteMusicProvider({required this.httpBaseUrl});

  /// e.g. `http://localhost:3000`
  final String httpBaseUrl;

  @override
  String get providerId => 'youtube_music';

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = httpBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  @override
  Future<List<Track>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final response = await http.get(_uri('/api/music/search', {'q': query}));
    if (response.statusCode >= 400) {
      throw Exception('Search failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['tracks'] as List<dynamic>? ?? [])
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

/// Converts a WebSocket relay URL to an HTTP base URL for the music API.
String httpBaseUrlFromWs(String serverUrl) {
  final normalized = serverUrl.replaceAll(RegExp(r'/+$'), '');
  String http;
  if (normalized.startsWith('wss://')) {
    http = 'https://${normalized.substring(6)}';
  } else if (normalized.startsWith('ws://')) {
    http = 'http://${normalized.substring(5)}';
  } else if (normalized.startsWith('http://') ||
      normalized.startsWith('https://')) {
    http = normalized;
  } else {
    http = 'http://$normalized';
  }
  // Strip websocket path suffixes like `/session`.
  return http.replaceFirst(RegExp(r'/session/?$'), '');
}
