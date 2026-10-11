# Extractos de tarjeta de crédito — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cada extracto (ciclo de facturación) de una tarjeta de crédito se
vuelve una entidad con su propio saldo y fecha límite; las compras a N
cuotas reparten el monto entre N extractos consecutivos; el bug de
inconsistencia en el día de corte queda unificado.

**Architecture:** Nueva tabla `CardStatements` (solo extractos ya
**cerrados**, histórico). El extracto abierto actual nunca se persiste — se
deriva on-the-fly. `CardMovement` gana `installmentIndex`/`statementCutoff`
para que una cuota de una compra a plazos sepa a qué extracto futuro
pertenece desde que se registra. `accrueCardCredit` (el único punto que ya
"cierra" ciclos) crea el `CardStatement` correspondiente cada vez que cruza
un corte.

**Tech Stack:** Flutter, Drift (SQLite), Riverpod, `package:flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-11-card-statements-design.md`

## Global Constraints

- `schemaVersion` de Drift sube de 14 a 15 (`lib/data/db/database.dart`).
- `kBackupFormatVersion` de `lib/domain/export_import.dart` sube de 3 a 4.
- Toda tabla nueva se añade a `clearAllData` y `replaceAllData` en
  `lib/data/db/database.dart`.
- Persistencia relacional (tabla separada + replace-all en `upsertCredit`),
  igual patrón que `CardMovements` hoy — nunca JSON embebido.
- Redondeo de cuotas a 2 decimales; el remanente va en la última cuota para
  que la suma exacta coincida con el monto original.
- No se reconstruyen extractos retroactivos para datos ya existentes antes
  de esta migración — solo aplica hacia adelante.
- Nombre del paquete del proyecto es `krezium` (imports de test usan
  `package:krezium/...`).

## Review Focus

- Compra a 1 cuota de monto con decimales no exactos (ej. $100.005): la
  suma de las N cuotas debe ser exactamente igual al monto original — sin
  perder ni duplicar centavos.
- Movimiento/compra registrado exactamente en el día de corte: debe
  agruparse de forma consistente (un solo criterio en todo el código, no
  dos opuestos).
- Restaurar un backup antiguo (formato v3, sin `closedStatements` ni
  `installmentIndex`/`statementCutoff`): debe importar sin error y arrancar
  con 0 extractos cerrados.
- Eliminar un movimiento individual que es una cuota de una compra a
  plazos (`deleteMovement`): debe borrar solo esa cuota, sin afectar las
  demás cuotas de la misma compra.
- `accrueCardCredit` llamado dos veces seguidas sin que haya pasado un
  nuevo ciclo (ej. dos arranques de la app el mismo día): no debe crear
  `CardStatement`s duplicados.

---

### Task 1: Modelo `CardStatement`

**Files:**
- Create: `lib/data/models/card_statement.dart`
- Test: `test/data/models/card_statement_test.dart`

**Interfaces:**
- Produces: `class CardStatement` con campos `id, creditId, cutoffDate,
  dueDate, closingBalance, paidAmount, status, createdAt` (todos
  `String`/`double` excepto `closingBalance`/`paidAmount` que son `double`),
  `toJson()`, `factory CardStatement.fromJson(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/card_statement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';

void main() {
  test('toJson/fromJson round-trip preserves all fields', () {
    final statement = CardStatement(
      id: 'card1-2026-01-15',
      creditId: 'card1',
      cutoffDate: '2026-01-15',
      dueDate: '2026-02-05',
      closingBalance: 150000.50,
      paidAmount: 50000,
      status: 'closed',
      createdAt: '2026-01-15',
    );

    final decoded = CardStatement.fromJson(statement.toJson());

    expect(decoded.id, 'card1-2026-01-15');
    expect(decoded.creditId, 'card1');
    expect(decoded.cutoffDate, '2026-01-15');
    expect(decoded.dueDate, '2026-02-05');
    expect(decoded.closingBalance, 150000.50);
    expect(decoded.paidAmount, 50000);
    expect(decoded.status, 'closed');
    expect(decoded.createdAt, '2026-01-15');
  });

  test('fromJson defaults paidAmount to 0 and status to closed when absent', () {
    final decoded = CardStatement.fromJson({
      'id': 'x',
      'creditId': 'card1',
      'cutoffDate': '2026-01-15',
      'dueDate': '2026-02-05',
      'closingBalance': 1000.0,
      'createdAt': '2026-01-15',
    });

    expect(decoded.paidAmount, 0);
    expect(decoded.status, 'closed');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/card_statement_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'krezium' in... card_statement.dart` (archivo no existe).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/data/models/card_statement.dart

/// Un extracto de tarjeta ya CERRADO (histórico). El extracto actualmente
/// abierto nunca tiene una fila de este tipo — se calcula on-the-fly desde
/// `CardCredit.movements` (ver `getCardCycleDates` en card_calculator.dart).
/// Creado una sola vez por `accrueCardCredit` cuando detecta que un ciclo
/// de facturación cruzó su fecha de corte.
class CardStatementStatus {
  static const closed = 'closed';
  static const paid = 'paid';
}

class CardStatement {
  final String id;
  final String creditId;

  /// "YYYY-MM-DD" — fecha de corte que cerró este extracto.
  final String cutoffDate;

  /// "YYYY-MM-DD" — fecha límite de pago de este extracto.
  final String dueDate;

  /// Saldo total a pagar de este extracto, fijado al momento de cerrar.
  final double closingBalance;

  /// Monto abonado a este extracto específico.
  final double paidAmount;

  /// Uno de [CardStatementStatus].
  final String status;

  /// "YYYY-MM-DD" — fecha en que se generó este registro (debug/orden).
  final String createdAt;

  const CardStatement({
    required this.id,
    required this.creditId,
    required this.cutoffDate,
    required this.dueDate,
    required this.closingBalance,
    this.paidAmount = 0,
    this.status = CardStatementStatus.closed,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'creditId': creditId,
        'cutoffDate': cutoffDate,
        'dueDate': dueDate,
        'closingBalance': closingBalance,
        'paidAmount': paidAmount,
        'status': status,
        'createdAt': createdAt,
      };

  factory CardStatement.fromJson(Map<String, dynamic> json) => CardStatement(
        id: json['id'] as String,
        creditId: json['creditId'] as String,
        cutoffDate: json['cutoffDate'] as String,
        dueDate: json['dueDate'] as String,
        closingBalance: (json['closingBalance'] as num).toDouble(),
        paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? CardStatementStatus.closed,
        createdAt: json['createdAt'] as String,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/card_statement_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/card_statement.dart test/data/models/card_statement_test.dart
git commit -m "feat: agrega modelo CardStatement (extracto cerrado de tarjeta)"
```

---

### Task 2: Campos `installmentIndex`/`statementCutoff` en `CardMovement`

**Files:**
- Modify: `lib/data/models/card_movement.dart`
- Test: `test/data/models/card_movement_test.dart` (crear si no existe)

**Interfaces:**
- Consumes: nada de tareas previas.
- Produces: `CardMovement.installmentIndex` (`int?`),
  `CardMovement.statementCutoff` (`String?`) — ambos en constructor,
  `toJson`, `fromJson`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/card_movement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';

void main() {
  test('toJson/fromJson round-trips installmentIndex and statementCutoff', () {
    final mv = CardMovement(
      date: '2026-01-10',
      type: CardMovementType.charge,
      amount: 50000,
      chargeInstallments: 3,
      installmentIndex: 2,
      statementCutoff: '2026-02-15',
    );

    final decoded = CardMovement.fromJson(mv.toJson());

    expect(decoded.chargeInstallments, 3);
    expect(decoded.installmentIndex, 2);
    expect(decoded.statementCutoff, '2026-02-15');
  });

  test('installmentIndex and statementCutoff default to null', () {
    final decoded = CardMovement.fromJson({
      'date': '2026-01-10',
      'type': CardMovementType.payment,
      'amount': 10000.0,
    });

    expect(decoded.installmentIndex, isNull);
    expect(decoded.statementCutoff, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/card_movement_test.dart`
Expected: FAIL — `The named parameter 'installmentIndex' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

En `lib/data/models/card_movement.dart`, agregar campos justo después de
`chargeMonthlyRate` (línea 39):

```dart
  /// Para charges: tasa mensual override (null = usar la de la tarjeta)
  final double? chargeMonthlyRate;

  /// Posición de esta cuota dentro de su compra a plazos (1-based).
  /// Null para movimientos que no son cuota de una compra (pago único,
  /// pago, interés, cuota de manejo, avance).
  final int? installmentIndex;

  /// "YYYY-MM-DD" — fecha de corte del extracto al que esta cuota
  /// específica fue asignada al registrarse. Null = se agrupa por el
  /// criterio normal de fecha+corte (ver `cycleKeyFor` en
  /// card_calculator.dart), usado por cargos de 1 sola cuota, pagos,
  /// intereses, cuotas de manejo y avances.
  final String? statementCutoff;
```

Actualizar el constructor (agregar los 2 parámetros), `toJson` y `fromJson`:

```dart
  CardMovement({
    required this.date,
    required this.type,
    required this.amount,
    this.note = '',
    this.advanceInstallments,
    this.advanceInterestRate,
    this.advanceInterestRateType,
    this.advanceCommission,
    this.advanceFirstPaymentDate,
    this.advanceDestination,
    this.categoria,
    this.chargeInstallments,
    this.chargeMonthlyRate,
    this.installmentIndex,
    this.statementCutoff,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'type': type,
        'amount': amount,
        'note': note,
        'advanceInstallments': advanceInstallments,
        'advanceInterestRate': advanceInterestRate,
        'advanceInterestRateType': advanceInterestRateType,
        'advanceCommission': advanceCommission,
        'advanceFirstPaymentDate': advanceFirstPaymentDate,
        'advanceDestination': advanceDestination,
        'categoria': categoria,
        'chargeInstallments': chargeInstallments,
        'chargeMonthlyRate': chargeMonthlyRate,
        'installmentIndex': installmentIndex,
        'statementCutoff': statementCutoff,
      };

  factory CardMovement.fromJson(Map<String, dynamic> json) => CardMovement(
        date: json['date'] as String,
        type: json['type'] as String,
        amount: (json['amount'] as num).toDouble(),
        note: json['note'] as String? ?? '',
        advanceInstallments: json['advanceInstallments'] as int?,
        advanceInterestRate: (json['advanceInterestRate'] as num?)?.toDouble(),
        advanceInterestRateType: json['advanceInterestRateType'] as String?,
        advanceCommission: (json['advanceCommission'] as num?)?.toDouble(),
        advanceFirstPaymentDate: json['advanceFirstPaymentDate'] as String?,
        advanceDestination: json['advanceDestination'] as String?,
        categoria: json['categoria'] as String?,
        chargeInstallments: json['chargeInstallments'] as int?,
        chargeMonthlyRate: (json['chargeMonthlyRate'] as num?)?.toDouble(),
        installmentIndex: json['installmentIndex'] as int?,
        statementCutoff: json['statementCutoff'] as String?,
      );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/card_movement_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/card_movement.dart test/data/models/card_movement_test.dart
git commit -m "feat: agrega installmentIndex/statementCutoff a CardMovement"
```

---

### Task 3: Campo `closedStatements` en `CardCredit`

**Files:**
- Modify: `lib/data/models/credit.dart`
- Test: `test/data/models/credit_test.dart` (crear si no existe; si existe, añadir al final)

**Interfaces:**
- Consumes: `CardStatement` (Task 1).
- Produces: `CardCredit.closedStatements` (`List<CardStatement>`, default
  `[]`), presente en constructor/`toJson`/`fromJson`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/credit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';

void main() {
  test('CardCredit.closedStatements defaults to empty list', () {
    final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank');
    expect(card.closedStatements, isEmpty);
  });

  test('CardCredit toJson/fromJson round-trips closedStatements', () {
    final card = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      closedStatements: [
        const CardStatement(
          id: 'c1-2026-01-15',
          creditId: 'c1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          createdAt: '2026-01-15',
        ),
      ],
    );

    final decoded = CardCredit.fromJson(card.toJson());

    expect(decoded.closedStatements, hasLength(1));
    expect(decoded.closedStatements.first.cutoffDate, '2026-01-15');
  });

  test('CardCredit.fromJson defaults closedStatements to empty when absent '
      '(backup v3 compat)', () {
    final decoded = CardCredit.fromJson({
      'id': 'c1',
      'name': 'Test',
      'lender': 'Bank',
    });
    expect(decoded.closedStatements, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/credit_test.dart`
Expected: FAIL — `The named parameter 'closedStatements' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

En `lib/data/models/credit.dart`, agregar import al inicio del archivo:

```dart
import 'card_statement.dart';
```

En la clase `CardCredit` (línea ~213, tras `oneInstallmentInterestPolicy`),
agregar el campo:

```dart
  /// Extractos ya cerrados (histórico). El extracto actualmente abierto no
  /// está aquí — se calcula on-the-fly. Ver card_statement.dart.
  List<CardStatement> closedStatements;
```

En el constructor, agregar el parámetro y la inicialización:

```dart
  CardCredit({
    required super.id,
    required super.name,
    required super.lender,
    super.color,
    super.notes,
    super.cardDesign,
    super.notificationDaysBefore,
    this.creditLimit = 0,
    this.currentBalance = 0,
    this.cutoffDay = 1,
    this.paymentDueOffsetDays = 20,
    this.paymentDueDay = 0,
    this.interestRate = 0,
    this.interestRateType = InterestRateType.effectiveAnnual,
    this.managementFee = 0,
    this.managementFeeFrequency = ManagementFeeFrequency.monthly,
    this.cycleCount = 0,
    this.lastAccrualCutoff,
    this.quotaId,
    this.oneInstallmentInterestPolicy,
    List<CardMovement>? movements,
    List<CardStatement>? closedStatements,
  })  : movements = movements ?? [],
        closedStatements = closedStatements ?? [],
        super(type: CreditType.card);
```

En `toJson`, agregar la línea:

```dart
        'movements': movements.map((m) => m.toJson()).toList(),
        'closedStatements': closedStatements.map((s) => s.toJson()).toList(),
      };
```

En `fromJson`, agregar:

```dart
        movements: (json['movements'] as List<dynamic>? ?? [])
            .map((e) => CardMovement.fromJson(e as Map<String, dynamic>))
            .toList(),
        closedStatements: (json['closedStatements'] as List<dynamic>? ?? [])
            .map((e) => CardStatement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/credit_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/credit.dart test/data/models/credit_test.dart
git commit -m "feat: agrega closedStatements a CardCredit"
```

---

### Task 4: Persistencia — tabla `CardStatements`, columnas nuevas en `CardMovements`, schema v15

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`
- Test: `test/data/card_statements_db_test.dart`

**Interfaces:**
- Consumes: `CardStatement` (Task 1), `CardMovement.installmentIndex`/
  `statementCutoff` (Task 2), `CardCredit.closedStatements` (Task 3).
- Produces: `AppDatabase` persiste/carga `closedStatements` y los 2 campos
  nuevos de movimiento vía `upsertCredit`/`loadAllCredits`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/card_statements_db_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('round-trips a card credit with closedStatements and installment '
      'movement fields', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bancolombia',
      cutoffDay: 15,
      currentBalance: 150000,
      closedStatements: const [
        CardStatement(
          id: 'card1-2026-01-15',
          creditId: 'card1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          paidAmount: 0,
          status: 'closed',
          createdAt: '2026-01-15',
        ),
      ],
      movements: [
        CardMovement(
          date: '2026-01-10',
          type: CardMovementType.charge,
          amount: 50000,
          chargeInstallments: 3,
          installmentIndex: 1,
          statementCutoff: '2026-01-15',
        ),
      ],
    );

    await db.upsertCredit(card);
    final all = await db.loadAllCredits();

    expect(all, hasLength(1));
    final loaded = all.first as CardCredit;
    expect(loaded.closedStatements, hasLength(1));
    expect(loaded.closedStatements.first.closingBalance, 100000);
    expect(loaded.movements, hasLength(1));
    expect(loaded.movements.first.installmentIndex, 1);
    expect(loaded.movements.first.statementCutoff, '2026-01-15');
  });

  test('clearAllData removes closedStatements', () async {
    final card = CardCredit(
      id: 'card1',
      name: 'Visa',
      lender: 'Bancolombia',
      closedStatements: const [
        CardStatement(
          id: 'card1-2026-01-15',
          creditId: 'card1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          createdAt: '2026-01-15',
        ),
      ],
    );
    await db.upsertCredit(card);
    await db.clearAllData();
    final all = await db.loadAllCredits();
    expect(all, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/card_statements_db_test.dart`
Expected: FAIL — `The named parameter 'closedStatements' isn't defined` (CardCredit aún no tiene el campo persistido, o `installmentIndex`/`statementCutoff` no existen en `CardMovementsCompanion`).

- [ ] **Step 3: Write minimal implementation**

**3a. `lib/data/db/tables.dart`** — agregar 2 columnas a `CardMovements`
(tras `categoria`, línea 173):

```dart
  /// Categoría del movimiento — null para movimientos anteriores a v12.
  /// Valores sugeridos: 'alimentacion' | 'transporte' | 'salud' | 'ropa' |
  /// 'entretenimiento' | 'servicios' | 'viajes' | 'otro'.
  TextColumn get categoria => text().nullable()();

  /// Posición de esta cuota dentro de su compra a plazos (1-based). Null
  /// para movimientos que no son cuota de una compra.
  IntColumn get installmentIndex => integer().nullable()();

  /// "YYYY-MM-DD" — corte del extracto al que esta cuota fue asignada al
  /// registrarse. Null = se agrupa por el criterio normal de fecha+corte.
  TextColumn get statementCutoff => text().nullable()();
}
```

Y agregar la tabla nueva al final del archivo:

```dart
/// Un extracto de tarjeta ya cerrado (histórico). Ver
/// lib/data/models/card_statement.dart.
@DataClassName('CardStatementRow')
class CardStatements extends Table {
  TextColumn get id => text()();
  TextColumn get creditId =>
      text().references(Credits, #id, onDelete: KeyAction.cascade)();
  TextColumn get cutoffDate => text()(); // YYYY-MM-DD
  TextColumn get dueDate => text()(); // YYYY-MM-DD
  RealColumn get closingBalance => real()();
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('closed'))();
  TextColumn get createdAt => text()(); // YYYY-MM-DD

  @override
  Set<Column> get primaryKey => {id};
}
```

**3b. `lib/data/db/database.dart`**:

Import nuevo al inicio:

```dart
import '../models/card_statement.dart';
```

Agregar `CardStatements` a la lista de tablas (línea 34-38):

```dart
@DriftDatabase(tables: [
  Credits, Installments, CardMovements, CardStatements, LoanAbonos,
  CommercialQuotas, PagosRealizados,
  FinanceAccounts, FinanceCategories, FinanceTransactions, FinanceBudgets,
  FinancePlaces, FinanceTemplates,
])
```

Subir `schemaVersion` (línea 46):

```dart
  int get schemaVersion => 15;
```

Agregar el bloque de migración al final de `onUpgrade`, después del bloque
`if (from < 12) { ... }` existente (línea ~157):

```dart
          if (from < 15) {
            await m.createTable(cardStatements);
            await m.addColumn(cardMovements, cardMovements.installmentIndex);
            await m.addColumn(cardMovements, cardMovements.statementCutoff);
          }
```

Modificar `_cardFromRow` (línea 198) para aceptar `closedStatements`:

```dart
  CardCredit _cardFromRow(
      CreditRow row, List<CardMovement> movements,
      List<CardStatement> closedStatements) {
    return CardCredit(
      id: row.id,
      name: row.name,
      lender: row.lender,
      color: row.color,
      notes: row.notes,
      creditLimit: row.creditLimit ?? 0,
      currentBalance: row.currentBalance ?? 0,
      cutoffDay: row.cutoffDay ?? 1,
      paymentDueOffsetDays: row.paymentDueOffsetDays ?? 20,
      interestRate: row.interestRate ?? 0,
      interestRateType:
          row.interestRateType ?? InterestRateType.effectiveAnnual,
      managementFee: row.managementFee ?? 0,
      managementFeeFrequency:
          row.managementFeeFrequency ?? ManagementFeeFrequency.monthly,
      cycleCount: row.cycleCount ?? 0,
      lastAccrualCutoff: row.lastAccrualCutoff,
      quotaId: row.quotaId,
      cardDesign: row.cardDesign,
      paymentDueDay: row.paymentDueDay,
      oneInstallmentInterestPolicy: row.oneInstallmentInterestPolicy,
      notificationDaysBefore: row.notificationDaysBefore,
      movements: movements,
      closedStatements: closedStatements,
    );
  }
```

Modificar `loadAllCredits` (línea 285-356) — en la rama `card`, cargar los
extractos y pasarlos a `_cardFromRow`:

```dart
      if (row.type == CreditType.card) {
        final movementRows = await (select(cardMovements)
              ..where((m) => m.creditId.equals(row.id))
              ..orderBy([(m) => OrderingTerm.asc(m.rowId)]))
            .get();
        final statementRows = await (select(cardStatements)
              ..where((s) => s.creditId.equals(row.id))
              ..orderBy([(s) => OrderingTerm.asc(s.cutoffDate)]))
            .get();
        result.add(_cardFromRow(
          row,
          movementRows
              .map((m) => CardMovement(
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
                    installmentIndex: m.installmentIndex,
                    statementCutoff: m.statementCutoff,
                  ))
              .toList(),
          statementRows
              .map((s) => CardStatement(
                    id: s.id,
                    creditId: s.creditId,
                    cutoffDate: s.cutoffDate,
                    dueDate: s.dueDate,
                    closingBalance: s.closingBalance,
                    paidAmount: s.paidAmount,
                    status: s.status,
                    createdAt: s.createdAt,
                  ))
              .toList(),
        ));
      } else {
```

Modificar `upsertCredit` (línea 446-507) — en la rama `CardCredit`, agregar
el replace-all de `cardStatements` y los 2 campos nuevos en el insert de
movimientos:

```dart
      } else if (credit is CardCredit) {
        await (delete(cardMovements)
              ..where((m) => m.creditId.equals(credit.id)))
            .go();
        for (final mv in credit.movements) {
          await into(cardMovements).insert(CardMovementsCompanion.insert(
            creditId: credit.id,
            date: mv.date,
            type: mv.type,
            amount: mv.amount,
            note: Value(mv.note),
            advanceInstallments: Value(mv.advanceInstallments),
            advanceInterestRate: Value(mv.advanceInterestRate),
            advanceInterestRateType: Value(mv.advanceInterestRateType),
            advanceCommission: Value(mv.advanceCommission),
            advanceFirstPaymentDate: Value(mv.advanceFirstPaymentDate),
            advanceDestination: Value(mv.advanceDestination),
            categoria: Value(mv.categoria),
            installmentIndex: Value(mv.installmentIndex),
            statementCutoff: Value(mv.statementCutoff),
          ));
        }
        await (delete(cardStatements)
              ..where((s) => s.creditId.equals(credit.id)))
            .go();
        for (final s in credit.closedStatements) {
          await into(cardStatements).insert(CardStatementsCompanion.insert(
            id: s.id,
            creditId: credit.id,
            cutoffDate: s.cutoffDate,
            dueDate: s.dueDate,
            closingBalance: s.closingBalance,
            paidAmount: Value(s.paidAmount),
            status: Value(s.status),
            createdAt: s.createdAt,
          ));
        }
      }
```

Agregar `delete(cardStatements)` a `clearAllData` (línea 651-660) y a
`replaceAllData` (línea 670-697), justo después de `delete(cardMovements)`
en ambos:

```dart
  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(installments).go();
      await delete(cardMovements).go();
      await delete(cardStatements).go();
      await delete(loanAbonos).go();
      await delete(pagosRealizados).go();
      await delete(credits).go();
      await delete(commercialQuotas).go();
    });
  }
```

```dart
  Future<void> replaceAllData(
      List<Credit> newCredits, List<CommercialQuota> newQuotas) async {
    final quotaIds = newQuotas.map((q) => q.id).toSet();
    await transaction(() async {
      await delete(installments).go();
      await delete(cardMovements).go();
      await delete(cardStatements).go();
      await delete(loanAbonos).go();
      await delete(pagosRealizados).go();
      await delete(credits).go();
      await delete(commercialQuotas).go();
      for (final q in newQuotas) {
        await upsertCommercialQuota(q);
      }
      for (final c in newCredits) {
        if (c is CardCredit && c.quotaId != null && !quotaIds.contains(c.quotaId)) {
          c.quotaId = null;
        } else if (c is LoanCredit && c.quotaId != null && !quotaIds.contains(c.quotaId)) {
          c.quotaId = null;
        }
        await upsertCredit(c);
      }
    });
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter pub run build_runner build --delete-conflicting-outputs && flutter test test/data/card_statements_db_test.dart`
Expected: PASS (2/2). (El `build_runner` regenera `database.g.dart` con las
columnas/tabla nuevas — necesario tras cualquier cambio a `tables.dart`.)

- [ ] **Step 5: Run full existing DB test suite to check no regression**

Run: `flutter test test/data/`
Expected: PASS — todos los tests existentes de `database_test.dart` y
`finance_tables_migration_test.dart` siguen pasando.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/card_statements_db_test.dart
git commit -m "feat: persiste CardStatements y campos de cuota en CardMovements (schema v15)"
```

---

### Task 5: Dominio — reparto de cuotas, saldo exigible, fix del día de corte, cierre de extracto

**Files:**
- Modify: `lib/domain/card_calculator.dart`
- Test: `test/domain/card_calculator_test.dart` (añadir al final)

**Interfaces:**
- Consumes: `CardStatement` (Task 1), `CardMovement.installmentIndex`/
  `statementCutoff` (Task 2), `CardCredit.closedStatements` (Task 3).
- Produces:
  - `String cycleKeyFor(String movementDate, int cutoffDay)` — reemplaza la
    lógica duplicada/inconsistente de `movements_tab.dart`.
  - `List<CardMovement> buildInstallmentMovements({required CardCredit
    credit, required double totalAmount, required int installments,
    String note = '', String? categoria, DateTime? refDate})`.
  - `void registerCardCharge(CardCredit credit, double totalAmount,
    {String note = '', String? categoria, int installments = 1, DateTime?
    refDate})`.
  - `class PayableSummary { final double exigible; final double
    pendienteFacturar; final DateTime? dueDate; }`.
  - `PayableSummary getPayableSummary(CardCredit credit)`.
  - `accrueCardCredit` ahora también agrega entradas a
    `credit.closedStatements` cada vez que cruza un corte.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir al final de test/domain/card_calculator_test.dart

group('cycleKeyFor', () {
  test('a movement dated exactly on the cutoff day belongs to the cycle '
      'that CLOSES that day (not the one that opens)', () {
    // Regression test for the bug reported by the user: a charge made on
    // the cutoff day was inconsistently assigned to next month's cycle in
    // movements_tab.dart while card_calculator.dart's getCardCycleDates
    // treated it as part of the cycle closing that same day.
    expect(cycleKeyFor('2026-01-15', 15), '2026-01-15');
  });

  test('a movement dated the day before cutoff belongs to this month\'s '
      'closing cycle', () {
    expect(cycleKeyFor('2026-01-14', 15), '2026-01-15');
  });

  test('a movement dated the day after cutoff belongs to next month\'s '
      'closing cycle', () {
    expect(cycleKeyFor('2026-01-16', 15), '2026-02-15');
  });
});

group('buildInstallmentMovements', () {
  test('splits total amount into N installments, each on a consecutive '
      'future statement', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final refDate = DateTime(2026, 1, 10); // antes del corte del 15

    final movements = buildInstallmentMovements(
      credit: credit,
      totalAmount: 300000,
      installments: 3,
      note: 'Compra TV',
      refDate: refDate,
    );

    expect(movements, hasLength(3));
    expect(movements[0].installmentIndex, 1);
    expect(movements[0].chargeInstallments, 3);
    expect(movements[0].statementCutoff, '2026-01-15');
    expect(movements[1].statementCutoff, '2026-02-15');
    expect(movements[2].statementCutoff, '2026-03-15');
    // Monto exacto repartido: cada cuota $100,000.
    expect(movements[0].amount, 100000);
    expect(movements[1].amount, 100000);
    expect(movements[2].amount, 100000);
  });

  test('rounding remainder goes entirely on the last installment — sum '
      'equals the exact original amount', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    final movements = buildInstallmentMovements(
      credit: credit,
      totalAmount: 100.01,
      installments: 3,
      refDate: DateTime(2026, 1, 10),
    );

    final sum = movements.fold<double>(0, (s, m) => s + m.amount);
    expect(sum, closeTo(100.01, 0.001));
    expect(movements[0].amount, 33.34);
    expect(movements[1].amount, 33.34);
    expect(movements[2].amount, 33.33);
  });
});

group('registerCardCharge', () {
  test('1 installment registers a single movement with no statementCutoff '
      '(same behavior as before)', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    registerCardCharge(credit, 50000, note: 'Café', installments: 1,
        refDate: DateTime(2026, 1, 10));

    expect(credit.movements, hasLength(1));
    expect(credit.movements.first.statementCutoff, isNull);
    expect(credit.movements.first.chargeInstallments, isNull);
    expect(credit.currentBalance, 50000);
  });

  test('N installments registers N movements and adds the full amount to '
      'currentBalance immediately', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    registerCardCharge(credit, 300000, note: 'TV', installments: 3,
        refDate: DateTime(2026, 1, 10));

    expect(credit.movements, hasLength(3));
    expect(credit.currentBalance, 300000);
  });
});

group('getPayableSummary', () {
  test('exigible = sum of unpaid closed statements; pendienteFacturar = '
      'currentBalance minus that', () {
    final credit = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      currentBalance: 180000,
      closedStatements: const [
        CardStatement(
          id: 's1',
          creditId: 'c1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          paidAmount: 0,
          status: 'closed',
          createdAt: '2026-01-15',
        ),
      ],
    );

    final summary = getPayableSummary(credit);

    expect(summary.exigible, 100000);
    expect(summary.pendienteFacturar, 80000);
    expect(summary.dueDate, parseDateStr('2026-02-05'));
  });

  test('a fully paid statement does not count toward exigible', () {
    final credit = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      currentBalance: 80000,
      closedStatements: const [
        CardStatement(
          id: 's1',
          creditId: 'c1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          paidAmount: 100000,
          status: 'paid',
          createdAt: '2026-01-15',
        ),
      ],
    );

    final summary = getPayableSummary(credit);

    expect(summary.exigible, 0);
    expect(summary.dueDate, isNull);
  });
});

group('accrueCardCredit creates CardStatements', () {
  test('closing a cycle with a charge inside it creates one CardStatement '
      'with the correct closingBalance and dueDate', () {
    final credit = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      cutoffDay: 15,
      paymentDueOffsetDays: 20,
      lastAccrualCutoff: '2026-01-15',
    );
    credit.movements.add(CardMovement(
      date: '2026-01-20',
      type: CardMovementType.charge,
      amount: 50000,
    ));

    accrueCardCredit(credit, DateTime(2026, 2, 16));

    expect(credit.closedStatements, hasLength(1));
    final s = credit.closedStatements.first;
    expect(s.cutoffDate, '2026-02-15');
    expect(s.closingBalance, 50000);
    expect(s.dueDate, '2026-03-07'); // 2026-02-15 + 20 días
  });

  test('calling accrueCardCredit twice without a new cycle elapsing does '
      'not create duplicate CardStatements', () {
    final credit = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      cutoffDay: 15,
      lastAccrualCutoff: '2026-01-15',
    );
    accrueCardCredit(credit, DateTime(2026, 2, 16));
    final countAfterFirst = credit.closedStatements.length;
    accrueCardCredit(credit, DateTime(2026, 2, 16));
    expect(credit.closedStatements.length, countAfterFirst);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/card_calculator_test.dart`
Expected: FAIL — `The function 'cycleKeyFor' isn't defined`,
`The function 'buildInstallmentMovements' isn't defined`, etc.

- [ ] **Step 3: Write minimal implementation**

En `lib/domain/card_calculator.dart`, agregar import:

```dart
import '../data/models/card_statement.dart';
```

Agregar `cycleKeyFor` (función pública, justo después de
`cutoffDateForMonth`, línea ~26):

```dart
/// Returns the closing cutoff date ("YYYY-MM-DD") of the billing cycle that
/// contains [movementDate], given [cutoffDay]. The cutoff day belongs to
/// the cycle that CLOSES that day (matches getCardCycleDates' documented
/// semantics) — a movement dated exactly on the cutoff day is part of the
/// statement generated that day, not the one that just opened.
///
/// Single source of truth for this grouping: movements_tab.dart and
/// accrueCardCredit both use this instead of each keeping their own
/// (previously inconsistent) copy.
String cycleKeyFor(String movementDate, int cutoffDay) {
  if (movementDate.length < 10) return movementDate;
  final d = DateTime.tryParse(movementDate);
  if (d == null) return movementDate;
  final clampedCutoff = _clampCutoffDay(cutoffDay).clamp(1, 28);
  DateTime cycleEnd;
  if (d.day <= clampedCutoff) {
    cycleEnd = DateTime(d.year, d.month, clampedCutoff);
  } else {
    final nextMonth = d.month == 12 ? 1 : d.month + 1;
    final nextYear = d.month == 12 ? d.year + 1 : d.year;
    cycleEnd = DateTime(nextYear, nextMonth, clampedCutoff);
  }
  return toDateStr(cycleEnd);
}
```

Refactorizar `getCardCycleDates` para extraer `_dueDateForCutoff` (evita
duplicar la fórmula de fecha límite entre aquí y el cierre de extractos):

```dart
DateTime _dueDateForCutoff(CardCredit credit, DateTime cutoff) {
  if (credit.paymentDueDay > 0) {
    final dueMonth = DateTime(cutoff.year, cutoff.month + 1, 1);
    final lastDayOfDueMonth = _lastDayOfMonth(dueMonth.year, dueMonth.month);
    return DateTime(
      dueMonth.year,
      dueMonth.month,
      math.min(credit.paymentDueDay, lastDayOfDueMonth),
    );
  }
  return cutoff.add(Duration(days: credit.paymentDueOffsetDays));
}

/// Port of getCardCycleDates (app.js ~L678-697).
CardCycleDates getCardCycleDates(CardCredit credit, [DateTime? refDate]) {
  final ref = refDate ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final cutoffDay = _clampCutoffDay(credit.cutoffDay);

  var lastCutoff = cutoffDateForMonth(today.year, today.month, cutoffDay);
  if (lastCutoff.isAfter(today)) {
    final prevMonthRef = DateTime(today.year, today.month - 1, 1);
    lastCutoff = cutoffDateForMonth(
        prevMonthRef.year, prevMonthRef.month, cutoffDay);
  }
  final nextMonthRef = DateTime(lastCutoff.year, lastCutoff.month + 1, 1);
  final nextCutoff =
      cutoffDateForMonth(nextMonthRef.year, nextMonthRef.month, cutoffDay);

  return CardCycleDates(
    lastCutoff: lastCutoff,
    nextCutoff: nextCutoff,
    dueDate: _dueDateForCutoff(credit, lastCutoff),
  );
}
```

(Esto reemplaza el cuerpo anterior de `getCardCycleDates` — mismo
comportamiento, solo extrae el cálculo de `dueDate` a una función
reutilizable por el cierre de extractos más abajo.)

Agregar `buildInstallmentMovements` y `registerCardCharge` después de
`registerCardMovement` (línea ~220):

```dart
/// Splits a purchase of [totalAmount] into [installments] movements, one
/// per consecutive future billing cycle starting from the currently open
/// one. Each movement's `date` is the real purchase date (for display);
/// `statementCutoff` is what determines which extracto it belongs to.
/// Rounds to 2 decimals; the rounding remainder is absorbed entirely by the
/// LAST installment so the sum always equals [totalAmount] exactly.
List<CardMovement> buildInstallmentMovements({
  required CardCredit credit,
  required double totalAmount,
  required int installments,
  String note = '',
  String? categoria,
  DateTime? refDate,
}) {
  final perInstallment = _round2(totalAmount / installments);
  final lastInstallment =
      _round2(totalAmount - perInstallment * (installments - 1));
  final purchaseDate = toDateStr(refDate ?? DateTime.now());

  var cycle = getCardCycleDates(credit, refDate);
  final movements = <CardMovement>[];
  for (var i = 1; i <= installments; i++) {
    movements.add(CardMovement(
      date: purchaseDate,
      type: CardMovementType.charge,
      amount: i == installments ? lastInstallment : perInstallment,
      note: note,
      categoria: categoria,
      chargeInstallments: installments,
      installmentIndex: i,
      statementCutoff: toDateStr(cycle.nextCutoff),
    ));
    cycle = getCardCycleDates(
      credit,
      cycle.nextCutoff.add(const Duration(days: 1)),
    );
  }
  return movements;
}

/// Registers a card charge, splitting it across [installments] consecutive
/// extractos when `installments > 1` (see [buildInstallmentMovements]).
/// A single-installment charge behaves exactly like the old
/// [registerCardMovement] (no `statementCutoff`, grouped by the normal
/// date+cutoff criterion).
void registerCardCharge(
  CardCredit credit,
  double totalAmount, {
  String note = '',
  String? categoria,
  int installments = 1,
  DateTime? refDate,
}) {
  if (installments <= 1) {
    registerCardMovement(
      credit,
      CardMovementType.charge,
      totalAmount,
      note: note,
      categoria: categoria,
    );
    return;
  }
  final movements = buildInstallmentMovements(
    credit: credit,
    totalAmount: totalAmount,
    installments: installments,
    note: note,
    categoria: categoria,
    refDate: refDate,
  );
  credit.currentBalance = _round2(credit.currentBalance + totalAmount.abs());
  credit.movements.addAll(movements);
}
```

Agregar `PayableSummary`/`getPayableSummary` después de
`getCardAvailableLimit` (línea ~247):

```dart
/// What the user actually owes RIGHT NOW (closed, unpaid statements) vs.
/// charges already made in the still-open cycle (not due yet). This is
/// what fixes the bug where a brand-new charge, registered right after a
/// cutoff, appeared lumped together with an imminent due date that
/// actually belonged to the PREVIOUS (already-closed) statement.
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
  final unpaid = credit.closedStatements
      .where((s) => s.status != CardStatementStatus.paid)
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final exigible =
      unpaid.fold(0.0, (sum, s) => sum + (s.closingBalance - s.paidAmount));
  final dueDate = unpaid.isEmpty ? null : parseDateStr(unpaid.first.dueDate);
  final pendienteFacturar = _round2(credit.currentBalance - exigible);
  return PayableSummary(
    exigible: exigible,
    pendienteFacturar: pendienteFacturar,
    dueDate: dueDate,
  );
}
```

Modificar `accrueCardCredit` (línea 95-161) para crear un `CardStatement`
en cada iteración del `while`, justo antes de `cursorStr = toDateStr(next);`:

```dart
    cursorStr = toDateStr(next);
```

reemplazar por:

```dart
    final cycleEndStr = toDateStr(next);
    final cycleMovements = credit.movements.where((m) {
      if (m.statementCutoff != null) return m.statementCutoff == cycleEndStr;
      return cycleKeyFor(m.date, cutoffDay) == cycleEndStr;
    });
    var netAmount = 0.0;
    for (final m in cycleMovements) {
      netAmount += m.type == CardMovementType.payment
          ? -m.amount.abs()
          : m.amount.abs();
    }
    final openingBalance = credit.closedStatements.isNotEmpty
        ? (credit.closedStatements.last.closingBalance -
            credit.closedStatements.last.paidAmount)
        : 0.0;
    credit.closedStatements.add(CardStatement(
      id: '${credit.id}-$cycleEndStr',
      creditId: credit.id,
      cutoffDate: cycleEndStr,
      dueDate: toDateStr(_dueDateForCutoff(credit, next)),
      closingBalance: _round2(openingBalance + netAmount),
      createdAt: toDateStr(todayMidnight),
    ));

    cursorStr = cycleEndStr;
```

(Nota: el `interest`/`fee` de esa misma iteración ya se agregó a
`credit.movements` ANTES de este bloque, con `date: toDateStr(next)` — por
lo tanto `cycleKeyFor(m.date, cutoffDay) == cycleEndStr` los incluye
correctamente en el extracto que se está cerrando.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/card_calculator_test.dart`
Expected: PASS — todos los tests nuevos y los preexistentes.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/card_calculator.dart test/domain/card_calculator_test.dart
git commit -m "feat: reparte cuotas en extractos consecutivos, unifica día de corte, saldo exigible real"
```

---

### Task 6: `movements_tab.dart` — usar `cycleKeyFor` unificado y agrupar cuotas por `statementCutoff`

**Files:**
- Modify: `lib/widgets/credit_detail/movements_tab.dart`
- Test: `test/widgets/credit_detail/movements_tab_grouping_test.dart`

**Interfaces:**
- Consumes: `cycleKeyFor` (Task 5), `CardMovement.statementCutoff` (Task 2).
- Produces: `Map<String, List<CardMovement>> groupMovementsByCycle(List<CardMovement> movements, int cutoffDay)` — función pura extraída y
  testeable, usada por `MovementsTab.build`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/credit_detail/movements_tab_grouping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/widgets/credit_detail/movements_tab.dart';

void main() {
  test('a charge exactly on the cutoff day groups under that same cutoff '
      '(not next month) — regression for the day==cutoff bug', () {
    final movements = [
      CardMovement(date: '2026-01-15', type: CardMovementType.charge, amount: 10000),
    ];
    final groups = groupMovementsByCycle(movements, 15);
    expect(groups.keys, contains('2026-01-15'));
    expect(groups.keys, isNot(contains('2026-02-15')));
  });

  test('an installment movement with statementCutoff groups by that field, '
      'ignoring its purchase date', () {
    final movements = [
      CardMovement(
        date: '2026-01-10', // fecha real de compra
        type: CardMovementType.charge,
        amount: 50000,
        chargeInstallments: 3,
        installmentIndex: 2,
        statementCutoff: '2026-02-15', // extracto al que pertenece esta cuota
      ),
    ];
    final groups = groupMovementsByCycle(movements, 15);
    expect(groups.keys, contains('2026-02-15'));
    expect(groups.keys, isNot(contains('2026-01-15')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/credit_detail/movements_tab_grouping_test.dart`
Expected: FAIL — `The function 'groupMovementsByCycle' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

En `lib/widgets/credit_detail/movements_tab.dart`, reemplazar el import y
la función privada `_cycleKeyFor` (líneas 1-38) por:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/card_movement.dart';
import '../../data/models/credit.dart';
import '../../domain/card_calculator.dart';
import '../../providers/credits_provider.dart';
import '../../theme/app_theme.dart';
import '../card_movement_sheet.dart';
import '../../utils/credit_display_utils.dart';
import '../kredit_bottom_dialogs.dart';

/// Groups [movements] by billing cycle (extracto), most-recent-first isn't
/// guaranteed here — callers sort as needed. An installment movement
/// (`statementCutoff != null`) groups by that field directly, since it was
/// assigned to a specific future extracto when registered; every other
/// movement groups by [cycleKeyFor] (date + cutoffDay).
Map<String, List<CardMovement>> groupMovementsByCycle(
    List<CardMovement> movements, int cutoffDay) {
  final groups = <String, List<CardMovement>>{};
  for (final m in movements) {
    final key = m.statementCutoff ?? cycleKeyFor(m.date, cutoffDay);
    groups.putIfAbsent(key, () => []).add(m);
  }
  return groups;
}
```

Y en `MovementsTab.build` (línea ~53-58), reemplazar el bucle de
agrupación manual por:

```dart
    final groups = groupMovementsByCycle(movements, credit.cutoffDay);
```

(Elimina las líneas `final groups = <String, List<CardMovement>>{}; for
(final m in movements) { final key = _cycleKeyFor(...); ... }` — ya no se
necesitan, `groupMovementsByCycle` hace el trabajo.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/credit_detail/movements_tab_grouping_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Run the full widget test suite to check no regression**

Run: `flutter test test/widgets/credit_detail/`
Expected: PASS — ningún test existente de `movements_tab` (si los hay) se rompe.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/credit_detail/movements_tab.dart test/widgets/credit_detail/movements_tab_grouping_test.dart
git commit -m "fix: unifica agrupación por extracto (día de corte consistente) y soporta cuotas futuras"
```

---

### Task 7: `credits_provider.dart` — enrutar compras a N cuotas por `registerCardCharge`

**Files:**
- Modify: `lib/providers/credits_provider.dart`
- Test: `test/providers/credits_provider_test.dart` (crear si no existe)

**Interfaces:**
- Consumes: `registerCardCharge` (Task 5).
- Produces: `CreditsNotifier.registerMovement(...)` sigue con la misma
  firma pública (compatibilidad con `card_movement_sheet.dart`), pero
  internamente enruta cargos con `chargeInstallments != null &&
  chargeInstallments! > 1` por `registerCardCharge` en vez de
  `registerCardMovement`.

- [ ] **Step 1: Write the failing test**

```dart
// test/providers/credits_provider_test.dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/providers/credits_provider.dart';
import 'package:krezium/providers/database_provider.dart';

void main() {
  test('registerMovement with chargeInstallments > 1 splits the charge '
      'into N movements with statementCutoff set', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final card = CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15);
    await db.upsertCredit(card);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(creditsProvider.future);
    await container.read(creditsProvider.notifier).registerMovement(
          'c1',
          CardMovementType.charge,
          300000,
          'Compra TV',
          chargeInstallments: 3,
        );

    final credits = container.read(creditsProvider).value!;
    final reloaded = credits.whereType<CardCredit>().first;
    expect(reloaded.movements, hasLength(3));
    expect(reloaded.movements.every((m) => m.statementCutoff != null), isTrue);
    expect(reloaded.currentBalance, 300000);
  });

  test('registerMovement with chargeInstallments == 1 behaves like before '
      '(single movement, no statementCutoff)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final card = CardCredit(id: 'c1', name: 'Visa', lender: 'Bank', cutoffDay: 15);
    await db.upsertCredit(card);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(creditsProvider.future);
    await container.read(creditsProvider.notifier).registerMovement(
          'c1',
          CardMovementType.charge,
          50000,
          'Café',
        );

    final credits = container.read(creditsProvider).value!;
    final reloaded = credits.whereType<CardCredit>().first;
    expect(reloaded.movements, hasLength(1));
    expect(reloaded.movements.first.statementCutoff, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/credits_provider_test.dart`
Expected: FAIL — primer test espera 3 movimientos pero
`registerCardMovement` actual crea solo 1.

- [ ] **Step 3: Write minimal implementation**

En `lib/providers/credits_provider.dart`, modificar `registerMovement`
(línea 196-210):

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
    if (type == CardMovementType.charge && (chargeInstallments ?? 1) > 1) {
      registerCardCharge(
        credit,
        amount,
        note: note,
        categoria: categoria,
        installments: chargeInstallments!,
      );
    } else {
      registerCardMovement(credit, type, amount, note: note, categoria: categoria);
    }
    await _db.upsertCredit(credit);
    _notifyInPlace();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/credits_provider_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Commit**

```bash
git add lib/providers/credits_provider.dart test/providers/credits_provider_test.dart
git commit -m "feat: registerMovement reparte compras a N cuotas por extracto"
```

---

### Task 8: UI — mostrar saldo exigible vs. pendiente de facturar

**Files:**
- Modify: `lib/utils/credit_display_utils.dart`
- Modify: `lib/widgets/wallet_card.dart`
- Modify: `lib/screens/credit_detail/credit_detail_screen.dart`
- Test: `test/utils/credit_display_utils_test.dart` (crear si no existe; si existe, añadir)

**Interfaces:**
- Consumes: `getPayableSummary` (Task 5).
- Produces: `getNextDueDate(Credit)` para tarjetas ahora usa el `dueDate` de
  `getPayableSummary` (solo extractos cerrados sin pagar) en vez de
  `getCardCycleDates(...).dueDate` directo.

- [ ] **Step 1: Write the failing test**

```dart
// test/utils/credit_display_utils_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/date_utils.dart';
import 'package:krezium/utils/credit_display_utils.dart';

void main() {
  test('getNextDueDate for a card with no closed statements returns null '
      '(nothing is due yet — only open-cycle charges exist)', () {
    final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    expect(getNextDueDate(card), isNull);
  });

  test('getNextDueDate for a card with an unpaid closed statement returns '
      'that statement\'s dueDate, not today\'s open-cycle projection', () {
    final card = CardCredit(
      id: 'c1',
      name: 'Test',
      lender: 'Bank',
      cutoffDay: 15,
      closedStatements: const [
        CardStatement(
          id: 's1',
          creditId: 'c1',
          cutoffDate: '2026-01-15',
          dueDate: '2026-02-05',
          closingBalance: 100000,
          createdAt: '2026-01-15',
        ),
      ],
    );
    expect(getNextDueDate(card), parseDateStr('2026-02-05'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/credit_display_utils_test.dart`
Expected: FAIL — primer test actual devuelve una fecha (la del ciclo
calculado respecto a "hoy"), no `null`.

- [ ] **Step 3: Write minimal implementation**

En `lib/utils/credit_display_utils.dart`, modificar `getNextDueDate`
(línea 34-45):

```dart
/// Next relevant due date for a credit: earliest unpaid installment for
/// loans, earliest unpaid CLOSED statement's due date for cards (NOT the
/// open cycle's projected due date — charges in the still-open cycle
/// aren't due yet). Null if a loan has no unpaid installments left, or a
/// card has no closed unpaid statements.
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

En `lib/widgets/wallet_card.dart`, en `_statsFor` (bloque `if (credit is
CardCredit)`, el que usaba `getCardCycleDates(credit).dueDate`):

```dart
    if (credit is CardCredit) {
      if (credit.creditLimit > 0) {
        final available = getCardAvailableLimit(credit);
        items.add(
          _StatItem(
            icon: Icons.credit_card_outlined,
            label: 'Cupo disponible',
            value: formatCOP(available),
          ),
        );
      }
      final summary = getPayableSummary(credit);
      if (summary.exigible > 0 && summary.dueDate != null) {
        items.add(
          _StatItem(
            icon: Icons.event_outlined,
            label: 'Próximo pago',
            value: formatDate(toDateStr(summary.dueDate!)),
          ),
        );
      }
    } else if (credit is LoanCredit) {
```

En `lib/screens/credit_detail/credit_detail_screen.dart`, en el bloque que
arma `leftLabel`/`rightLabel` para `CardCredit` (línea ~569-576):

```dart
      } else {
        final card = credit as CardCredit;
        final dates = getCardCycleDates(card);
        final summary = getPayableSummary(card);
        leftLabel = 'Fecha de corte';
        leftValue = toDateStr(dates.nextCutoff);
        leftIcon = Icons.event_repeat_outlined;
        rightLabel = summary.dueDate != null ? 'Límite de pago' : 'Sin pagos pendientes';
        rightValue = summary.dueDate != null ? toDateStr(summary.dueDate!) : '—';
        rightIcon = Icons.event_available_outlined;
      }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/credit_display_utils_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Run full test suite to check no regression**

Run: `flutter test`
Expected: PASS en todo el proyecto (todas las tareas anteriores incluidas).

- [ ] **Step 6: Commit**

```bash
git add lib/utils/credit_display_utils.dart lib/widgets/wallet_card.dart lib/screens/credit_detail/credit_detail_screen.dart test/utils/credit_display_utils_test.dart
git commit -m "fix: fecha límite y saldo exigible reflejan solo extractos cerrados"
```

---

### Task 9: Backup — subir versión de formato y migración v3→v4

**Files:**
- Modify: `lib/domain/export_import.dart`
- Test: `test/domain/export_import_test.dart` (crear si no existe; si existe, añadir)

**Interfaces:**
- Consumes: `CardCredit.closedStatements` (Task 3, ya maneja default `[]`
  en `fromJson`).
- Produces: `kBackupFormatVersion == 4`; un backup v3 (sin
  `closedStatements` en sus créditos tipo card) importa sin error.

- [ ] **Step 1: Write the failing test**

```dart
// Añadir a test/domain/export_import_test.dart (crear si no existe)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/export_import.dart';

void main() {
  test('kBackupFormatVersion is 4', () {
    expect(kBackupFormatVersion, 4);
  });

  test('imports a v3 backup (no closedStatements field) without error, '
      'card credit ends up with empty closedStatements', () {
    final v3Json = jsonEncode({
      'format': kBackupFormatMarker,
      'version': 3,
      'exportedAt': '2026-01-01T00:00:00.000Z',
      'credits': [
        {
          'id': 'c1',
          'type': 'card',
          'name': 'Visa',
          'lender': 'Bank',
          'currentBalance': 100000.0,
          'cutoffDay': 15,
          'movements': [],
        }
      ],
      'commercialQuotas': [],
    });

    final result = importStateFromJson(v3Json);

    expect(result.credits, hasLength(1));
    final card = result.credits.first as CardCredit;
    expect(card.closedStatements, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/export_import_test.dart`
Expected: FAIL — `expect(kBackupFormatVersion, 4)` falla porque hoy vale 3.

- [ ] **Step 3: Write minimal implementation**

En `lib/domain/export_import.dart`, cambiar la constante (línea 25):

```dart
const int kBackupFormatVersion = 4;
```

Agregar el branch de migración v3→v4 en `_migrateBackup` (dentro del
`while`, justo antes del `break` final, línea ~103-107):

```dart
    if (version == 3) {
      // v3 -> v4 added CardCredit.closedStatements and
      // CardMovement.installmentIndex/statementCutoff — all absent in v3
      // backups. CardCredit.fromJson and CardMovement.fromJson already
      // default them to [] / null respectively, so nothing needs to
      // change in the decoded payload itself; this branch exists purely
      // to document the version bump and advance the loop.
      version = 4;
      continue;
    }
    // Should be unreachable given the version check above, but avoid an
    // infinite loop if a future version is added to kBackupFormatVersion
    // without a matching branch here.
    break;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/export_import_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: PASS en todo el proyecto.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/export_import.dart test/domain/export_import_test.dart
git commit -m "feat: sube versión de backup a v4 para closedStatements"
```

---

## Self-Review

**1. Spec coverage:**
- Tabla `CardStatements` → Task 4. ✓
- Campos `installmentIndex`/`statementCutoff` en `CardMovement` → Task 2. ✓
- Reparto de cuotas en N extractos → Task 5 (`buildInstallmentMovements`,
  `registerCardCharge`). ✓
- `getPayableSummary` (exigible vs. pendiente de facturar) → Task 5. ✓
- Fix del día de corte → Task 5 (`cycleKeyFor` único) + Task 6 (consumidor). ✓
- Cierre de extracto en `accrueCardCredit` → Task 5. ✓
- Migración DB v14→v15 → Task 4. ✓
- Migración backup v3→v4 → Task 9. ✓
- UI (wallet_card, credit_detail_screen, movements_tab) → Task 6 y Task 8. ✓
- `clearAllData`/`replaceAllData` incluyen `cardStatements` → Task 4. ✓

**2. Placeholder scan:** sin TBD/TODO, todos los pasos tienen código real.

**3. Type consistency:** `CardStatement`, `PayableSummary`, `cycleKeyFor`,
`buildInstallmentMovements`, `registerCardCharge`, `getPayableSummary`,
`groupMovementsByCycle` se nombran igual en todas las tareas que los
consumen.

**4. Review Focus:**
- Redondeo de cuotas con decimales → test en Task 5
  (`buildInstallmentMovements` "rounding remainder").
- Día de corte exacto → tests en Task 5 (`cycleKeyFor`) y Task 6
  (`groupMovementsByCycle`).
- Backup v3 sin campos nuevos → test en Task 9.
- Eliminar una cuota individual de una compra a plazos sin afectar las
  demás: **gap detectado** — ningún task existente prueba esto
  explícitamente. `deleteCardMovement` ya opera por índice individual sin
  noción de "grupo", así que el comportamiento correcto (borrar solo esa
  cuota) ya es el actual por construcción; agrego el test ahora:

**Test adicional para Task 5** (agregar a
`test/domain/card_calculator_test.dart`, grupo `deleteCardMovement`):

```dart
group('deleteCardMovement with installments', () {
  test('deleting one installment movement leaves the other installments '
      'of the same purchase untouched', () {
    final credit = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    registerCardCharge(credit, 300000, installments: 3, refDate: DateTime(2026, 1, 10));
    expect(credit.movements, hasLength(3));

    deleteCardMovement(credit, 1); // borra la cuota 2 de 3

    expect(credit.movements, hasLength(2));
    expect(credit.movements[0].installmentIndex, 1);
    expect(credit.movements[1].installmentIndex, 3);
    expect(credit.currentBalance, 200000); // 300000 - cuota eliminada (100000)
  });
});
```
- `accrueCardCredit` llamado dos veces sin nuevo ciclo → test ya incluido
  en Task 5 ("does not create duplicate CardStatements").

Todos los puntos del Review Focus quedan cubiertos por un test concreto en
la tarea que posee el código correspondiente.

---

Plan completo y auto-revisado. Guardado en
`docs/superpowers/plans/2026-10-11-card-statements-implementation.md`.
