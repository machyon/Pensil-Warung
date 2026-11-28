import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import 'google_sign_in_model.dart';

/// White 56 px "<label>" button with the G mark, and its error text below.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (c) => GoogleSignInModel(c.read<AuthRepository>(), c.read<Session>()),
      child: Consumer<GoogleSignInModel>(
        builder: (context, vm, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.ink, width: 1.5),
                              ),
                              child: Text('G', style: appText(13, weight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 12),
                            Text(label, style: appText(17, weight: FontWeight.w700)),
                          ]),
                  ),
                ),
              ),
            ),
            if (vm.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(vm.error!,
                    textAlign: TextAlign.center,
                    style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
              ),
          ],
        ),
      ),
    );
  }
}
