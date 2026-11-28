import 'parser.dart';
import 'result.dart';

const notInTotal = 'Tidak masuk Total';

class SaleSummary {
  const SaleSummary(this.name, this.quantity, this.lineTotal);
  final String name;
  final int quantity, lineTotal;
}

class NewProductSummary {
  const NewProductSummary(this.name, this.price, this.stock);
  final String name;
  final int price, stock;
}

class PriceChangeSummary {
  const PriceChangeSummary(this.name, this.oldPrice, this.newPrice);
  final String name;
  final int oldPrice, newPrice;
}

class StockSummary {
  const StockSummary(this.name, this.quantity, {this.reason});
  final String name;
  final int quantity;
  final String? reason; // stock out only
  String? get note => reason == null ? null : notInTotal;
}

class DeleteSummary {
  const DeleteSummary(this.name, this.remainingStock);
  final String name;
  final int remainingStock;
  String get warning => '$name hilang dari Produk dan tidak bisa dibatalkan. Riwayat jualannya tetap ada.';
}

/// What [12] CatatKonfirmasi shows, built from a lint result.
class ConfirmSummary {
  ConfirmSummary(LintResult r) {
    for (final l in r.lines) {
      if (l.op == null || l.status == LineStatus.error) continue;
      final name = l.productName!;
      switch (l.kind) {
        case LineKind.sale:
          sales.add(SaleSummary(name, l.quantity!, l.lineTotal!));
        case LineKind.createProduct:
          newProducts.add(NewProductSummary(name, l.unitPrice!, l.stockAfter!));
        case LineKind.setPrice:
          priceChanges.add(PriceChangeSummary(name, l.previousPrice!, l.unitPrice!));
        case LineKind.restock:
          restocks.add(StockSummary(name, l.quantity!));
        case LineKind.adjustDown:
          stockOuts.add(StockSummary(name, l.quantity!, reason: l.reason));
        case LineKind.deleteProduct:
          deletions.add(DeleteSummary(name, l.stockAfter!));
      }
    }
    total = r.total;
    portions = r.portionCount;
    needsConfirm = r.ops.any((o) => o.op != 'sale');
  }

  final sales = <SaleSummary>[];
  final newProducts = <NewProductSummary>[];
  final priceChanges = <PriceChangeSummary>[];
  final restocks = <StockSummary>[];
  final stockOuts = <StockSummary>[];
  final deletions = <DeleteSummary>[];
  late final int total, portions;
  late final bool needsConfirm;

  int get items => sales.length;
}
