# Finanzas Fase 01 — Integridad financiera y cálculos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corregir las transferencias entre registros (hoy inertes), centralizar el cálculo de saldo en un solo lugar, implementar archivar/reactivar/eliminar-con-advertencia de registros, añadir el modelo de dominio mínimo para reservas/disponible estimado, y señalar (sin inventar) las transferencias históricas ambiguas.

**Architecture:** Nuevo servicio de dominio puro `lib/domain/finance_ledger.dart` (sin estado, sin DB) con las fórmulas contables. La capa de datos (`database.dart`) gana una query que trae transacciones por ambos lados de una transferencia y los métodos de ciclo de vida de registros/reservas. Un único provider (`financeAccountBalanceProvider`) en `finance_provider.dart` reemplaza los 4 cálculos duplicados; las pantallas pasan a consumirlo.

**Tech Stack:** Flutter/Dart, Drift (SQLite), Riverpod (`FutureProvider`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-13-finanzas-fase01-integridad.md`

## Global Constraints

- schemaVersion actual: 18 (`lib/data/db/database.dart:49`). Esta fase sube a 19.
- No tocar navegación, Plantillas, Estadísticas (salvo el cálculo de saldo), Presupuestos, metas de ahorro como feature de UI.
- No contar una transferencia como ingreso/gasto en ningún cálculo.
- No contar el mismo dinero dos veces (saldo vs. disponible estimado).
- Las transferencias históricas ambiguas se señalan, nunca se inventan ni se eliminan.
- Archivar nunca borra transacciones ni altera saldos históricos; reutilizar el campo `activa` existente (`FinanceAccounts.activa`, `tables_finance.dart:11`), no crear uno nuevo.
- Eliminación física definitiva solo con confirmación explícita fuerte cuando el registro tiene movimientos (decisión del usuario, amplía la recomendación de GPT).
- Toda migración de schema debe seguir el patrón ya usado en el proyecto: guardas con `PRAGMA table_info`/`sqlite_master` antes de `addColumn`/`createTable` (ver `database.dart:166-209`) para tolerar dispositivos de desarrollo con hot-restart.
- No introducir servicios externos, sincronización en la nube, ni reescribir registros/transacciones/categorías/historial/plantillas que ya funcionan.

## Review Focus

- Transacción con `tipo=='transferencia'` y `transferToAccountId == accountId` (transferencia a sí mismo) — debe rechazarse antes de guardar, no solo documentarse.
- Transacción con `tipo=='transferencia'` y `transferToAccountId` apuntando a un registro que ya no existe (borrado físicamente antes de esta fase, dato huérfano real) — el cálculo de saldo del origen no debe explotar ni ignorar silenciosamente el efecto en el origen.
- Reserva (`FinanceReservations`) cuyo monto supera el saldo del registro al que pertenece — debe persistir tal cual y quedar visible como inconsistencia, no clamparse a 0 ni al saldo disponible.
- Edición de una transacción que cambia su `tipo` de `'ingreso'`/`'gasto'` a `'transferencia'` (o viceversa) vía el mismo formulario — el saldo recalculado debe reflejar el nuevo tipo, no sumar ambos efectos.
- Archivar un registro que es el `transferToAccountId` de transacciones de otro registro — esas transacciones deben seguir siendo consultables y su efecto en el saldo del registro archivado debe seguir siendo correcto.

---

### Task 1: Reglas contables formalizadas + migración de schema (v18→v19)

**Files:**
- Create: `docs/finanzas-reglas-contables.md`
- Modify: `lib/data/db/tables_finance.dart`
- Modify: `lib/data/db/database.dart` (bump `schemaVersion`, migración, nuevos métodos CRUD de reservas)
- Test: `test/db/finance_tables_migration_test.dart`

**Interfaces:**
- Produces: tabla `FinanceReservations` (`id text pk`, `accountId text FK→FinanceAccounts (restrict)`, `nombre text`, `monto real`, `creadaEn text`); columna nueva `FinanceTransactions.revisionNota` (`text nullable`).
- Produces: `AppDatabase.getFinanceReservations(String accountId)`, `AppDatabase.upsertFinanceReservation(FinanceReservationsCompanion)`, `AppDatabase.deleteFinanceReservation(String id)`.

- [ ] **Step 1: Escribir `docs/finanzas-reglas-contables.md`**

Documento corto (no código) con las reglas obligatorias de la sección 3 de la spec, en formato de lista verificable: qué suma/resta saldo, cómo se calcula el saldo agregado, cómo se tratan transferencias en origen/destino, cómo se calcula el disponible estimado, qué pasa al archivar/eliminar un registro, qué pasa con una reserva que excede el saldo, qué pasa con una transferencia histórica sin destino. Este documento es la referencia que las Tasks siguientes implementan; si una Task descubre una contradicción, se corrige aquí primero.

- [ ] **Step 2: Añadir tabla `FinanceReservations` y columna `revisionNota`**

En `lib/data/db/tables_finance.dart`, después de `FinanceBudgets`:

```dart
@DataClassName('FinanceReservationRow')
class FinanceReservations extends Table {
  TextColumn get id => text()();
  TextColumn get accountId =>
      text().references(FinanceAccounts, #id, onDelete: KeyAction.restrict)();
  TextColumn get nombre => text()();
  RealColumn get monto => real()();
  TextColumn get creadaEn => text()(); // ISO8601

  @override
  Set<Column> get primaryKey => {id};
}
```

En `FinanceTransactions` (misma tabla), añadir tras `transferToAccountId`:

```dart
  TextColumn get revisionNota => text().nullable()();
```

- [ ] **Step 3: Escribir el test de migración que falla**

En `test/db/finance_tables_migration_test.dart`, añadir:

```dart
  test('v19: FinanceReservations existe y revisionNota es consultable', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.getFinanceReservations('cualquiera');
    final txs = await db.getFinanceTransactions();
    expect(txs, isEmpty); // solo confirma que la query no explota con la columna nueva
    await db.close();
  });
```

- [ ] **Step 4: Run test para confirmar que falla**

Run: `flutter test test/db/finance_tables_migration_test.dart`
Expected: FAIL — `getFinanceReservations` no existe (error de compilación) o tabla inexistente.

- [ ] **Step 5: Registrar la tabla, subir schemaVersion y añadir la migración guardada**

En `lib/data/db/database.dart`:
- Añadir `FinanceReservations` al arreglo `@DriftDatabase(tables: [...])` (línea ~39).
- Cambiar `int get schemaVersion => 19;` (línea 49).
- Dentro de `onUpgrade`, después del bloque `if (from < 18) { ... }` existente (línea ~210), añadir:

```dart
          if (from < 19) {
            if (!await tableExists('finance_reservations')) {
              await m.createTable(financeReservations);
            }
            final txCols = await colsOf('finance_transactions');
            if (!txCols.contains('revision_nota')) {
              await m.addColumn(financeTransactions, financeTransactions.revisionNota);
            }
          }
```

`tableExists`/`colsOf` ya están definidos como funciones locales dentro de `migration` (línea ~167-178, dentro del bloque `if (from < 17)`) — sácalas de ese bloque a nivel de `onUpgrade` (antes del primer `if`) para poder reutilizarlas en el bloque `from < 19` sin duplicar código.

- [ ] **Step 6: Añadir los métodos CRUD de reservas**

En `lib/data/db/database.dart`, después de `upsertFinanceBudget` (línea ~785):

```dart
  // --- Finance Reservations ---

  Future<List<FinanceReservationRow>> getFinanceReservations(String accountId) =>
      (select(financeReservations)..where((r) => r.accountId.equals(accountId))).get();

  Future<void> upsertFinanceReservation(FinanceReservationsCompanion row) =>
      into(financeReservations).insertOnConflictUpdate(row);

  Future<void> deleteFinanceReservation(String id) =>
      (delete(financeReservations)..where((r) => r.id.equals(id))).go();
```

- [ ] **Step 7: Correr `dart run build_runner build` para regenerar `database.g.dart`**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: genera `FinanceReservationRow`, `FinanceReservationsCompanion`, `$FinanceReservationsTable` sin errores.

- [ ] **Step 8: Run test para confirmar que pasa**

Run: `flutter test test/db/finance_tables_migration_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add docs/finanzas-reglas-contables.md lib/data/db/tables_finance.dart lib/data/db/database.dart lib/data/db/database.g.dart test/db/finance_tables_migration_test.dart
git commit -m "feat(finanzas): agrega tabla de reservas y columna revisionNota (schema v19)"
```

---

### Task 2: Servicio de dominio `finance_ledger.dart` — cálculo centralizado

**Files:**
- Create: `lib/domain/finance_ledger.dart`
- Test: `test/domain/finance_ledger_test.dart`

**Interfaces:**
- Consumes: `FinanceTransaction` (`lib/data/models/finance_models.dart:103`), `FinanceAccount` (línea 3), `FinanceReservationRow` (de Task 1).
- Produces:
  - `double signedEffectForLibro(FinanceTransaction t, String libroId)`
  - `double calcularSaldo({required double saldoInicial, required List<FinanceTransaction> txsInvolucradas, required String libroId})`
  - `({double ingresos, double gastos}) calcularIngresosGastos(List<FinanceTransaction> txs, String libroId)`
  - `double totalReservado(List<FinanceReservationRow> reservas)`
  - `({double disponibleEstimado, bool reservasExcedenSaldo}) calcularDisponibleEstimado({required double saldo, required double reservado})`

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/domain/finance_ledger_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_ledger.dart';

FinanceTransaction _tx({
  required String accountId,
  required String tipo,
  required double monto,
  String? transferToAccountId,
}) => FinanceTransaction(
      id: 't-$accountId-$tipo-$monto',
      accountId: accountId,
      categoryId: 'cat',
      tipo: tipo,
      monto: monto,
      fecha: '2026-10-01',
      nota: '',
      esRecurrente: false,
      transferToAccountId: transferToAccountId,
    );

void main() {
  group('signedEffectForLibro', () {
    test('ingreso en el propio libro suma', () {
      final t = _tx(accountId: 'A', tipo: 'ingreso', monto: 100);
      expect(signedEffectForLibro(t, 'A'), 100);
    });

    test('gasto en el propio libro resta', () {
      final t = _tx(accountId: 'A', tipo: 'gasto', monto: 50);
      expect(signedEffectForLibro(t, 'A'), -50);
    });

    test('transferencia: resta en el origen', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 30, transferToAccountId: 'B');
      expect(signedEffectForLibro(t, 'A'), -30);
    });

    test('transferencia: suma en el destino', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 30, transferToAccountId: 'B');
      expect(signedEffectForLibro(t, 'B'), 30);
    });

    test('transferencia sin destino no afecta ningún otro libro', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 30);
      expect(signedEffectForLibro(t, 'B'), 0);
    });

    test('transacción de otro libro no afecta', () {
      final t = _tx(accountId: 'A', tipo: 'ingreso', monto: 100);
      expect(signedEffectForLibro(t, 'Z'), 0);
    });
  });

  group('calcularSaldo', () {
    test('saldo inicial más efectos de todas las transacciones involucradas', () {
      final txs = [
        _tx(accountId: 'A', tipo: 'ingreso', monto: 200),
        _tx(accountId: 'A', tipo: 'gasto', monto: 50),
        _tx(accountId: 'A', tipo: 'transferencia', monto: 30, transferToAccountId: 'B'),
        _tx(accountId: 'C', tipo: 'transferencia', monto: 500, transferToAccountId: 'A'),
      ];
      final saldo = calcularSaldo(saldoInicial: 100, txsInvolucradas: txs, libroId: 'A');
      expect(saldo, 100 + 200 - 50 - 30 + 500);
    });
  });

  group('calcularIngresosGastos', () {
    test('una transferencia no cuenta como ingreso ni como gasto', () {
      final txs = [
        _tx(accountId: 'A', tipo: 'ingreso', monto: 100),
        _tx(accountId: 'A', tipo: 'gasto', monto: 40),
        _tx(accountId: 'A', tipo: 'transferencia', monto: 999, transferToAccountId: 'B'),
        _tx(accountId: 'B', tipo: 'transferencia', monto: 999, transferToAccountId: 'A'),
      ];
      final r = calcularIngresosGastos(txs, 'A');
      expect(r.ingresos, 100);
      expect(r.gastos, 40);
    });
  });

  group('calcularDisponibleEstimado', () {
    test('sin reservas, disponible == saldo', () {
      final r = calcularDisponibleEstimado(saldo: 500, reservado: 0);
      expect(r.disponibleEstimado, 500);
      expect(r.reservasExcedenSaldo, false);
    });

    test('con reservas, se descuentan del saldo', () {
      final r = calcularDisponibleEstimado(saldo: 500, reservado: 150);
      expect(r.disponibleEstimado, 350);
      expect(r.reservasExcedenSaldo, false);
    });

    test('reservas que exceden el saldo: no se oculta, se señala', () {
      final r = calcularDisponibleEstimado(saldo: 100, reservado: 300);
      expect(r.disponibleEstimado, -200);
      expect(r.reservasExcedenSaldo, true);
    });
  });
}
```

- [ ] **Step 2: Run tests para confirmar que fallan**

Run: `flutter test test/domain/finance_ledger_test.dart`
Expected: FAIL — `package:krezium/domain/finance_ledger.dart` no existe.

- [ ] **Step 3: Implementar `lib/domain/finance_ledger.dart`**

```dart
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/finance_models.dart';

/// Efecto con signo que [t] tiene sobre el saldo del registro [libroId].
/// Una transferencia resta en su registro de origen (accountId) y suma en
/// su registro de destino (transferToAccountId) — nunca en ambos a la vez
/// para el mismo [libroId], y nunca se cuenta como ingreso/gasto.
double signedEffectForLibro(FinanceTransaction t, String libroId) {
  if (t.tipo == 'transferencia') {
    if (t.accountId == libroId) return -t.monto;
    if (t.transferToAccountId == libroId) return t.monto;
    return 0;
  }
  if (t.accountId != libroId) return 0;
  if (t.tipo == 'ingreso') return t.monto;
  if (t.tipo == 'gasto') return -t.monto;
  return 0;
}

/// [txsInvolucradas] debe incluir tanto las transacciones cuyo accountId es
/// [libroId] como aquellas transferencias cuyo transferToAccountId es
/// [libroId] (ver AppDatabase.getFinanceTransactionsInvolvingLibro).
double calcularSaldo({
  required double saldoInicial,
  required List<FinanceTransaction> txsInvolucradas,
  required String libroId,
}) {
  var saldo = saldoInicial;
  for (final t in txsInvolucradas) {
    saldo += signedEffectForLibro(t, libroId);
  }
  return saldo;
}

/// Ingresos y gastos reales de [libroId] — una transferencia nunca entra
/// aquí, sea cual sea su dirección.
({double ingresos, double gastos}) calcularIngresosGastos(
  List<FinanceTransaction> txs,
  String libroId,
) {
  var ingresos = 0.0;
  var gastos = 0.0;
  for (final t in txs) {
    if (t.accountId != libroId) continue;
    if (t.tipo == 'ingreso') ingresos += t.monto;
    if (t.tipo == 'gasto') gastos += t.monto;
  }
  return (ingresos: ingresos, gastos: gastos);
}

double totalReservado(List<FinanceReservationRow> reservas) =>
    reservas.fold(0.0, (sum, r) => sum + r.monto);

/// El disponible estimado nunca oculta una inconsistencia: si las reservas
/// superan el saldo, [disponibleEstimado] queda negativo y
/// [reservasExcedenSaldo] en true — la UI decide cómo señalarlo, este
/// cálculo no lo oculta ni lo clampa a 0.
({double disponibleEstimado, bool reservasExcedenSaldo}) calcularDisponibleEstimado({
  required double saldo,
  required double reservado,
}) {
  final disponible = saldo - reservado;
  return (disponibleEstimado: disponible, reservasExcedenSaldo: reservado > saldo);
}
```

- [ ] **Step 4: Run tests para confirmar que pasan**

Run: `flutter test test/domain/finance_ledger_test.dart`
Expected: PASS, todos los grupos.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/finance_ledger.dart test/domain/finance_ledger_test.dart
git commit -m "feat(finanzas): servicio de dominio centralizado para saldo, transferencias y disponible estimado"
```

---

### Task 3: Query de transacciones por ambos lados de una transferencia + ciclo de vida de registros (archivar/reactivar/eliminar seguro)

**Files:**
- Modify: `lib/data/db/database.dart`
- Test: `test/db/finance_ledger_db_test.dart` (nuevo)

**Interfaces:**
- Consumes: `finance_ledger.dart` (Task 2) solo en el test de integración, no en `database.dart` (la capa de datos no debe conocer el dominio contable).
- Produces:
  - `Future<List<FinanceTransactionRow>> getFinanceTransactionsInvolvingLibro({required String libroId, String? mes, bool ascending = false})`
  - `Future<int> countTransactionsForAccount(String accountId)` (cuenta como origen o como destino de transferencia)
  - `Future<void> archiveFinanceAccount(String id)`
  - `Future<void> reactivateFinanceAccount(String id)`
  - `Future<List<FinanceAccountRow>> getFinanceAccounts({bool incluirArchivadas = false})` (reemplaza la firma anterior sin parámetros; todas las llamadas existentes sin argumento siguen compilando porque el parámetro tiene default)
  - `class AccountHasTransactionsException implements Exception { final int count; }`
  - `Future<void> deleteFinanceAccountSafely(String id)` (lanza `AccountHasTransactionsException` si `countTransactionsForAccount > 0`)
  - `Future<void> deleteFinanceAccountAndHistory(String id)` (borrado físico explícito: borra transacciones propias y luego el registro, en una transacción SQLite — solo se llama tras confirmación fuerte en la UI)

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/db/finance_ledger_db_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests para confirmar que fallan**

Run: `flutter test test/db/finance_ledger_db_test.dart`
Expected: FAIL — los métodos no existen.

- [ ] **Step 3: Implementar en `lib/data/db/database.dart`**

Reemplazar `getFinanceAccounts()` (línea 692-693) por:

```dart
  Future<List<FinanceAccountRow>> getFinanceAccounts({bool incluirArchivadas = false}) {
    final q = select(financeAccounts);
    if (!incluirArchivadas) q.where((t) => t.activa.equals(true));
    return q.get();
  }

  Future<void> archiveFinanceAccount(String id) =>
      (update(financeAccounts)..where((t) => t.id.equals(id)))
          .write(const FinanceAccountsCompanion(activa: Value(false)));

  Future<void> reactivateFinanceAccount(String id) =>
      (update(financeAccounts)..where((t) => t.id.equals(id)))
          .write(const FinanceAccountsCompanion(activa: Value(true)));

  Future<int> countTransactionsForAccount(String accountId) async {
    final rows = await (select(financeTransactions)
          ..where((t) =>
              t.accountId.equals(accountId) | t.transferToAccountId.equals(accountId)))
        .get();
    return rows.length;
  }

  Future<void> deleteFinanceAccountSafely(String id) async {
    final count = await countTransactionsForAccount(id);
    if (count > 0) throw AccountHasTransactionsException(count);
    await deleteFinanceAccount(id);
  }

  /// Borrado físico definitivo: elimina las transacciones donde esta cuenta
  /// es el origen y luego la cuenta. Las transacciones donde esta cuenta
  /// era el destino de una transferencia (transferToAccountId) quedan con
  /// ese campo en null por el FK onDelete: setNull — se conservan como
  /// ingreso/gasto normal del otro lado, pero pierden la referencia de
  /// destino. Solo se invoca tras confirmación explícita del usuario.
  Future<void> deleteFinanceAccountAndHistory(String id) => transaction(() async {
        await (delete(financeTransactions)..where((t) => t.accountId.equals(id))).go();
        await deleteFinanceAccount(id);
      });
```

Añadir la query de transferencias y la excepción, después de `getFinanceTransactionsByLibro` (línea ~775):

```dart
  /// Igual que [getFinanceTransactionsByLibro] pero incluye también las
  /// transferencias cuyo destino es [libroId] — necesario para que el
  /// registro destino vea el dinero que recibió.
  Future<List<FinanceTransactionRow>> getFinanceTransactionsInvolvingLibro({
    required String libroId,
    String? mes,
    bool ascending = false,
  }) {
    final q = select(financeTransactions)
      ..where((t) =>
          t.accountId.equals(libroId) | t.transferToAccountId.equals(libroId));
    if (mes != null) q.where((t) => t.fecha.like('$mes%'));
    q.orderBy([(t) => ascending
        ? OrderingTerm.asc(t.fecha)
        : OrderingTerm.desc(t.fecha)]);
    return q.get();
  }
```

Y, junto a `QuotaHasActivePurchasesException` (línea ~22), añadir:

```dart
class AccountHasTransactionsException implements Exception {
  final int count;
  const AccountHasTransactionsException(this.count);
  @override
  String toString() =>
      'AccountHasTransactionsException: $count transacción(es) asociada(s)';
}
```

- [ ] **Step 4: Run tests para confirmar que pasan**

Run: `flutter test test/db/finance_ledger_db_test.dart`
Expected: PASS, los 7 tests.

- [ ] **Step 5: Verificar que nada más en el proyecto rompe por el nuevo default de `getFinanceAccounts`**

Run: `grep -rn "getFinanceAccounts(" lib/`
Expected: todas las llamadas existentes van sin argumentos (compatibles con el default `incluirArchivadas: false`) o se actualizan en Task 6 para pasar `incluirArchivadas: true` donde corresponda (pantalla de archivados).

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/database.dart test/db/finance_ledger_db_test.dart
git commit -m "feat(finanzas): query de transferencias bidireccional y ciclo de vida de registros (archivar/reactivar/eliminar seguro)"
```

---

### Task 4: Provider centralizado de saldo — reemplazar los 4 cálculos duplicados

**Files:**
- Modify: `lib/providers/finance_provider.dart`
- Modify: `lib/screens/finanzas/finanzas_cuentas_screen.dart`
- Modify: `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart`
- Modify: `lib/screens/finanzas/finanzas_estadisticas_screen.dart`
- Test: `test/providers/finance_account_balance_provider_test.dart` (nuevo)

**Interfaces:**
- Consumes: `signedEffectForLibro`, `calcularSaldo`, `calcularIngresosGastos`, `totalReservado`, `calcularDisponibleEstimado` (Task 2); `getFinanceTransactionsInvolvingLibro`, `getFinanceReservations` (Task 1 y 3).
- Produces: `financeAccountBalanceProvider` — `FutureProvider.family<FinanceAccountBalance, String>`, con:

```dart
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
```

- [ ] **Step 1: Escribir el test que falla**

Crear `test/providers/finance_account_balance_provider_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';

void main() {
  test('financeAccountBalanceProvider combina saldo, ingresos/gastos y reservas', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: 'A', nombre: 'A', tipo: 'efectivo', icono: 'wallet', color: '#000',
      saldoInicial: const Value(100),
    ));
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't1', accountId: 'A', categoryId: 'ingresos', tipo: 'ingreso',
      monto: 200, fecha: '2026-10-01',
    ));
    await db.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: 'r1', accountId: 'A', nombre: 'Vacaciones', monto: 50, creadaEn: '2026-10-01',
    ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final balance = await container.read(financeAccountBalanceProvider('A').future);

    expect(balance.saldo, 300);
    expect(balance.ingresos, 200);
    expect(balance.gastos, 0);
    expect(balance.reservado, 50);
    expect(balance.disponibleEstimado, 250);
    expect(balance.reservasExcedenSaldo, false);

    await db.close();
  });
}
```

Confirmar primero cómo se llama `databaseProvider` y si acepta `overrideWithValue` (revisar `lib/providers/database_provider.dart`); si es un `Provider<AppDatabase>` normal, el override de arriba funciona tal cual.

- [ ] **Step 2: Run test para confirmar que falla**

Run: `flutter test test/providers/finance_account_balance_provider_test.dart`
Expected: FAIL — `financeAccountBalanceProvider` no existe.

- [ ] **Step 3: Implementar el provider**

En `lib/providers/finance_provider.dart`, añadir los imports de `finance_ledger.dart` y, después de `financeAccountSummaryProvider` (línea ~67-80), añadir:

```dart
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
```

No borrar `financeAccountSummaryProvider` todavía: márcalo con un comentario `// @Deprecated` apuntando al nuevo provider; se retira en el Step 5 de esta Task una vez confirmado que ningún screen lo usa.

- [ ] **Step 4: Run test para confirmar que pasa**

Run: `flutter test test/providers/finance_account_balance_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Migrar las 3 pantallas a consumir el provider nuevo**

En `finanzas_cuentas_screen.dart` (línea ~725-739): reemplazar el uso de `financeAccountSummaryProvider(libro.id)` por `financeAccountBalanceProvider(libro.id)`; el balance ya no se calcula como `libro.saldoInicial + s.ingresos - s.gastos`, se usa directamente `balance.saldo`. Los textos de ingresos/gastos usan `balance.ingresos`/`balance.gastos`.

En `finanzas_libro_transacciones_screen.dart` (línea ~118-126): el método `_totales(txs)` deja de calcular `balance` a mano; en su lugar, el widget que lo consume pasa a leer `ref.watch(financeAccountBalanceProvider(_libroActual.id))` para el balance/ingresos/gastos del resumen superior, y `_totales` se reduce a devolver solo lo necesario para el filtro por periodo visible en pantalla si ese filtro no coincide con "todo el histórico" (la Task no cambia el comportamiento de filtrado por periodo — solo el balance global de cabecera pasa a usar la fuente centralizada; si el resumen mostraba ingresos/gastos del periodo filtrado, mantenlo así usando `calcularIngresosGastos` directamente sobre los `txs` ya filtrados por periodo que la pantalla ya tiene, importando esa función de `finance_ledger.dart` en vez de reimplementar el `fold`).

En `finanzas_estadisticas_screen.dart`: el método `_totales` (línea ~146) y `_LibroBalanceCard` (línea ~781) reemplazan sus loops manuales por `calcularIngresosGastos` (para ingresos/gastos del periodo) y `financeAccountBalanceProvider`/`calcularSaldo` (para el balance mostrado en la tarjeta), según corresponda a si la pantalla ya tiene los `txs` en memoria (usa las funciones puras de `finance_ledger.dart` directamente, sin esperar otra llamada a la DB) o necesita el saldo "oficial" (usa el provider).

- [ ] **Step 6: Verificación manual de no-regresión**

Run: `dart analyze lib/screens/finanzas/ lib/providers/finance_provider.dart`
Expected: 0 errores nuevos (los warnings/infos preexistentes documentados en sesiones anteriores pueden seguir apareciendo, pero ninguno nuevo en estos archivos).

- [ ] **Step 7: Run suite completa**

Run: `flutter test`
Expected: todos los tests pasan, incluidos los 258 preexistentes más los nuevos de esta fase.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/finance_provider.dart lib/screens/finanzas/finanzas_cuentas_screen.dart lib/screens/finanzas/finanzas_libro_transacciones_screen.dart lib/screens/finanzas/finanzas_estadisticas_screen.dart test/providers/finance_account_balance_provider_test.dart
git commit -m "refactor(finanzas): centraliza cálculo de saldo/ingresos/gastos en financeAccountBalanceProvider"
```

---

### Task 5: Validación de transferencias nuevas en el formulario

**Files:**
- Modify: `lib/screens/finanzas/nueva_transaccion_sheet.dart`
- Test: `test/widgets/` — no se añade widget test nuevo (el formulario es un `ConsumerStatefulWidget` grande sin arnés de testing previo); en su lugar se valida la regla con un test de dominio puro.
- Test: `test/domain/finance_ledger_test.dart` (ampliar)

**Interfaces:**
- Consumes: ninguna nueva.
- Produces: `bool esTransferenciaValida({required String? origenId, required String? destinoId})` en `finance_ledger.dart`.

- [ ] **Step 1: Escribir el test que falla**

Añadir a `test/domain/finance_ledger_test.dart`:

```dart
  group('esTransferenciaValida', () {
    test('origen y destino distintos y presentes: válida', () {
      expect(esTransferenciaValida(origenId: 'A', destinoId: 'B'), true);
    });
    test('origen igual a destino: inválida', () {
      expect(esTransferenciaValida(origenId: 'A', destinoId: 'A'), false);
    });
    test('destino nulo: inválida', () {
      expect(esTransferenciaValida(origenId: 'A', destinoId: null), false);
    });
    test('origen nulo: inválida', () {
      expect(esTransferenciaValida(origenId: null, destinoId: 'B'), false);
    });
  });
```

- [ ] **Step 2: Run test para confirmar que falla**

Run: `flutter test test/domain/finance_ledger_test.dart`
Expected: FAIL — función no existe.

- [ ] **Step 3: Implementar la función**

En `lib/domain/finance_ledger.dart`:

```dart
/// Una transferencia es válida solo si tiene origen y destino distintos y
/// ambos definidos. No valida existencia en DB — eso lo hace quien la llama
/// con los libros ya cargados en memoria (ver nueva_transaccion_sheet).
bool esTransferenciaValida({required String? origenId, required String? destinoId}) {
  if (origenId == null || destinoId == null) return false;
  return origenId != destinoId;
}
```

- [ ] **Step 4: Run test para confirmar que pasa**

Run: `flutter test test/domain/finance_ledger_test.dart`
Expected: PASS.

- [ ] **Step 5: Usar la validación en `_guardar`**

En `lib/screens/finanzas/nueva_transaccion_sheet.dart`, en `_guardar` (línea 183), después del guard `if (_libroId == null) return;` (línea 187), añadir:

```dart
    if (_tipo == 'transferencia' &&
        !esTransferenciaValida(origenId: _libroId, destinoId: _libroDestinoId)) {
      return;
    }
```

Importar `package:krezium/domain/finance_ledger.dart`. Verificar en el build (sección del selector de libro destino, línea ~462) que el picker ya excluye al propio `_libroId` de las opciones de destino — si no lo hace, añadir ese filtro al listado de libros ofrecidos como destino (cambio imprescindible para que la regla sea también usable desde la UI, no solo bloqueada al guardar).

- [ ] **Step 6: Run suite completa**

Run: `flutter test`
Expected: todos pasan.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/finance_ledger.dart lib/screens/finanzas/nueva_transaccion_sheet.dart test/domain/finance_ledger_test.dart
git commit -m "fix(finanzas): rechaza transferencias a sí mismo o sin destino antes de guardar"
```

---

### Task 6: UI de archivar / reactivar / eliminar con advertencia en el lobby

**Files:**
- Modify: `lib/screens/finanzas/finanzas_cuentas_screen.dart`

**Interfaces:**
- Consumes: `archiveFinanceAccount`, `reactivateFinanceAccount`, `deleteFinanceAccountSafely`, `deleteFinanceAccountAndHistory`, `AccountHasTransactionsException`, `countTransactionsForAccount` (Task 3); `getFinanceAccounts(incluirArchivadas: true)`.

No se añade test widget (el screen no tiene arnés de testing de widgets previo en el proyecto); la cobertura de esta Task es la de Task 3 (DB) más verificación manual — documentarlo así en el cierre de fase.

- [ ] **Step 1: Añadir el control "Archivar" al menú de cada tarjeta de registro**

En el menú contextual de cada `_LibroCard` (donde hoy están editar/eliminar, cerca de línea ~700-712), añadir una opción "Archivar" que llama `ref.read(databaseProvider).archiveFinanceAccount(libro.id)` seguido de `ref.invalidate(financeAccountsProvider)`.

- [ ] **Step 2: Añadir acceso a "Registros archivados"**

Añadir un botón/chip discreto en la cabecera del lobby (no una pantalla nueva, no cambio de navegación) que, al tocarse, abre un `showModalBottomSheet` simple listando las cuentas con `getFinanceAccounts(incluirArchivadas: true)` filtradas a `activa == false`, cada una con un botón "Reactivar" que llama `reactivateFinanceAccount` + invalida `financeAccountsProvider`.

- [ ] **Step 3: Reescribir el flujo de eliminar**

Donde hoy existe el botón "Eliminar" de un registro, cambiar su handler para:

```dart
Future<void> _eliminarLibro(BuildContext context, WidgetRef ref, FinanceAccount libro) async {
  final db = ref.read(databaseProvider);
  final count = await db.countTransactionsForAccount(libro.id);
  if (count == 0) {
    await db.deleteFinanceAccountSafely(libro.id);
    ref.invalidate(financeAccountsProvider);
    return;
  }
  if (!context.mounted) return;
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar definitivamente'),
      content: Text(
        'Este registro tiene $count movimiento(s). Eliminarlo borrará también '
        'todo su historial de forma irreversible. Si solo quieres dejar de '
        'verlo pero conservar los datos, usa "Archivar" en su lugar.\n\n'
        '¿Seguro que quieres eliminarlo y perder su historial para siempre?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar y perder historial')),
      ],
    ),
  );
  if (confirmado == true) {
    await db.deleteFinanceAccountAndHistory(libro.id);
    if (context.mounted) ref.invalidate(financeAccountsProvider);
  }
}
```

- [ ] **Step 4: `dart analyze`**

Run: `dart analyze lib/screens/finanzas/finanzas_cuentas_screen.dart`
Expected: 0 errores nuevos.

- [ ] **Step 5: Run suite completa**

Run: `flutter test`
Expected: todos pasan (esta Task no añade tests nuevos, no debe romper los existentes).

- [ ] **Step 6: Commit**

```bash
git add lib/screens/finanzas/finanzas_cuentas_screen.dart
git commit -m "feat(finanzas): archivar/reactivar registros y eliminación definitiva con advertencia explícita"
```

---

### Task 7: Reparación histórica de transferencias (clasificar y señalar, no inventar)

**Files:**
- Modify: `lib/data/db/database.dart`
- Modify: `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart` (badge visual mínimo)
- Test: `test/db/finance_historical_repair_test.dart` (nuevo)

**Interfaces:**
- Produces: `Future<FinanceHistoricalAudit> auditarTransferenciasHistoricas(AppDatabase db)` y `Future<void> aplicarSenalamientoTransferenciasDudosas(AppDatabase db)`, con:

```dart
class FinanceHistoricalAudit {
  final int reconstruibles;
  final int dudosas;
  final int noReconstruibles;
  final List<String> idsDudosos;
  const FinanceHistoricalAudit({
    required this.reconstruibles, required this.dudosas,
    required this.noReconstruibles, required this.idsDudosos,
  });
}
```

- [ ] **Step 1: Escribir el test que falla**

Crear `test/db/finance_historical_repair_test.dart`:

```dart
import 'package:drift/drift.dart';
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
    // Dudosa: destino apunta a una cuenta que ya no existe.
    await db.upsertFinanceTransaction(FinanceTransactionsCompanion.insert(
      id: 't3', accountId: 'A', categoryId: 'transferencia', tipo: 'transferencia',
      monto: 15, fecha: '2026-01-03', transferToAccountId: const Value('inexistente'),
    ));

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
```

- [ ] **Step 2: Run test para confirmar que falla**

Run: `flutter test test/db/finance_historical_repair_test.dart`
Expected: FAIL — funciones no existen.

- [ ] **Step 3: Implementar en `lib/data/db/database.dart`**

Añadir al final del archivo (o junto a los métodos de Finance Transactions):

```dart
class FinanceHistoricalAudit {
  final int reconstruibles;
  final int dudosas;
  final int noReconstruibles;
  final List<String> idsDudosos;
  const FinanceHistoricalAudit({
    required this.reconstruibles, required this.dudosas,
    required this.noReconstruibles, required this.idsDudosos,
  });
}

/// Clasifica las transacciones tipo 'transferencia' existentes:
/// - reconstruible: tiene transferToAccountId no nulo y ese registro existe
///   y es distinto del origen — el fix de cálculo (Tasks 2-4) ya la hace
///   funcionar correctamente sin modificar datos.
/// - dudosa: transferToAccountId nulo, o apunta a un registro que ya no
///   existe, o es igual al origen (dato corrupto de antes de esta fase).
/// No modifica nada — solo cuenta y lista.
Future<FinanceHistoricalAudit> auditarTransferenciasHistoricas(AppDatabase db) async {
  final todas = await (db.select(db.financeTransactions)
        ..where((t) => t.tipo.equals('transferencia')))
      .get();
  final cuentas = (await db.getFinanceAccounts(incluirArchivadas: true))
      .map((c) => c.id)
      .toSet();

  var reconstruibles = 0;
  final dudosas = <String>[];
  for (final t in todas) {
    final destino = t.transferToAccountId;
    final esValida = destino != null && destino != t.accountId && cuentas.contains(destino);
    if (esValida) {
      reconstruibles++;
    } else {
      dudosas.add(t.id);
    }
  }
  return FinanceHistoricalAudit(
    reconstruibles: reconstruibles,
    dudosas: dudosas.length,
    noReconstruibles: 0,
    idsDudosos: dudosas,
  );
}

/// Marca con revisionNota (sin tocar monto/fecha/cuentas) las transferencias
/// dudosas detectadas por [auditarTransferenciasHistoricas]. Idempotente:
/// si ya tienen la nota, no se vuelve a escribir.
Future<void> aplicarSenalamientoTransferenciasDudosas(AppDatabase db) async {
  final audit = await auditarTransferenciasHistoricas(db);
  for (final id in audit.idsDudosos) {
    final fila = await (db.select(db.financeTransactions)..where((t) => t.id.equals(id)))
        .getSingle();
    if (fila.revisionNota != null) continue;
    await (db.update(db.financeTransactions)..where((t) => t.id.equals(id))).write(
      const FinanceTransactionsCompanion(
        revisionNota: Value(
          'Transferencia histórica sin destino verificable — revisar manualmente.',
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test para confirmar que pasa**

Run: `flutter test test/db/finance_historical_repair_test.dart`
Expected: PASS.

- [ ] **Step 5: Badge visual mínimo en el historial**

En `finanzas_libro_transacciones_screen.dart`, en el widget de fila de transacción (`_TxRow`), si `tx.revisionNota != null`, añadir un ícono pequeño de advertencia (`Icons.warning_amber_rounded`, tamaño `AppIconSize.small`, color `colors.textTertiary`) junto al monto, sin tooltip complejo — con un `onTap` opcional que muestre un `SnackBar` con el contenido de `revisionNota`. Cambio mínimo, no redise��a la fila.

- [ ] **Step 6: Invocar el señalamiento una vez al abrir Finanzas**

Decidir el punto de enganche mínimo: en el `initState` de `FinanzasCuentasScreen` (pantalla de entrada del módulo), llamar `unawaited(aplicarSenalamientoTransferenciasDudosas(ref.read(databaseProvider)))` — es idempotente y barato (recorre solo filas `tipo=='transferencia'`), seguro de correr en cada apertura del módulo sin necesidad de una migración de datos en el `onUpgrade` de Drift (evita acoplar lógica de negocio a la migración de schema, que debe quedarse puramente estructural).

- [ ] **Step 7: Run suite completa**

Run: `flutter test`
Expected: todos pasan.

- [ ] **Step 8: Commit**

```bash
git add lib/data/db/database.dart lib/screens/finanzas/finanzas_libro_transacciones_screen.dart lib/screens/finanzas/finanzas_cuentas_screen.dart test/db/finance_historical_repair_test.dart
git commit -m "feat(finanzas): clasifica y señala transferencias históricas ambiguas sin inventar datos"
```

---

### Task 8: Regresión completa, documentación y cierre de Fase 01

**Files:**
- Modify: `docs/finanzas-roadmap.md`
- Create: `docs/finanzas-fase01-cierre.md`

- [ ] **Step 1: Suite completa + análisis estático**

Run: `flutter test`
Expected: 100% verde, incluidos los ~258 tests preexistentes más los nuevos de Tasks 1-7.

Run: `dart analyze`
Expected: ningún error nuevo; los warnings/infos preexistentes documentados en sesiones anteriores (unused variable en `debt_history_provider.dart`, etc.) pueden seguir apareciendo pero ninguno nuevo relacionado con Finanzas.

- [ ] **Step 2: Revisar el diff completo de la fase contra el alcance autorizado**

Run: `git log --oneline <commit-inicial-de-la-fase>..HEAD`
Run: `git diff <commit-inicial-de-la-fase>..HEAD --stat`
Expected: todos los archivos tocados están dentro de lo descrito en las Tasks 1-7; ningún archivo de navegación, Plantillas, Presupuestos (UI) o Estadísticas más allá del cálculo de saldo.

- [ ] **Step 3: Escribir `docs/finanzas-fase01-cierre.md`**

Informe de cierre siguiendo el formato de la sección 8 de la spec: archivos modificados y motivo, cambios de esquema (v18→v19: tabla `FinanceReservations`, columna `revisionNota`), reglas contables implementadas (enlazar `docs/finanzas-reglas-contables.md`), pruebas ejecutadas y resultado, conteo real de transferencias históricas reconstruibles/dudosas/no-reconstruibles obtenido al correr `auditarTransferenciasHistoricas` contra una base de datos real de desarrollo si está disponible (si no hay acceso a datos reales de producción del usuario, decirlo explícitamente), incidencias para revisión manual, limitaciones pendientes (ej. Presupuestos sigue sin ruta de navegación — eso es Fase 02/04, no se toca aquí), confirmación explícita de que Fase 02 no inició.

- [ ] **Step 4: Actualizar `docs/finanzas-roadmap.md`**

Marcar Fase 01 como cerrada (checkbox), añadir fecha de cierre y enlazar `docs/finanzas-fase01-cierre.md`.

- [ ] **Step 5: Commit**

```bash
git add docs/finanzas-roadmap.md docs/finanzas-fase01-cierre.md
git commit -m "docs(finanzas): cierre de Fase 01 — integridad financiera y cálculos"
```

- [ ] **Step 6: Detenerse**

No iniciar Fase 02. Reportar al usuario el cierre y esperar autorización explícita antes de continuar, tal como exige la spec.
