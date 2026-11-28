import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/labeled_field.dart';
import 'account_view_model.dart';
import 'settings_widgets.dart';

/// [10d] Ubah kata sandi. The new token keeps this phone signed in.
class PasswordScreen extends StatelessWidget {
  const PasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => PasswordViewModel(c.read<AccountRepository>(), c.read<Session>()),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PasswordViewModel>();
    final longEnough = _new.text.length >= 8;
    final same = _new.text.isNotEmpty && _new.text == _repeat.text;
    final ok = _current.text.isNotEmpty && longEnough && same;
    void edited(String _) {
      vm.edited();
      setState(() {});
    }

    return SettingsPage(
      title: 'Ubah kata sandi',
      bottom: PrimaryButton(
        label: 'Simpan kata sandi',
        busy: vm.running,
        onPressed: ok
            ? () async {
                if (await vm.save(_current.text, _new.text) && context.mounted) Navigator.pop(context);
              }
            : null,
      ),
      children: [
        FormCard(children: [
          LabeledField(
              label: 'Kata sandi sekarang', controller: _current, password: true, error: vm.currentError, onChanged: edited),
          const Divider(height: 1, color: AppColors.border),
          LabeledField(label: 'Kata sandi baru', controller: _new, password: true, error: vm.newError ?? vm.error, onChanged: edited),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _Check('Minimal 8 karakter', longEnough),
              const SizedBox(height: 8),
              _Check('Sama dengan kata sandi baru', same),
            ]),
          ),
          LabeledField(label: 'Ulangi kata sandi baru', controller: _repeat, password: true, onChanged: edited),
        ]),
        const InfoNote('Setelah diganti, HP lain yang masuk dengan akun ini akan keluar otomatis.'),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.text, this.done);

  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: done ? AppColors.ink : AppColors.disabled),
          child: Icon(Icons.check_rounded, size: 14, color: done ? AppColors.surface : AppColors.onDisabled),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: appText(14, weight: FontWeight.w600))),
      ]);
}
