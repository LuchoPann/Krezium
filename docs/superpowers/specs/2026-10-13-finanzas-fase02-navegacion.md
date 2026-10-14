# Finanzas — Fase 02: Navegación y estructura de vistas

**Spec derivada de:** `UltimoChatConGPT.md` (roadmap de 9 fases) + auditoría de código real + `docs/finanzas-roadmap.md` (Fase 00 y Fase 01 cerradas).

**Estado:** Fase 02 autorizada para implementación. Fase 03 en adelante permanecen bloqueadas.

## 1. Alcance autorizado

- Reordenar la navegación principal de Finanzas: **Registros · Planificación · Estadísticas · Cuenta**.
- Crear la vista "Planificación" como destino nuevo, mostrando por ahora únicamente Presupuestos (envuelve la pantalla existente `FinanzasPresupuestoScreen`, hoy huérfana/sin ruta). No se agrega una sección de "Metas de ahorro" todavía — esa UI es Fase 05. No se presenta como si existiera algo que no existe.
- Sacar `FinanzasPlantillasScreen` (gestión completa: crear/editar/eliminar) de la navegación principal.
- Garantizar que Plantillas siga siendo accesible: añadir un acceso a la pantalla de administración completa desde el sheet rápido de selección de plantillas que ya existe en el historial (`_PlantillasSheet`, `finanzas_libro_transacciones_screen.dart`).
- Verificar que el cambio Créditos↔Finanzas conserve el estado de cada entorno (ya lo hace hoy vía `finanzasTabProvider`/`creditosTabProvider` independientes — no se toca esa parte).

Prohibido en esta fase: rediseñar pantallas existentes más allá de envolver Presupuestos en el nuevo destino, tocar Créditos, tocar Registros/Historial/categorías/plantillas en su funcionalidad (solo el punto de entrada a Plantillas cambia), implementar Metas de ahorro, mejorar Presupuestos funcionalmente (eso es Fase 04 — aquí solo se le da una ruta de acceso).

## 2. Hallazgos de la auditoría que esta fase debe resolver

1. `FinanzasPresupuestoScreen` no está enrutada en ningún lado — queda huérfana, inaccesible al usuario. Esta fase le da una ruta real (dentro de "Planificación").
2. `lib/main.dart`'s `destinations` (líneas ~435-446) tiene el label "Estadísticas" escrito a mano, no derivado dinámicamente de `finanzasScreens[2]` — asume que ese índice siempre es Estadísticas. Al insertar "Planificación" en medio del array, este acoplamiento debe corregirse explícitamente, no asumirse.
3. `isAccount = currentTab == 3` (línea 316) y el salto directo `finanzasTabProvider.notifier.state = 3` (línea ~419) asumen que el índice 3 (fuera del array de 3 tabs) es Cuenta — esto no cambia en esta fase (Cuenta sigue siendo el último destino), pero cualquier renumeración de `finanzasScreens` debe revisarse contra estas dos asunciones para no romperlas.
4. `FinanzasPlantillasScreen` no tiene ningún acceso secundario fuera de la navegación principal hoy — **excepto** el sheet rápido `_PlantillasSheet` (FAB en historial), que permite *usar* una plantilla pero no *administrarlas* (crear/editar/eliminar). Esta fase debe añadir ese acceso de administración ahí, antes de retirar la pantalla completa de la nav principal — nunca al revés.

## 3. Diseño de la vista "Planificación"

- Nueva pantalla ligera (no una pantalla "gigante", per GPT): envuelve directamente `FinanzasPresupuestoScreen` como su único contenido por ahora. No se construye un dashboard nuevo ni tarjetas de resumen propias en esta fase — eso puede venir en Fase 04 cuando Presupuestos se mejore funcionalmente.
- Ícono de la barra de navegación: `Icons.savings_outlined` (ya existe en el catálogo de íconos de Finanzas, consistente con el proyecto).
- Si en el futuro (Fase 05) se agrega Metas de ahorro, este mismo destino las absorbe — no se crea una quinta pestaña.

## 4. Diseño del acceso a Plantillas

- Dentro de `_PlantillasSheet` (el sheet rápido que ya se abre desde el FAB del historial), añadir una entrada "Administrar plantillas" (texto + ícono, al final de la lista o como acción en el AppBar del sheet) que haga `Navigator.push` a `FinanzasPlantillasScreen` (pantalla completa, fuera del sheet).
- `FinanzasPlantillasScreen` en sí no cambia — sigue siendo la misma pantalla de crear/editar/eliminar, solo cambia cómo se llega a ella (push normal en vez de tab de la nav principal).
- Se retira la entrada de `finanzasScreens` en `main.dart` correspondiente a Plantillas.

## 5. Diseño del cambio en `main.dart`

- `finanzasScreens` pasa de `[Cuentas, Plantillas, Estadísticas]` a `[Cuentas, Planificación, Estadísticas]` (incluyendo índices y comentarios actualizados para que quede explícito qué representa cada índice, dado que el acoplamiento previo por posición fue justamente el problema encontrado en la auditoría).
- El array `destinations` de la barra de navegación deja de tener el label "Estadísticas" como texto fijo asumiendo una posición — se construye explícitamente a partir de una lista de (ícono, label) por tab de Finanzas definida junto a `finanzasScreens`, para que el acoplamiento índice↔label quede en un solo lugar visible, no repetido/asumido en dos sitios distintos del archivo.
- `isAccount == 3` y el salto `=3` no cambian numéricamente (Cuenta sigue siendo la posición 3 fuera del array de 3 tabs), pero se revisan y se comentan explícitamente como "estos números dependen de `finanzasScreens` tener exactamente 3 elementos" para que una fase futura no los rompa sin darse cuenta.
- `_visitedFinanzas` (el Set de índices montados perezosamente) no requiere cambios de lógica — solo cambia qué pantalla corresponde a cada índice, lo cual es transparente para ese mecanismo.

## 6. Reglas globales (vigentes desde `UltimoChatConGPT.md`)

- No reconstruir Registros/Historial/categorías/plantillas en su funcionalidad.
- No tocar Créditos.
- No implementar funciones simuladas ni UI de algo que no existe (Metas de ahorro no se menciona ni se deja un placeholder vacío en Planificación).
- Local-first, sin servicios externos.
- No avanzar a Fase 03 sin autorización explícita al cerrar esta fase.

## 7. Criterios de aceptación

- La navegación principal de Finanzas muestra Registros, Planificación, Estadísticas, Cuenta, en ese orden.
- Tocar "Planificación" muestra Presupuestos funcionando igual que antes (sin regresión en lo que ya hacía, aunque siga siendo limitado — eso es Fase 04).
- Plantillas sigue totalmente funcional (crear/editar/eliminar/usar) y accesible, solo que vía el sheet rápido del historial → "Administrar plantillas", no desde la barra de navegación principal.
- Cambiar entre Créditos y Finanzas conserva el tab activo de cada entorno (sin regresión, no se toca esa lógica).
- El acoplamiento índice↔pantalla↔label en `main.dart` queda en un único lugar explícito, no repetido/asumido en múltiples puntos del archivo.
- `flutter test` y `dart analyze` limpios, sin regresión en el resto de la app (especialmente Créditos, que comparte el mismo Scaffold/nav).

## 8. Plan mínimo de pruebas

Dado que `main.dart` no tiene arnés de widget-test previo en el proyecto (confirmado en fases anteriores), la verificación aquí es principalmente `dart analyze` + revisión manual del usuario en dispositivo (el asistente nunca ejecuta `flutter run`). Donde sea posible, se añade un test unitario para cualquier función pura que se extraiga (p.ej. si la lista de (ícono,label) por tab se convierte en una estructura de datos testeable de forma aislada).

## 9. Reporte de cierre obligatorio

Igual que Fase 01: archivos modificados y motivo, decisiones de diseño, pruebas ejecutadas, limitaciones pendientes (Presupuestos sigue funcionalmente limitado, eso es Fase 04; Metas de ahorro no existe aún, eso es Fase 05), confirmación explícita de que Fase 03 no inició.
