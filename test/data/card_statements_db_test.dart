import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('round-trips a card credit with closedStatements and installment '
      'movement fields', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bancolombia',
      cutoffDay: 15,
      currentBalance: 150000,
      closedStatements: const [
        CardStatement(
          id: 'card1-2026-01-15',
          creditId: 'card1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          paidAmount: 0,
          status: 'closed',
          createdAt: '2026-01-15',
        ),
      ],
      movements: [
        CardMovement(
          date: '2026-01-10',
          type: CardMovementType.charge,
          amount: 50000,
          chargeInstallments: 3,
          installmentIndex: 1,
          statementCutoff: '2026-01-15',
        ),
      ],
    );

    await db.upsertCredit(card);
    final all = await db.loadAllCredits();

    expect(all, hasLength(1));
    final loaded = all.first as CardCredit;
    expect(loaded.closedStatements, hasLength(1));
    expect(loaded.closedStatements.first.closingBalance, 100000);
    expect(loaded.movements, hasLength(1));
    expect(loaded.movements.first.installmentIndex, 1);
    expect(loaded.movements.first.statementCutoff, '2026-01-15');
  });

  test('clearAllData removes closedStatements', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bancolombia',
      closedStatements: const [
        CardStatement(
          id: 'card1-2026-01-15',
          creditId: 'card1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          createdAt: '2026-01-15',
        ),
      ],
    );
    await db.upsertCredit(card);
    await db.clearAllData();
    final all = await db.loadAllCredits();
    expect(all, isEmpty);
  });
}
