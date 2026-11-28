import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';

enum PhotoSource { camera, gallery, remove }

/// [21] FotoPilih. Null when dismissed or "Batal".
Future<PhotoSource?> showPhotoPickSheet(BuildContext context, {required String name, required bool hasPhoto}) {
  return showAppSheet<PhotoSource>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Foto $name', style: appText(20, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Foto dipotong jadi kotak.', style: appText(14, color: AppColors.muted)),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Ambil foto', onPressed: () => Navigator.pop(context, PhotoSource.camera)),
        const SizedBox(height: 10),
        SecondaryButton(label: 'Pilih dari galeri', onPressed: () => Navigator.pop(context, PhotoSource.gallery)),
        if (hasPhoto) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context, PhotoSource.remove),
            child: Text('Hapus foto', style: appText(16, weight: FontWeight.w700, color: AppColors.error)),
          ),
        ],
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Batal', style: appText(16, weight: FontWeight.w700, color: AppColors.muted)),
        ),
      ],
    ),
  );
}
