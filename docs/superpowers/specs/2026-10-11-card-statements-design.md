# Extractos de tarjeta de crédito — Spec de diseño

## Contexto y problema

Hoy `CardCredit.currentBalance` es un saldo único revolvente. Un cargo
registrado se suma directo a ese saldo (`registerCardMovement`,
`lib/domain/card_calculator.dart`). La "fecha límite de pago" que ve el
usuario (`getCardCycleDates(credit).dueDate`) se calcula siempre respecto a
`DateTime.now()`, representando el extracto que **ya cerró** — no el ciclo
en el que cae un cargo específico.

Resultado: un cargo registrado justo después del corte (ciclo nuevo, aún
no exigible) se suma al mismo saldo que se muestra junto a la fecha límite
del extracto viejo (que sí vence pronto). El usuario percibe "tengo que
pagar esto ya" cuando en realidad ese cargo cae en el extracto siguiente.

Problema relacionado: una compra a N cuotas (`chargeInstallments`) hoy se
registra como **un solo movimiento por el monto total**. No existe reparto
real de cuotas en extractos sucesivos — `chargeInstallments` es solo texto
decorativo en la UI (`movements_tab.dart`), nunca genera N movimientos ni
N fechas de vencimiento.

Bug adicional confirmado: `card_calculator.dart::getCardCycleDates` y
`movements_tab.dart::_cycleKeyFor` tratan el caso límite "fecha == día de
corte" de forma opuesta — una inconsistencia de un archivo a otro para el
mismo día exacto.

## Objetivo

1. Cada extracto (ciclo de facturación) de una tarjeta es una entidad con
   su propio saldo de cierre y su propia fecha límite.
2. El saldo "a pagar ya" que ve el usuario = suma de extractos **cerrados**
   sin pagar. Los cargos del ciclo recién abierto se muestran separados,
   como "pendiente de facturar" (no exigibles todavía).
3. Una compra a N cuotas reparte el monto entre N extractos consecutivos
   (monto total / N, ajustando redondeo en la última cuota), cada cuota
   con su propia fecha límite real.
4. El criterio del día de corte es consistente en todo el código: el
   corte pertenece al ciclo que **cierra** ese día (convención bancaria
   estándar) — esto es ya el comportamiento documentado (en comentarios)
   de `card_calculator.dart`; hay que corregir `movements_tab.dart` para
   que coincida con su propio comentario.

## Fuera de alcance

- No se reconstruyen retroactivamente extractos para compras/cuotas ya
  registradas antes de esta migración. Solo aplica hacia adelante.
- No se soporta pago parcial de un extracto más allá de un monto abonado
  simple (`paidAmount`) — no hay reparto de abonos entre múltiples
  extractos abiertos simultáneamente en esta iteración.

## Global Constraints

- `schemaVersion` de Drift sube de 14 a 15 (`lib/data/db/database.dart`).
- `kBackupFormatVersion` de `lib/domain/export_import.dart` sube de 3 a 4.
- Toda tabla nueva debe añadirse a `clearAllData` y `replaceAllData` en
  `lib/data/db/database.dart` (líneas ~649-697) para no quedar huérfana.
- El patrón de persistencia de `CardMovements` (tabla relacional,
  replace-all en `upsertCredit`) se reutiliza para la tabla nueva — no se
  usa JSON embebido, por consistencia con el resto del código.
- Montos en cuotas: redondeo a 2 decimales; el remanente de la división
  (total - (monto_cuota * (N-1))) va en la última cuota, para que la suma
  exacta coincida con el monto original.

## Diseño

### 1. Nueva tabla `CardStatements` (`lib/data/db/tables.dart`)

Representa un extracto **cerrado** (histórico). El extracto actualmente
abierto NO tiene fila — se calcula on-the-fly (ver sección 4).

Campos:
- `id` (text, PK)
- `creditId` (text, FK → `credits.id`, cascade on delete)
- `cutoffDate` (text, "YYYY-MM-DD") — fecha de corte que cerró este extracto
- `dueDate` (text, "YYYY-MM-DD") — fecha límite de pago de este extracto
- `closingBalance` (real) — saldo total a pagar de este extracto al momento de cerrar
- `paidAmount` (real, default 0) — abonado a este extracto
- `status` (text) — `'closed'` | `'paid'` (se marca `'paid'` cuando `paidAmount >= closingBalance`)
- `createdAt` (text, "YYYY-MM-DD") — fecha en que se generó el registro (para debug/orden)

### 2. Campos nuevos en `CardMovement` (`lib/data/models/card_movement.dart`) y tabla `CardMovements`

- `int? installmentIndex` — posición de esta cuota dentro de su compra (1-based). `null` para movimientos que no son cuota de una compra a plazos.
- `String? statementCutoff` ("YYYY-MM-DD") — fecha de corte del extracto al que esta cuota específica está asignada. Cuando es `null`, el movimiento se agrupa por el criterio de fecha+corte normal (comportamiento actual, para cargos de 1 sola cuota, pagos, intereses, avances).

`chargeInstallments` (ya existente) pasa a representar el **total de cuotas** de la compra (igual que hoy), presente en los N movimientos generados.

### 3. Registro de una compra a N cuotas (`lib/domain/card_calculator.dart`)

Nueva función `registerCardCharge` (reemplaza el uso directo de
`registerCardMovement` para cargos con `chargeInstallments != null && > 1`
desde `lib/providers/credits_provider.dart::registerMovement`):

```dart
List<CardMovement> buildInstallmentMovements({
  required CardCredit credit,
  required double totalAmount,
  required int installments,
  required String note,
  String? categoria,
  DateTime? refDate,
}) {
  final perInstallment = _round2(totalAmount / installments);
  final lastInstallment = _round2(
    totalAmount - perInstallment * (installments - 1),
  );
  final today = toDateStr(refDate ?? DateTime.now());
  var cycle = getCardCycleDates(credit, refDate);
  final movements = <CardMovement>[];
  for (var i = 1; i <= installments; i++) {
    movements.add(CardMovement(
      date: today, // fecha real de la compra, para mostrar "comprado el X"
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
```

`registerCardCharge` llama a esto, agrega los N movimientos a
`credit.movements`, y suma `totalAmount` completo a `credit.currentBalance`
(el saldo corriente sigue existiendo como total de deuda viva, igual que
hoy — lo que cambia es cómo se calcula "cuánto debo pagar ya").

Compras de 1 sola cuota (`installments == null || installments <= 1`)
siguen el camino actual (`registerCardMovement`, sin `statementCutoff`).

### 4. Cálculo de saldo exigible y fecha límite (`lib/domain/card_calculator.dart`)

Nueva función que reemplaza el uso directo de `currentBalance` +
`getCardCycleDates(...).dueDate` para mostrar "cuánto debes pagar ya":

```dart
({double exigible, double pendienteFacturar, DateTime? dueDate})
    getPayableSummary(CardCredit credit, List<CardStatement> closedStatements) {
  final unpaid = closedStatements.where((s) => s.status != 'paid').toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final exigible = unpaid.fold(0.0, (sum, s) => sum + (s.closingBalance - s.paidAmount));
  final dueDate = unpaid.isEmpty ? null : parseDateStr(unpaid.first.dueDate);
  final pendienteFacturar = credit.currentBalance - exigible; // cargos del ciclo abierto
  return (exigible: exigible, pendienteFacturar: pendienteFacturar, dueDate: dueDate);
}
```

`getNextDueDate` (`lib/utils/credit_display_utils.dart`) se actualiza para
usar `dueDate` de `getPayableSummary` en vez de `getCardCycleDates(...).dueDate`
directo, para tarjetas.

### 5. Cierre de extracto (`lib/domain/card_calculator.dart::accrueCardCredit`)

Cuando `accrueCardCredit` detecta que un ciclo cerró (su lógica actual de
recorrer desde `lastAccrualCutoff` hasta el ciclo actual, líneas 95-161),
por cada corte cruzado:

1. Calcula `closingBalance` = suma de movimientos (`charge`, `fee`,
   `interest`, menos `payment`) cuyo `statementCutoff == cutoffDate` (si lo
   tienen) o cuya fecha cae en ese ciclo por el criterio fecha+corte
   (unificado, ver sección 6), más el `closingBalance` no pagado del
   extracto anterior (saldo que rueda).
2. Crea un `CardStatement` con `status: 'closed'`.
3. Esto se retorna desde `accrueCardCredit` como lista de nuevos
   `CardStatement` para que el provider los persista (`lib/providers/
   credits_provider.dart::_accrueAndRecompute`, líneas 67-112) vía un
   nuevo método `AppDatabase.insertCardStatements(List<CardStatement>)`.

### 6. Fix de la inconsistencia del día de corte (`lib/widgets/credit_detail/movements_tab.dart`)

`_cycleKeyFor` (líneas 24-38): cambiar `d.day < clampedCutoff` por
`d.day <= clampedCutoff` para que el día de corte caiga en el ciclo que
cierra ese mismo mes — consistente con `card_calculator.dart::
getCardCycleDates` (que ya trata `today == cutoffDay` como parte del ciclo
que se cierra) y con el comentario que ya tenía el propio archivo.

Test de regresión: dado `cutoffDay = 15`, un movimiento con fecha
`'2026-01-15'` debe agruparse en el ciclo que cierra `'2026-01-15'` (no en
`'2026-02-15'`).

### 7. Persistencia (`lib/data/db/database.dart`)

- Agregar `CardStatements` a `@DriftDatabase(tables: [...])`.
- `schemaVersion` → 15; bloque `if (from < 15) { await m.createTable(cardStatements); }`
  al final de `onUpgrade` (después del bloque `from < 12` existente, por el
  orden no-ascendente ya presente en el archivo).
- `loadAllCredits`: cargar `CardStatement`s por `creditId` igual que
  `cardMovements` hoy (líneas 290-310), exponerlos en un campo nuevo
  `List<CardStatement> closedStatements` de `CardCredit`.
- `upsertCredit`: igual patrón replace-all que `cardMovements` (borrar por
  `creditId`, reinsertar todos).
- `clearAllData` y `replaceAllData`: agregar `delete(cardStatements)`.

### 8. Modelo (`lib/data/models/credit.dart`, nuevo `lib/data/models/card_statement.dart`)

- Nueva clase `CardStatement` con `toJson`/`fromJson` (mismo patrón que
  `CardMovement`).
- `CardCredit` gana campo `List<CardStatement> closedStatements` (constructor,
  `toJson`, `fromJson`) — igual tratamiento que `movements`.

### 9. Backup/restore (`lib/domain/export_import.dart`)

- `kBackupFormatVersion` → 4.
- Migración `if (version == 3) { /* nada que mutar: closedStatements ya viene
  vacío en CardCredit.fromJson si no existe en el JSON viejo */ version = 4;
  continue; }` — no requiere default explícito porque `CardCredit.fromJson`
  ya maneja el campo como `?? []`.
- `exportStateToJson`/`importStateFromJson`: automático vía `toJson`/`fromJson`
  de `CardCredit`, sin cambios adicionales en este archivo salvo la
  migración.

### 10. UI

- `lib/widgets/wallet_card.dart` y `lib/screens/credit_detail/credit_detail_screen.dart`:
  mostrar "Debes $exigible antes del $dueDate" (de `getPayableSummary`) en
  vez de `currentBalance` + `getCardCycleDates().dueDate` directo. Mostrar
  además "Pendiente de facturar: $pendienteFacturar" cuando sea > 0.
- `lib/widgets/credit_detail/movements_tab.dart`: agrupar por
  `statementCutoff` cuando el movimiento lo tenga (cuotas futuras),
  usando `_cycleKeyFor(movement.date, cutoffDay)` como fallback cuando sea
  `null`.

## Review Focus

- **Compra a 1 cuota de monto con decimales no exactos (ej. $100.005)**:
  el redondeo de `_round2` no debe perder ni duplicar centavos entre
  cuotas — el test de `buildInstallmentMovements` debe verificar que
  `movements.map((m) => m.amount).sum == totalAmount` exacto.
- **Cambio de `cutoffDay` del usuario a mitad de compras con cuotas
  pendientes**: las cuotas ya generadas tienen `statementCutoff` fijo
  (no se recalculan si el usuario edita el día de corte después) —
  comportamiento esperado: cuotas ya asignadas no se mueven; un reasonable
  person entendería que solo afecta compras futuras, documentarlo en la UI
  de edición de tarjeta (`edit_credit_sheet.dart`).
- **Extracto cerrado pagado parcialmente y luego el usuario abona más
  del saldo restante**: `paidAmount` no debe exceder `closingBalance`
  visualmente negativo — clamp a `closingBalance` y el excedente debe
  advertirse o aplicarse al siguiente extracto (decisión: por ahora clamp
  simple, documentar como limitación conocida, no exigir reparto automático
  de excedente en esta iteración).
- **Restaurar un backup antiguo (versión de formato 3, sin
  `closedStatements`)**: debe importar sin error y arrancar con 0 extractos
  cerrados — `accrueCardCredit` los irá generando hacia adelante en el
  próximo arranque de la app.
- **Eliminar un movimiento de cuota individual (`deleteMovement`) que es
  parte de una compra a N cuotas**: hoy `deleteCardMovement` borra un solo
  movimiento sin noción de "grupo de cuotas" — debe decidirse si borrar una
  cuota individual dentro de una compra a plazos es una operación válida
  (recomendado: sí, se borra solo esa cuota, sin afectar las demás; añadir
  un test que lo confirme explícitamente para que no sea un accidente de
  implementación).
