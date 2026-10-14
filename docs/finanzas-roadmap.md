# Roadmap Finanzas — seguimiento

Roadmap maestro de 9 fases propuesto en `UltimoChatConGPT.md`. Reglas: una fase a la vez, sin avanzar sin autorización, sin romper lo maduro (registros/transacciones/categorías/historial).

## Progreso: 9 de 9 fases — roadmap completo (Fase 00 a Fase 08 cerradas)

- [x] **Fase 00 — Auditoría técnica** (solo lectura) — cerrada 2026-10-13
- [x] **Fase 01 — Integridad financiera y cálculos** — cerrada 2026-10-13 — ver [`docs/finanzas-fase01-cierre.md`](./finanzas-fase01-cierre.md)
- [x] **Fase 02 — Navegación y estructura de vistas** — cerrada 2026-10-13 — ver [`docs/finanzas-fase02-cierre.md`](./finanzas-fase02-cierre.md)
- [x] **Fase 03 — Inicio financiero (Registros)** — cerrada 2026-10-13 — ver [`docs/finanzas-fase03-cierre.md`](./finanzas-fase03-cierre.md)
- [x] **Fase 04 — Presupuestos** — cerrada 2026-10-13 — ver [`docs/finanzas-fase04-cierre.md`](./finanzas-fase04-cierre.md)
- [x] **Fase 05 — Metas de ahorro** — cerrada 2026-10-13 — ver [`docs/finanzas-fase05-cierre.md`](./finanzas-fase05-cierre.md)
- [x] **Fase 06 — Estadísticas** — cerrada 2026-10-13 — ver [`docs/finanzas-fase06-cierre.md`](./finanzas-fase06-cierre.md)
- [x] **Fase 07 — Observaciones y sugerencias** — cerrada 2026-10-13 — ver [`docs/finanzas-fase07-cierre.md`](./finanzas-fase07-cierre.md)
- [x] **Fase 08 — Funciones complementarias y pulido final** — cerrada 2026-10-13 — ver [`docs/finanzas-fase08-cierre.md`](./finanzas-fase08-cierre.md)

## Fase 00 — Diagnóstico (resumen)

**Bugs reales encontrados (no cosméticos):**
1. **Transferencias entre registros no mueven dinero.** Se guarda una fila con `tipo:'transferencia'` en el registro origen; el destino nunca la recibe (`getFinanceTransactionsByLibro` filtra solo por `accountId`, ignora `transferToAccountId`), y como el tipo no es 'ingreso'/'gasto' tampoco se resta del origen. Hoy es una anotación inerte.
2. **Presupuestos prácticamente inaccesibles.** `FinanzasPresupuestoScreen` no está enrutada en ningún lado (pantalla huérfana). `upsertFinanceBudget` no se llama desde ninguna UI y `deleteFinanceBudget` ni siquiera está implementado en `database.dart`. No hay forma de crear/editar/eliminar un presupuesto hoy.
3. **Categoría personalizada rota en presupuestos** — busca solo en el catálogo fijo (`catalogoFinanzas.firstWhere`), no en el combinado fijo+custom.
4. **Saldo calculado en 3 lugares distintos** (`finanzas_cuentas_screen.dart`, `finanzas_libro_transacciones_screen.dart`, `finanzas_estadisticas_screen.dart`) sin servicio común — cualquier corrección de regla contable hay que replicarla 3 veces.
5. Campo `activa` de un registro se escribe pero nunca se lee/filtra — campo muerto, no hay archivar/desactivar real.
6. Hard delete de registro con FK `onDelete: restrict` — riesgo de excepción no capturada al borrar un registro con movimientos (no confirmado si la UI la maneja).
7. Cero tests sobre cálculo de saldo, transferencias o presupuestos.

**No son bugs, confirmados como está documentado:** recurrencia (solo campo DB, sin UI), navegación (Stack indexado + providers por entorno, estado de tabs no se pierde al cambiar de entorno), schemaVersion 18 sin nada fundamentalmente fràgil para agregar tablas nuevas (ej. metas).

**Preguntas de producto sin resolver (bloquean Fase 01/05):**
- Qué es exactamente "dinero disponible" (saldo vs. reservas vs. compromisos futuros — ninguno existe hoy en el modelo).
- El campo `activa`: ¿se implementa archivar/desactivar o se elimina el campo?
- Transferencias: ¿se corrigen retroactivamente las ya guardadas (inertes) o solo se arregla hacia adelante?
- Meta de ahorro: el dinero "reservado" ¿vive como saldo dentro de un registro existente, o aparte, restando del "disponible" sin tocar el saldo del registro?

Informe completo (los 10 puntos de auditoría) en el historial de la conversación de esa fecha.
