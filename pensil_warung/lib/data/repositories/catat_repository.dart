import '../../catat/parser.dart';
import '../../domain/product.dart';
import '../api_client.dart';
import 'product_repository.dart';

/// One sale line of a saved transaction.
class SavedItem {
  const SavedItem(this.name, this.quantity);
  final String name;
  final int quantity;
}

/// The `transaction` of a `POST /catat` answer.
class SavedTransaction {
  SavedTransaction.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        total = j['total'] as int,
        occurredAt = DateTime.parse(j['occurred_at'] as String),
        items = [
          for (final i in j['items'] as List)
            SavedItem((i as Map<String, dynamic>)['product_name'] as String, i['quantity'] as int),
        ];

  final int id, total;
  final DateTime occurredAt;
  final List<SavedItem> items;

  /// `Nasi goreng 2, Es teh manis 3`
  String get summary => items.map((i) => '${i.name} ${i.quantity}').join(', ');
}

class CatatSaved {
  CatatSaved(Map<String, dynamic> j)
      : transaction = j['transaction'] == null ? null : SavedTransaction.fromJson(j['transaction'] as Map<String, dynamic>),
        changed = [for (final p in j['products_changed'] as List) Product.fromJson(p as Map<String, dynamic>)];

  final SavedTransaction? transaction;
  final List<Product> changed;
}

class CatatRepository {
  CatatRepository(this._api, this._products);

  final ApiClient _api;
  final ProductRepository _products;

  /// One Simpan. Throws `ApiException` (`lines_invalid` carries `details.lines`) or `NetworkException`.
  /// A replay of the same [clientUuid] answers 200 with the stored transaction.
  Future<CatatSaved> save({required String clientUuid, required String rawText, required List<Op> ops}) async {
    final j = await _api.post('/api/v1/catat', body: {
      'client_uuid': clientUuid,
      'raw_text': rawText,
      'ops': [for (final o in ops) o.toJson()],
    }) as Map<String, dynamic>;
    _products.applyChanges(
      [for (final p in j['products_changed'] as List) Product.fromJson(p as Map<String, dynamic>)],
      [for (final id in j['products_deleted'] as List? ?? const []) id as int],
    );
    return CatatSaved(j);
  }
}
