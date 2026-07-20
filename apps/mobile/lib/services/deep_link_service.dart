import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_invite.dart';

/// Holds a pending join invite from a shared link / deep link.
final pendingSessionInviteProvider =
    StateProvider<SessionInvite?>((ref) => null);

/// Listens for app links and stores a [SessionInvite] for the connect flow.
final deepLinkBootstrapProvider = Provider<void>((ref) {
  Future<void> applyInvite(SessionInvite? invite) async {
    if (invite == null) return;
    ref.read(pendingSessionInviteProvider.notifier).state = invite;
  }

  if (kIsWeb) {
    // https://…/web/?session=…&server=…  (and legacy hash invites)
    unawaited(applyInvite(SessionInvite.tryParseWebLocation(Uri.base)));
    return;
  }

  final appLinks = AppLinks();
  StreamSubscription<Uri>? sub;

  Future<void> handleUri(Uri? uri) async {
    if (uri == null) return;
    await applyInvite(
      SessionInvite.tryParseWebLocation(uri) ?? SessionInvite.tryParseUri(uri),
    );
  }

  unawaited(appLinks.getInitialLink().then(handleUri));
  sub = appLinks.uriLinkStream.listen(handleUri);

  ref.onDispose(() {
    unawaited(sub?.cancel() ?? Future<void>.value());
  });
});
