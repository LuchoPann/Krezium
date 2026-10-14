import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// Mismo NumberFormat (es_CO, sin decimales) que usa `formatCOP` en todo el
// proyecto para mostrar montos ya guardados.
final _milesFormat = NumberFormat.decimalPattern('es_CO');

/// Agrupa un entero en miles con '.' — "45000" → "45.000" — para que lo que
/// el usuario digita se vea igual a como luego aparece en el histórico.
String agruparMiles(int value) => _milesFormat.format(value);

/// Formatter: separa miles con "." mientras se digita (estilo peso
/// colombiano), sin decimales ni símbolo propio — el símbolo "$" se maneja
/// aparte (prefixText o antepuesto al texto según el diseño del campo).
class MontoInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final soloDigitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = agruparMiles(int.parse(soloDigitos));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
