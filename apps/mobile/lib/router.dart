import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'services/privacy_service.dart';
import 'ui/connect/connect_shell.dart';
import 'ui/connect/connect_join_screen.dart';
import 'ui/host/host_shell.dart';
import 'ui/host/host_start_screen.dart';
import 'ui/mode_picker_screen.dart';
import 'ui/privacy_accept_screen.dart';
import 'ui/privacy_view_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _PrivacyRefresh(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final privacy = ref.read(privacyAcceptanceProvider);
      final accepted = privacy.valueOrNull;
      final onPrivacy = state.matchedLocation == '/privacy';

      if (privacy.isLoading || accepted == null) {
        return onPrivacy ? null : '/privacy';
      }

      if (!accepted && !onPrivacy) return '/privacy';
      if (accepted && onPrivacy) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyAcceptScreen(),
      ),
      GoRoute(
        path: '/privacy-view',
        builder: (context, state) => const PrivacyViewScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const ModePickerScreen(),
      ),
      GoRoute(
        path: '/host',
        builder: (context, state) => const HostStartScreen(),
        routes: [
          GoRoute(
            path: 'session',
            builder: (context, state) => const HostShell(),
          ),
        ],
      ),
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectJoinScreen(),
        routes: [
          GoRoute(
            path: 'session',
            builder: (context, state) => const ConnectShell(),
          ),
        ],
      ),
    ],
  );
});

/// Notifies [GoRouter] when privacy acceptance changes.
class _PrivacyRefresh extends ChangeNotifier {
  _PrivacyRefresh(this._ref) {
    _ref.listen<AsyncValue<bool>>(privacyAcceptanceProvider, (previous, next) {
      notifyListeners();
    });
  }

  final Ref _ref;
}
