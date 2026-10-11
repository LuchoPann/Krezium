import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/providers/credits_provider.dart';
import 'package:krezium/providers/database_provider.dart';

void main() {
  test('addCredit creates the open statement immediately for a brand-new '
      'card — not just on the next app launch', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.future);

    final card = CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15);
    await container.read(creditsProvider.notifier).addCredit(card);

    final credits = container.read(creditsProvider).value!;
    final saved = credits.whereType<CardCredit>().first;
    expect(saved.statements, hasLength(1));
    expect(saved.statements.first.status, CardStatementStatus.open);
  });

  test('registerMovement with chargeInstallments > 1 creates an '
      'InstallmentPurchase and bills only cuota 1 immediately', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.notifier).addCredit(
        CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15));

    await container.read(creditsProvider.notifier).registerMovement(
          'c1', CardMovementType.charge, 90000, 'TV', chargeInstallments: 3,
        );

    final credits = container.read(creditsProvider).value!;
    final card = credits.whereType<CardCredit>().first;
    expect(card.installmentPurchases, hasLength(1));
    expect(card.installmentPurchases.first.installmentsBilled, 1);
    expect(card.movements, hasLength(1));
  });

  test('registerMovement payment applies via the new FIFO engine', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.notifier).addCredit(
        CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15));
    final notifier = container.read(creditsProvider.notifier);
    await notifier.registerMovement('c1', CardMovementType.charge, 50000, 'Café');

    await notifier.registerMovement('c1', CardMovementType.payment, 50000, 'Pago');

    final credits = container.read(creditsProvider).value!;
    final card = credits.whereType<CardCredit>().first;
    expect(card.currentBalance, 0);
  });

  test('deleteMovement removes the movement and recomputes currentBalance '
      '(no leftover manual delta)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.notifier).addCredit(
        CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15));
    final notifier = container.read(creditsProvider.notifier);
    await notifier.registerMovement('c1', CardMovementType.charge, 50000, 'Café');

    await notifier.deleteMovement('c1', 0);

    final credits = container.read(creditsProvider).value!;
    final card = credits.whereType<CardCredit>().first;
    expect(card.movements, isEmpty);
    expect(card.currentBalance, 0);
  });
}
