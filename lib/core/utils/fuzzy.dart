/// Tiny fuzzy matcher (subsequence + score) powering the command palette,
/// session switcher, paper-trail search and the explorer filter.
library;

class FuzzyMatch {
  const FuzzyMatch(this.score, this.indices);
  final int score;
  final List<int> indices;
}

FuzzyMatch? fuzzyScore(String query, String target) {
  if (query.isEmpty) return const FuzzyMatch(1, []);
  final q = query.toLowerCase();
  final t = target.toLowerCase();
  var qi = 0, score = 0, streak = 0;
  final idx = <int>[];
  var lastMatch = -2;
  for (var ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] == q[qi]) {
      idx.add(ti);
      streak = ti == lastMatch + 1 ? streak + 1 : 1;
      score += 8 + streak * 4;
      if (ti == 0 || '/ _-. '.contains(t[ti - 1])) score += 10;
      lastMatch = ti;
      qi++;
    }
  }
  if (qi < q.length) return null;
  score -= (t.length - idx.length) ~/ 4;
  return FuzzyMatch(score, idx);
}

/// Best score across the haystack fields (e.g. name + path).
int fuzzyBest(String query, Iterable<String> fields) {
  var best = 0;
  for (final f in fields) {
    final m = fuzzyScore(query, f);
    if (m != null && m.score > best) best = m.score;
  }
  return best;
}
