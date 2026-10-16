# Finanzas v2 — roadmap de rediseño (Planificación / Registros / Estadísticas)

Roadmap de la propuesta funcional de GPT (resumen en la conversación,
preferencias del usuario: presupuestos guiados, metas con ambas
modalidades, estadísticas = evolución + accionables). Dosificado en
sub-specs independientes, cada una con su propio ciclo
brainstorming → spec → plan → implementación, validada antes de pasar a
la siguiente. Ninguna fase toca código sin spec aprobada primero.

## Decisiones ya cerradas (de la conversación)

- Déficit de disponible (reservas > disponible real): Krezium **solo
  avisa**, nunca oculta el déficit como si fuera disponible real.
- Orden de trabajo: Planificación primero, luego conexión con Registros,
  luego Estadísticas — cada una validada antes de seguir.

## Fases

- [x] **Fase A — Spec de Planificación** (presupuestos guiados + metas
      con 2 modalidades: virtual y vinculada a cuenta) — cerrada
      2026-10-14. Ver `docs/superpowers/specs/2026-10-14-planificacion-v2-design.md`.
- [x] **Fase B — Plan + implementación de Planificación** — cerrada
      2026-10-14, 7/7 tareas, suite 357/357 verde en cada commit. Ver
      `docs/superpowers/plans/2026-10-14-planificacion-v2.md`.
- [x] **Fase C — Conexión Registros ↔ Planificación** — cerrada
      2026-10-16: resumen de presupuesto en Nueva Transacción, drill-down
      presupuesto→movimientos, atajo ingreso→meta, recálculo verificado.
      Ver `docs/superpowers/specs/2026-10-16-fases-c-e-g-design.md`.
- [x] **Fase D — (fusionada con C):** se implementó directo tras la spec,
      sin plan separado — mismo criterio dosificado, tareas chicas.
- [x] **Fase E — Estadísticas: tasa de ahorro, variación por categoría,
      acceso a presupuesto** — cerrada 2026-10-16.
- [x] **Fase F — (fusionada con E).**
- [x] **Fase G — Pulido y pruebas integrales** — cerrada 2026-10-16:
      estados vacíos ya cubiertos por diseño en cada tarea, `dart analyze`
      limpio (sin warnings nuevos sobre el baseline pre-existente),
      suite completa 362/362 verde. Roadmap de testeo manual entregado en
      `docs/finanzas-v2-roadmap-testeo.md`.

## Roadmap v2 completo

Las 7 fases (A-G) quedan cerradas. Pendiente: validación manual del
usuario siguiendo `docs/finanzas-v2-roadmap-testeo.md`.

Pendientes transversales a resolver en algún punto (fuera de este
roadmap): backup del módulo Finanzas completo (abierto desde Fase 04 del
roadmap original de 9 fases), dismiss/seen de observaciones (Fase 07),
presupuestos de dos niveles (general+específico, descartado a propósito
en la spec de Fase A).
