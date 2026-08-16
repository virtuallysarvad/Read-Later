/// Fuzzy text matching for the search bar.
///
/// A query matches a target when any of these hold (ranked best → worst):
///  1. the query is a **substring** of the target (e.g. "read" in "reading"),
///  2. the query is a **subsequence** — characters appear in order with skips
///     (e.g. "nyt" in "The New York Times"),
///  3. the query is within a few **single-character edits** of the target
///     (e.g. "reidng" → "reading"), guarding against length differences so
///     short queries never match long text by accident.
library;

import 'dart:math' as math;

/// Returns a relevance score for how well [query] matches [target], or null
/// when there is no fuzzy match. Lower scores are better matches.
double? fuzzyScore(String query, String target) {
  final q = query.trim().toLowerCase();
  final t = target.trim().toLowerCase();
  if (q.isEmpty || t.isEmpty) return null;

  // Exact substring: score by how early it appears in the target.
  final start = t.indexOf(q);
  if (start != -1) {
    return start / math.max(1, t.length);
  }

  // Subsequence: score by how early it starts and how tightly packed it is.
  final subsequence = _subsequenceScore(q, t);
  if (subsequence != null) return subsequence;

  // Typo within a single word of the target (e.g. "reidng" matches a title
  // whose first word is "Reading"). Comparing word-by-word keeps the edit
  // distance meaningful no matter how long the target is.
  final wordEdit = _wordEditScore(q, t);
  if (wordEdit != null) return wordEdit;

  // Edit distance against the whole target, for queries that are nearly the
  // target's length (e.g. "hllo wrld" vs "hello world"). An edit distance
  // is never smaller than the length difference, so anything much longer or
  // shorter than the query can't match — this keeps the expensive comparison
  // away from long excerpts.
  final maxEdits = _maxEdits(q.length);
  if ((t.length - q.length).abs() > maxEdits) return null;
  final distance = _osaDistance(q, t);
  if (distance <= maxEdits) {
    return 1 + distance / math.max(1, q.length);
  }
  return null;
}

/// Best edit-distance score between [q] and any single word of [t], or null
/// when no word is close enough.
double? _wordEditScore(String q, String t) {
  final maxEdits = _maxEdits(q.length);
  double? best;
  for (final word in t.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if ((word.length - q.length).abs() > maxEdits) continue;
    final distance = _osaDistance(q, word);
    if (distance <= maxEdits) {
      final score = 1 + distance / math.max(1, q.length);
      if (best == null || score < best) best = score;
    }
  }
  return best;
}

/// How many single-character edits a query of [queryLength] is allowed.
int _maxEdits(int queryLength) => math.max(1, (queryLength * 0.4).floor());

/// Matches when every character of [q] appears in [t] in order (skips
/// allowed). Returns a score that prefers early, tightly-packed matches.
double? _subsequenceScore(String q, String t) {
  var targetIndex = 0;
  var first = -1;
  var gaps = 0;
  var previous = -1;

  for (var qi = 0; qi < q.length; qi++) {
    final ch = q.codeUnitAt(qi);
    var found = false;
    while (targetIndex < t.length) {
      final isMatch = t.codeUnitAt(targetIndex) == ch;
      targetIndex++;
      if (isMatch) {
        if (first == -1) first = targetIndex - 1;
        if (previous != -1 && targetIndex - 1 - previous > 1) gaps++;
        previous = targetIndex - 1;
        found = true;
        break;
      }
    }
    if (!found) return null;
  }

  return 1 + (first / math.max(1, t.length)) + gaps / math.max(1, q.length);
}

/// Optimal string alignment distance (Damerau–Levenshtein): insertions,
/// deletions, substitutions, and adjacent transpositions (so "teh" → "the"
/// costs one edit, not two).
int _osaDistance(String a, String b) {
  final m = a.length;
  final n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;

  final d = List.generate(m + 1, (i) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= n; j++) {
    d[0][j] = j;
  }

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      final cost =
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = math.min(
        math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
        d[i - 1][j - 1] + cost,
      );
      // Adjacent transposition (e.g. "teh" ↔ "the").
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        best = math.min(best, d[i - 2][j - 2] + 1);
      }
      d[i][j] = best;
    }
  }
  return d[m][n];
}
