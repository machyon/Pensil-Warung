/// One line of a transaction (name and price are the snapshot taken at sale time).
class TxItem {
  const TxItem({required this.id, required this.productId, required this.name, required this.unitPrice, required this.quantity, required this.lineTotal});

  factory TxItem.fromJson(Map<String, dynamic> j) => TxItem(
        id: j['id'] as int,
        productId: j['product_id'] as int?,
        name: j['product_name'] as String,
        unitPrice: j['unit_price'] as int,
        quantity: j['quantity'] as int,
        lineTotal: j['line_total'] as int,
      );

  final int id, unitPrice, quantity, lineTotal;
  final int? productId; // null once the product was deleted
  final String name;
}

/// An older version of a revised sale.
class TxVersion {
  TxVersion.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        total = j['total'] as int,
        revisedAt = DateTime.parse(j['revised_at'] as String),
        items = [for (final i in j['items'] as List) TxItem.fromJson(i as Map<String, dynamic>)];

  final int id, total;
  final DateTime revisedAt;
  final List<TxItem> items;
}

/// `GET /transactions/{id}`.
class Transaction {
  Transaction.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        rawText = j['raw_text'] as String,
        total = j['total'] as int,
        voided = j['status'] == 'voided',
        occurredAt = DateTime.parse(j['occurred_at'] as String),
        voidReason = j['void_reason'] as String?,
        replacesId = j['replaces_id'] as int?,
        replacedById = j['replaced_by_id'] as int?,
        history = [for (final h in j['history'] as List) TxVersion.fromJson(h as Map<String, dynamic>)],
        items = [for (final i in j['items'] as List) TxItem.fromJson(i as Map<String, dynamic>)];

  final int id, total;
  final String rawText;
  final bool voided;
  final DateTime occurredAt;
  final String? voidReason;
  final int? replacesId, replacedById;
  final List<TxVersion> history;
  final List<TxItem> items;
}

/// A row of the Day list.
class TxRow {
  TxRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        occurredAt = DateTime.parse(j['occurred_at'] as String),
        total = j['total'] as int,
        voided = j['status'] == 'voided',
        summary = j['summary'] as String;

  final int id, total;
  final DateTime occurredAt;
  final bool voided;
  final String summary;
}

class DaySummary {
  const DaySummary(this.count, this.revenue);
  final int count, revenue;
}

/// One kept (`itemId`) or added (`productId`) line of a revise request.
class ReviseLine {
  const ReviseLine.keep(int this.itemId, this.quantity) : productId = null;
  const ReviseLine.add(int this.productId, this.quantity) : itemId = null;

  final int? itemId, productId;
  final int quantity;

  Map<String, Object> toJson() => {
        'item_id': ?itemId,
        'product_id': ?productId,
        'quantity': quantity,
      };
}
