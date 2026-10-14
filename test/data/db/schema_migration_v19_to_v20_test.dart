import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3_lib;

void main() {
  test('a database left at schemaVersion 19 (finance_reservations sin '
      'monto_objetivo/fecha_limite/estado) opens without crashing when the '
      'app now expects 20, preserves pre-existing reservas, and gets the '
      'new columns usable with safe defaults', () async {
    final dir = await Directory.systemTemp.createTemp('kredit_migration_test');
    final path = p.join(dir.path, 'test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. DB fresca en el esquema actual (v20) con una cuenta y una reserva
    // ya existente (como si viniera de un dispositivo real en v19, antes de
    // recortarla a esa forma).
    final fresh = AppDatabase.forTesting(NativeDatabase(File(path)));
    await fresh.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'acc-1', nombre: 'Efectivo', tipo: 'efectivo', icono: 'wallet', color: '#000000',
    ));
    await fresh.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'res-1', accountId: Value('acc-1'), nombre: 'Vacaciones', monto: 100, creadaEn: '2026-10-01',
    ));
    await fresh.close();

    // 2. Recortar a la forma v19: sin las 3 columnas nuevas, user_version=19.
    final raw = sqlite3_lib.sqlite3.open(path);
    raw.execute('ALTER TABLE finance_reservations DROP COLUMN monto_objetivo');
    raw.execute('ALTER TABLE finance_reservations DROP COLUMN fecha_limite');
    raw.execute('ALTER TABLE finance_reservations DROP COLUMN estado');
    raw.execute('PRAGMA user_version = 19');
    raw.dispose();

    // 3. Reabrir con el schemaVersion actual (20) — dispara el onUpgrade real.
    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    await expectLater(migrated.customSelect('SELECT 1').get(), completes);

    // La reserva previa sigue intacta y su columna nueva trae un default
    // seguro (0/'activa'), no null ni una excepción.
    final reservas = await migrated.getFinanceReservations('acc-1');
    expect(reservas, hasLength(1));
    expect(reservas.single.id, 'res-1');
    expect(reservas.single.monto, 100);
    expect(reservas.single.montoObjetivo, 0);
    expect(reservas.single.fechaLimite, null);
    expect(reservas.single.estado, 'activa');

    // Las columnas nuevas son usables de inmediato (crear una meta completa).
    await migrated.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'res-2', accountId: Value('acc-1'), nombre: 'Fondo de emergencia', monto: 0, creadaEn: '2026-10-01',
      montoObjetivo: const Value(2000000), fechaLimite: const Value('2027-01-01'),
    ));
    final reservasTrasInsertar = await migrated.getFinanceReservations('acc-1');
    expect(reservasTrasInsertar, hasLength(2));

    await migrated.close();
  });
}
