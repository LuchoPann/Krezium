import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/card_calculator.dart';
import 'package:krezium/domain/date_utils.dart';

void main() {
  group('cutoffDateForMonth', () {
    test('clamps to last day of February (non-leap year)', () {
      final d = cutoffDateForMonth(2026, 2, 31);
      expect(d, DateTime(2026, 2, 28));
    });

    test('clamps to last day of February (leap year)', () {
      final d = cutoffDateForMonth(2028, 2, 30);
      expect(d, DateTime(2028, 2, 29));
    });

    test('clamps to last day of a 30-day month', () {
      final d = cutoffDateForMonth(2026, 4, 31);
      expect(d, DateTime(2026, 4, 30));
    });

    test('keeps cutoffDay unchanged for 31-day months', () {
      final d = cutoffDateForMonth(2026, 1, 31);
      expect(d, DateTime(2026, 1, 31));
    });
  });

  group('getCardCycleDates', () {
    test('computes last/next cutoff and due date relative to ref date', () {
      final credit = CardCredit(
        id: 'card1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        paymentDueOffsetDays: 20,
      );
      final dates = getCardCycleDates(credit, DateTime(2026, 3, 20));
      expect(dates.lastCutoff, DateTime(2026, 3, 15));
      expect(dates.nextCutoff, DateTime(2026, 4, 15));
      expect(dates.dueDate, DateTime(2026, 3, 15).add(const Duration(days: 20)));
    });

    test('rolls back to previous month when ref date is before this month cutoff', () {
      final credit = CardCredit(
        id: 'card1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        paymentDueOffsetDays: 20,
      );
      final dates = getCardCycleDates(credit, DateTime(2026, 3, 5));
      expect(dates.lastCutoff, DateTime(2026, 2, 15));
      expect(dates.nextCutoff, DateTime(2026, 3, 15));
    });

    group('paymentDueDay', () {
      test('uses paymentDueDay when > 0, ignores paymentDueOffsetDays', () {
        // corte día 15, pago día 5 del mes siguiente
        final credit = CardCredit(
          id: 'c1', name: 'T', lender: 'B',
          cutoffDay: 15,
          paymentDueDay: 5,
          paymentDueOffsetDays: 999, // debe ser ignorado
        );
        // ref 2026-09-20: último corte fue sep 15 → pago oct 5
        final dates = getCardCycleDates(credit, DateTime(2026, 9, 20));
        expect(dates.dueDate, DateTime(2026, 10, 5));
      });

      test('falls back to paymentDueOffsetDays when paymentDueDay == 0', () {
        final credit = CardCredit(
          id: 'c2', name: 'T', lender: 'B',
          cutoffDay: 15,
          paymentDueDay: 0, // no migrado
          paymentDueOffsetDays: 20,
        );
        // ref 2026-09-20: último corte sep 15 + 20 días = oct 5
        final dates = getCardCycleDates(credit, DateTime(2026, 9, 20));
        expect(dates.dueDate, DateTime(2026, 10, 5));
      });

      test('paymentDueDay handles month wrap (día 5 del mes siguiente al corte)', () {
        final credit = CardCredit(
          id: 'c3', name: 'T', lender: 'B',
          cutoffDay: 28,
          paymentDueDay: 5,
          paymentDueOffsetDays: 0,
        );
        // ref 2026-09-30: último corte sep 28 → pago oct 5
        final dates = getCardCycleDates(credit, DateTime(2026, 9, 30));
        expect(dates.dueDate, DateTime(2026, 10, 5));
      });

      test('paymentDueDay clamps to last day of month (día 31 en mes de 30 días)', () {
        final credit = CardCredit(
          id: 'c4', name: 'T', lender: 'B',
          cutoffDay: 1,
          paymentDueDay: 31,
          paymentDueOffsetDays: 0,
        );
        // ref 2026-09-05: último corte sep 1 → pago en oct → oct tiene 31 días → oct 31
        final dates = getCardCycleDates(credit, DateTime(2026, 9, 5));
        expect(dates.dueDate, DateTime(2026, 10, 31));
      });

      test('paymentDueDay 31 in month of 30 days clamps to 30', () {
        final credit = CardCredit(
          id: 'c5', name: 'T', lender: 'B',
          cutoffDay: 1,
          paymentDueDay: 31,
          paymentDueOffsetDays: 0,
        );
        // ref 2026-04-05: último corte abr 1 → pago en mayo → mayo tiene 31 → mayo 31
        // Pero si último corte fuera mar 1 → pago abr → abr tiene 30 → abr 30
        final dates = getCardCycleDates(credit, DateTime(2026, 3, 5));
        // último corte fue mar 1, pago es abr que tiene 30 días → abr 30
        expect(dates.dueDate, DateTime(2026, 4, 30));
      });
    });
  });

  group('accrueCardCredit', () {
    test('first call just anchors lastAccrualCutoff without charging interest', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        interestRate: 36.5, // -> daily rate 0.1%
        cutoffDay: 1,
      );
      accrueCardCredit(credit, DateTime(2026, 3, 10));
      expect(credit.lastAccrualCutoff, isNotNull);
      expect(credit.currentBalance, 1000);
      expect(credit.movements, isEmpty);
    });

    test('accrues effective daily interest (from E.A.) for a single closed cycle', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        // dailyRate = (1.365)^(1/365) - 1 ~= 0.00085284 (effectiveAnnual, the default).
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-02-01',
      );
      // Next cutoff after 2026-02-01 is 2026-03-01 -> 28 days in cycle (2026 not leap).
      accrueCardCredit(credit, DateTime(2026, 3, 5));

      // interest = round(1000 * 0.00085284... * 28) = 23.88
      expect(credit.currentBalance, closeTo(1023.88, 1e-9));
      expect(credit.movements, hasLength(1));
      expect(credit.movements[0].type, 'interest');
      expect(credit.movements[0].amount, closeTo(23.88, 1e-9));
      expect(credit.lastAccrualCutoff, '2026-03-01');
    });

    test('accrues compounding-free-per-cycle simple interest across multiple cycles', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-01-01',
      );
      // Cycles: Jan01->Feb01 (31d), Feb01->Mar01 (28d), Mar01->Apr01 (31d)
      accrueCardCredit(credit, DateTime(2026, 4, 5));

      expect(credit.movements.where((m) => m.type == 'interest'), hasLength(3));
      // dailyRate = (1.365)^(1/365) - 1 ~= 0.00085284
      // cycle 1: 1000 * dailyRate * 31 = 26.44 -> balance 1026.44
      // cycle 2: 1026.44 * dailyRate * 28 = 24.51 -> balance 1050.95
      // cycle 3: 1050.95 * dailyRate * 31 = 27.79 -> balance 1078.74
      expect(credit.currentBalance, closeTo(1078.74, 1e-2));
      expect(credit.lastAccrualCutoff, '2026-04-01');
    });

    test('does not charge interest when balance is zero', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 0,
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-02-01',
      );
      accrueCardCredit(credit, DateTime(2026, 3, 5));
      expect(credit.currentBalance, 0);
      expect(credit.movements.where((m) => m.type == 'interest'), isEmpty);
    });

    test('is idempotent: a second call with the same "now" charges nothing further', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-02-01',
      );
      accrueCardCredit(credit, DateTime(2026, 3, 5));
      final balanceAfterFirst = credit.currentBalance;
      final movementsAfterFirst = credit.movements.length;

      accrueCardCredit(credit, DateTime(2026, 3, 5));
      expect(credit.currentBalance, balanceAfterFirst);
      expect(credit.movements.length, movementsAfterFirst);
    });

    test('monthly management fee is charged every closed cycle', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 0,
        interestRate: 0,
        managementFee: 15,
        managementFeeFrequency: ManagementFeeFrequency.monthly,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-01-01',
      );
      // 3 cycles close: Jan->Feb, Feb->Mar, Mar->Apr
      accrueCardCredit(credit, DateTime(2026, 4, 5));

      final feeMovements = credit.movements.where((m) => m.type == 'fee');
      expect(feeMovements, hasLength(3));
      expect(credit.currentBalance, closeTo(45, 1e-9));
      expect(credit.cycleCount, 3);
    });

    test('annual management fee is only charged every 12th cycle', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 0,
        interestRate: 0,
        managementFee: 100,
        managementFeeFrequency: ManagementFeeFrequency.annual,
        cutoffDay: 1,
        lastAccrualCutoff: '2025-01-01',
      );
      // 15 cycles close between 2025-01-01 and 2026-04-05: fee should charge
      // at cycle 12 only (once).
      accrueCardCredit(credit, DateTime(2026, 4, 5));

      final feeMovements = credit.movements.where((m) => m.type == 'fee');
      expect(credit.cycleCount, 15);
      expect(feeMovements, hasLength(1));
      expect(credit.currentBalance, closeTo(100, 1e-9));
    });

    test('safety cap stops after 36 cycles in a single call', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 0,
        interestRate: 0,
        cutoffDay: 1,
        lastAccrualCutoff: '2000-01-01',
      );
      accrueCardCredit(credit, DateTime(2026, 1, 1));
      expect(credit.cycleCount, 36);
    });
  });

  group('applyRateChangeAt', () {
    test('closes pending cycles with the OLD rate before a rate edit, instead of back-charging the new rate', () {
      // Card unopened for 3 full cycles (Jan01, Feb01, Mar01) at the old
      // rate of 36.5% E.A. The user edits the rate to 60% E.A. today
      // (2026-04-05), which is itself mid-cycle (next cutoff 2026-05-01).
      final creditOldRateReference = CardCredit(
        id: 'ref',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-01-01',
      );
      // What SHOULD happen: the 3 elapsed cycles accrue at the OLD rate.
      accrueCardCredit(creditOldRateReference, DateTime(2026, 4, 5));
      final expectedBalanceAtOldRate = creditOldRateReference.currentBalance;

      // What the bug would produce: same starting state, but accrual runs
      // AFTER the rate field was already overwritten to 60%.
      final creditBuggy = CardCredit(
        id: 'buggy',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-01-01',
      );
      creditBuggy.interestRate = 60; // simulate overwriting the rate first
      accrueCardCredit(creditBuggy, DateTime(2026, 4, 5));
      final buggyBalance = creditBuggy.currentBalance;

      // The fix: call applyRateChangeAt with the OLD rate still in place,
      // THEN overwrite the rate field.
      final creditFixed = CardCredit(
        id: 'fixed',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 1000,
        interestRate: 36.5,
        cutoffDay: 1,
        lastAccrualCutoff: '2026-01-01',
      );
      applyRateChangeAt(creditFixed, DateTime(2026, 4, 5));
      creditFixed.interestRate = 60;

      // The 3 already-elapsed cycles must match the OLD-rate reference
      // exactly, not the buggy new-rate result.
      expect(creditFixed.currentBalance, closeTo(expectedBalanceAtOldRate, 1e-9));
      expect(creditFixed.currentBalance, isNot(closeTo(buggyBalance, 1e-9)));
      expect(creditFixed.lastAccrualCutoff, '2026-04-01');

      // Now the pending (still-open) cycle from 2026-04-01 onward correctly
      // uses the NEW rate once it closes.
      accrueCardCredit(creditFixed, DateTime(2026, 5, 5));
      expect(creditFixed.lastAccrualCutoff, '2026-05-01');
      final lastInterestMovement =
          creditFixed.movements.where((m) => m.type == CardMovementType.interest).last;
      // dailyRate at 60% E.A. = (1.6)^(1/365)-1 ~= 0.0012872; 30 days in
      // April; balance going into April is expectedBalanceAtOldRate.
      final expectedNewCycleInterest =
          (expectedBalanceAtOldRate * (math.pow(1.6, 1 / 365) - 1) * 30 * 100).round() / 100;
      expect(lastInterestMovement.amount, closeTo(expectedNewCycleInterest, 1e-2));
    });

    test('on a brand-new card (no prior accrual) it is a no-op and does not break the first accrual', () {
      final credit = CardCredit(
        id: 'new1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 500,
        interestRate: 36.5,
        cutoffDay: 1,
      );
      expect(credit.lastAccrualCutoff, isNull);

      applyRateChangeAt(credit, DateTime(2026, 3, 10));
      // No anchor existed yet, so nothing should have been charged and the
      // anchor should still be unset (accrueCardCredit itself sets it on
      // its normal first run).
      expect(credit.lastAccrualCutoff, isNull);
      expect(credit.currentBalance, 500);
      expect(credit.movements, isEmpty);

      credit.interestRate = 60;
      // Normal first accrual afterwards still just anchors, no back-charge.
      accrueCardCredit(credit, DateTime(2026, 3, 10));
      expect(credit.lastAccrualCutoff, isNotNull);
      expect(credit.currentBalance, 500);
      expect(credit.movements, isEmpty);
    });
  });

  group('registerCardMovement', () {
    test('a charge increases the balance', () {
      final credit = CardCredit(id: 'c1', name: 'T', lender: 'B', currentBalance: 100);
      registerCardMovement(credit, 'charge', 50, note: 'compra');
      expect(credit.currentBalance, 150);
      expect(credit.movements.last.type, 'charge');
      expect(credit.movements.last.amount, 50);
    });

    test('a payment decreases the balance and never goes below zero', () {
      final credit = CardCredit(id: 'c1', name: 'T', lender: 'B', currentBalance: 30);
      registerCardMovement(credit, 'payment', 50);
      expect(credit.currentBalance, 0);
    });
  });

  test('toDateStr/parseDateStr round-trip', () {
    final d = DateTime(2026, 3, 1);
    expect(parseDateStr(toDateStr(d)), d);
  });

  group('cycleKeyFor', () {
    test('a movement dated exactly on the cutoff day belongs to the cycle '
        'that CLOSES that day (not the one that opens)', () {
      // Regression test for the bug reported by the user: a charge made on
      // the cutoff day was inconsistently assigned to next month's cycle in
      // movements_tab.dart while card_calculator.dart's getCardCycleDates
      // treated it as part of the cycle closing that same day.
      expect(cycleKeyFor('2026-01-15', 15), '2026-01-15');
    });

    test('a movement dated the day before cutoff belongs to this month\'s '
        'closing cycle', () {
      expect(cycleKeyFor('2026-01-14', 15), '2026-01-15');
    });

    test('a movement dated the day after cutoff belongs to next month\'s '
        'closing cycle', () {
      expect(cycleKeyFor('2026-01-16', 15), '2026-02-15');
    });

    test('cutoffDay 30 keeps the real day (not clamped to 28) for a '
        '31-day month', () {
      // Regression: the old implementation clamped cutoffDay to 28,
      // disagreeing with accrueCardCredit's cutoffDateForMonth (which uses
      // the real day). A charge on the 10th with cutoffDay 30 must close
      // on the 30th, not the 28th.
      expect(cycleKeyFor('2026-04-10', 30), '2026-04-30');
    });

    test('cutoffDay 31 clamps to the last day of a 30-day month (April)', () {
      expect(cycleKeyFor('2026-04-10', 31), '2026-04-30');
    });

    test('cutoffDay 31 clamps to Feb 28 on a non-leap year', () {
      expect(cycleKeyFor('2026-02-10', 31), '2026-02-28');
    });
  });

  group('buildInstallmentMovements', () {
    test('splits total amount into N installments, each on a consecutive '
        'future statement', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final refDate = DateTime(2026, 1, 10); // antes del corte del 15

      final movements = buildInstallmentMovements(
        credit: credit,
        totalAmount: 300000,
        installments: 3,
        note: 'Compra TV',
        refDate: refDate,
      );

      expect(movements, hasLength(3));
      expect(movements[0].installmentIndex, 1);
      expect(movements[0].chargeInstallments, 3);
      expect(movements[0].statementCutoff, '2026-01-15');
      expect(movements[1].statementCutoff, '2026-02-15');
      expect(movements[2].statementCutoff, '2026-03-15');
      expect(movements[0].amount, 100000);
      expect(movements[1].amount, 100000);
      expect(movements[2].amount, 100000);
    });

    test('a purchase made exactly on the cutoff day assigns installment 1 '
        'to the SAME extracto a single-cuota charge on that day would get '
        '(via cycleKeyFor) — regression for the installment-vs-single-charge '
        'inconsistency on the cutoff day', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final refDate = DateTime(2026, 1, 15); // exactamente el día de corte

      final movements = buildInstallmentMovements(
        credit: credit,
        totalAmount: 300000,
        installments: 3,
        refDate: refDate,
      );

      expect(movements[0].statementCutoff,
          cycleKeyFor('2026-01-15', credit.cutoffDay));
      expect(movements[0].statementCutoff, '2026-01-15');
      expect(movements[1].statementCutoff, '2026-02-15');
      expect(movements[2].statementCutoff, '2026-03-15');
    });

    test('works with cutoffDay 30 (end-of-month aware, no 28-day clamp)', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 30);
      final movements = buildInstallmentMovements(
        credit: credit,
        totalAmount: 200000,
        installments: 2,
        refDate: DateTime(2026, 4, 10),
      );
      expect(movements[0].statementCutoff, '2026-04-30');
      expect(movements[1].statementCutoff, '2026-05-30');
    });

    test('rounding remainder goes entirely on the last installment — sum '
        'equals the exact original amount', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final movements = buildInstallmentMovements(
        credit: credit,
        totalAmount: 100.01,
        installments: 3,
        refDate: DateTime(2026, 1, 10),
      );

      final sum = movements.fold<double>(0, (s, m) => s + m.amount);
      expect(sum, closeTo(100.01, 0.001));
      expect(movements[0].amount, 33.34);
      expect(movements[1].amount, 33.34);
      expect(movements[2].amount, 33.33);
    });
  });

  group('registerCardCharge', () {
    test('1 installment registers a single movement with no statementCutoff '
        '(same behavior as before)', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerCardCharge(credit, 50000, note: 'Café', installments: 1,
          refDate: DateTime(2026, 1, 10));

      expect(credit.movements, hasLength(1));
      expect(credit.movements.first.statementCutoff, isNull);
      expect(credit.movements.first.chargeInstallments, isNull);
      expect(credit.currentBalance, 50000);
    });

    test('N installments registers N movements and adds the full amount to '
        'currentBalance immediately', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerCardCharge(credit, 300000, note: 'TV', installments: 3,
          refDate: DateTime(2026, 1, 10));

      expect(credit.movements, hasLength(3));
      expect(credit.currentBalance, 300000);
    });
  });

  group('getPayableSummary', () {
    test('exigible = the LATEST closed statement\'s unpaid balance; '
        'pendienteFacturar = currentBalance minus that', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 180000,
        statements: const [
          CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            paidAmount: 0,
            status: 'closed',
            createdAt: '2026-01-15',
          ),
        ],
      );

      final summary = getPayableSummary(credit);

      expect(summary.exigible, 100000);
      expect(summary.pendienteFacturar, 80000);
      expect(summary.dueDate, parseDateStr('2026-02-05'));
    });

    test('a fully paid latest statement does not count toward exigible', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 80000,
        statements: const [
          CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            paidAmount: 100000,
            status: 'paid',
            createdAt: '2026-01-15',
          ),
        ],
      );

      final summary = getPayableSummary(credit);

      expect(summary.exigible, 0);
      expect(summary.dueDate, isNull);
    });

    test('does NOT double-count across multiple unpaid statements — the '
        'balance already rolls forward via openingBalance, so exigible is '
        'only the LATEST statement\'s outstanding amount', () {
      // Regression: summing every unpaid statement double-counts debt that
      // already rolled forward into the next statement's closingBalance.
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 150000,
        statements: const [
          CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            createdAt: '2026-01-15',
          ),
          CardStatement(
            id: 's2',
            creditId: 'c1',
            cutoffDate: '2026-02-15',
            dueDate: '2026-03-07',
            closingBalance: 150000, // ya incluye los 100000 del extracto anterior
            createdAt: '2026-02-15',
          ),
        ],
      );

      final summary = getPayableSummary(credit);

      expect(summary.exigible, 150000);
      expect(summary.pendienteFacturar, 0);
      expect(summary.dueDate, parseDateStr('2026-03-07'));
    });

    test('pendienteFacturar never goes negative even if data is '
        'inconsistent (currentBalance lower than the latest exigible)', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 50000,
        statements: const [
          CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            createdAt: '2026-01-15',
          ),
        ],
      );

      final summary = getPayableSummary(credit);

      expect(summary.pendienteFacturar, 0);
    });
  });

  group('applying a payment to the latest unpaid statement', () {
    test('registerCardMovement payment reduces the latest closed '
        'statement\'s outstanding amount and marks it paid once fully '
        'covered — fixes "I paid my card but exigible stayed the same"', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 100000,
        statements: [
          const CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            createdAt: '2026-01-15',
          ),
        ],
      );

      registerCardMovement(credit, CardMovementType.payment, 100000);

      expect(credit.currentBalance, 0);
      expect(credit.statements.first.paidAmount, 100000);
      expect(credit.statements.first.status, CardStatementStatus.paid);
      expect(getPayableSummary(credit).exigible, 0);
    });

    test('a partial payment reduces exigible without marking the statement '
        'paid', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 100000,
        statements: [
          const CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            createdAt: '2026-01-15',
          ),
        ],
      );

      registerCardMovement(credit, CardMovementType.payment, 40000);

      expect(credit.statements.first.paidAmount, 40000);
      expect(credit.statements.first.status, CardStatementStatus.closed);
      expect(getPayableSummary(credit).exigible, 60000);
    });

    test('an overpayment clamps paidAmount to closingBalance (never exceeds '
        'what was actually owed on that statement)', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        currentBalance: 100000,
        statements: [
          const CardStatement(
            id: 's1',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            createdAt: '2026-01-15',
          ),
        ],
      );

      registerCardMovement(credit, CardMovementType.payment, 150000);

      expect(credit.statements.first.paidAmount, 100000);
      expect(credit.statements.first.status, CardStatementStatus.paid);
    });

  });

  group('accrueCardCredit does not close a cycle until the day AFTER its '
      'cutoff (the cutoff day itself still belongs to that cycle, per the '
      'documented "until 23:59" semantics — a movement registered later '
      'that same day must still be counted)', () {
    test('calling accrueCardCredit ON the cutoff day does not close the '
        'cycle yet', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        lastAccrualCutoff: '2026-01-15',
      );
      accrueCardCredit(credit, DateTime(2026, 2, 15)); // exactamente el corte
      expect(credit.statements, isEmpty);
      expect(credit.lastAccrualCutoff, '2026-01-15');
    });

    test('calling it the day AFTER the cutoff closes the cycle', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        lastAccrualCutoff: '2026-01-15',
      );
      accrueCardCredit(credit, DateTime(2026, 2, 16));
      expect(credit.statements, hasLength(1));
      expect(credit.statements.first.cutoffDate, '2026-02-15');
      expect(credit.lastAccrualCutoff, '2026-02-15');
    });
  });

  group('payment application regression — no closed statements', () {
    test('a payment with no closed statements yet (all charges still in the '
        'open cycle) does not touch statements', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', currentBalance: 50000);
      registerCardMovement(credit, CardMovementType.payment, 50000);
      expect(credit.statements, isEmpty);
      expect(credit.currentBalance, 0);
    });
  });

  group('accrueCardCredit creates CardStatements', () {
    test('closing a cycle with a charge inside it creates one CardStatement '
        'with the correct closingBalance and dueDate', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        paymentDueOffsetDays: 20,
        currentBalance: 50000, // sincronizado con el movimiento de abajo,
        // igual que haría registerCardMovement en producción.
        lastAccrualCutoff: '2026-01-15',
      );
      credit.movements.add(CardMovement(
        date: '2026-01-20',
        type: CardMovementType.charge,
        amount: 50000,
      ));

      accrueCardCredit(credit, DateTime(2026, 2, 16));

      expect(credit.statements, hasLength(1));
      final s = credit.statements.first;
      expect(s.cutoffDate, '2026-02-15');
      expect(s.closingBalance, 50000);
      expect(s.dueDate, '2026-03-07'); // 2026-02-15 + 20 días
    });

    test('an existing card with pre-feature debt (currentBalance set with '
        'no CardStatement history yet) seeds the first statement\'s opening '
        'balance from that debt, instead of ignoring it as if it were 0', () {
      // Regression: a real user's card already has currentBalance = 1,000,000
      // (accumulated before this feature existed) and a payment of 200,000
      // registered this cycle. The first CardStatement generated after this
      // update must reflect the REAL total owed (800,000), not just the
      // cycle's own net movement (-200,000).
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        currentBalance: 800000, // 1,000,000 pre-existing - 200,000 pagados
        lastAccrualCutoff: '2026-01-15',
      );
      credit.movements.add(CardMovement(
        date: '2026-01-20',
        type: CardMovementType.payment,
        amount: 200000,
      ));

      accrueCardCredit(credit, DateTime(2026, 2, 16));

      expect(credit.statements, hasLength(1));
      expect(credit.statements.first.closingBalance, 800000);
    });

    test('calling accrueCardCredit twice without a new cycle elapsing does '
        'not create duplicate CardStatements', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        lastAccrualCutoff: '2026-01-15',
      );
      accrueCardCredit(credit, DateTime(2026, 2, 16));
      final countAfterFirst = credit.statements.length;
      accrueCardCredit(credit, DateTime(2026, 2, 16));
      expect(credit.statements.length, countAfterFirst);
    });
  });

  group('accrueCardCredit defends against a duplicate statement id', () {
    test('does not add a second CardStatement for a cutoffDate that '
        'already has one — defends against lastAccrualCutoff ever pointing '
        'backward (e.g. an inconsistent restored backup)', () {
      final credit = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        cutoffDay: 15,
        lastAccrualCutoff: '2026-01-15',
        statements: [
          const CardStatement(
            id: 'c1-2026-02-15',
            creditId: 'c1',
            cutoffDate: '2026-02-15',
            dueDate: '2026-03-07',
            closingBalance: 50000,
            createdAt: '2026-02-15',
          ),
        ],
      );

      accrueCardCredit(credit, DateTime(2026, 2, 16));

      expect(credit.statements, hasLength(1));
    });
  });

  group('deleteCardMovement with installments', () {
    test('deleting one installment movement leaves the other installments '
        'of the same purchase untouched', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerCardCharge(credit, 300000, installments: 3, refDate: DateTime(2026, 1, 10));
      expect(credit.movements, hasLength(3));

      deleteCardMovement(credit, 1); // borra la cuota 2 de 3

      expect(credit.movements, hasLength(2));
      expect(credit.movements[0].installmentIndex, 1);
      expect(credit.movements[1].installmentIndex, 3);
      expect(credit.currentBalance, 200000); // 300000 - cuota eliminada (100000)
    });
  });
}
