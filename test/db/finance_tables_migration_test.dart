import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';

void main() {
  test('tablas finanzas existen en DB nueva', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.getFinanceAccounts();
    await db.getFinanceCategories();
    await db.getFinanceBudgets(2026, 10);
    await db.getFinanceTransactions();
    await db.customSelect('SELECT * FROM credits LIMIT 1').get();
    await db.close();
  });

  test('v19: FinanceReservations existe y revisionNota es consultable', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.getFinanceReservations('cualquiera');
    final txs = await db.getFinanceTransactions();
    expect(txs, isEmpty); // solo confirma que la query no explota con la columna nueva
    await db.close();
  });

  test('v20: columnas de metas (montoObjetivo/fechaLimite/estado) existen en DB nueva', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final reservas = await db.getAllFinanceReservations();
    expect(reservas, isEmpty); // confirma que la query no explota con las columnas nuevas
    await db.close();
  });
}
