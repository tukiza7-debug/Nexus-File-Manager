import 'dart:collection';

import '../../domain/models.dart';

/// Myers O(ND) diff over lines with intra-line character refinement.
class DiffEngine {
  const DiffEngine();

  /// Produces aligned rows: same / removed / added / changed lines, where
  /// changed rows carry character-level [DiffSpan]s of what exactly moved.
  List<DiffLine> diffLines(
    String aText,
    String bText, {
    bool ignoreWhitespace = false,
  }) {
    final a = aText.split('\n');
    final b = bText.split('\n');
    String norm(String s) =>
        ignoreWhitespace ? s.replaceAll(RegExp(r'\s+'), ' ').trim() : s;

    final ops = _myers(
      [for (final l in a) norm(l)],
      [for (final l in b) norm(l)],
    );

    final out = <DiffLine>[];
    var ai = 0, bi = 0;
    var i = 0;
    while (i < ops.length) {
      if (ops[i] == _Op.same) {
        out.add(DiffLine(
          aNo: ai + 1,
          bNo: bi + 1,
          kind: DiffKind.same,
          text: a[ai],
        ));
        ai++;
        bi++;
        i++;
        continue;
      }
      // Collect the run of non-same ops and pair removes with adds.
      final removes = <String>[];
      final adds = <String>[];
      while (i < ops.length && ops[i] != _Op.same) {
        if (ops[i] == _Op.remove) {
          removes.add(a[ai]);
          ai++;
        } else {
          adds.add(b[bi]);
          bi++;
        }
        i++;
      }
      final aBase = ai - removes.length;
      final bBase = bi - adds.length;
      final paired =
          removes.length < adds.length ? removes.length : adds.length;
      for (var k = 0; k < paired; k++) {
        out.add(DiffLine(
          aNo: aBase + k + 1,
          bNo: bBase + k + 1,
          kind: DiffKind.changed,
          text: removes[k],
          spans: [_charDiff(removes[k], adds[k])],
        ));
      }
      for (var k = paired; k < removes.length; k++) {
        out.add(DiffLine(
          aNo: aBase + k + 1,
          bNo: null,
          kind: DiffKind.removed,
          text: removes[k],
        ));
      }
      for (var k = paired; k < adds.length; k++) {
        out.add(DiffLine(
          aNo: null,
          bNo: bBase + k + 1,
          kind: DiffKind.added,
          text: adds[k],
        ));
      }
    }
    return out;
  }

  /// Word-level diff between two strings (used by the toolbar compare view).
  List<DiffLine> diffWords(String a, String b) {
    final aw = a.split(RegExp(r'(\s+)'));
    final bw = b.split(RegExp(r'(\s+)'));
    final ops = _myers(aw, bw);
    final out = <DiffLine>[];
    var ai = 0, bi = 0;
    for (final op in ops) {
      switch (op) {
        case _Op.same:
          out.add(DiffLine(
              aNo: null, bNo: null, kind: DiffKind.same, text: aw[ai]));
          ai++;
          bi++;
        case _Op.remove:
          out.add(DiffLine(
              aNo: null, bNo: null, kind: DiffKind.removed, text: aw[ai]));
          ai++;
        case _Op.add:
          out.add(DiffLine(
              aNo: null, bNo: null, kind: DiffKind.added, text: bw[bi]));
          bi++;
      }
    }
    return out;
  }

  /// Classic Myers O(ND) over [a] and [b]; returns the edit script in order.
  static List<_Op> _myers(List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    if (n == 0 && m == 0) return const [];
    if (n == 0) return [for (var i = 0; i < m; i++) _Op.add];
    if (m == 0) return [for (var i = 0; i < n; i++) _Op.remove];

    final max = n + m;
    final offset = max;
    final v = HashMap<int, int>();
    final trace = <Map<int, int>>[];

    var found = false;
    for (var d = 0; d <= max && !found; d++) {
      trace.add(Map<int, int>.from(v));
      for (var k = -d; k <= d; k += 2) {
        int x;
        final down = k == -d ||
            (k != d && (v[k + 1 + offset] ?? 0) > (v[k - 1 + offset] ?? 0));
        if (down) {
          x = v[k + 1 + offset] ?? 0;
        } else {
          x = (v[k - 1 + offset] ?? 0) + 1;
        }
        var y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        v[k + offset] = x;
        if (x >= n && y >= m) {
          found = true;
          break;
        }
      }
    }

    // Backtrack from the final state to the start.
    final ops = <_Op>[];
    var x = n, y = m;
    for (var d = trace.length - 1; d >= 1; d--) {
      final vv = trace[d];
      final k = x - y;

      int prevK;
      final down = k == -d || (k != d && (vv[k + 1 + offset] ?? 0) > (vv[k - 1 + offset] ?? 0));
      if (down) {
        prevK = k + 1;
      } else {
        prevK = k - 1;
      }
      final prevX = vv[prevK + offset] ?? 0;
      final prevY = prevX - prevK;

      while (x > prevX && y > prevY) {
        ops.add(_Op.same);
        x--;
        y--;
      }
      if (x - prevX == 1 && y == prevY) {
        ops.add(_Op.remove);
        x--;
      } else if (y - prevY == 1 && x == prevX) {
        ops.add(_Op.add);
        y--;
      } else {
        // Diagonal snake consumes the remainder; fall back safely.
        while (x > prevX && y > prevY) {
          ops.add(_Op.same);
          x--;
          y--;
        }
        if (x > prevX) {
          ops.add(_Op.remove);
          x--;
        } else if (y > prevY) {
          ops.add(_Op.add);
          y--;
        }
      }
    }
    while (x > 0 && y > 0) {
      ops.add(_Op.same);
      x--;
      y--;
    }
    while (x > 0) {
      ops.add(_Op.remove);
      x--;
    }
    while (y > 0) {
      ops.add(_Op.add);
      y--;
    }
    return ops.reversed.toList();
  }

  /// Character-level diff span within a changed line pair.
  DiffSpan _charDiff(String a, String b) {
    var start = 0;
    final minLen = a.length < b.length ? a.length : b.length;
    while (start < minLen && a[start] == b[start]) {
      start++;
    }
    var endA = a.length, endB = b.length;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    if (start >= endA) {
      return DiffSpan(start, start, DiffKind.added);
    }
    return DiffSpan(start, endA, DiffKind.removed);
  }
}

enum _Op { same, remove, add }
