import 'dart:typed_data';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../data/session.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/buttons.dart';
import 'catat_confirm.dart';
import 'catat_editor.dart';
import 'catat_results.dart';
import '../photos/photo_flow.dart';
import '../../catat/parser.dart';
import '../../catat/result.dart';
import 'catat_view_model.dart';
import 'offline_screen.dart';
import 'saved_card.dart';

class CatatScreen extends StatefulWidget {
  const CatatScreen({super.key});

  @override
  State<CatatScreen> createState() => _CatatScreenState();
}

class _CatatScreenState extends State<CatatScreen> {
  final _editor = GlobalKey<CatatEditorState>();

  @override
  void initState() {
    super.initState();
    final products = context.read<ProductRepository>();
    if (!products.loaded) products.load().catchError((_) {});
  }

  Future<void> _save() async {
    final vm = context.read<CatatViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    if (vm.summary.needsConfirm &&
        !await showConfirmSheet(context, vm.summary, lineCount: vm.lint.lines.length)) {
      return;
    }
    var out = await vm.save();
    if (!mounted) return;
    if (out == SaveOutcome.offline) {
      // Same text, so Coba lagi reuses the same client_uuid.
      out = await Navigator.of(context).push<SaveOutcome>(
              MaterialPageRoute(builder: (_) => OfflineScreen(retry: vm.save))) ??
          SaveOutcome.offline;
      if (!mounted) return;
    }
    switch (out) {
      case SaveOutcome.saved:
        _afterSave(messenger, vm);
      case SaveOutcome.linesInvalid:
        messenger.showSnackBar(const SnackBar(content: Text('Ada baris yang perlu dibetulkan.')));
      case SaveOutcome.offline:
        break; // the user backed out of the offline screen; the text stays
      case SaveOutcome.failed:
        if (vm.error != null) messenger.showSnackBar(SnackBar(content: Text(vm.error!)));
    }
  }

  void _afterSave(ScaffoldMessengerState messenger, CatatViewModel vm) {
    messenger.hideCurrentSnackBar();
    final s = vm.saved;
    if (s == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Tersimpan')));
    } else if (s.undoable) {
      messenger.showSnackBar(SnackBar(
        content: Text('Tersimpan · ${rupiah(s.tx.total)}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () async {
            final err = await vm.undo();
            if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
          },
        ),
      ));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('Tersimpan')));
    }
    if (vm.failedPhotos > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text('${vm.failedPhotos} foto belum terunggah. Coba lagi dari halaman barangnya.')));
    }
  }

  void _goToLine(int n) {
    final vm = context.read<CatatViewModel>();
    final e = _editor.currentState;
    if (e == null || !vm.scroll.hasClients) return;
    vm.scroll.animateTo(e.offsetOfLine(n).clamp(0, vm.scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CatatViewModel>();
    final name = context.select<Session, String>((s) => s.user?.displayName ?? '?');
    return SafeArea(
      child: Column(
        children: [
          AppHeader(title: 'Catat', subtitle: wibDateShort(DateTime.now()), avatarLetter: name.isEmpty ? '?' : name[0]),
          Expanded(
            child: ListView(
              controller: null,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                CatatEditor(
                  key: _editor,
                  controller: vm.controller,
                  errorLines: vm.errorLines,
                  scroll: vm.scroll,
                  enabled: vm.boxEnabled,
                  hint: vm.noProducts
                      ? vm.commandMode ? 'buat produk nama harga 2000 stok 30' : 'Tambah barang dulu supaya bisa dicatat'
                      : 'Tulis jualan di sini',
                ),
                if (vm.noProducts && !vm.commandMode) ...[
                  const SizedBox(height: 40),
                  _NoProducts(onAdd: () => context.push('/produk/tambah'), onCommand: vm.enableCommandMode),
                ],
                if (vm.noProducts && vm.commandMode) ...[
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text.rich(TextSpan(style: appText(14, color: AppColors.label), children: [
                      const TextSpan(text: 'Satu barang per baris: '),
                      TextSpan(text: 'buat produk nama harga 2000 stok 30', style: monoText(13)),
                    ])),
                  ),
                ],
                if (vm.saved != null) ...[
                  const SizedBox(height: 40),
                  SavedCardView(saved: vm.saved!),
                ],
                if (vm.lint.lines.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  ResultsCard(
                    result: vm.lint,
                    onFix: vm.applyFix,
                    onGoToLine: _goToLine,
                    trailing: (l) => l.kind == LineKind.createProduct && l.status != LineStatus.error
                        ? _PhotoButton(name: l.productName!, bytes: vm.photos[l.productName!.toLowerCase()], vm: vm)
                        : null,
                  ),
                ],
              ],
            ),
          ),
          _Bar(vm: vm, onSave: _save),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.vm, required this.onSave});

  final CatatViewModel vm;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final newOnly = vm.lint.saleCount == 0 && vm.summary.newProducts.isNotEmpty;
    final label = newOnly ? 'Barang baru' : vm.hasText ? 'Total jualan' : 'Total';
    final value = newOnly ? '${vm.summary.newProducts.length}' : rupiah(vm.lint.total);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (vm.lint.errors > 0)
                  Text('Betulkan ${vm.lint.errors} baris dulu', style: appText(16, weight: FontWeight.w800, color: AppColors.error))
                else ...[
                  Text(label, style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                  Text(value, style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
                ],
              ],
            ),
          ),
          SizedBox(width: 140, child: PrimaryButton(label: 'Simpan', onPressed: vm.lint.canSave ? onSave : null, busy: vm.running)),
        ],
      ),
    );
  }
}

class _NoProducts extends StatelessWidget {
  const _NoProducts({required this.onAdd, required this.onCommand});

  final VoidCallback onAdd, onCommand;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Belum ada barang', style: appText(20, weight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Catat hanya mengenali barang yang sudah terdaftar. Cukup isi nama, harga, dan stok. Satu barang sudah bisa.',
            style: appText(15, color: AppColors.muted)),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Tambah barang', onPressed: onAdd),
        const SizedBox(height: 10),
        SecondaryButton(label: 'Ketik perintah', onPressed: onCommand),
      ]),
    );
  }
}

/// Camera button on a new-product row; shows the picked photo once there is one.
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({required this.name, required this.bytes, required this.vm});

  final String name;
  final Uint8List? bytes;
  final CatatViewModel vm;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Foto $name',
      onPressed: () async {
        final pick = await pickProductPhoto(context, name: name, hasPhoto: bytes != null);
        if (pick != null) vm.setPhoto(name, pick.remove ? null : pick.bytes);
      },
      icon: bytes == null
          ? const Icon(Icons.photo_camera_outlined)
          : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes!, width: 32, height: 32, fit: BoxFit.cover)),
    );
  }
}
