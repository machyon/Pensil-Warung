import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

const editorMin = 168.0, editorMax = 480.0, lineHeight = 32.0;

/// Text box controller that draws a red wavy underline under the lines in [errorLines] (1-based).
class CatatController extends TextEditingController {
  Set<int> _errorLines = {};

  set errorLines(Set<int> v) {
    if (v.length == _errorLines.length && v.containsAll(_errorLines)) return;
    _errorLines = v;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final rows = text.split('\n');
    return TextSpan(style: style, children: [
      for (var i = 0; i < rows.length; i++) ...[
        TextSpan(
          text: rows[i],
          style: _errorLines.contains(i + 1) && rows[i].trim().isNotEmpty
              ? const TextStyle(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.wavy,
                  decorationColor: AppColors.error,
                  decorationThickness: 1.5,
                )
              : null,
        ),
        if (i < rows.length - 1) const TextSpan(text: '\n'),
      ],
    ]);
  }
}

final _style = monoText(17);
const _strut = StrutStyle(fontSize: 17, height: lineHeight / 17, forceStrutHeight: true, fontFamily: 'Roboto Mono');

/// The Catat box: line numbers, red numbers on error lines, a drag handle that resizes it.
class CatatEditor extends StatefulWidget {
  const CatatEditor({
    super.key,
    required this.controller,
    required this.errorLines,
    required this.scroll,
    this.enabled = true,
    this.hint = 'Tulis jualan di sini',
    this.focusNode,
  });

  final CatatController controller;
  final Set<int> errorLines;
  final ScrollController scroll;
  final bool enabled;
  final String hint;
  final FocusNode? focusNode;

  @override
  State<CatatEditor> createState() => CatatEditorState();
}

class CatatEditorState extends State<CatatEditor> {
  double _h = editorMin;
  double _textWidth = 200;

  void _resize(double h) => setState(() => _h = h.clamp(editorMin, editorMax));

  /// Pixel offset of the top of line [lineNo] (1-based), counting wrapped rows.
  double offsetOfLine(int lineNo) => _heights().take(lineNo - 1).fold(0.0, (s, h) => s + h);

  List<double> _heights() => [
        for (final row in widget.controller.text.split('\n'))
          (TextPainter(
            text: TextSpan(text: row.isEmpty ? ' ' : row, style: _style),
            strutStyle: _strut,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: _textWidth))
              .height,
      ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: _h,
          padding: const EdgeInsets.fromLTRB(6, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.ink, width: 2),
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (context, c) {
            _textWidth = c.maxWidth - 22 - 14 - 8 - 2;
            return ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final heights = _heights();
                return SingleChildScrollView(
                  controller: widget.scroll,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(children: [
                        for (var i = 0; i < heights.length; i++)
                          SizedBox(
                            width: 22,
                            height: heights[i],
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${i + 1}',
                                  style: monoText(13, color: widget.errorLines.contains(i + 1) ? AppColors.error : AppColors.faint)
                                      .copyWith(fontWeight: widget.errorLines.contains(i + 1) ? FontWeight.w700 : null),
                                ),
                              ),
                            ),
                          ),
                      ]),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            enabled: widget.enabled,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: _style,
                            strutStyle: _strut,
                            cursorColor: AppColors.ink,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: widget.hint,
                              hintMaxLines: 3,
                              hintStyle: monoText(17, color: AppColors.faint),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -22,
          child: Center(
            child: Semantics(
              label: 'Ubah tinggi kotak catatan',
              child: Focus(
               onKeyEvent: (_, e) {
                 if (e is! KeyUpEvent && (e.logicalKey == LogicalKeyboardKey.arrowDown || e.logicalKey == LogicalKeyboardKey.arrowUp)) {
                   _resize(_h + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 32 : -32));
                   return KeyEventResult.handled;
                 }
                 return KeyEventResult.ignored;
               },
               child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => _resize(_h + d.delta.dy),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.chip,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.paper, width: 3),
                      ),
                      child: const Icon(Icons.unfold_more_rounded, size: 18),
                    ),
                  ),
                ),
              ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
