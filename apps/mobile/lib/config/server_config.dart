/// Relay server configuration for the Share List app.
///
/// **Edit this file** to change the default central server before building or
/// running the app. Optional CLI override:
///   `--dart-define=SERVER_URL=wss://other.example.com`
///   `--dart-define=SERVER_HOSTNAME=other.example.com`
abstract final class ServerConfig {
  /// Public hostname (no scheme), used for server-settings defaults.
  static const hostname = String.fromEnvironment(
    'SERVER_HOSTNAME',
    defaultValue: 'sharelist.servehttp.com',
  );

  /// WebSocket base URL joined by default (no `/session` suffix).
  static const url = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'wss://sharelist.servehttp.com',
  );

  /// HTTPS origin used for shareable join links (no trailing slash).
  static const joinOrigin = String.fromEnvironment(
    'JOIN_ORIGIN',
    defaultValue: 'https://sharelist.servehttp.com',
  );

  /// Custom URL scheme that opens the installed app.
  static const appScheme = 'sharelist';
}
