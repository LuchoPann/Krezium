import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _crearCuenta(AppDatabase db, String id) => db.upsertFinanceAccount(
      FinanceAccountsCompanion.insert(
        id: id, nombre: id, tipo: 'efectivo', icono: 'wallet', color: '#000000',
      ),
    );

void main() {
  test('getFinanceTransactionsInvolvingLibro trae origen y destino de transferencias', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await _crearCuenta(db, 'B');
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 50, fecha: '2026-10-01', transferToAccountId: const Value('B'),
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't2', accountId: 'A', categoryId: 'alimentacion', tipo: 'gasto',
      monto: 10, fecha: '2026-10-02',
    ));

    final paraA = await db.getFinanceTransactionsInvolvingLibro(libroId: 'A');
    final paraB = await db.getFinanceTransactionsInvolvingLibro(libroId: 'B');

    expect(paraA.map((t) => t.id), containsAll(['t1', 't2']));
    expect(paraB.map((t) => t.id), ['t1']);
    await db.close();
  });

  test('countTransactionsForAccount cuenta origen y destino', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await _crearCuenta(db, 'B');
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 50, fecha: '2026-10-01', transferToAccountId: const Value('B'),
    ));
    expect(await db.countTransactionsForAccount('A'), 1);
    expect(await db.countTransactionsForAccount('B'), 1);
    expect(await db.countTransactionsForAccount('C'), 0);
    await db.close();
  });

  test('archivar oculta de la lista por defecto pero conserva el registro', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await db.archiveFinanceAccount('A');
    expect(await db.getFinanceAccounts(), isEmpty);
    final conArchivadas = await db.getFinanceAccounts(incluirArchivadas: true);
    expect(conArchivadas.single.activa, false);
    await db.close();
  });

  test('reactivar vuelve a mostrar el registro', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await db.archiveFinanceAccount('A');
    await db.reactivateFinanceAccount('A');
    expect((await db.getFinanceAccounts()).single.activa, true);
    await db.close();
  });

  test('deleteFinanceAccountSafely lanza excepción si hay movimientos', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'otros', tipo: 'gasto',
      monto: 5, fecha: '2026-10-01',
    ));
    expect(
      () => db.deleteFinanceAccountSafely('A'),
      throwsA(isA<AccountHasTransactionsException>()),
    );
    await db.close();
  });

  test('deleteFinanceAccountSafely borra sin movimientos', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await db.deleteFinanceAccountSafely('A');
    expect(await db.getFinanceAccounts(incluirArchivadas: true), isEmpty);
    await db.close();
  });

  test('deleteFinanceAccountAndHistory borra cuenta y sus transacciones propias', () async {
    final db = _db();
    await _crearCuenta(db, 'A');
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'otros', tipo: 'gasto',
      monto: 5, fecha: '2026-10-01',
    ));
    await db.deleteFinanceAccountAndHistory('A');
    expect(await db.getFinanceAccounts(incluirArchivadas: true), isEmpty);
    expect(await db.getFinanceTransactions(), isEmpty);
    await db.close();
  });
}
