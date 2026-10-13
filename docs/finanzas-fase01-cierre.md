# Cierre de Fase 01 — Integridad financiera y cálculos

Fecha de cierre: 2026-10-13
Commits de esta fase: `0ad4033` es el commit base de la fase (rename/contraste previo, no pertenece a Task 1) y `8a256aa` es el último commit de Task 7 — 10 commits de implementación (Tasks 1-7) en el rango exclusivo, verificado con `git log --oneline 0ad4033..8a256aa --no-merges | wc -l`. A ese rango se suma el commit de este cierre (Task 8, `b07b6af` y su fix posterior), que no modifica código de producción salvo el ítem puntual descrito en la sección 7.3.

## 1. Resumen

Fase 01 implementó, de punta a punta, la corrección de los bugs de integridad financiera detectados en la Fase 00 (auditoría de solo lectura): transferencias que no se reflejaban en el registro destino, cálculo de saldo duplicado en tres pantallas, ausencia de archivar/eliminar seguro, validación de transferencias inválidas en el formulario, y reparación no destructiva de transferencias históricas ambiguas. Se trabajó en 7 tasks secuenciales (TDD, con revisión de código entre tasks) más esta Task 8 de cierre.

## 2. Archivos modificados y motivo

| Archivo | Motivo |
|---|---|
| `docs/finanzas-reglas-contables.md` (nuevo) | Formaliza por escrito las reglas contables: qué suma/resta el saldo, fórmula de saldo agregado, tratamiento de origen/destino en transferencias, disponible estimado, efectos de archivar/eliminar, reservas que exceden saldo, transferencias históricas sin destino. Referencia normativa para todo el resto de la fase (Task 1). |
| `lib/data/db/tables_finance.dart` | Nueva tabla `FinanceReservations` (id, accountId FK restrict → FinanceAccounts, nombre, monto, creadaEn) y columna `revisionNota` (nullable) en `FinanceTransactions`, para soportar reservas de saldo y el señalamiento de transferencias históricas dudosas (Task 1, Task 7). |
| `lib/data/db/database.dart` | Bump de `schemaVersion` 18→19 con migración `if (from < 19)` idempotente (crea tabla/columna si faltan, guard pattern existente reutilizado). CRUD de reservas (`getFinanceReservations`, `upsertFinanceReservation`, `deleteFinanceReservation`). Nueva excepción `AccountHasTransactionsException`. `getFinanceAccounts({bool incluirArchivadas = false})` (antes sin filtro, campo `activa` muerto). `archiveFinanceAccount`/`reactivateFinanceAccount`. `countTransactionsForAccount` (cuenta origen+destino). `deleteFinanceAccountSafely` (rechaza si hay movimientos) y `deleteFinanceAccountAndHistory` (borrado explícito con advertencia, en transacción). `getFinanceTransactionsInvolvingLibro` — fix central del bug de transferencias: antes solo `accountId == libroId`, ahora `accountId == libroId OR transferToAccountId == libroId`. `FinanceHistoricalAudit` + `auditarTransferenciasHistoricas` (clasifica transferencias históricas en reconstruibles/dudosas, solo lectura) + `aplicarSenalamientoTransferenciasDudosas` (escribe `revisionNota` solo en dudosas sin nota previa, idempotente, no toca monto/fecha/cuentas) (Tasks 1, 3, 6, 7). |
| `lib/data/db/database.g.dart` | Generado por `build_runner` a partir de los cambios de schema anteriores. |
| `lib/data/models/finance_models.dart` | `FinanceTransaction` expone `revisionNota` (constructor, `fromRow`, `toJson`, `fromJson` con fallback nullable — respeta la convención del proyecto de que campos nuevos deben ser nullable en `fromJson` para que backups viejos sigan siendo importables) (Task 7). |
| `lib/domain/finance_ledger.dart` (nuevo) | Servicio de dominio puro (sin DB/UI): `signedEffectForLibro`, `calcularSaldo`, `calcularIngresosGastos`, `totalReservado`, `calcularDisponibleEstimado`, `esTransferenciaValida` (Tasks 2, 5). |
| `lib/providers/finance_provider.dart` | `financeAccountBalanceProvider` (`FutureProvider.family`) — combina las queries de DB (Task 1/3) con las funciones puras de `finance_ledger.dart` (Task 2) en un único punto de cálculo de saldo/ingresos/gastos/disponible, reemplazando el cálculo duplicado en 3 pantallas (Task 4). |
| `lib/screens/finanzas/finanzas_cuentas_screen.dart` | Migrado a `financeAccountBalanceProvider`. Menú de tres puntos (editar/archivar/eliminar) con advertencia explícita antes de borrado definitivo, reemplazando el único ícono de lápiz que existía antes (no había flujo de eliminar previo). Hook de reparación histórica (`unawaited(aplicarSenalamientoTransferenciasDudosas(...))`) en `initState` (Tasks 4, 6, 7). |
| `lib/screens/finanzas/finanzas_estadisticas_screen.dart` | Tarjeta "Balance" migrada a `financeAccountBalanceProvider` (antes usaba `getFinanceTransactionsByLibro`, solo salida, ignorando transferencias entrantes) (Task 4). Único archivo de Estadísticas tocado, y solo en el cálculo de saldo — no se tocó ninguna otra parte de Estadísticas. |
| `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart` | Migrado a `getFinanceTransactionsInvolvingLibro`/`financeAccountBalanceProvider`. Badge de advertencia (ícono + `SnackBar`) en filas de transacciones con `revisionNota` (transferencias históricas dudosas) (Tasks 4, 7). |
| `lib/screens/finanzas/nueva_transaccion_sheet.dart` | Guard en `_guardar`: rechaza transferencias a sí mismo o sin destino usando `esTransferenciaValida` antes de guardar (Task 5). |
| `test/db/finance_historical_repair_test.dart` (nuevo) | Clasificación reconstruible/dudosa de transferencias históricas (Task 7). |
| `test/db/finance_ledger_db_test.dart` (nuevo) | Query bidireccional, archivar/reactivar, eliminar seguro/con historial (Task 3). |
| `test/db/finance_tables_migration_test.dart` | Extendido: existencia de `FinanceReservations` y `revisionNota` consultable tras migración v19 (Task 1). |
| `test/domain/finance_ledger_test.dart` (nuevo) | 17 tests sobre las funciones puras de `finance_ledger.dart`, incluida `esTransferenciaValida` (Tasks 2, 5). |
| `test/providers/finance_account_balance_provider_test.dart` (nuevo) | `financeAccountBalanceProvider` combina saldo, ingresos/gastos y reservas correctamente (Task 4). |

**Confirmación de alcance**: ningún archivo de navegación, Plantillas, Presupuestos (UI) fue tocado. El único archivo de Estadísticas modificado (`finanzas_estadisticas_screen.dart`) se tocó exclusivamente para el cálculo de la tarjeta Balance, tal como autorizaba el alcance de la fase.

## 3. Cambio de schema (v18 → v19)

- Nueva tabla `FinanceReservations`: `id` (pk), `accountId` (FK restrict → `FinanceAccounts`), `nombre`, `monto`, `creadaEn`.
- Nueva columna `revisionNota` (nullable, text) en `FinanceTransactions`, usada para marcar transferencias históricas dudosas sin alterar monto/fecha/cuentas.
- Migración `onUpgrade` con guard `if (from < 19)`, usando el mismo patrón hot-restart-safe (`tableExists`/`colsOf`) que las migraciones previas (`from < 17`). `test/db/finance_tables_migration_test.dart` confirma que, en una base de datos creada desde cero (`onCreate`), la tabla `FinanceReservations` existe y `revisionNota` es consultable — **no ejercita la ruta real de upgrade desde v18** (mismo hueco de cobertura que `from < 17`, documentado como hallazgo diferido de Task 1 en la sección 7).

## 4. Reglas contables implementadas

Ver [`docs/finanzas-reglas-contables.md`](./finanzas-reglas-contables.md) para el detalle normativo completo. Resumen operativo:
- El saldo de un registro suma transferencias entrantes y resta transferencias salientes (antes: inertes, invisibles en el destino).
- `financeAccountBalanceProvider` es ahora la única fuente de verdad de saldo/ingresos/gastos/disponible estimado para las 3 pantallas que antes lo calculaban por separado.
- `reservasExcedenSaldo` exige `reservado > 0 && reservado > saldo` (corregido en Task 2 para evitar falso positivo con saldo negativo y cero reservas).
- Transferencias nuevas rechazan origen==destino o destino nulo antes de guardar (Task 5).
- Transferencias históricas ambiguas (destino nulo, auto-transferencia, o destino inexistente/archivado-eliminado) se señalan con `revisionNota` sin modificar ningún dato existente (Task 7) — principio "no inventar datos" respetado.
- Archivar/reactivar/eliminar: eliminar con movimientos está bloqueado (`AccountHasTransactionsException`) salvo que el usuario confirme explícitamente "eliminar y borrar historial" (Task 3, Task 6).

## 5. Pruebas ejecutadas y resultado

- `flutter test` (suite completa): **285 tests, todos en verde** (`All tests passed!`). Incluye los ~258 tests preexistentes más los nuevos de Tasks 1-7 (finance_ledger, finance_ledger_db, finance_historical_repair, finance_tables_migration extendido, finance_account_balance_provider).
- `dart analyze`: 29 issues, **ninguno nuevo relacionado con Finanzas**. Todos corresponden a deuda preexistente ya documentada en sesiones anteriores (ej. `debt_history_provider.dart:31` variable no usada, `add_credit_sheet.dart` elementos no referenciados, `summary_tab.dart` dead code, warnings de `deprecated_member_use` en widgets de crédito/backup, y 1 error preexistente en `integration_test/credit_flow_test.dart` por import roto de `package:kredit/main.dart` — no relacionado con esta fase ni con Finanzas).

## 6. Auditoría de transferencias históricas reales (reconstruibles/dudosas/no-reconstruibles)

**No se pudo obtener un conteo real** en este entorno: este worktree es una copia de git aislada sin la base de datos de la aplicación del usuario (sin datos de producción). `auditarTransferenciasHistoricas` (añadida en Task 7, cubierta por `test/db/finance_historical_repair_test.dart` con datos sintéticos) queda disponible para que el usuario, o una sesión futura, la ejecute contra su base de datos real del dispositivo y obtenga las cifras reales. No se fabrica ningún número aquí.

Adicionalmente, `aplicarSenalamientoTransferenciasDudosas` ya se ejecuta automáticamente (de forma idempotente, en segundo plano) cada vez que se abre `finanzas_cuentas_screen.dart`, así que en el primer uso real de la app tras actualizar, las transferencias históricas dudosas del usuario quedarán señaladas (badge visible) sin acción manual adicional.

## 7. Incidencias para revisión manual / hallazgos diferidos

Recopilado íntegro del ledger (`progress.md`), sin omitir ninguno:

**Task 1:**
- Comentario duplicado/obsoleto en `database.dart:155-160` (cosmético).
- Rama `onUpgrade from<19` sin test directo de upgrade real (igual que `from<17` preexistente, no es regresión).

**Task 2:**
- Self-transfer (origen==destino) da `-monto` en vez de 0/rechazo a nivel de `calcularSaldo` puro — no cubierto por tests ahí; la UI lo bloquea en Task 5, pero la función pura en sí no lo impide.
- Import de `database.dart` en `finance_ledger.dart` solo por el tipo `FinanceReservationRow` — acopla dominio puro a Drift; aceptado tal como lo especificaba el brief.

**Task 3:**
- `countTransactionsForAccount` trae filas completas en vez de usar `count()` agregado — cuestión de performance, no de corrección.
- Sin test de archivar/eliminar un id inexistente (no-op silencioso, comportamiento deseado pero no asertado).
- Sin test de `deleteFinanceAccountAndHistory` cuando la cuenta es `transferToAccountId` de otra transacción (escenario FK asimétrico, documentado en el propio doc comment del método).

**Task 4:**
- `financeAccountBalanceProvider` no reutiliza la caché de `financeAccountsProvider`; hace su propia llamada a `getFinanceAccounts(incluirArchivadas: true)`.

**Task 5:**
- El guard de `esTransferenciaValida` retorna en silencio sin feedback al usuario (mismo patrón que el guard preexistente `_libroId==null`).
- **Parked, evaluado y resuelto en Task 8**: `onLibroChanged` no limpiaba `_libroDestinoId` al cambiar origen; si el nuevo origen coincidía con el destino ya elegido, el dropdown de destino podía quedar con un `value` fuera de su lista de items (mismo patrón de crash de dropdown ya corregido antes en otra pantalla). En el fix round de esta Task 8 se evaluó el riesgo/costo y se decidió corregirlo: `onLibroChanged` en `lib/screens/finanzas/nueva_transaccion_sheet.dart` ahora limpia `_libroDestinoId` a `null` en el mismo `setState` cuando el nuevo origen coincide con el destino ya seleccionado. Verificado con `dart analyze` (sin issues en el archivo) y `flutter test` completo (285/285 verde) — sin arnés de widget test para este screen, consistente con el resto de la fase.

**Task 6:**
- Race entre `countTransactionsForAccount` y `deleteFinanceAccountSafely` en la rama de 0 transacciones — `AccountHasTransactionsException` no se captura ahí.
- Falta `mounted` guard en `_ArchivadosSheetState._reactivar` tras el `await`.
- Inconsistencia de `mounted`-check entre las dos ramas de eliminar.
- Sin guard anti-doble-tap en el `PopupMenuButton` (archivar/eliminar podrían dispararse dos veces).

**Task 7:**
- `aplicarSenalamientoTransferenciasDudosas` hace un `getSingle()` extra por id dudoso en vez de reusar las filas ya traídas (N+1 menor, irrelevante a esta escala).
- `FinanceHistoricalAudit.noReconstruibles` queda hardcodeado a 0, campo vestigial (no se usa en la clasificación actual).

Ninguno de estos hallazgos bloqueó la aprobación de su task correspondiente (todas las tasks cerraron con "review clean" o "Approved" explícito del reviewer). Se listan aquí para que una sesión futura decida si amerita abrirlos como tickets.

## 8. Limitaciones conocidas / fuera de alcance de esta fase

- **Presupuestos (UI)** sigue sin ruta de navegación — `FinanzasPresupuestoScreen` permanece huérfana, tal como se documentó en la Fase 00. Esto es explícitamente Fase 02/04 y no se tocó en esta fase.
- **Navegación y estructura de vistas** (Fase 02) no se tocó.
- El conteo real de transferencias históricas reconstruibles/dudosas/no-reconstruibles del usuario no pudo obtenerse en este entorno (ver sección 6) — requiere ejecutar `auditarTransferenciasHistoricas` contra la base de datos real del dispositivo.

## 9. Confirmación explícita: Fase 02 no ha iniciado

Esta Task 8 es de verificación y documentación. La única excepción de código de producción es el fix de una línea descrito en la sección 7 (Task 5, `nueva_transaccion_sheet.dart`), aplicado tras revisión explícita de un hallazgo ya identificado y diferido durante la fase — no es trabajo nuevo de alcance. No se ha iniciado ningún trabajo de Fase 02 ("Navegación y estructura de vistas"). Se requiere autorización explícita del usuario antes de comenzar la Fase 02.
