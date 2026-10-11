import 'package:flutter_test/flutter_test.dart';
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

}
