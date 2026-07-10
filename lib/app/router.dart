import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:loqui/core/auth/auth_service.dart';
import 'package:loqui/features/auth/screens/login_screen.dart';
import 'package:loqui/features/channels/screens/channel_list_screen.dart';
import 'package:loqui/features/chat/screens/chat_screen.dart';

// rebuilt whenever auth state changes
// redirect gates every route
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  ref.listen<AuthState>(authControllerProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      switch (auth) {
        case AuthLoading():
          return loc == '/splash' ? null : '/splash';
        case Unauthenticated():
          return loc == '/login' ? null : '/login';
        case Authenticated():
          return (loc == '/login' || loc == '/splash') ? '/' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, _) => const ChannelListScreen()),
      GoRoute(
        path: '/channel/:id',
        builder: (_, state) =>
            ChatScreen(channelId: state.pathParameters['id']!),
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
