import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router.dart';
import 'core/theme/legacy_themes.dart';
import 'core/theme/nexus_theme.dart';
import 'domain/enums.dart';
import 'state/app_state.dart';

class NexusApp extends ConsumerWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(lookProvider);
    final dark = switch (look.bright) {
      BrightnessPref.dark => true,
      BrightnessPref.light => false,
      BrightnessPref.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    final theme = switch (look.brand) {
      ThemeBrand.nexus => NexusTheme.build(
          bright: dark ? Brightness.dark : Brightness.light,
          accentHex: look.accent,
          colorblindSafe: look.colorblindSafe,
        ),
      ThemeBrand.win98 => LegacyThemes.win98(),
      ThemeBrand.winxp => LegacyThemes.winxp(),
      ThemeBrand.win7 => LegacyThemes.win7(),
    };

    return MaterialApp.router(
      title: 'Nexus File Manager',
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
      scrollBehavior: const _ScrollFine(),
    );
  }
}

/// Finer scrollbars + mouse-wheel feel everywhere.
class _ScrollFine extends MaterialScrollBehavior {
  const _ScrollFine();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
