import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/data/models/installment_purchase.dart';
import 'package:krezium/domain/card_statement_engine.dart';
import 'package:krezium/domain/date_utils.dart';

void main() {
  group('computeStatementTotal', () {
    test('sums openingBalance + charges/interest/fee - payments, only for '
        'movements linked to this statement', () {
      const statement = CardStatement(
        id: 's1', creditId: 'c1', cutoffDate: '2026-02-15',
        dueDate: '2026-03-07', closingBalance: 0,
        status: CardStatementStatus.open, createdAt: '2026-01-15',
      );
      final other = CardStatement(
        id: 's0', creditId: 'c1', cutoffDate: '2026-01-15',
        dueDate: '2026-02-05', closingBalance: 0,
        status: CardStatementStatus.closed, createdAt: '2026-01-15',
      );
      final movements = [
        CardMovement(date: '2026-01-20', type: CardMovementType.charge, amount: 50000, statementId: 's1'),
        CardMovement(date: '2026-01-25', type: CardMovementType.payment, amount: 10000, statementId: 's1'),
        CardMovement(date: '2026-01-10', type: CardMovementType.charge, amount: 999999, statementId: other.id),
      ];

      final total = computeStatementTotal(statement, movements);

      expect(total, 40000);
    });

    test('includes openingBalance', () {
      const statement = CardStatement(
        id: 's2', creditId: 'c1', cutoffDate: '2026-03-15',
        dueDate: '2026-04-05', closingBalance: 0, openingBalance: 100000,
        status: CardStatementStatus.open, createdAt: '2026-02-15',
      );
      expect(computeStatementTotal(statement, const []), 100000);
    });
  });

  group('ensureOpenStatement', () {
    test('creates an open statement for a brand-new card with no '
        'statements yet', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));

      expect(credit.statements, hasLength(1));
      expect(open.status, CardStatementStatus.open);
      expect(open.cutoffDate, '2026-01-15');
      expect(open.openingBalance, 0);
    });

    test('returns the existing open statement without creating a '
        'duplicate', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final first = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      final second = ensureOpenStatement(credit, DateTime(2026, 1, 12));
      expect(credit.statements, hasLength(1));
      expect(second.id, first.id);
    });
  });

  group('closeCurrentCycleIfDue', () {
    test('does nothing before the cutoff day arrives', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      ensureOpenStatement(credit, DateTime(2026, 1, 10));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 14));
      expect(credit.statements, hasLength(1));
      expect(credit.statements.first.status, CardStatementStatus.open);
    });

    test('closes the open statement the day after its cutoff and opens the '
        'next one with a clean openingBalance — no carry-forward, since '
        'total unpaid debt is always the sum across ALL unpaid statements '
        '(see recomputeCardBalance/getPayableSummary), never a number '
        'duplicated between the closed statement and the next one', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(
        date: '2026-01-12', type: CardMovementType.charge, amount: 50000,
        statementId: open.id,
      ));

      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

      expect(credit.statements, hasLength(2));
      final closed = credit.statements.firstWhere((s) => s.id == open.id);
      expect(closed.status, CardStatementStatus.closed);
      expect(computeStatementTotal(closed, credit.movements), 50000);
      final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      expect(newOpen.openingBalance, 0);
      expect(newOpen.cutoffDate, '2026-02-15');
    });

    test('a closed statement whose total is 0 or less is marked paid, not '
        'closed', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      ensureOpenStatement(credit, DateTime(2026, 1, 10));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
      expect(closed.status, CardStatementStatus.paid);
    });

    test('bills the next pending cuota of every InstallmentPurchase into the '
        'newly-opened statement when a cycle closes', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.installmentPurchases.add(InstallmentPurchase(
        id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
        totalAmount: 90000, installments: 3,
        perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
        installmentsBilled: 1,
        createdAt: '2026-01-10',
      ));
      credit.movements.add(CardMovement(
        date: '2026-01-10', type: CardMovementType.charge, amount: 30000,
        statementId: open.id, installmentPurchaseId: 'ip1',
        chargeInstallments: 3, installmentIndex: 1,
      ));

      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

      final purchase = credit.installmentPurchases.first;
      expect(purchase.installmentsBilled, 2);
      final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      final cuota2 = credit.movements.firstWhere((m) => m.installmentIndex == 2);
      expect(cuota2.statementId, newOpen.id);
      expect(cuota2.amount, 30000);
      expect(cuota2.installmentPurchaseId, 'ip1');
    });

    test('a purchase that is already fully billed is not touched when a '
        'cycle closes', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.installmentPurchases.add(InstallmentPurchase(
        id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
        totalAmount: 60000, installments: 2,
        perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
        installmentsBilled: 2,
        createdAt: '2026-01-10',
      ));

      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

      expect(credit.installmentPurchases.first.installmentsBilled, 2);
      expect(credit.movements, isEmpty);
    });
  });

  group('registerCardCharge', () {
    test('creates a single charge linked to the open statement', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerCardCharge(credit, 50000, note: 'Café', refDate: DateTime(2026, 1, 10));

      expect(credit.movements, hasLength(1));
      final open = credit.statements.single;
      expect(credit.movements.first.statementId, open.id);
      expect(computeStatementTotal(open, credit.movements), 50000);
    });
  });

  group('registerInstallmentPurchase', () {
    test('creates the purchase and bills cuota 1 immediately into the open '
        'statement', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final purchase = registerInstallmentPurchase(
        credit, 90000, 3, note: 'TV', refDate: DateTime(2026, 1, 10),
      );

      expect(credit.installmentPurchases, hasLength(1));
      expect(purchase.installmentsBilled, 1);
      expect(credit.movements, hasLength(1));
      expect(credit.movements.first.installmentIndex, 1);
      expect(credit.movements.first.installmentPurchaseId, purchase.id);
      final open = credit.statements.single;
      expect(computeStatementTotal(open, credit.movements), 30000);
    });

    test('rounding remainder goes on lastInstallmentAmount, sum equals the '
        'exact total', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final purchase = registerInstallmentPurchase(credit, 100.01, 3, refDate: DateTime(2026, 1, 10));
      final sum = purchase.perInstallmentAmount * 2 + purchase.lastInstallmentAmount;
      expect(sum, closeTo(100.01, 0.001));
    });

    test('a purchase made exactly on the cutoff day bills cuota 1 into the '
        'statement that closes THAT day — same as a single-cuota charge '
        'would (both use ensureOpenStatement/getCardCycleDates consistently)', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final purchase = registerInstallmentPurchase(credit, 90000, 3, refDate: DateTime(2026, 1, 15));
      final open = credit.statements.single;
      expect(open.cutoffDate, '2026-01-15');
      expect(credit.movements.first.statementId, open.id);
    });
  });

  group('registerCardPayment — no double-subtracting (C2 regression)', () {
    test('a partial payment reduces the live total by exactly the amount '
        'paid, not twice — regression for paidAmount being subtracted both '
        'via the payment movement AND again as a separate field', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 100000, statementId: open.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      final closed = credit.statements.firstWhere((s) => s.status == CardStatementStatus.closed);

      registerCardPayment(credit, 40000, refDate: DateTime(2026, 1, 20));

      final stillClosed = credit.statements.firstWhere((s) => s.id == closed.id);
      expect(computeStatementTotal(stillClosed, credit.movements), 60000);
      recomputeCardBalance(credit);
      expect(credit.currentBalance, 60000);
      expect(getPayableSummary(credit).exigible, 60000);
    });

    test('two sequential partial payments reduce correctly and the second '
        'one that completes the statement marks it paid with the exact '
        'remaining amount, not an inflated one', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 100000, statementId: open.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

      registerCardPayment(credit, 40000, refDate: DateTime(2026, 1, 20));
      registerCardPayment(credit, 60000, refDate: DateTime(2026, 1, 25));

      final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
      expect(closed.status, CardStatementStatus.paid);
      recomputeCardBalance(credit);
      expect(credit.currentBalance, 0);
    });
  });

  group('status is re-derived live, never stuck (C3/I4 regression)', () {
    test('a statement that would be skipped by FIFO because it is already '
        'settled (owed <= 0) gets its status refreshed to paid instead of '
        'staying closed forever', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 50000, statementId: open.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      final closed = credit.statements.firstWhere((s) => s.status == CardStatementStatus.closed);
      // Paga manualmente de más vía movimiento directo (simula una
      // corrección manual) para dejarlo "ya saldado" sin pasar por
      // registerCardPayment.
      credit.movements.add(CardMovement(date: '2026-01-13', type: CardMovementType.payment, amount: 50000, statementId: closed.id));

      // Un pago nuevo cualquiera debe refrescar el estado de TODOS los
      // extractos cerrados, incluso los que no reciben el abono.
      registerCardPayment(credit, 0.01, refDate: DateTime(2026, 1, 20));

      final refreshed = credit.statements.firstWhere((s) => s.id == closed.id);
      expect(refreshed.status, CardStatementStatus.paid);
    });

    test('deleting a payment from a paid statement brings its debt back '
        'into exigible instead of disappearing forever', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 100000, statementId: open.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      registerCardPayment(credit, 100000, refDate: DateTime(2026, 1, 20));
      expect(getPayableSummary(credit).exigible, 0);

      // El índice del movimiento de pago recién agregado.
      final paymentIndex = credit.movements.indexWhere((m) => m.type == CardMovementType.payment);
      deleteCardMovement(credit, paymentIndex);
      recomputeCardBalance(credit);

      expect(getPayableSummary(credit).exigible, 100000);
    });
  });

  group('overpayment carries forward as a credit (I1 regression)', () {
    test('an overpayment on the open statement survives the next close as '
        'a negative openingBalance, reducing the next cycle\'s total — not '
        'lost when the overpaid statement closes as paid', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-11', type: CardMovementType.charge, amount: 100000, statementId: open.id));
      registerCardPayment(credit, 150000, refDate: DateTime(2026, 1, 12));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

      final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      expect(newOpen.openingBalance, -50000);

      registerCardCharge(credit, 80000, refDate: DateTime(2026, 1, 20));
      expect(computeStatementTotal(newOpen, credit.movements), 30000);
    });
  });

  group('interest accrues on the full outstanding balance, not just the '
      'open cycle (I2 regression)', () {
    test('a cycle that closes with NO new charges of its own still accrues '
        'interest, based on the still-unpaid closed statement from before '
        '— not zero, which is what the open cycle\'s own (empty) total '
        'would otherwise suggest', () {
      final credit = CardCredit(
        id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15,
        interestRate: 36.5, // tasa diaria efectiva, ver interest_rate.dart
      );
      final open1 = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 100000, statementId: open1.id));
      // Cierra el primer ciclo (genera su propio interés sobre los 100000
      // recién cargados — esperado, no es lo que probamos aquí).
      closeCurrentCycleIfDue(credit, DateTime(2026, 2, 16));
      final movementsBeforeSecondClose = credit.movements.length;

      // El segundo ciclo cierra SIN ningún cargo nuevo propio — su propio
      // computeStatementTotal sería 0 si no se suma la deuda ya cerrada.
      closeCurrentCycleIfDue(credit, DateTime(2026, 3, 16));

      final newMovements = credit.movements.skip(movementsBeforeSecondClose).toList();
      final secondCloseInterest = newMovements.where((m) => m.type == CardMovementType.interest).toList();
      expect(secondCloseInterest, isNotEmpty);
      expect(secondCloseInterest.first.amount, greaterThan(0));
    });
  });

  group('registerCardPayment', () {
    CardCredit cardWithOneClosedStatement(double closingTotal) {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(
        date: '2026-01-12', type: CardMovementType.charge, amount: closingTotal,
        statementId: open.id,
      ));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      return credit;
    }

    test('a payment that exactly covers the oldest closed statement marks '
        'it paid', () {
      final credit = cardWithOneClosedStatement(100000);
      registerCardPayment(credit, 100000, refDate: DateTime(2026, 1, 20));

      final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
      expect(closed.paidAmount, 100000);
      expect(closed.status, CardStatementStatus.paid);
    });

    test('an overpayment carries the remainder into the open statement as '
        'an advance payment, not lost', () {
      final credit = cardWithOneClosedStatement(100000);
      registerCardPayment(credit, 150000, refDate: DateTime(2026, 1, 20));

      final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
      expect(closed.paidAmount, 100000);
      final open = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      expect(computeStatementTotal(open, credit.movements), -50000);
    });

    test('a partial payment reduces the oldest closed statement without '
        'marking it paid', () {
      final credit = cardWithOneClosedStatement(100000);
      registerCardPayment(credit, 40000, refDate: DateTime(2026, 1, 20));

      final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
      expect(closed.paidAmount, 40000);
      expect(closed.status, CardStatementStatus.closed);
    });
  });

  group('recomputeCardBalance', () {
    test('two unpaid closed statements sum correctly without '
        'double-counting — regression for the v1 bug where carrying a '
        'balance forward via openingBalance duplicated debt once a later '
        'payment settled the older statement directly', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open1 = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 100000, statementId: open1.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      final open2 = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      credit.movements.add(CardMovement(date: '2026-02-12', type: CardMovementType.charge, amount: 50000, statementId: open2.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 2, 16));

      recomputeCardBalance(credit);
      expect(credit.currentBalance, 150000);

      registerCardPayment(credit, 100000, refDate: DateTime(2026, 2, 20));
      recomputeCardBalance(credit);
      expect(credit.currentBalance, 50000);
    });

    test('currentBalance = sum of unpaid statements + remaining unbilled '
        'cuotas of installment purchases', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(
        date: '2026-01-10', type: CardMovementType.charge, amount: 20000,
        statementId: open.id,
      ));
      credit.installmentPurchases.add(InstallmentPurchase(
        id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
        totalAmount: 90000, installments: 3,
        perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
        installmentsBilled: 1,
        createdAt: '2026-01-10',
      ));

      recomputeCardBalance(credit);

      expect(credit.currentBalance, 80000);
    });
  });

  group('getPayableSummary v2', () {
    test('exigible = suma de extractos cerrados sin pagar; dueDate = el '
        'más antiguo de ellos (vence primero)', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 50000, statementId: open.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      final open2 = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      credit.movements.add(CardMovement(date: '2026-02-12', type: CardMovementType.charge, amount: 30000, statementId: open2.id));
      closeCurrentCycleIfDue(credit, DateTime(2026, 2, 16));

      final summary = getPayableSummary(credit);

      expect(summary.exigible, 80000);
      expect(summary.dueDate, parseDateStr(credit.statements.firstWhere((s) => s.cutoffDate == '2026-01-15').dueDate));
    });

    test('pendienteFacturar = total del extracto abierto + cuotas sin '
        'facturar', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(date: '2026-01-10', type: CardMovementType.charge, amount: 10000, statementId: open.id));
      credit.installmentPurchases.add(InstallmentPurchase(
        id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
        totalAmount: 60000, installments: 2,
        perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
        installmentsBilled: 1, createdAt: '2026-01-10',
      ));

      final summary = getPayableSummary(credit);

      expect(summary.pendienteFacturar, 40000);
    });
  });

  group('deleteCardMovement v2', () {
    test('removing a charge recomputes the statement total — no manual '
        'delta tracking needed', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerCardCharge(credit, 50000, refDate: DateTime(2026, 1, 10));
      registerCardCharge(credit, 20000, refDate: DateTime(2026, 1, 11));
      recomputeCardBalance(credit);
      expect(credit.currentBalance, 70000);

      deleteCardMovement(credit, 0);
      recomputeCardBalance(credit);

      expect(credit.movements, hasLength(1));
      expect(credit.currentBalance, 20000);
    });

    test('deleting the most recently billed cuota of an InstallmentPurchase '
        'decrements installmentsBilled so it can be re-billed next close', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final purchase = registerInstallmentPurchase(credit, 90000, 3, refDate: DateTime(2026, 1, 10));
      expect(purchase.installmentsBilled, 1);

      deleteCardMovement(credit, 0);

      expect(purchase.installmentsBilled, 0);
    });
  });

  group('projectInstallmentSchedule', () {
    test('returns one entry per cuota: billed ones use the past, pending '
        'ones project forward one statement cycle apart', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final purchase = registerInstallmentPurchase(
          credit, 90000, 3, refDate: DateTime(2026, 1, 10));
      // registerInstallmentPurchase abre el extracto vía ensureOpenStatement
      // con corte 2026-01-15 (el próximo corte ≥ la fecha de compra).

      final schedule = projectInstallmentSchedule(purchase, credit);

      expect(schedule, hasLength(3));
      expect(schedule[0].number, 1);
      expect(schedule[0].billed, isTrue);
      expect(schedule[0].amount, 30000);
      expect(schedule[0].statementCutoff, DateTime(2026, 1, 15));

      expect(schedule[1].number, 2);
      expect(schedule[1].billed, isFalse);
      expect(schedule[1].amount, 30000);
      expect(schedule[1].statementCutoff, DateTime(2026, 2, 15));

      expect(schedule[2].number, 3);
      expect(schedule[2].billed, isFalse);
      // La última cuota absorbe el remanente de redondeo.
      expect(schedule[2].amount, purchase.lastInstallmentAmount);
      expect(schedule[2].statementCutoff, DateTime(2026, 3, 15));
    });

    test('after the next cycle closes and bills cuota 2, cuota 1 still '
        'projects to its own past statement and cuota 3 keeps advancing', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final purchase = registerInstallmentPurchase(
          credit, 90000, 3, refDate: DateTime(2026, 1, 10));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

      final schedule = projectInstallmentSchedule(purchase, credit);

      expect(purchase.installmentsBilled, 2);
      expect(schedule[0].billed, isTrue);
      expect(schedule[0].statementCutoff, DateTime(2026, 1, 15));
      expect(schedule[1].billed, isTrue);
      expect(schedule[1].statementCutoff, DateTime(2026, 2, 15));
      expect(schedule[2].billed, isFalse);
      expect(schedule[2].statementCutoff, DateTime(2026, 3, 15));
    });
  });

  group('projectFutureStatements', () {
    test('groups every pending cuota (across all purchases) by projected '
        'cutoff date into one virtual future statement per cycle', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerInstallmentPurchase(credit, 90000, 3, refDate: DateTime(2026, 1, 10));

      final future = projectFutureStatements(credit);

      // Cuota 1 ya facturada (en el extracto real de corte 2026-01-15);
      // quedan cuota 2 (corte 2026-02-15) y cuota 3 (corte 2026-03-15).
      expect(future, hasLength(2));
      expect(future[0].cutoffDate, DateTime(2026, 2, 15));
      expect(future[0].lines, hasLength(1));
      expect(future[0].lines.single.amount, 30000);
      expect(future[0].totalAmount, 30000);
      expect(future[1].cutoffDate, DateTime(2026, 3, 15));
      expect(future[1].totalAmount, future[1].lines.single.amount);
    });

    test('two purchases whose next pending cuota lands on the same cutoff '
        'are merged into a single virtual statement', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerInstallmentPurchase(credit, 60000, 2, refDate: DateTime(2026, 1, 10));
      registerInstallmentPurchase(credit, 40000, 2, refDate: DateTime(2026, 1, 11));

      final future = projectFutureStatements(credit);

      expect(future, hasLength(1));
      expect(future[0].cutoffDate, DateTime(2026, 2, 15));
      expect(future[0].lines, hasLength(2));
      expect(future[0].totalAmount, 50000);
    });

    test('a fully billed purchase contributes nothing', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      registerCardCharge(credit, 10000, refDate: DateTime(2026, 1, 10));

      final future = projectFutureStatements(credit);

      expect(future, isEmpty);
    });
  });

  group('proximoExtractoAmount', () {
    test('sin extracto exigible, muestra lo acumulado en el ciclo abierto '
        '(el que se convertirá en el próximo extracto a pagar)', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(
        date: '2026-01-12', type: CardMovementType.charge, amount: 75000,
        statementId: open.id,
      ));

      expect(proximoExtractoAmount(credit), 75000);
    });

    test('con extracto ya exigible (cerrado, sin pagar), ese es "lo que se '
        'avecina" — no el ciclo abierto actual, que es un periodo distinto', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      credit.movements.add(CardMovement(
        date: '2026-01-12', type: CardMovementType.charge, amount: 100000,
        statementId: open.id,
      ));
      closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
      final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      credit.movements.add(CardMovement(
        date: '2026-01-20', type: CardMovementType.charge, amount: 20000,
        statementId: newOpen.id,
      ));

      expect(proximoExtractoAmount(credit), 100000);
    });

    test('tarjeta recién creada sin ningún movimiento: el ciclo abierto da 0', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      ensureOpenStatement(credit, DateTime(2026, 1, 10));

      expect(proximoExtractoAmount(credit), 0);
    });
  });
}
