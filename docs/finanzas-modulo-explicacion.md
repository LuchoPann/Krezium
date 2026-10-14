# Módulo Finanzas — explicación detallada del plan ejecutado

Este documento explica, fase por fase, qué se construyó a partir del
roadmap de 9 fases propuesto en `UltimoChatConGPT.md` (seguimiento en
`docs/finanzas-roadmap.md`), cómo quedó el flujo de la app y la lógica
exacta detrás de cada pieza. Es la referencia de "cómo funciona", no un
changelog — para el detalle de bugs encontrados en cada fase, ver los
documentos `docs/finanzas-faseNN-cierre.md` individuales.

## Índice de fases

| Fase | Qué entrega | Estado |
|------|-------------|--------|
| 00 | Auditoría técnica (solo lectura) | cerrada |
| 01 | Integridad financiera y cálculos | cerrada |
| 02 | Navegación y estructura de vistas | cerrada |
| 03 | Inicio financiero (Registros) | cerrada |
| 04 | Presupuestos | cerrada |
| 05 | Metas de ahorro | cerrada |
| 06 | Estadísticas | cerrada |
| 07 | Observaciones y sugerencias | cerrada |
| 08 | Funciones complementarias y pulido final | cerrada |

---

## Fase 00 — Auditoría técnica

Solo lectura: se recorrió el módulo tal como estaba antes de tocar nada,
para dejar un diagnóstico base. Encontró 7 bugs reales (no cosméticos),
el más importante: **las transferencias entre registros no movían
dinero** — se guardaba una fila `tipo:'transferencia'` en el registro
origen, pero `getFinanceTransactionsByLibro` filtraba solo por
`accountId`, así que el registro destino nunca la recibía, y como el
`tipo` no era `'ingreso'`/`'gasto'` tampoco se restaba del origen. Era
una anotación inerte.

También detectó que `FinanzasPresupuestoScreen` existía en el código pero
no estaba enrutada a ningún lado (pantalla huérfana, inalcanzable desde
la UI), que el saldo se calculaba en 3 lugares distintos sin un servicio
común, y que no había ni un solo test sobre saldo, transferencias o
presupuestos.

La auditoría dejó también preguntas de producto sin resolver, que las
fases 01 y 05 tuvieron que responder antes de poder avanzar: qué es
exactamente "dinero disponible", qué hacer con el campo `activa` de un
registro, y si el dinero "reservado" de una meta vive dentro del saldo de
un registro o aparte.

---

## Fase 01 — Integridad financiera y cálculos

Define el modelo de cálculo que todas las fases siguientes reutilizan.
Vive en `lib/domain/finance_ledger.dart`.

**Transferencias, arregladas de verdad:** una transferencia ahora sí
mueve dinero — resta del registro origen y suma al registro destino. El
cálculo de saldo de un registro ya no es "sumar/restar sus propias
filas", sino: `saldoInicial + ingresos − gastos + transferencias
recibidas − transferencias enviadas`.

**"Disponible" definido:** se introduce el concepto de dinero
*reservado* (tabla `FinanceReservations`, creada en esta fase para
proteger contra el borrado de un registro con compromisos encima).
`totalReservado` sobre un registro resta del saldo bruto lo que está
reservado, y ese es el número que la UI muestra como "disponible" —
nunca el saldo bruto directamente, para que una reserva (más adelante,
una meta) no se pueda gastar dos veces sin que el usuario lo note.

**Un único servicio de cálculo:** antes el saldo se calculaba en 3
archivos distintos (`finanzas_cuentas_screen.dart`,
`finanzas_libro_transacciones_screen.dart`,
`finanzas_estadisticas_screen.dart`), cada uno con su propia copia de la
regla. Fase 01 centraliza esto en `finance_ledger.dart` +
`financeAccountBalanceProvider` (Riverpod), así que una corrección de
regla contable se hace una sola vez y se propaga a toda la app.

---

## Fase 02 — Navegación y estructura de vistas

Define cómo se organiza la navegación interna de Finanzas: un `Stack`
indexado (no rutas con `Navigator.push` para las vistas principales) con
providers por entorno, de forma que cambiar de pestaña no reinicia el
estado de la pestaña anterior (por ejemplo, el filtro de período de
Estadísticas sobrevive si el usuario va a Registros y vuelve).

---

## Fase 03 — Inicio financiero (Registros)

Construye la pantalla principal de "Registros" (cuentas/libros): tarjetas
por cuenta con su saldo disponible (ya usando Fase 01), creación/edición
de registros, selector de color/ícono. En esta fase se tomó una decisión
de producto por pedido directo del usuario: se **retiró** un bloque de
resumen/observaciones que se había probado en esta pantalla ("solo es
relleno"), dejando la lobby enfocada solo en la lista de registros. Esta
decisión fue relevante más adelante (ver Fase 07): las observaciones no
podían volver a vivir aquí sin re-litigar algo que el usuario ya había
cerrado explícitamente.

---

## Fase 04 — Presupuestos

**Entidad:** un presupuesto es `{categoryId, monto límite, año, mes}`,
siempre sobre una **categoría padre** (no sobre una subcategoría) — el
selector de categoría de presupuesto solo ofrece las ~8 categorías padre
fijas + las que el usuario haya creado como padre. Esto es deliberado:
exponer las ~113 subcategorías en el picker de presupuestos lo haría
inusable.

**Por qué el roll-up es necesario:** las transacciones reales casi
siempre se registran contra una subcategoría (ej. "Restaurantes", hija de
"Comida"), nunca contra el padre. Si el consumo del presupuesto solo
contara transacciones con `categoryId` exactamente igual al del
presupuesto, el gasto real sería casi siempre 0% sin importar cuánto
gastara el usuario. La función `gastoCategoriaPeriodo` (en
`lib/domain/finance_budget.dart`) resuelve esto sumando tanto las
transacciones directas sobre esa categoría como las de cualquier
subcategoría cuyo `parentId` apunte a ella, vía un mapa
`parentPorCategoria` construido desde el catálogo combinado
(fijo + personalizado).

**Estados y umbrales** (`estadoPresupuesto`):
- `progreso = gasto / límite` (sin acotar a 1.0 — un presupuesto puede
  excederse, y el usuario sigue registrando gastos igual).
- `< 0.8` → `normal`.
- `0.8` a `< 1.0` → `cercano` ("cerca del límite").
- `≥ 1.0` → `agotado` (incluye excedido).

**Identidad del presupuesto:** la clave real es `(categoryId, año, mes)`,
no un ID autoincremental que la UI conozca de antemano. Por eso
`upsertFinanceBudget` primero busca si ya existe un presupuesto para esa
combinación exacta — si existe, actualiza esa fila; si no, inserta una
nueva. Antes de esta fase, `upsertFinanceBudget` intentaba hacer
`insertOnConflictUpdate` contra el `rowId`, que la UI nunca conocía al
crear/editar, así que cada "edición" insertaba una fila duplicada en vez
de actualizar.

**Regla de UI:** una vez creado un presupuesto, la categoría **no se
puede editar** — es la identidad del presupuesto, solo el monto límite es
editable. El picker de categoría al crear uno nuevo excluye las
categorías que ya tienen presupuesto ese mes (evita duplicados).

**Hallazgo fuera de alcance, documentado y no resuelto:** todo el módulo
Finanzas (cuentas, categorías, transacciones, presupuestos, reservas,
lugares, plantillas) está excluido del sistema de backup de la app — el
botón de exportar/importar solo serializa Créditos. Los modelos
`toJson`/`fromJson` de Finanzas existen pero no están conectados a ningún
flujo de exportación real.

---

## Fase 05 — Metas de ahorro

**Decisión de diseño central (la más importante del módulo):** el dinero
de una meta de ahorro **vive dentro del saldo del registro** donde se
creó la meta — no es plata aparte, ni un ingreso nuevo, ni se mueve entre
registros. Técnicamente, una meta reutiliza la tabla `FinanceReservations`
(creada en Fase 01 para proteger contra borrado de registros, pero sin
ninguna UI hasta esta fase) — se le agregaron las columnas
`montoObjetivo`, `fechaLimite` y `estado` (migración de schema v19→v20).

Esto cumple directamente la regla del roadmap: *"una meta es un objetivo
financiero, no un ingreso nuevo"* — evita contar el mismo dinero como
disponible en dos lugares a la vez. Como `totalReservado` (Fase 01) ya
restaba las reservas del saldo disponible, las metas heredan ese
comportamiento gratis: aportar a una meta no crea una transacción ni
cambia el saldo bruto del registro, solo mueve dinero de "disponible" a
"reservado" dentro del mismo registro.

**Operaciones sobre una meta:**
- **Aportar:** `puedeAportar(monto)` exige `monto > 0`. Solo incrementa el
  campo `monto` (aportado) de la reserva.
- **Retirar:** `puedeRetirar(monto, aportado)` exige `0 < monto ≤
  aportado` — nunca se puede retirar más de lo que la meta tiene aportado
  (eso liberaría dinero que nunca estuvo reservado).
- Ninguna de las dos operaciones genera una transacción de
  ingreso/gasto/transferencia. Son ajustes puros sobre el campo `monto`
  de `FinanceReservations`.

**Progreso y ritmo** (`lib/domain/finance_goal.dart`):
- `progresoMeta = aportado / objetivo` (sin acotar — puede pasar 100% si
  el usuario sigue aportando después de cumplida).
- `montoRestanteMeta` nunca es negativo (una meta cumplida no "debe"
  nada).
- `contribucionOrientativa`: calcula cuánto aportar por mes, en
  promedio, para llegar a la `fechaLimite`. Devuelve `null` en 3 casos
  donde no hay plazo real sobre el cual calcular un ritmo: sin fecha
  límite, con la fecha ya vencida, o sin nada pendiente por aportar.
  Redondea hacia arriba al centavo, y cuenta meses completos (si faltan
  menos de 1 mes completo, usa 1 para no dividir por 0).

**Estados de una meta** (`estado`: `activa | pausada | finalizada |
cancelada`) y su efecto sobre el dinero:
- **Cancelar** libera el dinero reservado de vuelta al disponible — el
  usuario se arrepintió del objetivo.
- **Finalizar** (meta cumplida) **no** libera nada automáticamente — el
  dinero sigue reservado hasta que el usuario lo retire explícitamente.
  Esto evita que marcar "listo" en una meta cambie el disponible del
  registro sin que el usuario lo pida.
- Este comportamiento obligó a corregir `totalReservado` (Fase 01): antes
  sumaba **todas** las reservas sin mirar su estado, así que cancelar una
  meta nunca liberaba realmente el dinero en el cálculo de disponible.
  Ahora filtra explícitamente las reservas con `estado == 'cancelada'`.

**Dónde vive en la navegación:** Presupuestos y Metas se unificaron bajo
un solo destino de navegación, **"Planificación"**
(`lib/screens/finanzas/finanzas_planificacion_screen.dart`), con un
selector de pestañas (`AppPillSelector`) entre "Presupuestos" y "Metas" —
siguiendo la arquitectura que el propio GPT describió ("Planificación:
presupuestos y metas de ahorro" como un solo destino, no dos).

---

## Fase 06 — Estadísticas

Mandato explícito honrado: mantener el donut de gastos por categoría y
la barra de tendencia mensual tal como estaban visualmente; solo se
agregó interacción encima.

**Comparación con el mes anterior** (`comparacionPeriodoAnterior`, en
`finance_ledger.dart`): compara el gasto `actual` contra el `anterior`.
Devuelve `null` cuando no hay base real de comparación (`anterior ≤ 0` —
no hay un "más/menos %" significativo contra cero). Se muestra **solo**
cuando el período activo es "Este mes" — comparar "3 meses"/"6 meses"
contra un bloque anterior de igual longitud se consideró ambiguo y se
dejó fuera a propósito.

**Drill-down desde el donut:** cada entrada de la leyenda del pastel
(excepto "Otros", que agrupa varias categorías y no tiene un único
destino de filtro) es tocable — navega al historial de transacciones de
ese registro, ya filtrado por esa categoría exacta
(`FinanzasFiltros.categoriaId`). El filtro se limpia automáticamente
(`limpiarCategoria: true`) cuando el usuario entra al historial por la
vía normal (tocando un registro), para que un filtro de una visita
anterior a Estadísticas no persista de forma invisible.

---

## Fase 07 — Observaciones y sugerencias

**Principio de diseño, textual del roadmap:** *"primero una capa
determinista basada en reglas locales, no un sistema que invente
conclusiones"*. Cada regla de `lib/domain/finance_observaciones.dart`
devuelve una lista **vacía** cuando no hay evidencia suficiente — nunca
fabrica algo para rellenar espacio.

**Las 3 reglas:**
1. **`observacionesAumentoCategoria`** — compara gasto por categoría del
   mes actual vs. el anterior (del libro activo). Exige **ambos**
   umbrales a la vez: ≥30% de aumento **y** ≥$50.000 de diferencia
   absoluta — evita marcar como alerta algo como "$1.000 → $3.000" (+200%
   pero insignificante en pesos reales). Ordenadas por % de aumento,
   mayor primero.
2. **`observacionesPresupuestoCercano`** — reutiliza el mismo umbral
   ≥80% de `estadoPresupuesto` (Fase 04). Ordenadas por progreso, mayor
   primero.
3. **`observacionesMetaFueraDeRitmo`** — compara el progreso real de una
   meta (`aportado/objetivo`) contra el progreso *esperado* según cuánto
   tiempo ha pasado desde que se creó hasta su `fechaLimite`. Solo
   dispara si el atraso supera 15 puntos porcentuales. Se salta metas sin
   `fechaLimite`, ya cumplidas, o que no estén `activa`.

**Dónde viven las observaciones:** dentro de **Estadísticas**, no en la
lobby de Registros. Esta fue la decisión más delicada del roadmap:
Fase 03 ya había retirado un bloque de resumen de la lobby por pedido
explícito del usuario ("solo es relleno"). Re-litigar esa decisión sin
poder confirmar con el usuario (construido de madrugada, mientras
dormía) se consideró el riesgo más alto de esta fase — Estadísticas ya
era la pantalla designada para "entender cambios", así que las
observaciones se quedan ahí, completamente ocultas cuando ninguna regla
encuentra evidencia.

**Pendiente, documentado y no resuelto:** no existe un mecanismo de
"descartar"/"ya vista" — una observación que sigue siendo válida reaparece
en cada recálculo. Posible mejora futura si resulta molesto en uso real.

---

## Fase 08 — Funciones complementarias y pulido final

**Recurrencia — evaluada, no construida (decisión explícita):** los
campos `esRecurrente`/`recurrenciaConfig` existen en la tabla desde antes
de este roadmap, pero nunca tuvieron UI. Construir un motor real de
transacciones recurrentes (cuándo generar, cómo evitar duplicados si el
usuario abre la app varios días seguidos, notificaciones) implica
decisiones de producto no aprobadas, y el roadmap pedía explícitamente
*"evaluar... cuando resulte compatible"*, un verbo más débil que
"implementar". Se dejó fuera a propósito; los campos existentes son
compatibles con una futura implementación sin otra migración.

**Bugs reales encontrados y corregidos** — un mismo patrón repetido en 4
lugares distintos: código que resolvía una categoría buscando solo en el
catálogo **fijo** (`catalogoFinanzas`/`todoCatalogo`), nunca en el
catálogo **combinado** (fijo + personalizado,
`allFinanceCategoriesProvider`) que el resto del módulo ya usa desde que
existen categorías personalizadas:
1. **`nueva_transaccion_sheet.dart`** — editar una transacción o usar una
   plantilla con categoría personalizada dejaba el selector de categoría
   vacío en silencio. Si el usuario guardaba sin notarlo, el código
   mandaba `categoryId: _categoriaSeleccionada?.id ?? 'transferencia'` —
   **sobrescribía la categoría real con el placeholder de
   transferencia**: pérdida de dato real, no solo visual.
2. **`editar_plantilla_sheet.dart`** — mismo patrón, pero el fallback era
   `?? ''`, así que **vaciaba** el `categoryId` de la plantilla.
3. **`finanzas_plantillas_screen.dart`** — una plantilla con categoría
   personalizada se mostraba sin nombre ni ícono (sin pérdida de dato,
   solo visual).
4. **`finanzas_libro_transacciones_screen.dart`** — el nombre de la
   categoría padre en el subtítulo de cada movimiento se buscaba solo en
   las 8 categorías padre fijas, nunca en una padre personalizada.

También un bug de navegación separado: el buscador del historial
(`_BusquedaSheet`) abría un formulario de transacción **en blanco** al
tocar un resultado, ignorando la transacción tocada — corregido para
abrir esa transacción en modo edición. De paso, el buscador ahora también
filtra por nombre de categoría (antes solo nota/ordenante/monto/fecha).

**Verificado sin cambios necesarios:** migraciones de schema (cobertura
pairwise existente, v14→v20, todas verdes), regresión de Créditos
(suite completa verde en cada corrida), valores extremos (sin límite
práctico real en `NumberFormat`/`int` de Dart), accesibilidad/consistencia
visual (revisado a nivel de lectura de código, no auditoría profunda —
el resto de la app tampoco la tiene).

---

## Flujo de datos end-to-end (resumen técnico)

1. **Tablas** (`lib/data/db/tables_finance.dart`): `FinanceAccounts`
   (registros/libros), `FinanceTransactions` (ingreso/gasto/transferencia),
   `FinanceCategories` (categorías personalizadas — el catálogo fijo vive
   en código, no en DB), `FinanceBudgets`, `FinanceReservations` (metas),
   `FinancePlaces` (autocompletado de lugares/personas), `FinanceTemplates`.
2. **Dominio** (`lib/domain/finance_*.dart`): funciones puras, sin
   estado, sin DB — `finance_ledger.dart` (saldo, totales, comparaciones),
   `finance_budget.dart` (presupuestos), `finance_goal.dart` (metas),
   `finance_observaciones.dart` (reglas de alerta). Todas con tests
   unitarios dedicados.
3. **Providers** (`lib/providers/finance_provider.dart` +
   `database_provider.dart`): Riverpod conecta la capa de dominio con la
   DB real (Drift/SQLite) y expone el estado reactivo a la UI
   (`financeAccountBalanceProvider`, `financeBudgetsProvider`,
   `allFinanceReservationsProvider`, etc.).
4. **UI** (`lib/screens/finanzas/*.dart`): consume los providers,
   nunca recalcula reglas de negocio por su cuenta — todo cálculo
   (saldo, progreso, estado, observación) pasa por la capa de dominio.

Esta separación es la que permitió, por ejemplo, que el fix de
`totalReservado` en Fase 05 (filtrar `cancelada`) se propagara
automáticamente a toda pantalla que muestra "disponible", sin tocar una
sola línea de UI.
