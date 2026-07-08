import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/app/router.dart';
import 'package:loqui/app/theme/theme.dart';
import 'package:loqui/core/gateway/gateway_providers.dart';

class LoquiApp extends ConsumerWidget {
  const LoquiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(gatewayLifecycleProvider); //ries gateway to auth state
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Loqui',
      debugShowCheckedModeBanner: false,
      theme: loquiLightTheme,
      darkTheme: loquiDarkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
