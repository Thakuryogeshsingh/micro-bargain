import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/prefs.dart';
import '../../shared/models/user.dart';

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState {
  const SessionState(this.status, [this.user]);

  final SessionStatus status;
  final AppUser? user;

  bool get isMerchant => user?.role == 'merchant';
  bool get isAdmin => user?.role == 'admin';
  bool get isStaff => user?.role == 'staff';
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
      state = SessionState(SessionStatus.signedIn, await _loadUser());
    } on ApiException {
      if (await ref.read(tokenStorageProvider).refresh == null) {
        // The server rejected the login (expired or logged out elsewhere).
        state = const SessionState(SessionStatus.signedOut);
        return;
      }
      // Offline or the server is waking up: stay signed in as the last known user and try again shortly.
      state = SessionState(SessionStatus.signedIn, _cachedUser());
      Future.delayed(const Duration(seconds: 20), () async {
        try {
          if (state.status == SessionStatus.signedIn) state = SessionState(SessionStatus.signedIn, await _loadUser());
        } on ApiException {
          // Screens show their own retry.
        }
      });
    }
  }

  Future<AppUser> _loadUser() async {
    final json = Map<String, dynamic>.from(await _api.get('/auth/profile/'));
    await Prefs.set('user', jsonEncode(json));
    return AppUser.fromJson(json);
  }

  AppUser? _cachedUser() {
    final raw = Prefs.get('user');
    return raw == null ? null : AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> signIn(Map<String, dynamic> verifyResponse) async {
    await ref.read(tokenStorageProvider).save(verifyResponse['access'], verifyResponse['refresh']);
    await Prefs.set('user', jsonEncode(verifyResponse['user']));
    state = SessionState(SessionStatus.signedIn, AppUser.fromJson(verifyResponse['user']));
  }

  /// Re-read the profile, e.g. after becoming a merchant or editing the name.
  Future<void> reloadUser() async {
    state = SessionState(SessionStatus.signedIn, await _loadUser());
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
