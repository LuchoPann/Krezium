# Planificación v2 — Presupuestos guiados y Metas con 2 modalidades

**Fase del roadmap:** Fase A de `docs/finanzas-v2-roadmap.md` (spec).
Siguiente paso tras aprobar esta spec: `writing-plans` para la Fase B
(implementación). No cubre Registros ni Estadísticas — esas son las
Fases C/E, con sus propias specs, apoyadas en lo que esta define.

**Origen:** propuesta funcional de GPT (resumen de la conversación),
preferencias del usuario (presupuestos guiados, metas con ambas
modalidades) y decisiones tomadas en brainstorming, una por una, listadas
abajo. Contrastada contra la implementación real de Fases 00-08
(`docs/finanzas-fase0{4,5}-cierre.md`, `lib/domain/finance_budget.dart`,
`lib/domain/finance_goal.dart`, `lib/data/db/tables_finance.dart`).

## Decisiones cerradas en brainstorming

1. Déficit de disponible (reservas > disponible real): **solo avisar**,
   nunca ocultar el déficit como si fuera disponible real.
2. Presupuestos: **un solo nivel** (categoría padre) en esta spec — el
   solapamiento general/específico queda fuera, es una iteración futura
   con su propia spec si se confirma que hace falta.
3. Sugerencia de límite: mediana de gasto mensual de los últimos 3 meses
   del calendario, pero **solo si al menos 2 de esos 3 meses tienen algún
   gasto registrado** en esa categoría (roll-up a subcategorías incluido).
   Con menos de 2 meses con datos, no se sugiere nada — campo vacío, sin
   mensaje de aviso.
4. Metas: **ambas modalidades** — virtual (sin cuenta, descuenta del
   disponible global) y vinculada (a una cuenta específica, como ya
   funciona hoy). Requiere `accountId` nullable en `FinanceReservations`.
5. Historial de aportes/retiros: se agrega una tabla nueva
   (`FinanceGoalMovements`) — hoy `FinanceReservations.monto` es solo un
   acumulado, no permite reconstruir el historial.
6. Completar una meta: Krezium **pregunta explícitamente** qué hacer con
   el dinero (ya no queda reservado en silencio). Mismo flujo para
   cancelar.
7. El flujo de cierre (completar/cancelar) tiene 2 caminos:
   **gasto inmediato** (crea una transacción de gasto real, categoría
   elegida por el usuario en ese momento) o **mantener en un registro**
   (existente o nuevo, con nota automática "Proveniente de meta:
   {nombre}").
8. Meta vinculada a una cuenta que se intenta borrar: se bloquea el
   borrado (ya existe el mecanismo `onDelete: restrict`) mientras la meta
   esté activa o pausada; se ofrece reasignar a otra cuenta o convertir a
   virtual antes de poder borrar esa cuenta.
9. Alertas de presupuesto: se suma una señal de **ritmo** (gasto
   acumulado vs. tiempo transcurrido del periodo) junto a los umbrales de
   % ya existentes — es aditiva, no reemplaza `normal`/`cercano`/`agotado`.

## Global Constraints

- No se toca Créditos ni su cálculo — Finanzas y Créditos permanecen
  aislados salvo integración futura explícita.
- Las transferencias entre cuentas propias nunca son ingreso ni gasto
  (ya correcto desde Fase 01, no se modifica).
- Los aportes/retiros de metas nunca son transacciones de
  ingreso/gasto/transferencia — son ajustes internos sobre la reserva
  (ya correcto desde Fase 05, no se modifica salvo el registro en el
  nuevo historial).
- Un gasto se contabiliza una sola vez en los totales generales (no
  aplica aún el riesgo de doble conteo de presupuestos solapados, porque
  esta spec no los incluye).
- Todo cambio de schema requiere migración con test de migración real
  (patrón ya usado en v19→v20: abrir una DB recortada a la versión
  anterior, correr `onUpgrade`, verificar que los datos viejos sobreviven
  y las columnas nuevas tienen defaults seguros).
- Ningún dato histórico (transacciones, metas, presupuestos ya creados)
  se pierde ni se reescribe por esta migración. Las metas existentes
  quedan con `modalidad = 'vinculada'` por default (su `accountId` ya
  existe), de forma que el comportamiento actual no cambia para nadie que
  ya tenga metas creadas.
- La app sigue funcionando 100% offline — nada de esta spec depende de
  red.

## 1. Presupuestos guiados

### 1.1 Flujo de creación

Reemplaza el formulario plano actual (`_PresupuestoFormSheet`) por un
flujo de 4 pasos + confirmación, dentro de la misma hoja (bottom sheet),
sin pantallas nuevas:

1. **Elegir categoría.** Picker de categorías padre (fijas + las que el
   usuario haya creado como padre), igual que hoy — excluye las que ya
   tienen presupuesto ese mes/año. Bajo cada opción del picker se muestra
   el gasto de esa categoría en el mes actual (roll-up a subcategorías),
   si tiene alguno.
2. **Revisar sugerencia.** Se calcula la mediana del gasto mensual de los
   últimos 3 meses de calendario completos (sin contar el mes en curso)
   para esa categoría. Se sugiere solo si **al menos 2 de esos 3 meses**
   tienen gasto > 0 registrado en esa categoría. Si se sugiere, se
   muestra el monto y una línea explicando el origen ("Basado en tus
   últimos 3 meses: {mes1} ${...}, {mes2} ${...}, {mes3} ${...}"). Si no
   se sugiere, el campo de límite aparece vacío, sin mensaje de "sin
   datos" — simplemente no hay valor precargado.
3. **Ajustar el límite.** Campo numérico editable (reutiliza
   `MontoInputFormatter`), precargado con la sugerencia si existe. Debajo,
   en vivo mientras el usuario edita: gasto ya acumulado este mes en esa
   categoría (si el periodo ya empezó) y lo que quedaría disponible con
   el límite actual.
4. **Confirmar.** Resumen de categoría, periodo (mes actual, no
   editable en esta spec — la repetición/plantilla para meses futuros
   queda fuera), límite elegido, gasto ya acumulado. Botón "Crear
   presupuesto" guarda.

El picker del paso 1 y el guardado final usan las mismas funciones ya
existentes (`upsertFinanceBudget`, identidad `(categoryId, año, mes)`) —
no cambia la capa de datos de presupuestos, solo el flujo de UI que llega
a ella.

### 1.2 Función de sugerencia (dominio)

Nueva función en `lib/domain/finance_budget.dart`:

```dart
/// Sugerencia de límite para [categoryId]: mediana del gasto mensual de
/// los últimos 3 meses de calendario completos (anteriores al mes de
/// [hoy]), contando roll-up a subcategorías vía [parentPorCategoria].
/// Devuelve null si menos de 2 de esos 3 meses tienen gasto > 0 — no hay
/// base suficiente para sugerir sin inventar un número.
({double sugerido, List<({int year, int month, double monto})> meses})?
    sugerenciaPresupuesto({
  required String categoryId,
  required List<FinanceTransaction> transacciones,
  required Map<String, String?> parentPorCategoria,
  required DateTime hoy,
})
```

Implementación: para cada uno de los 3 meses anteriores a `hoy.month`,
suma gasto con `gastoCategoriaPeriodo` restringido a ese mes. Cuenta
cuántos de esos 3 montos son > 0; si son ≥ 2, la mediana de los 3 valores
(incluyendo los que sean 0) es el sugerido. Devuelve también el desglose
mes a mes para mostrar la explicación en el paso 2.

### 1.3 Ritmo de presupuesto (señal adicional, no reemplaza estados)

Nueva función en `lib/domain/finance_budget.dart`:

```dart
/// true si el presupuesto va "más rápido de lo esperado": el % del
/// límite ya consumido supera el % del periodo ya transcurrido por más
/// de [margen] puntos porcentuales (default 0.15, mismo criterio que
/// observacionesMetaFueraDeRitmo). No aplica si el presupuesto ya está
/// en estado agotado (ahí la alerta de "agotado" ya es suficiente).
bool vaRapido({
  required double progreso,       // gasto/límite, de progresoPresupuesto
  required DateTime inicioPeriodo,
  required DateTime finPeriodo,
  required DateTime hoy,
  double margen = 0.15,
})
```

Se usa así: `fraccionTranscurrida = (hoy - inicioPeriodo) / (finPeriodo -
inicioPeriodo)`, clamp a `[0, 1]`. `vaRapido = progreso < 1.0 && progreso
- fraccionTranscurrida > margen`.

En la UI, la tarjeta de presupuesto (ya existente, sin cambios
estructurales) agrega un texto corto cuando `vaRapido == true`: "Vas más
rápido de lo esperado para este punto del mes" — no cambia el color ni el
badge de estado (`normal`/`cercano`/`agotado` siguen siendo los mismos 3,
calculados igual que hoy).

## 2. Metas con 2 modalidades

### 2.1 Cambios de schema (migración nueva, v20→v21)

`FinanceReservations`:
- `accountId`: pasa de `text().references(...)` (NOT NULL) a
  `text().nullable().references(...)`.
- Nueva columna `modalidad`: `text().withDefault(const
  Constant('vinculada'))()`. Valores: `'virtual'` | `'vinculada'`. Toda
  fila existente recibe `'vinculada'` por el default — su `accountId` ya
  tiene un valor real, así que el comportamiento no cambia para metas
  creadas antes de esta migración.

Nueva tabla `FinanceGoalMovements`:
```dart
class FinanceGoalMovements extends Table {
  TextColumn get id => text()();
  TextColumn get goalId =>
      text().references(FinanceReservations, #id, onDelete: KeyAction.cascade)();
  TextColumn get tipo => text()(); // 'aporte' | 'retiro'
  RealColumn get monto => real()();
  TextColumn get fecha => text()(); // ISO8601
  RealColumn get saldoResultante => real()(); // monto acumulado de la meta tras esta operación

  @override
  Set<Column> get primaryKey => {id};
}
```

Test de migración real obligatorio (mismo patrón que v19→v20): crear DB
v21 con una meta vinculada existente, recortar a v20 (quitar `modalidad`,
quitar tabla `FinanceGoalMovements`, forzar `accountId` NOT NULL),
reabrir con `AppDatabase.forTesting`, verificar que la meta sobrevive con
`modalidad = 'vinculada'` y que la tabla nueva es usable.

### 2.2 Disponible global y disponible por registro

Nueva función en `lib/domain/finance_ledger.dart`:

```dart
/// Suma de reservas activas (no canceladas) con modalidad == 'virtual' —
/// se resta del disponible GLOBAL (todas las cuentas), no del de un
/// registro puntual.
double totalReservadoVirtual(List<FinanceReservation> reservas)
```

`totalReservado` (ya existente, por registro) se mantiene igual pero
**filtra también por modalidad vinculada** — una reserva virtual nunca
debe descontarse del disponible de una cuenta específica, solo del
global.

El disponible global (suma de saldos de todos los registros, menos
reservas virtuales) es un cálculo nuevo que se usará en la pantalla de
Planificación — no reemplaza el disponible por registro que ya se
muestra en Registros/Estadísticas.

**Regla de déficit:** si `totalReservadoVirtual > disponible global
bruto`, el disponible global se muestra igual (puede quedar negativo o
con una etiqueta "déficit: $X"), nunca se trunca a 0 ni se oculta la
diferencia.

### 2.3 Creación de una meta

Flujo de 3 decisiones + confirmación:

1. **Objetivo.** Nombre, monto objetivo, fecha límite opcional (igual
   que hoy).
2. **Modalidad.** Elegir "virtual" o "vinculada a una cuenta" (si
   vinculada, selector de registro — igual al que ya existe hoy, porque
   hoy toda meta es vinculada). La modalidad es la identidad de la meta:
   **no se puede cambiar después de creada** (mismo criterio que la
   categoría de un presupuesto) — si el usuario se equivoca, debe
   cancelar y crear una nueva.
3. **Aporte inicial opcional.** Puede crear la meta con $0 y aportar
   después.
4. **Confirmar.** Resumen: nombre, objetivo, modalidad, fecha si existe,
   aporte inicial si lo hay.

### 2.4 Aportar y retirar (con historial)

Mecánica de validación sin cambios (`puedeAportar`, `puedeRetirar`, ya
existentes). Lo nuevo: cada aportar/retirar exitoso inserta una fila en
`FinanceGoalMovements` con `tipo`, `monto`, `fecha` (ahora), y
`saldoResultante` (el `monto` de la meta después de aplicar la
operación). La tarjeta de detalle de la meta agrega una sección
"Historial" listando estas filas, más reciente primero — de solo
lectura, no editable ni borrable individualmente.

### 2.5 Completar y cancelar — flujo de cierre compartido

Ambas acciones (hoy botones separados en el menú de la meta) abren el
mismo diálogo de cierre, con una sola diferencia de encabezado
("¿Completar esta meta?" / "¿Cancelar esta meta?"):

**Paso único: ¿qué hacer con los ${monto reservado}?**
- **Opción A — Gasto inmediato.** Abre el formulario de nueva transacción
  ya existente (`nueva_transaccion_sheet.dart`), tipo gasto, monto
  precargado con el total reservado, registro destino = el de la meta si
  es vinculada, o a elegir si es virtual. El usuario elige la categoría
  ahí mismo. Al guardar, la reserva se cierra (deja de existir / pasa a
  `estado = 'cancelada'` o `'finalizada'` según la acción origen).
- **Opción B — Mantener en un registro.** Selector: "este registro" (si
  vinculada) / elegir uno existente / crear uno nuevo (nombre, mismo
  flujo corto que crear un registro desde Registros). El monto se suma al
  saldo de ese registro (ajuste directo, no transacción) y se guarda una
  nota automática en ese registro: *"Proveniente de meta: {nombre}"* (se
  persiste en un campo de nota del registro o como entrada liviana en su
  historial — a definir en la etapa de plan técnico, cualquiera de las
  dos cumple el requisito de trazabilidad).
- Cualquiera de las dos opciones cierra la reserva: dejará de contar en
  `totalReservado`/`totalReservadoVirtual` desde ese momento.
- Si el usuario cierra el diálogo sin elegir, la acción (completar/
  cancelar) no se aplica — el dinero sigue reservado como antes. No hay
  un tercer camino "silencioso".

### 2.6 Cuenta vinculada: borrado protegido

Sin cambios respecto al mecanismo ya existente (`onDelete: restrict` en
`FinanceReservations.accountId`) — se extiende la UI: al intentar borrar
un registro que tiene una meta vinculada con `estado` `activa` o
`pausada`, el diálogo de error ofrece un atajo directo a esa meta con dos
acciones: "Reasignar a otra cuenta" (cambia `accountId` a otro registro,
permitido porque no es la identidad completa de la meta — la modalidad
sigue siendo "vinculada") o "Convertir a virtual" (pone `accountId =
null`, `modalidad = 'virtual'`). Una meta `finalizada`/`cancelada` no
bloquea el borrado (ya cerró su reserva en 2.5).

## Review Focus

- **Meta virtual sin ninguna cuenta con saldo suficiente:** el disponible
  global debe mostrar el déficit explícitamente, nunca ocultar que la
  reserva excede lo realmente disponible. Cubierto en 2.2.
- **Presupuesto sin datos suficientes para sugerir (0 o 1 mes con
  gasto):** el campo de límite debe quedar vacío sin mensaje de error
  invasivo, nunca mostrar una sugerencia de $0 como si fuera real.
  Cubierto en 1.2.
- **Cerrar una meta (completar/cancelar) y cerrar el diálogo sin
  elegir opción:** la reserva debe seguir intacta, sin aplicar un cierre
  parcial. Cubierto en 2.5.
- **Migración v20→v21 sobre una DB con metas ya creadas antes de esta
  spec:** deben sobrevivir con `modalidad = 'vinculada'` y su `accountId`
  original, sin requerir que el usuario las reconfigure. Cubierto en 2.1.
- **Presupuesto con `vaRapido == true` pero ya en estado `agotado`:** no
  debe mostrar el texto de ritmo además del badge de agotado — sería
  ruido redundante. Cubierto en 1.3 (la condición excluye `progreso >=
  1.0`).

## Fuera de alcance de esta spec

- Presupuestos de dos niveles (general + específico) — decisión 2.
- Repetir/plantillar un presupuesto para el mes siguiente.
- Conexión con Registros (crear presupuesto desde un gasto, mostrar
  estado del presupuesto al registrar) — es la Fase C.
- Rediseño de Estadísticas (panorama, evolución, hallazgos) — es la
  Fase E.
- Backup del módulo Finanzas — pendiente transversal, fuera de este
  roadmap.
- Dismiss/seen de observaciones (Fase 07) — no tocado aquí.
