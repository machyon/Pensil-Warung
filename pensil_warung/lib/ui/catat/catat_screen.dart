import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../data/session.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/buttons.dart';
import 'catat_confirm.dart';
import 'catat_editor.dart';
import 'catat_results.dart';
import 'catat_view_model.dart';

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
    final out = await vm.save();
    if (!mounted) return;
    switch (out) {
      case SaveOutcome.saved:
        break;
      case SaveOutcome.linesInvalid:
        messenger.showSnackBar(const SnackBar(content: Text('Ada baris yang perlu dibetulkan.')));
      case SaveOutcome.offline:
        messenger.showSnackBar(const SnackBar(content: Text('Tidak ada internet.')));
      case SaveOutcome.failed:
        if (vm.error != null) messenger.showSnackBar(SnackBar(content: Text(vm.error!)));
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
                ),
                if (vm.lint.lines.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  ResultsCard(result: vm.lint, onFix: vm.applyFix, onGoToLine: _goToLine),
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
