import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pensil_warung/catat/linter.dart';
import 'package:pensil_warung/catat/matcher.dart';
import 'package:pensil_warung/catat/numbers.dart';
import 'package:pensil_warung/catat/result.dart';
import 'package:pensil_warung/catat/summary.dart';
import 'package:pensil_warung/domain/product.dart';

Product p(int id, String name, int price, int stock) => Product(id: id, name: name, price: price, stock: stock);

final products = [
  p(5, 'Nasi goreng', 15000, 10),
  p(6, 'Es teh manis', 3000, 20),
  p(7, 'Kopi susu', 8000, 4),
];

String ops(String text, [List<Product>? ps]) => jsonEncode(lint(text, ps ?? products).ops);
LineResult one(String text, [List<Product>? ps]) => lint(text, ps ?? products).lines.single;

void main() {
  group('numbers', () {
    test('plain, dotted thousands, decimals, non-numbers', () {
      expect(parseNumber('2000').value, 2000);
      expect(parseNumber('2.000').value, 2000);
      expect(parseNumber('1.250.000').value, 1250000);
      expect(parseNumber('1,5').kind, NumKind.decimal);
      expect(parseNumber('1.5').kind, NumKind.decimal);
      expect(parseNumber('abc').kind, NumKind.none);
      expect(rupiah(15000), 'Rp15.000');
      expect(nameKey('  Nasi   GORENG '), 'nasi goreng');
    });
  });

  group('grammar', () {
    test('sale: <name> <qty>, canonical product name', () {
      expect(ops('nasi goreng 2'), '[{"line_no":1,"op":"sale","product":"Nasi goreng","quantity":2}]');
    });
    test('restock', () {
      expect(ops('tambah stok kopi susu 10'), '[{"line_no":1,"op":"restock","product":"Kopi susu","quantity":10}]');
    });
    test('adjust_down with and without reason', () {
      expect(ops('hapus stok kopi susu 2 alasan basi karena hujan'),
          '[{"line_no":1,"op":"adjust_down","product":"Kopi susu","quantity":2,"note":"basi karena hujan"}]');
      expect(ops('hapus stok kopi susu 2'), '[{"line_no":1,"op":"adjust_down","product":"Kopi susu","quantity":2}]');
    });
    test('create_product, stok missing = 0, dotted price', () {
      expect(ops('buat produk kerupuk harga 2.000 stok 30'),
          '[{"line_no":1,"op":"create_product","name":"kerupuk","price":2000,"stock":30}]');
      expect(ops('buat produk kerupuk harga 2000'),
          '[{"line_no":1,"op":"create_product","name":"kerupuk","price":2000,"stock":0}]');
    });
    test('set_price', () {
      expect(ops('ubah harga nasi goreng 16000'),
          '[{"line_no":1,"op":"set_price","product":"Nasi goreng","price":16000}]');
    });
    test('delete_product', () {
      expect(ops('hapus kopi susu'), '[{"line_no":1,"op":"delete_product","product":"Kopi susu"}]');
    });
    test('case-insensitive and extra spaces; blank lines keep numbers', () {
      final r = lint('\n  TAMBAH   STOK  nasi   goreng 1 \n\nNASI GORENG   2', products);
      expect(r.lines.map((l) => l.lineNo), [2, 4]);
      expect(jsonEncode(r.ops),
          '[{"line_no":2,"op":"restock","product":"Nasi goreng","quantity":1},'
          '{"line_no":4,"op":"sale","product":"Nasi goreng","quantity":2}]');
    });
    test('docs/api.md example request ops, byte for byte', () {
      const docOps = '[{"line_no":1,"op":"sale","product":"Nasi goreng","quantity":2},'
          '{"line_no":2,"op":"sale","product":"Es teh manis","quantity":3},'
          '{"line_no":3,"op":"restock","product":"Kopi susu","quantity":10}]';
      final r = lint('nasi goreng 2\nes teh manis 3\ntambah stok kopi susu 10', products);
      expect(jsonEncode(r.ops), jsonEncode(jsonDecode(docOps)));
      expect(jsonEncode(r.ops), docOps);
      expect(r.total, 39000);
      expect(r.canSave, isTrue);
    });
  });

  group('numbers in lines', () {
    test('decimal quantity is an error', () {
      for (final t in ['nasi goreng 1,5', 'nasi goreng 1.5', 'tambah stok kopi susu 1,5']) {
        final l = one(t);
        expect(l.status, LineStatus.error, reason: t);
        expect(l.message, 'Jumlah harus bilangan bulat');
      }
    });
    test('missing quantity on a sale is a warning, counts as 1', () {
      final r = lint('nasi goreng', products);
      expect(r.lines.single.status, LineStatus.warning);
      expect(r.lines.single.message, 'Jumlah tidak ditulis, dianggap 1');
      expect(r.ops.single.quantity, 1);
      expect(r.canSave, isTrue);
      expect(r.warnings, 1);
    });
    test('quantity range', () {
      expect(one('nasi goreng 0').message, 'Jumlah harus 1 sampai 999.999.999');
      expect(one('tambah stok nasi goreng 1000000000').message, 'Jumlah harus 1 sampai 999.999.999');
    });
    test('missing pieces', () {
      expect(one('tambah stok nasi goreng').message, 'Jumlah belum ditulis');
      expect(one('2').message, 'Nama barang belum ditulis');
      expect(one('hapus').message, 'Nama barang belum ditulis');
      expect(one('ubah harga nasi goreng').message, 'Harga belum ditulis');
      expect(one('ubah harga nasi goreng 1,5').message, 'Harga harus bilangan bulat');
      expect(one('buat produk kerupuk harga 1,5').message, 'Harga harus bilangan bulat');
      expect(one('buat produk kerupuk harga 10 stok 1,5').message, 'Stok harus bilangan bulat');
      expect(one('buat produk kerupuk harga 10 stok').message, 'Stok belum ditulis');
      expect(one('buat produk harga 10').message, 'Nama barang belum ditulis');
      expect(one('nasi goreng 99999999999999999999').message, 'Jumlah harus 1 sampai 999.999.999');
      expect(one('ubah harga nasi goreng 99999999999999999999').message, 'Angka terlalu besar');
    });
    test('buat produk without harga: error with example', () {
      final l = one('buat produk kerupuk');
      expect(l.status, LineStatus.error);
      expect(l.message, 'Harga belum ditulis');
      expect(l.hint, 'buat produk kerupuk harga 2000 stok 30');
    });
  });

  group('matching', () {
    test('close name gets a "Ganti jadi" fix that rewrites the line', () {
      const t = 'nasi gorang 2';
      final l = one(t);
      expect(l.status, LineStatus.error);
      expect(l.message, 'Barang tidak ada di daftar');
      expect(l.fixes.map((f) => f.label), ['Ganti jadi Nasi goreng', 'Jadikan barang baru']);
      expect(l.fixes[0].apply(t), 'Nasi goreng 2');
    });
    test('"Jadikan barang baru" rewrites the line and puts the cursor after harga', () {
      const t = 'es teh manis 1\nkerupuk 3';
      final f = lint(t, products).lines[1].fixes.last;
      expect(f.label, 'Jadikan barang baru');
      final out = f.apply(t);
      expect(out, 'es teh manis 1\nbuat produk kerupuk harga  stok ');
      expect(out.substring(0, f.cursorAt!(out)), 'es teh manis 1\nbuat produk kerupuk harga ');
    });
    test('far-off names get no suggestion', () {
      expect(one('xyz 1').fixes.map((f) => f.label), ['Jadikan barang baru']);
    });
    test('levenshtein and closestKey', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(closestKey('kopi susu', ['kopi susuu', 'nasi']), 'kopi susuu');
      expect(closestKey('ab', ['cd']), isNull);
    });
    test('creating an existing name', () {
      expect(one('buat produk NASI goreng harga 1').message, 'Nama sudah dipakai');
    });
    test('two creates of the same name', () {
      final r = lint('buat produk kerupuk harga 1\nbuat produk Kerupuk harga 2', products);
      expect(r.lines[1].message, 'Kerupuk sudah ditulis di baris lain');
      expect(r.canSave, isFalse);
    });
  });

  group('batch simulation', () {
    test('create then sell uses the created stock and price', () {
      final r = lint('buat produk kerupuk harga 2000 stok 30\nkerupuk 5', products);
      expect(r.errors, 0);
      expect(r.total, 10000);
      expect(r.lines[1].stockAfter, 25);
    });
    test('delete then sell is not found', () {
      final r = lint('hapus kopi susu\nkopi susu 1', products);
      expect(r.lines[1].message, 'Barang tidak ada di daftar');
      expect(r.canSave, isFalse);
    });
    test('delete then create the same name is fine', () {
      expect(lint('hapus kopi susu\nbuat produk kopi susu harga 1', products).errors, 0);
    });
    test('set_price order: earlier sale old price, later sale new price', () {
      final r = lint('nasi goreng 1\nubah harga nasi goreng 20000\nnasi goreng 1', products);
      expect(r.lines.map((l) => l.lineTotal), [15000, null, 20000]);
      expect(r.total, 35000);
      expect(r.lines[1].previousPrice, 15000);
    });
    test('restock earlier counts toward a later sale', () {
      final r = lint('kopi susu 6\ntambah stok kopi susu 10\nkopi susu 6', products);
      expect(r.lines[0].message, 'Stok cuma 4, kurang 2');
      expect(r.lines[2].status, LineStatus.ok);
    });
    test('stock fixes: Jual N saja and Tambah stok M dulu', () {
      const t = 'es teh manis 1\nkopi susu 6';
      final l = lint(t, products).lines[1];
      expect(l.message, 'Stok cuma 4, kurang 2');
      expect(l.fixes.map((f) => f.label), ['Jual 4 saja', 'Tambah stok 2 dulu']);
      expect(l.fixes[0].apply(t), 'es teh manis 1\nKopi susu 4');
      expect(l.fixes[1].apply(t), 'es teh manis 1\ntambah stok Kopi susu 2\nkopi susu 6');
      expect(lint(l.fixes[1].apply(t), products).errors, 0);
    });
    test('adjust_down beyond stock', () {
      final l = one('hapus stok kopi susu 6 alasan basi');
      expect(l.message, 'Stok cuma 4, kurang 2');
      expect(l.fixes.single.apply('hapus stok kopi susu 6 alasan basi'), 'hapus stok kopi susu 4 alasan basi');
    });
    test('hapus stok lines are not in Total; counts', () {
      final r = lint('nasi goreng 2\nes teh manis 1\nhapus stok kopi susu 1 alasan basi', products);
      expect(r.total, 33000);
      expect(r.saleCount, 2);
      expect(r.portionCount, 3);
    });
    test('canSave needs an op and no errors; warnings are fine', () {
      expect(lint('', products).canSave, isFalse);
      expect(lint('   \n', products).canSave, isFalse);
      expect(lint('nasi goreng', products).canSave, isTrue);
      expect(lint('nasi goreng 1\nxyz 1', products).canSave, isFalse);
    });
  });

  group('server line mapping', () {
    test('attaches the server message to the right box line as an error', () {
      final r = lint('nasi goreng 1\n\nes teh manis 2', products);
      expect(r.canSave, isTrue);
      final m = mapServerLines(r, [
        {'line_no': 3, 'code': 'stock_insufficient', 'message': 'Stok tidak cukup.'},
      ]);
      expect(m.lines[0].status, LineStatus.ok);
      expect(m.lines[1].status, LineStatus.error);
      expect(m.lines[1].message, 'Stok tidak cukup.');
      expect(m.errors, 1);
      expect(m.canSave, isFalse);
      expect(m.total, 15000);
    });
  });

  group('confirm summary', () {
    test('sales only does not need confirm', () {
      final s = ConfirmSummary(lint('nasi goreng 2', products));
      expect(s.needsConfirm, isFalse);
      expect(s.items, 1);
      expect(s.portions, 2);
      expect(s.total, 30000);
    });
    test('every section', () {
      final s = ConfirmSummary(lint(
        'nasi goreng 2\n'
        'buat produk kerupuk harga 2000 stok 30\n'
        'ubah harga es teh manis 3500\n'
        'tambah stok kopi susu 10\n'
        'hapus stok nasi goreng 1 alasan basi\n'
        'hapus es teh manis',
        products,
      ));
      expect(s.needsConfirm, isTrue);
      expect(s.sales.single.lineTotal, 30000);
      expect(s.newProducts.single.name, 'kerupuk');
      expect(s.newProducts.single.stock, 30);
      expect(s.priceChanges.single.oldPrice, 3000);
      expect(s.priceChanges.single.newPrice, 3500);
      expect(s.restocks.single.quantity, 10);
      expect(s.stockOuts.single.reason, 'basi');
      expect(s.stockOuts.single.note, 'Tidak masuk Total');
      expect(s.deletions.single.remainingStock, 20);
      expect(s.deletions.single.warning,
          'Es teh manis hilang dari Produk dan tidak bisa dibatalkan. Riwayat jualannya tetap ada.');
      expect(s.total, 30000);
    });
  });
}
