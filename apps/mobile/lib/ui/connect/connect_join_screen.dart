import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/device_service.dart';
import '../../services/session_controller.dart';
import '../../services/session_invite.dart';

class ConnectJoinScreen extends ConsumerStatefulWidget {
  const ConnectJoinScreen({super.key});

  @override
  ConsumerState<ConnectJoinScreen> createState() => _ConnectJoinScreenState();
}

enum _ConnectJoinMode { scan, code }

class _ConnectJoinScreenState extends ConsumerState<ConnectJoinScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  var _mode = _ConnectJoinMode.scan;
  bool _scanning = false;
  bool _joining = false;
  String? _handledInviteKey;
  String? _lastScannedRaw;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authUserProvider);
    if (user != null) {
      _nameController.text = user.displayName;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeJoinPendingInvite();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedConnections = ref.watch(savedConnectionsProvider);
    final pendingInvite = ref.watch(pendingSessionInviteProvider);

    ref.listen<SessionInvite?>(pendingSessionInviteProvider, (previous, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeJoinPendingInvite();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Host'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_joining,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'Shown when you request a song',
              ),
            ),
            const SizedBox(height: 8),
            if (pendingInvite != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Session invite ready',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pendingInvite.sessionId,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        pendingInvite.serverUrl,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _joining
                            ? null
                            : () => _joinInvite(pendingInvite),
                        child: const Text('Join session'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Center(
              child: SegmentedButton<_ConnectJoinMode>(
                segments: const [
                  ButtonSegment<_ConnectJoinMode>(
                    value: _ConnectJoinMode.scan,
                    label: Text('Scan QR'),
                    icon: Icon(Icons.qr_code_scanner),
                  ),
                  ButtonSegment<_ConnectJoinMode>(
                    value: _ConnectJoinMode.code,
                    label: Text('Enter code'),
                    icon: Icon(Icons.pin),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selected) {
                  if (_joining) return;
                  setState(() {
                    _mode = selected.first;
                    if (_mode == _ConnectJoinMode.code) {
                      _scanning = false;
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _mode == _ConnectJoinMode.scan
                  ? 'Scan the App or Web QR on the host Session screen.'
                  : 'Enter the 6-character code shown on the host (A–Z, 0–9).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_mode == _ConnectJoinMode.code) ...[
              TextField(
                controller: _codeController,
                enabled: !_joining,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                autofocus: true,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      letterSpacing: 6,
                      fontWeight: FontWeight.w700,
                    ),
                decoration: const InputDecoration(
                  labelText: 'Join code',
                  hintText: 'ABC123',
                  counterText: '',
                ),
                onChanged: (value) {
                  final upper = value.toUpperCase().replaceAll(
                        RegExp(r'[^A-Z0-9]'),
                        '',
                      );
                  if (upper != value) {
                    _codeController.value = TextEditingValue(
                      text: upper,
                      selection: TextSelection.collapsed(offset: upper.length),
                    );
                  }
                },
                onSubmitted: (_) => _joinViaCode(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _joining ? null : _joinViaCode,
                icon: const Icon(Icons.login),
                label: const Text('Join with code'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: savedConnections.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (connections) {
                    if (connections.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _RecentSessionsList(
                      connections: connections,
                      joining: _joining,
                      shortSessionId: _shortSessionId,
                      onRemove: _removeConnection,
                      onJoin: _joinSaved,
                    );
                  },
                ),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _joining
                    ? null
                    : () => setState(() => _scanning = !_scanning),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(_scanning ? 'Hide scanner' : 'Open camera scanner'),
              ),
              const SizedBox(height: 16),
              if (_scanning)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MobileScanner(
                      onDetect: (capture) {
                        final raw = capture.barcodes.firstOrNull?.rawValue;
                        if (raw != null) _handleQr(raw);
                      },
                    ),
                  ),
                )
              else
                Expanded(
                  child: savedConnections.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Center(
                      child: Text(
                        'Scan the QR code shown on the host Session screen',
                      ),
                    ),
                    data: (connections) {
                      if (connections.isEmpty) {
                        return const Center(
                          child: Text(
                            'Open the scanner, or switch to Enter code',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return _RecentSessionsList(
                        connections: connections,
                        joining: _joining,
                        shortSessionId: _shortSessionId,
                        onRemove: _removeConnection,
                        onJoin: _joinSaved,
                      );
                    },
                  ),
                ),
            ],
            if (_joining) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            TextButton(
              onPressed: _joining
                  ? null
                  : () async {
                      final auth = ref.read(authServiceProvider);
                      final user = await auth.signInWithGoogle();
                      if (user != null) {
                        ref.read(authUserProvider.notifier).state = user;
                        _nameController.text = user.displayName;
                      }
                    },
              child: const Text('Sign in with Google (optional)'),
            ),
          ],
        ),
      ),
    );
  }

  String _shortSessionId(String sessionId) {
    if (sessionId.length <= 12) return sessionId;
    return '${sessionId.substring(0, 8)}…';
  }

  Future<void> _removeConnection(SavedConnection connection) async {
    final persistence = await ref.read(sessionPersistenceProvider.future);
    await persistence.removeSavedConnection(
      sessionId: connection.sessionId,
      serverUrl: connection.serverUrl,
    );
    ref.invalidate(savedConnectionsProvider);
  }

  Future<void> _maybeJoinPendingInvite() async {
    final invite = ref.read(pendingSessionInviteProvider);
    if (invite == null || _joining) return;
    final key = '${invite.serverUrl}|${invite.sessionId}';
    if (_handledInviteKey == key) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      // Keep invite visible; user taps Join after entering a name.
      return;
    }

    _handledInviteKey = key;
    await _joinInvite(invite);
  }

  Future<void> _joinInvite(SessionInvite invite, {String? invitePayload}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name first')),
      );
      return;
    }

    setState(() => _joining = true);
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref.read(connectSessionProvider.notifier).joinFromInvite(
            invite: invite,
            displayName: name,
            deviceId: deviceId,
            invitePayload: invitePayload ?? invite.payload,
          );
      ref.read(pendingSessionInviteProvider.notifier).state = null;
      if (mounted) context.go('/connect/session');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not join: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _joinSaved(SavedConnection connection) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name first')),
      );
      return;
    }

    setState(() => _joining = true);
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final invite = connection.invite;
      await ref.read(connectSessionProvider.notifier).joinFromInvite(
            invite: invite,
            displayName: name,
            deviceId: deviceId,
            invitePayload: connection.invitePayload ?? invite.payload,
          );
      if (mounted) context.go('/connect/session');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reconnect: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _joinViaCode([String? rawCode]) async {
    final code = SessionInvite.normalizeJoinCode(
      rawCode ?? _codeController.text,
    );
    if (!SessionInvite.isJoinCode(code)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a 6-character code (A–Z, 0–9)'),
          ),
        );
      }
      return;
    }

    setState(() => _joining = true);
    try {
      final invite = await SessionInvite.resolveJoinCode(code);
      if (!mounted) return;
      _codeController.text = code;
      // _joinInvite also toggles _joining; clear first so its finally is correct.
      setState(() => _joining = false);
      await _joinInvite(invite, invitePayload: invite.webUri.toString());
    } catch (error) {
      if (mounted) {
        setState(() => _joining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not join: $error')),
        );
      }
    }
  }

  Future<void> _handleQr(String raw) async {
    if (_joining) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == _lastScannedRaw) return;
    _lastScannedRaw = trimmed;

    final code = SessionInvite.tryParseJoinCode(trimmed);
    if (code != null) {
      await _joinViaCode(code);
      return;
    }

    final invite = SessionInvite.tryParse(trimmed);
    if (invite == null) {
      _lastScannedRaw = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code')),
        );
      }
      return;
    }
    // Persist the exact scanned payload so reconnect replays the same join.
    await _joinInvite(invite, invitePayload: trimmed);
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _RecentSessionsList extends StatelessWidget {
  const _RecentSessionsList({
    required this.connections,
    required this.joining,
    required this.shortSessionId,
    required this.onRemove,
    required this.onJoin,
  });

  final List<SavedConnection> connections;
  final bool joining;
  final String Function(String) shortSessionId;
  final Future<void> Function(SavedConnection) onRemove;
  final Future<void> Function(SavedConnection) onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recent sessions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to reconnect · swipe to remove',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: connections.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final connection = connections[index];
              return Dismissible(
                key: ValueKey(
                  '${connection.serverUrl}|${connection.sessionId}',
                ),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) => onRemove(connection),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(connection.sessionName),
                  subtitle: Text(
                    '${shortSessionId(connection.sessionId)}\n${connection.serverUrl}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: joining ? null : () => onJoin(connection),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
