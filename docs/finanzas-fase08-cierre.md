# Fase 08 — Funciones complementarias y pulido final (cierre)

**Estado:** cerrada. Suite completa: 346/346. **Última fase del roadmap de 9 — módulo Finanzas completo.**

## Bugs reales encontrados y corregidos

Revisando "categorías, búsquedas, filtros y autocompletados" se encontró
un patrón repetido en 4 lugares: código que resolvía una categoría
buscando solo en el catálogo **fijo** (`catalogoFinanzas`/`todoCatalogo`),
nunca en el catálogo **combinado** (fijo + personalizado,
`allFinanceCategoriesProvider`) que ya usa el resto del módulo desde que
existen categorías personalizadas. Para una transacción/plantilla con
categoría propia del usuario, el efecto no era solo cosmético:

1. **`nueva_transaccion_sheet.dart`** — editar una transacción o usar una
   plantilla con categoría personalizada dejaba el campo "Elegir
   categoría" vacío en silencio. Si el usuario no lo notaba y guardaba,
   `categoryId: Value(_categoriaSeleccionada?.id ?? 'transferencia')`
   **sobrescribía la categoría real con el placeholder de transferencia**
   — pérdida de dato real, no solo visual. Arreglado resolviendo la
   categoría pendiente en `build()` en cuanto el catálogo combinado carga.
2. **`editar_plantilla_sheet.dart`** — mismo patrón; al guardar mandaba
   `categoryId: Value(_categoria?.id ?? '')`, **vaciando el categoryId de
   la plantilla**. Mismo arreglo.
3. **`finanzas_plantillas_screen.dart`** — una plantilla con categoría
   personalizada se mostraba en la lista sin nombre ni ícono de categoría
   (sin pérdida de dato, pero información visible incorrecta).
4. **`finanzas_libro_transacciones_screen.dart`** — el nombre de la
   categoría padre en el subtítulo de cada movimiento se buscaba solo en
   `catalogoCategoriaPadres` (8 padres fijos) — una categoría padre
   personalizada (creada vía el botón "+" del selector) nunca aparecía ahí.

Además, un bug de navegación independiente:

5. **Buscador del historial** (`_BusquedaSheet`): tocar un resultado de
   búsqueda abría un formulario de transacción **en blanco**, ignorando
   por completo la transacción tocada (`showNuevaTransaccionSheet(context,
   libroId: _libroActual.id)` sin `editar:`). Ahora abre esa transacción
   para editarla. De paso, el buscador ahora también filtra por nombre de
   categoría (antes solo nota/ordenante/monto/fecha) — el propio checklist
   de la fase pedía "revisar... búsquedas".

## Recurrencia — evaluada, no implementada (decisión explícita)

Los campos `esRecurrente`/`recurrenciaConfig` existen en
`FinanceTransactions` desde antes de este roadmap, pero nunca tuvieron UI.
Construir un motor de recurrencia real (generar transacciones futuras,
decidir cuándo, evitar duplicados si el usuario abre la app varios días
seguidos, notificaciones) es una funcionalidad nueva con decisiones de
producto no aprobadas — la fase pide explícitamente "evaluar... cuando
resulte compatible", no implementar. Se deja documentado como evaluado y
deliberadamente fuera de alcance; los campos existentes son compatibles
con una futura implementación sin requerir otra migración.

## Verificado sin cambios necesarios

- **Persistencia y migraciones**: cobertura existente (migraciones
  pairwise v14→v17, v17→v18, v18→v19, v19→v20, todas reabriendo una DB
  real recortada a la versión anterior) se mantiene verde; no se encontró
  ningún caso no cubierto.
- **Regresión Créditos**: la suite completa (346 tests) incluye los tests
  de `credits_provider_test.dart` y relacionados — verde en cada corrida
  de esta sesión, incluida la final.
- **Valores extremos**: `agruparMiles`/`MontoInputFormatter` usan
  `NumberFormat`/`int` nativos de Dart, sin límite práctico para montos
  grandes; validaciones de monto > 0 ya existían en los formularios de
  transacción/presupuesto/meta.
- **Accesibilidad y consistencia visual**: revisado a nivel de lectura de
  código (tokens de diseño `AppRadius`/`AppSpacing`/`AppTextSize`/
  `AppThemeColors` usados consistentemente en todo lo tocado durante el
  roadmap). No se hizo una auditoría de accesibilidad profunda (lectores
  de pantalla, contraste) — el resto de la app tampoco la tiene, así que
  no se consideró parte del alcance de "pulido" de este módulo
  específico; queda como posible mejora futura aparte.

## Resultado del roadmap completo

Las 9 fases (00 a 08) quedan cerradas. Ver `docs/finanzas-roadmap.md` y
los documentos de cierre de cada fase para el detalle completo.
