import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/finance_categories_catalog.dart';

void main() {
  // Conteo actualizado tras expandir Transporte/Salud/Vivienda/Educación/
  // Alimentación con subcategorías reales (antes algunos padres tenían un
  // único hijo con el mismo nombre que el padre — ej. "Transporte" dentro
  // de "Transporte" — sin distinguir medios de transporte reales).
  test('catálogo tiene exactamente 43 categorías', () {
    expect(catalogoFinanzas.length, 43);
  });

  test('ids únicos en catálogo', () {
    final ids = catalogoFinanzas.map((c) => c.id).toSet();
    expect(ids.length, 43);
  });

  test('8 ingresos y 35 gastos', () {
    final ingresos = catalogoFinanzas.where((c) => c.tipo == 'ingreso').length;
    final gastos = catalogoFinanzas.where((c) => c.tipo == 'gasto').length;
    expect(ingresos, 8);
    expect(gastos, 35);
  });

  test('cada subcategoría apunta a un padre que existe', () {
    final padreIds = catalogoCategoriaPadres.map((c) => c.id).toSet();
    for (final c in catalogoFinanzas) {
      expect(padreIds.contains(c.parentId), isTrue,
          reason: '${c.id} apunta a un parentId inexistente: ${c.parentId}');
    }
  });

  test('ninguna subcategoría repite el nombre de su categoría padre '
      '(serían un duplicado redundante, ej. Transporte > Transporte)', () {
    final padresPorId = {for (final p in catalogoCategoriaPadres) p.id: p};
    for (final c in catalogoFinanzas) {
      final padre = padresPorId[c.parentId];
      if (padre == null) continue;
      expect(c.nombre, isNot(equals(padre.nombre)),
          reason: '${c.id} repite el nombre de su padre (${padre.nombre})');
    }
  });
}
