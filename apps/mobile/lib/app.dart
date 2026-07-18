import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'services/deep_link_service.dart';
import 'services/privacy_service.dart';
import 'services/session_invite.dart';
import 'theme/share_list_theme.dart';

class ShareListApp extends ConsumerStatefulWidget {
  const ShareListApp({super.key});

  @override
  ConsumerState<ShareListApp> createState() => _ShareListAppState();
}

class _ShareListAppState extends ConsumerState<ShareListApp> {
  @override
  Widget build(BuildContext context) {
    // Keep deep-link listener alive for the app lifetime.
    ref.watch(deepLinkBootstrapProvider);
    final router = ref.watch(routerProvider);
    final privacy = ref.watch(privacyAcceptanceProvider);

    ref.listen<SessionInvite?>(pendingSessionInviteProvider, (previous, next) {
      if (next == null) return;
      // Don't interrupt first-run privacy acceptance.
      if (privacy.valueOrNull != true) return;
      final location = router.routeInformationProvider.value.uri.path;
      if (!location.startsWith('/connect')) {
        router.go('/connect');
      }
    });

    return MaterialApp.router(
      title: 'Share List',
      theme: ShareListTheme.dark(),
      builder: (context, child) => ShareListTheme.wrapBackground(child),
      routerConfig: router,
    );
  }
}
