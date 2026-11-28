import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../data/session.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/buttons.dart';
import 'catat_editor.dart';
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
              ],
            ),
          ),
          _Bar(vm: vm),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.vm});

  final CatatViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vm.hasText ? 'Total jualan' : 'Total', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                Text(rupiah(vm.lint.total), style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
              ],
            ),
          ),
          SizedBox(width: 140, child: PrimaryButton(label: 'Simpan', onPressed: null, busy: vm.running)),
        ],
      ),
    );
  }
}
