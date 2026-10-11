import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/utils/currency_input_formatter.dart';

TextEditingValue _typeDigit(String oldText, String typedDigit) {
  // Simula escribir un dígito al final: el campo llega con viejo texto +
  // dígito, cursor al final — el caso real de un TextFormField.
  final newText = '$oldText$typedDigit';
  return const CurrencyInputFormatter().formatEditUpdate(
    TextEditingValue(text: oldText, selection: TextSelection.collapsed(offset: oldText.length)),
    TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length)),
  );
}

void main() {
  test('typing a digit when the field starts at "0" replaces the 0 instead '
      'of stacking ("0" + "5" → "5", not "05")', () {
    // Regression: a field initialized with "0" (default balance/fee) would
    // get stuck as "05", "052", etc. because formatEditUpdate never
    // stripped the leading zero — this made the keyboard appear to "lock up"
    // since the displayed value never matched what the user typed.
    final result = _typeDigit('0', '5');
    expect(result.text, '5');
  });

  test('typing a digit on an empty field behaves normally', () {
    final result = _typeDigit('', '7');
    expect(result.text, '7');
  });

  test('typing another 0 on a field that is already "0" collapses to empty, '
      'not "00"', () {
    final result = _typeDigit('0', '0');
    expect(result.text, '');
  });

  test('normal multi-digit typing still works and keeps thousands '
      'separators', () {
    final result = const CurrencyInputFormatter().formatEditUpdate(
      const TextEditingValue(text: '1.500', selection: TextSelection.collapsed(offset: 5)),
      const TextEditingValue(text: '1.5002', selection: TextSelection.collapsed(offset: 6)),
    );
    expect(result.text, '15.002');
  });
}
