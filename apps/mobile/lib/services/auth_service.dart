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
  AuthService() : _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  final GoogleSignIn _googleSignIn;
  AuthUser? _currentUser;

  AuthUser? get currentUser => _currentUser;

  Future<AuthUser?> signInWithGoogle() async {
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
