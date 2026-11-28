import '../../domain/analytics.dart';
import '../api_client.dart';

class AnalyticsRepository {
  AnalyticsRepository(this._api);

  final ApiClient _api;

  /// Months with sales, newest first.
  Future<List<MonthTotal>> months() async {
    final j = await _api.get('/api/v1/analytics/months') as List;
    return [for (final m in j) MonthTotal((m as Map)['month'] as String, m['revenue'] as int)];
  }

  Future<MonthSummary> month(String month) async =>
      MonthSummary.fromJson(await _api.get('/api/v1/analytics/month', query: {'month': month}) as Map<String, dynamic>);

  /// Days of [month] that have sales, newest first. A month has at most 31, so one page is enough.
  Future<List<DayTotal>> days(String month) async {
    final j = await _api.get('/api/v1/analytics/month/days', query: {'month': month, 'limit': '100'}) as Map<String, dynamic>;
    return [
      for (final d in j['items'] as List)
        DayTotal((d as Map)['day'] as String, d['transaction_count'] as int, d['revenue'] as int),
    ];
  }

  Future<DayItems> dayItems(String date) async =>
      DayItems.fromJson(await _api.get('/api/v1/analytics/days/$date/items') as Map<String, dynamic>);
}
