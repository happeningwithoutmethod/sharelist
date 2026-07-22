import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_models/shared_models.dart';

import 'music_provider.dart';

const _searchEndpoint = 'https://www.googleapis.com/youtube/v3/search';
const _defaultMaxResults = 20;

/// YouTube Data API v3 search (`search.list`, type=video).
///
/// Requires a project API key via `--dart-define=YOUTUBE_API_KEY=...`
/// (prefer keeping the key on the relay and using [RemoteMusicProvider] instead).
class YouTubeMusicProvider implements MusicProvider {
  YouTubeMusicProvider({http.Client? httpClient, String? apiKey})
      : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _apiKey = apiKey ??
            const String.fromEnvironment('YOUTUBE_API_KEY', defaultValue: '');

  final http.Client _http;
  final bool _ownsHttp;
  final String _apiKey;

  @override
  String get providerId => 'youtube_music';

  @override
  Future<List<Track>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    if (_apiKey.isEmpty) {
      throw StateError(
        'YOUTUBE_API_KEY is not set. Prefer relay search via RemoteMusicProvider, '
        'or pass --dart-define=YOUTUBE_API_KEY=...',
      );
    }

    final uri = Uri.parse(_searchEndpoint).replace(
      queryParameters: {
        'part': 'snippet',
        'type': 'video',
        'maxResults': '$_defaultMaxResults',
        'safeSearch': 'moderate',
        'q': trimmed,
        'key': _apiKey,
      },
    );

    final response = await _http.get(uri);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('YouTube Data API returned unexpected JSON');
    }

    if (response.statusCode >= 400) {
      final error = decoded['error'];
      final detail = error is Map ? error['message'] : null;
      throw Exception(
        'YouTube Data API search failed (${response.statusCode})'
        '${detail is String && detail.isNotEmpty ? ': $detail' : ''}',
      );
    }

    final items = decoded['items'] as List<dynamic>? ?? const [];
    return items.map(_trackFromItem).whereType<Track>().toList();
  }

  Track? _trackFromItem(Object? raw) {
    if (raw is! Map) return null;
    final item = Map<String, dynamic>.from(raw);
    final idNode = item['id'];
    final videoId = idNode is Map ? idNode['videoId'] as String? : null;
    if (videoId == null || videoId.isEmpty) return null;

    final snippet = item['snippet'];
    final snippetMap =
        snippet is Map ? Map<String, dynamic>.from(snippet) : null;
    final rawTitle = (snippetMap?['title'] as String?)?.trim();
    final rawArtist = (snippetMap?['channelTitle'] as String?)?.trim();
    final title =
        rawTitle == null || rawTitle.isEmpty ? null : decodeHtmlEntities(rawTitle);
    final artist = rawArtist == null || rawArtist.isEmpty
        ? null
        : decodeHtmlEntities(rawArtist);
    final thumbs = snippetMap?['thumbnails'];
    String? artworkUrl;
    if (thumbs is Map) {
      for (final key in ['high', 'medium', 'default']) {
        final entry = thumbs[key];
        if (entry is Map) {
          final url = entry['url'] as String?;
          if (url != null && url.isNotEmpty) {
            artworkUrl = url;
            break;
          }
        }
      }
    }

    return Track(
      id: videoId,
      title: (title == null || title.isEmpty) ? 'Unknown title' : title,
      artist: (artist == null || artist.isEmpty) ? 'Unknown artist' : artist,
      artworkUrl: artworkUrl,
      sourceUrl: 'https://www.youtube.com/watch?v=$videoId',
      provider: providerId,
    );
  }

  void dispose() {
    if (_ownsHttp) {
      _http.close();
    }
  }
}
