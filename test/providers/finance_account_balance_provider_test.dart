import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';

void main() {
  test('financeAccountBalanceProvider combina saldo, ingresos/gastos y reservas', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'A', nombre: 'A', tipo: 'efectivo', icono: 'wallet', color: '#000',
      saldoInicial: const Value(100),
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'ingresos', tipo: 'ingreso',
      monto: 200, fecha: '2026-10-01',
    ));
    await db.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'r1', accountId: Value('A'), nombre: 'Vacaciones', monto: 50, creadaEn: '2026-10-01',
    ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final balance = await container.read(financeAccountBalanceProvider('A').future);

    expect(balance.saldo, 300);
    expect(balance.ingresos, 200);
    expect(balance.gastos, 0);
    expect(balance.reservado, 50);
    expect(balance.disponibleEstimado, 250);
    expect(balance.reservasExcedenSaldo, false);

    await db.close();
  });

  test('invalidar el provider tras escribir una transacción refleja el nuevo saldo '
      '(simula lo que hace la UI tras guardar/editar/eliminar una transacción)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'A', nombre: 'A', tipo: 'efectivo', icono: 'wallet', color: '#000',
      saldoInicial: const Value(100),
    ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final inicial = await container.read(financeAccountBalanceProvider('A').future);
    expect(inicial.saldo, 100);

    // Escribir una transacción por fuera del provider — como lo hace
    // nueva_transaccion_sheet._guardar antes de invalidar.
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'ingresos', tipo: 'ingreso',
      monto: 500, fecha: '2026-10-01',
    ));

    // Sin invalidar, el FutureProvider (solo watchea databaseProvider) no
    // recalcula solo — el mismo valor cacheado seguiría siendo 100 si no se
    // invalida explícitamente, que es justo el bug que se está corrigiendo.
    container.invalidate(financeAccountBalanceProvider('A'));
    final actualizado = await container.read(financeAccountBalanceProvider('A').future);
    expect(actualizado.saldo, 600);

    await db.close();
  });

  test('financeGlobalPeriodSummaryProvider suma ingresos/gastos del mes sobre todos los registros, '
      'ignora transferencias y meses distintos', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'A', nombre: 'A', tipo: 'efectivo', icono: 'wallet', color: '#000',
    ));
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'B', nombre: 'B', tipo: 'efectivo', icono: 'wallet', color: '#000',
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'ingresos', tipo: 'ingreso',
      monto: 300, fecha: '2026-10-05',
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't2', accountId: 'B', categoryId: 'alimentacion', tipo: 'gasto',
      monto: 100, fecha: '2026-10-10',
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't3', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 999, fecha: '2026-10-12', transferToAccountId: const Value('B'),
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't4', accountId: 'A', categoryId: 'ingresos', tipo: 'ingreso',
      monto: 5000, fecha: '2026-09-01',
    ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final resumen = await container.read(financeGlobalPeriodSummaryProvider('2026-10').future);

    expect(resumen.ingresos, 300);
    expect(resumen.gastos, 100);

    await db.close();
  });
}
