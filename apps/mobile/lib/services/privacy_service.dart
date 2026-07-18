import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/server_config.dart';

/// Bump when the published privacy policy changes in a material way.
/// Must stay in sync with `PRIVACY_POLICY_VERSION` on the server.
const privacyPolicyVersion = 2;

String privacyPolicyUrl() => '${ServerConfig.joinOrigin}/privacy';

/// Required YouTube API Client disclosure link.
const youtubeTermsOfServiceUrl = 'https://www.youtube.com/t/terms';

/// Google Privacy Policy (linked alongside YouTube ToS for API Clients).
const googlePrivacyPolicyUrl = 'https://policies.google.com/privacy';

final privacyAcceptanceProvider =
    StateNotifierProvider<PrivacyAcceptanceController, AsyncValue<bool>>(
  (ref) => PrivacyAcceptanceController()..load(),
);

class PrivacyAcceptanceController extends StateNotifier<AsyncValue<bool>> {
  PrivacyAcceptanceController() : super(const AsyncValue.loading());

  static const _prefsKey = 'privacy_accepted_version';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final acceptedVersion = prefs.getInt(_prefsKey) ?? 0;
      state = AsyncValue.data(acceptedVersion >= privacyPolicyVersion);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, privacyPolicyVersion);
    state = const AsyncValue.data(true);
  }
}
