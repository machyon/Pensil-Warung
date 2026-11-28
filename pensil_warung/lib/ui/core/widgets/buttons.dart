import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class _AppButton extends StatelessWidget {
  const _AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.fill,
    required this.fg,
    this.side,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color fill;
  final Color fg;
  final BorderSide? side;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: enabled ? fill : AppColors.disabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: enabled ? side ?? BorderSide.none : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onDisabled),
                  )
                : Text(label, style: appText(16, weight: FontWeight.w800, color: enabled ? fg : AppColors.onDisabled)),
          ),
        ),
      ),
    );
  }
}

/// Yellow call-to-action. `busy` disables it and shows a spinner (no double send).
class PrimaryButton extends _AppButton {
  const PrimaryButton({super.key, required super.label, required super.onPressed, super.busy})
      : super(fill: AppColors.accent, fg: AppColors.onAccent);
}

class SecondaryButton extends _AppButton {
  const SecondaryButton({super.key, required super.label, required super.onPressed, super.busy})
      : super(
          fill: AppColors.surface,
          fg: AppColors.ink,
          side: const BorderSide(color: AppColors.fieldBorder),
        );
}
