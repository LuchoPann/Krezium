import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3_lib;

void main() {
  test('a database left at schemaVersion 14 opens without crashing when '
      'the app now expects 17 — regression for "duplicate column name: '
      'opening_balance" (the from<15 block creates card_statements with '
      'the CURRENT schema, which already has openingBalance; the old '
      'from<17 block then tried to add it again)', () async {
    final dir = await Directory.systemTemp.createTemp('kredit_migration_test');
    final path = p.join(dir.path, 'test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. Crea el schema actual completo (v17) en un archivo real.
    final fresh = AppDatabase.forTesting(NativeDatabase(File(path)));
    await fresh.customSelect('SELECT 1').get();
    await fresh.close();

    // 2. "Retrocede" el archivo a como habría quedado un usuario en v14:
    // sin las tablas/columnas agregadas en v15/v16/v17, y con
    // user_version = 14 para forzar que AppDatabase dispare el upgrade
    // completo (14 -> 17) en el siguiente open.
    final raw = sqlite3_lib.sqlite3.open(path);
    raw.execute('DROP TABLE card_statements');
    raw.execute('DROP TABLE installment_purchases');
    raw.execute('ALTER TABLE card_movements DROP COLUMN installment_index');
    raw.execute('ALTER TABLE card_movements DROP COLUMN statement_cutoff');
    raw.execute('ALTER TABLE card_movements DROP COLUMN statement_id');
    raw.execute('ALTER TABLE card_movements DROP COLUMN installment_purchase_id');
    raw.execute('PRAGMA user_version = 14');
    raw.dispose();

    // 3. Reabre con el schemaVersion actual (17) — debe migrar sin tirar
    // excepción. Antes del fix, esto lanzaba
    // SqliteException(1): duplicate column name: opening_balance.
    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    await expectLater(migrated.customSelect('SELECT 1').get(), completes);

    final statementCols = await migrated
        .customSelect("PRAGMA table_info(card_statements)")
        .get();
    final openingBalanceCount =
        statementCols.where((r) => r.read<String>('name') == 'opening_balance').length;
    expect(openingBalanceCount, 1, reason: 'opening_balance no debe duplicarse');

    await migrated.close();
  });
}
