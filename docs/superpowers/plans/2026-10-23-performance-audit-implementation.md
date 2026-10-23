# Auditoría de rendimiento Krezium — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminar los cuellos de botella de rendimiento identificados en la auditoría exhaustiva de 2026-10-23 (5 agentes de investigación en paralelo sobre capa DB/Drift, providers Riverpod, listas/scroll, alcance de rebuilds/setState, y animaciones/assets/startup) sin cambiar ningún comportamiento visible de la app.

**Architecture:** Los cambios son todos internos (consultas SQL, memoización, alcance de `ref.watch`/`setState`, compresión de assets) — ninguno altera UI, flujos de usuario ni formato de datos persistidos. Cada tarea es independiente y se puede revisar/revertir por separado.

**Tech Stack:** Flutter + Riverpod (flutter_riverpod 2.6.1) + Drift ORM sobre sqlite.

**Spec:** Este documento es su propia spec — basado directamente en los 5 reportes de auditoría (DB, Riverpod, listas, rebuilds, animaciones/assets) generados el 2026-10-23, citados inline en cada tarea.

## Global Constraints

- Nunca cambiar el comportamiento observable de la app (mismos resultados, misma UI) — esto es optimización pura, no refactor de producto.
- Toda migración de schema usa el patrón ya establecido en `lib/data/db/database.dart`: bump de `schemaVersion`, bloque `if (from < N)` idempotente, nunca tocar migraciones ya enviadas.
- `flutter analyze` debe quedar limpio en cada archivo tocado antes de dar una tarea por terminada.
- No añadir dependencias nuevas salvo que una tarea lo diga explícitamente.
- Preferir `.select()` de Riverpod y queries SQL agregadas sobre soluciones ad-hoc en Dart.

## Review Focus

- Una migración de índice que no sea idempotente (falla en upgrade si ya existe) — cada `CREATE INDEX` debe usar `IF NOT EXISTS`.
- Un batched query que cambie silenciosamente el resultado para el caso de 0 ids (`.isIn([])` en Drift debe devolver vacío, no todo).
- Una tarea de memoización que compare por `==` en vez de identidad en una lista que se reconstruye cada build (cache nunca se invalida o invalida siempre).
- Un `ValueNotifier`/`ValueListenableBuilder` que no se disponga, filtrando listeners.
- Compresión de assets que degrade visualmente un logo/ícono por debajo de lo aceptable en pantallas de alta densidad.

---

## Fase 1 — Capa de datos (Drift/DB): mayor impacto, menor riesgo

### Task 1: Índices en columnas FK/fecha muy filtradas

**Files:**
- Modify: `lib/data/db/tables_finance.dart` (añadir `@TableIndex` donde aplique)
- Modify: `lib/data/db/tables.dart` (créditos — añadir `@TableIndex` donde aplique)
- Modify: `lib/data/db/database.dart` (`schemaVersion` 23→24, bloque de migración)

**Interfaces:**
- Produce: índices SQL nuevos — no cambia ninguna firma de método Dart.

Hoy no existe ningún `@TableIndex` ni `CREATE INDEX` en el schema (confirmado en la auditoría), así que toda columna FK se escanea completa en cada query. Columnas a indexar (de la auditoría DB):

- `card_movements.credit_id`, `card_statements.credit_id`, `installment_purchases.credit_id`, `installments.credit_id`, `loan_abonos.credit_id`, `pagos_realizados.credit_id`
- `finance_transactions.account_id`, `finance_transactions.transfer_to_account_id`, `finance_transactions.fecha`
- `finance_reservations.account_id`
- `finance_goal_movements.goal_id`
- `finance_budgets(category_id, anio, mes)` — único, es la clave de negocio real (ver `getFinanceBudgetFor`)

- [ ] **Paso 1: Añadir `@TableIndex` a las tablas de Créditos**

En `lib/data/db/tables.dart`, sobre cada clase de tabla con `credit_id`, añadir (ejemplo para `CardMovements`; repetir el patrón para `CardStatements`, `InstallmentPurchases`, `Installments`, `LoanAbonos`, `PagosRealizados`):

```dart
@TableIndex(name: 'idx_card_movements_credit_id', columns: {#creditId})
@DataClassName('CardMovementRow')
class CardMovements extends Table {
  ...
}
```

- [ ] **Paso 2: Añadir `@TableIndex` a las tablas de Finanzas**

En `lib/data/db/tables_finance.dart`:

```dart
@TableIndex(name: 'idx_finance_tx_account', columns: {#accountId})
@TableIndex(name: 'idx_finance_tx_transfer_to', columns: {#transferToAccountId})
@TableIndex(name: 'idx_finance_tx_fecha', columns: {#fecha})
@DataClassName('FinanceTransactionRow')
class FinanceTransactions extends Table { ... }

@TableIndex(name: 'idx_finance_reservations_account', columns: {#accountId})
@DataClassName('FinanceReservationRow')
class FinanceReservations extends Table { ... }

@TableIndex(name: 'idx_finance_goal_movements_goal', columns: {#goalId})
@DataClassName('FinanceGoalMovementRow')
class FinanceGoalMovements extends Table { ... }

@TableIndex(
  name: 'idx_finance_budgets_key',
  columns: {#categoryId, #anio, #mes},
  unique: true,
)
@DataClassName('FinanceBudgetRow')
class FinanceBudgets extends Table { ... }
```

- [ ] **Paso 3: Regenerar código Drift**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Paso 4: Bump de `schemaVersion` y migración**

En `lib/data/db/database.dart`, cambiar `int get schemaVersion => 23;` a `24`, y dentro de `MigrationStrategy.onUpgrade`, añadir (siguiendo el patrón `if (from < N)` ya usado en el archivo):

```dart
if (from < 24) {
  // Drift ya crea los índices declarados vía @TableIndex para bases
  // NUEVAS, pero una base existente necesita el CREATE INDEX explícito.
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_card_movements_credit_id ON card_movements(credit_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_card_statements_credit_id ON card_statements(credit_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_installment_purchases_credit_id ON installment_purchases(credit_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_installments_credit_id ON installments(credit_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_loan_abonos_credit_id ON loan_abonos(credit_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_pagos_realizados_credit_id ON pagos_realizados(credit_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_finance_tx_account ON finance_transactions(account_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_finance_tx_transfer_to ON finance_transactions(transfer_to_account_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_finance_tx_fecha ON finance_transactions(fecha)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_finance_reservations_account ON finance_reservations(account_id)');
  await customStatement(
    'CREATE INDEX IF NOT EXISTS idx_finance_goal_movements_goal ON finance_goal_movements(goal_id)');
  await customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_finance_budgets_key ON finance_budgets(category_id, anio, mes)');
}
```

Nota: antes de crear el índice único de `finance_budgets`, verificar que no existan duplicados reales de `(categoryId, anio, mes)` en bases de usuarios actuales — si `upsertFinanceBudget` siempre hizo `getFinanceBudgetFor` antes de insertar (como indica su propio comentario en el código), no deberían existir, pero si el `CREATE UNIQUE INDEX` fallara por datos duplicados preexistentes, cambiar a un índice no-único como fallback seguro y abrir una tarea de limpieza de datos aparte — no bloquear esta migración por eso.

- [ ] **Paso 5: Verificar**

```bash
flutter analyze lib/data/db/database.dart lib/data/db/tables.dart lib/data/db/tables_finance.dart
flutter test test/data/db/
```

- [ ] **Paso 6: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/tables_finance.dart lib/data/db/database.dart lib/data/db/database.g.dart
git commit -m "perf(db): agrega índices a columnas FK/fecha muy filtradas (schemaVersion 24)"
```

---

### Task 2: Balance de cuentas en una sola query batcheada

**Files:**
- Modify: `lib/data/db/database.dart` (nuevo método `getAllFinanceAccountBalances`)
- Modify: `lib/providers/finance_provider.dart` (nuevo provider, o `financeAccountBalanceProvider` reescrito para leer de un mapa precomputado)
- Modify: `lib/screens/finanzas/finanzas_cuentas_screen.dart` (`_GlobalHeader` línea ~369-383, `_LibroCard` línea ~813)

**Interfaces:**
- Consumes: `AppDatabase.getFinanceAccounts`, `getFinanceTransactionsInvolvingLibro`, `getFinanceReservations` (lógica existente a fusionar).
- Produces: `Future<Map<String, FinanceAccountBalance>> getAllFinanceAccountBalancesRaw()` en `AppDatabase`, y `allFinanceAccountBalancesProvider` (`FutureProvider<Map<String, FinanceAccountBalance>>`) en `finance_provider.dart`.

Hoy, tanto `_GlobalHeader` como cada `_LibroCard` watchean `financeAccountBalanceProvider(libro.id)` por cuenta — cada instancia vuelve a hacer `getFinanceAccounts(incluirArchivadas:true)` completo + un scan de transacciones + reservas (auditoría DB #1, Riverpod #2/#4). Con N cuentas visibles son ~3×N queries en cada rebuild de la pantalla de registros.

- [ ] **Paso 1: Nuevo método batcheado en `AppDatabase`**

En `lib/data/db/database.dart`, junto a `getFinanceAccounts`:

```dart
/// Saldo/ingresos/gastos/reservado de TODAS las cuentas activas en una
/// sola pasada — reemplaza N llamadas individuales a financeAccountBalanceProvider
/// (antes: 3×N queries para N cuentas visibles en la pantalla de registros).
Future<Map<String, ({double saldo, double ingresos, double gastos, double reservado})>>
    getAllFinanceAccountBalancesRaw() async {
  final cuentas = await getFinanceAccounts(incluirArchivadas: true);
  final todasLasTx = await select(financeTransactions).get();
  final todasLasReservas = await select(financeReservations).get();

  final resultado = <String, ({double saldo, double ingresos, double gastos, double reservado})>{};
  for (final cuenta in cuentas) {
    final txsInvolucradas = todasLasTx.where((t) =>
        t.accountId == cuenta.id || t.transferToAccountId == cuenta.id);
    final txs = txsInvolucradas.map(FinanceTransaction.fromRow).toList();
    final saldo = calcularSaldo(
      saldoInicial: cuenta.saldoInicial, txsInvolucradas: txs, libroId: cuenta.id);
    final ig = calcularIngresosGastos(txs, cuenta.id);
    final reservado = totalReservado(
        todasLasReservas.where((r) => r.accountId == cuenta.id).toList());
    resultado[cuenta.id] = (saldo: saldo, ingresos: ig.ingresos, gastos: ig.gastos, reservado: reservado);
  }
  return resultado;
}
```

Nota: esto sigue trayendo las tablas completas UNA vez (no N veces) y agrupa en Dart — ya es el salto de 3×N a 3 queries totales. Con los índices de Task 1 ya en su lugar, si en el futuro el volumen de transacciones crece mucho, se puede migrar el agrupado a SQL con `GROUP BY account_id`, pero no es necesario para este fix.

- [ ] **Paso 2: Provider que expone el mapa completo**

En `lib/providers/finance_provider.dart`, junto a `financeAccountBalanceProvider`:

```dart
/// Balances de TODAS las cuentas en una sola consulta — usar este en
/// pantallas que muestran varias cuentas a la vez (lista de registros);
/// financeAccountBalanceProvider sigue existiendo para pantallas de una
/// sola cuenta (detalle de un registro).
final allFinanceAccountBalancesProvider =
    FutureProvider<Map<String, FinanceAccountBalance>>((ref) async {
  final db = ref.watch(databaseProvider);
  final raw = await db.getAllFinanceAccountBalancesRaw();
  final reservasPorCuenta = <String, List<FinanceReservationRow>>{};
  for (final entry in raw.entries) {
    final reservas = await db.getFinanceReservations(entry.key);
    reservasPorCuenta[entry.key] = reservas;
  }
  return {
    for (final entry in raw.entries)
      entry.key: FinanceAccountBalance(
        saldo: entry.value.saldo,
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
```

(Si al implementar se nota que `getFinanceReservations` por cuenta dentro del provider reintroduce el N+1 de reservas, mover esa parte también a un único `select(financeReservations).get()` agrupado en Dart dentro de `getAllFinanceAccountBalancesRaw`, igual que se hizo con las transacciones — usar el mismo patrón, no es necesario mantenerlo como llamada separada.)

- [ ] **Paso 3: Usar el provider batcheado en la pantalla de registros**

En `lib/screens/finanzas/finanzas_cuentas_screen.dart`:
- `_GlobalHeader.build()` (línea ~372-383): reemplazar el loop `for (final libro in libros) { ref.watch(financeAccountBalanceProvider(libro.id)) ... }` por un único `ref.watch(allFinanceAccountBalancesProvider)` y sumar `b.saldo` sobre los valores del mapa.
- `_LibroCard.build()` (línea ~813): reemplazar `ref.watch(financeAccountBalanceProvider(libro.id))` por `ref.watch(allFinanceAccountBalancesProvider).whenData((m) => m[libro.id])` (o un selector equivalente), manteniendo los mismos `loading`/`error`/`data` que ya maneja el widget.

No tocar `financeAccountBalanceProvider` en sí — sigue usándose en pantallas de una sola cuenta (detalle de registro, metas) donde no hay N+1.

- [ ] **Paso 4: Verificar**

```bash
flutter analyze lib/data/db/database.dart lib/providers/finance_provider.dart lib/screens/finanzas/finanzas_cuentas_screen.dart
```

- [ ] **Paso 5: Commit**

```bash
git add lib/data/db/database.dart lib/providers/finance_provider.dart lib/screens/finanzas/finanzas_cuentas_screen.dart
git commit -m "perf(finanzas): balance de todas las cuentas en una sola consulta batcheada"
```

---

### Task 3: `getFinanceAccountById` en vez de escanear toda la tabla

**Files:**
- Modify: `lib/data/db/database.dart`
- Modify: `lib/providers/finance_provider.dart` (`financeAccountBalanceProvider`, línea ~119-121)

`financeAccountBalanceProvider` hace `getFinanceAccounts(incluirArchivadas: true)` completo solo para encontrar una cuenta por id (auditoría DB #1, Riverpod #4).

- [ ] **Paso 1: Nuevo método puntual**

En `lib/data/db/database.dart`, junto a `getFinanceAccounts`:

```dart
Future<FinanceAccountRow?> getFinanceAccountById(String id) =>
    (select(financeAccounts)..where((t) => t.id.equals(id))).getSingleOrNull();
```

- [ ] **Paso 2: Usarlo en el provider**

En `financeAccountBalanceProvider` (`finance_provider.dart`), reemplazar:
```dart
final cuentas = await db.getFinanceAccounts(incluirArchivadas: true);
final cuenta = cuentas.where((c) => c.id == libroId).firstOrNull;
```
por:
```dart
final cuenta = await db.getFinanceAccountById(libroId);
```

- [ ] **Paso 3: Verificar**

```bash
flutter analyze lib/data/db/database.dart lib/providers/finance_provider.dart
```

- [ ] **Paso 4: Commit**

```bash
git add lib/data/db/database.dart lib/providers/finance_provider.dart
git commit -m "perf(finanzas): busca una cuenta por id en vez de escanear toda la tabla"
```

---

### Task 4: `loadAllCredits` sin N+1 entre tablas hijas

**Files:**
- Modify: `lib/data/db/database.dart` (`loadAllCredits`, línea ~448-559)

Para M créditos, hoy se hacen 2-3 queries POR crédito a sus tablas hijas (movimientos/statements/compras, o cuotas/abonos) — hasta `3M+1` queries (auditoría DB #4).

- [ ] **Paso 1: Leer el método actual completo antes de tocarlo**

```bash
sed -n '440,565p' lib/data/db/database.dart
```

- [ ] **Paso 2: Reescribir usando `isIn` + agrupado en Dart**

Reemplazar el loop por-crédito por: una query `.where((t) => t.creditId.isIn(allCreditIds))` por cada tabla hija (movements, statements, installmentPurchases, installments, abonos — las que el método use), luego agrupar los resultados en un `Map<String, List<Row>>` por `creditId` en Dart, y construir cada `Credit` desde ese mapa en vez de volver a consultar la DB por crédito. Mantener exactamente la misma forma de objeto `Credit` devuelta — este cambio es puramente de cuántas queries se hacen, no de qué datos se devuelven.

Si `allCreditIds` está vacío, cada query con `.isIn([])` debe devolver lista vacía (comportamiento estándar de Drift) — verificar que el caso "sin créditos" no rompa el agrupado posterior (debe devolver `[]`, no lanzar).

- [ ] **Paso 3: Verificar contra los tests existentes**

```bash
flutter analyze lib/data/db/database.dart
flutter test test/data/db/
flutter test test/domain/ # si hay tests que dependan de loadAllCredits indirectamente
```

- [ ] **Paso 4: Commit**

```bash
git add lib/data/db/database.dart
git commit -m "perf(creditos): loadAllCredits usa queries batcheadas por tabla en vez de N+1 por crédito"
```

---

### Task 5: `debtHistoryProvider` sin N+1 de pagos por crédito

**Files:**
- Modify: `lib/data/db/database.dart` (nuevo `loadPagosRealizadosForCredits`)
- Modify: `lib/providers/debt_history_provider.dart` (línea ~30-36)

- [ ] **Paso 1: Nuevo método batcheado**

```dart
Future<Map<String, List<PagoRealizadoRow>>> loadPagosRealizadosForCredits(
  List<String> creditIds,
) async {
  if (creditIds.isEmpty) return {};
  final rows = await (select(pagosRealizados)
        ..where((t) => t.creditId.isIn(creditIds)))
      .get();
  final porCredito = <String, List<PagoRealizadoRow>>{};
  for (final r in rows) {
    (porCredito[r.creditId] ??= []).add(r);
  }
  return porCredito;
}
```

(Ajustar el nombre real de la tabla/clase de fila según lo que exista en `tables.dart` — usar el mismo tipo que ya devuelve `loadPagosRealizados(id)` actual.)

- [ ] **Paso 2: Usarlo en `_buildHistory`**

En `lib/providers/debt_history_provider.dart`, reemplazar el loop `for (final c in credits) { await db.loadPagosRealizados(c.id) }` por una sola llamada a `loadPagosRealizadosForCredits(credits.map((c) => c.id).toList())` y leer del mapa resultante dentro del loop (sin más awaits).

- [ ] **Paso 3: Verificar**

```bash
flutter analyze lib/data/db/database.dart lib/providers/debt_history_provider.dart
```

- [ ] **Paso 4: Commit**

```bash
git add lib/data/db/database.dart lib/providers/debt_history_provider.dart
git commit -m "perf(creditos): debtHistoryProvider carga pagos de todos los créditos en una consulta"
```

---

### Task 6: Conteo por COUNT en vez de traer filas completas

**Files:**
- Modify: `lib/data/db/database.dart` (`countTransactionsForAccount`, línea ~804-810)

- [ ] **Paso 1: Reemplazar por un COUNT**

```dart
Future<int> countTransactionsForAccount(String accountId) async {
  final query = selectOnly(financeTransactions)
    ..addColumns([financeTransactions.id.count()])
    ..where(financeTransactions.accountId.equals(accountId) |
        financeTransactions.transferToAccountId.equals(accountId));
  final row = await query.getSingle();
  return row.read(financeTransactions.id.count()) ?? 0;
}
```

Ajustar la condición `where` exacta a la que ya tenga el método actual (puede que solo filtre por `accountId`, no por ambos lados) — leer el método completo antes de cambiarlo para no alterar qué se cuenta.

- [ ] **Paso 2: Verificar**

```bash
flutter analyze lib/data/db/database.dart
```

- [ ] **Paso 3: Commit**

```bash
git add lib/data/db/database.dart
git commit -m "perf(finanzas): countTransactionsForAccount usa COUNT en vez de traer todas las filas"
```

---

### Task 7: `asegurarPresupuestosAutomaticos` sin loop de hasta 24 queries

**Files:**
- Modify: `lib/data/db/database.dart` (línea ~1030-1053)

Hoy, cada visita a la pantalla de presupuestos puede disparar hasta 24 queries secuenciales buscando el mes anterior con datos (auditoría DB #5).

- [ ] **Paso 1: Leer el método completo**

```bash
sed -n '1020,1060p' lib/data/db/database.dart
```

- [ ] **Paso 2: Reemplazar el loop por una sola query ordenada**

Construir una query sobre `financeBudgets` filtrando `autoRepetir = true` y `(anio, mes)` anterior al mes actual, ordenada descendente por `(anio, mes)` con `limit(1)`, usando Drift (`orderBy` + `limit`). Si Drift no soporta directamente la comparación de tupla `(anio, mes) < (x, y)` de forma simple, mantener el filtro en Dart pero sobre el resultado YA ordenado y limitado a, por ejemplo, los últimos 24 meses traídos en una sola query (`anio >= currentAnio - 2`) en vez de 24 queries separadas — el punto es pasar de N queries a 1.

- [ ] **Paso 3: Verificar**

```bash
flutter analyze lib/data/db/database.dart
flutter test test/data/db/ # si existen tests de presupuestos automáticos
```

- [ ] **Paso 4: Commit**

```bash
git add lib/data/db/database.dart
git commit -m "perf(presupuestos): busca el mes anterior con autoRepetir en una sola consulta"
```

---

### Task 8: `finanzasLibroTxProvider` filtra categoría en SQL, no en Dart

**Files:**
- Modify: `lib/data/db/database.dart` (`getFinanceTransactionsInvolvingLibro`)
- Modify: `lib/providers/finance_provider.dart` (línea ~161-176)

Hoy se trae TODO el historial de un registro (sin filtro de mes) y se filtra por `categoriaId` en Dart después (auditoría Riverpod #8/DB #8) — para registros con historial largo esto es releer todo en cada rebuild.

- [ ] **Paso 1: Añadir parámetro opcional `categoryId` a `getFinanceTransactionsInvolvingLibro`**

Mantener compatibilidad: parámetro nullable, si es `null` no se añade condición extra al `where`.

- [ ] **Paso 2: Usarlo desde `finanzasLibroTxProvider`**

Pasar `filtros.categoriaId` directamente a la query en vez de hacer `txs.where((t) => t.categoryId == filtros.categoriaId).toList()` después de traer todo.

- [ ] **Paso 3: Verificar**

```bash
flutter analyze lib/data/db/database.dart lib/providers/finance_provider.dart
```

- [ ] **Paso 4: Commit**

```bash
git add lib/data/db/database.dart lib/providers/finance_provider.dart
git commit -m "perf(finanzas): filtra transacciones por categoría en SQL en vez de en Dart"
```

---

## Fase 2 — Alcance de rebuilds (Riverpod `.select()` + aislar `setState`)

### Task 9: `.select()` en providers watcheados por un solo campo

**Files:**
- Modify: `lib/screens/lock/setup_lock_screen.dart:79`

- [ ] **Paso 1:** Cambiar `ref.watch(appLockProvider).method` por `ref.watch(appLockProvider.select((s) => s.method))`.
- [ ] **Paso 2:** `flutter analyze lib/screens/lock/setup_lock_screen.dart`
- [ ] **Paso 3:** Commit: `perf(lock): usa select() en vez de watchear todo AppLockState`

---

### Task 10: Buscador de registros no rebuilda toda la pantalla

**Files:**
- Modify: `lib/screens/finanzas/finanzas_cuentas_screen.dart` (línea ~51, buscador)

Hoy `_searchCtrl.addListener(() => setState(() => _query = ...))` rebuilda la pantalla entera (balances, lista, FABs) en cada tecla (auditoría rebuilds #3), en una pantalla de 1300+ líneas.

- [ ] **Paso 1:** Extraer el estado de búsqueda a un `ValueNotifier<String>` de nivel de pantalla (no `setState`), y envolver SOLO la sección que renderiza la lista filtrada (la que hoy lee `_query`) en un `ValueListenableBuilder<String>`.
- [ ] **Paso 2:** Confirmar que el resto de la pantalla (header, balance global, FAB) no está dentro de ese `ValueListenableBuilder` y por tanto no se reconstruye al escribir.
- [ ] **Paso 3:** `flutter analyze lib/screens/finanzas/finanzas_cuentas_screen.dart`
- [ ] **Paso 4:** Commit: `perf(finanzas): el buscador de registros ya no reconstruye toda la pantalla`

---

### Task 11: Memoizar agrupado/totales en el libro de transacciones

**Files:**
- Modify: `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart` (línea ~272-273, `_agrupar`/`_totales`)
- Reference pattern: `lib/screens/credits/credits_list_screen.dart` (`_FilteredListState._apply()` — ya implementa cache por identidad)

`_agrupar(txs, ...)` y `_totales(txs)` corren sin memoizar dentro de `build()` sobre el historial completo — cualquier rebuild no relacionado (abrir/cerrar el sheet de filtros, async de categorías resolviendo) re-agrupa y re-ordena todo de nuevo (auditoría Riverpod #3).

- [ ] **Paso 1:** Leer el patrón de cache ya usado en `credits_list_screen.dart`'s `_FilteredListState._apply()` (cachea por `identical(txs)` + los filtros aplicados).
- [ ] **Paso 2:** Aplicar el mismo patrón aquí: guardar en campos de estado el último `txs`/filtros usados y el resultado de `_agrupar`/`_totales`; solo recalcular si `txs` (por identidad) o los filtros relevantes cambiaron.
- [ ] **Paso 3:** `flutter analyze lib/screens/finanzas/finanzas_libro_transacciones_screen.dart`
- [ ] **Paso 4:** Commit: `perf(finanzas): memoiza agrupado y totales del libro de transacciones`

---

### Task 12: Memoizar filtro/orden de metas

**Files:**
- Modify: `lib/screens/finanzas/finanzas_metas_screen.dart` (línea ~109-113)

Mismo patrón que Task 11, menor impacto hoy (listas de metas suelen ser cortas) pero mismo fix.

- [ ] **Paso 1:** Aplicar el mismo cache por identidad que en Task 11.
- [ ] **Paso 2:** `flutter analyze lib/screens/finanzas/finanzas_metas_screen.dart`
- [ ] **Paso 3:** Commit: `perf(finanzas): memoiza filtro/orden de metas`

---

### Task 13: Aislar el formulario de crédito (`add_credit_sheet.dart`) — la más grande

**Files:**
- Modify: `lib/screens/credits/add_credit_sheet.dart` (3480 líneas, 47 sitios de `setState(() {})`)

**Interfaces:**
- Consumes: los mismos `TextEditingController`s ya existentes en el formulario.
- Produces: un `ValueNotifier` (o varios, agrupados en un solo objeto inmutable "snapshot") que alimenta la vista previa/resumen sin pasar por `setState` del state gigante.

Esta es la tarea de mayor envergadura y mayor impacto de rebuild: cada tecla reconstruye las 3480 líneas del wizard completo, y `_buildPreviewCredit()`/`_summaryRows()` recalculan el cronograma de amortización completo en cada rebuild (auditoría rebuilds #1/#2/#7).

- [ ] **Paso 1: Mapear qué partes de la UI dependen de qué estado**

Leer `_AddCreditSheetState.build()` (línea ~937) completo y listar: (a) qué controla el índice de paso/wizard, (b) qué controla la vista previa/resumen (`_buildPreviewCredit`, `_summaryRows`), (c) qué son campos de formulario puros sin efecto fuera de su propio paso.

- [ ] **Paso 2: Crear un `ValueNotifier` para el snapshot de preview**

Definir una clase inmutable pequeña (p. ej. `_PreviewSnapshot`) con los campos que `_buildPreviewCredit`/`_summaryRows` necesitan, y un `ValueNotifier<_PreviewSnapshot?>` en el `State`. Cada `onChanged` de un campo relevante para la preview actualiza el notifier (no llama `setState`); los campos que NO afectan la preview pueden seguir usando `setState` normal si su propio alcance ya es pequeño, pero revisar cada uno de los 47 sitios para decidir caso por caso.

- [ ] **Paso 3: Envolver la sección de preview/resumen en `ValueListenableBuilder`**

Donde hoy se invoca `_buildPreviewCredit()`/`_summaryRows()` dentro de `build()`, envolver esa sección en `ValueListenableBuilder<_PreviewSnapshot?>` leyendo del notifier del Paso 2 — así escribir en un campo que no afecta la preview no dispara el cálculo del cronograma.

- [ ] **Paso 4: (Opcional, si el tiempo lo permite) Extraer pasos del wizard a widgets propios**

Los métodos `_stepTiendaDatos`, `_stepTiendaFechas`, `_loanFieldsCore`, etc. ya están factorizados como métodos — convertirlos en `StatefulWidget`/`ConsumerStatefulWidget` propios con su estado local evita que un cambio en el paso N reconstruya el indicador de pasos y los paneles hermanos. Si esto resulta muy invasivo para una sola tarea, dejarlo como tarea de seguimiento separada y no bloquear el Paso 3 por esto.

- [ ] **Paso 5: Probar manualmente el flujo completo de creación de cada tipo de crédito**

Este archivo no tiene suite de widget tests exhaustiva para el wizard — antes de dar la tarea por cerrada, ejecutar `flutter run` y crear un préstamo, una tarjeta y un cupo de tienda completos, confirmando que los 3 flujos guardan el mismo resultado que antes del cambio.

- [ ] **Paso 6:** `flutter analyze lib/screens/credits/add_credit_sheet.dart`

- [ ] **Paso 7:** Commit: `perf(creditos): aísla la vista previa del formulario de crédito para no recalcular el cronograma por cada tecla`

---

### Task 14: Granularidad de `finanzasFiltrosProvider`

**Files:**
- Modify: `lib/providers/finanzas_filtros.dart` (o donde viva `FinanzasFiltros`)
- Modify: `lib/providers/finance_provider.dart` (línea ~83, definición del provider)
- Modify: los 5 sitios que lo leen/mutan: `finanzas_libro_transacciones_screen.dart`, `finanzas_cuentas_screen.dart`, `finanzas_estadisticas_screen.dart` (x2), `finanzas_presupuesto_screen.dart`

Un solo `StateProvider<FinanzasFiltros>` watcheado por varias pantallas grandes significa que cualquier cambio de filtro (aunque sea de un solo campo) invalida a todos los watchers del objeto completo (auditoría rebuilds #4/#6).

Esta es una tarea de diseño, no solo mecánica — evaluar al implementar cuál de las dos opciones es más simple dado el uso real:

- [ ] **Opción A (más simple): usar `.select()` en cada sitio que lee el provider**, en vez de dividir el provider. Cambiar cada `ref.watch(finanzasFiltrosProvider)` por `ref.watch(finanzasFiltrosProvider.select((f) => f.campoQueRealmenteUsa))` donde el widget solo necesita un campo. Donde se necesitan varios campos relacionados, está bien seguir watcheando el objeto completo.
- [ ] **Opción B (más invasiva): dividir `FinanzasFiltros` en providers separados** (categoría, fecha, libro, orden) — solo si al revisar los 5 sitios de uso se ve que casi siempre se lee/muta un solo campo a la vez.

- [ ] **Paso 1:** Leer los 5 sitios de uso listados arriba y decidir A o B según cuál quede más simple.
- [ ] **Paso 2:** Implementar la opción elegida.
- [ ] **Paso 3:** `flutter analyze` sobre los 5 archivos tocados.
- [ ] **Paso 4:** Probar manualmente: cambiar un filtro en la pantalla de transacciones y confirmar que otras pantallas que no dependen de ese campo no parpadean/reconstruyen (verificable con Flutter DevTools' "Track widget rebuilds" si está disponible, o por inspección de código si no).
- [ ] **Paso 5:** Commit: `perf(finanzas): reduce el alcance de rebuild de finanzasFiltrosProvider`

---

## Fase 3 — Listas, imágenes y assets

### Task 15: Precomputar categorías por padre en el selector

**Files:**
- Modify: `lib/screens/finanzas/categoria_selector_sheet.dart` (línea ~198-279)

Hoy, por cada fila visible de categoría padre, se hace `all.where((c) => c.parentId == padre.id).toList()` dentro de `itemBuilder` — O(n·m) en cada build, incluyendo cada expandir/colapsar (auditoría listas #3).

- [ ] **Paso 1:** Antes del `ListView.builder`, construir una sola vez (fuera de `itemBuilder`, recalculada solo si `all` cambia): `final childrenByParent = <String, List<Categoria>>{}; for (final c in all) { if (c.parentId != null) (childrenByParent[c.parentId!] ??= []).add(c); }`.
- [ ] **Paso 2:** Dentro de `itemBuilder`, reemplazar el `.where()` por `childrenByParent[padre.id] ?? const []`.
- [ ] **Paso 3:** `flutter analyze lib/screens/finanzas/categoria_selector_sheet.dart`
- [ ] **Paso 4:** Commit: `perf(finanzas): precomputa categorías-por-padre en vez de escanear la lista completa por fila`

---

### Task 16: `schedule_tab.dart` sin ListView anidado

**Files:**
- Modify: `lib/widgets/credit_detail/schedule_tab.dart` (línea ~260-275)
- Reference pattern: `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart` (ya usa `SliverList`/`SliverMainAxisGroup` correctamente, línea ~459-509)

Un `ListView` con `shrinkWrap: true` anidado dentro de un `ListView` externo fuerza layout de TODOS los hijos para medir altura total, sin virtualización real (auditoría listas #5).

- [ ] **Paso 1:** Leer cómo `finanzas_libro_transacciones_screen.dart` arma sus `SliverMainAxisGroup` por grupo de fecha.
- [ ] **Paso 2:** Convertir el contenedor externo de `schedule_tab.dart` de `ListView` a `CustomScrollView`, y cada grupo (`_SectionGroup`) a un `SliverMainAxisGroup`/`SliverList` en vez de un `ListView` interno con `shrinkWrap`.
- [ ] **Paso 3:** Probar manualmente con un crédito (cupo de tienda) que tenga muchas cuotas/compras agrupadas, confirmando que el scroll y la agrupación visual se ven igual que antes.
- [ ] **Paso 4:** `flutter analyze lib/widgets/credit_detail/schedule_tab.dart`
- [ ] **Paso 5:** Commit: `perf(creditos): elimina ListView anidado en el cronograma usando slivers`

---

### Task 17: Avatares de perfil con tamaño de decodificación acotado

**Files:**
- Modify: `lib/screens/account/account_screen_widgets.dart:207`
- Modify: `lib/screens/finanzas/finanzas_cuentas_screen.dart:402`
- Modify: `lib/screens/dashboard/dashboard_screen.dart:217`

`FileImage(File(avatarPath))` sin hint de tamaño decodifica la foto de perfil a resolución completa de cámara solo para pintar un avatar de 22-44px (auditoría listas #1/#2).

- [ ] **Paso 1:** En cada uno de los 3 sitios, envolver con `ResizeImage`: `CircleAvatar(backgroundImage: ResizeImage(FileImage(File(avatarPath)), width: 176))` (176 ≈ 44px × 4 para pantallas de alta densidad; ajustar el múltiplo según el radio real de cada `CircleAvatar` en cada sitio — el dashboard usa radius 22, revisar si los otros dos sitios usan el mismo tamaño o distinto).
- [ ] **Paso 2:** Probar manualmente que el avatar se vea nítido en una pantalla de alta densidad (no pixelado) después del cambio.
- [ ] **Paso 3:** `flutter analyze` sobre los 3 archivos.
- [ ] **Paso 4:** Commit: `perf(ui): decodifica la foto de perfil al tamaño del avatar, no a resolución completa`

---

### Task 18: Colores constantes en la búsqueda de transacciones

**Files:**
- Modify: `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart` (`_TransaccionesSearchSheet`, línea ~1144-1178)

Impacto bajo, incluida por ser trivial y gratis: `Color(0xFF...).withValues(alpha: 0.15)` se reconstruye por fila/rebuild en vez de ser constante de módulo.

- [ ] **Paso 1:** Extraer los colores repetidos (ingreso/gasto) a constantes de nivel de archivo, p. ej. `const _ingresoBg = Color(0x2622C55E);` (alpha ya aplicado en el valor hex), y usarlas en vez de `Color(0xFF22C55E).withValues(alpha: 0.15)` dentro de `itemBuilder`.
- [ ] **Paso 2:** `flutter analyze lib/screens/finanzas/finanzas_libro_transacciones_screen.dart`
- [ ] **Paso 3:** Commit: `perf(finanzas): colores constantes en la búsqueda de transacciones`

---

## Fase 4 — Assets, fuentes y trabajo pesado fuera del hilo de UI

### Task 19: Comprimir/reescalar logos de bancos e ícono de la app

**Files:**
- Modify: `assets/logos/bank-itau.png`, `assets/logos/bank-occidente.png`, `assets/logos/bank-popular.png`, `assets/logos/bank-avvillas.png`, `assets/logos/bank-tuya.png`
- Modify: `assets/icons/KREZIUM_OUTLINE.png`

856KB en logos de banco que se muestran como íconos pequeños en tarjetas/listas (auditoría assets #1/#2).

- [ ] **Paso 1:** Determinar el tamaño de renderizado real de estos logos en la UI (buscar dónde se usan: `Image.asset('assets/logos/bank-...')` y el `width`/`height` que se les da).
- [ ] **Paso 2:** Reescalar cada PNG a ~2-3× ese tamaño de renderizado (no más) usando una herramienta de línea de comandos disponible en el sistema (`pngquant`, `convert` de ImageMagick, o equivalente) — NUNCA editar el PNG a mano ni regenerar el arte, solo redimensionar/comprimir el archivo existente preservando su apariencia visual.
- [ ] **Paso 3:** Confirmar visualmente (abrir cada PNG reescalado) que no hay pérdida de calidad perceptible al tamaño real de uso.
- [ ] **Paso 4:** Repetir para `KREZIUM_OUTLINE.png` si se confirma que se usa como ícono pequeño y no como splash a tamaño completo.
- [ ] **Paso 5:** `flutter analyze` (no debería reportar nada, pero confirmar que la app sigue abriendo y mostrando los logos correctamente con `flutter run`).
- [ ] **Paso 6:** Commit: `perf(assets): reescala y comprime logos de bancos e ícono de Krezium`

---

### Task 20: Consolidar fuentes bundleadas

**Files:**
- Modify: `pubspec.yaml` (sección `fonts:`)
- Posiblemente modify: `lib/theme/app_theme.dart` (si referencia pesos específicos de Outfit)

5 pesos estáticos de Outfit (~240KB) + una variable SpaceGrotesk ya bundleada (auditoría assets #3).

- [ ] **Paso 1:** Grep en `lib/` por `fontFamily: 'Outfit'` y los `fontWeight:` usados junto a esas referencias, para confirmar cuáles de los 5 pesos (300/400/500/600/700) realmente se usan en la app.
- [ ] **Paso 2:** Si se usan los 5, investigar si existe una versión variable de Outfit (`Outfit-Variable.ttf`) que Flutter pueda usar con `fontVariations`/pesos interpolados, igual que ya se hace con SpaceGrotesk — si existe y es viable sin cambiar la apariencia, reemplazar los 5 archivos estáticos por el único variable.
- [ ] **Paso 3:** Si NO todos los 5 pesos se usan, simplemente eliminar del `pubspec.yaml` los que no se usen en ningún `fontWeight:` del código.
- [ ] **Paso 4:** Probar visualmente que ningún texto de la app cambió de peso/apariencia tras el cambio.
- [ ] **Paso 5:** `flutter analyze`
- [ ] **Paso 6:** Commit: `perf(assets): consolida pesos de fuente Outfit no usados / a variable font`

---

### Task 21: JSON de backup fuera del hilo de UI

**Files:**
- Modify: `lib/domain/export_import.dart` (línea ~46 `exportStateToJson`, línea ~145 `jsonDecode`)

`jsonDecode`/`JsonEncoder.withIndent` corren síncronos en el hilo de UI — para backups grandes (muchos créditos/movimientos/transacciones) esto puede trabar la UI durante exportar/importar (auditoría assets #8).

- [ ] **Paso 1:** Leer ambos métodos completos (`exportStateToJson` y el método de importación que usa `jsonDecode` en línea ~145).
- [ ] **Paso 2:** Envolver el `JsonEncoder(...).convert(...)` de exportación en `compute(_encodeJson, data)`, donde `_encodeJson` es una función top-level (requisito de `compute`, no puede ser un closure que capture estado del widget).
- [ ] **Paso 3:** Envolver el `jsonDecode(jsonStr)` de importación en `compute(_decodeJson, jsonStr)`, misma restricción de función top-level.
- [ ] **Paso 4:** Confirmar que las funciones top-level nuevas no dependen de nada que no sea su propio parámetro (ni `BuildContext`, ni el objeto `AppDatabase`, ni closures) — `compute` corre en un isolate separado sin acceso a ese estado.
- [ ] **Paso 5:** Probar manualmente un export + import completo (flujo de respaldo) y confirmar que el resultado es idéntico a antes del cambio.
- [ ] **Paso 6:** `flutter analyze lib/domain/export_import.dart`
- [ ] **Paso 7:** Commit: `perf(backup): mueve el encode/decode de JSON a un isolate con compute()`

---

## Self-Review (hecho por quien escribió este plan)

- **Cobertura de la auditoría:** las 5 áreas investigadas (DB, Riverpod, listas, rebuilds, animaciones/assets) tienen al menos una tarea; los hallazgos marcados como "ya está bien" por los agentes (CustomPainters, dispose(), startup de main(), credits_provider's defer pattern, credits_list_screen's memoización ya existente) NO generaron tareas — se usan como referencia de patrón correcto en las Tasks 11/12/16.
- **Sin placeholders:** cada tarea tiene file:line concreto de la auditoría y una descripción accionable de la query/patrón a cambiar; donde el código exacto depende de cómo esté hoy el método (Tasks 4, 6, 7, 20) se indica explícitamente leer el método completo antes de tocarlo, en vez de asumir una forma.
- **Riesgo más bajo primero:** Fase 1 (DB) son cambios aditivos de bajo riesgo (índices, nuevos métodos) antes de tocar árboles de widgets grandes en Fase 2.
- **Punto más riesgoso del plan:** Task 13 (`add_credit_sheet.dart`) es la única tarea sin tests automatizados que la respalden — se señala explícitamente requerir prueba manual de los 3 flujos de crédito antes de cerrarla, y se deja la extracción completa a sub-widgets como paso opcional para no bloquear el fix principal (aislar la preview) si el tiempo apremia.

## Execution Handoff

Plan guardado en `docs/superpowers/plans/2026-10-23-performance-audit-implementation.md`. 21 tareas en 4 fases, ordenadas de mayor impacto/menor riesgo (capa de datos) a menor impacto/mayor costo de assets.

Recomendación: **subagent-driven-development** para la Fase 1 (tareas independientes, mecánicas, bien especificadas — ideal para implementadores frescos por tarea) y para las Fases 3-4. Para la Fase 2, especialmente Task 13 y Task 14, considerar ejecución nativa (tú mismo) dado que requieren juicio de diseño y prueba manual del flujo completo antes de dar por cerrada cada una — un subagente sin ese contexto visual podría marcar "listo" sin haber visto la app correr.

## Estado final (actualizado 2026-10-23, tras la implementación)

Las 21 tareas quedaron resueltas de una de estas tres formas — implementadas, cerradas por no aplicar tras verificación, o diferidas con razón explícita:

| Fase | Tareas | Estado |
|---|---|---|
| 1 — Capa de datos | 1-8 | ✅ Implementadas. Commit `d6e1ae0` (v2.5.1+30). |
| 2 — Rebuilds | 4, 5, 9, 10, 11, 12 | ✅ Implementadas (4 subagentes en paralelo). Commit `3a52162` (v2.5.2+31). |
| 2 — Rebuilds | 13 | ✅ Implementada con un enfoque de menor superficie que el original (memoización por clave en vez de reestructurar a `ValueNotifier`/sub-widgets) — ver nota abajo. Commit `893fc34` (v2.5.4+33). |
| 2 — Rebuilds | 14 | 🟢 **Cerrada, no aplica.** Al revisar los 5 sitios de uso de `finanzasFiltrosProvider`, solo UNA pantalla hace `ref.watch()` del objeto completo; el resto son `ref.read()` puntuales que no causan rebuilds. El fan-out que sugería la auditoría inicial no existe en el código real. Documentado en el commit `b7d6083`. |
| 3 — Listas/imágenes | 15, 16, 17, 18 | ✅ Implementadas (1 subagente). Commit `3a52162` (v2.5.2+31). |
| 4 — Assets/fuentes | 19 | ✅ Implementada — se encontró `python3`+PIL disponible en el entorno (no se necesitó `pngquant`/ImageMagick como preveía el plan). Logos de banco reescalados de 1376×768 a 287×160 (644KB → 66KB, -90%), verificados visualmente sin pérdida de nitidez perceptible al tamaño real de uso (~17px). `KREZIUM_OUTLINE.png` se dejó intacto a propósito: se pinta en mosaico a 170px lógicos, con un margen de solo ~2.6x sobre su tamaño real — mucho menos sobredimensionado que los logos de banco, reducirlo arriesgaba pixelado visible por una ganancia marginal. Commit `b11f608` (v2.5.5+34). |
| 4 — Assets/fuentes | 20 | ✅ Implementada (parcial, por diseño). Se verificó que `FontWeight.w300` de Outfit no se usa en ningún `TextStyle` de toda la app — se eliminó ese peso (~48KB). Los pesos 400/500/600/700 sí están en uso activo (confirmado por grep) y NO se tocaron; no se investigó si existe una versión variable de Outfit que los reemplace a todos, por quedar fuera del tiempo disponible en esta sesión — una oportunidad de ahorro adicional menor, sin urgencia. Commit `b7d6083` (v2.5.3+32). |
| 4 — Backup | 21 | ✅ Implementada (1 subagente). Commit `3a52162` (v2.5.2+31). |

**Nota sobre Task 13 — por qué se implementó distinto a como lo describía el plan:** el plan original pedía aislar `_buildPreviewCredit()`/`_summaryRows()` detrás de un `ValueNotifier` y, opcionalmente, extraer los pasos del wizard a widgets propios — un cambio estructural de superficie amplia en un archivo de 3480 líneas sin suite de widget tests, que el plan mismo señalaba como el punto más riesgoso y pedía probar manualmente los 3 flujos de crédito antes de cerrar. En esta sesión no hubo dispositivo/emulador conectado (el servidor REA no pudo conectar) para hacer esa prueba manual. En su lugar se implementó una memoización por clave de los campos que el método realmente lee: mismo resultado para los mismos valores de entrada, cero cambio de comportamiento, resuelve el costo real (recalcular la amortización completa sin necesidad en cada `setState` del paso de confirmación), y es 100% verificable con `flutter analyze` + la suite de 373 tests existente, sin requerir ejecutar la app. La extracción a sub-widgets queda como posible mejora futura si alguna vez se dispone de tiempo y dispositivo para hacerla con la prueba manual que merece.

**Límite honesto de esta sesión:** todo lo anterior se verificó con análisis estático (`flutter analyze`) y la suite de 373 tests unitarios/de provider/de DB existente — ninguno de los dos mide tiempo de frame, jank ni uso de memoria en un dispositivo real. No hubo emulador ni teléfono conectado en ningún momento de esta sesión para hacer profiling con Flutter DevTools o medir frames perdidos en vivo. El trabajo implementado ataca causas raíz concretas y medibles en el código (table scans sin índice, N+1 queries, recomputo innecesario en rebuilds, decode de imágenes a resolución excesiva) que son la causa típica de "trabas" en una app Flutter — pero la única forma de confirmar con números reales cuánto mejoró la fluidez percibida es perfilar la app compilada en un dispositivo, algo que esta sesión no pudo hacer. Si se cuenta con un dispositivo/emulador en una sesión futura, el primer paso recomendado sería correr `flutter run --profile` y usar el "Performance" tab de DevTools sobre los flujos más pesados (lista de créditos con muchos movimientos, lista de registros con muchas cuentas, el formulario de nuevo crédito) para confirmar las mejoras con datos reales.
