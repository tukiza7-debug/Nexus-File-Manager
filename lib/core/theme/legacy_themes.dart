/// Legacy Themes — faithful Windows 98, XP and 7 personality packs built as
/// real ThemeData plus per-brand decoration snippets. Not jokes: usable
/// chrome, authentic palettes and period-correct typography.
library;

import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import 'nexus_theme.dart';

class LegacyDecor {
  const LegacyDecor({
    required this.shellGradient,
    required this.chromeColor,
    required this.borderColor,
    required this.titleBarGradient,
    required this.squared,
    required this.bevel,
  });

  final Gradient? shellGradient;
  final Color chromeColor;
  final Color borderColor;
  final Gradient titleBarGradient;
  final bool squared; // 98 keeps 90° corners everywhere
  final bool bevel; // 98-style outset borders
}

class LegacyThemes {
  const LegacyThemes._();

  static ThemeData win98() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF000080),
      secondary: Color(0xFF000080),
      surface: Color(0xFFC0C0C0),
      surfaceContainerHighest: Color(0xFFC0C0C0),
      error: Color(0xFF800000),
    );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: NexusTheme.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF008080),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black),
        titleMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.black),
        bodyMedium: TextStyle(fontSize: 13, color: Colors.black),
        bodySmall: TextStyle(fontSize: 12, color: Color(0xFF404040)),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
      ),
      splashFactory: NoSplash.splashFactory,
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFFC0C0C0),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: _BevelBorder(inset: true),
        enabledBorder: _BevelBorder(inset: true),
        focusedBorder: _BevelBorder(inset: true),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFC0C0C0),
          foregroundColor: Colors.black,
          elevation: 0,
          shape: const RoundedRectangleBorder(),
          side: const BorderSide(color: Color(0xFF808080)),
          minimumSize: const Size(75, 28),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFFC0C0C0),
          foregroundColor: Colors.black,
          side: const BorderSide(color: Color(0xFF808080)),
          shape: const RoundedRectangleBorder(),
          minimumSize: const Size(75, 28),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFFC0C0C0),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Color(0xFFC0C0C0)),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFFC0C0C0),
        elevation: 0,
        shape: RoundedRectangleBorder(),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF808080)),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(16),
        thumbColor: WidgetStateProperty.all(const Color(0xFFC0C0C0)),
        radius: Radius.zero,
        crossAxisMargin: 0,
        mainAxisMargin: 0,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Color(0xFFC0C0C0),
        selectedColor: Colors.white,
        iconColor: Colors.black,
      ),
    );
    return base;
  }

  static ThemeData winxp() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF0A246A),
      secondary: Color(0xFF316AC5),
      surface: Color(0xFFECE9D8),
      surfaceContainerHighest: Color(0xFFDCD8C8),
      error: Color(0xFFB3261E),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: NexusTheme.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF3A6EA5),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFF0A246A)),
        titleMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.black),
        bodyMedium: TextStyle(fontSize: 13, color: Colors.black),
        bodySmall: TextStyle(fontSize: 12, color: Color(0xFF4A4A4A)),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFECE9D8),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: Color(0xFF7F9DB9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: Color(0xFF7F9DB9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: Color(0xFF316AC5), width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFECE9D8),
          foregroundColor: Colors.black,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          side: const BorderSide(color: Color(0xFF003C74)),
          minimumSize: const Size(75, 26),
        ),
      ),
      textButtonTheme:
          TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFF0A246A))),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFECE9D8),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF919B9C)),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(16),
        thumbColor: WidgetStateProperty.all(const Color(0xFF9DB9EB)),
        radius: const Radius.circular(2),
        crossAxisMargin: 0,
        mainAxisMargin: 0,
      ),
    );
  }

  static ThemeData win7() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF1F6FB2),
      secondary: Color(0xFF1F6FB2),
      surface: Color(0xFFF0F0F0),
      onSurface: Color(0xFF1A1A1A),
      surfaceContainerHighest: Color(0xFFE2E6ED),
      error: Color(0xFFB3261E),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: NexusTheme.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF5A7EDC),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
        titleMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        bodyMedium: TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
        bodySmall: TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFF0F0F0),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFFB6BCCC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFFB6BCCC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFF3C7FB1), width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE5E9F0),
          foregroundColor: const Color(0xFF1A1A1A),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: const BorderSide(color: Color(0xFF8D9AAE)),
          minimumSize: const Size(75, 26),
        ),
      ),
      textButtonTheme:
          TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFF1F6FB2))),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFFF0F0F0),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: Colors.black.withOpacity( 0.25)),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFF0F0F0),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: Colors.black.withOpacity( 0.18)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFB6BCCC)),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(14),
        thumbColor: WidgetStateProperty.all(const Color(0xFFBFC7D6)),
        radius: const Radius.circular(7),
      ),
    );
  }

  static LegacyDecor decorFor(ThemeBrand brand, Brightness bright) => switch (brand) {
        ThemeBrand.nexus => LegacyDecor(
            shellGradient: null,
            chromeColor: bright == Brightness.dark
                ? NexusColors.surfaceDark
                : NexusColors.surfaceLight,
            borderColor:
                bright == Brightness.dark ? NexusColors.borderDark : NexusColors.borderLight,
            titleBarGradient: bright == Brightness.dark
                ? const LinearGradient(colors: [Color(0xFF11151C), Color(0xFF0B0E14)])
                : const LinearGradient(colors: [Colors.white, Color(0xFFF1F3F9)]),
            squared: false,
            bevel: false,
          ),
        ThemeBrand.win98 => const LegacyDecor(
            shellGradient: LinearGradient(colors: [Color(0xFF008080), Color(0xFF008080)]),
            chromeColor: Color(0xFFC0C0C0),
            borderColor: Colors.black,
            titleBarGradient: LinearGradient(
                colors: [Color(0xFF000080), Color(0xFF1084D0)]),
            squared: true,
            bevel: true,
          ),
        ThemeBrand.winxp => const LegacyDecor(
            shellGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5A7EDC), Color(0xFF3A6EA5), Color(0xFF2C5A8C)],
            ),
            chromeColor: Color(0xFFECE9D8),
            borderColor: Color(0xFF7F9DB9),
            titleBarGradient: LinearGradient(
                colors: [Color(0xFF0058EE), Color(0xFF3F8CF3), Color(0xFF0054E3)]),
            squared: false,
            bevel: false,
          ),
        ThemeBrand.win7 => const LegacyDecor(
            shellGradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF6B8DD6), Color(0xFF4A6CB3), Color(0xFF305496)],
            ),
            chromeColor: Color(0xFFF0F0F0),
            borderColor: Color(0xFF8D9AAE),
            titleBarGradient: LinearGradient(
                colors: [Color(0xFF8BAFDC), Color(0xFF5B7DB1), Color(0xFF3A5F94)]),
            squared: false,
            bevel: false,
          ),
      };
}

/// Outset/inset 2px bevel used by the Windows 98 brand.
class _BevelBorder extends InputBorder {
  const _BevelBorder({this.inset = false});

  final bool inset;

  static const _none = BorderSide.none;

  @override
  BorderSide get borderSide => _none;

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(2);

  @override
  _BevelBorder copyWith({BorderSide? borderSide}) => this;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()
    ..addRect(Rect.fromLTWH(
        rect.left + 2, rect.top + 2, rect.width - 4, rect.height - 4));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect,
      {double? gapStart,
      double? gapEnd,
      double gapExtent = 0,
      double gapPercentage = 0,
      TextDirection? textDirection}) {
    const light = Color(0xFFFFFFFF);
    const dark = Color(0xFF808080);
    const black = Color(0xFF000000);
    final r = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
    Paint stroke(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c;
    if (inset) {
      canvas.drawLine(r.topLeft, r.topRight, stroke(dark));
      canvas.drawLine(r.topLeft, r.bottomLeft, stroke(dark));
      canvas.drawLine(r.bottomRight, r.topRight, stroke(light));
      canvas.drawLine(r.bottomRight, r.bottomLeft, stroke(light));
    } else {
      canvas.drawLine(r.topLeft, r.topRight, stroke(light));
      canvas.drawLine(r.topLeft, r.bottomLeft, stroke(light));
      canvas.drawLine(r.bottomRight, r.topRight, stroke(black));
      canvas.drawLine(r.bottomRight, r.bottomLeft, stroke(black));
    }
  }

  @override
  ShapeBorder scale(double t) => this;
}

