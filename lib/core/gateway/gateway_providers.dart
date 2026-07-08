import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/auth/auth_service.dart';
import 'package:loqui/core/gateway/gateway_client.dart';

// single client for app
// connect/disconnect is made by auth state
final gatewayClientProvider = Provider<GatewayClient>((ref) {
  final client = GatewayClient(gatewayUrl: gatewayBaseUrl);
  ref.onDispose(client.dipose);
  return client;
});

// watched by app root to tie connection to session:
// connect on login, disconect on logout
final gatewayLifecycleProvider = Provider<void>((ref) {
  final gateway = ref.watch(gatewayClientProvider);
  final storage = ref.read(tokenStorageProvider);

  ref.listen<AuthState>(authControllerProvider, (_, next) {
    if (next is Authenticated) {
      gateway.connect(storage.readAccess);
    } else if (next is Unauthenticated) {
      gateway.disconnect();
    }
  }, fireImmediately: true);
});
