import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/broadcaster_repository.dart';
import '../../domain/broadcast.dart';
import '../core/format.dart';
import 'siaran_view_model.dart';

const pastTimeText = 'Waktunya sudah lewat. Pilih waktu setelah sekarang.';
const badTimeText = 'Tulis jam dalam format 24 jam, misalnya 18:00.';

/// The message being written ([18]) and when to send it ([20]). Shared by both screens;
/// [editing] is set when it came from "Ubah" on a scheduled broadcast.
class BroadcastDraft extends ChangeNotifier {
  BroadcastDraft(this._repo, this._list, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _resetWhen();
  }

  final BroadcasterRepository _repo;
  final SiaranViewModel _list;
  final DateTime Function() _clock;

  String category = 'info';
  String title = '';
  String summary = '';
  String body = '';
  bool sendNow = false;

  /// WIB date `YYYY-MM-DD` and the typed time.
  String date = '';
  String time = '';

  /// The scheduled broadcast being changed, if any (its detail, with `body`).
  Broadcast? editing;

  /// Bumped when the text fields must be refilled (reset, start of an edit).
  int revision = 0;

  bool running = false;
  Object? error;

  bool get ready => title.trim().isNotEmpty && summary.trim().isNotEmpty;

  void _resetWhen() {
    final t = _clock().add(const Duration(hours: 1)); // an hour ahead, on the hour
    date = wibIsoDate(t);
    time = '${two(wib(t).hour)}:00';
    sendNow = false;
  }

  void reset() {
    category = 'info';
    title = summary = body = '';
    editing = null;
    error = null;
    _resetWhen();
    revision++;
    notifyListeners();
  }

  void startEdit(Broadcast b) {
    category = b.category;
    title = b.title;
    summary = b.summary;
    body = b.body ?? '';
    editing = b;
    error = null;
    final w = wib(b.shownAt);
    date = wibIsoDate(b.shownAt);
    time = '${two(w.hour)}:${two(w.minute)}';
    sendNow = false;
    revision++;
    notifyListeners();
  }

  void update({String? category, String? title, String? summary, String? body, bool? sendNow, String? date, String? time}) {
    this.category = category ?? this.category;
    this.title = title ?? this.title;
    this.summary = summary ?? this.summary;
    this.body = body ?? this.body;
    this.sendNow = sendNow ?? this.sendNow;
    this.date = date ?? this.date;
    this.time = time ?? this.time;
    if (error is ApiException && (error as ApiException).code == 'time_passed') error = null;
    notifyListeners();
  }

  /// The chosen moment, or null when "now" or the time text is not `HH:MM`.
  DateTime? get at {
    final m = RegExp(r'^(\d{1,2})[:.]?(\d{2})$').firstMatch(time.trim());
    if (sendNow || m == null || date.isEmpty) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) return null;
    return DateTime.parse('${date}T${two(h)}:${two(min)}:00+07:00');
  }

  /// RFC 3339 with `+07:00`, or null to send now.
  String? get sendAt {
    final t = at;
    return t == null ? null : '${date}T${two(wib(t).hour)}:${two(wib(t).minute)}:00+07:00';
  }

  /// What is wrong with the schedule, or null. The server's `time_passed` shows the same alert.
  String? get whenError {
    if (sendNow) return null;
    final t = at;
    if (t == null) return badTimeText;
    if (!t.isAfter(_clock()) || (error is ApiException && (error as ApiException).code == 'time_passed')) return pastTimeText;
    return null;
  }

  /// Only what differs from [editing]. `send_at: null` means send now.
  Map<String, Object?> changes() {
    final o = editing!;
    final t = at;
    return {
      if (category != o.category) 'category': category,
      if (title.trim() != o.title) 'title': title.trim(),
      if (summary.trim() != o.summary) 'summary': summary.trim(),
      if (body.trim() != (o.body ?? '')) 'body': body.trim(),
      if (sendNow) 'send_at': null else if (t != null && !t.isAtSameMomentAs(o.shownAt)) 'send_at': sendAt,
    };
  }

  /// Sends or schedules; PATCHes with only the changes when editing. Null on failure ([error] is set).
  Future<Broadcast?> submit() async {
    if (running || !ready || whenError != null) return null;
    running = true;
    error = null;
    notifyListeners();
    try {
      final Broadcast b;
      if (editing == null) {
        b = await _repo.create(
          category: category,
          title: title.trim(),
          summary: summary.trim(),
          body: body.trim().isEmpty ? null : body.trim(),
          sendAt: sendNow ? null : sendAt,
        );
      } else {
        final c = changes();
        b = c.isEmpty ? editing! : await _repo.update(editing!.id, c);
      }
      _list.load();
      return b;
    } on ApiException catch (e) {
      error = e;
    } on NetworkException catch (e) {
      error = e;
    } finally {
      running = false;
      notifyListeners();
    }
    return null;
  }
}
