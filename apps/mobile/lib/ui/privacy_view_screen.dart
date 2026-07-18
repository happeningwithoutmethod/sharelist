import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/privacy_service.dart';

/// Read-only privacy policy viewer (after acceptance).
class PrivacyViewScreen extends StatefulWidget {
  const PrivacyViewScreen({super.key});

  @override
  State<PrivacyViewScreen> createState() => _PrivacyViewScreenState();
}

class _PrivacyViewScreenState extends State<PrivacyViewScreen> {
  late final WebViewController _controller;
  var _loading = true;
  var _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: Stack(
        children: [
          if (_loadFailed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load the policy. Open ${privacyPolicyUrl()} in a browser.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _loadFailed = false;
                        });
                        _controller.loadRequest(Uri.parse(privacyPolicyUrl()));
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_loading && !_loadFailed)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
