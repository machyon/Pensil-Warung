import '../../domain/broadcast.dart';
import '../api_client.dart';

class BroadcastRepository {
  BroadcastRepository(this._api);

  final ApiClient _api;

  /// The latest 5 sent, newest first.
  Future<List<Broadcast>> list() async {
    final j = await _api.get('/api/v1/broadcasts') as List;
    return [for (final b in j) Broadcast.fromJson(b as Map<String, dynamic>)];
  }

  Future<Broadcast> detail(int id) async =>
      Broadcast.fromJson(await _api.get('/api/v1/broadcasts/$id') as Map<String, dynamic>);
}
