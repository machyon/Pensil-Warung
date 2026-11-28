import 'dart:math' as math;

int levenshtein(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(
        math.min(cur[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

/// The closest of [keys] to [key] (both already `nameKey`s): distance <= 2, or <= 30 % of the
/// length for long names, and always less than the whole word. Null when nothing is close.
String? closestKey(String key, Iterable<String> keys) {
  final limit = math.max(2, (key.length * 0.3).floor());
  String? best;
  var bestD = limit + 1;
  for (final k in keys) {
    final d = levenshtein(key, k);
    if (d < bestD && d < key.length) {
      best = k;
      bestD = d;
    }
  }
  return best;
}
