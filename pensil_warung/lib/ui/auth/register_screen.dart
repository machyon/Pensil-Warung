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
import 'register_view_model.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => RegisterViewModel(c.read<AuthRepository>(), c.read<Session>()),
        child: const _RegisterBody(),
      );
}

class _RegisterBody extends StatefulWidget {
  const _RegisterBody();

  @override
  State<_RegisterBody> createState() => _RegisterBodyState();
}

class _RegisterBodyState extends State<_RegisterBody> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RegisterViewModel>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthBackHeader(),
              const SizedBox(height: 4),
              Text('Buat akun', style: appText(34, weight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 8),
              Text('Gratis dan tanpa iklan.', style: appText(16, color: AppColors.muted)),
              const SizedBox(height: 24),
              LabeledField(
                label: 'Nama',
                controller: _name,
                hint: 'Nama kamu',
                error: vm.errors['display_name'],
                textInputAction: TextInputAction.next,
                onChanged: (_) => vm.edited('display_name'),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Email',
                controller: _email,
                hint: 'nama@email.com',
                keyboardType: TextInputType.emailAddress,
                error: vm.errors['email'],
                textInputAction: TextInputAction.next,
                onChanged: (_) => vm.edited('email'),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Password',
                controller: _password,
                hint: 'Minimal 8 karakter',
                password: true,
                helper: 'Minimal 8 karakter.',
                error: vm.errors['password'],
                onChanged: (_) => vm.edited('password'),
              ),
              if (vm.errors['form'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(vm.errors['form']!, style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Daftar',
                busy: vm.running,
                onPressed: () => vm.register(_name.text, _email.text, _password.text),
              ),
              const SizedBox(height: 16),
              const OrDivider(),
              const SizedBox(height: 16),
              const GoogleButton(label: 'Daftar dengan Google'),
              const SizedBox(height: 24),
              SwitchLink(text: 'Sudah punya akun?', action: 'Masuk', onTap: () => context.pushReplacement('/masuk')),
            ],
          ),
        ),
      ),
    );
  }
}
