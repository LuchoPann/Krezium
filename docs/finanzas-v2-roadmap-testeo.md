# Finanzas v2 — roadmap de testeo manual

Guía para validar con datos reales en tu dispositivo todo lo construido
en el roadmap v2 (Fases A-G, `docs/finanzas-v2-roadmap.md`). Nadie más
que vos puede correr esto — el asistente nunca usa `flutter run`, así que
nada de lo de abajo fue probado visualmente, solo con tests automatizados
y lectura de código. Hacé hot-restart y seguí el orden: cada bloque
depende de datos creados en el anterior.

## 0. Antes de empezar

- Hot-restart (no hot-reload) para asegurar que corre la migración de
  schema v20→v21.
- Si algo se ve raro en el primer render tras la migración, cerrá del
  todo la app y volvé a abrirla una vez — confirma que no era solo un
  frame transitorio del primer load de providers.

## 1. Presupuestos guiados (Fase A/B)

1. Andá a **Planificación → Presupuestos** → "+".
2. **Paso 1**: elegí una categoría de gasto que ya tenga movimientos en
   los últimos meses (ideal: con gasto en al menos 2 de los últimos 3
   meses de calendario).
3. **Paso 2**: deberías ver una sugerencia con el desglose de esos 3
   meses. Probá también con una categoría sin apenas historial — ahí no
   debería aparecer ninguna sugerencia, solo el aviso de que falta
   información.
4. **Paso 3**: cambiá el monto y confirmá que "ya gastado"/"quedarían" se
   actualiza en vivo.
5. **Paso 4**: confirmá y creá el presupuesto.
6. Volvé a la lista: la tarjeta debe mostrar %, gastado/límite, y si el
   consumo va "más rápido de lo esperado" para el día del mes en que
   estás, el texto de ritmo (no debería aparecer si el presupuesto ya
   está en rojo/agotado — ahí solo el badge de "Agotado").
7. Intentá editar ese presupuesto: la categoría no debe ser editable,
   solo el monto.
8. Intentá crear otro presupuesto para la misma categoría: no debería
   aparecer en el selector (ya tiene uno este mes).

## 2. Metas de ahorro (Fase A/B)

1. **Planificación → Metas** → "+".
2. Creá una meta **vinculada** a un registro existente, con fecha límite
   a futuro. Confirmá que el "disponible" de ese registro baja al
   aportar.
3. Creá una segunda meta **virtual** (sin cuenta). Aportale algo y
   confirmá que el disponible de un registro puntual NO cambia (la
   reserva virtual no debería tocar el disponible de un registro
   específico, solo el global si en algún lado de la UI se muestra ese
   total — si no lo ves en ningún lado todavía, está bien, es un cálculo
   interno sin pantalla dedicada aún).
4. Abrí la hoja de acciones de cualquiera de las dos metas: debería
   aparecer un **Historial** con cada aporte/retiro, fecha y saldo
   resultante tras esa operación.
5. Tocá **"Marcar como cumplida"** en la meta vinculada: debe preguntarte
   explícitamente "Gastar ahora" o "Mantener en un registro" — nunca
   debe cerrar la meta en silencio.
   - Probá **"Gastar ahora"**: te debe abrir un formulario de gasto con
     el monto precargado; al guardarlo, la meta debe quedar en 0/cerrada.
   - Con la otra meta probá **"Mantener en un registro"**, eligiendo un
     registro existente o creando uno nuevo con nombre — confirmá que el
     saldo de ese registro sube por el monto de la meta y que queda una
     nota "Proveniente de meta: ...".
6. Cerrá el sheet de cierre sin elegir ninguna opción (botón atrás): la
   meta debe seguir intacta, con el mismo monto reservado que antes.
7. Con un tercer registro, creá una meta vinculada a él, y probá borrar
   ese registro desde Registros: debe avisarte que tiene una meta
   vinculada y ofrecerte reasignarla a otra cuenta o convertirla a
   virtual, nunca un error genérico.

## 3. Conexión Registros ↔ Planificación (Fase C)

1. Registrá un **gasto nuevo** en una categoría que ya tenga presupuesto
   este mes: justo debajo del selector de categoría debería aparecer el
   resumen "gastado/límite/restante" de ese presupuesto, sin bloquear el
   guardado aunque lo excedas.
2. Registrá un gasto en una categoría **sin** presupuesto: debería
   aparecer un texto "Crear presupuesto para {categoría}" — tocalo y
   confirmá que abre el flujo guiado completo sin perder lo que ya
   llevabas escrito en el formulario de la transacción.
3. Desde **Planificación → Presupuestos**, tocá el ícono de "Ver
   movimientos" de cualquier tarjeta: si tenés un solo registro va
   directo al historial filtrado por esa categoría; con varios, primero
   te pregunta cuál.
4. Registrá un **ingreso**: al guardar debería aparecer un SnackBar con
   la acción "Apartar a una meta" (solo si tenés al menos una meta
   activa) — probá tocarlo y confirmá que abre el sheet de aportar con
   el monto del ingreso precargado, editable.
5. Registrá un ingreso cuando NO tengas ninguna meta activa (pausá o
   cancelá las que tengas): el SnackBar de "apartar" no debería
   aparecer en absoluto.

## 4. Estadísticas (Fase E)

1. Andá a **Estadísticas**, período "Este mes", con algún libro que
   tenga ingresos y gastos registrados este mes y el anterior.
2. En el hero de resumen, debajo de Ingresos/Gastos, confirmá que
   aparece la tasa de ahorro ("Ahorraste X% de tus ingresos" o, si
   gastaste más de lo que entró, "Gastaste X% más de lo que ingresó").
3. Con un mes sin ningún ingreso registrado, esa línea no debería
   aparecer en absoluto (ni un 0% engañoso).
4. En la leyenda del pastel, categorías con gasto tanto este mes como el
   anterior deberían mostrar una flechita y el % de variación. Una
   categoría nueva este mes (sin gasto el mes pasado) no debería mostrar
   ninguna variación.
5. Si alguna categoría del pastel ya tiene presupuesto asignado, debería
   verse un segundo ícono (de torta) junto al de "ir a movimientos" — al
   tocarlo te lleva a Planificación en vez de al historial.
6. Cambiá el período a "3 meses"/"6 meses"/"Este año": ni la comparación
   de totales ni la variación por categoría deberían aparecer (eso solo
   aplica a "Este mes", a propósito).

## 5. Regresión general

- Créditos: abrí cualquier tarjeta de crédito, registrá un movimiento,
  confirmá que nada de esto afectó su comportamiento (el roadmap nunca
  tocó ese módulo).
- Backup/exportar: como ya sabés, Finanzas completo (incluida toda esta
  Planificación v2) sigue sin estar incluido en el sistema de copias de
  seguridad de la app — pendiente transversal, no se resolvió en este
  roadmap.
- Si algo se ve raro, probá cerrar del todo la app (no solo hot-restart)
  y abrirla de nuevo — descarta que sea un estado de provider cacheado
  de una sesión de desarrollo anterior.

## Qué avisarme si algo falla

Decime en qué paso del número de sección (ej. "3.2") y qué viste en vez
de lo esperado — con eso puedo ir directo al código en vez de
reconstruir el escenario desde cero.
