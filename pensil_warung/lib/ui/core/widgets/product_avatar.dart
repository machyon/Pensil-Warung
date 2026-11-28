import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Photo (URL as the API sends it) or up to two initials on `#EAE9E8`.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, required this.name, this.photoUrl, this.size = 48, this.onPhotoError});

  final String name;
  final String? photoUrl;
  final double size;

  /// Called when the photo fails to load (an expired URL); the owner refreshes the product.
  final VoidCallback? onPhotoError;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final letters = words.length == 1 ? words[0].substring(0, words[0].length.clamp(1, 2)) : words[0][0] + words[1][0];
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(child: Text(_initials, style: appText(size * 0.33, weight: FontWeight.w800, color: AppColors.label)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Container(
        width: size,
        height: size,
        color: AppColors.chip,
        child: photoUrl == null
            ? fallback
            : Image.network(photoUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) {
                  if (onPhotoError != null) WidgetsBinding.instance.addPostFrameCallback((_) => onPhotoError!());
                  return fallback;
                }),
      ),
    );
  }
}
