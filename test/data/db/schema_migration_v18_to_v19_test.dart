import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3_lib;

void main() {
  test('a database left at schemaVersion 18 (no finance_reservations table, '
      'no revision_nota column) opens without crashing when the app now '
      'expects 19, preserves its pre-existing finance data, and gets the '
      'new table/column usable', () async {
    final dir = await Directory.systemTemp.createTemp('kredit_migration_test');
    final path = p.join(dir.path, 'test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. Crear una DB fresca en el esquema actual (v19) y poblarla con datos
    // de ejemplo — cuenta + transacción — como si viniera de un dispositivo
    // real antes de recortarla a la forma v18.
    final fresh = AppDatabase.forTesting(NativeDatabase(File(path)));
    await fresh.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'acc-1',
      nombre: 'Efectivo',
      tipo: 'efectivo',
      icono: 'wallet',
      color: '#000000',
      saldoInicial: const Value(1000),
    ));
    await fresh.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 'tx-1',
      accountId: 'acc-1',
      categoryId: 'ingresos',
      tipo: 'ingreso',
      monto: 500,
      fecha: '2026-10-01',
    ));
    await fresh.close();

    // 2. Recortar la DB a la forma v18: sin finance_reservations, sin
    // revision_nota en finance_transactions, y user_version=18 — simula un
    // dispositivo real que nunca llegó a v19.
    final raw = sqlite3_lib.sqlite3.open(path);
    raw.execute('DROP TABLE finance_reservations');
    raw.execute('ALTER TABLE finance_transactions DROP COLUMN revision_nota');
    raw.execute('PRAGMA user_version = 18');
    raw.dispose();

    // 3. Reabrir con AppDatabase.forTesting (schemaVersion actual = 19) —
    // esto dispara el onUpgrade real, no onCreate.
    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    await expectLater(migrated.customSelect('SELECT 1').get(), completes);

    // Los datos previos siguen intactos.
    final cuentas = await migrated.getFinanceAccounts();
    expect(cuentas, hasLength(1));
    expect(cuentas.single.id, 'acc-1');
    expect(cuentas.single.saldoInicial, 1000);

    final txs = await migrated.getFinanceTransactions();
    expect(txs, hasLength(1));
    expect(txs.single.id, 'tx-1');
    expect(txs.single.monto, 500);

    // La tabla nueva y la columna nueva existen y son usables.
    final reservas = await migrated.getFinanceReservations('acc-1');
    expect(reservas, isEmpty);
    await migrated.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'res-1',
      accountId: Value('acc-1'),
      nombre: 'Vacaciones',
      monto: 100,
      creadaEn: '2026-10-01',
    ));
    final reservasTrasInsertar = await migrated.getFinanceReservations('acc-1');
    expect(reservasTrasInsertar, hasLength(1));

    final cols = await migrated.customSelect('PRAGMA table_info(finance_transactions)').get();
    expect(cols.map((r) => r.read<String>('name')), contains('revision_nota'));

    await migrated.close();
  });
}
