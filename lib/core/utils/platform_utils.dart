import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform capability helpers shared by the interaction layer.
library;

/// True on devices where primary interaction is touch (phones / tablets).
/// Used to pick tap-to-open vs double-click, Draggable vs
/// LongPressDraggable and touch-sized hit targets (audit items 26-27).
bool get isTouchDevice {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// True when the current platform needs desktop-style chrome strings
/// ("Ctrl Z", "Right-click"). Mobile shows touch wording instead (item 41).
bool get useDesktopHints => !isTouchDevice;

/// True on Apple platforms where the primary modifier is Command (⌘).
bool get isApplePlatform {
  if (kIsWeb) return false;
  try {
    return Platform.isMacOS || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// Audit item 41: platform-aware modifier label — "⌘" on Apple platforms,
/// "Ctrl" elsewhere. Used in tooltips, palette hints and confirmations.
String get modifierKey => isApplePlatform ? '⌘' : 'Ctrl';
