import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test('upsertFinanceBudget crea un presupuesto nuevo para (categoría, año, mes)', () async {
    final db = _db();
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 10, montoLimite: 500000,
    ));

    final budgets = await db.getFinanceBudgets(2026, 10);
    expect(budgets, hasLength(1));
    expect(budgets.single.montoLimite, 500000);
    await db.close();
  });

  test('upsertFinanceBudget sobre la misma (categoría, año, mes) actualiza en vez de duplicar', () async {
    final db = _db();
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 10, montoLimite: 500000,
    ));
    // Regression: antes insertOnConflictUpdate conflictaba por `rowId`
    // (autoincrement), nunca provisto desde la UI — cada "edición" insertaba
    // una fila nueva en vez de actualizar la existente.
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 10, montoLimite: 700000,
    ));

    final budgets = await db.getFinanceBudgets(2026, 10);
    expect(budgets, hasLength(1));
    expect(budgets.single.montoLimite, 700000);
    await db.close();
  });

  test('upsertFinanceBudget distingue presupuestos de distinta categoría en el mismo mes', () async {
    final db = _db();
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 10, montoLimite: 500000,
    ));
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_transporte_padre', anio: 2026, mes: 10, montoLimite: 200000,
    ));

    final budgets = await db.getFinanceBudgets(2026, 10);
    expect(budgets, hasLength(2));
    await db.close();
  });

  test('upsertFinanceBudget distingue presupuestos de la misma categoría en distinto mes', () async {
    final db = _db();
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 10, montoLimite: 500000,
    ));
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 11, montoLimite: 600000,
    ));

    expect(await db.getFinanceBudgets(2026, 10), hasLength(1));
    expect(await db.getFinanceBudgets(2026, 11), hasLength(1));
    await db.close();
  });

  test('deleteFinanceBudget elimina un presupuesto por su rowId', () async {
    final db = _db();
    await db.upsertFinanceBudget(FinanceBudgetsCompanion.insert(
      categoryId: 'cat_alimentacion_padre', anio: 2026, mes: 10, montoLimite: 500000,
    ));
    final rowId = (await db.getFinanceBudgets(2026, 10)).single.rowId;

    await db.deleteFinanceBudget(rowId);

    expect(await db.getFinanceBudgets(2026, 10), isEmpty);
    await db.close();
  });

  test('getFinanceBudgetFor devuelve null cuando no existe presupuesto para esa categoría/mes', () async {
    final db = _db();
    final found = await db.getFinanceBudgetFor('cat_alimentacion_padre', 2026, 10);
    expect(found, null);
    await db.close();
  });
}
