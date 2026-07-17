import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_service.dart';

// ── Auth ──────────────────────────────────────────────────────────────────────

final authServiceProvider = Provider((_) => AuthService());

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);
