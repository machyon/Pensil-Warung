/// One broadcast from `GET /broadcasts`. [body] and the status fields are only filled by the detail calls.
class Broadcast {
  const Broadcast({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.hasBody,
    required this.shownAt,
    this.body,
    this.status,
    this.createdAt,
    this.createdByName,
    this.cancelledAt,
    this.cancelledByName,
  });

  factory Broadcast.fromJson(Map<String, dynamic> j) => Broadcast(
        id: j['id'] as int,
        category: j['category'] as String,
        title: j['title'] as String,
        summary: j['summary'] as String,
        hasBody: j['has_body'] as bool,
        shownAt: DateTime.parse(j['shown_at'] as String),
        body: j['body'] as String?,
        status: j['effective_status'] as String?,
        createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at'] as String),
        createdByName: j['created_by_name'] as String?,
        cancelledAt: j['cancelled_at'] == null ? null : DateTime.parse(j['cancelled_at'] as String),
        cancelledByName: j['cancelled_by_name'] as String?,
      );

  final int id;
  final String category;
  final String title;
  final String summary;
  final bool hasBody;
  final DateTime shownAt;
  final String? body;

  /// Broadcaster detail only: `scheduled`, `sent` or `cancelled`.
  final String? status;
  final DateTime? createdAt;
  final String? createdByName;
  final DateTime? cancelledAt;
  final String? cancelledByName;

  /// Indonesian tag text for [category].
  String get categoryLabel => switch (category) {
        'update' => 'Pembaruan',
        'berita' => 'Berita',
        'tips' => 'Tips',
        _ => 'Info',
      };
}

/// `GET /broadcaster/broadcasts`: the recipient count, what is still scheduled and a page of sent ones.
class BroadcasterPage {
  const BroadcasterPage({required this.recipientCount, required this.scheduled, required this.sent, this.nextCursor});

  factory BroadcasterPage.fromJson(Map<String, dynamic> j) {
    final sent = j['sent'] as Map<String, dynamic>;
    return BroadcasterPage(
      recipientCount: j['recipient_count'] as int,
      scheduled: [for (final b in j['scheduled'] as List) Broadcast.fromJson(b as Map<String, dynamic>)],
      sent: [for (final b in sent['items'] as List) Broadcast.fromJson(b as Map<String, dynamic>)],
      nextCursor: sent['next_cursor'] as String?,
    );
  }

  final int recipientCount;
  final List<Broadcast> scheduled;
  final List<Broadcast> sent;
  final String? nextCursor;
}
