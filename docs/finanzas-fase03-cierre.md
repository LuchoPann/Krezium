# Finanzas — Fase 03: Inicio financiero (Registros) — cierre

Diseño acotado aprobado en chat (sin spec/plan formal separado, dado el tamaño reducido del cambio — mismo criterio que Fase 02).

## Cambios

1. **Resumen del periodo en el lobby** (`_PeriodoResumen`, `finanzas_cuentas_screen.dart`): Ingresos/Gastos dejan de ser históricos y pasan a ser del mes seleccionado (por defecto, el mes actual), con flechitas para navegar mes anterior/siguiente. El "BALANCE TOTAL" de arriba no cambia — sigue siendo el saldo histórico acumulado, deliberadamente separado para no confundir saldo registrado con resumen de periodo.
2. **Observación calculada** (`observacionPeriodo`, `lib/domain/finance_ledger.dart`): frase breve ("Tus ingresos superan tus gastos en X% este mes") que solo aparece si hubo al menos un movimiento ese mes — si ingresos y gastos son ambos cero, no se muestra nada. Maneja los casos de solo-ingresos/solo-gastos sin dividir por cero, e ingresos==gastos (mensaje de equilibrio sin porcentaje).
3. **Nuevo provider `financeGlobalPeriodSummaryProvider`** (`finance_provider.dart`): suma ingresos/gastos del mes sobre todos los registros activos, reutilizando `calcularIngresosGastos` (excluye transferencias, como el resto del módulo).
4. **Accesos rápidos** (`_AccionesRapidas`): 3 chips (Ingreso/Gasto/Transferir) debajo del resumen, que abren el formulario de nueva transacción ya existente con el tipo preseleccionado. Si hay un solo registro, se usa directamente; si hay varios, el propio formulario pregunta cuál (Paso 1, sin cambios). Para esto se agregó un parámetro opcional `tipoInicial` a `showNuevaTransaccionSheet`/`_NuevaTransaccionSheet` — no afecta ninguna llamada existente (plantillas, edición), todas omiten el parámetro.

## No se tocó

Tarjetas de registro, creación/edición/archivar/eliminar, historial, el formulario de transacción en sí (solo el parámetro nuevo, opcional), estados vacíos existentes (`_EmptyState` para "sin registros" ya cubre ese caso).

## Pruebas

- 7 tests nuevos: 6 para `observacionPeriodo` (TDD, RED confirmado antes de implementar) + 1 para `financeGlobalPeriodSummaryProvider` (suma correcta, excluye transferencias, filtra por mes).
- `dart analyze` limpio en los 3 archivos tocados.
- `flutter test` completo: 295/295.
- No se ejecutó la app en dispositivo (restricción permanente) — pendiente confirmación visual del usuario.

## Limitaciones

- El selector de mes es local a esta pantalla (no persiste ni se comparte con Estadísticas/Presupuesto, que tienen los suyos propios) — consistente con no tocar esas pantallas en esta fase.
- Las 3 acciones rápidas abren el mismo formulario completo (no un atajo simplificado) — mantiene consistencia con el único punto de entrada de transacciones que ya existe.

## Confirmación

Fase 04 no ha iniciado. Se espera autorización explícita del usuario para continuar.
