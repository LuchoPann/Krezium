# Fase 07 — Observaciones y sugerencias (cierre)

**Estado:** cerrada. Suite completa: 346/346.

## Capa determinista, no un sistema que inventa conclusiones

`lib/domain/finance_observaciones.dart` (con tests en
`test/domain/finance_observaciones_test.dart`) implementa 3 reglas, cada una
pura, basada solo en datos reales, que devuelve una lista **vacía** cuando
no hay evidencia suficiente — nunca rellena con algo que mostrar:

1. **`observacionesAumentoCategoria`** — gasto de una categoría este mes vs.
   el anterior. Exige **dos** umbrales a la vez (≥30% Y ≥$50.000 de
   diferencia absoluta) para evitar el caso clásico de "$1.000 → $3.000 es
   +200%" siendo ruido, no una señal útil. Reutiliza
   `comparacionPeriodoAnterior` de Fase 06 (ya filtra el caso sin base
   comparable).
2. **`observacionesPresupuestoCercano`** — presupuestos al 80% o más de su
   límite (mismo umbral que `estadoPresupuesto` de Fase 04, cercano +
   agotado).
3. **`observacionesMetaFueraDeRitmo`** — compara el progreso real de una
   meta activa contra el progreso que debería tener según cuánto tiempo ya
   pasó desde que se creó hasta su fecha límite; solo avisa si el rezago
   supera 15 puntos porcentuales. Ignora metas sin fecha límite (no hay
   ritmo esperado que calcular), ya cumplidas, pausadas, finalizadas o
   canceladas.

## Dónde se muestran (decisión de ubicación)

Se colocaron en **Estadísticas**, no en el lobby de Registros. La Fase 03 de
esta misma sesión había agregado y luego **retirado** un bloque de
observaciones en el lobby a pedido explícito del usuario
("solo es relleno" — ver `docs/finanzas-fase03-cierre.md`). Reabrir esa
discusión sin poder confirmar con el usuario (sesión nocturna no
supervisada) era el riesgo más alto de esta fase; Estadísticas ya es el
lugar "para entender cambios" según la propia arquitectura del roadmap, así
que las observaciones conviven ahí con el contexto que las explica, en vez
de competir por espacio en la pantalla de inicio. La sección completa se
oculta si no hay ninguna observación con evidencia.

## Qué cumple cada observación (checklist de la fase)

- Tiene datos suficientes (los umbrales de cada regla lo garantizan).
- Explica qué se observó y en qué periodo (texto con cantidades y mes/%
  explícitos, nunca solo una cifra suelta).
- Ofrece una acción útil: cada tarjeta es tocable y navega a la fuente —
  aumento de categoría → historial filtrado a esa categoría (mismo patrón
  de Fase 06); presupuesto/meta → Planificación.
- No es moralizante ni alarmista: tono descriptivo ("Gastaste X% más...",
  "Vas en X% del presupuesto..."), sin juicios de valor.
- No se repite de forma molesta: no hay persistencia de "ya vista" en esta
  primera versión — las reglas solo producen una observación por
  categoría/presupuesto/meta por sesión de cálculo, no se acumulan ni se
  insisten.

## Pendiente explícito (no implementado, fuera de alcance de esta fase)

No hay mecanismo de "descartar"/"ya la vi" persistente entre sesiones —
cada recálculo vuelve a mostrar la misma observación si la condición sigue
vigente. Si se vuelve molesto en el uso real, es candidato para Fase 08 o
una mejora aparte.
