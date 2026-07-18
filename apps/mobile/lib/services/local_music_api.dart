import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:music_providers/music_providers.dart';
import 'package:shared_models/shared_models.dart';

import '../config/server_config.dart';

/// Prefer central relay search (holds the Data API key). Optional local key for
/// offline/dev: `--dart-define=YOUTUBE_API_KEY=...`.
final _localFallbackProvider = YouTubeMusicProvider();

void _applyCors(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
}

Future<void> _writeJson(HttpRequest request, int status, Object body) async {
  final response = request.response;
  _applyCors(response);
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<List<Track>> _searchTracks(String query) async {
  final upstream = Uri.parse(
    '${ServerConfig.joinOrigin}/api/music/search',
  ).replace(queryParameters: {'q': query});

  try {
    final response = await http.get(upstream).timeout(const Duration(seconds: 15));
    if (response.statusCode >= 400) {
      throw HttpException(
        'Upstream search failed (${response.statusCode}): ${response.body}',
        uri: upstream,
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['tracks'] as List<dynamic>? ?? [])
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (error) {
    debugPrint('[local-music-api] upstream search failed: $error');
    // Dev/offline fallback when a local Data API key is configured.
    return _localFallbackProvider.search(query);
  }
}

/// Handles `/api/music/*` on the embedded local relay (search only).
Future<bool> handleLocalMusicApi(HttpRequest request) async {
  final path = request.uri.path;
  if (!path.startsWith('/api/music')) return false;

  if (request.method == 'OPTIONS') {
    final response = request.response;
    _applyCors(response);
    response.statusCode = 204;
    response.headers.set('Access-Control-Max-Age', '86400');
    await response.close();
    return true;
  }

  try {
    if (path == '/api/music/search' && request.method == 'GET') {
      final query = request.uri.queryParameters['q']?.trim() ?? '';
      if (query.isEmpty) {
        await _writeJson(request, 400, {'error': 'Missing q parameter'});
        return true;
      }
      final tracks = await _searchTracks(query);
      await _writeJson(
        request,
        200,
        {'tracks': tracks.map((track) => track.toJson()).toList()},
      );
      return true;
    }

    await _writeJson(request, 404, {'error': 'Not found'});
    return true;
  } catch (error) {
    debugPrint('[local-music-api] $error');
    try {
      await _writeJson(request, 500, {'error': error.toString()});
    } catch (_) {}
    return true;
  }
}
