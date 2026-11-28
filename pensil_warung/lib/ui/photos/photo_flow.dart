import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';
import 'photo_crop_screen.dart';
import 'photo_pick_sheet.dart';

/// Sheet, then camera or gallery, then crop. `bytes` is the cropped image; `remove`
/// means "Hapus foto". Null when the user backed out.
Future<({Uint8List? bytes, bool remove})?> pickProductPhoto(
  BuildContext context, {
  required String name,
  required bool hasPhoto,
}) async {
  while (true) {
    if (!context.mounted) return null;
    final source = await showPhotoPickSheet(context, name: name, hasPhoto: hasPhoto);
    if (source == null || !context.mounted) return null;
    if (source == PhotoSource.remove) return (bytes: null, remove: true);
    final XFile? file;
    try {
      // 1024 px is the most we upload; the server shrinks it again.
      file = await ImagePicker().pickImage(
        source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamera atau galeri tidak bisa dibuka.')));
      }
      return null;
    }
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return null;
    final r = await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => PhotoCropScreen(image: bytes)));
    if (r is Uint8List) return (bytes: r, remove: false);
    if (r != false) return null; // "Ulangi" goes back to the sheet
  }
}

/// Pick, crop and upload (or delete) the photo of an existing product.
/// True when the photo changed on the server.
Future<bool> changeProductPhoto(BuildContext context, Product p) async {
  final repo = context.read<ProductRepository>();
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context, rootNavigator: true);
  final pick = await pickProductPhoto(context, name: p.name, hasPhoto: p.photoUrl != null);
  if (pick == null || !context.mounted) return false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    if (pick.remove) {
      await repo.deletePhoto(p.id);
    } else {
      await repo.uploadPhoto(p.id, pick.bytes!);
    }
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(messageOf(e))));
    return false;
  } finally {
    nav.pop();
  }
}
