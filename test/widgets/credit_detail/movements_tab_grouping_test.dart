import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/widgets/credit_detail/movements_tab.dart';

void main() {
  test('groupMovementsByStatement groups by statementId, in the same order '
      'as the statements list passed in', () {
    const s1 = CardStatement(id: 's1', creditId: 'c1', cutoffDate: '2026-01-15', dueDate: '2026-02-05', closingBalance: 0, status: CardStatementStatus.closed, createdAt: '2026-01-15');
    const s2 = CardStatement(id: 's2', creditId: 'c1', cutoffDate: '2026-02-15', dueDate: '2026-03-07', closingBalance: 0, status: CardStatementStatus.open, createdAt: '2026-02-15');
    final movements = [
      CardMovement(date: '2026-01-20', type: CardMovementType.charge, amount: 50000, statementId: 's1'),
      CardMovement(date: '2026-02-20', type: CardMovementType.charge, amount: 30000, statementId: 's2'),
    ];

    final groups = groupMovementsByStatement([s1, s2], movements);

    expect(groups[0].statement.id, 's1');
    expect(groups[0].movements, hasLength(1));
    expect(groups[1].statement.id, 's2');
  });

  test('a statement with no movements still appears (empty group) — a '
      'brand-new open cycle with nothing charged yet is still visible', () {
    const s1 = CardStatement(id: 's1', creditId: 'c1', cutoffDate: '2026-01-15', dueDate: '2026-02-05', closingBalance: 0, status: CardStatementStatus.open, createdAt: '2026-01-15');
    final groups = groupMovementsByStatement([s1], const []);
    expect(groups, hasLength(1));
    expect(groups.first.movements, isEmpty);
  });
}
