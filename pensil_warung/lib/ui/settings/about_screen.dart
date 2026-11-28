import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/theme.dart';
import 'settings_widgets.dart';

/// [10f] Tentang. "Cek pembaruan" and "Beri nilai aplikasi" wait for a Play Store listing.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Tentang',
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(children: [
            SvgPicture.asset('assets/images/logo_pensil_warung.svg', width: 84, height: 84),
            const SizedBox(height: 16),
            Text('Pensil Warung', style: appText(20, weight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 8),
            Text('Catat jualan semudah menulis di buku',
                textAlign: TextAlign.center, style: appText(22, weight: FontWeight.w800, letterSpacing: -0.5).copyWith(height: 28 / 22)),
            const SizedBox(height: 10),
            Text('Gratis & Tanpa Iklan :)', style: appText(14, weight: FontWeight.w600, color: AppColors.label)),
          ]),
        ),
        SettingsSection(children: [
          SettingsRow(label: 'Versi aplikasi', value: _version),
          SettingsRow(
              label: 'Lisensi sumber terbuka',
              onTap: () => showLicensePage(context: context, applicationName: 'Pensil Warung')),
        ]),
        Center(child: Text('Pensil Warung · ${DateTime.now().year}', style: appText(13, color: AppColors.muted))),
      ],
    );
  }
}
