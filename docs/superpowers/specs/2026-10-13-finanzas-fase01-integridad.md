# Finanzas — Fase 01: Integridad financiera y cálculos

**Spec derivada de:** `UltimoChatConGPT.md` (roadmap de 9 fases) + decisiones de producto confirmadas por el usuario + `docs/finanzas-roadmap.md` (Fase 00, auditoría cerrada).

**Estado:** Fase 01 autorizada para implementación. Fase 02 en adelante permanecen bloqueadas.

## 1. Alcance autorizado

Solo esto:
- Integridad de cálculos de saldo, transferencias, ciclo de vida de registros (archivar/reactivar/eliminar), reservas lógicas y disponible estimado, reparación histórica de transferencias, pruebas automatizadas.

Prohibido en esta fase: navegación, rediseño de pantallas, Planificación, metas de ahorro como feature de UI completa (solo su lógica de dominio mínima para soportar reservas), estadísticas nuevas, sugerencias. Si una corrección de integridad exige tocar una pantalla existente, solo el cambio imprescindible — no rediseñar.

## 2. Hallazgos de la Fase 00 que esta fase corrige

1. Transferencias no mueven dinero (fila solo en origen, tipo `'transferencia'` no filtrado como ingreso/gasto, destino nunca la ve).
2. Saldo calculado en 3 lugares (`finanzas_cuentas_screen.dart`, `finanzas_libro_transacciones_screen.dart`, `finanzas_estadisticas_screen.dart`).
3. Categoría personalizada rota en presupuestos (`catalogoFinanzas.firstWhere` en vez del catálogo combinado) — **fuera de alcance de Fase 01** (pertenece a Fase 04, presupuestos); se documenta aquí solo para no perderlo.
4. Campo `activa` escrito pero nunca leído — se resuelve en esta fase (archivar/reactivar).
5. Hard delete de registro con `onDelete: restrict` — riesgo de excepción no capturada — se resuelve en esta fase.
6. Cero tests de saldo/transferencias/presupuestos — se corrige para saldo/transferencias/reservas en esta fase.

## 3. Decisiones de producto confirmadas (obligatorias, no reinterpretables)

### 3.1 Transferencias
Movimiento real entre registros: descuenta del origen, suma al destino, nunca cuenta como ingreso ni gasto, nunca duplicada ni parcial.

**Transferencias históricas** (ya guardadas, hoy inertes): se investigan y reparan **solo las reconstruibles con certeza**. Las dudosas o no reconstruibles se **conservan intactas y se señalan** para revisión manual — nunca se inventa destino/monto/fecha, nunca se convierten silenciosamente en ingreso/gasto, nunca se eliminan para que el saldo "cuadre".

### 3.2 Dinero disponible — tres conceptos distintos
- **Saldo registrado:** suma contable de movimientos de un registro (igual que hoy).
- **Dinero reservado:** parte del saldo que el usuario asignó lógicamente a una meta u otra reserva explícita que el sistema pueda identificar.
- **Disponible estimado:** saldo registrado menos reservas contabilizadas, **solo cuando hay datos suficientes**. Si no hay reservas, disponible estimado == saldo registrado. Nunca se presenta como dinero garantizado libre de compromisos no registrados.

No se infieren reservas a partir del nombre u objetivo de una meta — deben tener representación de datos explícita.

### 3.3 Ciclo de vida de registros — archivar/reactivar + eliminar con advertencia
Decisión del usuario (amplía la recomendación de GPT): **se implementa archivar/reactivar como mecanismo principal**, reutilizando el campo `activa` existente (no crear campo nuevo). Además, **se mantiene disponible la eliminación física definitiva**, pero:
- Solo se ofrece cuando el registro no tiene movimientos asociados, **o** tras una advertencia explícita y expresa que dejar claro que se perderá el historial asociado de forma irreversible (confirmación fuerte, no un simple diálogo genérico).
- Un registro archivado conserva su historial completo y desaparece de los listados operativos activos por defecto; el usuario puede consultarlo y reactivarlo.
- Archivar nunca borra transacciones ni altera saldos históricos.
- `deleteFinanceAccount` con FK `restrict` debe manejarse de forma segura: si hay movimientos asociados, la UI ofrece archivar en vez de un error crudo de SQLite; la eliminación física real solo procede si el usuario la confirma explícitamente sabiendo que borra el historial (puede implicar borrar en cascada controlado, nunca un fallo no capturado).

### 3.4 Metas de ahorro como reservas lógicas (solo lógica de dominio, no UI de Fase 05)
- Una meta reserva dinero de forma lógica, nunca lo mueve físicamente.
- Crear/modificar una meta o su reserva no genera ingreso, gasto ni transferencia.
- El dinero permanece en el registro donde ya está; solo una transferencia real lo mueve.
- Cada reserva se vincula a un registro específico (no una reserva "flotante" sin registro de origen).
- Una meta no reserva automáticamente su objetivo total — la reserva es un monto explícito que el usuario asigna, independiente del objetivo.
- No se cuenta el mismo dinero dos veces (ni se resta del saldo del registro Y del disponible simultáneamente de forma duplicada).
- Si las reservas superan el saldo del registro: se conserva el dato, se señala la inconsistencia, nunca se oculta con un ajuste automático.

## 4. Orden de implementación (igual al propuesto por GPT, vinculante)

1. **Etapa 1 — Reglas contables documentadas** (qué suma/resta saldo, cómo se tratan transferencias/reservas/archivado, casos límite) antes de tocar código.
2. **Etapa 2 — Centralizar cálculos** (saldo por registro, saldo agregado, disponible estimado) en una fuente única; las pantallas consumen, no recalculan.
3. **Etapa 3 — Corregir transferencias nuevas** (origen/destino, atomicidad, validación de origen≠destino y existencia de ambos registros).
4. **Etapa 4 — Archivar/reactivar/eliminar con advertencia** sobre el campo `activa` existente.
5. **Etapa 5 — Reservas y disponible estimado** (modelo de dominio mínimo para que Fase 05 lo use después).
6. **Etapa 6 — Reparación histórica de transferencias** (clasificar reconstruible/dudoso/no-reconstruible; reparar solo lo seguro; con respaldo y estrategia de reversión).
7. **Etapa 7 — Pruebas y cierre** (suite completa de la sección 5 de la instrucción original, criterios de aceptación de la sección 4).

## 5. Reglas globales (de `UltimoChatConGPT.md`, vigentes para todo el proyecto)

- No reconstruir registros/transacciones/categorías/historial/plantillas si ya funcionan.
- No modificar navegación compartida Créditos↔Finanzas.
- No contar una transferencia como ingreso/gasto.
- No contar el mismo dinero dos veces.
- No generar recomendaciones sin datos suficientes (no aplica aún en Fase 01, pero rige para disponible estimado: no se inventa si faltan datos).
- No bloquear operaciones por exceso de presupuesto ni penalizar metas incumplidas (no aplica directamente en Fase 01).
- Local-first, SQLite existente, sin servicios externos ni sincronización.
- No borrar ni reinicializar la base de datos para simplificar desarrollo; no incrementar `schemaVersion` sin necesidad real; probar migración con copia de una DB anterior.
- No avanzar a Fase 02 sin autorización explícita del usuario al cerrar esta fase.

## 6. Criterios de aceptación

Ver íntegros en el mensaje original de GPT (sección "4. Criterios de aceptación" del prompt pegado por el usuario) — se adoptan sin modificación, agregando que el criterio de "eliminación física de registros relacionados se maneja de forma segura" incluye la vía de confirmación explícita descrita en 3.3.

## 7. Plan mínimo de pruebas

Los 28 escenarios listados en la sección "5. Plan mínimo de pruebas" del prompt del usuario se adoptan íntegros como base de la Etapa 7.

## 8. Reporte de cierre obligatorio

Al terminar: archivos modificados y motivo, cambios de esquema/migraciones, reglas contables implementadas, pruebas ejecutadas y resultado, conteo de transferencias históricas reconstruibles/dudosas/no-reconstruibles, incidencias para revisión manual, limitaciones pendientes, confirmación explícita de que Fase 02 no inició. Luego detenerse.
