import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class LabeledField extends StatefulWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.error,
    this.password = false,
    this.keyboardType,
    this.onChanged,
    this.textInputAction,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? error;
  final bool password;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  State<LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<LabeledField> {
  bool _hidden = true;

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    final note = widget.error ?? widget.helper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: appText(14, weight: FontWeight.w700, color: AppColors.label)),
        const SizedBox(height: 6),
        SizedBox(
          height: 56,
          child: TextField(
            controller: widget.controller,
            autofocus: widget.autofocus,
            obscureText: widget.password && _hidden,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            style: appText(16),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: appText(16, color: AppColors.faint),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              enabledBorder: hasError ? _border(AppColors.error, 2) : _border(AppColors.fieldBorder),
              focusedBorder: _border(hasError ? AppColors.error : AppColors.ink, 2),
              suffixIcon: widget.password
                  ? IconButton(
                      tooltip: _hidden ? 'Tampilkan kata sandi' : 'Sembunyikan kata sandi',
                      icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.muted),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    )
                  : null,
            ),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note,
                style: hasError
                    ? appText(14, weight: FontWeight.w700, color: AppColors.error)
                    : appText(13, color: AppColors.muted)),
          ),
      ],
    );
  }
}
