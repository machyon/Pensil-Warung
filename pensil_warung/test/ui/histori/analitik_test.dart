import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/repositories/analytics_repository.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/data/repositories/transaction_repository.dart';
import 'package:pensil_warung/domain/analytics.dart';
import 'package:pensil_warung/ui/core/format.dart';
import 'package:pensil_warung/ui/histori/analitik_view.dart';
import 'package:pensil_warung/ui/histori/barang_view_model.dart';
import 'package:pensil_warung/ui/histori/histori_view_model.dart';
import 'package:provider/provider.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Map<String, Object?> _month({Object? changePct = 8.2, List<int>? weekday, int through = 17, List<Object> top = const []}) => {
      'month': '2026-11', 'through_day': through, 'revenue': 18175000, 'transaction_count': 641,
      'previous': {'month': '2026-10', 'revenue': 16800000, 'change_pct': changePct},
      'trend': [for (var m = 0; m < 12; m++) {'month': monthKey(2025 * 12 + 11 + m), 'revenue': m * 1000000}],
      'weekday_avg': weekday == null ? null : [for (var d = 0; d < 7; d++) {'weekday': d + 1, 'avg_revenue': weekday[d]}],
      'top_items': top,
    };

Map<String, Object?> _top(int id, String name, int qty, int revenue) =>
    {'product_id': id, 'name': name, 'qty': qty, 'revenue': revenue, 'stock': 5};

void main() {
  group('pure rules', () {
    test('comparison line: up, down, null', () {
      expect(comparisonLine(MonthSummary.fromJson(_month())), '▲ 8,2% dari 1–17 Okt · 641 transaksi');
      expect(comparisonLine(MonthSummary.fromJson(_month(changePct: -3.0))), '▼ 3% dari 1–17 Okt · 641 transaksi');
      expect(comparisonLine(MonthSummary.fromJson(_month(changePct: null))), '641 transaksi');
    });

    test('change_pct may arrive as an integer', () {
      expect(MonthSummary.fromJson(_month(changePct: 8)).previous.changePct, 8.0);
    });

    test('gates open at 14 days (weekday), 7 days (top items) and a non-null change_pct', () {
      MonthSummary s(int days) => MonthSummary.fromJson(_month(weekday: days >= 14 ? [1, 2, 3, 4, 5, 6, 7] : null, top: [_top(1, 'A', 3, 30)]));
      expect(analitikGates(s(13), 13).weekday, isFalse);
      expect(analitikGates(s(14), 14).weekday, isTrue);
      expect(analitikGates(s(6), 6).top, isFalse);
      expect(analitikGates(s(7), 7).top, isTrue);
      expect(analitikGates(MonthSummary.fromJson(_month(changePct: null)), 20).comparison, isFalse);
      expect(analitikGates(MonthSummary.fromJson(_month()), 20).comparison, isTrue);
    });

    test('best and worst weekday, and the mean of the 7 values', () {
      final st = weekdayStats([887000, 600000, 700000, 500000, 900000, 1500000, 1000000]);
      expect(st.best, 'Sabtu');
      expect(st.worst, 'Kamis');
      expect(st.worstValue, 500000);
      expect(st.mean, 869571); // 6087000 / 7, whole rupiah
    });

    test('top items sentence: different items, same item', () {
      final a = TopItem.fromJson(_top(1, 'Es teh', 512, 2560000)), b = TopItem.fromJson(_top(2, 'Nasi goreng', 300, 4500000));
      expect(topItemsSentence([a, b], 18000000), 'Nasi goreng menyumbang 25% penjualan, walau Es teh paling banyak terjual.');
      expect(topItemsSentence([b, a], 18000000), 'Nasi goreng paling laris bulan ini.');
    });

    test('share bar: top 5 plus Lainnya', () {
      SoldItem it(int i, double pct) => SoldItem.fromJson({..._top(i, 'B$i', 1, 1), 'share_pct': pct});
      final seg = shareSegments([it(1, 30), it(2, 20), it(3, 15), it(4, 10), it(5, 5), it(6, 12), it(7, 8)]);
      expect(seg.map((s) => s.label), ['B1', 'B2', 'B3', 'B4', 'B5', 'Lainnya']);
      expect(seg.last.pct, 20.0);
      expect(shareSegments([it(1, 60), it(2, 40)]).length, 2); // nothing left over
    });

    test('percent drops a trailing .0', () {
      expect(percent(8.0), '8');
      expect(percent(23.4), '23,4');
    });
  });

  group('Analitik segment', () {
    late ProductRepository products;
    late TransactionRepository tx;
    late AnalyticsRepository repo;

    Future<void> pump(WidgetTester tester, {required int days, required Map<String, Object?> month}) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = ApiClient(baseUrl: 'http://x', client: MockClient((r) async {
        return switch (r.url.path) {
          '/api/v1/analytics/months' => _json([{'month': '2026-11', 'revenue': 18175000}]),
          '/api/v1/analytics/month' => _json(month),
          '/api/v1/analytics/month/days' => _json({'items': [for (var d = 0; d < days; d++) {'day': '2026-11-${two(17 - d)}', 'transaction_count': 3, 'revenue': 100000}], 'next_cursor': null}),
          _ => http.Response('{}', 500),
        };
      }));
      products = ProductRepository(api);
      tx = TransactionRepository(api, products);
      repo = AnalyticsRepository(api);
      final vm = HistoriViewModel(repo, tx);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: products)],
        child: MaterialApp(home: Scaffold(body: ListenableBuilder(listenable: vm, builder: (_, _) => AnalitikView(vm: vm)))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('3 days: progress card and the later list, no weekday chart', (tester) async {
      await pump(tester, days: 3, month: _month(changePct: null, top: [_top(1, 'Nasi goreng', 3, 45000)], through: 3));
      expect(find.text('Laporan lengkap sedang disiapkan'), findsOneWidget);
      expect(find.text('3 dari 14 hari · 11 hari lagi'), findsOneWidget);
      expect(find.text('Butuh 14 hari jualan supaya polanya akurat'), findsOneWidget);
      expect(find.text('641 transaksi · 3 hari tercatat'), findsOneWidget);
      expect(find.text('Akan muncul nanti'), findsOneWidget);
      expect(find.text('Mulai Desember'), findsOneWidget);
      expect(find.text('Setelah 7 hari'), findsOneWidget);
      expect(find.textContaining('biasanya paling laris'), findsNothing);
      expect(find.textContaining('paling laris bulan ini'), findsNothing);
    });

    testWidgets('14 days: weekday chart and top items, no progress card', (tester) async {
      await pump(tester, days: 14, month: _month(weekday: [100000, 90000, 80000, 70000, 120000, 300000, 200000], top: [_top(1, 'Nasi goreng', 3, 45000)]));
      expect(find.text('Sabtu biasanya paling laris'), findsOneWidget);
      expect(find.text('Rata-rata Rp137.142. Paling sepi hari Kamis, Rp70.000.'), findsOneWidget);
      expect(find.text('Nasi goreng paling laris bulan ini.'), findsOneWidget);
      expect(find.text('Laporan lengkap sedang disiapkan'), findsNothing);
      expect(find.text('Akan muncul nanti'), findsNothing);
      expect(find.text('▲ 8,2% dari 1–17 Okt · 641 transaksi'), findsOneWidget);
    });
  });
}
