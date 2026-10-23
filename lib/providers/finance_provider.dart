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
    FutureProvider.family<List<FinanceBudgetRow>, (int, int)>((ref, anioMes) async {
  final db = ref.watch(databaseProvider);
  // Copia sin preguntar los presupuestos marcados "repetir automáticamente"
  // — opt-in ya dado por el usuario al crear/editar ese presupuesto. Los
  // que no lo tienen ya no se repiten solos: el usuario decidió no
  // marcarlos, así que no hay un aviso de "¿mantener?" de respaldo.
  await db.asegurarPresupuestosAutomaticos(anioMes.$1, anioMes.$2);
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
  // saldoInicial + ingresos - gastos, sin el efecto de transferencias —
  // es el balance "base" que se muestra por defecto en tarjetas y
  // resúmenes (pedido explícito del usuario: una transferencia entre
  // registros propios es solo plata que cambió de lugar, no debe hacer
  // ver un registro como si estuviera en rojo).
  final double saldoSinTransferencias;
  final double ingresos;
  final double gastos;
  final double reservado;
  final double disponibleEstimado;
  final bool reservasExcedenSaldo;
  const FinanceAccountBalance({
    required this.saldo, required this.saldoSinTransferencias,
    required this.ingresos, required this.gastos,
    required this.reservado, required this.disponibleEstimado,
    required this.reservasExcedenSaldo,
  });
}

/// Fuente única de cálculo de saldo/ingresos/gastos/disponible para un
/// registro — reemplaza los cálculos locales que antes vivían repetidos en
/// finanzas_cuentas_screen, finanzas_libro_transacciones_screen y
/// finanzas_estadisticas_screen.
/// Balances de TODAS las cuentas en una sola consulta batcheada — usar en
/// pantallas que muestran varias cuentas a la vez (lista de registros, su
/// encabezado global). `financeAccountBalanceProvider` sigue existiendo
/// para pantallas de una sola cuenta (detalle de un registro, metas), donde
/// no hay N+1 que resolver.
final allFinanceAccountBalancesProvider =
    FutureProvider<Map<String, FinanceAccountBalance>>((ref) async {
  final db = ref.watch(databaseProvider);
  final raw = await db.getAllFinanceAccountBalancesRaw();
  return {
    for (final entry in raw.entries)
      entry.key: FinanceAccountBalance(
        saldo: entry.value.saldo,
        saldoSinTransferencias: entry.value.saldoSinTransferencias,
        ingresos: entry.value.ingresos,
        gastos: entry.value.gastos,
        reservado: entry.value.reservado,
        disponibleEstimado: calcularDisponibleEstimado(
                saldo: entry.value.saldo, reservado: entry.value.reservado)
            .disponibleEstimado,
        reservasExcedenSaldo: calcularDisponibleEstimado(
                saldo: entry.value.saldo, reservado: entry.value.reservado)
            .reservasExcedenSaldo,
      ),
  };
});

final financeAccountBalanceProvider =
    FutureProvider.family<FinanceAccountBalance, String>((ref, libroId) async {
  final db = ref.watch(databaseProvider);
  final cuenta = await db.getFinanceAccountById(libroId);
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
    saldo: saldo,
    saldoSinTransferencias: saldoInicial + ig.ingresos - ig.gastos,
    ingresos: ig.ingresos, gastos: ig.gastos,
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
  final r = await db.getFinanceGlobalPeriodSummary(mes);
  return FinanceGlobalPeriodSummary(ingresos: r.ingresos, gastos: r.gastos);
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
    categoryId: filtros.categoriaId,
    ascending: filtros.ascending,
  );
  return rows.map(FinanceTransaction.fromRow).toList();
});
