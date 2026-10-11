import 'dart:math' as math;

import '../data/models/card_movement.dart';
import '../data/models/card_statement.dart';
import '../data/models/credit.dart';
import 'date_utils.dart';
import 'interest_rate.dart';

/// Card cycle engine, ported from app.js's "CREDIT CARD CYCLE ENGINE"
/// section (~L668-773).

int _clampCutoffDay(int cutoffDay) => math.min(math.max(cutoffDay, 1), 31);

/// Last day-of-month for [year]/[month] (1-indexed month).
int _lastDayOfMonth(int year, int month) {
  // Day 0 of the next month == last day of this month (mirrors
  // `new Date(year, month + 1, 0)` in JS, where JS months are 0-indexed).
  return DateTime(year, month + 1, 0).day;
}

/// Port of cutoffDateForMonth (app.js ~L671-674). [month] is 1-indexed here
/// (unlike the JS original's 0-indexed `month` param) to match Dart's
/// DateTime convention; callers pass Dart month numbers directly.
DateTime cutoffDateForMonth(int year, int month, int cutoffDay) {
  final lastDay = _lastDayOfMonth(year, month);
  return DateTime(year, month, math.min(cutoffDay, lastDay));
}

/// Returns the closing cutoff date ("YYYY-MM-DD") of the billing cycle that
/// contains [movementDate], given [cutoffDay]. The cutoff day belongs to
/// the cycle that CLOSES that day (matches getCardCycleDates' documented
/// semantics) — a movement dated exactly on the cutoff day is part of the
/// statement generated that day, not the one that just opened.
///
/// Single source of truth for this grouping: movements_tab.dart and
/// accrueCardCredit both use this instead of each keeping their own
/// (previously inconsistent) copy.
String cycleKeyFor(String movementDate, int cutoffDay) {
  if (movementDate.length < 10) return movementDate;
  final d = DateTime.tryParse(movementDate);
  if (d == null) return movementDate;
  final cutoffDayClamped = _clampCutoffDay(cutoffDay);
  // Use the real cutoff day (clamped to the end of each month via
  // cutoffDateForMonth, e.g. day 31 in April → the 30th), matching
  // accrueCardCredit's cycle-end computation exactly — NOT a flat clamp to
  // 28, which disagreed with it for any cutoffDay above 28.
  final thisMonthEnd = cutoffDateForMonth(d.year, d.month, cutoffDayClamped);
  if (d.day <= thisMonthEnd.day) {
    return toDateStr(thisMonthEnd);
  }
  final nextMonth = d.month == 12 ? 1 : d.month + 1;
  final nextYear = d.month == 12 ? d.year + 1 : d.year;
  return toDateStr(cutoffDateForMonth(nextYear, nextMonth, cutoffDayClamped));
}

class CardCycleDates {
  final DateTime lastCutoff;
  final DateTime nextCutoff;
  final DateTime dueDate;

  const CardCycleDates({
    required this.lastCutoff,
    required this.nextCutoff,
    required this.dueDate,
  });
}

/// Due date for a statement that closes on [cutoff], given how [credit]
/// expresses its payment terms (`paymentDueDay` or the legacy
/// `paymentDueOffsetDays` fallback). Factored out of [getCardCycleDates] so
/// the cycle-closing logic in `accrueCardCredit` can compute the exact same
/// due date for a specific (not necessarily "today") cutoff.
DateTime _dueDateForCutoff(CardCredit credit, DateTime cutoff) {
  if (credit.paymentDueDay > 0) {
    // paymentDueDay es un día del mes: el vencimiento cae ese día en el mes
    // siguiente al corte (ej: corte sep 15 → pago oct 5).
    final dueMonth = DateTime(cutoff.year, cutoff.month + 1, 1);
    final lastDayOfDueMonth = _lastDayOfMonth(dueMonth.year, dueMonth.month);
    return DateTime(
      dueMonth.year,
      dueMonth.month,
      math.min(credit.paymentDueDay, lastDayOfDueMonth),
    );
  }
  // Fallback para registros no migrados: offset en días desde el corte.
  return cutoff.add(Duration(days: credit.paymentDueOffsetDays));
}

/// Port of getCardCycleDates (app.js ~L678-697).
CardCycleDates getCardCycleDates(CardCredit credit, [DateTime? refDate]) {
  final ref = refDate ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final cutoffDay = _clampCutoffDay(credit.cutoffDay);

  var lastCutoff = cutoffDateForMonth(today.year, today.month, cutoffDay);
  // The cutoff day belongs to the CURRENT cycle until 23:59:59 — the new cycle
  // starts the following day at 00:00. Move to previous month only when the
  // cutoff date is strictly after today (i.e. today < cutoffDay this month).
  if (lastCutoff.isAfter(today)) {
    final prevMonthRef = DateTime(today.year, today.month - 1, 1);
    lastCutoff = cutoffDateForMonth(
        prevMonthRef.year, prevMonthRef.month, cutoffDay);
  }
  final nextMonthRef = DateTime(lastCutoff.year, lastCutoff.month + 1, 1);
  final nextCutoff =
      cutoffDateForMonth(nextMonthRef.year, nextMonthRef.month, cutoffDay);

  return CardCycleDates(
    lastCutoff: lastCutoff,
    nextCutoff: nextCutoff,
    dueDate: _dueDateForCutoff(credit, lastCutoff),
  );
}

double _round2(double v) => (v * 100).round() / 100;

/// Port of accrueCardCredit (app.js ~L703-756).
///
/// Applies simple daily interest (no compounding within/across cycles) and
/// the management fee for every billing cycle closed since
/// `lastAccrualCutoff`, bringing `currentBalance` up to date. The daily rate
/// is derived from `credit.interestRate` normalized per how the user says
/// it's expressed (`credit.interestRateType` — E.A., E.M., or simple
/// monthly; see `interest_rate.dart`), so the entity that quoted the rate
/// never needs to be known here. Idempotent (safe to call on every app
/// load) and capped at 36 cycles per call as a safety net against runaway
/// loops.
void accrueCardCredit(CardCredit credit, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);

  if (credit.lastAccrualCutoff == null) {
    // First run: anchor to the most recent cutoff without back-charging
    // historical interest.
    final dates = getCardCycleDates(credit, todayMidnight);
    credit.lastAccrualCutoff = toDateStr(dates.lastCutoff);
    return;
  }

  final cutoffDay = _clampCutoffDay(credit.cutoffDay);

  // Early-exit guard: compute next cutoff from the last accrual point and
  // skip everything if it hasn't passed yet — avoids computing dailyRate
  // and entering the loop on the common "already up-to-date" app launch.
  final lastCursor = parseDateStr(credit.lastAccrualCutoff!);
  final earlyNextRef = DateTime(lastCursor.year, lastCursor.month + 1, 1);
  final earlyNext = cutoffDateForMonth(earlyNextRef.year, earlyNextRef.month, cutoffDay);
  // The cutoff day itself still belongs to the cycle closing that day (per
  // getCardCycleDates' documented "until 23:59" semantics) — a movement
  // registered later that same day must still be counted, so a cycle only
  // actually CLOSES (snapshots into a CardStatement) the day AFTER its
  // cutoff, never on the cutoff day itself.
  if (!earlyNext.isBefore(todayMidnight)) return;

  final dailyRate = dailyRateFrom(credit.interestRate, credit.interestRateType);

  // Seed for the FIRST CardStatement this card ever gets: a card that
  // already had debt before this feature existed (currentBalance set
  // directly, or accrued over past cycles with no CardStatement history)
  // must not have that debt silently ignored as if openingBalance were 0.
  // currentBalance = seed + net(all movements so far) always holds, since
  // every balance-changing operation also appends a matching movement —
  // so seed = currentBalance - net(movements), captured BEFORE this call's
  // loop adds any new interest/fee movements.
  final seedBalance = credit.currentBalance -
      credit.movements.fold<double>(
          0.0,
          (sum, m) => sum +
              (m.type == CardMovementType.payment
                  ? -m.amount.abs()
                  : m.amount.abs()));

  var cursorStr = credit.lastAccrualCutoff!;
  var safety = 0;
  while (safety < 36) {
    final cursor = parseDateStr(cursorStr);
    final nextRef = DateTime(cursor.year, cursor.month + 1, 1);
    final next = cutoffDateForMonth(nextRef.year, nextRef.month, cutoffDay);
    if (!next.isBefore(todayMidnight)) break;

    final daysInCycle = next.difference(cursor).inDays;
    if (credit.currentBalance > 0 && dailyRate > 0) {
      final interestAmt =
          _round2(credit.currentBalance * dailyRate * daysInCycle);
      credit.currentBalance = _round2(credit.currentBalance + interestAmt);
      credit.movements.add(CardMovement(
        date: toDateStr(next),
        type: CardMovementType.interest,
        amount: interestAmt,
        note: 'Interés corriente (${daysInCycle}d × tasa diaria)',
      ));
    }

    credit.cycleCount++;
    final fee = credit.managementFee;
    if (fee > 0) {
      final freq = credit.managementFeeFrequency;
      final chargeFee =
          freq == ManagementFeeFrequency.annual ? (credit.cycleCount % 12 == 0) : true;
      if (chargeFee) {
        credit.currentBalance = _round2(credit.currentBalance + fee);
        credit.movements.add(CardMovement(
          date: toDateStr(next),
          type: CardMovementType.fee,
          amount: fee,
          note: 'Cuota de manejo',
        ));
      }
    }

    final cycleEndStr = toDateStr(next);
    final cycleMovements = credit.movements.where((m) {
      if (m.statementCutoff != null) return m.statementCutoff == cycleEndStr;
      return cycleKeyFor(m.date, cutoffDay) == cycleEndStr;
    });
    var netAmount = 0.0;
    for (final m in cycleMovements) {
      netAmount += m.type == CardMovementType.payment
          ? -m.amount.abs()
          : m.amount.abs();
    }
    final openingBalance = credit.closedStatements.isNotEmpty
        ? (credit.closedStatements.last.closingBalance -
            credit.closedStatements.last.paidAmount)
        : seedBalance;
    // Defends against lastAccrualCutoff ever pointing at a cutoffDate that
    // already has a statement (e.g. an inconsistent restored backup) —
    // without this, re-adding one with the same deterministic id would
    // throw a UNIQUE constraint violation on the next upsertCredit and lose
    // the whole save, not just this one statement.
    final alreadyExists =
        credit.closedStatements.any((s) => s.cutoffDate == cycleEndStr);
    if (!alreadyExists) {
      credit.closedStatements.add(CardStatement(
        id: '${credit.id}-$cycleEndStr',
        creditId: credit.id,
        cutoffDate: cycleEndStr,
        dueDate: toDateStr(_dueDateForCutoff(credit, next)),
        closingBalance: _round2(openingBalance + netAmount),
        createdAt: toDateStr(todayMidnight),
      ));
    }

    cursorStr = cycleEndStr;
    safety++;
  }
  credit.lastAccrualCutoff = cursorStr;
}

/// Closes out any interest already accrued under the CURRENT
/// `interestRate`/`interestRateType` up to [changeDate], anchoring
/// `lastAccrualCutoff` there, so that a caller can safely overwrite the rate
/// fields right after calling this and know the new rate will only ever be
/// applied to cycles that close AFTER [changeDate].
///
/// This fixes a real financial bug: without this step, editing a card's
/// rate after the app has been unopened for several billing cycles would
/// cause the next `accrueCardCredit` call to charge the NEW rate
/// retroactively over interest that, in reality, accrued under the OLD
/// rate.
///
/// Call this BEFORE mutating `credit.interestRate` /
/// `credit.interestRateType` — it reads the credit's current (pre-edit)
/// rate to accrue whatever full cycles have elapsed, exactly like a normal
/// `accrueCardCredit` call would, just capped at [changeDate] instead of
/// "today".
///
/// Known limitation (documented, not fixed here): the engine has no
/// intra-cycle daily-balance tracking, so a rate change that lands in the
/// MIDDLE of an open cycle cannot be prorated by days. That cycle — the one
/// still open at [changeDate] — is left untouched here (its cutoff hasn't
/// arrived yet) and will be accrued in full, with whichever rate is current
/// at the time its cutoff is reached, on a later `accrueCardCredit` call.
/// This is the same simplification the engine already makes for ordinary
/// accrual; this function only prevents the strictly worse case of
/// retroactively re-rating cycles that already closed.
void applyRateChangeAt(CardCredit credit, DateTime changeDate) {
  // No prior accrual anchor yet (brand-new card, or never opened since
  // creation): nothing has accrued under the old rate, so there is nothing
  // to close out. `accrueCardCredit` will set the initial anchor on its own
  // next run.
  if (credit.lastAccrualCutoff == null) return;
  accrueCardCredit(credit, changeDate);
}

/// Port of registerCardMovement (app.js ~L763-773), minus the
/// persistence/save call which belongs to the data layer, not domain logic.
void registerCardMovement(
  CardCredit credit,
  String type,
  double amount, {
  String note = '',
  String? categoria,
  int? chargeInstallments,
}) {
  final delta = type == CardMovementType.payment ? -amount.abs() : amount.abs();
  credit.currentBalance =
      math.max(0.0, _round2(credit.currentBalance + delta));
  credit.movements.add(CardMovement(
    date: toDateStr(DateTime.now()),
    type: type,
    amount: amount.abs(),
    note: note,
    categoria: categoria,
    chargeInstallments: type == CardMovementType.charge ? chargeInstallments : null,
  ));
  if (type == CardMovementType.payment) {
    _applyPaymentToLatestStatement(credit, amount.abs());
  }
}

/// Applies [amount] against the LATEST closed statement's unpaid balance
/// (the only one that matters for [getPayableSummary] — older statements'
/// unpaid balances already rolled forward into it via `openingBalance`).
/// Clamps `paidAmount` to `closingBalance` so an overpayment never shows as
/// "paid more than was owed", and flips `status` to paid once fully
/// covered. No-op when there are no closed statements yet (every charge is
/// still in the open cycle — nothing to pay down yet).
void _applyPaymentToLatestStatement(CardCredit credit, double amount) {
  if (credit.closedStatements.isEmpty) return;
  final latest = credit.closedStatements.last;
  final newPaid = math.min(latest.closingBalance, latest.paidAmount + amount);
  credit.closedStatements[credit.closedStatements.length - 1] = CardStatement(
    id: latest.id,
    creditId: latest.creditId,
    cutoffDate: latest.cutoffDate,
    dueDate: latest.dueDate,
    closingBalance: latest.closingBalance,
    paidAmount: _round2(newPaid),
    status: newPaid >= latest.closingBalance
        ? CardStatementStatus.paid
        : CardStatementStatus.closed,
    createdAt: latest.createdAt,
  );
}

/// Splits a purchase of [totalAmount] into [installments] movements, one
/// per consecutive future billing cycle starting from the currently open
/// one. Each movement's `date` is the real purchase date (for display);
/// `statementCutoff` is what determines which extracto it belongs to.
/// Rounds to 2 decimals; the rounding remainder is absorbed entirely by the
/// LAST installment so the sum always equals [totalAmount] exactly.
List<CardMovement> buildInstallmentMovements({
  required CardCredit credit,
  required double totalAmount,
  required int installments,
  String note = '',
  String? categoria,
  DateTime? refDate,
}) {
  final perInstallment = _round2(totalAmount / installments);
  final lastInstallment =
      _round2(totalAmount - perInstallment * (installments - 1));
  final purchaseDate = toDateStr(refDate ?? DateTime.now());
  final cutoffDay = _clampCutoffDay(credit.cutoffDay);

  // The first installment goes to whichever extracto cycleKeyFor would
  // assign a single-cuota charge made on [purchaseDate] — same function
  // used everywhere else to group by extracto, so a purchase on the cutoff
  // day behaves identically whether it's 1 cuota or N.
  var cutoff = parseDateStr(cycleKeyFor(purchaseDate, cutoffDay));
  final movements = <CardMovement>[];
  for (var i = 1; i <= installments; i++) {
    movements.add(CardMovement(
      date: purchaseDate,
      type: CardMovementType.charge,
      amount: i == installments ? lastInstallment : perInstallment,
      note: note,
      categoria: categoria,
      chargeInstallments: installments,
      installmentIndex: i,
      statementCutoff: toDateStr(cutoff),
    ));
    final nextMonthRef = DateTime(cutoff.year, cutoff.month + 1, 1);
    cutoff = cutoffDateForMonth(nextMonthRef.year, nextMonthRef.month, cutoffDay);
  }
  return movements;
}

/// Registers a card charge, splitting it across [installments] consecutive
/// extractos when `installments > 1` (see [buildInstallmentMovements]).
/// A single-installment charge behaves exactly like the old
/// [registerCardMovement] (no `statementCutoff`, grouped by the normal
/// date+cutoff criterion).
void registerCardCharge(
  CardCredit credit,
  double totalAmount, {
  String note = '',
  String? categoria,
  int installments = 1,
  DateTime? refDate,
}) {
  if (installments <= 1) {
    registerCardMovement(
      credit,
      CardMovementType.charge,
      totalAmount,
      note: note,
      categoria: categoria,
    );
    return;
  }
  final movements = buildInstallmentMovements(
    credit: credit,
    totalAmount: totalAmount,
    installments: installments,
    note: note,
    categoria: categoria,
    refDate: refDate,
  );
  credit.currentBalance = _round2(credit.currentBalance + totalAmount.abs());
  credit.movements.addAll(movements);
}

/// Removes a previously-registered movement (identified by its index within
/// `credit.movements`, most-recent-first order not assumed — callers must
/// pass the index into the underlying `credit.movements` list) and reverses
/// its effect on `currentBalance`, undoing exactly what [registerCardMovement]
/// (or [accrueCardCredit], for interest/fee entries) applied when it was
/// created. Lets a user correct a mis-registered charge/payment/interest/fee
/// without leaving the balance out of sync with the visible history.
void deleteCardMovement(CardCredit credit, int index) {
  if (index < 0 || index >= credit.movements.length) return;
  final removed = credit.movements[index];
  // Payments reduced the balance (delta = -amount); every other type
  // (charge/interest/fee) increased it (delta = +amount). Reversing means
  // applying the opposite delta.
  final delta = removed.type == CardMovementType.payment
      ? removed.amount.abs()
      : -removed.amount.abs();
  credit.currentBalance = math.max(0.0, _round2(credit.currentBalance + delta));
  credit.movements.removeAt(index);
}

/// Port of getCreditRemainingBalance for card credits (app.js ~L1332-1336).
double getCardRemainingBalance(CardCredit credit) => credit.currentBalance;

/// Available credit limit (renderCardDetailPanel, app.js ~L1469).
double getCardAvailableLimit(CardCredit credit) =>
    math.max(0.0, credit.creditLimit - credit.currentBalance);

/// What the user actually owes RIGHT NOW (closed, unpaid statements) vs.
/// charges already made in the still-open cycle (not due yet). This is
/// what fixes the bug where a brand-new charge, registered right after a
/// cutoff, appeared lumped together with an imminent due date that
/// actually belonged to the PREVIOUS (already-closed) statement.
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
  // Only the LATEST closed statement matters: the balance rolls forward
  // (each statement's closingBalance already carries the prior unpaid
  // amount via `openingBalance` in accrueCardCredit) — summing every unpaid
  // statement would double-count debt that already rolled into this one.
  if (credit.closedStatements.isEmpty) {
    return const PayableSummary(exigible: 0, pendienteFacturar: 0);
  }
  final latest = credit.closedStatements.last;
  if (latest.status == CardStatementStatus.paid) {
    return PayableSummary(
      exigible: 0,
      pendienteFacturar: math.max(0.0, _round2(credit.currentBalance)),
    );
  }
  final exigible = _round2(latest.closingBalance - latest.paidAmount);
  final pendienteFacturar =
      math.max(0.0, _round2(credit.currentBalance - exigible));
  return PayableSummary(
    exigible: exigible,
    pendienteFacturar: pendienteFacturar,
    dueDate: parseDateStr(latest.dueDate),
  );
}

// ─── French amortization helpers (shared with simulator) ─────────────────────

/// Monthly payment (PMT) under the French amortization formula.
/// Returns [principal] / [months] when [monthlyRate] is zero.
double frenchMonthlyPayment(double principal, double monthlyRate, int months) {
  if (monthlyRate == 0 || months <= 0) {
    return months > 0 ? principal / months : 0;
  }
  final r = monthlyRate;
  final factor = math.pow(1 + r, months);
  return principal * r * factor / (factor - 1);
}

/// Total interest paid over the life of a French-amortized loan.
double frenchTotalInterest(double principal, double monthlyRate, int months) =>
    frenchMonthlyPayment(principal, monthlyRate, months) * months - principal;
