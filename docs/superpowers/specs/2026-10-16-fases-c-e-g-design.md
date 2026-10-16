# Fases C, E, G — conexión Registros↔Planificación, Estadísticas, pulido final

**Fase del roadmap:** C, E, G de `docs/finanzas-v2-roadmap.md`. Fase A/B
(Planificación guiada) ya cerradas. El usuario autorizó ejecutar las 3
fases seguidas, con validación manual suya al final vía un roadmap de
testeo (documento aparte, entregado al cerrar G).

**Origen:** diseño condensado aprobado en brainstorming (sección 4 de la
propuesta original de GPT: Registro↔Presupuesto, Presupuesto↔Registros,
Estadística↔Registro, Ingreso↔Meta) + sección 5 de esa misma propuesta
(Estadísticas: resumen de periodo, evolución, distribución, hallazgos) —
contrastado contra lo que Fase 06/07 ya construyeron, para no duplicar.

## Decisiones ya cerradas (brainstorming)

1. Resumen de presupuesto al elegir categoría en Nueva Transacción:
   compacto, nunca bloquea el guardado, acción discreta "crear
   presupuesto" si no existe.
2. Drill-down Presupuesto → Registros reusa el patrón ya existente
   (filtro por categoría en `finanzas_libro_transacciones_screen.dart`,
   mismo que usa el pastel de Estadísticas desde Fase 06).
3. Ingreso → Meta: atajo discreto y opcional tras guardar un ingreso,
   nunca automático, nunca altera la transacción real.
4. Edición/eliminación de movimientos: verificar con test que el
   recálculo de presupuestos ya es correcto (providers invalidados), no
   se espera código nuevo salvo que el test revele lo contrario.

## Global Constraints

(hereda las de `docs/superpowers/specs/2026-10-14-planificacion-v2-design.md`)
- Ningún atajo de esta fase crea una transacción fuera del flujo normal
  de `nueva_transaccion_sheet.dart` ni una reserva fuera del flujo normal
  de `_AportarRetirarSheet`.
- Ningún resumen de presupuesto bloquea guardar un gasto, ni siquiera
  excedido.
- `dart analyze` limpio y suite completa verde antes de cerrar cada tarea.
- Nunca `flutter run`.

## Fase C — Conexión Registros ↔ Planificación

### C1. Resumen de presupuesto en Nueva Transacción

Al elegir una categoría de tipo gasto en el paso 2 del formulario, debajo
del selector de categoría se muestra, si existe un presupuesto para esa
categoría (padre o resuelta vía `parentId`) en el mes de la fecha de la
transacción:
- Gastado hasta ahora / límite / restante (reusa `gastoCategoriaPeriodo`,
  `saldoPresupuesto`, `estadoPresupuesto` — sin cálculos nuevos).
- Si el presupuesto no existe: texto-acción "Crear presupuesto para
  {categoría}" que abre `_PresupuestoFormSheet` (ya construido en Fase A)
  con esa categoría preseleccionada, sin cerrar el formulario de
  transacción detrás (se abre como sheet apilado).
- Si excede el límite: el texto cambia de color (mismo rojo que usa
  `EstadoPresupuesto.agotado` en la tarjeta de presupuesto) pero el botón
  de guardar sigue habilitado igual que siempre.

### C2. Drill-down Presupuesto → Registros

La tarjeta de presupuesto (`_BudgetCard` en
`finanzas_presupuesto_screen.dart`) gana una acción "Ver movimientos" que
navega a `FinanzasLibroTransaccionesScreen` con
`finanzasFiltrosProvider.categoriaId` seteado a la categoría del
presupuesto — mismo patrón ya usado por el drill-down del pastel de
Estadísticas (Fase 06). Como un presupuesto es global (no por registro),
el filtro se aplica sobre el registro que el usuario elija primero (un
selector simple si hay más de un registro, o directo si solo hay uno).

### C3. Ingreso → Meta

Al guardar exitosamente una transacción tipo ingreso
(`nueva_transaccion_sheet.dart`, mismo punto donde hoy se dispara
`HapticFeedback.mediumImpact()` antes de cerrar), si existen metas
`activa` se muestra un `SnackBar` con acción "Apartar a una meta" que
abre `_AportarRetirarSheet` para que el usuario elija la meta y confirme
el monto (precargado con el monto del ingreso, editable). Si no hay
ninguna meta activa, no se muestra nada — nunca un flujo que presiona a
crear una meta en medio de registrar un ingreso.

### C4. Verificación de recálculo tras editar/eliminar

Test de regresión en `test/domain/finance_budget_test.dart` o
`test/providers/` (a decidir según dónde viva mejor): simula editar el
`categoryId` de una transacción ya contabilizada en un presupuesto y
confirma que `gastoCategoriaPeriodo` sobre la lista actualizada refleja
el cambio sin necesitar tocar el presupuesto. Si el test pasa sin cambios
de código, se documenta como verificado; si falla, se corrige el bug real
encontrado.

## Fase E — Estadísticas: lo que falta sobre lo ya construido

Fase 06/07 ya entregaron: donut + leyenda tocable, barra de tendencia
mensual, comparación vs. mes anterior, observaciones deterministas
(aumento de categoría, presupuesto cercano, meta fuera de ritmo), hero de
resumen (Fase de rediseño visual de esta misma conversación). Lo que
falta de la propuesta de GPT y no se solapa:

### E1. Tasa de ahorro en el resumen hero

Nueva función en `lib/domain/finance_ledger.dart`:
```dart
/// % de los ingresos que no se gastó: (ingresos - gastos) / ingresos.
/// null si no hay ingresos registrados en el periodo — mostrar un 0%
/// ahí sería engañoso (no es que no se ahorró nada, es que no hay base).
double? tasaAhorro({required double ingresos, required double gastos})
```
Se agrega como cuarto dato en `_ResumenHero`
(`finanzas_estadisticas_screen.dart`), sin romper el layout de 2 columnas
existente (Ingresos/Gastos) — va como línea adicional bajo la barra,
mismo patrón visual que el resto del hero.

### E2. Variación por categoría en la lista del pastel

La leyenda del donut (`_PieLegendItem`) gana la variación vs. el mismo
mes anterior, cuando ambos periodos tienen datos — reusa
`comparacionPeriodoAnterior` (ya existe desde Fase 06), por categoría en
vez de total. No se muestra variación si el periodo anterior tiene 0 en
esa categoría (regla ya establecida en `comparacionPeriodoAnterior`: sin
base, sin %).

### E3. Acceso directo a un presupuesto desde su categoría en el pastel

Al tocar una entrada de la leyenda que además tiene presupuesto asignado
este mes, se agrega una segunda acción (ícono pequeño) que navega
directo a `FinanzasPlanificacionScreen` en vez de (o además de) al
historial filtrado — ambos accesos conviven: tocar el texto filtra
historial (ya existe), tocar el ícono de presupuesto va a Planificación.

## Fase G — Pulido y pruebas integrales

No agrega funciones nuevas. Consiste en:
- Revisar estados vacíos de las pantallas tocadas en C/E (sin
  presupuestos, sin metas activas, sin ingresos del periodo) — mensajes
  claros, nunca un hueco en blanco.
- Confirmar `dart analyze` limpio y suite completa verde en el estado
  final de todo el roadmap v2 (A a F).
- Entregar el documento `docs/finanzas-v2-roadmap-testeo.md`: un roadmap
  de testeo manual, fase por fase, para que el usuario valide con datos
  reales en su dispositivo (ningún paso de esto lo ejecuta el asistente —
  es la guía que el usuario sigue él mismo, ya que el asistente nunca usa
  `flutter run`).

## Review Focus

- Resumen de presupuesto con una categoría que NO tiene presupuesto este
  mes pero sí en meses anteriores: no debe mostrar datos de otro mes como
  si fueran del actual. Cubierto en C1 (`financeBudgetsProvider((anio,
  mes))` ya es mes-específico).
- Atajo "Apartar a una meta" tras un ingreso cuando el usuario tiene
  metas pero todas `pausada`/`finalizada`/`cancelada`: no debe aparecer
  (solo `activa`). Cubierto en C3.
- Tasa de ahorro con gastos > ingresos (número negativo): debe mostrarse
  tal cual (negativo), nunca clamp a 0 — es información real de que se
  gastó más de lo que entró. Cubierto en E1 (`tasaAhorro` no clampa).
- Variación por categoría cuando la categoría es nueva este mes (no
  existía el mes anterior): debe comportarse igual que "sin base" — sin
  %, no un falso "+100%" desde 0. Cubierto en E2 (reusa
  `comparacionPeriodoAnterior`, ya maneja `anterior <= 0`).
- Drill-down de presupuesto cuando el usuario tiene un solo registro:
  no debe mostrar un selector de registro innecesario — ir directo.
  Cubierto en C2.

## Fuera de alcance

- Presupuestos de dos niveles (general+específico) — sigue fuera, igual
  que en la spec de Fase A.
- Backup del módulo Finanzas — pendiente transversal, no se toca aquí.
- Dismiss/seen de observaciones — no se toca aquí.
- Proyecciones futuras de gasto — explícitamente descartado por GPT en
  su propuesta original ("no dibujaría proyecciones... sin un modelo
  confiable").
