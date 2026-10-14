import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3_lib;

void main() {
  test('a database left at schemaVersion 20 (finance_reservations sin '
      'modalidad, accountId NOT NULL, sin finance_goal_movements) opens '
      'without crashing when the app now expects 21, preserves la meta '
      'vinculada existente con su accountId intacto, y la deja con '
      "modalidad = 'vinculada' por default", () async {
    final dir = await Directory.systemTemp.createTemp('kredit_migration_test');
    final path = p.join(dir.path, 'test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. DB fresca en el esquema actual (v21) con una cuenta y una meta
    // vinculada ya existente (como si viniera de un dispositivo real en
    // v20, antes de recortarla a esa forma).
    final fresh = AppDatabase.forTesting(NativeDatabase(File(path)));
    await fresh.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'acc-1', nombre: 'Efectivo', tipo: 'efectivo', icono: 'wallet', color: '#000000',
    ));
    await fresh.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'res-1', accountId: const Value('acc-1'), nombre: 'Vacaciones', monto: 100, creadaEn: '2026-10-01',
    ));
    await fresh.close();

    // 2. Recortar a la forma v20: accountId NOT NULL, sin 'modalidad',
    // sin la tabla finance_goal_movements, user_version = 20.
    final raw = sqlite3_lib.sqlite3.open(path);
    raw.execute('''
      CREATE TABLE finance_reservations_v20 (
        id TEXT NOT NULL PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES finance_accounts(id),
        nombre TEXT NOT NULL,
        monto REAL NOT NULL,
        creada_en TEXT NOT NULL,
        monto_objetivo REAL NOT NULL DEFAULT 0,
        fecha_limite TEXT NULL,
        estado TEXT NOT NULL DEFAULT 'activa'
      )
    ''');
    raw.execute('''
      INSERT INTO finance_reservations_v20
      SELECT id, account_id, nombre, monto, creada_en, monto_objetivo,
             fecha_limite, estado
      FROM finance_reservations
    ''');
    raw.execute('DROP TABLE finance_reservations');
    raw.execute(
        'ALTER TABLE finance_reservations_v20 RENAME TO finance_reservations');
    raw.execute('DROP TABLE IF EXISTS finance_goal_movements');
    raw.execute('PRAGMA user_version = 20');
    raw.dispose();

    // 3. Reabrir con el schemaVersion actual (21) — dispara el onUpgrade real.
    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    await expectLater(migrated.customSelect('SELECT 1').get(), completes);

    final reservas = await migrated.getFinanceReservations('acc-1');
    expect(reservas, hasLength(1));
    expect(reservas.single.id, 'res-1');
    expect(reservas.single.accountId, 'acc-1');
    expect(reservas.single.modalidad, 'vinculada');

    // accountId ahora acepta null (meta virtual) sin romper nada.
    await migrated.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'res-2', nombre: 'Portátil', monto: 0, creadaEn: '2026-10-14',
      modalidad: const Value('virtual'),
    ));

    // La tabla nueva de historial es usable de inmediato.
    await migrated.into(migrated.financeGoalMovements).insert(
          FinanceGoalMovementsCompanion.insert(
            id: 'mov-1',
            goalId: 'res-1',
            tipo: 'aporte',
            monto: 50,
            fecha: '2026-10-14',
            saldoResultante: 150,
          ),
        );
    final movimientos = await (migrated.select(migrated.financeGoalMovements)
          ..where((t) => t.goalId.equals('res-1')))
        .get();
    expect(movimientos, hasLength(1));
    expect(movimientos.single.saldoResultante, 150);

    await migrated.close();
  });
}
