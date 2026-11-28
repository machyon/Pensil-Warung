/// One broadcast from `GET /broadcasts`. [body] is only filled by the detail call.
class Broadcast {
  const Broadcast({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.hasBody,
    required this.shownAt,
    this.body,
  });

  factory Broadcast.fromJson(Map<String, dynamic> j) => Broadcast(
        id: j['id'] as int,
        category: j['category'] as String,
        title: j['title'] as String,
        summary: j['summary'] as String,
        hasBody: j['has_body'] as bool,
        shownAt: DateTime.parse(j['shown_at'] as String),
        body: j['body'] as String?,
      );

  final int id;
  final String category;
  final String title;
  final String summary;
  final bool hasBody;
  final DateTime shownAt;
  final String? body;

  /// Indonesian tag text for [category].
  String get categoryLabel => switch (category) {
        'update' => 'Pembaruan',
        'berita' => 'Berita',
        'tips' => 'Tips',
        _ => 'Info',
      };
}
