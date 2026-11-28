import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/prefs.dart';
import 'package:pensil_warung/data/repositories/broadcast_repository.dart';
import 'package:pensil_warung/ui/notifications/notification_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A feed over a mocked API. [list] answers GET /broadcasts; [detail] maps an id to its body.
Future<NotificationFeed> testFeed({
  List<Map<String, Object?>> list = const [],
  Map<int, String?> detail = const {},
  Set<int> read = const {},
  void Function(http.Request)? onRequest,
}) async {
  SharedPreferences.setMockInitialValues({if (read.isNotEmpty) 'read_broadcast_ids': [for (final i in read) '$i']});
  final api = ApiClient(
    baseUrl: 'http://x',
    client: MockClient((r) async {
      onRequest?.call(r);
      final m = RegExp(r'/broadcasts/(\d+)$').firstMatch(r.url.path);
      final body = m == null
          ? list
          : {...list.firstWhere((b) => b['id'].toString() == m[1]), 'body': detail[int.parse(m[1]!)]};
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    }),
  );
  return NotificationFeed(BroadcastRepository(api), Prefs(await SharedPreferences.getInstance()));
}
