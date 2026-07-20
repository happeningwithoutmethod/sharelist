import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/privacy_service.dart';
import 'open_external_url.dart';

/// Read-only privacy policy viewer (after acceptance).
class PrivacyViewScreen extends StatefulWidget {
  const PrivacyViewScreen({super.key});

  @override
  State<PrivacyViewScreen> createState() => _PrivacyViewScreenState();
}

class _PrivacyViewScreenState extends State<PrivacyViewScreen> {
  WebViewController? _controller;
  var _loading = true;
  var _loadFailed = false;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: Stack(
        children: [
          if (_loadFailed || controller == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open ${privacyPolicyUrl()} in a browser to read the full policy.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => openExternalUrl(privacyPolicyUrl()),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open privacy policy'),
                    ),
                    if (controller != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _loadFailed = false;
                          });
                          controller.loadRequest(Uri.parse(privacyPolicyUrl()));
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: controller),
          if (_loading && !_loadFailed)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
