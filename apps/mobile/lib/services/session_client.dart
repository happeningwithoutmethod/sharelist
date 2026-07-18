import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SessionMessageHandler = void Function(Map<String, dynamic> message);

class SessionClient {
  SessionClient({required this.serverUrl});

  final String serverUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _pongWatchdog;
  final _handlers = <SessionMessageHandler>[];
  final _disconnectListeners = <VoidCallback>[];
  bool _closing = false;
  bool _awaitingPong = false;
  DateTime? _lastMessageAt;

  bool get isConnected => _channel != null;

  /// True when a message (including pong) was received recently.
  bool get isHealthy {
    if (_channel == null) return false;
    final last = _lastMessageAt;
    if (last == null) return true; // just connected, no traffic yet
    return DateTime.now().difference(last) < const Duration(seconds: 45);
  }

  void addHandler(SessionMessageHandler handler) => _handlers.add(handler);

  void removeHandler(SessionMessageHandler handler) => _handlers.remove(handler);

  void addDisconnectListener(VoidCallback listener) =>
      _disconnectListeners.add(listener);

  void removeDisconnectListener(VoidCallback listener) =>
      _disconnectListeners.remove(listener);

  Future<void> connect() async {
    await disconnect();
    _closing = false;
    _awaitingPong = false;
    _lastMessageAt = DateTime.now();
    final normalized = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$normalized/session');
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      try {
        await channel.sink.close();
      } catch (_) {}
      throw StateError(
        'Timed out connecting to relay at $uri. Is the server reachable?',
      );
    } catch (error) {
      try {
        await channel.sink.close();
      } catch (_) {}
      throw StateError(
        'Could not connect to relay at $uri. '
        'Is the server running? ($error)',
      );
    }

    _channel = channel;
    _subscription = channel.stream.listen(
      (data) {
        _lastMessageAt = DateTime.now();
        _awaitingPong = false;
        _pongWatchdog?.cancel();
        _pongWatchdog = null;
        final decoded = jsonDecode(data as String) as Map<String, dynamic>;
        for (final handler in List.of(_handlers)) {
          handler(decoded);
        }
      },
      onError: (Object error) {
        debugPrint('WebSocket error: $error');
        _notifyDisconnected();
      },
      onDone: () {
        debugPrint('WebSocket closed');
        _notifyDisconnected();
      },
      cancelOnError: true,
    );

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendPing();
    });
  }

  void _sendPing() {
    if (_channel == null || _closing) return;
    if (_awaitingPong) {
      // Previous ping never got a reply — treat as dead.
      debugPrint('WebSocket pong timeout — forcing disconnect');
      unawaited(_forceClose());
      return;
    }
    _awaitingPong = true;
    send(PingMessage().toJson());
    _pongWatchdog?.cancel();
    _pongWatchdog = Timer(const Duration(seconds: 8), () {
      if (!_awaitingPong || _closing) return;
      debugPrint('WebSocket pong watchdog — forcing disconnect');
      unawaited(_forceClose());
    });
  }

  Future<void> _forceClose() async {
    if (_closing) return;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _notifyDisconnected();
  }

  void _notifyDisconnected() {
    final unexpected = !_closing;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    _channel = null;
    _awaitingPong = false;
    if (unexpected) {
      for (final listener in List.of(_disconnectListeners)) {
        listener();
      }
    }
  }

  Future<void> disconnect() async {
    _closing = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    _awaitingPong = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (error) {
      debugPrint('WebSocket send failed: $error');
      unawaited(_forceClose());
    }
  }

  /// Actively probe the socket; completes false if no pong within [timeout].
  Future<bool> probe({Duration timeout = const Duration(seconds: 5)}) async {
    if (_channel == null) return false;
    final completer = Completer<bool>();
    late final SessionMessageHandler handler;
    handler = (message) {
      if (message['type'] == 'pong') {
        if (!completer.isCompleted) completer.complete(true);
      }
    };
    addHandler(handler);
    send(PingMessage().toJson());
    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      removeHandler(handler);
    }
  }
}
