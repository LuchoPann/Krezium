import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/finance_models.dart';

/// Efecto con signo que [t] tiene sobre el saldo del registro [libroId].
/// Una transferencia resta en su registro de origen (accountId) y suma en
/// su registro de destino (transferToAccountId) — nunca en ambos a la vez
/// para el mismo [libroId], y nunca se cuenta como ingreso/gasto.
///
/// 'meta_aporte'/'meta_retiro': la plata SÍ sale/entra del saldo real del
/// registro (accountId) — a diferencia de una reserva "virtual" de antes,
/// un aporte a una meta mueve dinero de verdad, igual que una transferencia
/// a otro registro, solo que el destino es una meta en vez de otra cuenta.
/// Nunca cuenta como ingreso/gasto (ver calcularIngresosGastos).
double signedEffectForLibro(FinanceTransaction t, String libroId) {
  if (t.tipo == 'transferencia') {
    if (t.accountId == t.transferToAccountId) return 0;
    if (t.accountId == libroId) return -t.monto;
    if (t.transferToAccountId == libroId) return t.monto;
    return 0;
  }
  if (t.tipo == 'meta_aporte') {
    return t.accountId == libroId ? -t.monto : 0;
  }
  if (t.tipo == 'meta_retiro') {
    return t.accountId == libroId ? t.monto : 0;
  }
  if (t.accountId != libroId) return 0;
  if (t.tipo == 'ingreso') return t.monto;
  if (t.tipo == 'gasto') return -t.monto;
  return 0;
}

/// [txsInvolucradas] debe incluir tanto las transacciones cuyo accountId es
/// [libroId] como aquellas transferencias cuyo transferToAccountId es
/// [libroId] (ver AppDatabase.getFinanceTransactionsInvolvingLibro).
double calcularSaldo({
  required double saldoInicial,
  required List<FinanceTransaction> txsInvolucradas,
  required String libroId,
}) {
  var saldo = saldoInicial;
  for (final t in txsInvolucradas) {
    saldo += signedEffectForLibro(t, libroId);
  }
  return saldo;
}

/// Ingresos y gastos reales de [libroId] — una transferencia nunca entra
/// aquí, sea cual sea su dirección.
({double ingresos, double gastos}) calcularIngresosGastos(
  List<FinanceTransaction> txs,
  String libroId,
) {
  var ingresos = 0.0;
  var gastos = 0.0;
  for (final t in txs) {
    if (t.accountId != libroId) continue;
    if (t.tipo == 'ingreso') ingresos += t.monto;
    if (t.tipo == 'gasto') gastos += t.monto;
  }
  return (ingresos: ingresos, gastos: gastos);
}

/// Una transferencia es válida solo si tiene origen y destino distintos y
/// ambos definidos. No valida existencia en DB — eso lo hace quien la llama
/// con los libros ya cargados en memoria (ver nueva_transaccion_sheet).
bool esTransferenciaValida({required String? origenId, required String? destinoId}) {
  if (origenId == null || destinoId == null) return false;
  return origenId != destinoId;
}

/// Observación breve sobre el periodo, solo cuando hay datos que la
/// respalden. Devuelve null si no hubo ningún movimiento (ingresos==0 y
/// gastos==0) — nunca se inventa una conclusión sin evidencia.
String? observacionPeriodo({required double ingresos, required double gastos}) {
  if (ingresos == 0 && gastos == 0) return null;
  if (ingresos == gastos) return 'Tus ingresos y gastos están equilibrados este mes.';
  if (gastos == 0) return 'Aún no registras gastos este mes.';
  if (ingresos == 0) return 'Aún no registras ingresos este mes.';
  if (ingresos > gastos) {
    final pct = (((ingresos - gastos) / gastos) * 100).round();
    return 'Tus ingresos superan tus gastos en $pct% este mes.';
  }
  final pct = (((gastos - ingresos) / ingresos) * 100).round();
  return 'Tus gastos superan tus ingresos en $pct% este mes.';
}

/// Cancelar una meta libera su dinero (deja de descontar del disponible);
/// finalizarla no — sigue reservado hasta que el usuario lo retire
/// explícitamente (ver [FinanceReservations] en tables_finance.dart).
double totalReservado(List<FinanceReservationRow> reservas) => reservas
    .where((r) => r.estado != 'cancelada')
    .fold(0.0, (sum, r) => sum + r.monto);

/// Suma de reservas con modalidad 'virtual' (sin cuenta propia) — se resta
/// del disponible GLOBAL (todos los registros), nunca del de un registro
/// puntual. Las reservas 'vinculada' nunca entran acá: ya se descuentan
/// vía [totalReservado] sobre la lista de reservas de su propia cuenta.
double totalReservadoVirtual(List<FinanceReservationRow> reservas) => reservas
    .where((r) => r.modalidad == 'virtual' && r.estado != 'cancelada')
    .fold(0.0, (sum, r) => sum + r.monto);

/// % de los ingresos que no se gastó: (ingresos - gastos) / ingresos. Sin
/// clamp — puede ser negativa (se gastó más de lo que entró, información
/// real) o superar 1.0 no tiene sentido aquí porque gastos nunca es
/// negativo, pero sí puede ser 0 (100% ahorrado). Devuelve null sin
/// ingresos registrados: un 0% ahí sería engañoso, no es que no se
/// ahorró nada, es que no hay base sobre la cual calcular una tasa.
double? tasaAhorro({required double ingresos, required double gastos}) {
  if (ingresos <= 0) return null;
  return (ingresos - gastos) / ingresos;
}

/// El disponible estimado nunca oculta una inconsistencia: si las reservas
/// superan el saldo, [disponibleEstimado] queda negativo y
/// [reservasExcedenSaldo] en true — la UI decide cómo señalarlo, este
/// cálculo no lo oculta ni lo clampa a 0.
({double disponibleEstimado, bool reservasExcedenSaldo}) calcularDisponibleEstimado({
  required double saldo,
  required double reservado,
}) {
  final disponible = saldo - reservado;
  return (disponibleEstimado: disponible, reservasExcedenSaldo: reservado > 0 && reservado > saldo);
}

/// Compara [actual] contra [anterior] — devuelve null cuando el periodo
/// anterior no tiene datos (==0), porque calcular un % de variación contra
/// cero produce una cifra sin sentido (infinita o engañosa), no una
/// comparación real. La UI decide cómo presentar el delta; esto solo
/// calcula si hay base comparable y cuál es la variación.
({double actual, double anterior, double deltaPct})? comparacionPeriodoAnterior({
  required double actual,
  required double anterior,
}) {
  if (anterior <= 0) return null;
  return (actual: actual, anterior: anterior, deltaPct: (actual - anterior) / anterior * 100);
}
