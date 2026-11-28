import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../support/feed.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/domain/product.dart';
import 'package:pensil_warung/ui/core/format.dart';
import 'package:pensil_warung/ui/core/money_input.dart';
import 'package:pensil_warung/ui/products/bulk_add_view_model.dart';
import 'package:pensil_warung/ui/products/product_list_screen.dart';
import 'package:provider/provider.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _p(int id, String name, int price, int stock) =>
    {'id': id, 'name': name, 'price': price, 'stock': stock, 'photo_url': null};

StockMovement _m(String reason, {String? note, int delta = 1}) => StockMovement(
      id: 1,
      reason: reason,
      delta: delta,
      note: note,
      createdAt: DateTime.utc(2026, 11, 26),
    );

void main() {
  const all = [
    Product(id: 1, name: 'Nasi goreng', price: 15000, stock: 18),
    Product(id: 2, name: 'Es teh manis', price: 5000, stock: 37),
  ];

  test('search filter is case-insensitive, trims, and empty keeps all', () {
    expect(filterProducts(all, 'TEH').map((p) => p.id), [2]);
    expect(filterProducts(all, '  nasi ').map((p) => p.id), [1]);
    expect(filterProducts(all, ''), all);
    expect(filterProducts(all, 'bakso'), isEmpty);
  });

  test('movement labels by reason, note only on adjustment', () {
    expect(_m('initial').label, 'Stok awal');
    expect(_m('restock').label, 'Stok masuk');
    expect(_m('adjustment', note: 'basi', delta: -3).label, 'Stok keluar · basi');
    expect(_m('adjustment').label, 'Stok keluar');
    expect(_m('sale').label, 'Terjual');
    expect(_m('void_sale').label, 'Batal jual');
    expect(_m('restock', note: 'x').label, 'Stok masuk');
  });

  test('movement time: today, yesterday, older (WIB)', () {
    final now = DateTime.utc(2026, 11, 26, 10); // 17.00 WIB on the 26th
    expect(wibRelative(DateTime.utc(2026, 11, 26, 7, 32), now: now), 'Hari ini, 14.32');
    expect(wibRelative(DateTime.utc(2026, 11, 25, 14, 40), now: now), 'Kemarin, 21.40');
    expect(wibRelative(DateTime.utc(2026, 11, 16, 1), now: now), 'Sen, 16 Nov, 08.00');
    // 20.00 UTC on the 25th is already 03.00 on the 26th in WIB.
    expect(wibRelative(DateTime.utc(2026, 11, 25, 20), now: now), 'Hari ini, 03.00');
  });

  test('rupiah input groups digits as you type', () {
    const f = RupiahInputFormatter();
    String run(String s) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s)).text;
    expect(run('15000'), '15.000');
    expect(run('1.5000'), '15.000');
    expect(run('abc'), '');
    expect(parseRupiah('1.250.000'), 1250000);
    expect(parseRupiah(''), isNull);
  });

  group('bulk add', () {
    late List<http.Request> sent;
    late BulkAddViewModel vm;

    BulkAddViewModel make(http.Response Function(http.Request) reply) {
      sent = [];
      final repo = ProductRepository(ApiClient(
        baseUrl: 'http://x',
        client: MockClient((r) async {
          sent.add(r);
          return r.url.path == '/api/v1/products' ? _json(200, {'items': [], 'count': 0}) : reply(r);
        }),
      ));
      return BulkAddViewModel(repo);
    }

    void fill(BulkRow r, String name, String price, [String stock = '']) {
      r.nameCtrl.text = name;
      r.priceCtrl.text = price;
      r.stockCtrl.text = stock;
    }

    test('a row without a price is not sent and says so', () async {
      vm = make((_) => _json(201, {'items': []}));
      fill(vm.rows[0], 'Teh', '3.000', '5');
      vm.add();
      fill(vm.rows[1], 'Kerupuk', '');
      vm.add(); // stays blank: neither counted nor flagged
      expect(vm.readyCount, 1);
      expect(vm.rows[1].skipNote, 'Belum ada harga, jadi belum ikut disimpan.');
      expect(vm.rows[2].skipNote, isNull);

      expect(await vm.save(), isTrue);
      final body = jsonDecode(sent.firstWhere((r) => r.method == 'POST').body) as Map;
      expect(body['items'], [
        {'name': 'Teh', 'price': 3000, 'stock': 5},
      ]);
    });

    test('name_taken index points at the right row even when a row was skipped', () async {
      vm = make((_) => _json(409, {
            'error': {'code': 'name_taken', 'message': 'Nama produk sudah digunakan.', 'details': {'index': 1}},
          }));
      fill(vm.rows[0], 'Teh', '3000');
      vm.add();
      fill(vm.rows[1], 'Tanpa harga', ''); // skipped, so it is not in the request
      vm.add();
      fill(vm.rows[2], 'nasi goreng', '15000'); // request index 1
      expect(await vm.save(), isFalse);
      expect(vm.rows[0].nameError, isNull);
      expect(vm.rows[1].nameError, isNull);
      expect(vm.rows[2].nameError, 'Nama produk sudah digunakan.');
      expect(vm.error, isNull);

      vm.edited(vm.rows[2]);
      expect(vm.rows[2].nameError, isNull);
    });
  });

  testWidgets('list: search filters the cache without a request; no match offers Tambah', (tester) async {
    var gets = 0;
    final repo = ProductRepository(ApiClient(
      baseUrl: 'http://x',
      client: MockClient((r) async {
        gets++;
        return _json(200, {
          'items': [_p(2, 'Es teh manis', 5000, 37), _p(1, 'Nasi goreng', 15000, 18)],
          'count': 2,
        });
      }),
    ));
    final feed = await testFeed();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: repo), ChangeNotifierProvider.value(value: feed)],
      child: const MaterialApp(home: Scaffold(body: ProductListScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2 produk'), findsOneWidget);
    expect(find.text('Stok 18'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nasi');
    await tester.pump();
    expect(find.text('1 produk'), findsOneWidget);
    expect(find.text('Es teh manis'), findsNothing);

    await tester.enterText(find.byType(TextField), 'bakso');
    await tester.pump();
    expect(find.text('"bakso" tidak ditemukan'), findsOneWidget);
    expect(find.text('Tambah "bakso"'), findsOneWidget);
    expect(gets, 1);
  });

  testWidgets('list: empty account shows the Catat hint', (tester) async {
    final repo = ProductRepository(ApiClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => _json(200, {'items': [], 'count': 0})),
    ));
    final feed = await testFeed();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: repo), ChangeNotifierProvider.value(value: feed)],
      child: const MaterialApp(home: Scaffold(body: ProductListScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada produk'), findsOneWidget);
    expect(find.text('buat produk kerupuk harga 2000 stok 30'), findsOneWidget);
  });
}
