import 'package:http/http.dart' as http;
import 'package:music_providers/music_providers.dart';

/// Probes the relay HTTP `/health` endpoint derived from a WebSocket server URL.
Future<bool> checkRelayReachable(
  String serverUrl, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final trimmed = serverUrl.trim();
  if (trimmed.isEmpty) return false;

  try {
    final base = httpBaseUrlFromWs(trimmed).replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/health');
    final response = await http.get(uri).timeout(timeout);
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}
