/// Pure-Dart formatting helpers (no intl dependency).
library;

const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

String formatSize(num bytes) {
  if (bytes < 0) return '—';
  if (bytes < 1000) return '${bytes}B';
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1000 && i < _units.length - 1) {
    v /= 1024;
    i++;
  }
  return v >= 100
      ? '${v.toStringAsFixed(0)} ${_units[i]}'
      : '${v.toStringAsFixed(1)} ${_units[i]}';
}

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String formatTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String formatDateTime(DateTime d) => '${formatDate(d)} ${formatTime(d)}';

String formatRelative(DateTime d, {DateTime? now}) {
  now ??= DateTime.now();
  final diff = now.difference(d);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return formatDate(d);
  return formatDate(d);
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 12,345 → "12.3 k"; used for compact counters.
String compact(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)} k';
  return '${(n / 1000000).toStringAsFixed(1)} M';
}

DateTime? tryParseDate(String s) {
  final d = DateTime.tryParse(s);
  if (d != null) return d;
  final m = RegExp(r'^(\d{4})[:-](\d{2})[:-](\d{2})[ T]?(\d{2})?:?(\d{2})?')
      .firstMatch(s.trim());
  if (m == null) return null;
  return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.tryParse(m.group(4) ?? '') ?? 0,
      int.tryParse(m.group(5) ?? '') ?? 0);
}
