import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google 로그인/로그아웃 얇은 래퍼.
///
/// google_sign_in v7+ API(`GoogleSignIn.instance.initialize()` →
/// `authenticate()`)를 사용한다. `google-services.json`에 web(oauth_client
/// type 3) 항목이 이미 있으므로 Android에서는 clientId/serverClientId를
/// 따로 넘길 필요가 없다.
class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _initFuture;

  /// `GoogleSignIn.instance.initialize()`는 앱 생애주기 동안 정확히 한 번만
  /// 호출되어야 하므로, 첫 호출의 Future를 캐시해 재사용한다.
  Future<void> _ensureInitialized() {
    return _initFuture ??= _googleSignIn.initialize();
  }

  Stream<User?> authStateChanges() => FirebaseAuth.instance.authStateChanges();

  /// 계정 선택 다이얼로그를 띄우고 Firebase 로그인까지 완료한다.
  /// 사용자가 취소한 경우 예외를 던지지 않고 null을 반환한다.
  Future<UserCredential?> signInWithGoogle() async {
    await _ensureInitialized();
    try {
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return FirebaseAuth.instance.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _googleSignIn.signOut(),
      FirebaseAuth.instance.signOut(),
    ]);
  }
}
