# Extractos de tarjeta de crédito v2 — Reescritura (extracto como fuente de verdad)

## Contexto

La iteración anterior (`docs/superpowers/specs/2026-10-11-card-statements-design.md`,
implementada y luego parcheada varias veces — ver historial de commits
`113ab56..d829688`) intentó añadir extractos (`CardStatement`) **encima**
de un modelo ya existente donde `CardCredit.currentBalance` es un saldo
único que se muta a mano (`registerCardMovement`/`registerCardCharge`).
Esto dejó dos fuentes de verdad paralelas que hay que mantener
sincronizadas manualmente, y produjo una cadena de bugs (doble conteo de
deuda, saldo semilla ignorado, pagos que no bajaban el "exigible", cuotas
agrupadas en orden no cronológico) — cada parche resolvía un síntoma sin
tocar la causa.

Esta reescritura hace que **el extracto sea la única fuente de verdad**.
`currentBalance` deja de mutarse directamente: se calcula siempre a partir
de los extractos y de las compras a plazos pendientes de facturar — igual
que un banco real, donde los extractos y los indicadores de pago son lo
que manda.

## Objetivo

1. Cada tarjeta tiene SIEMPRE un extracto abierto (ciclo actual) como fila
   real, no inferida — además de sus extractos cerrados (histórico).
2. Una compra a N cuotas es una entidad propia (`InstallmentPurchase`): la
   cuota 1 se factura de inmediato en el extracto abierto; cada cuota
   siguiente se factura automáticamente, una por una, cuando el extracto
   correspondiente abre — nunca se "pre-crean" N grupos futuros de golpe.
3. "Debes ya" = extracto cerrado más reciente sin pagar por completo.
   "Cupo disponible" descuenta el total comprometido (extractos sin pagar +
   el abierto + cuotas aún no facturadas de compras a plazos).
4. `currentBalance` se vuelve una caché recalculada por una sola función —
   nunca un valor que distintas rutas de código suman/restan a mano.

## Fuera de alcance

- Reconstrucción retroactiva perfecta de compras a plazos ya registradas
  antes de esta migración — se migran best-effort (ver sección de
  migración), aceptando que su reparto histórico puede no coincidir
  exactamente con lo que habría sido con este diseño desde el inicio.
- Reparto de un pago entre varios extractos cerrados sin pagar
  simultáneamente (ej. 2 meses de atraso) — un pago se aplica siempre al
  extracto cerrado sin pagar MÁS ANTIGUO primero (FIFO), documentado como
  comportamiento esperado, no editable por el usuario en esta iteración.

## Diseño

### 1. Entidad nueva: `InstallmentPurchase` (compra a plazos)

Una fila por cada compra registrada con N > 1 cuotas.

Campos:
- `id`, `creditId` (FK)
- `purchaseDate` ("YYYY-MM-DD")
- `totalAmount`, `installments` (N)
- `perInstallmentAmount` (redondeado a 2 decimales), `lastInstallmentAmount`
  (monto + remanente de redondeo, para que la suma total sea exacta)
- `note`, `categoria`
- `installmentsBilled` (empieza en 1 — la cuota 1 se factura al momento de
  la compra, en el extracto abierto)
- `createdAt`

No se "pre-generan" movimientos para las cuotas 2..N al momento de la
compra. Se generan una por una, automáticamente, cuando cada ciclo futuro
abre (ver sección 3).

### 2. `CardStatement` rediseñado — ahora incluye el ciclo ABIERTO

Campos (reemplaza el diseño anterior):
- `id`, `creditId` (FK)
- `cutoffDate`, `dueDate` ("YYYY-MM-DD")
- `status`: `'open' | 'closed' | 'paid'`
- `openingBalance` (double) — saldo sin pagar del extracto anterior al
  momento en que ESTE abrió. Fijo una vez creado, nunca se recalcula
  retroactivamente.
- `paidAmount` (double, default 0)
- `createdAt`

**`totalAmount` NO se guarda** — se calcula siempre:
```
totalAmount(statement) = openingBalance
    + sum(movimientos ligados a este statement: charge/interest/fee +, payment -)
```
Esto significa que un extracto abierto siempre refleja la realidad en vivo
(si se borra/edita un movimiento, el total se recalcula solo, sin arrastrar
un valor congelado desactualizado). Un extracto cerrado también se calcula
igual — "cerrado" solo quiere decir que ya no se le pueden agregar cargos
nuevos del ciclo normal (sí se le pueden seguir aplicando pagos).

Invariante: por tarjeta, existe exactamente UN `CardStatement` con
`status == 'open'` en todo momento (se crea uno junto con la tarjeta, o en
el primer `accrueCardCredit` si no existe).

### 3. `CardMovement` — ligado a un extracto, no a una fecha de corte

Reemplaza el campo `statementCutoff` (string) por:
- `statementId` (FK a `CardStatement.id`, NOT NULL para charge/payment/
  interest/fee creados desde esta versión en adelante — nullable solo para
  compatibilidad con filas migradas de antes de esta feature, ver
  migración).
- `installmentPurchaseId` (FK nullable a `InstallmentPurchase.id`) — solo
  presente en movimientos que son una cuota de una compra a plazos.

`chargeInstallments`/`installmentIndex` (ya existentes) se mantienen tal
cual, como metadata de display ("cuota 2 de 3"), ahora derivables también
desde `installmentPurchaseId` pero conservados por compatibilidad y para
no tener que hacer join solo para pintar un texto.

### 4. Transición de ciclo (reemplaza la lógica de cierre en `accrueCardCredit`)

Nueva función `closeCurrentCycleIfDue(CardCredit credit, [DateTime? now])`,
invocada desde donde hoy se invoca `accrueCardCredit` (incluye su lógica de
interés/cuota de manejo, ahora reescrita sobre el extracto abierto en vez
de sobre `currentBalance` directo):

Cuando el corte del extracto abierto ya pasó (mismo criterio ya corregido:
el corte pertenece al ciclo hasta las 23:59 de ese día, cierra recién al
día siguiente):

1. Aplica interés (sobre el `totalAmount` del extracto abierto al momento
   de cerrar) y cuota de manejo como `CardMovement`s ligados a ESE extracto
   (el que se está cerrando), igual que hoy.
2. Marca el extracto como `status = 'closed'` (o `'paid'` si su
   `totalAmount` calculado da 0 o menos).
3. Crea el SIGUIENTE extracto abierto: `openingBalance` = `totalAmount` del
   que se acaba de cerrar menos su `paidAmount`; `cutoffDate`/`dueDate`
   calculados igual que antes; `status = 'open'`.
4. Para cada `InstallmentPurchase` de esta tarjeta con
   `installmentsBilled < installments`: crea un `CardMovement` tipo
   `charge`, monto = `perInstallmentAmount` (o `lastInstallmentAmount` si
   es la última), ligado al extracto NUEVO recién creado y a esa
   `installmentPurchaseId`; incrementa `installmentsBilled`.
5. Repite si hay varios ciclos atrasados (igual que el `while` actual, con
   el mismo límite de seguridad de 36 iteraciones).

Esto resuelve directamente el problema que reportaste: cada cuota SÍ ocupa
su propio extracto, pero aparece en el momento correcto — cuando ese
extracto realmente abre — no como grupos fantasma de meses futuros
mezclados en la vista de Movimientos.

### 5. Pago — FIFO sobre extractos cerrados sin pagar

```
registerCardPayment(credit, amount):
  restante = amount
  # Primero, extractos CERRADOS sin pagar, del más antiguo al más reciente.
  for statement in credit.statements.where(status == 'closed').sortBy(cutoffDate):
    debido = totalAmount(statement) - statement.paidAmount
    si debido <= 0: continuar
    abono = min(restante, debido)
    statement.paidAmount += abono
    restante -= abono
    si restante == 0: salir
  # Si sobra después de cubrir todo lo cerrado, se aplica como pago
  # anticipado sobre el extracto ABIERTO (reduce lo que deberá al cerrar).
  si restante > 0:
    crear CardMovement(type: payment, amount: restante, statementId: openStatement.id)
```
Cada abono genera también un `CardMovement` tipo `payment` ligado al
extracto que recibió ese abono (para que el historial de Movimientos lo
muestre dentro del extracto correcto).

### 6. `currentBalance` — caché recalculada, nunca mutada a mano

Nueva función pura:
```
double computeCardTotalDebt(CardCredit credit) =>
    sum(statement.totalAmount - statement.paidAmount for statement in
        credit.statements where status != 'paid')
    + sum(installmentPurchase.remainingAmount for installmentPurchase in
        credit.installmentPurchases where installmentsBilled < installments)
```
`remainingAmount` de una compra a plazos = `totalAmount -
(perInstallmentAmount * installmentsBilled)` ajustado por si la última
cuota ya se facturó.

`CardCredit.currentBalance` pasa a ser un campo **de solo lectura desde el
punto de vista de negocio** — la única función autorizada a asignarlo es
`recomputeCardBalance(credit)`, llamada al final de CADA operación que
pueda haberlo cambiado (registrar cargo, pago, cerrar ciclo, borrar
movimiento). Ningún otro lugar hace `credit.currentBalance = ...`
directamente nunca más.

### 7. "Debes ya" / "pendiente de facturar"

```
PayableSummary:
  exigible = sum(totalAmount - paidAmount para extractos status == 'closed')
  dueDate  = fecha límite del extracto 'closed' sin pagar MÁS ANTIGUO
             (ese es el que vence primero — no el más reciente)
  pendienteFacturar = totalAmount del extracto ABIERTO
                     + suma de cuotas de InstallmentPurchase aún no facturadas
```

### 8. UI

- `movements_tab.dart`: agrupa por `statementId` directo (join simple, sin
  `cycleKeyFor`/`groupMovementsByCycle` para esto — el orden cronológico es
  gratis porque los extractos se crean en orden). El extracto abierto
  siempre aparece primero y expandido. Cuando una `InstallmentPurchase`
  tiene cuotas pendientes de facturar, se muestra una línea informativa
  "Próxima cuota: cuota 2 de 3 — $X el [mes]" dentro del extracto abierto
  o como nota aparte — NO como un grupo "EXTRACTO" futuro falso.
- `wallet_card.dart` / `credit_detail_screen.dart`: usan
  `computeCardTotalDebt` (vía `currentBalance` cacheado) para cupo
  disponible, y `getPayableSummary` para "debes ya" + fecha límite.

### 9. Migración de datos (schemaVersion sube, versión exacta a definir en
el plan según el valor actual del repo al momento de implementar)

1. Tabla nueva `InstallmentPurchases`.
2. `CardStatements`: agregar columnas que falten (`status` ya existe,
   verificar que admite `'open'`; si antes solo se usaba `'closed'`/`'paid'`,
   no hace falta migrar valores existentes, solo permitir el nuevo).
   Quitar el uso de `closingBalance` como valor autoritativo — se mantiene
   la columna por compatibilidad de lectura histórica pero el código nuevo
   no la usa para calcular `totalAmount` (se deriva de movimientos).
3. `CardMovements`: agregar `statementId`, `installmentPurchaseId`.
   Migración de datos best-effort en código de aplicación (no SQL puro, por
   la complejidad de la lógica): al cargar una tarjeta cuyos movimientos NO
   tienen `statementId` (datos de antes de esta versión), un paso de
   "backfill" bajo demanda:
   - Agrupa esos movimientos usando el `cycleKeyFor` + `statementCutoff`
     legado (el de la iteración anterior) para inferir a qué extracto
     deberían pertenecer.
   - Crea (o reutiliza si ya existe por `cutoffDate`) el `CardStatement`
     correspondiente y liga cada movimiento legado a él.
   - Esto corre UNA VEZ por tarjeta (flag o detección "tiene movimientos
     con statementId null"), dentro de `accrueCardCredit`/la función que lo
     reemplace, antes de aplicar cualquier lógica nueva.
4. Para cada tarjeta sin extracto abierto tras la migración, crear uno
   (usando `getCardCycleDates` para calcular el corte vigente).
5. Compras a plazos legadas: agrupar movimientos por
   (`chargeInstallments`, `installmentIndex`, mismo `note`+fecha de compra
   aproximada) para reconstruir un `InstallmentPurchase` best-effort por
   cada grupo de cuotas que comparten esos atributos. Si no se puede
   reconstruir con confianza (ambigüedad), dejar esos movimientos como
   cargos sueltos ligados a su extracto inferido, sin `InstallmentPurchase`
   asociado — no se pierden datos, solo no se benefician del
   auto-facturado futuro (ya no aplica, porque si son legados ya tienen
   todos sus movimientos creados).

## Review Focus

- **Tarjeta sin ningún extracto (recién creada, antes del primer
  `accrueCardCredit`)**: debe tener su extracto abierto creado
  inmediatamente al guardar la tarjeta, no esperar al primer launch de la
  app — de lo contrario, registrar un cargo antes de que exista el extracto
  abierto no tiene dónde engancharse.
- **Pago exacto que cierra todos los extractos cerrados y deja sobrante**:
  el sobrante debe aplicarse al extracto abierto como pago anticipado, no
  perderse ni quedar "flotando".
- **Compra a plazos registrada el mismo día que el corte**: la cuota 1 debe
  facturarse en el extracto que cierra ESE día (criterio ya unificado por
  `cycleKeyFor`), consistente con un cargo normal de 1 sola cuota el mismo
  día.
- **Migración de una tarjeta con muchos movimientos legados de compras a
  plazos ambiguas** (dos compras distintas con el mismo `chargeInstallments`
  y fecha): no debe fusionarlas en una sola `InstallmentPurchase`
  incorrecta — mejor dejarlas sin reconstruir (cargos sueltos) que
  reconstruir mal.
- **Eliminar la última cuota facturada de una `InstallmentPurchase`**: debe
  decrementar `installmentsBilled` para que, si el ciclo aún no cerró, no
  se pierda la oportunidad de volver a facturarla correctamente (o, más
  simple: documentar que borrar una cuota ya facturada dejará esa
  `InstallmentPurchase` con una cuota "saltada" permanentemente — decisión
  explícita a tomar en el plan, no implícita).
