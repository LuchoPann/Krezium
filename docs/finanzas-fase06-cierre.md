# Fase 06 — Estadísticas (cierre)

**Estado:** cerrada. Suite completa: 330/330.

## Qué se mantuvo sin cambios

Siguiendo el mandato de la fase ("mantener los gráficos existentes"), el
donut de gastos por categoría y el bar chart de tendencia mensual no se
tocaron en su lógica ni en su visual — solo se les agregó interacción
nueva (drill-down) sin alterar lo que ya funcionaba.

## Qué se agregó

- **Comparación con el mes anterior** (`comparacionPeriodoAnterior` en
  `lib/domain/finance_ledger.dart`, con tests): compara el gasto del mes
  actual contra el mes calendario inmediatamente anterior. Devuelve `null`
  —y la UI no muestra nada— cuando el mes anterior no tiene datos, porque
  un % de variación contra cero es una cifra sin sentido, no una
  comparación real. Solo se muestra para el periodo "Este mes": comparar
  "3 meses" o "6 meses" contra el bloque anterior de igual longitud sería
  más ambiguo que útil, así que se dejó fuera de alcance deliberadamente.
  El texto siempre da cantidades y el mes explícitos (ej. "Gastaste 23%
  más que en septiembre: $450.000 → $553.000."), nunca solo un porcentaje
  suelto.
- **Navegar de un resultado a los movimientos que lo originan**: la
  leyenda del donut ahora es tocable (excepto "Otros", que agrupa varias
  categorías y no tiene un único filtro posible) y lleva directo al
  historial del registro activo, filtrado a esa categoría exacta.
  - `FinanzasFiltros` (`lib/data/finanzas_filtros.dart`) gana un campo
    `categoriaId` opcional, aplicado en `finanzasLibroTxProvider`
    (`lib/providers/finance_provider.dart`).
  - El historial (`finanzas_libro_transacciones_screen.dart`) muestra un
    chip "Categoría: X" con botón para quitar el filtro cuando está activo
    — sin esto, nada explicaría por qué el listado aparece recortado.
  - Entrar al historial por el flujo normal (tocar un registro desde
    Cuentas) siempre limpia ese filtro explícitamente, para que no quede
    un filtro de una sesión de Estadísticas aplicado por sorpresa en una
    visita normal.

## Hallazgo (no corregido, fuera de alcance de esta fase)

El filtro `tipoFiltro` ('todos'/'ingreso'/'gasto') del historial sí se
aplica correctamente — se verificó al implementar `categoriaId` junto a
él en `finanzasLibroTxProvider`, contrario a lo que una lectura rápida del
widget de filtros sugería. No hubo que corregir nada ahí.
