# Fase 04 — Presupuestos (cierre)

**Estado:** cerrada. Suite completa: 311/311.

## Qué estaba roto

1. `FinanzasPresupuestoScreen` no tenía ningún CRUD: no había forma de crear, editar ni eliminar un presupuesto desde la UI (`deleteFinanceBudget` ni siquiera existía en `database.dart`).
2. `upsertFinanceBudget` llamaba `insertOnConflictUpdate` contra `rowId` (autoincrement), que la UI nunca conoce al crear — cada "edición" habría insertado una fila duplicada en vez de actualizar la existente.
3. La búsqueda de categoría (`catalogoFinanzas.firstWhere`) solo miraba el catálogo fijo, ignorando categorías personalizadas del usuario.
4. El consumo gastado por categoría se calculaba sumando transacciones por `categoryId` exacto — como el selector de presupuestos solo ofrece categorías padre, y las transacciones casi siempre se registran contra una subcategoría, el gasto real nunca se habría reflejado (presupuesto eternamente en 0% gastado).
5. Pantalla sin ningún token de diseño del proyecto (`Card`/`Scaffold`/colores Material stock).

## Qué se hizo

- **Dominio** (`lib/domain/finance_budget.dart`, con tests en `test/domain/finance_budget_test.dart`):
  - `gastoCategoriaPeriodo` — suma gasto directo a la categoría padre + roll-up de todas sus subcategorías (vía `parentPorCategoria`). Ignora ingresos y transferencias.
  - `progresoPresupuesto`, `saldoPresupuesto`, `estadoPresupuesto` (normal/cercano ≥80%/agotado ≥100%, incluye excedido).
- **DB** (`lib/data/db/database.dart`, tests en `test/db/finance_budget_db_test.dart`):
  - `upsertFinanceBudget` ahora busca por `(categoryId, anio, mes)` antes de insertar — actualiza si existe, inserta si no.
  - `getFinanceBudgetFor` y `deleteFinanceBudget` nuevos.
- **UI** (`lib/screens/finanzas/finanzas_presupuesto_screen.dart`, reescrita):
  - Resumen global (asignado/gastado/disponible) con barra de progreso.
  - Tarjetas de presupuesto con franja de color por categoría, barra de progreso, badge "Cerca del límite"/"Agotado", saldo restante — todo con tokens del proyecto (`AppRadius`/`AppSpacing`/`AppTextSize`/`AppThemeColors`).
  - Crear/editar vía sheet (`scaffoldBackgroundColor` como fondo, según la regla de diseño estandarizado); categoría no editable una vez creado el presupuesto (es su identidad).
  - Eliminar con confirmación.
  - Selector de categoría limitado a categorías padre tipo gasto/ambos (fijas + personalizadas) sin presupuesto ya asignado ese mes — evita duplicados.
  - Estado vacío diferenciado según si quedan categorías disponibles o no.
  - El usuario puede seguir registrando gastos aunque supere el límite (sin bloqueo, por diseño — spec de GPT).
- **Extraído** `lib/utils/monto_input_formatter.dart` (antes vivía solo en `nueva_transaccion_sheet.dart`) para reusar el mismo formateador de miles en el nuevo sheet de presupuesto, sin duplicar lógica.

## Decisiones

- Presupuestos solo sobre categorías **padre** (no subcategorías) — evita una lista de ~113 opciones en el selector; el roll-up en `gastoCategoriaPeriodo` hace que esto siga siendo útil.
- Categoría no editable al editar un presupuesto existente — cambiarla sería crear una identidad nueva y dejar huérfano el límite anterior.

## Hallazgo fuera de alcance (no corregido en esta fase)

El módulo Finanzas completo (cuentas, categorías, transacciones, presupuestos, reservas, lugares, plantillas) **no está incluido en el sistema de backup** (`lib/widgets/account/data_tools_card.dart` solo exporta créditos/cupos vía `exportStateToJson(credits, quotas)`). Los modelos de Finanzas (`FinanceBudget.toJson/fromJson`, etc.) existen pero están muertos — nunca se llaman desde el backup real. Esto excede el alcance de "Presupuestos" y toca las 8 fases por igual; se deja señalado para decidir en Fase 08 (pulido/persistencia) o como tarea aparte, no se tocó aquí para no expandir el alcance sin autorización.
