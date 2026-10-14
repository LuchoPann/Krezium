import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/finance_categories_catalog.dart';

void main() {
  // Conteo actualizado tras ampliar el catálogo a (casi) toda la
  // amplitud de subcategorías propuesta por el usuario, sobre todo en
  // gastos — manteniendo los 18 padres ya consolidados (no se refragmentó
  // en padres, solo se ampliaron las subcategorías de cada uno).
  test('catálogo tiene exactamente 125 categorías', () {
    expect(catalogoFinanzas.length, 125);
  });

  test('ids únicos en catálogo', () {
    final ids = catalogoFinanzas.map((c) => c.id).toSet();
    expect(ids.length, 125);
  });

  test('12 ingresos y 113 gastos', () {
    final ingresos = catalogoFinanzas.where((c) => c.tipo == 'ingreso').length;
    final gastos = catalogoFinanzas.where((c) => c.tipo == 'gasto').length;
    expect(ingresos, 12);
    expect(gastos, 113);
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
