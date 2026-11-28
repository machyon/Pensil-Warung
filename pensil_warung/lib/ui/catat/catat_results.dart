import 'package:material_ui/material_ui.dart';

import '../../catat/parser.dart';
import '../../catat/result.dart';
import '../core/format.dart';
import '../core/theme.dart';

String resultHeader(LintResult r) {
  if (r.errors > 0 && r.warnings == 0) return 'Hasil baca · ${r.errors} perlu dicek';
  if (r.errors > 0) return 'Hasil baca · ${r.errors} salah · ${r.warnings} peringatan';
  if (r.warnings > 0) return 'Hasil baca · ${r.warnings} peringatan';
  return 'Hasil baca';
}

/// Errors first, then warnings, then the rest (the design's order).
List<LineResult> sortedLines(LintResult r) => [
      ...r.lines.where((l) => l.status == LineStatus.error),
      ...r.lines.where((l) => l.status == LineStatus.warning),
      ...r.lines.where((l) => l.status == LineStatus.ok),
    ];

class ResultsCard extends StatelessWidget {
  const ResultsCard({super.key, required this.result, required this.onFix, required this.onGoToLine, this.trailing});

  final LintResult result;
  final void Function(Fix) onFix;
  final void Function(int lineNo) onGoToLine;

  /// Extra widget at the end of a line's row (the photo button of a new product).
  final Widget? Function(LineResult)? trailing;

  @override
  Widget build(BuildContext context) {
    final lines = sortedLines(result);
    final firstError = lines.where((l) => l.status == LineStatus.error).firstOrNull;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(resultHeader(result).toUpperCase(),
                style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
          ),
          for (var i = 0; i < lines.length; i++)
            _Row(lines[i], first: i == 0, onFix: onFix, trailing: trailing?.call(lines[i])),
          if (firstError != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(children: [
                Expanded(
                  child: Text('${result.errors} baris perlu dibetulkan',
                      style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
                ),
                TextButton(
                  onPressed: () => onGoToLine(firstError.lineNo),
                  child: Text('Ke baris ${firstError.lineNo}', style: appText(14, weight: FontWeight.w700)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

String _detail(LineResult l) => switch (l.kind) {
      LineKind.sale => l.stockAfter == null ? l.message : '${l.message} · sisa stok ${l.stockAfter}',
      LineKind.createProduct => 'Barang baru · ${rupiah(l.unitPrice!)} · stok ${l.stockAfter}',
      LineKind.deleteProduct => 'Hapus barang · sisa stok ${l.stockAfter}',
      LineKind.adjustDown => 'Stok keluar ${l.quantity} · ${l.message}${l.reason == null ? '' : ' · ${l.reason}'}',
      _ => l.message,
    };

class _Row extends StatelessWidget {
  const _Row(this.l, {required this.first, required this.onFix, this.trailing});

  final LineResult l;
  final bool first;
  final void Function(Fix) onFix;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bad = l.status != LineStatus.ok;
    final isError = l.status == LineStatus.error;
    final color = isError ? AppColors.error : AppColors.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: isError ? AppColors.errorBg : AppColors.chip, shape: BoxShape.circle),
            child: Icon(
              isError ? Icons.error_outline_rounded : l.status == LineStatus.warning ? Icons.info_outline_rounded : Icons.check_rounded,
              size: 18,
              color: isError ? AppColors.error : AppColors.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bad) Text('Baris ${l.lineNo}', style: appText(12, weight: FontWeight.w700, color: AppColors.muted)),
                Text(bad ? l.raw : l.productName ?? l.raw, style: appText(16, weight: FontWeight.w700)),
                Text(bad ? l.message : _detail(l),
                    style: appText(13, weight: bad ? FontWeight.w600 : FontWeight.w500, color: bad ? color : AppColors.muted)),
                if (l.hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(TextSpan(style: appText(13, color: AppColors.muted), children: [
                      const TextSpan(text: 'Contoh: '),
                      TextSpan(text: l.hint, style: monoText(13)),
                    ])),
                  ),
                if (l.fixes.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in l.fixes)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            foregroundColor: AppColors.ink,
                            side: const BorderSide(color: AppColors.fieldBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: () => onFix(f),
                          child: Text(f.label, style: appText(14, weight: FontWeight.w700)),
                        ),
                      ),
                  ]),
              ],
            ),
          ),
          if (l.kind == LineKind.sale && !isError && l.lineTotal != null) ...[
            const SizedBox(width: 8),
            Text(rupiah(l.lineTotal!), style: appText(16, weight: FontWeight.w700)),
          ],
          ?trailing,
        ],
      ),
    );
  }
}
