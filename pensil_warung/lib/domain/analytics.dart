class MonthTotal {
  const MonthTotal(this.month, this.revenue);
  final String month; // 2026-11
  final int revenue;
}

class TopItem {
  const TopItem({required this.name, required this.qty, required this.revenue});
  final String name;
  final int qty, revenue;
}

/// `GET /analytics/month`.
class MonthSummary {
  MonthSummary.fromJson(Map<String, dynamic> j)
      : throughDay = j['through_day'] as int,
        revenue = j['revenue'] as int,
        count = j['transaction_count'] as int,
        topItems = [
          for (final i in j['top_items'] as List)
            TopItem(name: (i as Map)['name'] as String, qty: i['qty'] as int, revenue: i['revenue'] as int),
        ];

  final int throughDay, revenue, count;
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
