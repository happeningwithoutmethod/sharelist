import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/server_config.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/privacy_service.dart';

class ModePickerScreen extends ConsumerStatefulWidget {
  const ModePickerScreen({super.key});

  @override
  ConsumerState<ModePickerScreen> createState() => _ModePickerScreenState();
}

class _ModePickerScreenState extends ConsumerState<ModePickerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final auth = ref.read(authServiceProvider);
      final user = await auth.tryRestore();
      if (user != null && mounted) {
        ref.read(authUserProvider.notifier).state = user;
      }
    });
  }

  Future<void> _openServerSettings() async {
    final current = ref.read(relaySettingsProvider).valueOrNull ??
        relayEndpointFromServerUrl(defaultServerUrl);
    final localMode = ref.read(localModeProvider).valueOrNull ?? false;
    final packageInfo = await PackageInfo.fromPlatform();
    final buildVersion = packageInfo.version;

    final hostController = TextEditingController(text: current.host);
    final portController = TextEditingController(text: '${current.port}');
    var localModeEnabled = localMode;

    if (!mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 8,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Server settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localModeEnabled
                          ? 'Local mode: this device hosts the session on your Wi‑Fi. Connectors scan the QR and join directly.'
                          : 'Host and connectors use the central WebSocket relay.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable local mode'),
                      subtitle: Text(
                        kIsWeb
                            ? 'Unavailable in the browser — use a phone or desktop host.'
                            : 'No central server; connectors join over the local network.',
                      ),
                      value: localModeEnabled && !kIsWeb,
                      onChanged: kIsWeb
                          ? null
                          : (value) => setModalState(() => localModeEnabled = value),
                    ),
                    if (!localModeEnabled || kIsWeb) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: hostController,
                        decoration: InputDecoration(
                          labelText: 'Server host / URL',
                          hintText: ServerConfig.hostname,
                          border: const OutlineInputBorder(),
                          helperText: 'Hostname or IP (scheme optional)',
                        ),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enabled: !localModeEnabled || kIsWeb,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: portController,
                        decoration: InputDecoration(
                          labelText: 'Port',
                          hintText: '${configuredRelayEndpoint().port}',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        enabled: !localModeEnabled || kIsWeb,
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.wifi_tethering),
                          title: const Text('Local mode enabled'),
                          subtitle: const Text(
                            'Relay URL is not used. The QR code will show this device’s LAN address.',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(localModeProvider.notifier)
                              .setEnabled(localModeEnabled && !kIsWeb);
                          if (!localModeEnabled || kIsWeb) {
                            final host = hostController.text.trim();
                            final port = int.tryParse(portController.text.trim());
                            if (host.isEmpty || port == null) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter a valid host and port'),
                                ),
                              );
                              return;
                            }
                            await ref.read(relaySettingsProvider.notifier).save(
                                  RelayEndpoint(host: host, port: port),
                                );
                          }
                          if (context.mounted) Navigator.of(context).pop(true);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$error')),
                            );
                          }
                        }
                      },
                      child: const Text('Save'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Build version: $buildVersion',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) context.push('/privacy-view');
                      });
                    },
                    child: const Text('Privacy Policy'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _LegalWebViewScreen(
                            title: 'YouTube Terms of Service',
                            url: youtubeTermsOfServiceUrl,
                          ),
                        ),
                      );
                    },
                    child: const Text('YouTube Terms of Service'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _LegalWebViewScreen(
                            title: 'Google Privacy Policy',
                            url: googlePrivacyPolicyUrl,
                          ),
                        ),
                      );
                    },
                    child: const Text('Google Privacy Policy'),
                  ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    hostController.dispose();
    portController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final relay = ref.watch(relaySettingsProvider);
    final localMode = ref.watch(localModeProvider).valueOrNull ?? false;
    final relayLabel = localMode
        ? 'Local mode'
        : relay.when(
            data: (value) => value.serverUrl,
            loading: () => '…',
            error: (_, _) => defaultServerUrl,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share List'),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            onPressed: _openServerSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.queue_music, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Share List',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Play music together. Host the playlist or connect and request songs.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Server: $relayLabel',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => context.go('/host'),
                icon: const Icon(Icons.speaker),
                label: const Text('Host Mode'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/connect'),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Connect Mode'),
              ),
              if (user != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Signed in as ${user.displayName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalWebViewScreen extends StatefulWidget {
  const _LegalWebViewScreen({required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<_LegalWebViewScreen> createState() => _LegalWebViewScreenState();
}

class _LegalWebViewScreenState extends State<_LegalWebViewScreen> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
