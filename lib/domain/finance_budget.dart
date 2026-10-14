import 'package:krezium/data/models/finance_models.dart';

/// Gasto real de [categoryId] en el período de [transacciones] — suma tanto
/// las transacciones cuyo `categoryId` es exactamente [categoryId] (un
/// presupuesto asignado directo a esa categoría) como las de cualquier
/// subcategoría cuyo padre, según [parentPorCategoria], sea [categoryId].
/// Sin este roll-up, un presupuesto creado sobre una categoría padre (el
/// único tipo de categoría que ofrece el selector de presupuestos) nunca
/// vería gasto real, porque las transacciones casi siempre se registran
/// contra la subcategoría específica, no contra el padre.
/// Ingresos y transferencias nunca cuentan, aunque compartan `categoryId`.
double gastoCategoriaPeriodo({
  required String categoryId,
  required List<FinanceTransaction> transacciones,
  required Map<String, String?> parentPorCategoria,
}) {
  var total = 0.0;
  for (final t in transacciones) {
    if (t.tipo != 'gasto') continue;
    final esDirecta = t.categoryId == categoryId;
    final esSubcategoria = parentPorCategoria[t.categoryId] == categoryId;
    if (esDirecta || esSubcategoria) total += t.monto;
  }
  return total;
}

/// Proporción gasto/límite, sin acotar a 1.0 — un presupuesto puede
/// excederse (el usuario sigue registrando gastos igual) y la UI decide
/// cómo mostrar ese exceso.
double progresoPresupuesto({required double gasto, required double limite}) {
  if (limite <= 0) return 0;
  return gasto / limite;
}

double saldoPresupuesto({required double limite, required double gasto}) => limite - gasto;

enum EstadoPresupuesto { normal, cercano, agotado }

/// Umbrales: por debajo de 80% es normal, de 80% a 100% (sin llegar) está
/// cerca del límite, y de 100% en adelante (incluye excedido) está agotado.
EstadoPresupuesto estadoPresupuesto(double progreso) {
  if (progreso >= 1.0) return EstadoPresupuesto.agotado;
  if (progreso >= 0.8) return EstadoPresupuesto.cercano;
  return EstadoPresupuesto.normal;
}
