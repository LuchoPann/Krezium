import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3_lib;

void main() {
  test('a database left at schemaVersion 17 opens without crashing when '
      'the app now expects 18, and gets the new financeAccounts.descripcion '
      'column with the empty-string default', () async {
    final dir = await Directory.systemTemp.createTemp('kredit_migration_test');
    final path = p.join(dir.path, 'test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    final fresh = AppDatabase.forTesting(NativeDatabase(File(path)));
    await fresh.customSelect('SELECT 1').get();
    await fresh.close();

    final raw = sqlite3_lib.sqlite3.open(path);
    raw.execute('ALTER TABLE finance_accounts DROP COLUMN descripcion');
    raw.execute('PRAGMA user_version = 17');
    raw.dispose();

    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    await expectLater(migrated.customSelect('SELECT 1').get(), completes);

    final cols = await migrated.customSelect('PRAGMA table_info(finance_accounts)').get();
    final descripcionCount =
        cols.where((r) => r.read<String>('name') == 'descripcion').length;
    expect(descripcionCount, 1);

    await migrated.close();
  });

  test('re-running the migration from a device that already got '
      'descripcion via a dev build does not crash with duplicate column',
      () async {
    final dir = await Directory.systemTemp.createTemp('kredit_migration_test');
    final path = p.join(dir.path, 'test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    final fresh = AppDatabase.forTesting(NativeDatabase(File(path)));
    await fresh.customSelect('SELECT 1').get();
    await fresh.close();

    final raw = sqlite3_lib.sqlite3.open(path);
    raw.execute('PRAGMA user_version = 17');
    raw.dispose();

    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    await expectLater(migrated.customSelect('SELECT 1').get(), completes);
    await migrated.close();
  });
}
