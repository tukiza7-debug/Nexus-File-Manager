import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router.dart';
import 'core/theme/legacy_themes.dart';
import 'core/theme/nexus_theme.dart';
import 'core/utils/responsive.dart';
import 'domain/enums.dart';
import 'l10n/app_localizations.dart';
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
        (MediaQuery.maybeOf(context)?.platformBrightness ??
                WidgetsBinding.instance.platformDispatcher.platformBrightness) ==
            Brightness.dark,
    };

    final metrics = NexusMetrics.of(context, touchMode: look.touchMode);
    final theme = switch (look.brand) {
      ThemeBrand.nexus => NexusTheme.build(
          bright: dark ? Brightness.dark : Brightness.light,
          accentHex: look.accent,
          colorblindSafe: look.colorblindSafe,
          density: metrics.visualDensity,
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
      // Audit item 45: generated ARB localizations (en / id / ms).
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Scale UI to the device screen; clamp font inflation on small phones.
      // Audit item 37: the effective cap never exceeds 1.3 (1.0 on phones).
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final look = ref.watch(lookProvider);
        final m = NexusMetrics.of(context, touchMode: look.touchMode);
        final factor = mq.textScaler.scale(1.0).clamp(0.85, m.textScaleClamp);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(factor)),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
