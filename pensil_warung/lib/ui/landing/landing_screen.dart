import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/widgets/buttons.dart';

/// [00] AppLanding. The example card is static artwork.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Color(0x59FFC727), Color(0x00FFC727)], stops: [0.0, 0.7]),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: SvgPicture.asset('assets/images/logo_pensil_warung.svg',
                        width: 84, height: 84, semanticsLabel: 'Ikon Pensil Warung'),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('Pensil Warung',
                  textAlign: TextAlign.center, style: appText(20, weight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: 20),
              Text('Catat jualan semudah menulis di buku',
                  textAlign: TextAlign.center,
                  style: appText(31, weight: FontWeight.w800, letterSpacing: -0.8).copyWith(height: 37 / 31)),
              const SizedBox(height: 20),
              const _Example(),
              const SizedBox(height: 20),
              Text('Gratis & Tanpa Iklan :)',
                  textAlign: TextAlign.center, style: appText(14, weight: FontWeight.w600, color: AppColors.label)),
              const SizedBox(height: 28),
              PrimaryButton(label: 'Mulai sekarang', onPressed: () => context.push('/daftar')),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Saya sudah punya akun', onPressed: () => context.push('/masuk')),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _mono() => GoogleFonts.robotoMono(fontSize: 16, height: 30 / 16, color: AppColors.ink);

class _Example extends StatelessWidget {
  const _Example();

  Widget _caps(String t, EdgeInsets p) =>
      Padding(padding: p, child: Text(t, style: appText(12, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)));

  Widget _line(int n, String text, {bool cursor = false}) => Row(children: [
        SizedBox(
            width: 22,
            child: Text('$n', textAlign: TextAlign.right, style: appText(13, color: AppColors.faint))),
        const SizedBox(width: 14),
        Text(text, style: _mono()),
        if (cursor) Container(width: 2, height: 20, margin: const EdgeInsets.only(left: 1), color: AppColors.ink),
      ]);

  Widget _row(String name, String sub, String total) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: appText(15, weight: FontWeight.w700)),
              Text(sub, style: appText(13, color: AppColors.muted)),
            ]),
          ),
          Text(total, style: appText(15, weight: FontWeight.w700)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Contoh: teks jualan diubah menjadi transaksi',
      child: ExcludeSemantics(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.ink, width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _caps('KAMU TULIS', const EdgeInsets.fromLTRB(14, 2, 0, 2)),
              Padding(padding: const EdgeInsets.only(left: 0), child: _line(1, 'nasi goreng 2')),
              _line(2, 'es teh manis 3', cursor: true),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _caps('APLIKASI CATAT', const EdgeInsets.fromLTRB(16, 10, 16, 6)),
              _row('Nasi goreng', '2 × Rp15.000 · stok 20 → 18', 'Rp30.000'),
              _row('Es teh manis', '3 × Rp5.000 · stok 40 → 37', 'Rp15.000'),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Expanded(child: Text('Total', style: appText(14, weight: FontWeight.w700, color: AppColors.label))),
                  Text('Rp45.000', style: appText(20, weight: FontWeight.w800, letterSpacing: -0.3)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
