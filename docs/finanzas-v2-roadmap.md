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

- [ ] **Fase A — Spec de Planificación** (presupuestos guiados + metas
      con 2 modalidades: virtual y vinculada a cuenta). En curso.
- [ ] **Fase B — Plan + implementación de Planificación** (solo tras
      aprobar la spec de Fase A).
- [ ] **Fase C — Spec de conexión Registros ↔ Planificación** (accesos
      contextuales al registrar/editar/eliminar un movimiento, navegación
      bidireccional).
- [ ] **Fase D — Plan + implementación de Fase C.**
- [ ] **Fase E — Spec de rediseño de Estadísticas** (resumen de periodo,
      evolución, distribución de gasto, sección de hallazgos accionables
      conectada con presupuestos/metas).
- [ ] **Fase F — Plan + implementación de Fase E.**
- [ ] **Fase G — Pulido y pruebas integrales** (migraciones, categorías
      personalizadas, estados vacíos, datos incompletos).

Pendientes transversales a resolver en algún punto (no bloquean Fase A):
backup del módulo Finanzas (fuera del alcance de este roadmap, abierto
desde Fase 04 original), dismiss/seen de observaciones.
