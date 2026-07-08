import 'package:flutter/material.dart';

import 'package:loqui/app/theme/colors.dart';

ThemeData _base(Brightness brightness, Color surface) {
  final scheme = ColorScheme.fromSeed(
    seedColor: LoquiColors.seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

final loquiLightTheme = _base(Brightness.light, LoquiColors.surfaceLight);
final loquiDarkTheme = _base(Brightness.dark, LoquiColors.surfaceDark);
