class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    this.photoUrl,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        name: j['name'] as String,
        price: j['price'] as int,
        stock: j['stock'] as int,
        photoUrl: j['photo_url'] as String?,
      );

  final int id;
  final String name;
  final int price;
  final int stock;
  final String? photoUrl;
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.reason,
    required this.delta,
    required this.note,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        id: j['id'] as int,
        reason: j['reason'] as String,
        delta: j['delta'] as int,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  final int id;
  final String reason;
  final int delta;
  final String? note;
  final DateTime createdAt;

  /// "Stok awal", "Stok keluar · basi", ...
  String get label {
    final base = switch (reason) {
      'initial' => 'Stok awal',
      'restock' => 'Stok masuk',
      'adjustment' => 'Stok keluar',
      'sale' => 'Terjual',
      'void_sale' => 'Batal jual',
      _ => reason,
    };
    final n = note?.trim();
    return reason == 'adjustment' && n != null && n.isNotEmpty ? '$base · $n' : base;
  }
}

/// One product's row of `GET /analytics/month/items`.
class MonthItem {
  const MonthItem({required this.productId, required this.qty, required this.revenue});

  final int productId;
  final int qty;
  final int revenue;
}
