import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'app_card.dart';

/// Expandable "Per hari" card: a title row (day, total) that reveals [children].
class DayCard extends StatefulWidget {
  const DayCard({super.key, required this.title, this.subtitle, required this.trailing, this.children = const [], this.expanded, this.onToggle});

  final String title;
  final String? subtitle;
  final String trailing;
  final List<Widget> children;

  /// Controlled mode (only one card open at a time): set both, and [children] may be empty while loading.
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  State<DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<DayCard> {
  bool _open = false;

  bool get _controlled => widget.onToggle != null;
  bool get _isOpen => _controlled ? widget.expanded ?? false : _open;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: _controlled ? widget.onToggle : widget.children.isEmpty ? null : () => setState(() => _open = !_open),
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
                  if (_controlled || widget.children.isNotEmpty)
                    Icon(_isOpen ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
                ],
              ),
            ),
          ),
          if (_isOpen) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.all(16), child: Column(children: widget.children)),
          ],
        ],
      ),
    );
  }
}
