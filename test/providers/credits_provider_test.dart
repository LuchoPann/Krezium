import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/date_utils.dart';
import 'package:krezium/providers/credits_provider.dart';
import 'package:krezium/providers/database_provider.dart';

void main() {
  test('registerMovement with chargeInstallments > 1 splits the charge '
      'into N movements with statementCutoff set', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final card = CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15);
    await db.upsertCredit(card);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(creditsProvider.future);
    await container.read(creditsProvider.notifier).registerMovement(
          'c1',
          CardMovementType.charge,
          300000,
          'Compra TV',
          chargeInstallments: 3,
        );

    final credits = container.read(creditsProvider).value!;
    final reloaded = credits.whereType<CardCredit>().first;
    expect(reloaded.movements, hasLength(3));
    expect(reloaded.movements.every((m) => m.statementCutoff != null), isTrue);
    expect(reloaded.currentBalance, 300000);
  });

  test('registerMovement with chargeInstallments == 1 behaves like before '
      '(single movement, no statementCutoff)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final card = CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15);
    await db.upsertCredit(card);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(creditsProvider.future);
    await container.read(creditsProvider.notifier).registerMovement(
          'c1',
          CardMovementType.charge,
          50000,
          'Café',
        );

    final credits = container.read(creditsProvider).value!;
    final reloaded = credits.whereType<CardCredit>().first;
    expect(reloaded.movements, hasLength(1));
    expect(reloaded.movements.first.statementCutoff, isNull);
  });

  test('a cycle that closes without generating any interest/fee movement '
      '(0% rate, no fee) still PERSISTS to the database — regression for '
      'change-detection that only looked at currentBalance/movements.length '
      'and missed closedStatements/lastAccrualCutoff advancing', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    // Anchor far enough in the past (2 months, cutoffDay 1) that at least
    // one cycle has unconditionally closed by "now", regardless of which
    // day this test happens to run on.
    final anchor = DateTime(now.year, now.month - 2, 1);
    final card = CardCredit(
      id: 'c1',
      name: 'Visa',
      lender: 'Bank',
      cutoffDay: 1,
      interestRate: 0,
      managementFee: 0,
      lastAccrualCutoff: toDateStr(anchor),
    );
    await db.upsertCredit(card);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(creditsProvider.future);
    // Give the fire-and-forget _accrueAndRecompute a turn to finish its
    // async work (it runs without being awaited from build()).
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final persisted = await db.loadAllCredits();
    final persistedCard = persisted.whereType<CardCredit>().first;
    expect(persistedCard.statements, isNotEmpty);
    expect(persistedCard.lastAccrualCutoff, isNot(toDateStr(anchor)));
  });
}
