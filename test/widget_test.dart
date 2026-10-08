import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_file_manager/core/theme/legacy_themes.dart';
import 'package:nexus_file_manager/core/theme/nexus_theme.dart';
import 'package:nexus_file_manager/domain/enums.dart';

void main() {
  test('Nexus theme builds for both brightness modes with Inter typography', () {
    for (final bright in Brightness.values) {
      final theme = NexusTheme.build(
        bright: bright,
        accentHex: '0xFF2563EB',
        colorblindSafe: false,
      );
      expect(theme.useMaterial3, isTrue);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.colorScheme.primary, const Color(0xFF2563EB));
    }
  });

  test('invalid accent hex falls back to brand blue', () {
    final theme = NexusTheme.build(
      bright: Brightness.dark,
      accentHex: 'not-a-color',
      colorblindSafe: false,
    );
    expect(theme.colorScheme.primary, NexusColors.blueBright);
  });

  test('every file category has a colour and a pattern in a11y mode', () {
    for (final c in FileCategory.values) {
      expect(categoryColor(c, colorblindSafe: true), isA<Color>());
      expect(categoryColor(c), isA<Color>());
    }
    expect(patternFor(FileCategory.image), A11yPattern.hatch);
    expect(patternFor(FileCategory.video), A11yPattern.dots);
    expect(patternFor(FileCategory.other), A11yPattern.none);
  });

  test('legacy theme brands all build', () {
    expect(LegacyThemes.win98().textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(LegacyThemes.winxp().colorScheme.surface, const Color(0xFFECE9D8));
    expect(LegacyThemes.win7().colorScheme.primary, const Color(0xFF1F6FB2));
  });
}
