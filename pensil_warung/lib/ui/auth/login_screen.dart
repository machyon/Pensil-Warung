import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/labeled_field.dart';
import 'auth_widgets.dart';
import 'google_button.dart';
import 'login_view_model.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => LoginViewModel(c.read<AuthRepository>(), c.read<Session>()),
        child: const _LoginBody(),
      );
}

class _LoginBody extends StatefulWidget {
  const _LoginBody();

  @override
  State<_LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<_LoginBody> {
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
    final vm = context.watch<LoginViewModel>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthBackHeader(brand: true),
              const SizedBox(height: 4),
              Text('Masuk', style: appText(34, weight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 8),
              Text('Lanjutkan catatan jualanmu.', style: appText(16, color: AppColors.muted)),
              const SizedBox(height: 24),
              LabeledField(
                label: 'Email',
                controller: _email,
                hint: 'nama@email.com',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) => vm.edited(),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Password',
                controller: _password,
                hint: 'Password kamu',
                password: true,
                error: vm.wrongPassword ? 'Email atau kata sandi salah' : null,
                onChanged: (_) => vm.edited(),
              ),
              if (vm.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(vm.error!, style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Masuk',
                busy: vm.running,
                onPressed: () => vm.login(_email.text, _password.text),
              ),
              const SizedBox(height: 16),
              const OrDivider(),
              const SizedBox(height: 16),
              const GoogleButton(label: 'Masuk dengan Google'),
              const SizedBox(height: 24),
              SwitchLink(text: 'Belum punya akun?', action: 'Daftar', onTap: () => context.pushReplacement('/daftar')),
            ],
          ),
        ),
      ),
    );
  }
}
