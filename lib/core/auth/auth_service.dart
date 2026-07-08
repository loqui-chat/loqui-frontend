import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/core/api/api_client.dart';
import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/auth/token_storage.dart';
import 'package:loqui/shared/models/models.dart';

// ==== providers ====

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: apiBaseUrl,
    storage: ref.read(tokenStorageProvider),
    onSessionExpired: () async {
      ref.read(authControllerProvider.notifier).onSessionExpired();
    },
  );
  ref.onDispose(client.close);
  return client;
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

// ==== state ====

sealed class AuthState {
  const AuthState();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class Authenticated extends AuthState {
  const Authenticated(this.user);
  final User user;
}

// ==== contoller ====

class AuthController extends Notifier<AuthState> {
  late final ApiClient _api;
  late final TokenStorage _storage;

  @override
  AuthState build() {
    _storage = ref.read(tokenStorageProvider);
    _api = ref.read(apiClientProvider);
    _bootstrap();
    return const AuthLoading();
  }

  Future<void> _bootstrap() async {
    final access = await _storage.readAccess();
    if (access == null) {
      state = const Unauthenticated();
      return;
    }
    try {
      final me = await _api.get(Endpoints.me);
      state = Authenticated(User.fromJson(me as Map<String, dynamic>));
    } catch (_) {
      state = const Unauthenticated();
    }
  }

  Future<void> login(String identity, String password) async {
    final data =
        await _api.postPublic(Endpoints.login, {
              'identity': identity,
              'password': password,
            })
            as Map<String, dynamic>;
    await _persist(data);
  }

  Future<void> register(String username, String password, String? email) async {
    final data =
        await _api.postPublic(Endpoints.register, {
              'username': username,
              'password': password,
              if (email != null && email.isNotEmpty) 'email': email,
            })
            as Map<String, dynamic>;
    await _persist(data);
  }

  Future<void> logout() async {
    await _storage.clear();
    state = const Unauthenticated();
  }

  void onSessionExpired() => state = const Unauthenticated();

  Future<void> _persist(Map<String, dynamic> data) async {
    await _storage.saveTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );
    state = Authenticated(User.fromJson(data['user'] as Map<String, dynamic>));
  }
}
