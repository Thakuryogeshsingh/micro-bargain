import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../../shared/models/user.dart';

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState {
  const SessionState(this.status, [this.user]);

  final SessionStatus status;
  final AppUser? user;

  bool get isMerchant => user?.role == 'merchant';
}

/// Who is logged in. The router listens to this to send customers and merchants to their own screens.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState(SessionStatus.unknown);
  }

  ApiClient get _api => ref.read(apiProvider);

  Future<void> restore() async {
    if (await ref.read(tokenStorageProvider).access == null) {
      state = const SessionState(SessionStatus.signedOut);
      return;
    }
    try {
      final user = AppUser.fromJson(await _api.get('/auth/profile/'));
      state = SessionState(SessionStatus.signedIn, user);
    } on ApiException catch (e) {
      if (e.code == 'network') {
        // Offline at startup: keep the session; screens show their own retry.
        state = const SessionState(SessionStatus.signedIn);
        return;
      }
      await signOutLocally();
    }
  }

  Future<void> signIn(Map<String, dynamic> verifyResponse) async {
    await ref.read(tokenStorageProvider).save(verifyResponse['access'], verifyResponse['refresh']);
    state = SessionState(SessionStatus.signedIn, AppUser.fromJson(verifyResponse['user']));
  }

  /// Re-read the profile, e.g. after becoming a merchant or editing the name.
  Future<void> reloadUser() async {
    final user = AppUser.fromJson(await _api.get('/auth/profile/'));
    state = SessionState(SessionStatus.signedIn, user);
  }

  Future<void> signOut({String? deviceToken}) async {
    final refresh = await ref.read(tokenStorageProvider).refresh;
    try {
      if (deviceToken != null) await _api.post('/notifications/devices/unregister/', {'token': deviceToken});
      if (refresh != null) await _api.post('/auth/logout/', {'refresh': refresh});
    } on ApiException {
      // Logging out must work offline too.
    }
    await signOutLocally();
  }

  Future<void> signOutLocally() async {
    await ref.read(tokenStorageProvider).clear();
    state = const SessionState(SessionStatus.signedOut);
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
