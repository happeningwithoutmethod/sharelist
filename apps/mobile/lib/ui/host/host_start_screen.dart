import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../../services/playback_service.dart';
import '../../services/relay_health.dart';
import '../../services/session_controller.dart';
import '../../config/server_config.dart';

enum _RelayStatus { checking, online, offline }

/// Screen to optionally sign in and start (or resume) a host session.
class HostStartScreen extends ConsumerStatefulWidget {
  const HostStartScreen({super.key});

  @override
  ConsumerState<HostStartScreen> createState() => _HostStartScreenState();
}

class _HostStartScreenState extends ConsumerState<HostStartScreen> {
  final _sessionNameController = TextEditingController(text: 'Share List Session');
  late final TextEditingController _serverUrlController;
  bool _busy = false;
  String? _error;
  StoredHostSession? _storedSession;
  _RelayStatus _relayStatus = _RelayStatus.checking;
  int _healthCheckId = 0;
  Timer? _urlDebounce;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(text: ServerConfig.url);
    _serverUrlController.addListener(_onServerUrlEdited);
    Future.microtask(() async {
      await _loadStoredSession();
      await _loadRelaySettings();
      if (mounted) await _checkRelayHealth();
    });
  }

  @override
  void dispose() {
    _urlDebounce?.cancel();
    _serverUrlController.removeListener(_onServerUrlEdited);
    _sessionNameController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  void _onServerUrlEdited() {
    _urlDebounce?.cancel();
    _urlDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) unawaited(_checkRelayHealth());
    });
  }

  Future<void> _loadRelaySettings() async {
    final relay = await ref.read(relaySettingsProvider.future);
    if (!mounted) return;
    // Don't overwrite a resumed session's stored URL.
    if (_storedSession != null) return;
    // Prefer the live configured URL for the branded host / after migration.
    _serverUrlController.text = relay.serverUrl.isEmpty
        ? ServerConfig.url
        : relay.serverUrl;
  }

  Future<void> _loadStoredSession() async {
    final persistence = await ref.read(sessionPersistenceProvider.future);
    final stored = await persistence.loadHostSession();
    if (mounted) {
      setState(() {
        _storedSession = stored;
        if (stored != null) {
          _serverUrlController.text = stored.serverUrl;
        }
      });
    }
  }

  Future<void> _checkRelayHealth() async {
    final localMode = ref.read(localModeProvider).valueOrNull ?? false;
    if (localMode) {
      if (mounted) setState(() => _relayStatus = _RelayStatus.online);
      return;
    }

    final checkId = ++_healthCheckId;
    setState(() => _relayStatus = _RelayStatus.checking);

    final url = _serverUrlController.text.trim().isEmpty
        ? defaultServerUrl
        : _serverUrlController.text.trim();
    final online = await checkRelayReachable(url);
    if (!mounted || checkId != _healthCheckId) return;
    setState(() => _relayStatus = online ? _RelayStatus.online : _RelayStatus.offline);
  }

  Future<AuthUser> _resolveHostUser({required bool asGuest}) async {
    if (!asGuest) {
      final existing = ref.read(authUserProvider);
      if (existing != null && !existing.isGuest) return existing;
    }

    final deviceId = await ref.read(deviceIdProvider.future);
    final guest = AuthUser.guest(deviceId);
    ref.read(authUserProvider.notifier).state = guest;
    return guest;
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(authServiceProvider).signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        setState(() => _error = 'Sign-in was cancelled.');
      } else {
        ref.read(authUserProvider.notifier).state = user;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Google Sign-In failed: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startNewSession({required bool asGuest}) async {
    final localMode = ref.read(localModeProvider).valueOrNull ?? false;
    if (!localMode && _relayStatus != _RelayStatus.online) {
      setState(() => _error = 'Relay server is offline. Wait until it is reachable, then try again.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (localMode && kIsWeb) {
        setState(() {
          _error =
              'Local mode cannot host from Chrome. Use the Android app on the same Wi‑Fi, or turn off local mode.';
          _busy = false;
        });
        return;
      }

      final user = asGuest
          ? await _resolveHostUser(asGuest: true)
          : (ref.read(authUserProvider) ?? await _resolveHostUser(asGuest: true));

      final name = _sessionNameController.text.trim();
      final serverUrl = _serverUrlController.text.trim();
      await ref.read(hostSessionProvider.notifier).startSession(
            user: user,
            sessionName: name.isEmpty ? null : name,
            serverUrl: localMode
                ? null
                : (serverUrl.isEmpty ? defaultServerUrl : serverUrl),
          );
      if (!mounted) return;
      context.go('/host/session');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not start session: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconnectSession() async {
    final stored = _storedSession;
    if (stored == null) return;

    if (_relayStatus != _RelayStatus.online) {
      setState(() => _error = 'Relay server is offline. Wait until it is reachable, then try again.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      var user = ref.read(authUserProvider);
      if (user == null || user.id != stored.hostGoogleSub) {
        if (stored.hostGoogleSub.startsWith('guest:')) {
          final deviceId = await ref.read(deviceIdProvider.future);
          user = AuthUser.guest(deviceId);
          if (user.id != stored.hostGoogleSub) {
            setState(() {
              _error = 'This session belongs to a different device.';
              _busy = false;
            });
            return;
          }
          ref.read(authUserProvider.notifier).state = user;
        } else if (user == null || user.isGuest) {
          setState(() {
            _error = 'Sign in with the same Google account to resume this session.';
            _busy = false;
          });
          return;
        }
      }

      await ref.read(hostSessionProvider.notifier).reconnectSession(
            stored: stored,
            user: user,
          );
      if (!mounted) return;
      context.go('/host/session');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not reconnect: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildRelayStatusRow(BuildContext context, {required bool localMode}) {
    if (localMode) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.check_circle, color: Colors.green.shade400),
        title: const Text('Local mode'),
        subtitle: const Text('No central relay required'),
      );
    }

    final (icon, color, label) = switch (_relayStatus) {
      _RelayStatus.checking => (
          Icons.hourglass_top,
          Theme.of(context).colorScheme.onSurfaceVariant,
          'Checking relay server…',
        ),
      _RelayStatus.online => (
          Icons.check_circle,
          Colors.green.shade400,
          'Relay server online',
        ),
      _RelayStatus.offline => (
          Icons.cancel,
          Colors.red.shade400,
          'Relay server offline',
        ),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _relayStatus == _RelayStatus.checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(
        _relayStatus == _RelayStatus.offline
            ? 'Start is disabled until the server responds at /health'
            : 'GET ${_serverUrlController.text.trim().isEmpty ? defaultServerUrl : _serverUrlController.text.trim()} → /health',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Retry connection',
        onPressed: _busy || _relayStatus == _RelayStatus.checking
            ? null
            : () => _checkRelayHealth(),
        icon: const Icon(Icons.refresh),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final localMode = ref.watch(localModeProvider).valueOrNull ?? false;
    final signedInGoogle = user != null && !user.isGuest;
    final canResume = !localMode &&
        _storedSession != null &&
        (user == null ||
            user.id == _storedSession!.hostGoogleSub ||
            _storedSession!.hostGoogleSub.startsWith('guest:'));

    // Re-check when local mode toggles while this screen is open.
    ref.listen(localModeProvider, (previous, next) {
      unawaited(_checkRelayHealth());
    });

    final canStart = localMode
        ? (!_busy && !kIsWeb)
        : (!_busy && _relayStatus == _RelayStatus.online);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Mode'),
        leading: BackButton(
          onPressed: () {
            unawaited(ref.read(playbackProvider.notifier).stopPlayback());
            context.go('/');
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Start a session',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              localMode
                  ? 'Local mode is on. Connectors on the same Wi‑Fi scan your QR code and join this device directly.'
                  : 'You can start immediately without Google. Optional Google sign-in is only needed later for Premium YouTube Music.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _sessionNameController,
              decoration: const InputDecoration(
                labelText: 'Session name',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            if (localMode)
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.wifi_tethering,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Local mode enabled'),
                  subtitle: Text(
                    kIsWeb
                        ? 'Hosting in local mode requires the Android/desktop app.'
                        : 'No central relay. Your QR code will use this device’s LAN address.',
                  ),
                ),
              )
            else
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Relay server URL',
                  hintText: ServerConfig.url,
                  border: OutlineInputBorder(),
                  helperText:
                      'Defaults to ${ServerConfig.url}. Change in Home → Settings if needed.',
                ),
                enabled: !_busy,
              ),
            const SizedBox(height: 8),
            _buildRelayStatusRow(context, localMode: localMode),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canStart ? () => _startNewSession(asGuest: true) : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start without Google'),
            ),
            const SizedBox(height: 12),
            if (!signedInGoogle)
              OutlinedButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google (optional)'),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle),
                title: Text(user.displayName),
                subtitle: Text(user.email),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await ref.read(authServiceProvider).signOut();
                          ref.read(authUserProvider.notifier).state = null;
                        },
                  child: const Text('Sign out'),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: canStart ? () => _startNewSession(asGuest: false) : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start with Google account'),
              ),
            ],
            if (canResume && _storedSession != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: canStart ? _reconnectSession : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Resume previous session'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
