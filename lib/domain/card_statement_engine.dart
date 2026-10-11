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
    // openingBalance SIEMPRE 0 — sin arrastre. Cada extracto representa
    // solo los movimientos de su propio período; la deuda total sin pagar
    // se obtiene sumando TODOS los extractos no-'paid' (ver
    // recomputeCardBalance/getPayableSummary), nunca arrastrando un número
    // fijo de un extracto a otro. Arrastrar quedaba "stale" en cuanto un
    // pago posterior (FIFO) reducía el extracto cerrado directamente,
    // duplicando la deuda entre los dos extractos.
    final newOpen = CardStatement(
      id: '${credit.id}-${nextCutoff.microsecondsSinceEpoch}',
      creditId: credit.id,
      cutoffDate: toDateStr(nextCutoff),
      dueDate: toDateStr(dueDateForCutoff(credit, nextCutoff)),
      closingBalance: 0,
      openingBalance: 0,
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

/// Aplica [amount] primero a los extractos CERRADOS sin pagar, del más
/// antiguo al más reciente (FIFO). Lo que sobre después de cubrirlos todos
/// se registra como pago anticipado sobre el extracto ABIERTO (puede
/// dejarlo en negativo — un "saldo a favor" que se descuenta del próximo
/// cierre).
void registerCardPayment(
  CardCredit credit,
  double amount, {
  DateTime? refDate,
}) {
  final date = toDateStr(refDate ?? DateTime.now());
  var remaining = amount.abs();

  final unpaidClosed = credit.statements
      .where((s) => s.status == CardStatementStatus.closed)
      .toList()
    ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));

  for (final statement in unpaidClosed) {
    if (remaining <= 0) break;
    final total = computeStatementTotal(statement, credit.movements);
    final owed = total - statement.paidAmount;
    if (owed <= 0) continue;
    final applied = math.min(remaining, owed);
    final idx = credit.statements.indexWhere((s) => s.id == statement.id);
    final newPaid = _round2(statement.paidAmount + applied);
    credit.statements[idx] = CardStatement(
      id: statement.id,
      creditId: statement.creditId,
      cutoffDate: statement.cutoffDate,
      dueDate: statement.dueDate,
      closingBalance: statement.closingBalance,
      openingBalance: statement.openingBalance,
      paidAmount: newPaid,
      status: newPaid >= total ? CardStatementStatus.paid : CardStatementStatus.closed,
      createdAt: statement.createdAt,
    );
    credit.movements.add(CardMovement(
      date: date,
      type: CardMovementType.payment,
      amount: applied,
      statementId: statement.id,
    ));
    remaining = _round2(remaining - applied);
  }

  if (remaining > 0) {
    final open = ensureOpenStatement(credit, refDate);
    credit.movements.add(CardMovement(
      date: date,
      type: CardMovementType.payment,
      amount: remaining,
      statementId: open.id,
    ));
  }
}

/// Recalcula credit.currentBalance desde cero: nunca se suma/resta a mano
/// en ningún otro lugar. Incluye lo que ya está facturado en extractos sin
/// pagar (abierto + cerrados) más las cuotas de compras a plazos que aún
/// no se han facturado (reservan cupo igual que un banco real).
void recomputeCardBalance(CardCredit credit) {
  var total = 0.0;
  for (final statement in credit.statements) {
    if (statement.status == CardStatementStatus.paid) continue;
    total += computeStatementTotal(statement, credit.movements) - statement.paidAmount;
  }
  for (final purchase in credit.installmentPurchases) {
    total += purchase.remainingAmount;
  }
  credit.currentBalance = _round2(total);
}

/// Cupo disponible — descuenta currentBalance (ya incluye cuotas de
/// compras a plazos aún no facturadas, vía recomputeCardBalance), igual
/// que reservaría un banco real.
double getCardAvailableLimit(CardCredit credit) =>
    math.max(0.0, credit.creditLimit - credit.currentBalance);

/// Lo que el usuario debe AHORA (extractos cerrados sin pagar por
/// completo) vs. lo que ya está cargado pero aún no se le exige pagar
/// (extracto abierto + cuotas de compras a plazos aún no facturadas).
class PayableSummary {
  final double exigible;
  final double pendienteFacturar;
  final DateTime? dueDate;

  const PayableSummary({
    required this.exigible,
    required this.pendienteFacturar,
    this.dueDate,
  });
}

PayableSummary getPayableSummary(CardCredit credit) {
  final unpaidClosed = credit.statements
      .where((s) => s.status == CardStatementStatus.closed)
      .toList()
    ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));

  final exigible = _round2(unpaidClosed.fold(
      0.0,
      (sum, s) =>
          sum + (computeStatementTotal(s, credit.movements) - s.paidAmount)));
  final dueDate = unpaidClosed.isEmpty ? null : parseDateStr(unpaidClosed.first.dueDate);

  final openTotal = credit.statements
      .where((s) => s.status == CardStatementStatus.open)
      .fold(0.0, (sum, s) => sum + computeStatementTotal(s, credit.movements));
  final unbilledCuotas = credit.installmentPurchases
      .fold(0.0, (sum, p) => sum + p.remainingAmount);

  return PayableSummary(
    exigible: exigible,
    pendienteFacturar: _round2(openTotal + unbilledCuotas),
    dueDate: dueDate,
  );
}

/// Elimina credit.movements[index] y, si era una cuota de una compra a
/// plazos y era la MÁS RECIENTE facturada de esa compra, decrementa
/// installmentsBilled para que se vuelva a facturar en el próximo cierre
/// de ciclo en vez de perderse. No hay tracking manual de delta sobre
/// currentBalance — el llamador debe invocar recomputeCardBalance después.
void deleteCardMovement(CardCredit credit, int index) {
  if (index < 0 || index >= credit.movements.length) return;
  final removed = credit.movements[index];
  credit.movements.removeAt(index);

  final purchaseId = removed.installmentPurchaseId;
  if (purchaseId != null) {
    final purchase = credit.installmentPurchases
        .where((p) => p.id == purchaseId)
        .firstOrNull;
    if (purchase != null &&
        removed.installmentIndex == purchase.installmentsBilled) {
      purchase.installmentsBilled -= 1;
    }
  }
}

/// Migra datos de tarjetas creadas antes del motor de extractos v2:
/// liga cada CardMovement sin `statementId` al extracto que le
/// corresponde (inferido con el mismo criterio de agrupación legado,
/// `cycleKeyFor`), creando ese CardStatement si no existe todavía —
/// reutilizando uno existente con el mismo `cutoffDate` si ya se creó
/// para otro movimiento del mismo ciclo. Idempotente: una tarjeta sin
/// nada legado no se modifica. Llamar SIEMPRE antes de
/// `closeCurrentCycleIfDue` en el flujo de arranque.
void migrateLegacyCardData(CardCredit credit, [DateTime? refDate]) {
  final legacyMovements =
      credit.movements.where((m) => m.statementId == null).toList();

  for (final m in legacyMovements) {
    final cutoffDate = m.statementCutoff ?? cycleKeyFor(m.date, credit.cutoffDay);
    var statement = credit.statements
        .where((s) => s.cutoffDate == cutoffDate)
        .firstOrNull;
    statement ??= _createLegacyStatement(credit, cutoffDate);
    final idx = credit.movements.indexOf(m);
    credit.movements[idx] = CardMovement(
      date: m.date,
      type: m.type,
      amount: m.amount,
      note: m.note,
      advanceInstallments: m.advanceInstallments,
      advanceInterestRate: m.advanceInterestRate,
      advanceInterestRateType: m.advanceInterestRateType,
      advanceCommission: m.advanceCommission,
      advanceFirstPaymentDate: m.advanceFirstPaymentDate,
      advanceDestination: m.advanceDestination,
      categoria: m.categoria,
      chargeInstallments: m.chargeInstallments,
      installmentIndex: m.installmentIndex,
      statementId: statement.id,
    );
  }

  ensureOpenStatement(credit, refDate);
}

CardStatement _createLegacyStatement(CardCredit credit, String cutoffDate) {
  final cutoff = parseDateStr(cutoffDate);
  final dueDate = toDateStr(dueDateForCutoff(credit, cutoff));
  final statement = CardStatement(
    id: '${credit.id}-legacy-$cutoffDate',
    creditId: credit.id,
    cutoffDate: cutoffDate,
    dueDate: dueDate,
    closingBalance: 0,
    status: CardStatementStatus.closed,
    createdAt: cutoffDate,
  );
  credit.statements.add(statement);
  return statement;
}
