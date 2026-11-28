import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/widgets/buttons.dart';
import 'catat_view_model.dart';

/// [30] TanpaInternet, full screen. "Coba lagi" runs [retry]; the screen closes with the
/// outcome once the request gets an answer (anything but offline).
class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key, required this.retry});

  final Future<SaveOutcome> Function() retry;

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    final out = await widget.retry();
    if (!mounted) return;
    if (out == SaveOutcome.offline) {
      setState(() => _busy = false);
    } else {
      Navigator.pop(context, out);
    }
  }

  @override
  Widget build(BuildContext context) {
    const tips = ['Nyalakan data seluler atau Wi-Fi', 'Matikan mode pesawat', 'Pindah ke tempat dengan sinyal lebih kuat'];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Kembali',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
                  child: const Icon(Icons.wifi_off_rounded, size: 40),
                ),
              ),
              const SizedBox(height: 20),
              Text('Tidak ada internet', textAlign: TextAlign.center, style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text('Tulisanmu di Catat masih ada. Sambungkan internet lalu coba lagi.',
                  textAlign: TextAlign.center, style: appText(16, color: AppColors.muted)),
              const SizedBox(height: 24),
              for (var i = 0; i < tips.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: appText(14, weight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(tips[i], style: appText(15, weight: FontWeight.w600))),
                  ]),
                ),
              const Spacer(),
              PrimaryButton(label: 'Coba lagi', busy: _busy, onPressed: _retry),
            ],
          ),
        ),
      ),
    );
  }
}
