import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Back arrow (to Landing) on the auth screens, optionally with logo + wordmark.
class AuthBackHeader extends StatelessWidget {
  const AuthBackHeader({super.key, this.brand = false});

  final bool brand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(children: [
        IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded, size: 26),
          onPressed: () => context.canPop() ? context.pop() : context.go('/welcome'),
        ),
        if (brand) ...[
          SvgPicture.asset('assets/images/logo_pensil_warung.svg', width: 36, height: 36),
          const SizedBox(width: 10),
          Text('Pensil Warung', style: appText(22, weight: FontWeight.w400, letterSpacing: -0.8)),
        ],
      ]),
    );
  }
}

/// The "atau" divider between the form button and the Google button.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(height: 1, color: AppColors.border));
    return Row(children: [
      line,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('atau', style: appText(14, weight: FontWeight.w600, color: AppColors.muted)),
      ),
      line,
    ]);
  }
}

/// "Belum punya akun? Daftar" style footer link.
class SwitchLink extends StatelessWidget {
  const SwitchLink({super.key, required this.text, required this.action, required this.onTap});

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text.rich(TextSpan(
            style: appText(15, color: AppColors.muted),
            children: [
              TextSpan(text: '$text '),
              TextSpan(text: action, style: appText(15, weight: FontWeight.w700)),
            ],
          )),
        ),
      ),
    );
  }
}
