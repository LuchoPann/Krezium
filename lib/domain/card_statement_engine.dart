import 'dart:math' as math;

import '../data/models/card_movement.dart';
import '../data/models/card_statement.dart';
import '../data/models/credit.dart';
import '../data/models/installment_purchase.dart';
import 'card_calculator.dart'
    show cutoffDateForMonth, dueDateForCutoff, cycleKeyFor;
import 'date_utils.dart';
import 'interest_rate.dart';

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
/// cierra en el corte que `cycleKeyFor` asigna a hoy.
CardStatement ensureOpenStatement(CardCredit credit, [DateTime? refDate]) {
  final existing = credit.statements
      .where((s) => s.status == CardStatementStatus.open)
      .toList();
  if (existing.isNotEmpty) return existing.first;

  final today = refDate ?? DateTime.now();
  // Usa cycleKeyFor — el mismo criterio que asigna un cargo normal a su
  // extracto — para que el PRIMER extracto de una tarjeta nueva sea
  // consistente con una compra a plazos hecha el mismo día (Task 7's
  // regression test): ambos deben coincidir exactamente en qué ciclo
  // "hoy" pertenece, incluyendo el caso límite día == día de corte.
  final cutoff = parseDateStr(cycleKeyFor(toDateStr(today), credit.cutoffDay));
  final statement = CardStatement(
    id: '${credit.id}-${DateTime.now().microsecondsSinceEpoch}',
    creditId: credit.id,
    cutoffDate: toDateStr(cutoff),
    dueDate: toDateStr(dueDateForCutoff(credit, cutoff)),
    closingBalance: 0,
    openingBalance: 0,
    status: CardStatementStatus.open,
    createdAt: toDateStr(today),
  );
  credit.statements.add(statement);
  return statement;
}

/// Cierra el extracto abierto de [credit] cada vez que su fecha de corte ya
/// pasó por completo (el día de corte pertenece al ciclo hasta las 23:59;
/// recién al día siguiente se cierra), aplicando interés/cuota de manejo,
/// abriendo el siguiente extracto, y facturando automáticamente la próxima
/// cuota pendiente de cada InstallmentPurchase en el extracto nuevo.
/// Idempotente — seguro de llamar en cada arranque de la app. Capado a 36
/// iteraciones como red de seguridad.
void closeCurrentCycleIfDue(CardCredit credit, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);
  final cutoffDay = math.min(math.max(credit.cutoffDay, 1), 31);

  var open = ensureOpenStatement(credit, todayMidnight);
  var safety = 0;
  while (safety < 36) {
    final cutoff = parseDateStr(open.cutoffDate);
    if (!cutoff.isBefore(todayMidnight)) break;

    final dailyRate = dailyRateFrom(credit.interestRate, credit.interestRateType);
    final balanceBeforeInterest = computeStatementTotal(open, credit.movements);
    final openedAt = _openedAtFor(credit, open);
    final daysInCycle = cutoff.difference(openedAt).inDays;
    if (balanceBeforeInterest > 0 && dailyRate > 0) {
      final interestAmt = _round2(balanceBeforeInterest * dailyRate * daysInCycle);
      credit.movements.add(CardMovement(
        date: open.cutoffDate,
        type: CardMovementType.interest,
        amount: interestAmt,
        statementId: open.id,
        note: 'Interés corriente (${daysInCycle}d × tasa diaria)',
      ));
    }

    credit.cycleCount++;
    final fee = credit.managementFee;
    if (fee > 0) {
      final chargeFee = credit.managementFeeFrequency == ManagementFeeFrequency.annual
          ? (credit.cycleCount % 12 == 0)
          : true;
      if (chargeFee) {
        credit.movements.add(CardMovement(
          date: open.cutoffDate,
          type: CardMovementType.fee,
          amount: fee,
          statementId: open.id,
          note: 'Cuota de manejo',
        ));
      }
    }

    final closingTotal = computeStatementTotal(open, credit.movements);
    final closedIndex = credit.statements.indexWhere((s) => s.id == open.id);
    final closed = CardStatement(
      id: open.id,
      creditId: open.creditId,
      cutoffDate: open.cutoffDate,
      dueDate: open.dueDate,
      closingBalance: closingTotal,
      paidAmount: open.paidAmount,
      status: closingTotal <= 0 ? CardStatementStatus.paid : CardStatementStatus.closed,
      createdAt: open.createdAt,
    );
    credit.statements[closedIndex] = closed;

    final nextCutoffRef = DateTime(cutoff.year, cutoff.month + 1, 1);
    final nextCutoff = cutoffDateForMonth(nextCutoffRef.year, nextCutoffRef.month, cutoffDay);
    final newOpen = CardStatement(
      id: '${credit.id}-${nextCutoff.microsecondsSinceEpoch}',
      creditId: credit.id,
      cutoffDate: toDateStr(nextCutoff),
      dueDate: toDateStr(dueDateForCutoff(credit, nextCutoff)),
      closingBalance: 0,
      openingBalance: closingTotal - closed.paidAmount,
      status: CardStatementStatus.open,
      createdAt: toDateStr(todayMidnight),
    );
    credit.statements.add(newOpen);

    for (final purchase in credit.installmentPurchases) {
      if (purchase.isFullyBilled) continue;
      final nextIndex = purchase.installmentsBilled + 1;
      final amount = nextIndex == purchase.installments
          ? purchase.lastInstallmentAmount
          : purchase.perInstallmentAmount;
      credit.movements.add(CardMovement(
        date: toDateStr(nextCutoff),
        type: CardMovementType.charge,
        amount: amount,
        note: purchase.note,
        categoria: purchase.categoria,
        statementId: newOpen.id,
        installmentPurchaseId: purchase.id,
        chargeInstallments: purchase.installments,
        installmentIndex: nextIndex,
      ));
      purchase.installmentsBilled = nextIndex;
    }

    open = newOpen;
    safety++;
  }
}

/// Fecha en que [statement] empezó a acumularse — el corte del extracto
/// anterior + 1 día, o su propia `createdAt` si es el primero de la
/// tarjeta (no hay anterior del cual partir).
DateTime _openedAtFor(CardCredit credit, CardStatement statement) {
  final sorted = credit.statements.toList()
    ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));
  final idx = sorted.indexWhere((s) => s.id == statement.id);
  if (idx <= 0) return parseDateStr(statement.createdAt);
  return parseDateStr(sorted[idx - 1].cutoffDate).add(const Duration(days: 1));
}

/// Registra un cargo de 1 sola exhibición, ligado al extracto abierto.
void registerCardCharge(
  CardCredit credit,
  double amount, {
  String note = '',
  String? categoria,
  DateTime? refDate,
}) {
  final open = ensureOpenStatement(credit, refDate);
  credit.movements.add(CardMovement(
    date: toDateStr(refDate ?? DateTime.now()),
    type: CardMovementType.charge,
    amount: amount.abs(),
    note: note,
    categoria: categoria,
    statementId: open.id,
  ));
}

/// Registra una compra a [installments] cuotas: crea la InstallmentPurchase
/// y factura la cuota 1 de inmediato en el extracto abierto. Las cuotas
/// 2..N se facturan solas cuando sus ciclos abran (closeCurrentCycleIfDue).
InstallmentPurchase registerInstallmentPurchase(
  CardCredit credit,
  double totalAmount,
  int installments, {
  String note = '',
  String? categoria,
  DateTime? refDate,
}) {
  final open = ensureOpenStatement(credit, refDate);
  final perInstallment = _round2(totalAmount / installments);
  final lastInstallment = _round2(totalAmount - perInstallment * (installments - 1));
  final purchaseDate = toDateStr(refDate ?? DateTime.now());

  final purchase = InstallmentPurchase(
    id: '${credit.id}-ip-${DateTime.now().microsecondsSinceEpoch}',
    creditId: credit.id,
    purchaseDate: purchaseDate,
    totalAmount: totalAmount,
    installments: installments,
    perInstallmentAmount: perInstallment,
    lastInstallmentAmount: lastInstallment,
    note: note,
    categoria: categoria,
    installmentsBilled: 1,
    createdAt: purchaseDate,
  );
  credit.installmentPurchases.add(purchase);

  credit.movements.add(CardMovement(
    date: purchaseDate,
    type: CardMovementType.charge,
    amount: installments == 1 ? totalAmount : perInstallment,
    note: note,
    categoria: categoria,
    statementId: open.id,
    installmentPurchaseId: purchase.id,
    chargeInstallments: installments,
    installmentIndex: 1,
  ));

  return purchase;
}
