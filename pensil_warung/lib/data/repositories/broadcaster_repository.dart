import '../../domain/broadcast.dart';
import '../api_client.dart';

/// The `/broadcaster/broadcasts` routes (needs the broadcaster role).
class BroadcasterRepository {
  BroadcasterRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/v1/broadcaster/broadcasts';

  Future<BroadcasterPage> list({String? cursor}) async => BroadcasterPage.fromJson(
      await _api.get(_base, query: {'cursor': ?cursor}) as Map<String, dynamic>);

  Future<Broadcast> detail(int id) async => _one(await _api.get('$_base/$id'));

  /// [sendAt] is RFC 3339 with an offset; null sends now.
  Future<Broadcast> create({
    required String category,
    required String title,
    required String summary,
    String? body,
    String? sendAt,
  }) async =>
      _one(await _api.post(_base, body: {
        'category': category,
        'title': title,
        'summary': summary,
        'body': body,
        'send_at': sendAt,
      }));

  /// Only the keys in [changes] are sent. `send_at: null` sends now; a missing `send_at` keeps the schedule.
  Future<Broadcast> update(int id, Map<String, Object?> changes) async => _one(await _api.patch('$_base/$id', body: changes));

  Future<Broadcast> cancel(int id) async => _one(await _api.post('$_base/$id/cancel'));

  Broadcast _one(dynamic j) => Broadcast.fromJson(j as Map<String, dynamic>);
}
