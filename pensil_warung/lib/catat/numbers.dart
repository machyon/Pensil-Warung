/// Line tokenizer and number parsing for Catat. Pure Dart.
enum NumKind { integer, decimal, none }

class ParsedNumber {
  const ParsedNumber(this.kind, [this.value = 0]);
  final NumKind kind;
  final int value;
}

final _plain = RegExp(r'^\d+$');
final _thousands = RegExp(r'^\d{1,3}(\.\d{3})+$');
final _decimal = RegExp(r'^\d+[.,]\d+$');

/// `2000` and `2.000` are integers, `1,5` and `1.5` are decimals, anything else is not a number.
/// An integer too big for `int` comes back as -1.
ParsedNumber parseNumber(String t) {
  if (_plain.hasMatch(t) || _thousands.hasMatch(t)) {
    return ParsedNumber(NumKind.integer, int.tryParse(t.replaceAll('.', '')) ?? -1);
  }
  if (_decimal.hasMatch(t)) return const ParsedNumber(NumKind.decimal);
  return const ParsedNumber(NumKind.none);
}

List<String> tokenize(String line) {
  final t = line.trim();
  return t.isEmpty ? const [] : t.split(RegExp(r'\s+'));
}

/// Same rule as the server's `name_key`.
String nameKey(String s) => tokenize(s).join(' ').toLowerCase();

/// `15000` -> `Rp15.000`.
String rupiah(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}Rp$b';
}
