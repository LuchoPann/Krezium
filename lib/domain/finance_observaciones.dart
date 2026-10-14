import 'package:krezium/domain/finance_ledger.dart';

/// Capa determinista de observaciones (Fase 07): reglas locales sobre datos
/// reales, nunca una conclusión inventada. Cada función devuelve una lista
/// vacía cuando no hay evidencia suficiente — nunca "rellena" con algo para
/// mostrar. Los campos crudos (valorActual/valorAnterior/progreso/deltaPct)
/// quedan sin formatear a propósito: la UI compone el texto final y decide
/// ícono/color/acción según [tipo], siguiendo el mismo patrón que
/// [comparacionPeriodoAnterior].
enum TipoObservacion {
  aumentoCategoria,
  presupuestoCercano,
  metaFueraDeRitmo,
}

class Observacion {
  final TipoObservacion tipo;
  final String refId;
  final String nombre;
  final double? valorActual;
  final double? valorAnterior;
  final double? deltaPct;
  final double? progreso;

  const Observacion({
    required this.tipo,
    required this.refId,
    required this.nombre,
    this.valorActual,
    this.valorAnterior,
    this.deltaPct,
    this.progreso,
  });
}

/// Categorías cuyo gasto subió de forma significativa este mes frente al
/// anterior — exige tanto un umbral porcentual ([umbralPct]) como uno de
/// monto absoluto ([umbralMinimo]): un aumento de 200% sobre $1.000 no es
/// una señal útil, solo ruido. Ordenadas de mayor a menor aumento.
List<Observacion> observacionesAumentoCategoria({
  required Map<String, double> gastoActualPorCategoria,
  required Map<String, double> gastoAnteriorPorCategoria,
  required Map<String, String> nombrePorCategoria,
  double umbralPct = 30,
  double umbralMinimo = 50000,
}) {
  final out = <Observacion>[];
  for (final entry in gastoActualPorCategoria.entries) {
    final anterior = gastoAnteriorPorCategoria[entry.key] ?? 0;
    final comp = comparacionPeriodoAnterior(actual: entry.value, anterior: anterior);
    if (comp == null) continue;
    if (comp.deltaPct < umbralPct) continue;
    if ((comp.actual - comp.anterior) < umbralMinimo) continue;
    out.add(Observacion(
      tipo: TipoObservacion.aumentoCategoria,
      refId: entry.key,
      nombre: nombrePorCategoria[entry.key] ?? entry.key,
      valorActual: comp.actual,
      valorAnterior: comp.anterior,
      deltaPct: comp.deltaPct,
    ));
  }
  out.sort((a, b) => b.deltaPct!.compareTo(a.deltaPct!));
  return out;
}

/// Presupuestos al 80% o más de su límite — mismo umbral que
/// `estadoPresupuesto` en finance_budget.dart (cercano/agotado). Ordenados
/// de más urgente (mayor progreso) a menos.
List<Observacion> observacionesPresupuestoCercano(
  List<({String categoryId, String nombre, double progreso})> presupuestos,
) {
  final out = presupuestos
      .where((p) => p.progreso >= 0.8)
      .map((p) => Observacion(
            tipo: TipoObservacion.presupuestoCercano,
            refId: p.categoryId,
            nombre: p.nombre,
            progreso: p.progreso,
          ))
      .toList()
    ..sort((a, b) => b.progreso!.compareTo(a.progreso!));
  return out;
}

/// Metas activas cuyo ritmo de aportes actual se queda notablemente atrás
/// del ritmo que haría falta para llegar a la fecha límite — compara el
/// progreso real (aportado/objetivo) contra el progreso esperado según el
/// tiempo ya transcurrido desde que se creó la meta. Solo activa (no
/// pausada/finalizada/cancelada, no sin fecha límite, no ya cumplida).
List<Observacion> observacionesMetaFueraDeRitmo(
  List<({
    String id,
    String nombre,
    double aportado,
    double objetivo,
    DateTime creadaEn,
    DateTime? fechaLimite,
    String estado,
  })> metas, {
  required DateTime hoy,
  double umbralRezago = 0.15,
}) {
  final out = <Observacion>[];
  for (final m in metas) {
    if (m.estado != 'activa') continue;
    if (m.fechaLimite == null) continue;
    if (m.objetivo <= 0) continue;
    final progresoReal = m.aportado / m.objetivo;
    if (progresoReal >= 1) continue; // ya cumplida

    final totalDias = m.fechaLimite!.difference(m.creadaEn).inDays;
    if (totalDias <= 0) continue;
    final diasTranscurridos = hoy.difference(m.creadaEn).inDays;
    final progresoEsperado = (diasTranscurridos / totalDias).clamp(0.0, 1.0);

    if (progresoEsperado - progresoReal < umbralRezago) continue;

    out.add(Observacion(
      tipo: TipoObservacion.metaFueraDeRitmo,
      refId: m.id,
      nombre: m.nombre,
      valorActual: progresoReal,
      valorAnterior: progresoEsperado,
    ));
  }
  return out;
}
