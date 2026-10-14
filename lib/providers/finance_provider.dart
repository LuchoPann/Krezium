import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/finanzas_filtros.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_ledger.dart';
import 'database_provider.dart';

final financeAccountsProvider = FutureProvider<List<FinanceAccountRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getFinanceAccounts();
});

final financeTransactionsProvider =
    FutureProvider.family<List<FinanceTransactionRow>, String?>((ref, mes) {
  final db = ref.watch(databaseProvider);
  return db.getFinanceTransactions(mes: mes);
});

final financeBudgetsProvider =
    FutureProvider.family<List<FinanceBudgetRow>, (int, int)>((ref, anioMes) {
  final db = ref.watch(databaseProvider);
  return db.getFinanceBudgets(anioMes.$1, anioMes.$2);
});

/// Todas las metas/reservas de todos los registros — alimenta la vista
/// global de Planificación > Metas (no está anidada dentro de un registro).
final allFinanceReservationsProvider =
    FutureProvider<List<FinanceReservationRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getAllFinanceReservations();
});

/// Historial de aportes/retiros de una meta (Planificación v2) — permite
/// reconstruir qué pasó y cuándo, cosa que el solo acumulado de
/// FinanceReservations.monto no permitía.
final financeGoalMovementsProvider =
    FutureProvider.family<List<FinanceGoalMovementRow>, String>((ref, goalId) {
  final db = ref.watch(databaseProvider);
  return db.getFinanceGoalMovements(goalId);
});

final allFinanceCategoriesProvider =
    FutureProvider<List<CatalogoCategoria>>((ref) async {
  final db = ref.watch(databaseProvider);
  final custom = await db.getFinanceCategories();
  return [
    ...todoCatalogo,
    for (final row in custom)
      if (!row.archivada)
        CatalogoCategoria.fromCustomRow(
          id: row.id,
          nombre: row.nombre,
          iconoKey: row.icono,
          colorHex: row.color,
          tipo: row.tipo,
          parentId: row.parentId,
        ),
  ];
});

// Lugares (autocomplete de lugar en transacción)
final financePlacesProvider = FutureProvider<List<FinancePlace>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.getFinancePlaces();
  return rows.map(FinancePlace.fromRow).toList();
});

// Plantillas filtradas por tipo ('ingreso'|'gasto'|null = todas)
final financeTemplatesByTipoProvider =
    FutureProvider.family<List<FinanceTemplate>, String?>((ref, tipo) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.getFinanceTemplates(tipo: tipo);
  return rows.map(FinanceTemplate.fromRow).toList();
});

// Filtros activos de la pantalla de transacciones
final finanzasFiltrosProvider = StateProvider<FinanzasFiltros>(
  (_) => const FinanzasFiltros(),
);

// Libro activo (ID del libro seleccionado en Tab 0)
final finanzasLibroActivoProvider = StateProvider<String?>((_) => null);

class FinanceAccountBalance {
  final double saldo;
  final double ingresos;
  final double gastos;
  final double reservado;
  final double disponibleEstimado;
  final bool reservasExcedenSaldo;
  const FinanceAccountBalance({
    required this.saldo, required this.ingresos, required this.gastos,
    required this.reservado, required this.disponibleEstimado,
    required this.reservasExcedenSaldo,
  });
}

/// Fuente única de cálculo de saldo/ingresos/gastos/disponible para un
/// registro — reemplaza los cálculos locales que antes vivían repetidos en
/// finanzas_cuentas_screen, finanzas_libro_transacciones_screen y
/// finanzas_estadisticas_screen.
final financeAccountBalanceProvider =
    FutureProvider.family<FinanceAccountBalance, String>((ref, libroId) async {
  final db = ref.watch(databaseProvider);
  final cuentas = await db.getFinanceAccounts(incluirArchivadas: true);
  final cuenta = cuentas.where((c) => c.id == libroId).firstOrNull;
  final saldoInicial = cuenta?.saldoInicial ?? 0.0;

  final rows = await db.getFinanceTransactionsInvolvingLibro(libroId: libroId);
  final txs = rows.map(FinanceTransaction.fromRow).toList();

  final saldo = calcularSaldo(
    saldoInicial: saldoInicial, txsInvolucradas: txs, libroId: libroId,
  );
  final ig = calcularIngresosGastos(txs, libroId);

  final reservas = await db.getFinanceReservations(libroId);
  final reservado = totalReservado(reservas);
  final disp = calcularDisponibleEstimado(saldo: saldo, reservado: reservado);

  return FinanceAccountBalance(
    saldo: saldo, ingresos: ig.ingresos, gastos: ig.gastos,
    reservado: reservado, disponibleEstimado: disp.disponibleEstimado,
    reservasExcedenSaldo: disp.reservasExcedenSaldo,
  );
});

class FinanceGlobalPeriodSummary {
  final double ingresos;
  final double gastos;
  const FinanceGlobalPeriodSummary({required this.ingresos, required this.gastos});
}

/// Ingresos/gastos de [mes] ('YYYY-MM') sumados sobre todos los registros
/// activos — una transferencia nunca cuenta aquí (ver calcularIngresosGastos).
/// Fuente para el resumen del periodo en el lobby de Registros (Fase 03).
final financeGlobalPeriodSummaryProvider =
    FutureProvider.family<FinanceGlobalPeriodSummary, String>((ref, mes) async {
  final db = ref.watch(databaseProvider);
  final cuentas = await db.getFinanceAccounts();
  var ingresos = 0.0;
  var gastos = 0.0;
  for (final cuenta in cuentas) {
    final rows = await db.getFinanceTransactionsInvolvingLibro(
      libroId: cuenta.id, mes: mes,
    );
    final txs = rows.map(FinanceTransaction.fromRow).toList();
    final ig = calcularIngresosGastos(txs, cuenta.id);
    ingresos += ig.ingresos;
    gastos += ig.gastos;
  }
  return FinanceGlobalPeriodSummary(ingresos: ingresos, gastos: gastos);
});

// Historial completo del libro activo (sin recorte por mes) — incluye las
// transferencias entrantes (transferToAccountId == libroId) para que el
// registro destino también vea el dinero que recibió.
final finanzasLibroTxProvider =
    FutureProvider.family<List<FinanceTransaction>, String>(
        (ref, libroId) async {
  final db = ref.watch(databaseProvider);
  final filtros = ref.watch(finanzasFiltrosProvider);
  final tipo = filtros.tipoFiltro == 'todos' ? null : filtros.tipoFiltro;
  final rows = await db.getFinanceTransactionsInvolvingLibro(
    libroId: libroId,
    mes: null,
    tipo: tipo,
    ascending: filtros.ascending,
  );
  final txs = rows.map(FinanceTransaction.fromRow).toList();
  if (filtros.categoriaId == null) return txs;
  return txs.where((t) => t.categoryId == filtros.categoriaId).toList();
});
