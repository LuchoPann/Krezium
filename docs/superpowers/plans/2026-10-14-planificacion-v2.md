# Planificación v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> (native, en esta misma sesión) para implementar esta plan tarea por tarea.

**Goal:** Implementar la Fase A del roadmap (`docs/finanzas-v2-roadmap.md`):
presupuestos guiados con sugerencia automática + señal de ritmo, y metas
de ahorro con 2 modalidades (virtual/vinculada), historial de
aportes/retiros, y flujo de cierre explícito (completar/cancelar).

**Architecture:** Capa de dominio (funciones puras, testeadas) primero,
migración de schema con test de migración real, luego UI consumiendo lo
anterior vía los providers Riverpod ya existentes. Ningún cálculo de
negocio vive en widgets.

**Tech Stack:** Flutter, Drift (SQLite), Riverpod, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-14-planificacion-v2-design.md`

## Global Constraints

- No tocar Créditos ni su cálculo.
- Transferencias y aportes/retiros de metas nunca son transacciones de
  ingreso/gasto/transferencia (ver spec, Global Constraints).
- Toda migración de schema lleva test de migración real (DB recortada a
  la versión anterior, reabierta con `AppDatabase.forTesting`, `onUpgrade`
  real).
- Metas existentes (creadas antes de esta migración) deben quedar con
  `modalidad = 'vinculada'` y su `accountId` intacto — sin acción del
  usuario.
- `dart analyze` limpio y suite completa de `flutter test` verde antes de
  cerrar cada tarea.
- Nunca correr `flutter run` (instrucción permanente del usuario —
  su propio proceso está corriendo en el dispositivo).

## Review Focus

(copiado de la spec, cada uno con su tarea dueña)
- Meta virtual sin cuenta con saldo suficiente → disponible global
  muestra déficit explícito. Tarea 2.
- Presupuesto con 0-1 meses de datos → campo de límite vacío, sin
  sugerencia fabricada. Tarea 1.
- Cerrar diálogo de completar/cancelar sin elegir opción → la reserva
  sigue intacta. Tarea 5.
- Migración v20→v21 sobre metas ya creadas → sobreviven con
  `modalidad='vinculada'`. Tarea 1 (schema).
- Presupuesto `vaRapido==true` pero ya `agotado` → no mostrar ambos
  mensajes. Tarea 1.

---

### Task 1: Migración de schema v20→v21

**Files:**
- Modify: `lib/data/db/tables_finance.dart` (agregar `modalidad` a
  `FinanceReservations`, volver `accountId` nullable; nueva tabla
  `FinanceGoalMovements`)
- Modify: `lib/data/db/database.dart` (schemaVersion 20→21, bloque
  `onUpgrade`, lista de tablas del `@DriftDatabase`)
- Test: `test/data/db/schema_migration_v20_to_v21_test.dart`
- Correr `dart run build_runner build --delete-conflicting-outputs` para
  regenerar `database.g.dart`.

**Interfaces:**
- Produce: columna `FinanceReservations.modalidad` (`'virtual'` |
  `'vinculada'`, default `'vinculada'`), `FinanceReservations.accountId`
  nullable, tabla `FinanceGoalMovements(id, goalId, tipo, monto, fecha,
  saldoResultante)`.
- Consumido por: Tareas 2-6.

- [ ] **Paso 1: Editar `tables_finance.dart`**

En `FinanceReservations`, cambiar:
```dart
TextColumn get accountId =>
    text().references(FinanceAccounts, #id, onDelete: KeyAction.restrict)();
```
por:
```dart
TextColumn get accountId => text()
    .nullable()
    .references(FinanceAccounts, #id, onDelete: KeyAction.restrict)();
```
y agregar al final de la clase (antes de `primaryKey`):
```dart
// 'virtual' (sin cuenta, descuenta del disponible global) |
// 'vinculada' (accountId fijo, descuenta del disponible de esa cuenta).
TextColumn get modalidad => text().withDefault(const Constant('vinculada'))();
```

Agregar tabla nueva al final del archivo:
```dart
/// Historial de aportes/retiros de una meta (Planificación v2) — antes
/// solo existía el acumulado en FinanceReservations.monto, sin forma de
/// reconstruir qué pasó y cuándo.
@DataClassName('FinanceGoalMovementRow')
class FinanceGoalMovements extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()
      .references(FinanceReservations, #id, onDelete: KeyAction.cascade)();
  TextColumn get tipo => text()(); // 'aporte' | 'retiro'
  RealColumn get monto => real()();
  TextColumn get fecha => text()(); // ISO8601
  RealColumn get saldoResultante => real()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Paso 2: Registrar la tabla nueva en `database.dart`**

Agregar `FinanceGoalMovements` a la lista `tables:` del
`@DriftDatabase(tables: [...])` y al import si hace falta.

- [ ] **Paso 3: Correr build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: genera `FinanceGoalMovementRow`, `FinanceReservationRow`
actualizado (con `modalidad`, `accountId` nullable) en `database.g.dart`.

- [ ] **Paso 4: Subir `schemaVersion` y escribir el bloque `onUpgrade`**

En `database.dart`, `schemaVersion` pasa de `20` a `21`. Agregar, después
del bloque `if (from < 20) {...}` ya existente:

```dart
if (from < 21) {
  await m.createTable(financeGoalMovements);
  // accountId pasa a nullable: SQLite no soporta ALTER COLUMN para
  // quitar NOT NULL, así que se reconstruye la tabla (patrón estándar
  // de migración SQLite: crear nueva, copiar datos, borrar vieja,
  // renombrar). 'modalidad' se agrega directo porque sí es un ADD COLUMN
  // normal.
  final hasModalidad = await m.database
      .customSelect("PRAGMA table_info(finance_reservations)")
      .get()
      .then((rows) => rows.any((r) => r.data['name'] == 'modalidad'));
  if (!hasModalidad) {
    await m.addColumn(financeReservations, financeReservations.modalidad);
  }
  await m.database.customStatement('''
    CREATE TABLE IF NOT EXISTS finance_reservations_new (
      id TEXT NOT NULL PRIMARY KEY,
      account_id TEXT NULL REFERENCES finance_accounts(id),
      nombre TEXT NOT NULL,
      monto REAL NOT NULL,
      creada_en TEXT NOT NULL,
      monto_objetivo REAL NOT NULL DEFAULT 0,
      fecha_limite TEXT NULL,
      estado TEXT NOT NULL DEFAULT 'activa',
      modalidad TEXT NOT NULL DEFAULT 'vinculada'
    )
  ''');
  await m.database.customStatement('''
    INSERT INTO finance_reservations_new
    SELECT id, account_id, nombre, monto, creada_en, monto_objetivo,
           fecha_limite, estado, modalidad
    FROM finance_reservations
  ''');
  await m.database
      .customStatement('DROP TABLE finance_reservations');
  await m.database.customStatement(
      'ALTER TABLE finance_reservations_new RENAME TO finance_reservations');
}
```

Nota para quien implemente: verificar el nombre real de tabla/columnas
generado por Drift (`finance_reservations`, `account_id`, etc. — Drift
usa snake_case del nombre de la clase/columna salvo `@DataClassName`
distinto) antes de pegar este SQL; ajustar si el nombre real difiere.

- [ ] **Paso 5: Test de migración real**

Crear `test/data/db/schema_migration_v20_to_v21_test.dart` siguiendo el
patrón exacto de `test/data/db/schema_migration_v19_to_v20_test.dart`:
abrir una DB en memoria con el schema actual (v21), insertar una cuenta y
una meta vinculada con datos reales, cerrar; reabrir una conexión cruda y
recortarla a v20 (quitar columna `modalidad`, recrear
`finance_reservations` sin ella si hace falta, `DROP TABLE
finance_goal_movements`, `PRAGMA user_version = 20`); reabrir con
`AppDatabase.forTesting` (dispara el `onUpgrade` real) y verificar:
- La meta sobrevive con todos sus campos originales intactos.
- `modalidad == 'vinculada'` y `accountId` es el original (no null).
- Insertar una fila en `finance_goal_movements` funciona.

- [ ] **Paso 6: Correr tests y verificar**

```bash
flutter test test/data/db/
dart analyze lib/data/db/
```
Expected: todo verde, sin warnings nuevos.

- [ ] **Paso 7: Commit**

```bash
git add lib/data/db/tables_finance.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/db/schema_migration_v20_to_v21_test.dart
git commit -m "feat(finanzas): schema v21 — metas con modalidad virtual/vinculada + historial de movimientos"
```

---

### Task 2: Dominio — presupuestos guiados (sugerencia + ritmo)

**Files:**
- Modify: `lib/domain/finance_budget.dart`
- Test: `test/domain/finance_budget_test.dart`

**Interfaces:**
- Consume: `FinanceTransaction`, `gastoCategoriaPeriodo` (ya existentes).
- Produce: `sugerenciaPresupuesto(...)`, `vaRapido(...)` — consumidas por
  Tarea 4 (UI de presupuestos).

- [ ] **Paso 1: Test de `sugerenciaPresupuesto` — con datos suficientes**

```dart
test('sugiere la mediana de 3 meses cuando al menos 2 tienen gasto', () {
  final hoy = DateTime(2026, 10, 15);
  final txs = [
    _gasto('comida', 100000, '2026-07-10'),
    _gasto('comida', 200000, '2026-08-10'),
    // septiembre sin gasto
  ];
  final r = sugerenciaPresupuesto(
    categoryId: 'comida',
    transacciones: txs,
    parentPorCategoria: {},
    hoy: hoy,
  );
  expect(r, isNotNull);
  expect(r!.sugerido, 100000); // mediana de [100000, 200000, 0]
});
```

- [ ] **Paso 2: Correr, verificar que falla** (`sugerenciaPresupuesto` no
  existe).

- [ ] **Paso 3: Test — sin datos suficientes (solo 1 mes con gasto)**

```dart
test('no sugiere nada con menos de 2 meses con gasto', () {
  final hoy = DateTime(2026, 10, 15);
  final txs = [_gasto('comida', 100000, '2026-08-10')];
  final r = sugerenciaPresupuesto(
    categoryId: 'comida', transacciones: txs,
    parentPorCategoria: {}, hoy: hoy,
  );
  expect(r, isNull);
});
```

- [ ] **Paso 4: Implementar `sugerenciaPresupuesto`**

```dart
({double sugerido, List<({int year, int month, double monto})> meses})?
    sugerenciaPresupuesto({
  required String categoryId,
  required List<FinanceTransaction> transacciones,
  required Map<String, String?> parentPorCategoria,
  required DateTime hoy,
}) {
  final meses = <({int year, int month, double monto})>[];
  for (int i = 3; i >= 1; i--) {
    final d = DateTime(hoy.year, hoy.month - i);
    final gastoMes = transacciones.where((t) {
      final prefix = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      return t.fecha.startsWith(prefix);
    }).toList();
    final monto = gastoCategoriaPeriodo(
      categoryId: categoryId,
      transacciones: gastoMes,
      parentPorCategoria: parentPorCategoria,
    );
    meses.add((year: d.year, month: d.month, monto: monto));
  }
  final conGasto = meses.where((m) => m.monto > 0).length;
  if (conGasto < 2) return null;
  final montos = meses.map((m) => m.monto).toList()..sort();
  final mediana = montos[1]; // de 3 elementos ordenados, el del medio
  return (sugerido: mediana, meses: meses);
}
```

- [ ] **Paso 5: Correr, verificar que ambos tests pasan.**

- [ ] **Paso 6: Test de `vaRapido`**

```dart
test('vaRapido true cuando el consumo supera el tiempo transcurrido por más del margen', () {
  final result = vaRapido(
    progreso: 0.75,
    inicioPeriodo: DateTime(2026, 10, 1),
    finPeriodo: DateTime(2026, 10, 31),
    hoy: DateTime(2026, 10, 10), // ~30% transcurrido
  );
  expect(result, isTrue);
});

test('vaRapido false si ya está agotado (progreso >= 1.0)', () {
  final result = vaRapido(
    progreso: 1.2,
    inicioPeriodo: DateTime(2026, 10, 1),
    finPeriodo: DateTime(2026, 10, 31),
    hoy: DateTime(2026, 10, 10),
  );
  expect(result, isFalse);
});
```

- [ ] **Paso 7: Implementar `vaRapido`**

```dart
bool vaRapido({
  required double progreso,
  required DateTime inicioPeriodo,
  required DateTime finPeriodo,
  required DateTime hoy,
  double margen = 0.15,
}) {
  if (progreso >= 1.0) return false;
  final duracionTotal = finPeriodo.difference(inicioPeriodo).inMinutes;
  if (duracionTotal <= 0) return false;
  final transcurrido = hoy.difference(inicioPeriodo).inMinutes;
  final fraccion = (transcurrido / duracionTotal).clamp(0.0, 1.0);
  return progreso - fraccion > margen;
}
```

- [ ] **Paso 8: Correr todos los tests de `finance_budget_test.dart`,
  verificar verde.**

- [ ] **Paso 9: Commit**

```bash
git add lib/domain/finance_budget.dart test/domain/finance_budget_test.dart
git commit -m "feat(finanzas): sugerencia de presupuesto por mediana + señal de ritmo"
```

---

### Task 3: Dominio — modalidad de metas y disponible global

**Files:**
- Modify: `lib/domain/finance_ledger.dart`
- Test: `test/domain/finance_ledger_test.dart`

**Interfaces:**
- Consume: lista de reservas (ya tipadas con el `modalidad` nuevo de
  Tarea 1, vía el modelo `FinanceReservation` regenerado).
- Produce: `totalReservadoVirtual(...)`; modifica `totalReservado(...)`
  para excluir virtuales.

- [ ] **Paso 1: Test — `totalReservado` excluye reservas virtuales**

```dart
test('totalReservado solo cuenta reservas vinculadas a esta cuenta, nunca virtuales', () {
  final reservas = [
    _reserva(accountId: 'cta1', monto: 100, modalidad: 'vinculada', estado: 'activa'),
    _reserva(accountId: null, monto: 500, modalidad: 'virtual', estado: 'activa'),
  ];
  expect(totalReservado(reservas, 'cta1'), 100);
});
```

- [ ] **Paso 2: Correr, verificar que falla o pasa por casualidad —
  ajustar fixture si hace falta para que falle de verdad primero
  (agregar explícitamente la reserva virtual con accountId null para
  forzar el caso que antes no se filtraba).**

- [ ] **Paso 3: Ajustar `totalReservado`** para filtrar
  `r.modalidad == 'vinculada' && r.accountId == accountId &&
  r.estado != 'cancelada'`.

- [ ] **Paso 4: Test — `totalReservadoVirtual`**

```dart
test('totalReservadoVirtual suma solo reservas virtuales activas/pausadas', () {
  final reservas = [
    _reserva(accountId: null, monto: 500, modalidad: 'virtual', estado: 'activa'),
    _reserva(accountId: null, monto: 300, modalidad: 'virtual', estado: 'cancelada'),
    _reserva(accountId: 'cta1', monto: 100, modalidad: 'vinculada', estado: 'activa'),
  ];
  expect(totalReservadoVirtual(reservas), 500);
});
```

- [ ] **Paso 5: Implementar `totalReservadoVirtual`**

```dart
double totalReservadoVirtual(List<FinanceReservation> reservas) {
  return reservas
      .where((r) => r.modalidad == 'virtual' && r.estado != 'cancelada')
      .fold(0.0, (s, r) => s + r.monto);
}
```

- [ ] **Paso 6: Correr todos los tests, verde.**

- [ ] **Paso 7: Commit**

```bash
git add lib/domain/finance_ledger.dart test/domain/finance_ledger_test.dart
git commit -m "feat(finanzas): disponible global descuenta reservas virtuales, nunca las vinculadas de otra cuenta"
```

---

### Task 4: UI — flujo guiado de creación de presupuesto

**Files:**
- Modify: `lib/screens/finanzas/finanzas_planificacion_screen.dart` (o
  el archivo que contenga `_PresupuestoFormSheet` hoy — confirmar con
  `grep -rn "_PresupuestoFormSheet"` antes de editar, puede vivir en
  `finanzas_presupuesto_screen.dart` según Fase 04).
- Test manual (no hay testing de widgets establecido en este módulo —
  mismo patrón que fases anteriores: `dart analyze` + `flutter test` de
  dominio, verificación visual por el usuario).

**Interfaces:**
- Consume: `sugerenciaPresupuesto`, `vaRapido` (Tarea 2),
  `upsertFinanceBudget` (ya existente).

- [ ] **Paso 1: Localizar el formulario actual**

```bash
grep -rn "_PresupuestoFormSheet" lib/screens/finanzas/
```

- [ ] **Paso 2: Reestructurar el sheet en 4 pasos** (usar un `PageView`
  o un `int _paso` con `IndexedStack`, consistente con el patrón de
  pasos ya usado en `nueva_transaccion_sheet.dart` si existe algo
  similar — si no, un `Stepper` simple de Material basta):
  1. Categoría (reusa el picker ya existente).
  2. Sugerencia — llama `sugerenciaPresupuesto` con las transacciones del
     registro activo (o todas, a decidir según si presupuestos son
     globales o por registro — **verificar en el código actual**: hoy
     `financeBudgetsProvider` parece global, no por libro — confirmar
     antes de filtrar transacciones por un registro específico).
  3. Ajuste del límite (campo ya existente, reusar
     `MontoInputFormatter`).
  4. Confirmación (resumen, botón guardar llama `upsertFinanceBudget`
     sin cambios).

- [ ] **Paso 3: Agregar el texto de ritmo a la tarjeta de presupuesto
  existente** (no es parte del formulario de creación — es la tarjeta
  que ya muestra %, gastado, límite): calcular `vaRapido` con
  `inicioPeriodo`/`finPeriodo` del mes del presupuesto, mostrar el texto
  solo si `true`.

- [ ] **Paso 4: `dart analyze` + `flutter test` completos, verde.**

- [ ] **Paso 5: Commit**

```bash
git add lib/screens/finanzas/
git commit -m "feat(finanzas): flujo guiado de creación de presupuesto con sugerencia y señal de ritmo"
```

---

### Task 5: UI — creación de meta con modalidad + historial de movimientos

**Files:**
- Modify: `lib/screens/finanzas/finanzas_metas_screen.dart`
  (`_MetaFormSheet`, `_AportarRetirarSheet`)
- Modify: `lib/providers/database_provider.dart` /
  `finance_provider.dart` (exponer insert en `FinanceGoalMovements` y
  query de historial por `goalId`)

**Interfaces:**
- Consume: schema de Tarea 1.
- Produce: `insertFinanceGoalMovement(...)`,
  `getFinanceGoalMovements(goalId)` en la capa de DB; sección
  "Historial" en la pantalla de detalle de meta.

- [ ] **Paso 1: Agregar a `database.dart`** (o el archivo de queries de
  Finanzas):
```dart
Future<void> insertFinanceGoalMovement(FinanceGoalMovementsCompanion row) =>
    into(financeGoalMovements).insert(row);

Future<List<FinanceGoalMovementRow>> getFinanceGoalMovements(String goalId) =>
    (select(financeGoalMovements)
          ..where((t) => t.goalId.equals(goalId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha)]))
        .get();
```

- [ ] **Paso 2: `_MetaFormSheet` — agregar selector de modalidad**
  (`ChoiceChip`/`RadioListTile` virtual vs. vinculada; si vinculada,
  mostrar el selector de registro ya existente; si virtual, ocultarlo).
  Al guardar, setear `modalidad` y `accountId` (null si virtual) en el
  companion de `upsertFinanceReservation`.

- [ ] **Paso 3: `_AportarRetirarSheet` — registrar el movimiento**
  después de un aportar/retirar exitoso, llamar
  `insertFinanceGoalMovement` con `tipo`, `monto`, `fecha: DateTime.now()
  .toIso8601String()`, `saldoResultante: nuevoMontoDeLaMeta`.

- [ ] **Paso 4: Sección "Historial" en el detalle de meta** — `ListView`
  de solo lectura con las filas de `getFinanceGoalMovements`, más
  reciente primero, mostrando tipo/monto/fecha/saldo resultante.

- [ ] **Paso 5: `dart analyze` + `flutter test`, verde.**

- [ ] **Paso 6: Commit**

```bash
git add lib/screens/finanzas/finanzas_metas_screen.dart lib/data/db/database.dart lib/providers/finance_provider.dart
git commit -m "feat(finanzas): metas con modalidad virtual/vinculada e historial de aportes/retiros"
```

---

### Task 6: UI — flujo de cierre de meta (completar/cancelar compartido)

**Files:**
- Modify: `lib/screens/finanzas/finanzas_metas_screen.dart` (nuevo
  `_CierreMetaSheet` compartido entre completar y cancelar)
- Modify: `lib/screens/finanzas/nueva_transaccion_sheet.dart` (reuso
  directo para la opción "gasto inmediato" — confirmar que acepta un
  `montoInicial`/`libroInicial` prellenado; si no, agregar esos
  parámetros opcionales)

**Interfaces:**
- Consume: `showNuevaTransaccionSheet` (ya existente, posible extensión
  de parámetros), `upsertFinanceReservation`, registros existentes vía
  `financeAccountsProvider`.

- [ ] **Paso 1: Construir `_CierreMetaSheet`** — recibe la meta y el
  tipo de cierre (`completar`|`cancelar`), muestra el monto reservado y
  2 botones: "Gastar ahora" / "Mantener en un registro". Si el usuario
  cierra el sheet sin elegir (back/swipe), no se aplica ningún cambio —
  la reserva sigue como estaba (verificar que `showModalBottomSheet`
  devuelve `null` en ese caso y el código no actúa sobre `null`).

- [ ] **Paso 2: Opción "Gastar ahora"** — llama
  `showNuevaTransaccionSheet` con `tipo: 'gasto'`, monto prellenado =
  monto reservado, `libroId`: el de la meta si vinculada, o a elegir si
  virtual (selector simple antes de abrir el sheet). Al confirmarse la
  transacción, actualizar `estado` de la reserva a `finalizada` o
  `cancelada` según el origen, y poner `monto = 0`.

- [ ] **Paso 3: Opción "Mantener en un registro"** — selector: registro
  actual (si vinculada) / elegir otro existente / crear uno nuevo (reusa
  el flujo corto de creación de registro ya existente en
  `finanzas_cuentas_screen.dart`). Al confirmar: sumar el monto al saldo
  de ese registro (ajuste directo — **definir el mecanismo exacto**:
  revisar si existe ya una forma de "ajuste de saldo" sin transacción, o
  si hace falta agregar un campo de ajuste manual a `FinanceAccounts`;
  si no existe, la opción más simple y consistente con el resto del
  módulo es un `saldoInicial` recalculado — documentar la decisión
  tomada en el código con un comentario corto). Guardar nota "Proveniente
  de meta: {nombre}" en el campo `descripcion` del registro (ya existe
  desde Fase 03). Cerrar la reserva igual que en el Paso 2.

- [ ] **Paso 4: Reemplazar los botones actuales de "Completar"/
  "Cancelar"** en el menú de la meta para que abran `_CierreMetaSheet`
  en vez del comportamiento silencioso de hoy.

- [ ] **Paso 5: `dart analyze` + `flutter test`, verde.**

- [ ] **Paso 6: Commit**

```bash
git add lib/screens/finanzas/
git commit -m "feat(finanzas): completar/cancelar meta pregunta explícitamente qué hacer con la reserva"
```

---

### Task 7: UI — borrado protegido de cuenta con meta vinculada

**Files:**
- Modify: `lib/screens/finanzas/finanzas_cuentas_screen.dart` (manejo
  del error de `onDelete: restrict` al borrar un registro)

**Interfaces:**
- Consume: excepción de Drift al violar la FK, `allFinanceReservationsProvider`.

- [ ] **Paso 1: Capturar el error de borrado** y, si el registro tiene
  una meta vinculada `activa`/`pausada`, mostrar un diálogo con esa meta
  y 2 acciones: "Reasignar a otra cuenta" (selector de registro, cambia
  `accountId`) / "Convertir a virtual" (pone `accountId = null,
  modalidad = 'virtual'`).

- [ ] **Paso 2: `dart analyze` + `flutter test`, verde.**

- [ ] **Paso 3: Commit**

```bash
git add lib/screens/finanzas/finanzas_cuentas_screen.dart
git commit -m "feat(finanzas): borrar un registro con meta vinculada ofrece reasignar o convertir a virtual"
```

---

## Orden de ejecución

Tareas 1→7 en orden estricto — cada una depende de la anterior (schema
primero, dominio después, UI al final). No paralelizable dentro de esta
plan.
