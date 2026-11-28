import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/prefs.dart';
import 'package:pensil_warung/ui/core/format.dart';
import 'package:pensil_warung/ui/notifications/notifikasi_screen.dart';
import 'package:pensil_warung/ui/notifications/notification_feed.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/feed.dart';

Map<String, Object?> _b(int id, String category, String title, {bool body = false, String at = '2026-11-28T03:00:00Z'}) =>
    {'id': id, 'category': category, 'title': title, 'summary': 'Ringkasan $id', 'has_body': body, 'shown_at': at};

Future<void> _pump(WidgetTester tester, NotificationFeed feed) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(value: feed, child: const MaterialApp(home: NotifikasiScreen())));
  await tester.pumpAndSettle();
}

void main() {
  test('timeAgo: Baru saja, menit lalu, then the WIB relative form', () {
    final now = DateTime.utc(2026, 11, 28, 5, 0);
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'Baru saja');
    expect(timeAgo(now.subtract(const Duration(minutes: 7)), now: now), '7 menit lalu');
    expect(timeAgo(DateTime.utc(2026, 11, 28, 2, 12), now: now), 'Hari ini, 09.12');
    expect(timeAgo(DateTime.utc(2026, 11, 27, 13, 31), now: now), 'Kemarin, 20.31');
  });

  test('unread count follows the read set; markRead persists', () async {
    final feed = await testFeed(list: [_b(1, 'info', 'A'), _b(2, 'tips', 'B'), _b(3, 'update', 'C')], read: {2});
    await feed.load();
    expect(feed.unreadCount, 2);
    expect(feed.hasUnread, isTrue);
    await feed.markRead(1);
    expect(feed.unreadCount, 1);
    expect(feed.unread.map((b) => b.id), [3]);
    expect(Prefs(await SharedPreferences.getInstance()).readBroadcastIds, {1, 2});
  });

  testWidgets('empty feed shows the Kosong state', (tester) async {
    final feed = await testFeed();
    await _pump(tester, feed);
    expect(find.text('Belum ada notifikasi'), findsOneWidget);
    expect(find.text('Belum ada'), findsOneWidget);
  });

  testWidgets('rows show tag and dot; Belum dibaca filters; opening clears the dot and shows the body', (tester) async {
    final reads = <String>[];
    final feed = await testFeed(
      list: [_b(2, 'tips', 'Judul dua', body: true), _b(1, 'info', 'Judul satu')],
      detail: {2: 'Isi lengkap dua'},
      read: {1},
      onRequest: (r) => reads.add(r.url.path),
    );
    await _pump(tester, feed);
    await tester.pumpAndSettle();
    expect(find.text('1 belum dibaca'), findsOneWidget);
    expect(find.textContaining('Tips · '), findsOneWidget);
    expect(find.textContaining('Info · '), findsOneWidget);
    expect(find.bySemanticsLabel('Belum dibaca'), findsOneWidget);

    await tester.tap(find.text('Belum dibaca'));
    await tester.pump();
    expect(find.text('Judul satu'), findsNothing);

    await tester.tap(find.text('Judul dua'));
    await tester.pumpAndSettle();
    expect(find.text('Isi lengkap dua'), findsOneWidget);
    expect(reads, contains('/api/v1/broadcasts/2'));
    expect(feed.hasUnread, isFalse);
    expect(feed.unreadCount, 0);
  });

  testWidgets('a broadcast without a body does not fetch the detail', (tester) async {
    final reads = <String>[];
    final feed = await testFeed(list: [_b(1, 'info', 'Tanpa isi')], onRequest: (r) => reads.add(r.url.path));
    await _pump(tester, feed);
    await tester.tap(find.text('Tanpa isi'));
    await tester.pumpAndSettle();
    expect(reads, ['/api/v1/broadcasts']);
    expect(feed.hasUnread, isFalse);
  });
}
