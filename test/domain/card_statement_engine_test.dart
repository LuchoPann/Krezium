import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
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
}
