import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../domain/broadcast.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/error_view.dart';
import 'broadcast_widgets.dart';
import 'siaran_view_model.dart';

/// [17] Siaran: what is scheduled and what was sent.
class SiaranScreen extends StatefulWidget {
  const SiaranScreen({super.key});

  @override
  State<SiaranScreen> createState() => _SiaranScreenState();
}

class _SiaranScreenState extends State<SiaranScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<SiaranViewModel>().load());
    // Keeps the countdowns fresh and moves a due broadcast from Terjadwal to Terkirim.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final vm = context.read<SiaranViewModel>();
      if (vm.scheduled.any((b) => !b.shownAt.isAfter(DateTime.now()))) {
        vm.load();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SiaranViewModel>();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: 'Siaran',
            subtitle: vm.loaded ? 'Ke semua pengguna · ${groupedDigits(vm.recipientCount)} akun' : null,
            avatar: true,
          ),
          Expanded(child: _body(vm)),
        ],
      ),
    );
  }

  Widget _body(SiaranViewModel vm) {
    if (!vm.loaded) {
      return vm.error != null ? ErrorView(error: vm.error!, onRetry: vm.load) : const Center(child: CircularProgressIndicator());
    }
    if (vm.scheduled.isEmpty && vm.sent.isEmpty) {
      return EmptyState(
        icon: Icons.campaign_outlined,
        title: 'Belum ada siaran',
        text: 'Tulis pesan pertamamu untuk semua pengguna.',
        actionLabel: 'Tulis siaran',
        onAction: () => context.go('/tulis'),
      );
    }
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (vm.scheduled.isNotEmpty) ...[
            const _Label('Terjadwal'),
            _List(vm.scheduled, countdown: true),
            const SizedBox(height: 8),
          ],
          if (vm.sent.isNotEmpty) ...[
            const _Label('Terkirim'),
            _List(vm.sent),
            if (vm.nextCursor != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SecondaryButton(label: 'Muat lebih banyak', busy: vm.loadingMore, onPressed: vm.loadMore),
              ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
      );
}

class _List extends StatelessWidget {
  const _List(this.items, {this.countdown = false});

  final List<Broadcast> items;
  final bool countdown;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            BroadcastRow(b: items[i], countdown: countdown, onTap: () => context.push('/siaran/${items[i].id}')),
          ],
        ]),
      );
}
