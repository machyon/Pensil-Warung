import 'package:flutter/foundation.dart';

import '../../domain/transaction.dart';
import '../../ui/core/format.dart';
import '../api_client.dart';
import 'product_repository.dart';

typedef DayPage = ({List<TxRow> rows, String? next, DaySummary? day});

/// Transactions API. Listeners hear [markChanged] after anything that alters history
/// (a save in Catat, a void, a revise), so Histori and the Day list reload.
class TransactionRepository extends ChangeNotifier {
  TransactionRepository(this._api, this._products);

  final ApiClient _api;
  final ProductRepository _products;

  void markChanged() => notifyListeners();

  /// One WIB day's list; `day` is sent on the first page only.
  Future<DayPage> day(String date, {String? cursor, int limit = 20}) async {
    final j = await _api.get('/api/v1/transactions', query: {
      'date': date,
      'limit': '$limit',
      'cursor': ?cursor,
    }) as Map<String, dynamic>;
    final d = j['day'] as Map<String, dynamic>?;
    return (
      rows: [for (final r in j['items'] as List) TxRow.fromJson(r as Map<String, dynamic>)],
      next: j['next_cursor'] as String?,
      day: d == null ? null : DaySummary(d['transaction_count'] as int, d['revenue'] as int),
    );
  }

  /// Today's completed sales (WIB).
  Future<DaySummary> today() async => (await day(wibIsoDate(DateTime.now()), limit: 1)).day!;

  Future<Transaction> get(int id) async =>
      Transaction.fromJson(await _api.get('/api/v1/transactions/$id') as Map<String, dynamic>);

  Future<void> voidTransaction(int id) async {
    await _api.post('/api/v1/transactions/$id/void', body: {'reason': 'salah catat'});
    await _afterChange();
  }

  /// Edit: the answer is the new version (`201`, or `200` on a replay of [clientUuid]).
  Future<Transaction> revise(int id, {required String clientUuid, required List<ReviseLine> lines}) async {
    final j = await _api.post('/api/v1/transactions/$id/revise', body: {
      'client_uuid': clientUuid,
      'items': [for (final l in lines) l.toJson()],
    }) as Map<String, dynamic>;
    await _afterChange();
    return Transaction.fromJson(j);
  }

  Future<void> _afterChange() async {
    try {
      await _products.load(); // stock moved
    } catch (_) {}
    markChanged();
  }
}
