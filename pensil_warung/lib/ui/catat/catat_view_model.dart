import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../catat/linter.dart' as catat;
import '../../catat/result.dart';
import '../../catat/summary.dart';
import '../../data/api_exception.dart';
import '../../data/repositories/catat_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction.dart';
import 'catat_editor.dart';

enum SaveOutcome { saved, linesInvalid, offline, failed }

/// The "Baru saja disimpan" card ([14]).
class SavedCard {
  const SavedCard({required this.tx, required this.rawText, required this.undoable, this.today});
  final SavedTransaction tx;
  final String rawText;
  final bool undoable; // sales-only batches
  final DaySummary? today;
}

/// State of the Catat tab. App-wide, so the text survives tab switches.
class CatatViewModel extends ChangeNotifier {
  CatatViewModel(this._repo, this._products, this._tx, {this._debounce = const Duration(milliseconds: 150)})
      {
    controller.addListener(_onText);
    _products.addListener(_relint);
    _tx.addListener(_refreshSaved);
    _relint();
  }

  final CatatRepository _repo;
  final ProductRepository _products;
  final TransactionRepository _tx;
  final Duration _debounce;
  final controller = CatatController();
  final scroll = ScrollController();

  Timer? _timer;
  String _lastText = '';
  LintResult _lint = LintResult.fromLines(const []);
  LintResult? _serverLint;
  bool commandMode = false;
  bool running = false;
  String? error;
  SavedCard? saved;
  int failedPhotos = 0;

  /// Photos picked for new products, by lower-cased name; uploaded after the save.
  final photos = <String, Uint8List>{};

  String? _uuid, _uuidText;

  LintResult get lint => _serverLint ?? _lint;
  ConfirmSummary get summary => ConfirmSummary(lint);
  Set<int> get errorLines => {for (final l in lint.lines) if (l.status == LineStatus.error) l.lineNo};
  bool get noProducts => _products.loaded && _products.items.isEmpty;
  bool get boxEnabled => !noProducts || commandMode;
  bool get hasText => controller.text.trim().isNotEmpty;

  /// Non-blank lines, for the Keluar sheet (branch 10).
  int get unsavedLines => controller.text.split('\n').where((l) => l.trim().isNotEmpty).length;

  void _onText() {
    if (controller.text == _lastText) return;
    _lastText = controller.text;
    _serverLint = null;
    if (hasText) saved = null;
    _timer?.cancel();
    _timer = Timer(_debounce, _relint);
    notifyListeners();
  }

  void _relint() {
    _lint = catat.lint(controller.text, _products.items);
    controller.errorLines = errorLines;
    notifyListeners();
  }

  void enableCommandMode() {
    commandMode = true;
    notifyListeners();
  }

  void applyFix(Fix f) {
    final t = f.apply(controller.text);
    controller.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: f.cursorAt?.call(t) ?? t.length),
    );
    _timer?.cancel();
    _relint();
  }

  void setText(String t) {
    controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _timer?.cancel();
    _relint();
  }

  void setPhoto(String name, Uint8List? bytes) {
    final k = name.toLowerCase();
    bytes == null ? photos.remove(k) : photos[k] = bytes;
    notifyListeners();
  }

  /// One Simpan, or the retry of one (same text keeps the same `client_uuid`).
  Future<SaveOutcome> save() async {
    if (running) return SaveOutcome.failed;
    _timer?.cancel();
    _relint();
    final text = controller.text;
    final r = lint;
    if (!r.canSave) return SaveOutcome.failed;
    if (_uuid == null || _uuidText != text) {
      _uuid = const Uuid().v7();
      _uuidText = text;
    }
    running = true;
    error = null;
    notifyListeners();
    try {
      final res = await _repo.save(clientUuid: _uuid!, rawText: text, ops: r.ops);
      _uuid = null;
      _tx.markChanged();
      final tx = res.transaction;
      final creates = {for (final l in r.lines) if (l.op?.op == 'create_product') l.productName!.toLowerCase()};
      final toUpload = {
        for (final p in res.changed)
          if (creates.contains(p.name.toLowerCase()) && photos.containsKey(p.name.toLowerCase())) p.id: photos[p.name.toLowerCase()]!,
      };
      photos.clear();
      setText('');
      _serverLint = null;
      saved = tx == null
          ? null
          : SavedCard(tx: tx, rawText: text, undoable: r.ops.every((o) => o.op == 'sale'));
      running = false;
      notifyListeners();
      _loadToday();
      failedPhotos = 0;
      for (final e in toUpload.entries) {
        if (!await _products.uploadPending(e.key, e.value)) failedPhotos++;
      }
      notifyListeners();
      return SaveOutcome.saved;
    } on ApiException catch (e) {
      running = false;
      if (e.code == 'lines_invalid') {
        final lines = (e.details?['lines'] as List? ?? const []).cast<Map<String, dynamic>>();
        _serverLint = catat.mapServerLines(_lint, lines);
        controller.errorLines = errorLines;
        notifyListeners();
        return SaveOutcome.linesInvalid;
      }
      error = e.message;
      notifyListeners();
      return SaveOutcome.failed;
    } on NetworkException {
      running = false;
      notifyListeners();
      return SaveOutcome.offline;
    }
  }

  Future<void> _loadToday() async {
    final s = saved;
    if (s == null) return;
    try {
      final d = await _tx.today();
      if (identical(saved, s)) {
        saved = SavedCard(tx: s.tx, rawText: s.rawText, undoable: s.undoable, today: d);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// A void or revise done elsewhere (Detail) changed the sale the card shows: follow it.
  Future<void> _refreshSaved() async {
    final s = saved;
    if (s == null || running) return; // a save of our own also calls markChanged
    try {
      var t = await _tx.get(s.tx.id);
      while (t.replacedById != null) {
        t = await _tx.get(t.replacedById!);
      }
      if (saved?.tx.id != s.tx.id) return; // _loadToday may have swapped the card meanwhile
      saved = t.voided ? null : SavedCard(tx: SavedTransaction.fromTransaction(t), rawText: s.rawText, undoable: s.undoable);
      notifyListeners();
      if (saved != null) _loadToday();
    } catch (_) {} // keep the card as it is
  }

  /// Voids the saved sale and puts its text back in the box. Returns an error message, or null.
  Future<String?> undo() async {
    final s = saved;
    if (s == null || !s.undoable) return null;
    try {
      await _tx.voidTransaction(s.tx.id);
    } catch (e) {
      return messageOf(e);
    }
    setText(s.rawText);
    saved = null;
    notifyListeners();
    return null;
  }

  void clear() {
    setText('');
    saved = null;
    photos.clear();
    commandMode = false;
    _uuid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _products.removeListener(_relint);
    _tx.removeListener(_refreshSaved);
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }
}
