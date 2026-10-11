import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/data/models/installment_purchase.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('round-trips a card with an InstallmentPurchase and a movement '
      'linked to it via statementId/installmentPurchaseId', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bank',
      installmentPurchases: [
        InstallmentPurchase(
          id: 'ip1',
          creditId: 'card1',
          purchaseDate: '2026-01-10',
          totalAmount: 100000,
          installments: 3,
          perInstallmentAmount: 33333,
          lastInstallmentAmount: 33334,
          createdAt: '2026-01-10',
        ),
      ],
      movements: [
        CardMovement(
          date: '2026-01-10',
          type: CardMovementType.charge,
          amount: 33333,
          statementId: 's1',
          installmentPurchaseId: 'ip1',
          chargeInstallments: 3,
          installmentIndex: 1,
        ),
      ],
    );

    await db.upsertCredit(card);
    final all = await db.loadAllCredits();

    expect(all, hasLength(1));
    final loaded = all.first as CardCredit;
    expect(loaded.installmentPurchases, hasLength(1));
    expect(loaded.installmentPurchases.first.totalAmount, 100000);
    expect(loaded.movements.first.statementId, 's1');
    expect(loaded.movements.first.installmentPurchaseId, 'ip1');
  });

  test('clearAllData removes installmentPurchases', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bank',
      installmentPurchases: [
        InstallmentPurchase(
          id: 'ip1',
          creditId: 'card1',
          purchaseDate: '2026-01-10',
          totalAmount: 100000,
          installments: 2,
          perInstallmentAmount: 50000,
          lastInstallmentAmount: 50000,
          createdAt: '2026-01-10',
        ),
      ],
    );
    await db.upsertCredit(card);
    await db.clearAllData();
    expect(await db.loadAllCredits(), isEmpty);
  });
}
