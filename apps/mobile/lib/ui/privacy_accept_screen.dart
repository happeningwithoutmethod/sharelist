import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/app_permissions.dart';
import '../services/privacy_service.dart';
import 'open_external_url.dart';

/// First-run gate: user must accept the published privacy policy.
class PrivacyAcceptScreen extends ConsumerStatefulWidget {
  const PrivacyAcceptScreen({super.key});

  @override
  ConsumerState<PrivacyAcceptScreen> createState() =>
      _PrivacyAcceptScreenState();
}

class _PrivacyAcceptScreenState extends ConsumerState<PrivacyAcceptScreen> {
  WebViewController? _controller;
  var _loading = true;
  var _loadFailed = false;
  var _accepting = false;

  @override
  void initState() {
    super.initState();
    // webview_flutter has no web implementation — creating a controller throws.
    if (kIsWeb) {
      _loading = false;
      _loadFailed = true;
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _loadFailed = false;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _loadFailed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(privacyPolicyUrl()));
    _controller = controller;
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await ref.read(privacyAcceptanceProvider.notifier).accept();
      // Permissions only after the user has accepted the policy.
      await requestStartupPermissions();
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                'Please review and accept the Privacy Policy to continue. '
                'Using YouTube features also means you agree to the YouTube '
                'Terms of Service. Version $privacyPolicyVersion · ${privacyPolicyUrl()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_loadFailed || controller == null)
                  _OfflinePrivacyFallback(
                    onRetry: controller == null
                        ? null
                        : () {
                            setState(() {
                              _loading = true;
                              _loadFailed = false;
                            });
                            controller.loadRequest(
                              Uri.parse(privacyPolicyUrl()),
                            );
                          },
                  )
                else
                  WebViewWidget(controller: controller),
                if (_loading && !_loadFailed)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'By tapping Accept you agree to this Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _accepting ? null : _accept,
                    child: _accepting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept & continue'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflinePrivacyFallback extends StatelessWidget {
  const _OfflinePrivacyFallback({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          kIsWeb
              ? 'Review the privacy policy'
              : 'Could not load the online policy',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          kIsWeb
              ? 'Open the full policy in a new tab, or read the summary below and accept to continue.'
              : 'Check your connection and retry, or open ${privacyPolicyUrl()} '
                  'in a browser. A short summary is shown below so you can still accept.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (kIsWeb)
          OutlinedButton.icon(
            onPressed: () => openExternalUrl(privacyPolicyUrl()),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open full policy'),
          ),
        if (onRetry != null) ...[
          if (kIsWeb) const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
        const SizedBox(height: 24),
        Text('Summary', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        const Text(
          'Share List may collect optional Google account details for hosting, '
          'a guest/device id, approximate country for public charts, session '
          'playlist content, and aggregated play statistics. Search uses the '
          'YouTube Data API; playback uses the official YouTube player. By using '
          'YouTube features you agree to YouTube’s Terms of Service and Google’s '
          'Privacy Policy. We do not sell your personal information. Full '
          'details are on the website privacy page.',
        ),
      ],
    );
  }
}
