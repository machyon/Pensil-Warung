import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'app_card.dart';

/// Expandable "Per hari" card: a title row (day, total) that reveals [children].
class DayCard extends StatefulWidget {
  const DayCard({super.key, required this.title, this.subtitle, required this.trailing, this.children = const []});

  final String title;
  final String? subtitle;
  final String trailing;
  final List<Widget> children;

  @override
  State<DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<DayCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: widget.children.isEmpty ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: appText(16, weight: FontWeight.w800)),
                        if (widget.subtitle != null)
                          Text(widget.subtitle!, style: appText(13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(widget.trailing, style: appText(16, weight: FontWeight.w800)),
                  if (widget.children.isNotEmpty)
                    Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.all(16), child: Column(children: widget.children)),
          ],
        ],
      ),
    );
  }
}
