import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';

void main() {
  test('clasifica transferencias históricas: reconstruible vs. dudosa', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'A', nombre: 'A', tipo: 'efectivo', icono: 'wallet', color: '#000',
    ));
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'B', nombre: 'B', tipo: 'efectivo', icono: 'wallet', color: '#000',
    ));
    // Reconstruible: tiene destino válido y existente, el bug de cálculo ya
    // se corrigió en Tasks 2-4 — esta transferencia ya funciona sola, no
    // necesita modificarse, solo se cuenta como reconstruible.
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 50, fecha: '2026-01-01', transferToAccountId: const Value('B'),
    ));
    // Dudosa: transferencia sin destino registrado.
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't2', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 20, fecha: '2026-01-02',
    ));
    // Dudosa: destino apunta a una cuenta que ya no existe. Se desactiva
    // temporalmente el chequeo de FK para simular datos históricos
    // corruptos (previos a esta fase), ya que el schema actual impediría
    // insertar una referencia colgante directamente.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't3', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 15, fecha: '2026-01-03', transferToAccountId: const Value('inexistente'),
    ));
    await db.customStatement('PRAGMA foreign_keys = ON');

    final audit = await auditarTransferenciasHistoricas(db);
    expect(audit.reconstruibles, 1);
    expect(audit.dudosas, 2);
    expect(audit.noReconstruibles, 0);
    expect(audit.idsDudosos, containsAll(['t2', 't3']));

    await aplicarSenalamientoTransferenciasDudosas(db);
    final t2 = (await db.getFinanceTransactions()).firstWhere((t) => t.id == 't2');
    expect(t2.revisionNota, isNotNull);
    final t1 = (await db.getFinanceTransactions()).firstWhere((t) => t.id == 't1');
    expect(t1.revisionNota, isNull); // la reconstruible no se toca

    // Idempotencia: repetir no duplica ni cambia nada más.
    await aplicarSenalamientoTransferenciasDudosas(db);
    final t2Otra = (await db.getFinanceTransactions()).firstWhere((t) => t.id == 't2');
    expect(t2Otra.revisionNota, t2.revisionNota);

    await db.close();
  });
}
