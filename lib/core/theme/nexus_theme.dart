/// Nexus design system — Material 3 deeply customized. Nothing here is the
/// stock Material look: bespoke palette, Inter typography, tight radii and
/// restrained elevation. Also hosts the colour-blind-safe pattern palette.
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;


import 'package:flutter/material.dart';

import '../../domain/enums.dart';

class NexusColors {
  const NexusColors._();

  // Brand navy from the logo.
  static const Color navy = Color(0xFF0A1628);
  static const Color blue = Color(0xFF2563EB);
  static const Color blueBright = Color(0xFF3B82F6);
  static const Color blueSoft = Color(0xFF60A5FA);

  // Dark surfaces (default).
  static const Color bgDark = Color(0xFF0B0E14);
  static const Color surfaceDark = Color(0xFF11151C);
  static const Color surface2Dark = Color(0xFF161B24);
  static const Color surface3Dark = Color(0xFF1C2230);
  static const Color borderDark = Color(0xFF232B3A);
  static const Color textDark = Color(0xFFE6EAF2);
  static const Color textDimDark = Color(0xFF8B94A7);

  // Light surfaces.
  static const Color bgLight = Color(0xFFF7F8FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surface2Light = Color(0xFFF1F3F9);
  static const Color surface3Light = Color(0xFFE7EBF4);
  static const Color borderLight = Color(0xFFD9DFEC);
  static const Color textLight = Color(0xFF161B26);
  static const Color textDimLight = Color(0xFF5D6678);

  // Semantic — colour-blind-safe de-emphasised with patterns when enabled.
  static const Color danger = Color(0xFFD2564E);
  static const Color warn = Color(0xFFC98A2B);
  static const Color ok = Color(0xFF3E9C6E);
  static const Color info = Color(0xFF4E8AD2);
}

/// Per-file-category hues. In colour-blind-safe mode these are paired with
/// [patternFor] overlays so categories stay distinguishable by texture.
Color categoryColor(FileCategory c, {bool colorblindSafe = false}) {
  if (colorblindSafe) {
    return switch (c) {
      FileCategory.folder => const Color(0xFF2563EB),
      FileCategory.image => const Color(0xFF7B5CB8),
      FileCategory.video => const Color(0xFF1F7A8C),
      FileCategory.audio => const Color(0xFFB85C7B),
      FileCategory.document => const Color(0xFF4E6BD2),
      FileCategory.archive => const Color(0xFF8A6D3B),
      FileCategory.code => const Color(0xFF2E8B6E),
      FileCategory.font => const Color(0xFF6E6AD2),
      FileCategory.executable => const Color(0xFF5C5F70),
      FileCategory.other => const Color(0xFF75809A),
    };
  }
  return switch (c) {
    FileCategory.folder => const Color(0xFF3B82F6),
    FileCategory.image => const Color(0xFF8B5CF6),
    FileCategory.video => const Color(0xFFEC4899),
    FileCategory.audio => const Color(0xFFF59E0B),
    FileCategory.document => const Color(0xFF10B981),
    FileCategory.archive => const Color(0xFFCA8A04),
    FileCategory.code => const Color(0xFF06B6D4),
    FileCategory.font => const Color(0xFF6366F1),
    FileCategory.executable => const Color(0xFFEF4444),
    FileCategory.other => const Color(0xFF94A3B8),
  };
}

/// Texture overlay used instead of relying on colour alone.
enum A11yPattern { none, hatch, dots, crossHatch, diagonalDots, solidRing }

A11yPattern patternFor(FileCategory c) => switch (c) {
      FileCategory.image => A11yPattern.hatch,
      FileCategory.video => A11yPattern.dots,
      FileCategory.document => A11yPattern.crossHatch,
      FileCategory.audio => A11yPattern.diagonalDots,
      FileCategory.archive => A11yPattern.solidRing,
      _ => A11yPattern.none,
    };

class NexusTheme {
  const NexusTheme._();

  static const fontFamily = 'Inter';

  static ThemeData build({
    required Brightness bright,
    required String accentHex,
    required bool colorblindSafe,
    VisualDensity? density,
  }) {
    final accent = _parseAccent(accentHex, bright);
    final isDark = bright == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: bright,
    ).copyWith(
      primary: accent,
      secondary: isDark ? NexusColors.blueSoft : NexusColors.blue,
      surface: isDark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
      surfaceContainerHighest:
          isDark ? NexusColors.surface3Dark : NexusColors.surface3Light,
      error: NexusColors.danger,
    );

    final textTheme = _textTheme(bright);

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? NexusColors.bgDark : NexusColors.bgLight,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: density ??
          ((!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              ? VisualDensity.compact
              : VisualDensity.comfortable),
      textTheme: textTheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha:  0.30),
        selectionHandleColor: accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
        iconTheme: IconThemeData(
            color: isDark ? NexusColors.textDark : NexusColors.textLight),
      ),
      cardTheme: CardThemeData(
        color: isDark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isDark ? NexusColors.borderDark : NexusColors.borderLight),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? NexusColors.borderDark : NexusColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? NexusColors.surface2Dark : NexusColors.surface2Light,
        hintStyle: TextStyle(
            color: isDark ? NexusColors.textDimDark : NexusColors.textDimLight),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? NexusColors.borderDark : NexusColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? NexusColors.borderDark : NexusColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(40, 38),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? NexusColors.textDark : NexusColors.textLight,
          side: BorderSide(
              color: isDark ? NexusColors.borderDark : NexusColors.borderLight),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(40, 38),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor:
              isDark ? NexusColors.textDimDark : NexusColors.textDimLight,
          focusColor: accent.withValues(alpha:  0.25),
          hoverColor: (isDark ? NexusColors.surface3Dark : NexusColors.surface3Light),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(
            color: isDark ? NexusColors.borderDark : NexusColors.borderLight,
            width: 1.4),
      ),
      sliderTheme: const SliderThemeData(),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : null),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
              isDark ? NexusColors.surface2Dark : NexusColors.surfaceLight),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color:
                    isDark ? NexusColors.borderDark : NexusColors.borderLight),
          )),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? NexusColors.surface2Dark : NexusColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isDark ? NexusColors.borderDark : NexusColors.borderLight),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? NexusColors.surface3Dark : NexusColors.navy,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
            color: Colors.white, fontSize: 12, fontFamily: fontFamily),
        waitDuration: const Duration(milliseconds: 450),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? NexusColors.surface3Dark : NexusColors.navy,
        contentTextStyle: const TextStyle(
            color: Colors.white, fontSize: 13, fontFamily: fontFamily),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.hovered) ? 10.0 : 6.0),
        thumbColor: WidgetStateProperty.resolveWith((s) => s
                .contains(WidgetState.hovered)
            ? (isDark ? NexusColors.textDimDark : NexusColors.textDimLight)
                .withValues(alpha:  0.85)
            : (isDark ? NexusColors.borderDark : NexusColors.borderLight)
                .withValues(alpha:  0.9)),
        radius: const Radius.circular(8),
        minThumbLength: 48,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        iconColor: isDark ? NexusColors.textDimDark : NexusColors.textDimLight,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(
            color: accent, fontWeight: FontWeight.w600, fontFamily: fontFamily),
        unselectedLabelTextStyle: TextStyle(
            color:
                isDark ? NexusColors.textDimDark : NexusColors.textDimLight,
            fontFamily: fontFamily),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor:
            isDark ? NexusColors.textDimDark : NexusColors.textDimLight,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? NexusColors.surface2Dark : NexusColors.surface2Light,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.labelLarge,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor:
            isDark ? NexusColors.surface3Dark : NexusColors.surface3Light,
        circularTrackColor:
            isDark ? NexusColors.surface3Dark : NexusColors.surface3Light,
      ),
    );
  }

  static TextTheme _textTheme(Brightness bright) {
    final base = bright == Brightness.dark
        ? const TextTheme(
            displayLarge: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: NexusColors.textDark),
            displayMedium: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: NexusColors.textDark),
            headlineLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: NexusColors.textDark),
            headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: NexusColors.textDark),
            headlineSmall: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: NexusColors.textDark),
            titleLarge: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: NexusColors.textDark),
            titleMedium: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: NexusColors.textDark),
            titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NexusColors.textDark),
            bodyLarge: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: NexusColors.textDark),
            bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: NexusColors.textDark),
            bodySmall: TextStyle(fontSize: 12.5, color: NexusColors.textDimDark),
            labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NexusColors.textDark),
            labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: NexusColors.textDimDark),
            labelSmall: TextStyle(fontSize: 10.5, letterSpacing: 0.4, color: NexusColors.textDimDark),
          )
        : const TextTheme(
            displayLarge: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: NexusColors.textLight),
            displayMedium: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: NexusColors.textLight),
            headlineLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: NexusColors.textLight),
            headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: NexusColors.textLight),
            headlineSmall: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: NexusColors.textLight),
            titleLarge: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: NexusColors.textLight),
            titleMedium: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: NexusColors.textLight),
            titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NexusColors.textLight),
            bodyLarge: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: NexusColors.textLight),
            bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: NexusColors.textLight),
            bodySmall: TextStyle(fontSize: 12.5, color: NexusColors.textDimLight),
            labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NexusColors.textLight),
            labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: NexusColors.textDimLight),
            labelSmall: TextStyle(fontSize: 10.5, letterSpacing: 0.4, color: NexusColors.textDimLight),
          );
    return base;
  }

  static Color _parseAccent(String hex, Brightness bright) {
    final cleaned = hex.replaceFirst(RegExp(r'^#?(0x)?', caseSensitive: false), '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null || value < 0 || value > 0xFFFFFFFF) {
      return bright == Brightness.dark ? NexusColors.blueBright : NexusColors.blue;
    }
    return Color(value);
  }
}

/// Paints the accessibility pattern overlay for a tile badge.
class PatternPainter extends CustomPainter {
  PatternPainter(this.pattern, this.color, {this.strokeWidth = 1.2});

  final A11yPattern pattern;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pattern) {
      case A11yPattern.none:
        return;
      case A11yPattern.hatch:
        _lines(canvas, size, Offset(0, size.height), Offset(size.width, 0), 6);
      case A11yPattern.crossHatch:
        _lines(canvas, size, Offset(0, size.height), Offset(size.width, 0), 6);
        _lines(canvas, size, Offset.zero, Offset(size.width, size.height), 6);
      case A11yPattern.dots:
        _dots(canvas, size, 5, 5, 1.4);
      case A11yPattern.diagonalDots:
        _dots(canvas, size, 6, 6, 1.4, diagonal: true);
      case A11yPattern.solidRing:
        canvas.drawCircle(
          Offset(size.width / 2, size.height / 2),
          size.shortestSide / 2 - 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color,
        );
    }
  }

  void _lines(Canvas canvas, Size size, Offset from, Offset to, double gap) {
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    // Diagonal stroke direction implied by from→to; repeat across the rect.
    final rising = to.dy < from.dy; // '/' vs '\'
    if (rising) {
      for (var x = -size.height; x < size.width; x += gap) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
      }
    } else {
      for (var x = 0.0; x < size.width + size.height; x += gap) {
        canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), p);
      }
    }
  }

  void _dots(Canvas canvas, Size size, double dx, double dy, double r,
      {bool diagonal = false}) {
    final p = Paint()..color = color;
    final off = diagonal ? dx / 2 : 0.0;
    for (var y = 0.0; y < size.height; y += dy) {
      for (var x = 0.0; x < size.width; x += dx) {
        canvas.drawCircle(Offset(x + off, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color;
}
