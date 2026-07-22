import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    required this.email,
    this.accessToken,
    this.isGuest = false,
  });

  /// Local guest host identity (no Google account).
  factory AuthUser.guest(String deviceId) => AuthUser(
        id: 'guest:$deviceId',
        displayName: 'Guest Host',
        email: '',
        isGuest: true,
      );

  final String id;
  final String displayName;
  final String email;
  final String? accessToken;
  final bool isGuest;
}

class AuthService {
  AuthService() : _googleSignIn = _createGoogleSignIn();

  /// OAuth **Web** client ID from Google Cloud Console.
  /// Pass at build/run time:
  /// `--dart-define=GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com`
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  final GoogleSignIn _googleSignIn;
  AuthUser? _currentUser;

  AuthUser? get currentUser => _currentUser;

  static GoogleSignIn _createGoogleSignIn() {
    final webId = webClientId.trim();
    return GoogleSignIn(
      scopes: const ['email', 'profile'],
      // Web requires [clientId]. Native Android benefits from [serverClientId]
      // (same Web OAuth client) for ID tokens.
      clientId: kIsWeb && webId.isNotEmpty ? webId : null,
      serverClientId: !kIsWeb && webId.isNotEmpty ? webId : null,
    );
  }

  Future<AuthUser?> signInWithGoogle() async {
    if (kIsWeb && webClientId.trim().isEmpty) {
      throw StateError(
        'Google Sign-In on web is not configured. '
        'Create an OAuth Web client in Google Cloud Console, add '
        'https://sharelist.servehttp.com (and http://localhost) as authorized '
        'JavaScript origins, then rebuild with '
        '--dart-define=GOOGLE_WEB_CLIENT_ID=your-id.apps.googleusercontent.com',
      );
    }

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return null;

      final auth = await account.authentication;
      _currentUser = AuthUser(
        id: account.id,
        displayName: account.displayName ?? account.email,
        email: account.email,
        accessToken: auth.accessToken,
      );
      return _currentUser;
    } catch (error) {
      // Surface configuration / platform errors to the caller.
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<AuthUser?> tryRestore() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return null;

      final auth = await account.authentication;
      _currentUser = AuthUser(
        id: account.id,
        displayName: account.displayName ?? account.email,
        email: account.email,
        accessToken: auth.accessToken,
      );
      return _currentUser;
    } catch (_) {
      return null;
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authUserProvider = StateProvider<AuthUser?>((ref) => null);
