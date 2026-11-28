import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/repositories/catat_repository.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/domain/product.dart';
import 'package:pensil_warung/ui/catat/catat_view_model.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _tx = {
  'id': 12, 'raw_text': 'nasi goreng 2', 'total': 30000, 'status': 'completed',
  'occurred_at': '2026-11-26T08:00:00Z', 'voided_at': null, 'void_reason': null,
  'replaces_id': null, 'replaced_by_id': null, 'history': [],
  'items': [
    {'id': 30, 'line_no': 1, 'product_id': 5, 'product_name': 'Nasi goreng', 'unit_price': 15000, 'quantity': 2, 'line_total': 30000},
  ],
};

void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late ProductRepository products;
  late CatatViewModel vm;

  setUp(() {
    sent = [];
    reply = (_) => _json(500, {});
    final api = ApiClient(baseUrl: 'http://x', client: MockClient((r) async {
      sent.add(r);
      return reply(r);
    }));
    products = ProductRepository(api)
      ..items = const [Product(id: 5, name: 'Nasi goreng', price: 15000, stock: 10)]
      ..loaded = true;
    vm = CatatViewModel(CatatRepository(api, products), products);
  });

  tearDown(() => vm.dispose());

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  List<http.Request> posts() => sent.where((r) => r.url.path == '/api/v1/catat').toList();

  test('sales-only text does not need the confirm sheet; a command does', () {
    vm.setText('nasi goreng 2');
    expect(vm.summary.needsConfirm, isFalse);
    vm.setText('nasi goreng 2\nbuat produk kerupuk harga 2000 stok 30');
    expect(vm.summary.needsConfirm, isTrue);
  });

  test('save sends ops, applies products_changed and shows the card with Urungkan', () async {
    reply = (r) => r.url.path == '/api/v1/catat'
        ? _json(201, {
            'transaction': _tx,
            'products_changed': [{'id': 5, 'name': 'Nasi goreng', 'price': 15000, 'stock': 8}],
            'products_deleted': [],
          })
        : _json(200, {'day': {'date': '2026-11-26', 'transaction_count': 3, 'revenue': 90000}, 'items': []});
    vm.setText('nasi goreng 2');
    expect(await vm.save(), SaveOutcome.saved);
    final b = body(posts().single);
    expect(b['raw_text'], 'nasi goreng 2');
    expect(b['ops'], [{'line_no': 1, 'op': 'sale', 'product': 'Nasi goreng', 'quantity': 2}]);
    expect(products.items.single.stock, 8);
    expect(vm.controller.text, '');
    expect(vm.saved!.undoable, isTrue);
    expect(vm.saved!.tx.summary, 'Nasi goreng 2');
    await Future<void>.delayed(Duration.zero);
    expect(vm.saved!.today!.count, 3);
  });

  test('a batch with a command is saved without Urungkan', () async {
    reply = (_) => _json(201, {
          'transaction': _tx,
          'products_changed': [{'id': 9, 'name': 'Kerupuk', 'price': 2000, 'stock': 30}],
          'products_deleted': [],
        });
    vm.setText('nasi goreng 2\nbuat produk kerupuk harga 2000 stok 30');
    await vm.save();
    expect(vm.saved!.undoable, isFalse);
    expect(products.items.map((p) => p.name), containsAll(['Kerupuk', 'Nasi goreng']));
  });

  test('lines_invalid puts the server message on its line and keeps the text', () async {
    reply = (_) => _json(422, {
          'error': {
            'code': 'lines_invalid', 'message': 'Ada baris yang tidak valid.',
            'details': {'lines': [{'line_no': 1, 'code': 'stock_insufficient', 'message': 'Stok tidak cukup.'}]},
          },
        });
    vm.setText('nasi goreng 2');
    expect(await vm.save(), SaveOutcome.linesInvalid);
    expect(vm.controller.text, 'nasi goreng 2');
    expect(vm.lint.lines.single.message, 'Stok tidak cukup.');
    expect(vm.errorLines, {1});
    expect(vm.lint.canSave, isFalse);
  });

  test('retry after a network failure reuses the client_uuid; new text gets a new one', () async {
    var down = true;
    reply = (r) {
      if (down) throw http.ClientException('offline');
      return _json(201, {'transaction': _tx, 'products_changed': [], 'products_deleted': []});
    };
    vm.setText('nasi goreng 2');
    expect(await vm.save(), SaveOutcome.offline);
    expect(vm.controller.text, 'nasi goreng 2');
    down = false;
    expect(await vm.save(), SaveOutcome.saved);
    final ids = posts().map((r) => body(r)['client_uuid']).toList();
    expect(ids, hasLength(2));
    expect(ids[0], ids[1]);

    vm.setText('nasi goreng 3');
    down = true;
    await vm.save();
    vm.setText('nasi goreng 1');
    await vm.save();
    final all = posts().map((r) => body(r)['client_uuid']).toList();
    expect(all[2], isNot(all[3]));
  });

  test('urungkan voids the sale and puts the text back', () async {
    reply = (r) {
      if (r.url.path == '/api/v1/catat') {
        return _json(201, {'transaction': _tx, 'products_changed': [], 'products_deleted': []});
      }
      if (r.url.path.endsWith('/void')) return _json(200, {..._tx, 'status': 'voided'});
      return _json(200, {'items': [], 'day': {'date': 'd', 'transaction_count': 0, 'revenue': 0}});
    };
    vm.setText('nasi goreng 2');
    await vm.save();
    expect(await vm.undo(), isNull);
    expect(sent.any((r) => r.method == 'POST' && r.url.path == '/api/v1/transactions/12/void'), isTrue);
    expect(vm.controller.text, 'nasi goreng 2');
    expect(vm.saved, isNull);
  });
}
