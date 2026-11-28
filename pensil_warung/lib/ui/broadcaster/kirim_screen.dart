import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api_exception.dart';
import '../../domain/broadcast.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/category_icon.dart';
import 'broadcast_draft.dart';
import 'broadcast_widgets.dart';
import 'siaran_view_model.dart';

/// [20] Kirim, step 2: now or later, summary, confirm.
class KirimScreen extends StatefulWidget {
  const KirimScreen({super.key});

  @override
  State<KirimScreen> createState() => _KirimScreenState();
}

class _KirimScreenState extends State<KirimScreen> {
  late final _time = TextEditingController(text: context.read<BroadcastDraft>().time);

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  String _label(BroadcastDraft d) {
    final t = d.at;
    return t == null ? '-' : '${wibRelative(t)} WIB';
  }

  Future<void> _pickDate(BroadcastDraft d) async {
    final today = parseIsoDate(wibIsoDate(DateTime.now()));
    final cur = DateTime.tryParse(d.date) ?? today;
    final p = await showDatePicker(
      context: context,
      initialDate: cur.isBefore(today) ? today : cur,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (p != null) d.update(date: '${p.year}-${two(p.month)}-${two(p.day)}');
  }

  Future<void> _confirm(BroadcastDraft d) async {
    final count = context.read<SiaranViewModel>().recipientCount;
    final later = !d.sendNow;
    final when = _label(d);
    final ok = await showAppSheet<bool>(
      context,
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(later ? 'Jadwalkan untuk $when?' : 'Kirim ke ${groupedDigits(count)} pengguna sekarang?',
            style: appText(22, weight: FontWeight.w800, letterSpacing: -0.3).copyWith(height: 28 / 22)),
        const SizedBox(height: 12),
        Text(
            later
                ? 'Siaran dikirim ke semua pengguna pada waktu itu. Sebelumnya, kamu masih bisa mengubah atau membatalkannya.'
                : 'Setelah terkirim, siaran tidak bisa ditarik kembali atau diubah.',
            style: appText(15, color: AppColors.label).copyWith(height: 22 / 15)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Icon(categoryIcon(d.category), size: 20, color: AppColors.label),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title.trim(), style: appText(15, weight: FontWeight.w700)),
                Text('${_catLabel(d.category)} · ${groupedDigits(count)} penerima',
                    style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          SizedBox(width: 120, child: SecondaryButton(label: 'Batal', onPressed: () => Navigator.pop(context, false))),
          const SizedBox(width: 12),
          Expanded(child: PrimaryButton(label: later ? 'Ya, jadwalkan' : 'Ya, kirim', onPressed: () => Navigator.pop(context, true))),
        ]),
      ]),
    );
    if (ok != true || !mounted) return;
    final editing = d.editing;
    final b = await d.submit();
    if (!mounted) return;
    if (b != null) {
      d.reset();
      context.go('/siaran');
      context.push('/siaran/${b.id}');
      return;
    }
    final e = d.error;
    if (e is ApiException && e.code == 'not_editable' && editing != null) {
      // Already sent, cancelled or just due: show where it stands now.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      d.reset();
      context.go('/siaran');
      context.push('/siaran/${editing.id}');
    } else if (e != null && !(e is ApiException && e.code == 'time_passed')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageOf(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<BroadcastDraft>();
    final count = context.select<SiaranViewModel, int>((v) => v.recipientCount);
    final err = d.whenError;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SiaranHeader(title: 'Kirim', subtitle: 'Langkah 2 dari 2 · Pilih waktu', onBack: () => context.pop()),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text('Kapan dikirim?', style: appText(15, weight: FontWeight.w700)),
              ),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _Radio(
                    on: d.sendNow,
                    title: 'Kirim sekarang',
                    text: 'Sampai ke pengguna dalam beberapa menit.',
                    onTap: () => d.update(sendNow: true),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  _Radio(
                    on: !d.sendNow,
                    title: 'Jadwalkan',
                    text: 'Masih bisa diubah atau dibatalkan sebelum terkirim.',
                    onTap: () => d.update(sendNow: false),
                  ),
                  if (!d.sendNow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: _Cell(
                              label: 'Tanggal',
                              error: err != null,
                              child: InkWell(
                                onTap: () => _pickDate(d),
                                child: Container(
                                  height: 52,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(d.date.isEmpty ? '-' : dayShort(d.date), style: appText(15, weight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Cell(
                              label: 'Jam (WIB)',
                              error: err != null,
                              child: TextField(
                                controller: _time,
                                keyboardType: TextInputType.datetime,
                                maxLength: 5,
                                onChanged: (v) => d.update(time: v),
                                style: appText(15, weight: FontWeight.w600),
                                decoration: const InputDecoration(
                                  counterText: '',
                                  hintText: '00:00',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                                ),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        if (err != null)
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(err, style: appText(14, weight: FontWeight.w700, color: AppColors.error).copyWith(height: 20 / 14))),
                          ])
                        else
                          Text('${_label(d)} · ${untilText(d.at!, long: true)}',
                              style: appText(14, weight: FontWeight.w600, color: AppColors.label).copyWith(height: 20 / 14)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('RINGKASAN', style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
                    ),
                  ),
                  _Line('Penerima', 'Semua pengguna', sub: '${groupedDigits(count)} akun'),
                  _Line('Kategori', _catLabel(d.category)),
                  _Line('Judul', d.title.trim()),
                  _Line('Waktu', d.sendNow ? 'Sekarang' : _label(d)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SecondaryButton(label: 'Ubah pesan', onPressed: () => context.pop()),
                  ),
                ]),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
            child: PrimaryButton(
              label: d.editing != null ? 'Simpan perubahan' : (d.sendNow ? 'Kirim siaran' : 'Jadwalkan siaran'),
              busy: d.running,
              onPressed: err == null ? () => _confirm(d) : null,
            ),
          ),
        ]),
      ),
    );
  }
}

String _catLabel(String id) => Broadcast(id: 0, category: id, title: '', summary: '', hasBody: false, shownAt: DateTime(0)).categoryLabel;

class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.title, required this.text, required this.onTap});

  final bool on;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 22, color: AppColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: appText(16, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(text, style: appText(14, color: AppColors.label).copyWith(height: 20 / 14)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.child, required this.error});

  final String label;
  final Widget child;
  final bool error;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: appText(13, weight: FontWeight.w700, color: AppColors.label)),
        const SizedBox(height: 6),
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: error ? AppColors.error : AppColors.fieldBorder, width: error ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ]);
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(label, style: appText(14, weight: FontWeight.w600, color: AppColors.muted))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: appText(15, weight: FontWeight.w700)),
              if (sub != null) Text(sub!, style: appText(14, color: AppColors.label)),
            ]),
          ),
        ]),
      );
}
