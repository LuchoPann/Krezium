import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/finance_models.dart';

/// Efecto con signo que [t] tiene sobre el saldo del registro [libroId].
/// Una transferencia resta en su registro de origen (accountId) y suma en
/// su registro de destino (transferToAccountId) — nunca en ambos a la vez
/// para el mismo [libroId], y nunca se cuenta como ingreso/gasto.
double signedEffectForLibro(FinanceTransaction t, String libroId) {
  if (t.tipo == 'transferencia') {
    if (t.accountId == t.transferToAccountId) return 0;
    if (t.accountId == libroId) return -t.monto;
    if (t.transferToAccountId == libroId) return t.monto;
    return 0;
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

double totalReservado(List<FinanceReservationRow> reservas) =>
    reservas.fold(0.0, (sum, r) => sum + r.monto);

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
