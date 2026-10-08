
import '../../domain/models.dart';
import '../utils/path_utils.dart' as pu;

/// Batch Rule Engine: evaluates if-then rules against entries.
class RuleEngine {
  const RuleEngine();

  bool matches(NexusRule rule, NexusEntry e) {
    if (rule.conditions.isEmpty) return false;
    var any = false;
    for (final c in rule.conditions) {
      final hit = _match(c, e);
      if (rule.match == 'any' && hit) return true;
      if (rule.match == 'all' && !hit) return false;
      any = any || hit;
    }
    return any;
  }

  bool _match(RuleCondition c, NexusEntry e) {
    switch (c.field) {
      case 'name':
        return _text(c.match, e.name, c.value);
      case 'ext':
        return _text(c.match, e.ext, c.value.toLowerCase());
      case 'path':
        return _text(c.match, e.path, c.value);
      case 'size':
        final target = _parseSize(c.value);
        return switch (c.match) {
          'gt' => e.size > target,
          'lt' => e.size < target,
          _ => e.size == target,
        };
      case 'mtime':
        final days = double.tryParse(c.value) ?? 0;
        final cutoff = DateTime.now().subtract(Duration(milliseconds: (days * 86400000).round()));
        return switch (c.match) {
          'within' => e.modified.isAfter(cutoff),
          'gt' => e.modified.isBefore(cutoff),
          _ => false,
        };
      default:
        return false;
    }
  }

  bool _text(String match, String actual, String value) => switch (match) {
        'contains' => actual.toLowerCase().contains(value.toLowerCase()),
        'equals' => actual.toLowerCase() == value.toLowerCase(),
        'glob' => _glob(actual, value),
        _ => false,
      };

  bool _glob(String s, String pattern) {
    final re = RegExp('^${RegExp.escape(pattern)
        .replaceAll(r'\*', '[^/]*')
        .replaceAll(r'\?', '.')
        .replaceAll(r'\[!', '[^')}\$', caseSensitive: false);
    return re.hasMatch(s);
  }

  static int _parseSize(String v) {
    final m = RegExp(r'^\s*([\d.]+)\s*([KMGT]?B?)\s*$', caseSensitive: false).firstMatch(v);
    if (m == null) return int.tryParse(v) ?? 0;
    final n = double.parse(m.group(1)!);
    final unit = (m.group(2) ?? 'B').toUpperCase();
    final mult = switch (unit) {
      'K' || 'KB' => 1024,
      'M' || 'MB' => 1024 * 1024,
      'G' || 'GB' => 1024 * 1024 * 1024,
      'T' || 'TB' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (n * mult).round();
  }

  /// Applies [rule] to [entries], returning per-entry planned actions.
  /// rename → new name; move/trash → flagged.
  List<RulePlanEntry> plan(NexusRule rule, List<NexusEntry> entries) {
    final out = <RulePlanEntry>[];
    for (final e in entries) {
      if (!matches(rule, e)) continue;
      for (final a in rule.actions) {
        out.add(switch (a.kind) {
          'rename' => RulePlanEntry(e, 'rename', _applyPattern(a.arg, e, out.length + 1)),
          'move' => RulePlanEntry(e, 'move', a.arg),
          'trash' => RulePlanEntry(e, 'trash', ''),
          'freeze' => RulePlanEntry(e, 'freeze', ''),
          _ => RulePlanEntry(e, 'noop', ''),
        });
      }
    }
    return out;
  }

  String _applyPattern(String pattern, NexusEntry e, int n) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return pattern
        .replaceAll('{n}', '$n')
        .replaceAll('{name}', pu.stem(e.name))
        .replaceAll('{ext}', e.ext)
        .replaceAll('{date}', '${now.year}-${two(now.month)}-${two(now.day)}')
        .replaceAll('{time}', '${two(now.hour)}${two(now.minute)}')
        .replaceAll('{size}', e.size.toString());
  }
}

class RulePlanEntry {
  const RulePlanEntry(this.entry, this.action, this.arg);
  final NexusEntry entry;
  final String action; // rename | move | trash | freeze | noop
  final String arg;
}
