import 'dart:math' as math;

import '../data/models/credit.dart';
import 'date_utils.dart';

/// Pure date/cycle math for credit cards. The mutating ledger functions
/// (registrar cargos/pagos, cerrar ciclos, calcular saldo exigible) viven
/// en card_statement_engine.dart — este archivo solo calcula fechas.

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
/// the cycle that CLOSES that day — a movement dated exactly on the cutoff
/// day is part of the statement generated that day, not the one that just
/// opened. Used by card_statement_engine.dart (ensureOpenStatement,
/// migrateLegacyCardData) as the single source of truth for this grouping.
String cycleKeyFor(String movementDate, int cutoffDay) {
  if (movementDate.length < 10) return movementDate;
  final d = DateTime.tryParse(movementDate);
  if (d == null) return movementDate;
  final cutoffDayClamped = _clampCutoffDay(cutoffDay);
  // Use the real cutoff day (clamped to the end of each month via
  // cutoffDateForMonth, e.g. day 31 in April → the 30th) — NOT a flat
  // clamp to 28, which disagreed with it for any cutoffDay above 28.
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
/// `paymentDueOffsetDays` fallback).
DateTime dueDateForCutoff(CardCredit credit, DateTime cutoff) {
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
    dueDate: dueDateForCutoff(credit, lastCutoff),
  );
}

/// Port of getCreditRemainingBalance for card credits (app.js ~L1332-1336).
/// currentBalance es una caché recalculada por recomputeCardBalance (ver
/// card_statement_engine.dart) — este helper solo expone el campo con el
/// nombre que espera credit_calculator.dart's getCreditRemainingBalance.
double getCardRemainingBalance(CardCredit credit) => credit.currentBalance;

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
