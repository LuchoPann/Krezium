# Finanzas — Fase 02: Navegación y estructura de vistas — cierre

**Spec:** [`docs/superpowers/specs/2026-10-13-finanzas-fase02-navegacion.md`](./superpowers/specs/2026-10-13-finanzas-fase02-navegacion.md)

## Alcance real vs. previsto

La auditoría inicial de la spec asumía que podría hacer falta renumerar/corregir el acoplamiento índice↔label en `lib/main.dart` (el label "Estadísticas" está escrito a mano, no derivado dinámicamente del array `finanzasScreens`). Al revisar el código real se confirmó que **ambos entornos** (Créditos y Finanzas) ya tienen "Estadísticas" en la posición 2 de su array de 3 pantallas — es decir, el acoplamiento existe pero no se rompe con este cambio, porque el índice que se reemplaza es el 1 (antes Plantillas, ahora Planificación), no el 2. No fue necesario tocar `isAccount == 3`, el salto `=3`, ni la fórmula de `navIndex` — ninguno depende de qué pantalla haya en el índice 1.

Esto redujo el alcance real a 3 cambios quirúrgicos, sin necesidad de ejecutar el proceso completo de subagentes (justificado: bajo riesgo, cambio acotado, ya verificado contra el código real antes de tocar nada).

## Archivos modificados

- `lib/main.dart`: import de `FinanzasPresupuestoScreen` en vez de `FinanzasPlantillasScreen`; `finanzasScreens[1]` pasa de `FinanzasPlantillasScreen()` a `FinanzasPresupuestoScreen()`; el `NavigationDestination` correspondiente cambia de ícono/label `receipt_long`/"Plantillas" a `savings`/"Planificación". Comentario añadido explicando el porqué del índice 1 y la futura absorción de Metas de ahorro (Fase 05) en el mismo destino.
- `lib/screens/finanzas/finanzas_libro_transacciones_screen.dart`: el sheet rápido de plantillas (`_PlantillasSheet`, ya existente) gana un botón "Administrar" junto al título, que cierra el sheet y navega (push normal) a `FinanzasPlantillasScreen` — la pantalla completa de crear/editar/eliminar plantillas, que ya no vive en la navegación principal.

## Decisiones de diseño

- "Planificación" por ahora muestra únicamente `FinanzasPresupuestoScreen` tal cual existe (sin wrapper ni rediseño) — ya es un `Scaffold` completo con su propio AppBar, igual que las demás pantallas de tab. No se agregó ninguna sección de Metas de ahorro ni placeholder vacío (Fase 05 construirá esa UI cuando corresponda, en el mismo destino).
- Plantillas conserva el 100% de su funcionalidad (crear/editar/eliminar/usar); solo cambió cómo se llega a la administración completa — antes por tab principal, ahora desde el sheet rápido del historial.
- Ícono elegido para Planificación: `Icons.savings_outlined`/`Icons.savings`, ya existente en el catálogo de íconos del proyecto, consistente con las convenciones ya usadas (Material Icons, no un ícono nuevo foráneo).

## Pruebas

- `dart analyze` en los 2 archivos tocados: sin issues.
- `flutter test` completo: 288/288 (sin cambio respecto a Fase 01 — esta fase no añadió ni quitó lógica testeable, es reconexión de navegación).
- No se ejecutó la app en dispositivo (restricción permanente de la sesión) — pendiente que el usuario confirme visualmente el cambio de label/ícono en su propio teléfono.

## Limitaciones conocidas / fuera de alcance

- `FinanzasPresupuestoScreen` sigue siendo funcionalmente limitada (bugs documentados en la auditoría de Fase 00: sin ruta de creación de presupuestos desde la UI, `deleteFinanceBudget` no implementado, bug con categorías personalizadas) — **no se tocó nada de eso aquí**, solo se le dio una ruta de navegación real. Corresponde a Fase 04.
- Metas de ahorro no existen como UI — Fase 05.
- El acoplamiento índice↔label en `main.dart` sigue siendo implícito (coincidencia de que ambos entornos tienen Estadísticas en el índice 2) — funciona hoy pero queda documentado en el comentario añadido para que una fase futura no lo rompa sin darse cuenta.

## Confirmación

Fase 03 no ha iniciado. Se espera autorización explícita del usuario para continuar.
