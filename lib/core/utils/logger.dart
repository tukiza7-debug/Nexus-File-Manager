import 'package:flutter/foundation.dart';

/// Tiny centralized logger (audit item 46). Every previously swallowed
/// `catch (_) {}` now reports through here so failures are at least
/// observable in debug output / release logs, and the UI shows feedback
/// where a user action failed.
class NexusLog {
  NexusLog._();

  static void debug(String message) {
    if (!kReleaseMode) debugPrint('[nexus] $message');
  }

  static void warn(String message, [Object? error, StackTrace? stack]) {
    debugPrint('[nexus][warn] $message'
        '${error == null ? '' : ' — $error'}'
        '${stack == null ? '' : '\n$stack'}');
  }

  static void error(String message, [Object? error, StackTrace? stack]) {
    debugPrint('[nexus][error] $message'
        '${error == null ? '' : ' — $error'}'
        '${stack == null ? '' : '\n$stack'}');
  }
}

/// Convenience top-level functions.
void logDebug(String message) => NexusLog.debug(message);
void logWarn(String message, [Object? error, StackTrace? stack]) =>
    NexusLog.warn(message, error, stack);
void logError(String message, [Object? error, StackTrace? stack]) =>
    NexusLog.error(message, error, stack);
