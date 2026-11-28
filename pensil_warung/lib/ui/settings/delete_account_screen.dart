import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/labeled_field.dart';
import 'account_view_model.dart';
import 'google_reauth.dart';
import 'settings_widgets.dart';

const _red = Color(0xFFB3261E);

/// [10h] Hapus akun and its [10i] confirm sheet.
class DeleteAccountScreen extends StatelessWidget {
  const DeleteAccountScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => DeleteViewModel(c.read<AccountRepository>(), c.read<Session>(), c.read<GoogleReauth>(),
            hasPassword: c.read<Session>().user?.hasPassword ?? true),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm(DeleteViewModel vm, String username) async {
    final ok = await showAppSheet<bool>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline_rounded, color: _red),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hapus akun $username?', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4).copyWith(height: 28 / 22)),
                const SizedBox(height: 4),
                Text('Produk, histori jualan, dan laporan hilang permanen.',
                    style: appText(14, color: AppColors.label).copyWith(height: 20 / 14)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Akun akan dihapus permanen, apakah anda yakin untuk menghapus?',
                    style: appText(13, weight: FontWeight.w600, color: AppColors.error).copyWith(height: 19 / 13)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(flex: 10, child: SecondaryButton(label: 'Batal', onPressed: () => Navigator.pop(context, false))),
            const SizedBox(width: 12),
            Expanded(flex: 13, child: DangerButton(label: 'Hapus permanen', onPressed: () => Navigator.pop(context, true))),
          ]),
        ],
      ),
    );
    if (ok == true) await vm.delete(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeleteViewModel>();
    final user = context.select<Session, ({String username, String email})>(
        (s) => (username: s.user?.username ?? '', email: s.user?.email ?? ''));
    final products = context.watch<ProductRepository>();
    final ready = vm.understood && (vm.hasPassword ? _password.text.isNotEmpty : vm.signedInAgain);
    return SettingsPage(
      title: 'Hapus akun',
      bottom: DangerButton(
        label: 'Hapus akun',
        busy: vm.running,
        onPressed: ready ? () => _confirm(vm, user.username) : null,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text.rich(
            TextSpan(style: appText(15, color: AppColors.label).copyWith(height: 22 / 15), children: [
              const TextSpan(text: 'Akun '),
              TextSpan(text: user.username, style: appText(15, weight: FontWeight.w700)),
              const TextSpan(text: ' dan semua isinya akan dihapus permanen. Ini tidak bisa dibatalkan.'),
            ]),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('YANG IKUT TERHAPUS', style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
            ),
            _Lost(Icons.inventory_2_outlined, 'Produk dan stok', products.loaded ? '${products.items.length} barang' : null),
            _Lost(Icons.receipt_long_outlined, 'Histori jualan', 'Semua transaksi sejak akun dibuat'),
            _Lost(Icons.bar_chart_rounded, 'Laporan analitik', 'Ringkasan bulanan dan terlaris'),
            _Lost(Icons.person_outline_rounded, 'Username dan email', '${user.email} bisa dipakai daftar lagi'),
          ]),
        ),
        FormCard(children: [
          if (vm.hasPassword)
            LabeledField(
              label: 'Kata sandi',
              controller: _password,
              password: true,
              error: vm.passwordError ?? vm.error,
              onChanged: (_) {
                vm.edited();
                setState(() {});
              },
            )
          else ...[
            SecondaryButton(
              label: vm.signedInAgain ? 'Sudah masuk ulang dengan Google' : 'Masuk ulang dengan Google',
              busy: vm.running,
              onPressed: vm.reauth,
            ),
            if (vm.error != null) Text(vm.error!, style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
          ],
          const Divider(height: 1, color: AppColors.border),
          InkWell(
            onTap: () => vm.setUnderstood(!vm.understood),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(value: vm.understood, activeColor: AppColors.ink, onChanged: (v) => vm.setUnderstood(v ?? false)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Saya mengerti semua data di atas hilang dan tidak bisa dikembalikan.',
                    style: appText(14, weight: FontWeight.w600).copyWith(height: 20 / 14)),
              ),
            ]),
          ),
        ]),
      ],
    );
  }
}

class _Lost extends StatelessWidget {
  const _Lost(this.icon, this.title, this.sub);

  final IconData icon;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppColors.error),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(15, weight: FontWeight.w700)),
              if (sub != null) Text(sub!, style: appText(13, color: AppColors.muted)),
            ]),
          ),
        ]),
      );
}
