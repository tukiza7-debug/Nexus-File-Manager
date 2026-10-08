/// Screen-aware metrics so the UI scales to the device it is installed on.
///
/// Uses [MediaQuery] shortest-side (logical dp) relative to a 360 dp reference
/// phone. Small phones get a denser chrome; large phones / foldables / tablets
/// get proportionally larger tiles without looking like a stretched desktop.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class NexusMetrics {
  const NexusMetrics({
    required this.scale,
    required this.isPhone,
    required this.isTablet,
    required this.isDesktopLayout,
    required this.gridMinTile,
    required this.gridPadding,
    required this.gridGap,
    required this.gridAspect,
    required this.listRowHeight,
    required this.glyphGrid,
    required this.glyphList,
    required this.tileFontSize,
    required this.titleBarHeight,
    required this.titleBarPadLeft,
    required this.sidebarDefaultOpen,
    required this.visualDensity,
    required this.textScaleClamp,
  });

  final double scale;
  final bool isPhone;
  final bool isTablet;
  final bool isDesktopLayout;

  final double gridMinTile;
  final double gridPadding;
  final double gridGap;
  final double gridAspect;
  final double listRowHeight;
  final double glyphGrid;
  final double glyphList;
  final double tileFontSize;
  final double titleBarHeight;
  final double titleBarPadLeft;
  final bool sidebarDefaultOpen;
  final VisualDensity visualDensity;
  final double textScaleClamp;

  /// Build metrics from the current [MediaQuery].
  ///
  /// Safe to call above [MaterialApp]: if no MediaQuery is in the tree yet
  /// (root [NexusApp] build), we fall back to [PlatformDispatcher] / a
  /// phone-sized default so startup never throws → grey native window.
  static NexusMetrics of(BuildContext context, {bool touchMode = false}) {
    final mq = MediaQuery.maybeOf(context);
    Size size;
    if (mq != null && mq.size.width > 0 && mq.size.height > 0) {
      size = mq.size;
    } else {
      // Root / first frame: approximate from the platform view.
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final v = views.first;
        final dpr = v.devicePixelRatio == 0 ? 1.0 : v.devicePixelRatio;
        size = Size(v.physicalSize.width / dpr, v.physicalSize.height / dpr);
      } else {
        size = const Size(360, 640); // compact phone fallback
      }
    }
    if (size.width <= 0 || size.height <= 0) {
      size = const Size(360, 640);
    }
    final shortest = size.shortestSide;
    final width = size.width;

    // Web / wide windows keep the desktop layout regardless of height.
    final desktop = kIsWeb || width >= 900;

    // Material-ish breakpoints on shortest side.
    final tablet = !desktop && shortest >= 600;
    final phone = !desktop && !tablet;

    // 360 dp ≈ typical compact phone. Clamp so tiny / huge screens stay sane.
    final scale = desktop ? 1.0 : (shortest / 360.0).clamp(0.82, 1.35);

    // Touch mode opts into larger hit targets on top of screen scale.
    final touchBoost = touchMode ? 1.18 : 1.0;

    double tile;
    if (desktop) {
      tile = touchMode ? 118.0 : 96.0;
    } else if (tablet) {
      tile = (92.0 * scale * touchBoost).clamp(88.0, 130.0);
    } else {
      tile = (78.0 * scale * touchBoost).clamp(68.0, 110.0);
    }

    final pad = desktop ? 12.0 : (8.0 * scale).clamp(6.0, 14.0);
    final gap = desktop ? 6.0 : (4.0 * scale).clamp(3.0, 8.0);

    final listH = desktop
        ? (touchMode ? 52.0 : 36.0)
        : ((touchMode ? 44.0 : 32.0) * scale).clamp(28.0, 52.0);

    final gGrid = desktop
        ? (touchMode ? 40.0 : 34.0)
        : ((touchMode ? 34.0 : 28.0) * scale).clamp(22.0, 40.0);
    final gList = desktop
        ? (touchMode ? 26.0 : 18.0)
        : ((touchMode ? 22.0 : 16.0) * scale).clamp(14.0, 26.0);

    final font = desktop
        ? (touchMode ? 13.0 : 12.0)
        : ((touchMode ? 12.0 : 11.0) * scale).clamp(10.0, 14.0);

    final titleH = desktop ? 46.0 : (40.0 * scale).clamp(36.0, 48.0);
    final titlePad = desktop ? 12.0 : (8.0 * scale).clamp(6.0, 12.0);

    // Density: tighter on small phones, standard on tablet/desktop.
    final density = desktop
        ? VisualDensity.comfortable
        : (shortest < 360
            ? const VisualDensity(horizontal: -2, vertical: -2)
            : VisualDensity.compact);

    // Cap system font inflation on phones so layout does not blow up.
    final textClamp = phone ? 1.0 : (tablet ? 1.1 : 1.3);

    return NexusMetrics(
      scale: scale,
      isPhone: phone,
      isTablet: tablet,
      isDesktopLayout: desktop,
      gridMinTile: tile,
      gridPadding: pad,
      gridGap: gap,
      gridAspect: phone ? 0.88 : 0.92,
      listRowHeight: listH,
      glyphGrid: gGrid,
      glyphList: gList,
      tileFontSize: font,
      titleBarHeight: titleH,
      titleBarPadLeft: titlePad,
      sidebarDefaultOpen: desktop,
      visualDensity: density,
      textScaleClamp: textClamp,
    );
  }
}
