import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/widgets/buttons.dart';

/// [22] FotoPotong. Pops the cropped bytes ("Pakai foto"), `false` ("Ulangi",
/// back to the sheet) or null (back).
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.image});

  final Uint8List image;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _controller = CropController();
  late Uint8List _image = widget.image;
  Rect? _rect; // the crop square, in viewport coordinates
  double _base = 0; // side of the square at zoom 1
  double _zoom = 1;
  bool _busy = false;

  // Zoom = shrink the square around its centre.
  void _setZoom(double z) {
    final r = _rect;
    if (r == null || _base == 0) return;
    setState(() => _zoom = z);
    _controller.cropRect = Rect.fromCenter(center: r.center, width: _base / z, height: _base / z);
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final codec = await ui.instantiateImageCodec(_image);
    final src = (await codec.getNextFrame()).image;
    final rec = ui.PictureRecorder();
    Canvas(rec)
      ..translate(src.height.toDouble(), 0)
      ..rotate(1.5707963267948966)
      ..drawImage(src, Offset.zero, Paint());
    final out = await rec.endRecording().toImage(src.height, src.width);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    setState(() {
      _image = data!.buffer.asUint8List();
      _zoom = 1;
      _rect = null;
      _busy = false;
    });
    _controller.image = _image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111110),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(children: [
                IconButton(
                  tooltip: 'Kembali',
                  color: Colors.white,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Text('Atur foto', style: appText(22, weight: FontWeight.w800, color: Colors.white)),
                const Spacer(),
                IconButton(
                  tooltip: 'Putar 90 derajat',
                  color: Colors.white,
                  onPressed: _busy ? null : _rotate,
                  icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                ),
              ]),
            ),
            Expanded(
              child: Crop(
                image: _image,
                controller: _controller,
                aspectRatio: 1,
                baseColor: const Color(0xFF111110),
                maskColor: Colors.black54,
                radius: 12,
                cornerDotBuilder: (_, _) => const SizedBox.shrink(),
                progressIndicator: const CircularProgressIndicator(),
                initialRectBuilder: InitialRectBuilder.withBuilder((viewport, image) {
                  _base = image.shortestSide;
                  return Rect.fromCenter(center: image.center, width: _base, height: _base);
                }),
                onMoved: (viewport, _) => _rect = viewport,
                onCropped: (r) {
                  if (!mounted) return;
                  if (r is CropSuccess) {
                    Navigator.pop(context, r.croppedImage);
                  } else {
                    setState(() => _busy = false);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto tidak bisa dipotong. Coba foto lain.')));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text('Geser foto supaya barangnya di tengah',
                  style: appText(14, color: Colors.white70), textAlign: TextAlign.center),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const Icon(Icons.zoom_out, color: Colors.white70),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    min: 1,
                    max: 4,
                    label: 'Perbesar foto',
                    semanticFormatterCallback: (_) => 'Perbesar foto',
                    activeColor: AppColors.accent,
                    onChanged: _busy ? null : _setZoom,
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white70),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(child: SecondaryButton(label: 'Ulangi', onPressed: _busy ? null : () => Navigator.pop(context, false))),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Pakai foto',
                    busy: _busy,
                    onPressed: () {
                      setState(() => _busy = true);
                      _controller.crop();
                    },
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
