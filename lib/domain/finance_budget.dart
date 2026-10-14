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

/// Sugerencia de límite para [categoryId]: mediana del gasto mensual de
/// los últimos 3 meses de calendario completos (anteriores al mes de
/// [hoy]), contando roll-up a subcategorías vía [parentPorCategoria].
/// Devuelve null si menos de 2 de esos 3 meses tienen gasto > 0 — no hay
/// base suficiente para sugerir sin inventar un número.
({double sugerido, List<({int year, int month, double monto})> meses})?
    sugerenciaPresupuesto({
  required String categoryId,
  required List<FinanceTransaction> transacciones,
  required Map<String, String?> parentPorCategoria,
  required DateTime hoy,
}) {
  final meses = <({int year, int month, double monto})>[];
  for (int i = 3; i >= 1; i--) {
    final d = DateTime(hoy.year, hoy.month - i);
    final prefix = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final txsDelMes =
        transacciones.where((t) => t.fecha.startsWith(prefix)).toList();
    final monto = gastoCategoriaPeriodo(
      categoryId: categoryId,
      transacciones: txsDelMes,
      parentPorCategoria: parentPorCategoria,
    );
    meses.add((year: d.year, month: d.month, monto: monto));
  }
  final conGasto = meses.where((m) => m.monto > 0).length;
  if (conGasto < 2) return null;
  final montosOrdenados = meses.map((m) => m.monto).toList()..sort();
  final mediana = montosOrdenados[1]; // de 3 elementos ordenados, el del medio
  return (sugerido: mediana, meses: meses);
}

/// true si el presupuesto va "más rápido de lo esperado": el % del
/// límite ya consumido ([progreso]) supera el % del periodo ya
/// transcurrido por más de [margen] puntos porcentuales. No aplica si el
/// presupuesto ya está en estado agotado — esa alerta ya es suficiente,
/// sumar esta sería ruido redundante.
bool vaRapido({
  required double progreso,
  required DateTime inicioPeriodo,
  required DateTime finPeriodo,
  required DateTime hoy,
  double margen = 0.15,
}) {
  if (progreso >= 1.0) return false;
  final duracionTotal = finPeriodo.difference(inicioPeriodo).inMinutes;
  if (duracionTotal <= 0) return false;
  final transcurrido = hoy.difference(inicioPeriodo).inMinutes;
  final fraccion = (transcurrido / duracionTotal).clamp(0.0, 1.0);
  return progreso - fraccion > margen;
}
