# Flujo de vistas y funcionalidades del módulo Finanzas (Krezium)

Este documento complementa a `modulo-finanzas-explicacion.md` (que explica los conceptos de datos: registros, transacciones, categorías). Aquí el foco es otro: **qué pantallas existen, cómo se navega entre ellas, y qué puede hacer el usuario en cada una**, como si se estuviera recorriendo la app con el dedo.

## Punto de entrada: navegación dual

La app tiene un botón central en la barra de navegación inferior que alterna entre dos "mundos": Créditos y Finanzas. Al cambiar a Finanzas, el usuario cae en la pantalla principal de ese módulo: el **lobby de registros**.

## 1. Lobby de registros — `finanzas_cuentas_screen.dart`

Es la pantalla raíz de Finanzas. Muestra:

- Un header con el balance global (suma de todos los registros) y, debajo, ingresos/gastos totales en texto neutro.
- Una lista de tarjetas, una por cada registro (cuenta) que el usuario haya creado: nombre, ícono, color, balance individual grande, e ingresos/gastos de ese registro en texto neutro debajo.
- Un botón flotante extendido ("Nuevo registro") para crear una cuenta nueva.

**Acciones disponibles aquí:**
- Tocar una tarjeta de registro → entra al historial de ese registro (ver sección 2).
- Crear un registro nuevo → abre un formulario (nombre, tipo, ícono, color, saldo inicial).
- Editar o eliminar un registro existente (desde la propia tarjeta, con sus controles).

Si el usuario no tiene ningún registro creado todavía, esta pantalla es también el punto donde se le invita a crear el primero — Finanzas funciona de forma completamente independiente de si el usuario usa o no el módulo de Créditos.

## 2. Historial de un registro — `finanzas_libro_transacciones_screen.dart`

Se llega aquí tocando un registro desde el lobby. Es la pantalla más usada del módulo día a día.

**Qué muestra:**
- Una `SliverAppBar` arriba con el nombre del registro (hay un dropdown para saltar directamente a otro registro sin volver al lobby).
- Una tarjeta de resumen: balance del registro en grande, y a la derecha (separado por una línea vertical) ingresos (flecha verde arriba) y gastos (flecha roja abajo), cada uno con su porcentaje real sobre el total de movimientos. Debajo, una frase corta calculada en vivo (ej. "42 registros · ingresos superan gastos en 18%").
- La lista de transacciones, agrupada por periodo (día/semana/mes/año, o sin agrupar — se elige en el menú de filtros). Cada grupo tiene un encabezado neutro ("Octubre 2026 · 12 registros") y debajo las transacciones una a una.
- Cada fila: ícono neutro de la categoría, nombre de la subcategoría, debajo categoría padre + nota + lugar/persona (si existen), y a la derecha el monto coloreado (verde/rojo con signo) + la hora.

**Acciones disponibles aquí:**
- Deslizar una fila a la izquierda → eliminar (pide confirmación).
- Deslizar a la derecha → abrir esa transacción para editarla (reutiliza el panel de nueva transacción, prellenado).
- Buscador de texto libre sobre notas/lugares/categorías.
- Botón de filtros (menú flotante, no pantalla completa): tipo de agrupación, orden (reciente/antiguo primero), filtrar solo ingresos o solo gastos.
- Botón flotante pequeño → ir a Plantillas.
- Botón flotante principal ("+") → abrir el panel de nueva transacción (ver sección 3).

## 3. Panel de nueva transacción — `nueva_transaccion_sheet.dart`

Es un *bottom sheet* (panel que sube desde abajo), no una pantalla nueva — se abre encima del historial o desde cualquier otro punto que dispare una transacción nueva (incluida una plantilla). Tiene varios pasos internos que se intercambian dentro del mismo panel (nunca se apila un sheet sobre otro):

**Paso 1 (si aplica):** elegir a qué registro pertenece la transacción, y si es una transferencia entre registros propios, el registro destino.

**Paso 2 — formulario principal:**
- Campo de monto grande y centrado, con separadores de miles en vivo mientras se escribe.
- Interruptor tipo píldora: Ingreso / Gasto.
- Fila de chips horizontales con las categorías más usadas para ese tipo, más un chip "Más" que lleva al paso 3.
- Fecha y hora, cada una tocable de forma independiente (cada toque abre solo su propio selector).
- Campo de lugar/persona con autocompletado basado en lugares usados antes.
- Campo de nota (crece hacia abajo si el texto ocupa varias líneas).
- Botón "Guardar" al final, coloreado según el tipo (verde si ingreso, rojo si gasto).

**Paso 3 — selector completo de categoría** (solo si se necesita, tocando "Más"):
- Buscador de categorías.
- Chips de categorías recientes.
- Acordeón por categoría padre, desplegable para ver sus subcategorías.
- Botón "Crear categoría nueva" al final, y un "+" junto a cada categoría padre para crear directamente una subcategoría dentro de ese grupo.
- Al crear una categoría nueva se abre `categoria_selector_sheet.dart` (su sheet interno `_NuevaCategoriaSheet`) para definir nombre, ícono, tipo y categoría padre.

Este mismo panel sirve para **editar** una transacción existente (abre directo en el paso 2 con los datos cargados) y para **prellenar desde una plantilla**.

## 4. Plantillas — `finanzas_plantillas_screen.dart`

Pantalla con pestañas: Gasto / Ingreso / Todas. Lista las plantillas guardadas (nombre, categoría, tipo, monto si tiene uno fijo).

**Acciones disponibles aquí:**
- Tocar una plantilla → abre el panel de nueva transacción prellenado con sus datos, listo para confirmar o ajustar el monto.
- Botón flotante → crear una plantilla nueva.
- Editar plantilla existente → `editar_plantilla_sheet.dart` (usa el selector de categorías clásico, `categoria_selector_sheet.dart`, no el inline nuevo del paso 3).
- Eliminar una plantilla.

## 5. Estadísticas — `finanzas_estadisticas_screen.dart`

Pantalla de solo lectura con dos gráficos:
- Gráfico de pastel: distribución del gasto por categoría en el periodo seleccionado, con porcentajes.
- Gráfico de barras: ingresos vs. gastos mes a mes, para ver tendencia.

No tiene acciones de edición — es puramente de consulta.

## 6. Presupuestos — `finanzas_presupuesto_screen.dart`

Permite asignar un tope de gasto mensual a una categoría y ver cuánto se lleva gastado contra ese tope. Es la parte menos desarrollada del módulo: funcional pero básica, sin el nivel de pulido de las demás pantallas.

## Mapa de navegación resumido

```
Lobby de registros (finanzas_cuentas_screen)
 ├─ crear/editar/eliminar registro (en la misma pantalla)
 └─ tocar un registro
     └─ Historial del registro (finanzas_libro_transacciones_screen)
         ├─ swipe izq → eliminar transacción
         ├─ swipe der → editar transacción (abre nueva_transaccion_sheet)
         ├─ filtros / búsqueda (en la misma pantalla)
         ├─ FAB pequeño → Plantillas (finanzas_plantillas_screen)
         │    ├─ tocar plantilla → nueva_transaccion_sheet (prellenado)
         │    ├─ crear plantilla
         │    └─ editar plantilla → editar_plantilla_sheet
         │         └─ selector de categoría clásico (categoria_selector_sheet)
         └─ FAB principal → nueva_transaccion_sheet
              ├─ Paso 1: registro (si aplica)
              ├─ Paso 2: monto/tipo/categoría rápida/fecha/hora/lugar/nota
              └─ Paso 3: selector completo de categoría
                   └─ crear categoría nueva → categoria_selector_sheet (_NuevaCategoriaSheet)

(Accesibles desde otro punto de la navegación de Finanzas, no anidadas bajo un registro específico:)
Estadísticas (finanzas_estadisticas_screen) — solo lectura
Presupuestos (finanzas_presupuesto_screen) — gestión básica de topes
```

## Funcionalidades clave por pantalla (resumen rápido)

| Pantalla | Crear | Editar | Eliminar | Filtrar/buscar |
|---|---|---|---|---|
| Lobby de registros | ✅ registro | ✅ | ✅ | — |
| Historial | ✅ transacción (FAB) | ✅ (swipe der) | ✅ (swipe izq) | ✅ tipo, orden, agrupación, búsqueda texto |
| Plantillas | ✅ | ✅ | ✅ | ✅ pestañas por tipo |
| Estadísticas | — | — | — | ✅ por periodo |
| Presupuestos | ✅ | ✅ | ✅ | — |

## Notas de estado actual

- Todas las pantallas comparten los tokens de diseño del theme (`AppRadius`, `AppSpacing`, `AppTextSize`, `AppIconSize`) y el color de acento personalizable del usuario, con contraste automático de texto/ícono sobre ese acento (`legibleForegroundOn`).
- La única excepción de color fija en todo el módulo es verde/rojo para ingreso/gasto (monto de cada transacción y flechitas del resumen) — decisión de diseño consciente, no accidente de desarrollo.
- No existe aún navegación cruzada entre Créditos y Finanzas (por ejemplo, un pago de tarjeta reflejado como gasto en Finanzas) — los dos módulos son independientes por decisión de diseño.
