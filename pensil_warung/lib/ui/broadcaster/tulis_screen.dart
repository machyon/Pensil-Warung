import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/category_icon.dart';
import 'broadcast_draft.dart';
import 'broadcast_widgets.dart';
import 'siaran_view_model.dart';

const _categories = [('update', 'Pembaruan'), ('berita', 'Berita'), ('info', 'Info'), ('tips', 'Tips')];

/// [18] Tulis, step 1: category, title, summary and the optional full text.
class TulisScreen extends StatelessWidget {
  const TulisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<BroadcastDraft>();
    final count = context.select<SiaranViewModel, int?>((v) => v.loaded ? v.recipientCount : null);
    final editing = draft.editing != null;
    final ready = draft.ready;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (editing)
          SiaranHeader(
            title: 'Ubah siaran',
            subtitle: 'Langkah 1 dari 2 · Ubah pesan',
            onBack: () {
              draft.reset();
              context.go('/siaran');
            },
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Siaran baru', style: appText(30, weight: FontWeight.w800, letterSpacing: -0.5)),
              Text('Langkah 1 dari 2 · Tulis pesan', style: appText(14, color: AppColors.muted)),
            ]),
          ),
        Expanded(
          child: _Form(
            key: ValueKey(draft.revision),
            draft: draft,
            recipients: count == null ? '…' : '${groupedDigits(count)} akun',
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!ready) ...[
              Text('Isi judul dan ringkasan dulu',
                  textAlign: TextAlign.center, style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
              const SizedBox(height: 8),
            ],
            PrimaryButton(label: 'Lanjut Jadwalkan', onPressed: ready ? () => context.push('/tulis/kirim') : null),
          ]),
        ),
      ]),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({super.key, required this.draft, required this.recipients});

  final BroadcastDraft draft;
  final String recipients;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final _title = TextEditingController(text: widget.draft.title);
  late final _summary = TextEditingController(text: widget.draft.summary);
  late final _body = TextEditingController(text: widget.draft.body);

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.groups_outlined, size: 22, color: AppColors.label),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dikirim ke', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                Text('Semua pengguna · ${widget.recipients}', style: appText(16, weight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Kategori', style: appText(15, weight: FontWeight.w700)),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3.4,
          children: [for (final (id, label) in _categories) _CategoryButton(id, label, on: d.category == id, onTap: () => d.update(category: id))],
        ),
        const SizedBox(height: 20),
        _Field(label: 'Judul', controller: _title, max: 60, lines: 1, onChanged: (v) => d.update(title: v)),
        const SizedBox(height: 20),
        _Field(
          label: 'Ringkasan',
          controller: _summary,
          max: 120,
          lines: 3,
          help: 'Tampil di daftar notifikasi, di bawah judul.',
          onChanged: (v) => d.update(summary: v),
        ),
        const SizedBox(height: 20),
        _Field(
          label: 'Isi lengkap',
          optional: true,
          controller: _body,
          lines: 5,
          help: 'Tampil saat pengguna membuka notifikasinya. Kosongkan jika ringkasan sudah cukup.',
          onChanged: (v) => d.update(body: v),
        ),
      ],
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton(this.id, this.label, {required this.on, required this.onTap});

  final String id;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? AppColors.accent : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: on ? AppColors.accent : AppColors.fieldBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(categoryIcon(id), size: 20, color: on ? AppColors.onAccent : AppColors.ink),
              const SizedBox(width: 8),
              Text(label, style: appText(15, weight: on ? FontWeight.w800 : FontWeight.w600, color: on ? AppColors.onAccent : AppColors.ink)),
            ]),
          ),
        ),
      );
}

/// Label with a live `n/max` counter, a 1 or more line field and a helper.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.lines,
    required this.onChanged,
    this.max,
    this.help,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final int lines;
  final int? max;
  final String? help;
  final bool optional;
  final ValueChanged<String> onChanged;

  OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(label, style: appText(15, weight: FontWeight.w700)),
          if (optional) Text(' (opsional)', style: appText(15, color: AppColors.muted)),
          const Spacer(),
          if (max != null)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, _) => Text('${v.text.length}/$max', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        maxLength: max,
        minLines: lines,
        maxLines: lines,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.sentences,
        style: appText(16, weight: lines == 1 ? FontWeight.w600 : FontWeight.w500),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: lines == 1 ? 15 : 14),
          enabledBorder: _border(AppColors.fieldBorder),
          focusedBorder: _border(AppColors.ink, 2),
        ),
      ),
      if (help != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(help!, style: appText(13, color: AppColors.muted).copyWith(height: 18 / 13)),
        ),
    ]);
  }
}
