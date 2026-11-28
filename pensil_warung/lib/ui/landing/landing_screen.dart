import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import 'landing_view_model.dart';

/// Minimal Landing: only the Google button for now (full design in a later commit).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (c) => LandingViewModel(c.read<AuthRepository>(), c.read<Session>()),
      child: const _LandingBody(),
    );
  }
}

class _LandingBody extends StatelessWidget {
  const _LandingBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LandingViewModel>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(vm.error!,
                      textAlign: TextAlign.center,
                      style: appText(14, weight: FontWeight.w600, color: AppColors.error)),
                ),
              SizedBox(
                height: 56,
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: AppColors.fieldBorder),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: vm.running ? null : vm.signInWithGoogle,
                    child: Center(
                      child: vm.running
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('G',
                                  style: appText(20, weight: FontWeight.w800, color: const Color(0xFF4285F4))),
                              const SizedBox(width: 12),
                              Text('Masuk dengan Google',
                                  style: appText(16, weight: FontWeight.w800, color: AppColors.ink)),
                            ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
