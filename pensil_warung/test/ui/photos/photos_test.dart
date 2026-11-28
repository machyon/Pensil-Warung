import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/ui/photos/photo_pick_sheet.dart';
import 'package:pensil_warung/ui/products/bulk_add_view_model.dart';
import 'package:pensil_warung/ui/products/product_detail_screen.dart';
import 'package:provider/provider.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _p(int id, {String? photo}) =>
    {'id': id, 'name': 'Teh', 'price': 3000, 'stock': 5, 'photo_url': photo};

final _bytes = Uint8List.fromList([1, 2, 3]);

void main() {
  late List<http.Request> sent;

  ProductRepository make(http.Response Function(http.Request) reply) {
    sent = [];
    return ProductRepository(ApiClient(
      baseUrl: 'http://x',
      client: MockClient((r) async {
        sent.add(r);
        if (r.method == 'GET' && r.url.path == '/api/v1/products') return _json(200, {'items': [], 'count': 0});
        return reply(r);
      }),
    ));
  }

  test('upload sends a multipart PUT with the photo field', () async {
    final repo = make((_) => _json(200, _p(7, photo: 'https://s/x')));
    final p = await repo.uploadPhoto(7, _bytes);
    final r = sent.single;
    expect(r.method, 'PUT');
    expect(r.url.path, '/api/v1/products/7/photo');
    expect(r.headers['content-type'], startsWith('multipart/form-data'));
    expect(r.body, contains('name="photo"'));
    expect(p.photoUrl, 'https://s/x');
  });

  test('delete sends DELETE and refreshes the list', () async {
    final repo = make((_) => http.Response('', 204));
    await repo.deletePhoto(7);
    expect(sent.map((r) => '${r.method} ${r.url.path}'), ['DELETE /api/v1/products/7/photo', 'GET /api/v1/products']);
  });

  test('bulk save uploads the row photo with the returned id; a failure is kept for retry', () async {
    var putStatus = 503;
    final repo = make((r) {
      if (r.method == 'POST') return _json(201, {'items': [_p(11)]});
      return putStatus == 200
          ? _json(200, _p(11, photo: 'https://s/x'))
          : _json(503, {'error': {'code': 'storage_unavailable', 'message': 'Penyimpanan foto belum tersedia.'}});
    });
    final vm = BulkAddViewModel(repo);
    vm.rows[0].nameCtrl.text = 'Teh';
    vm.rows[0].priceCtrl.text = '3000';
    vm.setPhoto(vm.rows[0], _bytes);

    expect(await vm.save(), isTrue); // the product is kept
    expect(sent.any((r) => r.method == 'PUT' && r.url.path == '/api/v1/products/11/photo'), isTrue);
    expect(vm.failedPhotos, 1);
    expect(repo.pendingPhotos.keys, [11]);

    putStatus = 200;
    expect(await repo.uploadPending(11, repo.pendingPhotos[11]!), isTrue);
    expect(repo.pendingPhotos, isEmpty);
  });

  testWidgets('sheet shows Hapus foto only when the product has a photo', (tester) async {
    for (final has in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showPhotoPickSheet(c, name: 'Teh', hasPhoto: has),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Ambil foto'), findsOneWidget);
      expect(find.text('Pilih dari galeri'), findsOneWidget);
      expect(find.text('Hapus foto'), has ? findsOneWidget : findsNothing);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('detail: Foto belum terunggah, Coba lagi uploads and hides the banner', (tester) async {
    var uploaded = false;
    final repo = make((r) {
      final path = r.url.path;
      if (r.method == 'PUT') {
        uploaded = true;
        return _json(200, _p(11, photo: 'https://s/x'));
      }
      if (path.endsWith('/movements')) return _json(200, {'items': [], 'next_cursor': null});
      if (path.contains('/analytics/')) return _json(200, {'items': []});
      return _json(200, _p(11));
    });
    repo.pendingPhotos[11] = _bytes;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: repo,
      child: const MaterialApp(home: ProductDetailScreen(id: 11)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Foto belum terunggah'), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(uploaded, isTrue);
    expect(find.text('Foto belum terunggah'), findsNothing);
  });
}
