# Fase 05 — Metas de ahorro (cierre)

**Estado:** cerrada. Suite completa: 327/327.

## Decisión de representación del dinero reservado

El dinero de una meta **vive dentro del saldo del registro donde se creó** —
nunca se mueve a otro registro, nunca genera un ingreso ni un gasto. Esta
decisión aprovecha `FinanceReservations`, una tabla creada en Fase 01 para
proteger cuentas con dinero apartado al eliminarlas, pero que hasta ahora no
tenía ninguna UI — quedó completamente inaccesible para el usuario.

- **Aportar** a una meta: solo aumenta `monto` (lo aportado) en la reserva.
  No crea ninguna transacción, no es un ingreso.
- **Retirar**: solo disminuye `monto`. Nunca puede superar lo ya aportado
  (`puedeRetirar`).
- El saldo "disponible" de un registro ya restaba las reservas desde Fase 01
  (`totalReservado` → `calcularDisponibleEstimado`) — las metas heredan ese
  comportamiento sin cambios adicionales: una meta activa reduce el
  disponible automáticamente, nunca infla ingresos ni duplica el conteo.
- **Cancelar** una meta libera el dinero (`totalReservado` ahora excluye
  `estado == 'cancelada'`, antes sumaba todo sin filtrar).
- **Finalizar** una meta (objetivo cumplido) *no* libera el dinero — sigue
  reservado hasta que el usuario lo retire explícitamente. Evita que "marcar
  como cumplida" devuelva por sorpresa dinero al disponible.

## Qué se hizo

- **Schema** (v19→v20, migración real probada en
  `test/data/db/schema_migration_v19_to_v20_test.dart` recortando una DB
  v20 a la forma v19 y reabriéndola): `FinanceReservations` gana
  `montoObjetivo` (real, default 0), `fechaLimite` (texto nullable),
  `estado` (texto, default `'activa'`, valores `activa|pausada|finalizada|cancelada`).
- **Dominio** (`lib/domain/finance_goal.dart`, tests en
  `test/domain/finance_goal_test.dart`): `progresoMeta`, `montoRestanteMeta`,
  `contribucionOrientativa` (ritmo mensual orientativo hacia la fecha
  límite — null sin fecha, con fecha vencida o sin nada pendiente, nunca
  inventa una cifra sin esos datos), `puedeAportar`, `puedeRetirar`.
- **`totalReservado`** (`lib/domain/finance_ledger.dart`) ahora filtra
  `estado != 'cancelada'` — antes sumaba toda reserva sin mirar su estado,
  lo que habría hecho que cancelar una meta no liberara nada. Con tests.
- **DB**: `getAllFinanceReservations()` nuevo (la vista de Metas es global,
  no anidada en un registro); `deleteFinanceReservation` y
  `upsertFinanceReservation` ya existían desde Fase 01.
- **UI** (`lib/screens/finanzas/finanzas_metas_screen.dart`, nueva):
  listado global de metas con progreso, badge pausada/cumplida, fecha
  límite + contribución orientativa cuando aplica. Crear/editar vía sheet
  (cuenta fija una vez creada, igual que la categoría en presupuestos).
  Aportar/retirar vía sheet dedicado con las reglas de `puedeAportar`/
  `puedeRetirar`. Pausar/reanudar/finalizar/cancelar/eliminar vía menú de
  acciones, con confirmación y explicación explícita en cancelar/eliminar
  de que el dinero vuelve a estar disponible.
- **Navegación**: Presupuestos y Metas quedan agrupados en una sola
  pantalla (`lib/screens/finanzas/finanzas_planificacion_screen.dart`) con
  un selector de píldora (`AppPillSelector`) — "Planificación: presupuestos
  y metas de ahorro" bajo el mismo destino, sin crear una pestaña de
  navegación nueva (según la arquitectura objetivo del roadmap). Esto
  obligó a quitar el `Scaffold`/`AppBar`/FAB propios que
  `FinanzasPresupuestoScreen` tenía desde Fase 04 — ahora vive embebida
  como contenido, con su selector de mes movido al cuerpo y su FAB expuesto
  aparte (`PresupuestoFab`) para que la pantalla contenedora decida cuál
  FAB mostrar según la pestaña activa (`MetasFab` para Metas).

## Hallazgo confirmado (ver Fase 04 — aún sin corregir)

Las metas (igual que presupuestos, cuentas, categorías, etc.) tampoco están
incluidas en el sistema de backup del proyecto — sigue pendiente para
Fase 08 o una tarea aparte.
