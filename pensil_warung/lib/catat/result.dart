import 'parser.dart';
import '../domain/product.dart';

enum LineStatus { ok, warning, error }

/// A one-tap repair: [apply] returns the new box text. [cursorAt], when set, gives where the
/// caret goes in that new text.
class Fix {
  const Fix(this.label, this.apply, {this.cursorAt});

  final String label;
  final String Function(String text) apply;
  final int Function(String newText)? cursorAt;
}

/// `unitPrice` is the sale price, the new price of `set_price`, or the price of `create_product`.
/// `stockAfter` is the simulated stock after the line (for `delete_product`: the stock it had).
class LineResult {
  const LineResult({
    required this.lineNo,
    required this.raw,
    required this.kind,
    required this.status,
    required this.message,
    this.product,
    this.productName,
    this.quantity,
    this.unitPrice,
    this.previousPrice,
    this.lineTotal,
    this.stockAfter,
    this.reason,
    this.hint,
    this.op,
    this.fixes = const [],
  });

  final int lineNo;
  final String raw;
  final LineKind kind;
  final LineStatus status;
  final String message;
  final Product? product; // the existing product, null for one created in the text
  final String? productName;
  final int? quantity, unitPrice, previousPrice, lineTotal, stockAfter;
  final String? reason, hint;
  final Op? op;
  final List<Fix> fixes;

  LineResult asError(String message) => LineResult(
        lineNo: lineNo, raw: raw, kind: kind, status: LineStatus.error, message: message,
        product: product, productName: productName, quantity: quantity, unitPrice: unitPrice,
        previousPrice: previousPrice, lineTotal: lineTotal, stockAfter: stockAfter,
        reason: reason, hint: hint, op: null, fixes: const [],
      );
}

class LintResult {
  LintResult._(this.lines)
      : ops = [for (final l in lines) if (l.op != null && l.status != LineStatus.error) l.op!],
        total = lines.where((l) => l.kind == LineKind.sale).fold(0, (s, l) => s + (l.lineTotal ?? 0)),
        saleCount = lines.where((l) => l.op?.op == 'sale').length,
        portionCount = lines.where((l) => l.op?.op == 'sale').fold(0, (s, l) => s + (l.quantity ?? 0)),
        errors = lines.where((l) => l.status == LineStatus.error).length,
        warnings = lines.where((l) => l.status == LineStatus.warning).length;

  factory LintResult.fromLines(List<LineResult> lines) => LintResult._(lines);

  final List<LineResult> lines;
  final List<Op> ops;
  final int total, saleCount, portionCount, errors, warnings;

  bool get canSave => ops.isNotEmpty && errors == 0;
}
