class MonthTotal {
  const MonthTotal(this.month, this.revenue);
  final String month; // 2026-11
  final int revenue;
}

class TopItem {
  const TopItem({required this.name, required this.qty, required this.revenue, this.productId, this.stock});
  factory TopItem.fromJson(Map<String, dynamic> i) => TopItem(
        name: i['name'] as String,
        qty: i['qty'] as int,
        revenue: i['revenue'] as int,
        productId: i['product_id'] as int?,
        stock: i['stock'] as int?,
      );
  final String name;
  final int qty, revenue;
  final int? productId, stock; // null once the product was deleted
}

/// `previous` of `GET /analytics/month`: the same day range of the month before.
class PreviousMonth {
  const PreviousMonth(this.month, this.revenue, this.changePct);
  final String month; // 2026-10
  final int revenue;
  final double? changePct; // null when the previous revenue is 0
}

/// `GET /analytics/month`.
class MonthSummary {
  MonthSummary.fromJson(Map<String, dynamic> j)
      : month = j['month'] as String,
        throughDay = j['through_day'] as int,
        revenue = j['revenue'] as int,
        count = j['transaction_count'] as int,
        previous = PreviousMonth(
          (j['previous'] as Map)['month'] as String,
          j['previous']['revenue'] as int,
          (j['previous']['change_pct'] as num?)?.toDouble(),
        ),
        trend = [for (final t in j['trend'] as List) MonthTotal((t as Map)['month'] as String, t['revenue'] as int)],
        weekdayAvg = j['weekday_avg'] == null
            ? null
            : [for (final w in (j['weekday_avg'] as List)..sort((a, b) => (a['weekday'] as int).compareTo(b['weekday'] as int))) (w as Map)['avg_revenue'] as int],
        topItems = [for (final i in j['top_items'] as List) TopItem.fromJson(i as Map<String, dynamic>)];

  final String month;
  final int throughDay, revenue, count;
  final PreviousMonth previous;
  final List<MonthTotal> trend; // 12, oldest first
  final List<int>? weekdayAvg; // Monday first; null under 14 days with sales
  final List<TopItem> topItems;
}

class DayTotal {
  const DayTotal(this.day, this.count, this.revenue);
  final String day; // 2026-11-17
  final int count, revenue;
}

/// A day card expanded: top 3 plus "Barang lain".
class DayItems {
  DayItems.fromJson(Map<String, dynamic> j)
      : items = [
          for (final i in j['items'] as List)
            TopItem(name: (i as Map)['name'] as String, qty: i['qty'] as int, revenue: i['revenue'] as int),
        ],
        other = j['other_revenue'] as int,
        total = j['total'] as int;

  final List<TopItem> items;
  final int other, total;
}

class SoldItem {
  SoldItem.fromJson(Map<String, dynamic> j)
      : item = TopItem.fromJson(j),
        sharePct = (j['share_pct'] as num).toDouble();
  final TopItem item;
  final double sharePct;
}

class UnsoldItem {
  const UnsoldItem(this.id, this.name, this.stock);
  final int id, stock;
  final String name;
}

/// `GET /analytics/month/items`.
class MonthItems {
  MonthItems.fromJson(Map<String, dynamic> j)
      : totalQty = j['total_qty'] as int,
        revenue = j['revenue'] as int,
        items = [for (final i in j['items'] as List) SoldItem.fromJson(i as Map<String, dynamic>)],
        unsold = [for (final u in j['unsold'] as List) UnsoldItem((u as Map)['id'] as int, u['name'] as String, u['stock'] as int)];
  final int totalQty, revenue;
  final List<SoldItem> items;
  final List<UnsoldItem> unsold;
}
