import 'package:flutter/services.dart';

import 'format.dart';

/// Digits only, shown with dots as you type (`15000` -> `15.000`).
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    final digits = value.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = groupedDigits(int.parse(digits.length > 12 ? digits.substring(0, 12) : digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// `15.000` -> 15000, empty -> null.
int? parseRupiah(String text) => int.tryParse(text.replaceAll('.', ''));
