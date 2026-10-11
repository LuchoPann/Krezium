import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/data/models/installment_purchase.dart';
import 'package:krezium/domain/card_statement_engine.dart';

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
        'next one, carrying the unpaid balance forward as openingBalance', () {
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
      final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
      expect(newOpen.openingBalance, 50000);
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
}
