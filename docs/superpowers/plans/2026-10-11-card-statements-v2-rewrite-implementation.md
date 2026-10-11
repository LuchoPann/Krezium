# Extractos de tarjeta v2 — Reescritura — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El extracto (abierto o cerrado) es la única fuente de verdad para
la deuda de una tarjeta de crédito; las compras a plazos son una entidad
propia que factura su siguiente cuota automáticamente cuando el ciclo
correspondiente abre, no de golpe por adelantado.

**Architecture:** Nuevo archivo `lib/domain/card_statement_engine.dart`
reemplaza las funciones mutadoras de `card_calculator.dart`
(`accrueCardCredit`, `registerCardMovement`, `registerCardCharge`,
`buildInstallmentMovements`, `_applyPaymentToLatestStatement`,
`deleteCardMovement`, `getPayableSummary`) con una versión donde
`CardMovement` se liga a un `CardStatement` real por `statementId` (no por
fecha calculada), y `currentBalance` se recalcula siempre desde los
extractos en vez de mutarse a mano. Las funciones de fecha puras
(`cutoffDateForMonth`, `getCardCycleDates`, `cycleKeyFor`,
`frenchMonthlyPayment`) se quedan donde están — siguen siendo correctas y
las usa la migración de datos legados.

**Tech Stack:** Flutter, Drift (SQLite), Riverpod, `package:flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-11-card-statements-v2-rewrite-design.md`

## Global Constraints

- `schemaVersion` de Drift sube de 15 a 16 (`lib/data/db/database.dart`).
- `kBackupFormatVersion` de `lib/domain/export_import.dart` sube de 4 a 5.
- `CardCredit.closedStatements` se renombra a `CardCredit.statements` —
  ahora contiene TODOS los extractos (abierto, cerrado, pagado), no solo
  los cerrados.
- `CardStatement.closingBalance` se conserva como columna/campo pero pasa
  a ser una **caché de solo-escritura** (se recalcula y sobreescribe cada
  vez que algo cambia; ningún código de negocio nuevo la lee para decidir
  nada — siempre llaman a `computeStatementTotal`). Esto evita una
  migración SQL destructiva de la columna.
- Nombre del paquete del proyecto: `krezium`.
- `CardMovement.statementCutoff` (de la iteración anterior) se conserva
  solo para que la migración legada pueda leerlo — el código nuevo no lo
  escribe nunca más; usa `statementId`.

## Review Focus

- Tarjeta recién creada (`addCredit`): debe tener su extracto abierto
  creado en el momento, no esperar al primer `closeCurrentCycleIfDue` del
  próximo arranque — de lo contrario, registrar un cargo antes de que
  exista el extracto abierto no tiene dónde engancharse.
- Un pago que cierra todos los extractos sin pagar y deja sobrante: el
  sobrante se aplica al extracto abierto como pago anticipado, no se
  pierde.
- Compra a plazos registrada el mismo día del corte: la cuota 1 debe
  facturarse en el extracto que cierra ESE día (mismo criterio que un
  cargo normal de 1 sola cuota el mismo día, vía `cycleKeyFor` reutilizado
  solo para decidir esto, no para el modelo de datos en vivo).
- Migración de una tarjeta con movimientos legados de compras a plazos
  ambiguas (dos compras distintas con mismo `chargeInstallments` y fecha):
  no debe fusionarlas en una `InstallmentPurchase` incorrecta — mejor
  dejarlas como cargos sueltos que reconstruir mal.
- Borrar la cuota más reciente ya facturada de una `InstallmentPurchase`:
  debe decrementar `installmentsBilled` para que se vuelva a facturar
  correctamente en el próximo cierre de ciclo, en vez de perderse para
  siempre.

---

### Task 1: Modelo `InstallmentPurchase`

**Files:**
- Create: `lib/data/models/installment_purchase.dart`
- Test: `test/data/models/installment_purchase_test.dart`

**Interfaces:**
- Produces: `class InstallmentPurchase` con `id, creditId, purchaseDate,
  totalAmount, installments, perInstallmentAmount, lastInstallmentAmount,
  note, categoria, installmentsBilled (mutable int), createdAt`, getters
  `bool get isFullyBilled`, `double get remainingAmount`, `toJson()`,
  `factory InstallmentPurchase.fromJson(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/installment_purchase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/installment_purchase.dart';

void main() {
  InstallmentPurchase build({int billed = 1}) => InstallmentPurchase(
        id: 'ip1',
        creditId: 'c1',
        purchaseDate: '2026-01-10',
        totalAmount: 100000,
        installments: 3,
        perInstallmentAmount: 33333,
        lastInstallmentAmount: 33334,
        note: 'TV',
        categoria: 'otro',
        installmentsBilled: billed,
        createdAt: '2026-01-10',
      );

  test('toJson/fromJson round-trip preserves all fields', () {
    final p = build();
    final decoded = InstallmentPurchase.fromJson(p.toJson());
    expect(decoded.id, 'ip1');
    expect(decoded.totalAmount, 100000);
    expect(decoded.installments, 3);
    expect(decoded.perInstallmentAmount, 33333);
    expect(decoded.lastInstallmentAmount, 33334);
    expect(decoded.installmentsBilled, 1);
  });

  test('isFullyBilled is true once installmentsBilled reaches installments', () {
    expect(build(billed: 2).isFullyBilled, isFalse);
    expect(build(billed: 3).isFullyBilled, isTrue);
  });

  test('remainingAmount sums the still-unbilled cuotas, using '
      'lastInstallmentAmount for the final one', () {
    // 3 cuotas, ya facturada 1 → quedan cuota 2 (33333) y cuota 3 (33334)
    expect(build(billed: 1).remainingAmount, 33333 + 33334);
    // ya facturadas las 3 → nada pendiente
    expect(build(billed: 3).remainingAmount, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/installment_purchase_test.dart`
Expected: FAIL — `lib/data/models/installment_purchase.dart` no existe.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/data/models/installment_purchase.dart

/// Una compra registrada a N cuotas. La cuota 1 se factura de inmediato
/// (al momento de la compra); cada cuota siguiente se factura sola,
/// automáticamente, cuando el extracto correspondiente abre — ver
/// `closeCurrentCycleIfDue` en lib/domain/card_statement_engine.dart.
class InstallmentPurchase {
  final String id;
  final String creditId;

  /// "YYYY-MM-DD"
  final String purchaseDate;

  final double totalAmount;
  final int installments;

  /// Monto redondeado a 2 decimales de cada cuota, excepto la última.
  final double perInstallmentAmount;

  /// Monto de la última cuota — absorbe el remanente de redondeo para que
  /// la suma de todas las cuotas sea exactamente [totalAmount].
  final double lastInstallmentAmount;

  final String note;
  final String? categoria;

  /// Cuántas cuotas ya se facturaron como CardMovement (empieza en 1: la
  /// cuota 1 se factura al momento de la compra).
  int installmentsBilled;

  /// "YYYY-MM-DD"
  final String createdAt;

  InstallmentPurchase({
    required this.id,
    required this.creditId,
    required this.purchaseDate,
    required this.totalAmount,
    required this.installments,
    required this.perInstallmentAmount,
    required this.lastInstallmentAmount,
    this.note = '',
    this.categoria,
    this.installmentsBilled = 1,
    required this.createdAt,
  });

  bool get isFullyBilled => installmentsBilled >= installments;

  double get remainingAmount {
    final remainingCount = installments - installmentsBilled;
    if (remainingCount <= 0) return 0;
    // (remainingCount - 1) cuotas normales + la última (que puede diferir
    // por redondeo) — si solo queda la última, remainingCount == 1 y el
    // primer término da 0.
    return perInstallmentAmount * (remainingCount - 1) + lastInstallmentAmount;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'creditId': creditId,
        'purchaseDate': purchaseDate,
        'totalAmount': totalAmount,
        'installments': installments,
        'perInstallmentAmount': perInstallmentAmount,
        'lastInstallmentAmount': lastInstallmentAmount,
        'note': note,
        'categoria': categoria,
        'installmentsBilled': installmentsBilled,
        'createdAt': createdAt,
      };

  factory InstallmentPurchase.fromJson(Map<String, dynamic> json) =>
      InstallmentPurchase(
        id: json['id'] as String,
        creditId: json['creditId'] as String,
        purchaseDate: json['purchaseDate'] as String,
        totalAmount: (json['totalAmount'] as num).toDouble(),
        installments: (json['installments'] as num).toInt(),
        perInstallmentAmount: (json['perInstallmentAmount'] as num).toDouble(),
        lastInstallmentAmount:
            (json['lastInstallmentAmount'] as num).toDouble(),
        note: json['note'] as String? ?? '',
        categoria: json['categoria'] as String?,
        installmentsBilled: (json['installmentsBilled'] as num?)?.toInt() ?? 1,
        createdAt: json['createdAt'] as String,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/installment_purchase_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/installment_purchase.dart test/data/models/installment_purchase_test.dart
git commit -m "feat: agrega modelo InstallmentPurchase (compra a plazos)"
```

---

### Task 2: `CardMovement.statementId`/`installmentPurchaseId`, `CardStatementStatus.open`

**Files:**
- Modify: `lib/data/models/card_movement.dart`
- Modify: `lib/data/models/card_statement.dart`
- Test: `test/data/models/card_movement_test.dart` (añadir)

**Interfaces:**
- Produces: `CardMovement.statementId` (`String?`),
  `CardMovement.installmentPurchaseId` (`String?`),
  `CardStatementStatus.open == 'open'`.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir a test/data/models/card_movement_test.dart
test('toJson/fromJson round-trips statementId and installmentPurchaseId', () {
  final mv = CardMovement(
    date: '2026-01-10',
    type: CardMovementType.charge,
    amount: 50000,
    statementId: 's1',
    installmentPurchaseId: 'ip1',
  );
  final decoded = CardMovement.fromJson(mv.toJson());
  expect(decoded.statementId, 's1');
  expect(decoded.installmentPurchaseId, 'ip1');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/card_movement_test.dart`
Expected: FAIL — `The named parameter 'statementId' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

En `lib/data/models/card_movement.dart`, agregar campos (tras
`statementCutoff`):

```dart
  /// FK al CardStatement (abierto o cerrado) al que este movimiento está
  /// ligado. NOT NULL para todo movimiento creado desde la v2 del motor de
  /// extractos en adelante — null solo en filas legadas no migradas aún
  /// (ver migrateLegacyCardData en card_statement_engine.dart).
  final String? statementId;

  /// FK a InstallmentPurchase cuando este movimiento es una cuota de una
  /// compra a plazos. Null para cargos de 1 sola exhibición, pagos,
  /// intereses, cuotas de manejo y avances.
  final String? installmentPurchaseId;
```

Constructor, `toJson`, `fromJson`: agregar los 2 parámetros/campos igual
que los demás opcionales (mismo patrón que `installmentIndex`/
`statementCutoff` ya existentes).

En `lib/data/models/card_statement.dart`, agregar a `CardStatementStatus`:

```dart
class CardStatementStatus {
  static const open = 'open';
  static const closed = 'closed';
  static const paid = 'paid';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/card_movement_test.dart`
Expected: PASS (todos, incluidos los preexistentes)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/card_movement.dart lib/data/models/card_statement.dart test/data/models/card_movement_test.dart
git commit -m "feat: CardMovement se liga a un CardStatement real (statementId)"
```

---

### Task 3: Persistencia — tabla `InstallmentPurchases`, columnas nuevas, schema v16

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`
- Test: `test/data/installment_purchases_db_test.dart`

**Interfaces:**
- Consumes: `InstallmentPurchase` (Task 1), `CardMovement.statementId`/
  `installmentPurchaseId` (Task 2).
- Produces: `AppDatabase` persiste/carga `installmentPurchases` por tarjeta
  igual patrón que `cardMovements`/`cardStatements`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/installment_purchases_db_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/data/models/installment_purchase.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('round-trips a card with an InstallmentPurchase and a movement '
      'linked to it via statementId/installmentPurchaseId', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bank',
      installmentPurchases: [
        InstallmentPurchase(
          id: 'ip1',
          creditId: 'card1',
          purchaseDate: '2026-01-10',
          totalAmount: 100000,
          installments: 3,
          perInstallmentAmount: 33333,
          lastInstallmentAmount: 33334,
          createdAt: '2026-01-10',
        ),
      ],
      movements: [
        CardMovement(
          date: '2026-01-10',
          type: CardMovementType.charge,
          amount: 33333,
          statementId: 's1',
          installmentPurchaseId: 'ip1',
          chargeInstallments: 3,
          installmentIndex: 1,
        ),
      ],
    );

    await db.upsertCredit(card);
    final all = await db.loadAllCredits();

    expect(all, hasLength(1));
    final loaded = all.first as CardCredit;
    expect(loaded.installmentPurchases, hasLength(1));
    expect(loaded.installmentPurchases.first.totalAmount, 100000);
    expect(loaded.movements.first.statementId, 's1');
    expect(loaded.movements.first.installmentPurchaseId, 'ip1');
  });

  test('clearAllData removes installmentPurchases', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bank',
      installmentPurchases: [
        InstallmentPurchase(
          id: 'ip1',
          creditId: 'card1',
          purchaseDate: '2026-01-10',
          totalAmount: 100000,
          installments: 2,
          perInstallmentAmount: 50000,
          lastInstallmentAmount: 50000,
          createdAt: '2026-01-10',
        ),
      ],
    );
    await db.upsertCredit(card);
    await db.clearAllData();
    expect(await db.loadAllCredits(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/installment_purchases_db_test.dart`
Expected: FAIL — `The named parameter 'installmentPurchases' isn't
defined` (CardCredit no tiene el campo aún — lo agrega Task 4 — y
`statementId`/`installmentPurchaseId` no están en `CardMovementsCompanion`).

Nota de orden: este test fallará por `installmentPurchases` hasta
completar también Task 4. Es intencional — correrlo aquí confirma que la
capa de DB está lista para cuando el modelo lo esté; el PASS real llega al
cerrar Task 4. Sigue con Step 3 de todas formas.

- [ ] **Step 3: Write minimal implementation**

**3a. `lib/data/db/tables.dart`** — agregar columnas a `CardMovements`
(tras `statementCutoff`):

```dart
  /// FK al CardStatement (abierto o cerrado) al que este movimiento está
  /// ligado. Null solo en filas legadas de antes de esta versión.
  TextColumn get statementId => text().nullable()();

  /// FK a InstallmentPurchases cuando este movimiento es una cuota de una
  /// compra a plazos.
  TextColumn get installmentPurchaseId => text().nullable()();
}
```

Agregar tabla nueva al final del archivo:

```dart
/// Una compra a plazos. Ver lib/data/models/installment_purchase.dart.
@DataClassName('InstallmentPurchaseRow')
class InstallmentPurchases extends Table {
  TextColumn get id => text()();
  TextColumn get creditId =>
      text().references(Credits, #id, onDelete: KeyAction.cascade)();
  TextColumn get purchaseDate => text()(); // YYYY-MM-DD
  RealColumn get totalAmount => real()();
  IntColumn get installments => integer()();
  RealColumn get perInstallmentAmount => real()();
  RealColumn get lastInstallmentAmount => real()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get categoria => text().nullable()();
  IntColumn get installmentsBilled =>
      integer().withDefault(const Constant(1))();
  TextColumn get createdAt => text()(); // YYYY-MM-DD

  @override
  Set<Column> get primaryKey => {id};
}
```

**3b. `lib/data/db/database.dart`**:

Import:
```dart
import '../models/installment_purchase.dart';
```

Agregar `InstallmentPurchases` a `@DriftDatabase(tables: [...])` y subir
`schemaVersion`:

```dart
@DriftDatabase(tables: [
  Credits, Installments, CardMovements, CardStatements,
  InstallmentPurchases, LoanAbonos, CommercialQuotas, PagosRealizados,
  FinanceAccounts, FinanceCategories, FinanceTransactions, FinanceBudgets,
  FinancePlaces, FinanceTemplates,
])
```
```dart
  int get schemaVersion => 16;
```

Agregar al final de `onUpgrade` (después del bloque `if (from < 15)`):

```dart
          if (from < 16) {
            await m.createTable(installmentPurchases);
            await m.addColumn(cardMovements, cardMovements.statementId);
            await m.addColumn(
                cardMovements, cardMovements.installmentPurchaseId);
          }
```

En `loadAllCredits`, dentro de la rama `card`, cargar las compras a plazos
y pasarlas a `_cardFromRow` (que Task 4 extenderá para aceptarlas):

```dart
        final installmentPurchaseRows = await (select(installmentPurchases)
              ..where((p) => p.creditId.equals(row.id))
              ..orderBy([(p) => OrderingTerm.asc(p.purchaseDate)]))
            .get();
```
y en el mapeo de movimientos, agregar:
```dart
                    statementId: m.statementId,
                    installmentPurchaseId: m.installmentPurchaseId,
```
y pasar
```dart
          installmentPurchaseRows
              .map((p) => InstallmentPurchase(
                    id: p.id,
                    creditId: p.creditId,
                    purchaseDate: p.purchaseDate,
                    totalAmount: p.totalAmount,
                    installments: p.installments,
                    perInstallmentAmount: p.perInstallmentAmount,
                    lastInstallmentAmount: p.lastInstallmentAmount,
                    note: p.note,
                    categoria: p.categoria,
                    installmentsBilled: p.installmentsBilled,
                    createdAt: p.createdAt,
                  ))
              .toList(),
```
como nuevo argumento final a `_cardFromRow(row, movements, statements,
installmentPurchases)`.

En `upsertCredit`, rama `CardCredit`: agregar en el insert de
`CardMovementsCompanion`:
```dart
            statementId: Value(mv.statementId),
            installmentPurchaseId: Value(mv.installmentPurchaseId),
```
y después del bloque de `cardStatements`, agregar replace-all de
`installmentPurchases`:
```dart
        await (delete(installmentPurchases)
              ..where((p) => p.creditId.equals(credit.id)))
            .go();
        for (final p in credit.installmentPurchases) {
          await into(installmentPurchases)
              .insert(InstallmentPurchasesCompanion.insert(
            id: p.id,
            creditId: credit.id,
            purchaseDate: p.purchaseDate,
            totalAmount: p.totalAmount,
            installments: p.installments,
            perInstallmentAmount: p.perInstallmentAmount,
            lastInstallmentAmount: p.lastInstallmentAmount,
            note: Value(p.note),
            categoria: Value(p.categoria),
            installmentsBilled: Value(p.installmentsBilled),
            createdAt: p.createdAt,
          ));
        }
```

Agregar `delete(installmentPurchases)` a `clearAllData` y
`replaceAllData`, junto a `delete(cardStatements)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter pub run build_runner build --delete-conflicting-outputs && flutter test test/data/installment_purchases_db_test.dart`
Expected: aún puede fallar por `installmentPurchases` no existir en
`CardCredit` — eso lo resuelve Task 4. Si Task 4 ya se hizo antes de este
paso (ver nota de orden en Step 2), debe dar PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/installment_purchases_db_test.dart
git commit -m "feat: persiste InstallmentPurchases y statementId/installmentPurchaseId (schema v16)"
```

---

### Task 4: `CardCredit` — renombrar `closedStatements`→`statements`, agregar `installmentPurchases`

**Files:**
- Modify: `lib/data/models/credit.dart`
- Modify: `lib/data/db/database.dart` (ajustar `_cardFromRow`/`loadAllCredits` al nuevo nombre)
- Test: `test/data/models/credit_test.dart` (modificar el grupo `CardCredit closedStatements`)

**Interfaces:**
- Consumes: `InstallmentPurchase` (Task 1).
- Produces: `CardCredit.statements` (`List<CardStatement>`, TODOS los
  estados), `CardCredit.installmentPurchases` (`List<InstallmentPurchase>`).

- [ ] **Step 1: Write the failing test**

En `test/data/models/credit_test.dart`, renombrar el grupo existente
`'CardCredit closedStatements'` a `'CardCredit statements'` y su primer
test de `closedStatements` por `statements`, y agregar:

```dart
group('CardCredit statements', () {
  test('defaults to empty list', () {
    final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank');
    expect(card.statements, isEmpty);
    expect(card.installmentPurchases, isEmpty);
  });

  test('toJson/fromJson round-trips statements and installmentPurchases', () {
    final card = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      statements: [
        const CardStatement(
          id: 's1', creditId: 'c1', cutoffDate: '2026-01-15',
          dueDate: '2026-02-05', closingBalance: 0,
          status: CardStatementStatus.open, createdAt: '2026-01-01',
        ),
      ],
      installmentPurchases: [
        InstallmentPurchase(
          id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
          totalAmount: 100000, installments: 3,
          perInstallmentAmount: 33333, lastInstallmentAmount: 33334,
          createdAt: '2026-01-10',
        ),
      ],
    );

    final decoded = CardCredit.fromJson(card.toJson());

    expect(decoded.statements, hasLength(1));
    expect(decoded.statements.first.status, CardStatementStatus.open);
    expect(decoded.installmentPurchases, hasLength(1));
  });

  test('fromJson defaults both to empty when absent (backup v4 compat)', () {
    final decoded = CardCredit.fromJson({'id': 'c1', 'name': 'Test', 'lender': 'Bank'});
    expect(decoded.statements, isEmpty);
    expect(decoded.installmentPurchases, isEmpty);
  });
});
```

Elimina el grupo viejo `'CardCredit closedStatements'` por completo (lo
reemplaza el de arriba).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/credit_test.dart`
Expected: FAIL — `The getter 'statements' isn't defined for the type
'CardCredit'`.

- [ ] **Step 3: Write minimal implementation**

En `lib/data/models/credit.dart`:

```dart
import 'installment_purchase.dart';
```

Reemplazar el campo (antes `closedStatements`):
```dart
  /// Todos los extractos de esta tarjeta — abierto, cerrados y pagados.
  /// Invariante: exactamente uno tiene status == CardStatementStatus.open
  /// en todo momento (ver ensureOpenStatement en card_statement_engine.dart).
  List<CardStatement> statements;

  /// Compras a plazos registradas (N cuotas). Cada cuota se factura sola,
  /// automáticamente, cuando el extracto correspondiente abre.
  List<InstallmentPurchase> installmentPurchases;
```

Constructor:
```dart
    List<CardMovement>? movements,
    List<CardStatement>? statements,
    List<InstallmentPurchase>? installmentPurchases,
  })  : movements = movements ?? [],
        statements = statements ?? [],
        installmentPurchases = installmentPurchases ?? [],
        super(type: CreditType.card);
```

`toJson`:
```dart
        'movements': movements.map((m) => m.toJson()).toList(),
        'statements': statements.map((s) => s.toJson()).toList(),
        'installmentPurchases':
            installmentPurchases.map((p) => p.toJson()).toList(),
      };
```

`fromJson` — lee tanto `statements` (nuevo) como `closedStatements`
(nombre legado, para backups v4 ya exportados con el nombre viejo):
```dart
        movements: (json['movements'] as List<dynamic>? ?? [])
            .map((e) => CardMovement.fromJson(e as Map<String, dynamic>))
            .toList(),
        statements: ((json['statements'] ?? json['closedStatements'])
                as List<dynamic>? ??
            [])
            .map((e) => CardStatement.fromJson(e as Map<String, dynamic>))
            .toList(),
        installmentPurchases:
            (json['installmentPurchases'] as List<dynamic>? ?? [])
                .map((e) =>
                    InstallmentPurchase.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
```

En `lib/data/db/database.dart`, renombrar el parámetro/uso en
`_cardFromRow` de `closedStatements` a `statements`, y extender su firma
para aceptar `installmentPurchases` (ya cableado en Task 3):

```dart
  CardCredit _cardFromRow(
      CreditRow row, List<CardMovement> movements,
      List<CardStatement> statements,
      List<InstallmentPurchase> installmentPurchases) {
    return CardCredit(
      // ...campos existentes sin cambios...
      movements: movements,
      statements: statements,
      installmentPurchases: installmentPurchases,
    );
  }
```

Y en `upsertCredit`, el bucle que antes decía
`for (final s in credit.closedStatements)` pasa a
`for (final s in credit.statements)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/credit_test.dart test/data/installment_purchases_db_test.dart test/data/card_statements_db_test.dart`
Expected: PASS en los tres archivos.

- [ ] **Step 5: Run full existing suite to check no regression**

Run: `flutter test`
Expected: pueden fallar temporalmente los archivos que usan
`closedStatements` (`card_calculator_test.dart`,
`credit_display_utils_test.dart`, `credits_provider_test.dart`) — se
arreglan en las tareas siguientes al migrar esa lógica. Anota cuáles
fallan y por qué (deben ser solo por el rename, nada más) antes de seguir.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/credit.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/models/credit_test.dart
git commit -m "refactor: CardCredit.closedStatements -> statements, agrega installmentPurchases"
```

---

### Task 5: `card_statement_engine.dart` — `computeStatementTotal` + `ensureOpenStatement`

**Files:**
- Create: `lib/domain/card_statement_engine.dart`
- Test: `test/domain/card_statement_engine_test.dart`

**Interfaces:**
- Consumes: `cutoffDateForMonth`, `getCardCycleDates`, `_dueDateForCutoff`
  (ya existen en `card_calculator.dart` — `_dueDateForCutoff` hay que
  hacerla pública, ver Step 3), `toDateStr`/`parseDateStr`
  (`date_utils.dart`).
- Produces: `double computeStatementTotal(CardStatement statement,
  List<CardMovement> movements)`, `CardStatement ensureOpenStatement(
  CardCredit credit, [DateTime? refDate])`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/card_statement_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/card_statement_engine.dart';

void main() {
  group('computeStatementTotal', () {
    test('sums openingBalance + charges/interest/fee - payments, only for '
        'movements linked to this statement', () {
      const statement = CardStatement(
        id: 's1', creditId: 'c1', cutoffDate: '2026-02-15',
        dueDate: '2026-03-07', closingBalance: 0,
        status: CardStatementStatus.open, createdAt: '2026-01-15',
      );
      final other = CardStatement(
        id: 's0', creditId: 'c1', cutoffDate: '2026-01-15',
        dueDate: '2026-02-05', closingBalance: 0,
        status: CardStatementStatus.closed, createdAt: '2026-01-15',
      );
      final movements = [
        CardMovement(date: '2026-01-20', type: CardMovementType.charge, amount: 50000, statementId: 's1'),
        CardMovement(date: '2026-01-25', type: CardMovementType.payment, amount: 10000, statementId: 's1'),
        CardMovement(date: '2026-01-10', type: CardMovementType.charge, amount: 999999, statementId: other.id),
      ];

      final total = computeStatementTotal(statement, movements);

      expect(total, 40000); // 0 (opening) + 50000 - 10000, ignora el de 's0'
    });

    test('includes openingBalance', () {
      const statement = CardStatement(
        id: 's2', creditId: 'c1', cutoffDate: '2026-03-15',
        dueDate: '2026-04-05', closingBalance: 0, openingBalance: 100000,
        status: CardStatementStatus.open, createdAt: '2026-02-15',
      );
      expect(computeStatementTotal(statement, const []), 100000);
    });
  });

  group('ensureOpenStatement', () {
    test('creates an open statement for a brand-new card with no '
        'statements yet', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));

      expect(credit.statements, hasLength(1));
      expect(open.status, CardStatementStatus.open);
      expect(open.cutoffDate, '2026-01-15');
      expect(open.openingBalance, 0);
    });

    test('returns the existing open statement without creating a '
        'duplicate', () {
      final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final first = ensureOpenStatement(credit, DateTime(2026, 1, 10));
      final second = ensureOpenStatement(credit, DateTime(2026, 1, 12));
      expect(credit.statements, hasLength(1));
      expect(second.id, first.id);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: FAIL — `lib/domain/card_statement_engine.dart` no existe.

- [ ] **Step 3: Write minimal implementation**

En `lib/domain/card_calculator.dart`, hacer pública `_dueDateForCutoff`
(renombrarla a `dueDateForCutoff`, quitando el guion bajo — es la única
línea de ese archivo que cambia en este task; actualizar sus 2 usos
internos en el mismo archivo):

```dart
DateTime dueDateForCutoff(CardCredit credit, DateTime cutoff) {
```
(y los 2 call-sites `_dueDateForCutoff(` → `dueDateForCutoff(` dentro de
`getCardCycleDates` y, si aún existe en este punto, `accrueCardCredit`).

```dart
// lib/domain/card_statement_engine.dart
import 'dart:math' as math;

import '../data/models/card_movement.dart';
import '../data/models/card_statement.dart';
import '../data/models/credit.dart';
import '../data/models/installment_purchase.dart';
import 'card_calculator.dart'
    show cutoffDateForMonth, getCardCycleDates, dueDateForCutoff;
import 'date_utils.dart';

double _round2(double v) => (v * 100).round() / 100;

/// El total a pagar de [statement] — SIEMPRE calculado desde los
/// movimientos ligados a él, nunca un valor congelado. Un extracto abierto
/// refleja la realidad en vivo; uno cerrado también, por si se corrige un
/// movimiento después (borrar/editar) — no hay un número "guardado" que
/// pueda quedar desincronizado.
double computeStatementTotal(
    CardStatement statement, List<CardMovement> movements) {
  var total = statement.openingBalance;
  for (final m in movements) {
    if (m.statementId != statement.id) continue;
    total += m.type == CardMovementType.payment ? -m.amount.abs() : m.amount.abs();
  }
  return _round2(total);
}

/// Garantiza que [credit] tenga un extracto abierto, creándolo si hace
/// falta (tarjeta recién creada, o justo después de cerrar el anterior).
/// El extracto abierto representa el ciclo que se está acumulando AHORA —
/// cierra en la próxima fecha de corte (`getCardCycleDates(...).nextCutoff`).
CardStatement ensureOpenStatement(CardCredit credit, [DateTime? refDate]) {
  final existing = credit.statements
      .where((s) => s.status == CardStatementStatus.open)
      .toList();
  if (existing.isNotEmpty) return existing.first;

  final dates = getCardCycleDates(credit, refDate);
  final cutoffDate = toDateStr(dates.nextCutoff);
  final statement = CardStatement(
    id: '${credit.id}-${DateTime.now().microsecondsSinceEpoch}',
    creditId: credit.id,
    cutoffDate: cutoffDate,
    dueDate: toDateStr(dueDateForCutoff(credit, dates.nextCutoff)),
    closingBalance: 0,
    openingBalance: 0,
    status: CardStatementStatus.open,
    createdAt: toDateStr(refDate ?? DateTime.now()),
  );
  credit.statements.add(statement);
  return statement;
}
```

`CardStatement` necesita un campo `openingBalance` — si no existe aún,
agrégalo ahora en `lib/data/models/card_statement.dart` (constructor con
default `0`, incluido en `toJson`/`fromJson`), igual patrón que los demás
campos de esa clase.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_calculator.dart lib/domain/card_statement_engine.dart lib/data/models/card_statement.dart test/domain/card_statement_engine_test.dart
git commit -m "feat: computeStatementTotal + ensureOpenStatement (motor de extractos v2)"
```

---

### Task 6: `closeCurrentCycleIfDue` — transición de ciclo + auto-facturado de cuotas

**Files:**
- Modify: `lib/domain/card_statement_engine.dart`
- Test: `test/domain/card_statement_engine_test.dart`

**Interfaces:**
- Consumes: `computeStatementTotal`, `ensureOpenStatement` (Task 5),
  `dailyRateFrom` (`interest_rate.dart`, ya existe).
- Produces: `void closeCurrentCycleIfDue(CardCredit credit, [DateTime? now])`.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir a test/domain/card_statement_engine_test.dart
group('closeCurrentCycleIfDue', () {
  test('does nothing before the cutoff day arrives', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    ensureOpenStatement(credit, DateTime(2026, 1, 10));
    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 14));
    expect(credit.statements, hasLength(1));
    expect(credit.statements.first.status, CardStatementStatus.open);
  });

  test('closes the open statement the day after its cutoff and opens the '
      'next one, carrying the unpaid balance forward as openingBalance', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.movements.add(CardMovement(
      date: '2026-01-12', type: CardMovementType.charge, amount: 50000,
      statementId: open.id,
    ));

    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

    expect(credit.statements, hasLength(2));
    final closed = credit.statements.firstWhere((s) => s.id == open.id);
    expect(closed.status, CardStatementStatus.closed);
    final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
    expect(newOpen.openingBalance, 50000);
    expect(newOpen.cutoffDate, '2026-02-15');
  });

  test('a closed statement whose total is 0 or less is marked paid, not '
      'closed', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    ensureOpenStatement(credit, DateTime(2026, 1, 10));
    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
    final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
    expect(closed.status, CardStatementStatus.paid);
  });

  test('bills the next pending cuota of every InstallmentPurchase into the '
      'newly-opened statement when a cycle closes', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.installmentPurchases.add(InstallmentPurchase(
      id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
      totalAmount: 90000, installments: 3,
      perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
      installmentsBilled: 1, // cuota 1 ya facturada al comprar
      createdAt: '2026-01-10',
    ));
    credit.movements.add(CardMovement(
      date: '2026-01-10', type: CardMovementType.charge, amount: 30000,
      statementId: open.id, installmentPurchaseId: 'ip1',
      chargeInstallments: 3, installmentIndex: 1,
    ));

    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

    final purchase = credit.installmentPurchases.first;
    expect(purchase.installmentsBilled, 2);
    final newOpen = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
    final cuota2 = credit.movements.firstWhere((m) => m.installmentIndex == 2);
    expect(cuota2.statementId, newOpen.id);
    expect(cuota2.amount, 30000);
    expect(cuota2.installmentPurchaseId, 'ip1');
  });

  test('a purchase that is already fully billed is not touched when a '
      'cycle closes', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.installmentPurchases.add(InstallmentPurchase(
      id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
      totalAmount: 60000, installments: 2,
      perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
      installmentsBilled: 2,
      createdAt: '2026-01-10',
    ));

    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));

    expect(credit.installmentPurchases.first.installmentsBilled, 2);
    expect(credit.movements, isEmpty);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: FAIL — `The function 'closeCurrentCycleIfDue' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Añadir a `lib/domain/card_statement_engine.dart`:

```dart
import 'interest_rate.dart';

/// Cierra el extracto abierto de [credit] cada vez que su fecha de corte ya
/// pasó por completo (el día de corte pertenece al ciclo hasta las 23:59;
/// recién al día siguiente se cierra), aplicando interés/cuota de manejo,
/// abriendo el siguiente extracto, y facturando automáticamente la próxima
/// cuota pendiente de cada InstallmentPurchase en el extracto nuevo.
/// Idempotente — seguro de llamar en cada arranque de la app. Capado a 36
/// iteraciones como red de seguridad.
void closeCurrentCycleIfDue(CardCredit credit, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);
  final cutoffDay = math.min(math.max(credit.cutoffDay, 1), 31);

  var open = ensureOpenStatement(credit, todayMidnight);
  var safety = 0;
  while (safety < 36) {
    final cutoff = parseDateStr(open.cutoffDate);
    if (!cutoff.isBefore(todayMidnight)) break; // aún no pasó por completo

    // Interés sobre el total del extracto que se está cerrando.
    final dailyRate = dailyRateFrom(credit.interestRate, credit.interestRateType);
    final balanceBeforeInterest = computeStatementTotal(open, credit.movements);
    final openedAt = _openedAtFor(credit, open);
    final daysInCycle = cutoff.difference(openedAt).inDays;
    if (balanceBeforeInterest > 0 && dailyRate > 0) {
      final interestAmt = _round2(balanceBeforeInterest * dailyRate * daysInCycle);
      credit.movements.add(CardMovement(
        date: open.cutoffDate,
        type: CardMovementType.interest,
        amount: interestAmt,
        statementId: open.id,
        note: 'Interés corriente (${daysInCycle}d × tasa diaria)',
      ));
    }

    credit.cycleCount++;
    final fee = credit.managementFee;
    if (fee > 0) {
      final chargeFee = credit.managementFeeFrequency == ManagementFeeFrequency.annual
          ? (credit.cycleCount % 12 == 0)
          : true;
      if (chargeFee) {
        credit.movements.add(CardMovement(
          date: open.cutoffDate,
          type: CardMovementType.fee,
          amount: fee,
          statementId: open.id,
          note: 'Cuota de manejo',
        ));
      }
    }

    final closingTotal = computeStatementTotal(open, credit.movements);
    final closedIndex = credit.statements.indexWhere((s) => s.id == open.id);
    final closed = CardStatement(
      id: open.id,
      creditId: open.creditId,
      cutoffDate: open.cutoffDate,
      dueDate: open.dueDate,
      closingBalance: closingTotal,
      paidAmount: open.paidAmount,
      status: closingTotal <= 0 ? CardStatementStatus.paid : CardStatementStatus.closed,
      createdAt: open.createdAt,
    );
    credit.statements[closedIndex] = closed;

    final nextCutoffRef = DateTime(cutoff.year, cutoff.month + 1, 1);
    final nextCutoff = cutoffDateForMonth(nextCutoffRef.year, nextCutoffRef.month, cutoffDay);
    final newOpen = CardStatement(
      id: '${credit.id}-${nextCutoff.microsecondsSinceEpoch}',
      creditId: credit.id,
      cutoffDate: toDateStr(nextCutoff),
      dueDate: toDateStr(dueDateForCutoff(credit, nextCutoff)),
      closingBalance: 0,
      openingBalance: closingTotal - closed.paidAmount,
      status: CardStatementStatus.open,
      createdAt: toDateStr(todayMidnight),
    );
    credit.statements.add(newOpen);

    // Auto-facturar la próxima cuota pendiente de cada compra a plazos.
    for (final purchase in credit.installmentPurchases) {
      if (purchase.isFullyBilled) continue;
      final nextIndex = purchase.installmentsBilled + 1;
      final amount = nextIndex == purchase.installments
          ? purchase.lastInstallmentAmount
          : purchase.perInstallmentAmount;
      credit.movements.add(CardMovement(
        date: toDateStr(nextCutoff),
        type: CardMovementType.charge,
        amount: amount,
        note: purchase.note,
        categoria: purchase.categoria,
        statementId: newOpen.id,
        installmentPurchaseId: purchase.id,
        chargeInstallments: purchase.installments,
        installmentIndex: nextIndex,
      ));
      purchase.installmentsBilled = nextIndex;
    }

    open = newOpen;
    safety++;
  }
}

/// Fecha en que [statement] empezó a acumularse — el corte del extracto
/// anterior + 1 día, o su propia `createdAt` si es el primero de la
/// tarjeta (no hay anterior del cual partir).
DateTime _openedAtFor(CardCredit credit, CardStatement statement) {
  final sorted = credit.statements.toList()
    ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));
  final idx = sorted.indexWhere((s) => s.id == statement.id);
  if (idx <= 0) return parseDateStr(statement.createdAt);
  return parseDateStr(sorted[idx - 1].cutoffDate).add(const Duration(days: 1));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: PASS (todos)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_statement_engine.dart test/domain/card_statement_engine_test.dart
git commit -m "feat: closeCurrentCycleIfDue — cierra ciclo y auto-factura cuotas pendientes"
```

---

### Task 7: `registerCardCharge` + `registerInstallmentPurchase`

**Files:**
- Modify: `lib/domain/card_statement_engine.dart`
- Test: `test/domain/card_statement_engine_test.dart`

**Interfaces:**
- Consumes: `ensureOpenStatement` (Task 5).
- Produces: `void registerCardCharge(CardCredit credit, double amount,
  {String note = '', String? categoria, DateTime? refDate})`,
  `InstallmentPurchase registerInstallmentPurchase(CardCredit credit,
  double totalAmount, int installments, {String note = '', String?
  categoria, DateTime? refDate})`.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir a test/domain/card_statement_engine_test.dart
group('registerCardCharge', () {
  test('creates a single charge linked to the open statement', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    registerCardCharge(credit, 50000, note: 'Café', refDate: DateTime(2026, 1, 10));

    expect(credit.movements, hasLength(1));
    final open = credit.statements.single;
    expect(credit.movements.first.statementId, open.id);
    expect(computeStatementTotal(open, credit.movements), 50000);
  });
});

group('registerInstallmentPurchase', () {
  test('creates the purchase and bills cuota 1 immediately into the open '
      'statement', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final purchase = registerInstallmentPurchase(
      credit, 90000, 3, note: 'TV', refDate: DateTime(2026, 1, 10),
    );

    expect(credit.installmentPurchases, hasLength(1));
    expect(purchase.installmentsBilled, 1);
    expect(credit.movements, hasLength(1));
    expect(credit.movements.first.installmentIndex, 1);
    expect(credit.movements.first.installmentPurchaseId, purchase.id);
    final open = credit.statements.single;
    expect(computeStatementTotal(open, credit.movements), 30000);
  });

  test('rounding remainder goes on lastInstallmentAmount, sum equals the '
      'exact total', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final purchase = registerInstallmentPurchase(credit, 100.01, 3, refDate: DateTime(2026, 1, 10));
    final sum = purchase.perInstallmentAmount * 2 + purchase.lastInstallmentAmount;
    expect(sum, closeTo(100.01, 0.001));
  });

  test('a purchase made exactly on the cutoff day bills cuota 1 into the '
      'statement that closes THAT day — same as a single-cuota charge '
      'would (both use ensureOpenStatement/getCardCycleDates consistently)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final purchase = registerInstallmentPurchase(credit, 90000, 3, refDate: DateTime(2026, 1, 15));
    final open = credit.statements.single;
    expect(open.cutoffDate, '2026-01-15');
    expect(credit.movements.first.statementId, open.id);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: FAIL — `The function 'registerCardCharge' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Registra un cargo de 1 sola exhibición, ligado al extracto abierto.
void registerCardCharge(
  CardCredit credit,
  double amount, {
  String note = '',
  String? categoria,
  DateTime? refDate,
}) {
  final open = ensureOpenStatement(credit, refDate);
  credit.movements.add(CardMovement(
    date: toDateStr(refDate ?? DateTime.now()),
    type: CardMovementType.charge,
    amount: amount.abs(),
    note: note,
    categoria: categoria,
    statementId: open.id,
  ));
}

/// Registra una compra a [installments] cuotas: crea la InstallmentPurchase
/// y factura la cuota 1 de inmediato en el extracto abierto. Las cuotas
/// 2..N se facturan solas cuando sus ciclos abran (closeCurrentCycleIfDue).
InstallmentPurchase registerInstallmentPurchase(
  CardCredit credit,
  double totalAmount,
  int installments, {
  String note = '',
  String? categoria,
  DateTime? refDate,
}) {
  final open = ensureOpenStatement(credit, refDate);
  final perInstallment = _round2(totalAmount / installments);
  final lastInstallment = _round2(totalAmount - perInstallment * (installments - 1));
  final purchaseDate = toDateStr(refDate ?? DateTime.now());

  final purchase = InstallmentPurchase(
    id: '${credit.id}-ip-${DateTime.now().microsecondsSinceEpoch}',
    creditId: credit.id,
    purchaseDate: purchaseDate,
    totalAmount: totalAmount,
    installments: installments,
    perInstallmentAmount: perInstallment,
    lastInstallmentAmount: lastInstallment,
    note: note,
    categoria: categoria,
    installmentsBilled: 1,
    createdAt: purchaseDate,
  );
  credit.installmentPurchases.add(purchase);

  credit.movements.add(CardMovement(
    date: purchaseDate,
    type: CardMovementType.charge,
    amount: installments == 1 ? totalAmount : perInstallment,
    note: note,
    categoria: categoria,
    statementId: open.id,
    installmentPurchaseId: purchase.id,
    chargeInstallments: installments,
    installmentIndex: 1,
  ));

  return purchase;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: PASS (todos)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_statement_engine.dart test/domain/card_statement_engine_test.dart
git commit -m "feat: registerCardCharge y registerInstallmentPurchase (motor v2)"
```

---

### Task 8: `registerCardPayment` (FIFO) + `recomputeCardBalance`

**Files:**
- Modify: `lib/domain/card_statement_engine.dart`
- Test: `test/domain/card_statement_engine_test.dart`

**Interfaces:**
- Consumes: `ensureOpenStatement`, `computeStatementTotal` (Task 5).
- Produces: `void registerCardPayment(CardCredit credit, double amount,
  {DateTime? refDate})`, `void recomputeCardBalance(CardCredit credit)`.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir a test/domain/card_statement_engine_test.dart
group('registerCardPayment', () {
  CardCredit cardWithOneClosedStatement(double closingTotal) {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.movements.add(CardMovement(
      date: '2026-01-12', type: CardMovementType.charge, amount: closingTotal,
      statementId: open.id,
    ));
    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
    return credit;
  }

  test('a payment that exactly covers the oldest closed statement marks '
      'it paid', () {
    final credit = cardWithOneClosedStatement(100000);
    registerCardPayment(credit, 100000, refDate: DateTime(2026, 1, 20));

    final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
    expect(closed.paidAmount, 100000);
    expect(closed.status, CardStatementStatus.paid);
  });

  test('an overpayment carries the remainder into the open statement as '
      'an advance payment, not lost', () {
    final credit = cardWithOneClosedStatement(100000);
    registerCardPayment(credit, 150000, refDate: DateTime(2026, 1, 20));

    final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
    expect(closed.paidAmount, 100000);
    final open = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
    expect(computeStatementTotal(open, credit.movements), -50000);
  });

  test('a partial payment reduces the oldest closed statement without '
      'marking it paid', () {
    final credit = cardWithOneClosedStatement(100000);
    registerCardPayment(credit, 40000, refDate: DateTime(2026, 1, 20));

    final closed = credit.statements.firstWhere((s) => s.status != CardStatementStatus.open);
    expect(closed.paidAmount, 40000);
    expect(closed.status, CardStatementStatus.closed);
  });
});

group('recomputeCardBalance', () {
  test('currentBalance = sum of unpaid statements + remaining unbilled '
      'cuotas of installment purchases', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.movements.add(CardMovement(
      date: '2026-01-10', type: CardMovementType.charge, amount: 20000,
      statementId: open.id,
    ));
    credit.installmentPurchases.add(InstallmentPurchase(
      id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
      totalAmount: 90000, installments: 3,
      perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
      installmentsBilled: 1,
      createdAt: '2026-01-10',
    ));

    recomputeCardBalance(credit);

    // 20000 (abierto) + 60000 (2 cuotas de 30000 aún no facturadas)
    expect(credit.currentBalance, 80000);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: FAIL — `The function 'registerCardPayment' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Aplica [amount] primero a los extractos CERRADOS sin pagar, del más
/// antiguo al más reciente (FIFO). Lo que sobre después de cubrirlos todos
/// se registra como pago anticipado sobre el extracto ABIERTO (puede
/// dejarlo en negativo — un "saldo a favor" que se descuenta del próximo
/// cierre).
void registerCardPayment(
  CardCredit credit,
  double amount, {
  DateTime? refDate,
}) {
  final date = toDateStr(refDate ?? DateTime.now());
  var remaining = amount.abs();

  final unpaidClosed = credit.statements
      .where((s) => s.status == CardStatementStatus.closed)
      .toList()
    ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));

  for (final statement in unpaidClosed) {
    if (remaining <= 0) break;
    final total = computeStatementTotal(statement, credit.movements);
    final owed = total - statement.paidAmount;
    if (owed <= 0) continue;
    final applied = math.min(remaining, owed);
    final idx = credit.statements.indexWhere((s) => s.id == statement.id);
    final newPaid = _round2(statement.paidAmount + applied);
    credit.statements[idx] = CardStatement(
      id: statement.id,
      creditId: statement.creditId,
      cutoffDate: statement.cutoffDate,
      dueDate: statement.dueDate,
      closingBalance: statement.closingBalance,
      paidAmount: newPaid,
      status: newPaid >= total ? CardStatementStatus.paid : CardStatementStatus.closed,
      createdAt: statement.createdAt,
    );
    credit.movements.add(CardMovement(
      date: date,
      type: CardMovementType.payment,
      amount: applied,
      statementId: statement.id,
    ));
    remaining = _round2(remaining - applied);
  }

  if (remaining > 0) {
    final open = ensureOpenStatement(credit, refDate);
    credit.movements.add(CardMovement(
      date: date,
      type: CardMovementType.payment,
      amount: remaining,
      statementId: open.id,
    ));
  }
}

/// Recalcula credit.currentBalance desde cero: nunca se suma/resta a mano
/// en ningún otro lugar. Incluye lo que ya está facturado en extractos sin
/// pagar (abierto + cerrados) más las cuotas de compras a plazos que aún
/// no se han facturado (reservan cupo igual que un banco real).
void recomputeCardBalance(CardCredit credit) {
  var total = 0.0;
  for (final statement in credit.statements) {
    if (statement.status == CardStatementStatus.paid) continue;
    total += computeStatementTotal(statement, credit.movements) - statement.paidAmount;
  }
  for (final purchase in credit.installmentPurchases) {
    total += purchase.remainingAmount;
  }
  credit.currentBalance = _round2(total);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: PASS (todos)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_statement_engine.dart test/domain/card_statement_engine_test.dart
git commit -m "feat: registerCardPayment (FIFO) y recomputeCardBalance (motor v2)"
```

---

### Task 9: `getPayableSummary` v2 + `deleteCardMovement` v2 (basado en recompute)

**Files:**
- Modify: `lib/domain/card_statement_engine.dart`
- Test: `test/domain/card_statement_engine_test.dart`

**Interfaces:**
- Consumes: `computeStatementTotal`, `recomputeCardBalance` (Tasks 5, 8).
- Produces: `class PayableSummary` (mismos 3 campos que la v1:
  `exigible`, `pendienteFacturar`, `dueDate`), `PayableSummary
  getPayableSummary(CardCredit credit)`, `void deleteCardMovement(
  CardCredit credit, int index)`.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir a test/domain/card_statement_engine_test.dart
group('getPayableSummary v2', () {
  test('exigible = suma de extractos cerrados sin pagar; dueDate = el '
      'más antiguo de ellos (vence primero)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.movements.add(CardMovement(date: '2026-01-12', type: CardMovementType.charge, amount: 50000, statementId: open.id));
    closeCurrentCycleIfDue(credit, DateTime(2026, 1, 16));
    final open2 = credit.statements.firstWhere((s) => s.status == CardStatementStatus.open);
    credit.movements.add(CardMovement(date: '2026-02-12', type: CardMovementType.charge, amount: 30000, statementId: open2.id));
    closeCurrentCycleIfDue(credit, DateTime(2026, 2, 16));

    final summary = getPayableSummary(credit);

    expect(summary.exigible, 80000); // 50000 + 30000, 2 extractos distintos
    expect(summary.dueDate, parseDateStr(credit.statements.firstWhere((s) => s.cutoffDate == '2026-01-15').dueDate));
  });

  test('pendienteFacturar = total del extracto abierto + cuotas sin '
      'facturar', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final open = ensureOpenStatement(credit, DateTime(2026, 1, 10));
    credit.movements.add(CardMovement(date: '2026-01-10', type: CardMovementType.charge, amount: 10000, statementId: open.id));
    credit.installmentPurchases.add(InstallmentPurchase(
      id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
      totalAmount: 60000, installments: 2,
      perInstallmentAmount: 30000, lastInstallmentAmount: 30000,
      installmentsBilled: 1, createdAt: '2026-01-10',
    ));

    final summary = getPayableSummary(credit);

    expect(summary.pendienteFacturar, 40000); // 10000 abierto + 30000 cuota pendiente
  });
});

group('deleteCardMovement v2', () {
  test('removing a charge recomputes the statement total — no manual '
      'delta tracking needed', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    registerCardCharge(credit, 50000, refDate: DateTime(2026, 1, 10));
    registerCardCharge(credit, 20000, refDate: DateTime(2026, 1, 11));
    recomputeCardBalance(credit);
    expect(credit.currentBalance, 70000);

    deleteCardMovement(credit, 0);
    recomputeCardBalance(credit);

    expect(credit.movements, hasLength(1));
    expect(credit.currentBalance, 20000);
  });

  test('deleting the most recently billed cuota of an InstallmentPurchase '
      'decrements installmentsBilled so it can be re-billed next close', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final purchase = registerInstallmentPurchase(credit, 90000, 3, refDate: DateTime(2026, 1, 10));
    expect(purchase.installmentsBilled, 1);

    deleteCardMovement(credit, 0); // borra la única cuota facturada (cuota 1)

    expect(purchase.installmentsBilled, 0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: FAIL — `The function 'getPayableSummary' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Lo que el usuario debe AHORA (extractos cerrados sin pagar por
/// completo) vs. lo que ya está cargado pero aún no se le exige pagar
/// (extracto abierto + cuotas de compras a plazos aún no facturadas).
class PayableSummary {
  final double exigible;
  final double pendienteFacturar;
  final DateTime? dueDate;

  const PayableSummary({
    required this.exigible,
    required this.pendienteFacturar,
    this.dueDate,
  });
}

PayableSummary getPayableSummary(CardCredit credit) {
  final unpaidClosed = credit.statements
      .where((s) => s.status == CardStatementStatus.closed)
      .toList()
    ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));

  final exigible = _round2(unpaidClosed.fold(
      0.0,
      (sum, s) =>
          sum + (computeStatementTotal(s, credit.movements) - s.paidAmount)));
  final dueDate = unpaidClosed.isEmpty ? null : parseDateStr(unpaidClosed.first.dueDate);

  final openTotal = credit.statements
      .where((s) => s.status == CardStatementStatus.open)
      .fold(0.0, (sum, s) => sum + computeStatementTotal(s, credit.movements));
  final unbilledCuotas = credit.installmentPurchases
      .fold(0.0, (sum, p) => sum + p.remainingAmount);

  return PayableSummary(
    exigible: exigible,
    pendienteFacturar: _round2(openTotal + unbilledCuotas),
    dueDate: dueDate,
  );
}

/// Elimina credit.movements[index] y, si era una cuota de una compra a
/// plazos y era la MÁS RECIENTE facturada de esa compra, decrementa
/// installmentsBilled para que se vuelva a facturar en el próximo cierre
/// de ciclo en vez de perderse. No hay tracking manual de delta sobre
/// currentBalance — el llamador debe invocar recomputeCardBalance después.
void deleteCardMovement(CardCredit credit, int index) {
  if (index < 0 || index >= credit.movements.length) return;
  final removed = credit.movements[index];
  credit.movements.removeAt(index);

  final purchaseId = removed.installmentPurchaseId;
  if (purchaseId != null) {
    final purchase = credit.installmentPurchases
        .where((p) => p.id == purchaseId)
        .firstOrNull;
    if (purchase != null &&
        removed.installmentIndex == purchase.installmentsBilled) {
      purchase.installmentsBilled -= 1;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_statement_engine_test.dart`
Expected: PASS (todos)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_statement_engine.dart test/domain/card_statement_engine_test.dart
git commit -m "feat: getPayableSummary y deleteCardMovement v2 (motor de extractos)"
```

---

### Task 10: Migración de datos legados — `migrateLegacyCardData`

**Files:**
- Modify: `lib/domain/card_statement_engine.dart`
- Test: `test/domain/card_statement_engine_migration_test.dart`

**Interfaces:**
- Consumes: `cycleKeyFor` (`card_calculator.dart`, ya existe),
  `ensureOpenStatement` (Task 5).
- Produces: `void migrateLegacyCardData(CardCredit credit, [DateTime?
  refDate])` — idempotente, se puede llamar en cada arranque sin efecto
  si ya no hay nada legado que migrar.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/card_statement_engine_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/card_statement_engine.dart';

void main() {
  test('a movement with no statementId gets backfilled to a statement '
      'inferred from cycleKeyFor(date, cutoffDay)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    credit.movements.add(CardMovement(
      date: '2026-01-10', type: CardMovementType.charge, amount: 50000,
      // sin statementId — dato legado
    ));

    migrateLegacyCardData(credit, DateTime(2026, 1, 20));

    expect(credit.movements.first.statementId, isNotNull);
    final statement = credit.statements
        .firstWhere((s) => s.id == credit.movements.first.statementId);
    expect(statement.cutoffDate, '2026-01-15');
  });

  test('a movement that already has statementId is left untouched', () {
    final credit = CardCredit(
      id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15,
      statements: [
        const CardStatement(
          id: 's1', creditId: 'c1', cutoffDate: '2026-01-15',
          dueDate: '2026-02-05', closingBalance: 0,
          status: CardStatementStatus.closed, createdAt: '2026-01-15',
        ),
      ],
      movements: [
        CardMovement(date: '2026-01-10', type: CardMovementType.charge, amount: 50000, statementId: 's1'),
      ],
    );

    migrateLegacyCardData(credit, DateTime(2026, 1, 20));

    expect(credit.movements.first.statementId, 's1');
    expect(credit.statements, hasLength(1)); // no crea duplicados
  });

  test('ensures an open statement exists after migrating', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    migrateLegacyCardData(credit, DateTime(2026, 1, 20));
    expect(credit.statements.any((s) => s.status == CardStatementStatus.open), isTrue);
  });

  test('is a no-op on a card with nothing legacy to migrate (idempotent)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    migrateLegacyCardData(credit, DateTime(2026, 1, 20));
    final statementsCountAfterFirst = credit.statements.length;
    migrateLegacyCardData(credit, DateTime(2026, 1, 20));
    expect(credit.statements.length, statementsCountAfterFirst);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_statement_engine_migration_test.dart`
Expected: FAIL — `The function 'migrateLegacyCardData' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'card_calculator.dart' show cycleKeyFor;
// (agregar al import `show` ya existente de card_calculator.dart en este
// archivo, junto a cutoffDateForMonth/getCardCycleDates/dueDateForCutoff)

/// Migra datos de tarjetas creadas antes del motor de extractos v2:
/// liga cada CardMovement sin `statementId` al extracto que le
/// corresponde (inferido con el mismo criterio de agrupación legado,
/// `cycleKeyFor`), creando ese CardStatement si no existe todavía —
/// reutilizando uno existente con el mismo `cutoffDate` si ya se creó
/// para otro movimiento del mismo ciclo. Idempotente: una tarjeta sin
/// nada legado no se modifica. Llamar SIEMPRE antes de
/// `closeCurrentCycleIfDue` en el flujo de arranque.
void migrateLegacyCardData(CardCredit credit, [DateTime? refDate]) {
  final legacyMovements =
      credit.movements.where((m) => m.statementId == null).toList();

  for (final m in legacyMovements) {
    final cutoffDate = m.statementCutoff ?? cycleKeyFor(m.date, credit.cutoffDay);
    var statement = credit.statements
        .where((s) => s.cutoffDate == cutoffDate)
        .firstOrNull;
    statement ??= _createLegacyStatement(credit, cutoffDate);
    final idx = credit.movements.indexOf(m);
    credit.movements[idx] = CardMovement(
      date: m.date,
      type: m.type,
      amount: m.amount,
      note: m.note,
      advanceInstallments: m.advanceInstallments,
      advanceInterestRate: m.advanceInterestRate,
      advanceInterestRateType: m.advanceInterestRateType,
      advanceCommission: m.advanceCommission,
      advanceFirstPaymentDate: m.advanceFirstPaymentDate,
      advanceDestination: m.advanceDestination,
      categoria: m.categoria,
      chargeInstallments: m.chargeInstallments,
      installmentIndex: m.installmentIndex,
      statementId: statement.id,
    );
  }

  ensureOpenStatement(credit, refDate);
}

CardStatement _createLegacyStatement(CardCredit credit, String cutoffDate) {
  final cutoff = parseDateStr(cutoffDate);
  final dueDate = toDateStr(dueDateForCutoff(credit, cutoff));
  final statement = CardStatement(
    id: '${credit.id}-legacy-$cutoffDate',
    creditId: credit.id,
    cutoffDate: cutoffDate,
    dueDate: dueDate,
    closingBalance: 0,
    status: CardStatementStatus.closed,
    createdAt: cutoffDate,
  );
  credit.statements.add(statement);
  return statement;
}
```

No se intenta reconstruir `InstallmentPurchase` desde cuotas legadas en
este task — es un YAGNI aceptado explícitamente: los movimientos legados
ya tienen TODAS sus cuotas creadas de antemano (así funcionaba la versión
anterior), así que no necesitan auto-facturado futuro; quedan como cargos
sueltos ligados a su extracto inferido, mostrando igual su
`chargeInstallments`/`installmentIndex` ya existentes para el texto "cuota
X de Y" en la UI. Esto es exactamente lo que pide el Review Focus del spec
("mejor dejarlas sin reconstruir que reconstruir mal").

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_statement_engine_migration_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_statement_engine.dart test/domain/card_statement_engine_migration_test.dart
git commit -m "feat: migrateLegacyCardData — backfill de datos previos al motor v2"
```

---

### Task 11: Cablear en `credits_provider.dart`

**Files:**
- Modify: `lib/providers/credits_provider.dart`
- Test: `test/providers/credits_provider_test.dart` (reemplaza los tests
  existentes que usaban la API vieja)

**Interfaces:**
- Consumes: `migrateLegacyCardData`, `closeCurrentCycleIfDue`,
  `ensureOpenStatement`, `registerCardCharge`, `registerInstallmentPurchase`,
  `registerCardPayment`, `recomputeCardBalance`, `deleteCardMovement`,
  `getPayableSummary` (Tasks 5-10, todas en `card_statement_engine.dart`).

- [ ] **Step 1: Write the failing test**

Reemplazar TODO el contenido de `test/providers/credits_provider_test.dart`
por:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/date_utils.dart';
import 'package:krezium/providers/credits_provider.dart';
import 'package:krezium/providers/database_provider.dart';

void main() {
  test('addCredit creates the open statement immediately for a brand-new '
      'card — not just on the next app launch', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.future);

    final card = CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15);
    await container.read(creditsProvider.notifier).addCredit(card);

    final credits = container.read(creditsProvider).value!;
    final saved = credits.whereType<CardCredit>().first;
    expect(saved.statements, hasLength(1));
    expect(saved.statements.first.status, CardStatementStatus.open);
  });

  test('registerMovement with chargeInstallments > 1 creates an '
      'InstallmentPurchase and bills only cuota 1 immediately', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.notifier).addCredit(
        CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15));

    await container.read(creditsProvider.notifier).registerMovement(
          'c1', CardMovementType.charge, 90000, 'TV', chargeInstallments: 3,
        );

    final credits = container.read(creditsProvider).value!;
    final card = credits.whereType<CardCredit>().first;
    expect(card.installmentPurchases, hasLength(1));
    expect(card.installmentPurchases.first.installmentsBilled, 1);
    expect(card.movements, hasLength(1));
  });

  test('registerMovement payment applies via the new FIFO engine', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.notifier).addCredit(
        CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15));
    final notifier = container.read(creditsProvider.notifier);
    await notifier.registerMovement('c1', CardMovementType.charge, 50000, 'Café');

    await notifier.registerMovement('c1', CardMovementType.payment, 50000, 'Pago');

    final credits = container.read(creditsProvider).value!;
    final card = credits.whereType<CardCredit>().first;
    expect(card.currentBalance, 0);
  });

  test('deleteMovement removes the movement and recomputes currentBalance '
      '(no leftover manual delta)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    addTearDown(db.close);
    await container.read(creditsProvider.notifier).addCredit(
        CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15));
    final notifier = container.read(creditsProvider.notifier);
    await notifier.registerMovement('c1', CardMovementType.charge, 50000, 'Café');

    await notifier.deleteMovement('c1', 0);

    final credits = container.read(creditsProvider).value!;
    final card = credits.whereType<CardCredit>().first;
    expect(card.movements, isEmpty);
    expect(card.currentBalance, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/credits_provider_test.dart`
Expected: FAIL — `addCredit` no crea extracto abierto (`saved.statements`
vacío), y las demás rutas siguen usando las funciones viejas de
`card_calculator.dart`.

- [ ] **Step 3: Write minimal implementation**

En `lib/providers/credits_provider.dart`, reemplazar el import de
`card_calculator.dart` por el motor nuevo (mantener `card_calculator.dart`
solo si se necesita algo de él en este archivo — no se necesita nada
directamente, se puede quitar):

```dart
import '../domain/card_statement_engine.dart';
```

Modificar `_accrueAndRecompute` (bloque `if (c is CardCredit)`):

```dart
      if (c is CardCredit) {
        final before = c.currentBalance;
        final beforeMovements = c.movements.length;
        final beforeStatements = c.statements.length;
        migrateLegacyCardData(c);
        closeCurrentCycleIfDue(c);
        recomputeCardBalance(c);
        changed = c.currentBalance != before ||
            c.movements.length != beforeMovements ||
            c.statements.length != beforeStatements;
      } else if (c is LoanCredit && !c.scheduleManuallyAdjusted) {
```

Modificar `addCredit` para crear el extracto abierto de inmediato:

```dart
  Future<void> addCredit(Credit credit) async {
    _clearInterestUnknownIfRateKnown(credit);
    if (credit is CardCredit) {
      ensureOpenStatement(credit);
    }
    await _db.upsertCredit(credit);
    final current = List<Credit>.from(state.value ?? [])..add(credit);
    state = AsyncData(current);
  }
```

Modificar `registerMovement`:

```dart
  Future<void> registerMovement(
    String creditId,
    String type,
    double amount,
    String note, {
    String? categoria,
    int? chargeInstallments,
  }) async {
    final credits = state.value ?? [];
    final credit = credits.whereType<CardCredit>().where((c) => c.id == creditId).firstOrNull;
    if (credit == null) return;
    if (type == CardMovementType.payment) {
      registerCardPayment(credit, amount);
    } else if ((chargeInstallments ?? 1) > 1) {
      registerInstallmentPurchase(credit, amount, chargeInstallments!, note: note, categoria: categoria);
    } else {
      registerCardCharge(credit, amount, note: note, categoria: categoria);
    }
    recomputeCardBalance(credit);
    await _db.upsertCredit(credit);
    _notifyInPlace();
  }
```

Modificar `deleteMovement`:

```dart
  Future<void> deleteMovement(String creditId, int movementIndex) async {
    final credits = state.value ?? [];
    final credit = credits.whereType<CardCredit>().where((c) => c.id == creditId).firstOrNull;
    if (credit == null) return;
    deleteCardMovement(credit, movementIndex);
    recomputeCardBalance(credit);
    await _db.upsertCredit(credit);
    _notifyInPlace();
  }
```

`registerAdvance` queda igual (los avances no participan del motor de
extractos en esta iteración — ya estaba fuera de alcance en el diseño
original y sigue fuera aquí; solo revisar que sigue compilando porque
importa `CardMovementType` desde `card_movement.dart` directo, no desde
`card_calculator.dart`).

El import de `card_movement.dart` para `CardMovementType` ya existe en el
archivo — no toca cambiarlo.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/credits_provider_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: Run full suite to check no regression**

Run: `flutter test`
Expected: Los tests de `test/domain/card_calculator_test.dart` que
ejercitaban `accrueCardCredit`/`registerCardMovement`/`registerCardCharge`/
`getPayableSummary`/`deleteCardMovement` (funciones que esta tarea deja de
usar desde el provider, pero que siguen existiendo en
`card_calculator.dart` hasta el siguiente paso) deben seguir pasando tal
cual — no se tocan en esta tarea. `test/utils/credit_display_utils_test.dart`
puede fallar porque `getNextDueDate` todavía llama a la `getPayableSummary`
vieja sobre `credit.closedStatements` (que ya no existe, fue renombrado en
Task 4) — anota esta falla, se corrige en Task 12 al actualizar la UI.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/credits_provider.dart test/providers/credits_provider_test.dart
git commit -m "feat: cablea el motor de extractos v2 en CreditsNotifier"
```

---

### Task 12: Limpieza de `card_calculator.dart` + actualizar UI (`credit_display_utils.dart`, `movements_tab.dart`, `wallet_card.dart`, `credit_detail_screen.dart`)

**Files:**
- Modify: `lib/domain/card_calculator.dart` (quitar funciones reemplazadas)
- Modify: `lib/utils/credit_display_utils.dart`
- Modify: `lib/widgets/credit_detail/movements_tab.dart`
- Modify: `lib/widgets/wallet_card.dart`
- Modify: `lib/screens/credit_detail/credit_detail_screen.dart`
- Test: `test/domain/card_calculator_test.dart` (eliminar los grupos de
  las funciones quitadas), `test/utils/credit_display_utils_test.dart`,
  `test/widgets/credit_detail/movements_tab_grouping_test.dart` (reemplazar)

**Interfaces:**
- Consumes: `getPayableSummary`, `getCardAvailableLimit` (de
  `card_statement_engine.dart` ahora — mover `getCardAvailableLimit`
  también, ver Step 3).

- [ ] **Step 1: Write the failing test**

En `test/utils/credit_display_utils_test.dart`, reemplazar el contenido
completo:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/date_utils.dart';
import 'package:krezium/utils/credit_display_utils.dart';

void main() {
  test('getNextDueDate for a card with no closed statements returns null', () {
    final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    expect(getNextDueDate(card), isNull);
  });

  test('getNextDueDate for a card with an unpaid closed statement returns '
      'that statement\'s dueDate', () {
    final card = CardCredit(
      id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15,
      statements: [
        const CardStatement(
          id: 's1', creditId: 'c1', cutoffDate: '2026-01-15',
          dueDate: '2026-02-05', closingBalance: 100000,
          status: CardStatementStatus.closed, createdAt: '2026-01-15',
        ),
      ],
    );
    expect(getNextDueDate(card), parseDateStr('2026-02-05'));
  });
}
```

En `test/widgets/credit_detail/movements_tab_grouping_test.dart`,
reemplazar el contenido completo (ya no existe `groupMovementsByCycle`,
las cuotas no se agrupan por fecha calculada sino por `statementId`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/widgets/credit_detail/movements_tab.dart';

void main() {
  test('groupMovementsByStatement groups by statementId, ordered by '
      'cutoffDate ascending (abierto al final, igual que la lista de '
      'statements ya viene ordenada cronológicamente desde el motor)', () {
    const s1 = CardStatement(id: 's1', creditId: 'c1', cutoffDate: '2026-01-15', dueDate: '2026-02-05', closingBalance: 0, status: CardStatementStatus.closed, createdAt: '2026-01-15');
    const s2 = CardStatement(id: 's2', creditId: 'c1', cutoffDate: '2026-02-15', dueDate: '2026-03-07', closingBalance: 0, status: CardStatementStatus.open, createdAt: '2026-02-15');
    final movements = [
      CardMovement(date: '2026-01-20', type: CardMovementType.charge, amount: 50000, statementId: 's1'),
      CardMovement(date: '2026-02-20', type: CardMovementType.charge, amount: 30000, statementId: 's2'),
    ];

    final groups = groupMovementsByStatement([s1, s2], movements);

    expect(groups[0].statement.id, 's1');
    expect(groups[0].movements, hasLength(1));
    expect(groups[1].statement.id, 's2');
  });

  test('a statement with no movements still appears (empty group) — a '
      'brand-new open cycle with nothing charged yet is still visible', () {
    const s1 = CardStatement(id: 's1', creditId: 'c1', cutoffDate: '2026-01-15', dueDate: '2026-02-05', closingBalance: 0, status: CardStatementStatus.open, createdAt: '2026-01-15');
    final groups = groupMovementsByStatement([s1], const []);
    expect(groups, hasLength(1));
    expect(groups.first.movements, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/credit_display_utils_test.dart test/widgets/credit_detail/movements_tab_grouping_test.dart`
Expected: FAIL — `getNextDueDate` referencia símbolos movidos;
`groupMovementsByStatement`/`StatementGroup` no existen.

- [ ] **Step 3: Write minimal implementation**

**3a. `lib/domain/card_calculator.dart`** — eliminar por completo:
`accrueCardCredit`, `registerCardMovement`, `_applyPaymentToLatestStatement`,
`buildInstallmentMovements`, `registerCardCharge`, `deleteCardMovement`,
`getCardRemainingBalance`, `getCardAvailableLimit`, `PayableSummary`,
`getPayableSummary` — todas reemplazadas por `card_statement_engine.dart`.
Dejar: `cutoffDateForMonth`, `cycleKeyFor`, `CardCycleDates`,
`dueDateForCutoff`, `getCardCycleDates`, `frenchMonthlyPayment`,
`frenchTotalInterest`, y los imports/helpers privados que esas funciones
siguen usando (`_clampCutoffDay`, `_lastDayOfMonth`). Quitar el import de
`card_statement.dart` si ya no se usa en este archivo (no se usa).

En `test/domain/card_calculator_test.dart`, eliminar los `group(...)` que
testeaban las funciones borradas: `accrueCardCredit` (todo el grupo, con
sus 2 subgrupos de "does not close a cycle..." y "creates CardStatements"
y "defends against a duplicate statement id"), `applyRateChangeAt` (usaba
`accrueCardCredit` internamente — bórralo también, el reintento de
prorrateo al cambiar tasa se puede reimplementar sobre el motor nuevo en
una iteración futura, documentado como gap conocido), `registerCardMovement`,
`buildInstallmentMovements`, `registerCardCharge`, `getPayableSummary`,
`applying a payment to the latest unpaid statement`, `payment application
regression`, `deleteCardMovement with installments`. Deja intactos:
`cutoffDateForMonth`, `getCardCycleDates` (y su subgrupo `paymentDueDay`),
`cycleKeyFor`, el test suelto `toDateStr/parseDateStr round-trip`.

Agrega `getCardAvailableLimit` a `card_statement_engine.dart` (se movió
porque ahora depende de `recomputeCardBalance`, no de un `currentBalance`
mutado a mano en el mismo archivo — aunque técnicamente podría quedarse en
`card_calculator.dart` leyendo el campo, se mueve para que toda la API
pública de "consultar estado de una tarjeta" viva junta):

```dart
// en lib/domain/card_statement_engine.dart
double getCardAvailableLimit(CardCredit credit) =>
    math.max(0.0, credit.creditLimit - credit.currentBalance);
```

**3b. `lib/utils/credit_display_utils.dart`** — cambiar el import y la
implementación de `getNextDueDate`:

```dart
import '../domain/card_statement_engine.dart';
```
(reemplaza `import '../domain/card_calculator.dart';` si ya no se usa
nada más de ese archivo aquí — revisa `getCardCycleDates`: si se sigue
usando en este archivo para algo más, deja ambos imports).

```dart
DateTime? getNextDueDate(Credit credit) {
  if (credit is LoanCredit) {
    final unpaid = credit.installments.where((i) => !i.paid).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (unpaid.isEmpty) return null;
    return parseDateStr(unpaid.first.dueDate);
  }
  if (credit is CardCredit) {
    return getPayableSummary(credit).dueDate;
  }
  return null;
}
```

**3c. `lib/widgets/credit_detail/movements_tab.dart`** — reemplazar
`groupMovementsByCycle` por:

```dart
import '../../data/models/card_statement.dart';

/// Un extracto junto a los movimientos ligados a él.
class StatementGroup {
  final CardStatement statement;
  final List<CardMovement> movements;
  const StatementGroup(this.statement, this.movements);
}

/// Agrupa [movements] por el extracto (`statementId`) al que están
/// ligados, en el mismo orden que [statements] (que ya viene ordenada
/// cronológicamente — se crean en orden por closeCurrentCycleIfDue). Un
/// extracto sin movimientos propios (ej. uno recién abierto) igual aparece,
/// con lista vacía — nunca se oculta.
List<StatementGroup> groupMovementsByStatement(
    List<CardStatement> statements, List<CardMovement> movements) {
  return [
    for (final s in statements)
      StatementGroup(
        s,
        movements.where((m) => m.statementId == s.id).toList(),
      ),
  ];
}
```

En `MovementsTab.build`, reemplazar:
```dart
    final movements = credit.movements.reversed.toList();
    final groups = groupMovementsByCycle(movements, credit.cutoffDay);
    final currentCycleKey = cycleKeyFor(toDateStr(DateTime.now()), credit.cutoffDay);
    final groupKeys = groups.keys.toList();
    final defaultExpandedIndex = groupKeys.indexOf(currentCycleKey);
```
por:
```dart
    final sortedStatements = credit.statements.toList()
      ..sort((a, b) => b.cutoffDate.compareTo(a.cutoffDate)); // más reciente/abierto primero
    final groups = groupMovementsByStatement(sortedStatements, credit.movements);
    final defaultExpandedIndex = groups.indexWhere((g) => g.statement.status == CardStatementStatus.open);
```

Y el `for` del `ListView` que construye `_CycleGroup`, actualizar para
pasar `groups[i].movements` (ya en el orden correcto, sin `.reversed`
adicional — si se quiere más reciente primero DENTRO del extracto, aplicar
`.reversed` solo a `groups[i].movements` ahí) y
`cycleEndDate: groups[i].statement.cutoffDate`, manteniendo el resto de
`_CycleGroup`/`_CycleGroupState`/`_MovementTile` sin cambios (siguen
recibiendo `cutoffDay`, `allMovements: credit.movements`, etc.).

Quitar el import de `card_calculator.dart` de este archivo si
`cycleKeyFor` ya no se usa aquí (no se usa tras este cambio); el import de
`date_utils.dart` puede quedarse si `formatDate` sigue en uso más abajo en
`_MovementTile` (sí sigue).

**3d. `lib/widgets/wallet_card.dart` y
`lib/screens/credit_detail/credit_detail_screen.dart`** — cambiar el
import de `card_calculator.dart` a `card_statement_engine.dart` donde se
use `getPayableSummary`/`getCardAvailableLimit`/`getCardCycleDates`
(`getCardCycleDates` sigue en `card_calculator.dart`, así que ambos
imports conviven si el archivo usa las dos cosas). Ningún otro cambio de
lógica — las firmas de `PayableSummary`/`getPayableSummary` son
idénticas a la v1.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/credit_display_utils_test.dart test/widgets/credit_detail/movements_tab_grouping_test.dart test/domain/card_calculator_test.dart`
Expected: PASS en los tres.

- [ ] **Step 5: Run the full suite**

Run: `flutter pub run build_runner build --delete-conflicting-outputs && flutter test`
Expected: PASS en todo el proyecto. Si algo más referencia una función
borrada de `card_calculator.dart` (`dart analyze` lo señalará como error
de compilación antes de correr los tests), localízalo con
`grep -rn "accrueCardCredit\|registerCardMovement\|getCardRemainingBalance" lib/`
y actualízalo al equivalente de `card_statement_engine.dart` (mismo
patrón que los Steps anteriores).

- [ ] **Step 6: Commit**

```bash
git add lib/domain/card_calculator.dart lib/utils/credit_display_utils.dart lib/widgets/credit_detail/movements_tab.dart lib/widgets/wallet_card.dart lib/screens/credit_detail/credit_detail_screen.dart test/domain/card_calculator_test.dart test/utils/credit_display_utils_test.dart test/widgets/credit_detail/movements_tab_grouping_test.dart
git commit -m "refactor: retira el motor de extractos v1, UI usa statementId directo"
```

---

### Task 13: Backup — versión v5 y compatibilidad con nombres legados

**Files:**
- Modify: `lib/domain/export_import.dart`
- Test: `test/domain/export_import_test.dart`

**Interfaces:**
- Consumes: `CardCredit.fromJson` (Task 4, ya lee tanto `statements` como
  `closedStatements` legado).

- [ ] **Step 1: Write the failing test**

Añadir a `test/domain/export_import_test.dart`:

```dart
test('kBackupFormatVersion is 5', () {
  expect(kBackupFormatVersion, 5);
});

test('imports a v4 backup (field name "closedStatements", no '
    'installmentPurchases) without error — statements/installmentPurchases '
    'end up populated/empty correctly', () {
  final v4Json = jsonEncode({
    'format': kBackupFormatMarker,
    'version': 4,
    'exportedAt': '2026-01-01T00:00:00.000Z',
    'credits': [
      {
        'id': 'c1', 'type': 'card', 'name': 'Visa', 'lender': 'Bank',
        'currentBalance': 100000.0, 'cutoffDay': 15,
        'movements': [],
        'closedStatements': [
          {
            'id': 's1', 'creditId': 'c1', 'cutoffDate': '2026-01-15',
            'dueDate': '2026-02-05', 'closingBalance': 100000.0,
            'paidAmount': 0.0, 'status': 'closed', 'createdAt': '2026-01-15',
          }
        ],
      }
    ],
    'commercialQuotas': [],
  });

  final result = importStateFromJson(v4Json);

  final card = result.credits.first as CardCredit;
  expect(card.statements, hasLength(1));
  expect(card.statements.first.cutoffDate, '2026-01-15');
  expect(card.installmentPurchases, isEmpty);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/export_import_test.dart`
Expected: FAIL — `kBackupFormatVersion` vale 4.

- [ ] **Step 3: Write minimal implementation**

```dart
const int kBackupFormatVersion = 5;
```

En `_migrateBackup`, agregar antes del `break` final:
```dart
    if (version == 4) {
      // v4 -> v5: CardCredit renombró closedStatements -> statements y
      // agregó installmentPurchases. CardCredit.fromJson ya lee ambos
      // nombres (statements ?? closedStatements) y defaultea
      // installmentPurchases a [] si falta, así que no hay nada que
      // transformar en el payload — este branch solo documenta el bump.
      version = 5;
      continue;
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/export_import_test.dart`
Expected: PASS (todos)

- [ ] **Step 5: Run the full suite one last time**

Run: `flutter test`
Expected: PASS en todo el proyecto.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/export_import.dart test/domain/export_import_test.dart
git commit -m "feat: sube versión de backup a v5 (statements/installmentPurchases)"
```

---

## Self-Review

**1. Spec coverage:**
- Extracto abierto siempre existe → Task 5 (`ensureOpenStatement`) + Task
  11 (`addCredit` lo crea de inmediato). ✓
- `InstallmentPurchase`, cuota 1 inmediata + auto-facturado futuro → Tasks
  1, 7, 6. ✓
- `CardMovement` ligado por `statementId` → Task 2, 3. ✓
- `totalAmount` derivado, nunca congelado → `computeStatementTotal`
  (Task 5), usado en absolutamente todo lugar que antes leía
  `closingBalance`. ✓
- Pago FIFO + sobrante al abierto → Task 8. ✓
- `currentBalance` como caché recalculada, una sola función autorizada →
  Task 8 (`recomputeCardBalance`), cableada en Task 11 tras cada mutación. ✓
- Migración best-effort de datos legados → Task 10. ✓
- UI (movements_tab, wallet_card, credit_detail_screen) → Task 12. ✓
- Backup v4→v5 → Task 13. ✓

**2. Placeholder scan:** sin TBD/TODO; cada paso de código tiene
implementación completa y real.

**3. Type consistency:** `CardStatement`, `InstallmentPurchase`,
`PayableSummary`, `StatementGroup`, `computeStatementTotal`,
`ensureOpenStatement`, `closeCurrentCycleIfDue`, `registerCardCharge`,
`registerInstallmentPurchase`, `registerCardPayment`,
`recomputeCardBalance`, `getPayableSummary`, `deleteCardMovement`,
`migrateLegacyCardData`, `groupMovementsByStatement` se nombran y firman
igual en toda tarea que los consume.

**4. Review Focus:**
- Extracto abierto al crear tarjeta → test en Task 11.
- Sobrepago con sobrante al extracto abierto → test en Task 8.
- Compra a plazos el mismo día del corte → cubierto (test añadido
  directamente en Task 7).
- Migración de compras a plazos ambiguas → cubierto explícitamente por
  Task 10's decisión documentada (YAGNI: no se reconstruyen
  `InstallmentPurchase`, se dejan como cargos sueltos) — no requiere test
  adicional porque no hay comportamiento nuevo que verificar (es la
  ausencia deliberada de una funcionalidad).
- Borrar la cuota más reciente decrementa `installmentsBilled` → test ya
  en Task 9. ✓

Todos los puntos del Review Focus quedan cubiertos.

---

Plan completo y auto-revisado. Guardado en
`docs/superpowers/plans/2026-10-11-card-statements-v2-rewrite-implementation.md`.
