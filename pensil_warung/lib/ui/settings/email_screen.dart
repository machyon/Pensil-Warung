import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/labeled_field.dart';
import 'account_view_model.dart';
import 'settings_widgets.dart';

/// [10b] Ubah email. Immediate, confirmed with the password; the new token is swapped in.
class EmailScreen extends StatelessWidget {
  const EmailScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => EmailViewModel(c.read<AccountRepository>(), c.read<Session>()),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EmailViewModel>();
    final current = context.select<Session, String>((s) => s.user?.email ?? '');
    final email = _email.text.trim();
    final ok = EmailViewModel.valid.hasMatch(email) && _password.text.isNotEmpty;
    void edited(String _) {
      vm.edited();
      setState(() {});
    }

    return SettingsPage(
      title: 'Ubah email',
      bottom: PrimaryButton(
        label: 'Simpan',
        busy: vm.running,
        onPressed: ok
            ? () async {
                if (await vm.save(email, _password.text) && context.mounted) Navigator.pop(context);
              }
            : null,
      ),
      children: [
        FormCard(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Email sekarang', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
            Text(current, style: appText(16, weight: FontWeight.w700)),
          ]),
          const Divider(height: 1, color: AppColors.border),
          LabeledField(
            label: 'Email baru',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            error: vm.emailError,
            onChanged: edited,
          ),
          LabeledField(
            label: 'Kata sandi',
            controller: _password,
            password: true,
            helper: 'Untuk memastikan ini kamu',
            error: vm.passwordError ?? vm.error,
            onChanged: edited,
          ),
        ]),
      ],
    );
  }
}
