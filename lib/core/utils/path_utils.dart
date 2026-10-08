/// Path manipulation helpers that behave identically on POSIX and Windows.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// True when running on Windows (guarded for web where dart:io is absent).
bool get isWindowsPlatform {
  if (kIsWeb) return false;
  try {
    return Platform.isWindows;
  } catch (_) {
    return false;
  }
}

/// Returns the final path segment ('' for root paths).
///
/// The backslash is treated as a separator only on Windows; on POSIX a
/// backslash is a legal filename character (audit item R8).
String basename(String p) {
  if (p.isEmpty) return '';
  final trimmed = _stripTrailing(p);
  var i = trimmed.lastIndexOf('/');
  if (isWindowsPlatform) {
    final j = trimmed.lastIndexOf(r'\');
    if (j > i) i = j;
  }
  return i < 0 ? trimmed : trimmed.substring(i + 1);
}

/// Parent directory path (self-contained, does not rely on package:path).
String dirname(String p) {
  if (p.isEmpty) return p;
  final trimmed = _stripTrailing(p);
  var i = trimmed.lastIndexOf('/');
  if (isWindowsPlatform) {
    final j = trimmed.lastIndexOf(r'\');
    if (j > i) i = j;
  }
  if (i < 0) return p == trimmed ? p : trimmed;
  if (i == 0) return trimmed[0];
  return trimmed.substring(0, i);
}

String extension(String p) {
  final b = basename(p);
  final i = b.lastIndexOf('.');
  if (i <= 0) return '';
  return b.substring(i + 1).toLowerCase();
}

/// Extension without the leading dot, lowercased ('' when none).
String ext(String p) => extension(p);

String stem(String p) {
  final b = basename(p);
  final i = b.lastIndexOf('.');
  return i <= 0 ? b : b.substring(0, i);
}

/// 'report.pdf' + 2 → 'report (2).pdf'.
String withCounter(String p, int n) {
  if (n <= 1) return p;
  final d = dirname(p), b = basename(p), e = ext(p);
  final base = e.isEmpty ? b : b.substring(0, b.length - e.length - 1);
  return join(d, '$base ($n)${e.isEmpty ? '' : '.$e'}');
}

String join(String a, String b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  final sep = isWindowsPlatform && a.contains(r'\') ? r'\' : '/';
  final left = a.endsWith(sep) || a.endsWith('/') ? a : '$a$sep';
  return '$left${b.startsWith(sep) || b.startsWith('/') ? b.substring(1) : b}';
}

/// Compact display keeping the last [segments] path components.
String compactPath(String p, {int segments = 2}) {
  final parts = p.replaceAll(r'\', '/').split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length <= segments) return p;
  return '…/${parts.sublist(parts.length - segments).join('/')}';
}

bool isUnder(String child, String parent) {
  final c = _normForCompare(child), pt = _normForCompare(parent);
  if (c == pt) return true;
  if (pt == '/' || pt.isEmpty) return true;
  final prefix = pt.endsWith('/') ? pt : '$pt/';
  return c.startsWith(prefix);
}

String normalize(String p) {
  var out = p.replaceAll(r'\', '/');
  if (out.length > 1 && out.endsWith('/')) out = out.substring(0, out.length - 1);
  return out;
}

/// Case-insensitive comparison on Windows (audit item S25): `C:\Foo` and
/// `c:\foo` must not bypass freeze or duplicate detection.
String _normForCompare(String p) {
  final n = normalize(p);
  return isWindowsPlatform ? n.toLowerCase() : n;
}

/// True when [a] and [b] refer to the same path lexically (separator and
/// case handling included). Use with [dart:io] `identicalSync` for the
/// filesystem-level check.
bool samePath(String a, String b) => _normForCompare(a) == _normForCompare(b);

/// Result of [validateName]: null when the name is acceptable, otherwise a
/// user-facing error message (audit item 7).
String? validateName(String? name, {int maxLength = 240}) {
  if (name == null) return 'Name is required';
  if (name.trim().isEmpty) return 'Name cannot be empty';
  if (name == '.' || name == '..') return 'Name cannot be "." or ".."';
  if (name.contains('/') || name.contains(r'\')) {
    return 'Name cannot contain / or \\';
  }
  if (name.contains('\x00')) return 'Name contains invalid characters';
  if (name.length > maxLength) return 'Name is too long (max $maxLength characters)';
  // Windows reserved device names are invalid everywhere we might sync to.
  final stemOnly = name.contains('.') ? name.substring(0, name.indexOf('.')) : name;
  const reserved = {
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };
  if (reserved.contains(stemOnly.toUpperCase())) {
    return '"$stemOnly" is a reserved device name';
  }
  if (name.endsWith('.') || name.endsWith(' ')) {
    return 'Name cannot end with a dot or a space';
  }
  for (final r in name.runes) {
    if (r < 0x20) return 'Name contains control characters';
  }
  return null;
}

/// Throws [FormatException] when [name] fails [validateName].
void checkName(String name, {int maxLength = 240}) {
  final err = validateName(name, maxLength: maxLength);
  if (err != null) throw FormatException(err, name);
}

/// Natural sort key: "file2" < "file10".
String naturalKey(String s) {
  final b = StringBuffer();
  var num = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch).toLowerCase();
    if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
      num.write(c);
    } else {
      if (num.isNotEmpty) {
        b.write(num.toString().padLeft(12, '0'));
        num = StringBuffer();
      }
      b.write(c);
    }
  }
  if (num.isNotEmpty) b.write(num.toString().padLeft(12, '0'));
  return b.toString();
}

String _stripTrailing(String p) {
  var t = p;
  while (t.length > 1 && (t.endsWith('/') || t.endsWith(r'\'))) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}
