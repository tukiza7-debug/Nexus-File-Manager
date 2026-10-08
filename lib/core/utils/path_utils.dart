/// Path manipulation helpers that behave identically on POSIX and Windows.
library;

/// Returns the final path segment ('' for root paths).
String basename(String p) {
  if (p.isEmpty) return '';
  final trimmed = _stripTrailing(p);
  final i = trimmed.lastIndexOf('/');
  final j = trimmed.lastIndexOf(r'\');
  final idx = i > j ? i : j;
  return idx < 0 ? trimmed : trimmed.substring(idx + 1);
}

/// Parent directory path (self-contained, does not rely on package:path).
String dirname(String p) {
  if (p.isEmpty) return p;
  final trimmed = _stripTrailing(p);
  final i = trimmed.lastIndexOf('/');
  final j = trimmed.lastIndexOf(r'\');
  final idx = i > j ? i : j;
  if (idx < 0) return p == trimmed ? p : trimmed;
  if (idx == 0) return trimmed[0];
  return trimmed.substring(0, idx);
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
  final sep = a.contains(r'\') ? r'\' : '/';
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
  final c = normalize(child), pt = normalize(parent);
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
