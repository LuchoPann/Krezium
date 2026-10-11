import '../data/models/card_movement.dart';
import '../data/models/card_statement.dart';
import '../data/models/credit.dart';
import 'card_calculator.dart' show getCardCycleDates, dueDateForCutoff;
import 'date_utils.dart';

double _round2(double v) => (v * 100).round() / 100;

/// El total a pagar de [statement] — SIEMPRE calculado desde los
/// movimientos ligados a él, nunca un valor congelado. Un extracto abierto
/// refleja la realidad en vivo; uno cerrado también, por si se corrige un
/// movimiento después (borrar/editar) — no hay un número "guardado" que
/// pueda quedar desincronizado.
double computeStatementTotal(
    CardStatement statement, List<CardMovement> movements) {
  var total = statement.openingBalance;
  for (final m in movements) {
    if (m.statementId != statement.id) continue;
    total += m.type == CardMovementType.payment ? -m.amount.abs() : m.amount.abs();
  }
  return _round2(total);
}

/// Garantiza que [credit] tenga un extracto abierto, creándolo si hace
/// falta (tarjeta recién creada, o justo después de cerrar el anterior).
/// El extracto abierto representa el ciclo que se está acumulando AHORA —
/// cierra en la próxima fecha de corte (`getCardCycleDates(...).nextCutoff`).
CardStatement ensureOpenStatement(CardCredit credit, [DateTime? refDate]) {
  final existing = credit.statements
      .where((s) => s.status == CardStatementStatus.open)
      .toList();
  if (existing.isNotEmpty) return existing.first;

  final dates = getCardCycleDates(credit, refDate);
  final cutoffDate = toDateStr(dates.nextCutoff);
  final statement = CardStatement(
    id: '${credit.id}-${DateTime.now().microsecondsSinceEpoch}',
    creditId: credit.id,
    cutoffDate: cutoffDate,
    dueDate: toDateStr(dueDateForCutoff(credit, dates.nextCutoff)),
    closingBalance: 0,
    openingBalance: 0,
    status: CardStatementStatus.open,
    createdAt: toDateStr(refDate ?? DateTime.now()),
  );
  credit.statements.add(statement);
  return statement;
}
