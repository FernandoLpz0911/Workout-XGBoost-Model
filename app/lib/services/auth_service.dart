import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Wraps Firebase Authentication and creates the Firestore user document on
/// first sign-in.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();
  final _firestore = FirebaseFirestore.instance;

  /// Emits the signed-in [User] whenever auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Signs in with Google. Returns the [User] on success, or null if the user
  /// cancelled the picker.
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    await _ensureUserDocument(result.user!);
    return result.user;
  }

  Future<void> signOut() async {
    await Future.wait([_googleSignIn.signOut(), _auth.signOut()]);
  }

  /// Returns a fresh Firebase ID token to attach as a Bearer token on API
  /// requests. Automatically refreshed by the SDK when near expiry.
  Future<String?> getIdToken() =>
      _auth.currentUser?.getIdToken() ?? Future.value(null);

  /// Creates the Firestore user document on first sign-in. Subsequent
  /// sign-ins are a no-op so existing subscription data is never overwritten.
  Future<void> _ensureUserDocument(User user) async {
    final ref = _firestore.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'subscriptionStatus': 'none',
        'subscriptionPlan': null,
        'subscriptionExpiry': null,
        'isLifetimePremium': false,
      });
    }
  }
}
