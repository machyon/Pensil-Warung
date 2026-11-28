import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../support/feed.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/repositories/analytics_repository.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/data/repositories/transaction_repository.dart';
import 'package:pensil_warung/data/session.dart';
import 'package:pensil_warung/domain/product.dart';
import 'package:pensil_warung/domain/transaction.dart';
import 'package:pensil_warung/ui/histori/detail_screen.dart';
import 'package:pensil_warung/ui/histori/edit_view_model.dart';
import 'package:pensil_warung/ui/histori/histori_screen.dart';
import 'package:pensil_warung/ui/histori/void_sheet.dart';
import 'package:provider/provider.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _item(int id, int? productId, String name, int price, int qty) => {
      'id': id, 'line_no': 1, 'product_id': productId, 'product_name': name,
      'unit_price': price, 'quantity': qty, 'line_total': price * qty,
    };

Map<String, Object?> _tx({String status = 'completed', int? replacedBy, List<Object> history = const []}) => {
      'id': 12, 'raw_text': 'nasi goreng 2\nes teh manis 3', 'total': 45000, 'status': status,
      'occurred_at': '2026-11-17T07:32:00Z', 'voided_at': status == 'voided' ? '2026-11-17T08:00:00Z' : null,
      'void_reason': null, 'replaces_id': null, 'replaced_by_id': replacedBy, 'history': history,
      'items': [_item(41, 5, 'Nasi goreng', 15000, 2), _item(42, 6, 'Es teh manis', 5000, 3)],
    };

void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late ProductRepository products;
  late TransactionRepository txRepo;
  late ApiClient api;

  setUp(() {
    sent = [];
    reply = (_) => _json(500, {});
    api = ApiClient(baseUrl: 'http://x', client: MockClient((r) async {
      sent.add(r);
      return reply(r);
    }));
    products = ProductRepository(api)
      ..items = const [
        Product(id: 5, name: 'Nasi goreng', price: 15000, stock: 18),
        Product(id: 6, name: 'Es teh manis', price: 5000, stock: 37),
      ]
      ..loaded = true;
    txRepo = TransactionRepository(api, products);
  });

  test('void math: the day revenue loses the transaction total', () {
    expect(revenueAfterVoid(1245000, 45000), 1200000);
  });

  group('Ubah', () {
    test('kept lines go as item_id, added ones as product_id, with one client_uuid per edit', () async {
      final vm = EditViewModel(txRepo, products, Transaction.fromJson(_tx()));
      expect(vm.changed, isFalse);
      vm.setQty(0, 1);
      vm.add(const Product(id: 7, name: 'Kerupuk', price: 2000, stock: 9));
      expect(vm.changed, isTrue);
      expect(vm.newTotal, 15000 + 15000 + 2000);

      reply = (r) => r.url.path.endsWith('/revise') ? _json(201, _tx()) : _json(200, {'items': [], 'count': 0});
      await vm.save();
      final revise = sent.firstWhere((r) => r.url.path == '/api/v1/transactions/12/revise');
      final body = jsonDecode(revise.body) as Map<String, dynamic>;
      expect(body['items'], [
        {'item_id': 41, 'quantity': 1},
        {'item_id': 42, 'quantity': 3},
        {'product_id': 7, 'quantity': 1},
      ]);
      expect(body['client_uuid'], isA<String>());
    });

    test('stock note comes from the cached stock', () {
      final vm = EditViewModel(txRepo, products, Transaction.fromJson(_tx()));
      vm.setQty(0, 1);
      expect(vm.stockNotes, ['Nasi goreng kembali 1 (18 jadi 19)']);
      vm.setQty(1, 5);
      expect(vm.stockNotes.last, 'Es teh manis berkurang 2 (37 jadi 35)');
    });

    test('lines_invalid marks rows by line_no - 1 and keeps the same client_uuid on retry', () async {
      final vm = EditViewModel(txRepo, products, Transaction.fromJson(_tx()));
      vm.setQty(1, 99);
      reply = (_) => _json(422, {
            'error': {
              'code': 'lines_invalid',
              'message': 'x',
              'details': {
                'lines': [{'line_no': 2, 'code': 'stock_insufficient', 'message': 'Stok kurang.'}],
              },
            },
          });
      expect(await vm.save(), isNull);
      expect(vm.rowErrors, {1: 'Stok kurang.'});
      await vm.save();
      final uuids = [for (final r in sent) (jsonDecode(r.body) as Map)['client_uuid']];
      expect(uuids.length, 2);
      expect(uuids[0], uuids[1]);
    });

    test('the last line cannot be removed', () {
      final vm = EditViewModel(txRepo, products, Transaction.fromJson(_tx()));
      vm.remove(0);
      expect(vm.canRemove, isFalse);
      vm.remove(0);
      expect(vm.lines.length, 1);
    });
  });

  Future<void> pumpDetail(WidgetTester tester, Map<String, Object?> tx) async {
    reply = (_) => _json(200, tx);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: products),
        ChangeNotifierProvider.value(value: txRepo),
        ChangeNotifierProvider(create: (_) => Session()),
      ],
      child: const MaterialApp(home: DetailScreen(id: 12)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('detail: a completed sale shows both actions and "Belum pernah diubah"', (tester) async {
    await pumpDetail(tester, _tx());
    expect(find.text('Belum pernah diubah'), findsOneWidget);
    expect(find.text('Batalkan'), findsOneWidget);
    expect(find.text('Ubah'), findsOneWidget);
  });

  testWidgets('detail: a voided sale shows Dibatalkan and hides the actions', (tester) async {
    await pumpDetail(tester, _tx(status: 'voided'));
    expect(find.text('Dibatalkan'), findsOneWidget);
    expect(find.text('Batalkan'), findsNothing);
    expect(find.text('Ubah'), findsNothing);
  });

  testWidgets('detail: a replaced sale links to the newer version', (tester) async {
    await pumpDetail(tester, _tx(status: 'voided', replacedBy: 13));
    expect(find.text('Diganti'), findsOneWidget);
    expect(find.text('Transaksi ini sudah diganti dengan versi baru.'), findsOneWidget);
    expect(find.text('Lihat'), findsOneWidget);
    expect(find.text('Batalkan'), findsNothing);
  });

  testWidgets('detail: history lists the older versions', (tester) async {
    await pumpDetail(tester, _tx(history: [
      {
        'id': 11, 'raw_text': 'nasi goreng 1', 'total': 15000, 'occurred_at': '2026-11-17T07:32:00Z',
        'revised_at': '2026-11-17T07:40:00Z', 'items': [_item(40, 5, 'Nasi goreng', 15000, 1)],
      },
    ]));
    expect(find.text('1 versi lama'), findsOneWidget);
    expect(find.text('Nasi goreng 1 × Rp15.000'), findsOneWidget);
  });

  testWidgets('Histori: no months shows the empty state', (tester) async {
    reply = (_) => _json(200, []);
    final feed = await testFeed();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider(create: (_) => AnalyticsRepository(api)),
        ChangeNotifierProvider.value(value: txRepo),
        ChangeNotifierProvider.value(value: feed),
        ChangeNotifierProvider(create: (_) => Session()),
      ],
      child: const MaterialApp(home: Scaffold(body: HistoriScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada jualan'), findsOneWidget);
    expect(find.text('Catat jualan pertama'), findsOneWidget);
  });
}
