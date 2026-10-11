import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/card_statement_engine.dart';

void main() {
  test('a movement with no statementId gets backfilled to a statement '
      'inferred from cycleKeyFor(date, cutoffDay)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    credit.movements.add(CardMovement(
      date: '2026-01-10', type: CardMovementType.charge, amount: 50000,
    ));

    migrateLegacyCardData(credit, DateTime(2026, 1, 20));

    expect(credit.movements.first.statementId, isNotNull);
    final statement = credit.statements
        .firstWhere((s) => s.id == credit.movements.first.statementId);
    expect(statement.cutoffDate, '2026-01-15');
  });

  test('a movement that already has statementId is left untouched', () {
    final credit = CardCredit(
      id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15,
      statements: [
        const CardStatement(
          id: 's1', creditId: 'c1', cutoffDate: '2026-01-15',
          dueDate: '2026-02-05', closingBalance: 0,
          status: CardStatementStatus.closed, createdAt: '2026-01-15',
        ),
      ],
      movements: [
        CardMovement(date: '2026-01-10', type: CardMovementType.charge, amount: 50000, statementId: 's1'),
      ],
    );

    migrateLegacyCardData(credit, DateTime(2026, 1, 20));

    expect(credit.movements.first.statementId, 's1');
    // El 's1' legado no se duplica; pero sí se agrega el extracto abierto
    // (ensureOpenStatement) ya que ninguno existía con status 'open'.
    expect(credit.statements.where((s) => s.id == 's1'), hasLength(1));
    expect(credit.statements.where((s) => s.status == CardStatementStatus.open), hasLength(1));
  });

  test('a legacy movement whose inferred cutoffDate is TODAY\'s open cycle '
      '(or later) gets attached to the open statement directly, not '
      'created as a NEW closed one — regression for v1 cuotas with a '
      'future statementCutoff ending up permanently marked \'closed\' '
      '(counted as already-due debt instead of pending/not-yet-due)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    // Cuota futura legada (como las que generaba buildInstallmentMovements
    // en v1): statementCutoff apunta 2 meses adelante de "hoy".
    credit.movements.add(CardMovement(
      date: '2026-01-10', type: CardMovementType.charge, amount: 30000,
      statementCutoff: '2026-03-15',
    ));

    migrateLegacyCardData(credit, DateTime(2026, 1, 20)); // hoy: antes del corte de enero

    final open = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
    expect(credit.movements.first.statementId, open.id);
    expect(credit.statements.where((s) => s.status == CardStatementStatus.closed), isEmpty);
  });

  test('a legacy movement from a PAST cycle still becomes its own closed '
      'statement, separate from the open one', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    credit.movements.add(CardMovement(
      date: '2025-11-10', type: CardMovementType.charge, amount: 50000,
    ));

    migrateLegacyCardData(credit, DateTime(2026, 1, 20));

    final open = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
    final movementStatementId = credit.movements.first.statementId;
    expect(movementStatementId, isNot(open.id));
    final closedStatement = credit.statements.firstWhere((s) => s.id == movementStatementId);
    expect(closedStatement.status, CardStatementStatus.closed);
  });

  test('ensures an open statement exists after migrating', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    migrateLegacyCardData(credit, DateTime(2026, 1, 20));
    expect(credit.statements.any((s) => s.status == CardStatementStatus.open), isTrue);
  });

  test('is a no-op on a card with nothing legacy to migrate (idempotent)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    migrateLegacyCardData(credit, DateTime(2026, 1, 20));
    final statementsCountAfterFirst = credit.statements.length;
    migrateLegacyCardData(credit, DateTime(2026, 1, 20));
    expect(credit.statements.length, statementsCountAfterFirst);
  });
}
