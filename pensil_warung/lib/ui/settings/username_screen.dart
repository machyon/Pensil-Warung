import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/labeled_field.dart';
import 'account_view_model.dart';
import 'settings_widgets.dart';

/// [10a] Ubah username.
class UsernameScreen extends StatelessWidget {
  const UsernameScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => UsernameViewModel(c.read<AccountRepository>(), c.read<Session>()),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UsernameViewModel>();
    final current = context.select<Session, String>((s) => s.user?.username ?? '');
    final value = _name.text.trim();
    final ok = UsernameViewModel.valid.hasMatch(value) && value != current;
    return SettingsPage(
      title: 'Ubah username',
      bottom: PrimaryButton(
        label: 'Simpan',
        busy: vm.running,
        onPressed: ok
            ? () async {
                if (await vm.save(value) && context.mounted) Navigator.pop(context);
              }
            : null,
      ),
      children: [
        FormCard(children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.avatar, shape: BoxShape.circle),
              child: Text(current.isEmpty ? '?' : current[0].toUpperCase(),
                  style: appText(16, weight: FontWeight.w800, color: AppColors.surface)),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sekarang', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
              Text(current, style: appText(16, weight: FontWeight.w700)),
            ]),
          ]),
          const Divider(height: 1, color: AppColors.border),
          LabeledField(
            label: 'Username baru',
            controller: _name,
            autofocus: true,
            error: vm.usernameError ?? vm.error,
            onChanged: (_) {
              vm.edited();
              setState(() {});
            },
          ),
        ]),
        const InfoNote('3 sampai 30 karakter. Huruf kecil, angka, dan garis bawah. Tanpa spasi.'),
      ],
    );
  }
}
