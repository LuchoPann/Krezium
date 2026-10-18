# Krezium — qué probar de los cambios nuevos

Guía simple para entender qué se construyó, para qué sirve, y cómo
probarlo paso a paso — con lo que deberías ver en pantalla en cada paso,
para que sepas si algo salió mal o está bien.

Antes de empezar: cerrá la app del todo (no solo minimizarla) y volvé a
abrirla, para que se active todo lo nuevo desde cero.

---

## 1. Presupuestos guiados

**Para qué sirve:** antes, crear un presupuesto era llenar un formulario
en blanco — vos tenías que adivinar cuánto poner de límite. Ahora la app
te ayuda: mira tu historial de gasto de los últimos 3 meses en esa
categoría y te sugiere un monto razonable, en vez de dejarte solo con un
campo vacío.

**Cómo funciona por dentro:** la app calcula cuánto gastaste en esa
categoría en cada uno de los últimos 3 meses, y te sugiere el valor del
medio (ni el más alto ni el más bajo, para que un mes raro no te
desvíe). Si no tenés suficiente historial (menos de 2 meses con gasto en
esa categoría), prefiere no inventar un número y te deja escribirlo vos.

### Paso a paso

1. Entrá a **Planificación → Presupuestos** y tocá el botón de crear uno
   nuevo (el "+").
   - **Qué deberías ver:** una pantalla pidiéndote elegir una categoría,
     con la lista de tus categorías de gasto.
2. Elegí una categoría en la que ya hayas gastado plata en meses
   anteriores (por ejemplo, Comida o Transporte).
   - **Qué deberías ver:** la pantalla avanza sola al siguiente paso.
3. En el paso de "sugerencia":
   - **Si tenés historial suficiente**, deberías ver un monto sugerido
     grande, y debajo una frase tipo "Basado en tus últimos 3 meses:
     ago $X, sep $Y, oct $Z" — y un botón para usar esa sugerencia.
   - **Si no tenés historial suficiente**, deberías ver un mensaje
     explicando que falta información, sin ningún monto inventado.
4. Tocá "Siguiente" (o "Usar esta sugerencia" y después "Siguiente").
   - **Qué deberías ver:** un campo para escribir o ajustar el monto del
     límite. Si ya gastaste algo este mes en esa categoría, debería
     decirte "Ya gastado este mes: $X" y "Con este límite quedarían: $Y"
     actualizándose mientras escribís.
5. Confirmá en el último paso.
   - **Qué deberías ver:** un resumen con la categoría, el mes y el
     límite elegido, y un botón de "Crear presupuesto".
6. Volvé a la lista de presupuestos.
   - **Qué deberías ver:** una tarjeta nueva con el nombre de la
     categoría, una barra de progreso, cuánto llevas gastado y cuánto es
     el límite. Si vas gastando más rápido de lo que corresponde para el
     día del mes en que estás, debería aparecer un textito amarillo tipo
     "Vas más rápido de lo esperado para este punto del mes" (esto NO
     debería aparecer si el presupuesto ya está en rojo/agotado, ahí ya
     es suficiente el aviso de "Agotado").
7. Tocá esa tarjeta para editarla.
   - **Qué deberías ver:** la categoría ya no se puede cambiar (está
     fija), solo el monto del límite.
8. Intentá crear otro presupuesto para esa misma categoría.
   - **Qué deberías ver:** esa categoría ya no aparece en la lista para
     elegir (porque ya tiene presupuesto este mes).

---

## 2. Metas de ahorro

**Para qué sirve:** una meta te deja apartar plata para un objetivo (un
viaje, un portátil) sin que esa plata cuente como "gastada" ni se mueva
de verdad a ningún lado — es más como ponerle una etiqueta a una parte de
tu dinero para no tocarlo por accidente.

**Cómo funciona por dentro:** hay dos formas de crear una meta:
- **Vinculada a una cuenta:** la plata apartada "vive" dentro de un
  registro que ya tengas (por ejemplo, tu cuenta de ahorros), y se resta
  de lo que esa cuenta te muestra como disponible.
- **Virtual:** no está atada a ninguna cuenta en particular, se resta de
  tu disponible general.

Aportar o retirar de una meta nunca crea un ingreso o un gasto falso —
es un movimiento interno, pero ahora queda guardado en un historial para
que puedas ver qué aportaste y cuándo.

### Paso a paso

1. Andá a **Planificación → Metas** y creá una meta nueva.
   - **Qué deberías ver:** un formulario pidiendo nombre, monto
     objetivo, y una opción para elegir entre "Vinculada a una cuenta"
     (con un selector de cuál cuenta) o "Virtual (sin cuenta)".
2. Creá una primera meta como **vinculada** a un registro que ya tengas,
   con una fecha límite a futuro.
   - **Qué deberías ver:** la meta aparece en la lista con el nombre de
     la cuenta debajo, y si tiene fecha, cuánto te falta aportar por mes
     para llegar a tiempo.
3. Creá una segunda meta como **virtual**.
   - **Qué deberías ver:** en la lista, en vez del nombre de una cuenta,
     debería decir algo como "Virtual · disponible global".
4. Tocá cualquiera de las dos metas y elegí "Aportar". Metele un monto.
   - **Qué deberías ver:** la barra de progreso de la meta avanza, y el
     monto acumulado sube.
5. Volvé a entrar a esa meta.
   - **Qué deberías ver:** una sección de **Historial** con el aporte
     que acabás de hacer, la fecha, y cuánto quedó acumulado en total
     después de ese aporte.
6. Tocá "Marcar como cumplida" en una de las metas.
   - **Qué deberías ver:** la app te pregunta explícitamente qué hacer
     con la plata reservada, con dos opciones: "Gastar ahora" o
     "Mantener en un registro". Nunca debería cerrar la meta sin
     preguntarte esto.
   - Probá **"Gastar ahora"**: debería abrirte el formulario normal de
     registrar un gasto, con el monto ya puesto (vos elegís la
     categoría).
7. Con la otra meta, probá **"Mantener en un registro"**.
   - **Qué deberías ver:** te deja elegir un registro que ya tengas, o
     crear uno nuevo con un nombre. Al confirmar, el saldo de ese
     registro debería subir por el monto de la meta.
8. Volvé a intentar cerrar una meta (completar o cancelar) pero esta vez
   tocá "atrás" sin elegir ninguna opción.
   - **Qué deberías ver:** la meta sigue exactamente igual que antes,
     con el mismo monto reservado — no debería haber cambiado nada.
9. Andá a Registros e intentá borrar la cuenta que tiene la meta
   vinculada activa.
   - **Qué deberías ver:** un aviso de que esa cuenta tiene una meta
     asociada, con la opción de reasignarla a otra cuenta o convertirla
     en virtual — nunca un error genérico sin explicación.

---

## 3. Conexión entre Registros y Planificación

**Para qué sirve:** antes, Registros y Planificación estaban separados —
tenías que acordarte vos mismo de ir a revisar tus presupuestos o metas.
Ahora la app te muestra esa información en el momento justo, sin que
tengas que ir a buscarla.

### Paso a paso

1. Registrá un gasto nuevo en una categoría que **ya tenga presupuesto**
   este mes.
   - **Qué deberías ver:** justo debajo de donde elegís la categoría,
     una línea mostrando cuánto llevas gastado de ese presupuesto y
     cuánto te queda (o, si ya te pasaste, cuánto lo excediste, en rojo).
     Esto nunca debería impedirte guardar el gasto, aunque te excedas.
2. Registrá un gasto en una categoría **sin** presupuesto.
   - **Qué deberías ver:** un texto tipo "Crear presupuesto para
     {categoría}" — tocalo y debería abrirte el flujo guiado de crear
     presupuesto (el mismo del punto 1) sin perder lo que ya habías
     escrito en el formulario de gasto.
3. Desde la lista de **Planificación → Presupuestos**, tocá el ícono de
   "Ver movimientos" (uno con forma de recibo) en cualquier tarjeta.
   - **Qué deberías ver:** si solo tenés un registro, te lleva directo
     al historial de movimientos filtrado por esa categoría. Si tenés
     varios registros, primero te pregunta en cuál mirar.
4. Registrá un **ingreso** (asegurate de tener al menos una meta activa
   primero).
   - **Qué deberías ver:** al guardar, un mensaje abajo de la pantalla
     (tipo aviso) ofreciéndote "Apartar a una meta" — tocalo y debería
     abrirte el sheet de aportar con el monto del ingreso ya puesto
     (podés cambiarlo).
5. Pausá o cancelá todas tus metas activas, y registrá otro ingreso.
   - **Qué deberías ver:** esta vez el mensaje de "Apartar a una meta"
     NO debería aparecer (porque no hay ninguna meta activa a la cual
     apartar).

---

## 4. Estadísticas

**Para qué sirve:** que de un vistazo entiendas no solo cuánto gastaste,
sino si eso es bueno o malo comparado con lo normal, y qué hacer al
respecto.

### Paso a paso

1. Entrá a **Estadísticas**, con el período en "Este mes" y un registro
   que tenga ingresos y gastos tanto este mes como el anterior.
   - **Qué deberías ver:** arriba, el resumen de Balance, con una barra
     de colores mostrando la proporción entre ingresos y gastos.
2. Mirá debajo de los montos de Ingresos y Gastos.
   - **Qué deberías ver:** una frase nueva sobre cuánto ahorraste, del
     tipo "Ahorraste el 30% de tus ingresos este mes" — o si gastaste más
     de lo que entró, "Gastaste 20% más de lo que ingresó este mes" (en
     rojo).
3. Probá con un mes en el que no hayas registrado ningún ingreso.
   - **Qué deberías ver:** esa frase de ahorro no debería aparecer en
     absoluto (ni un "0%" raro).
4. Mirá la leyenda del gráfico de torta (las categorías de gasto).
   - **Qué deberías ver:** en las categorías donde gastaste tanto este
     mes como el anterior, una flechita (arriba o abajo) con un
     porcentaje, mostrando si gastaste más o menos que el mes pasado. En
     una categoría que es nueva este mes (no gastaste nada el mes
     pasado), no debería aparecer ninguna flecha ni porcentaje.
5. Si alguna de esas categorías ya tiene presupuesto asignado.
   - **Qué deberías ver:** un segundo ícono pequeño (de torta) al lado
     del nombre — tocándolo te lleva directo a Planificación, en vez de
     al historial de movimientos (ese sigue siendo el ícono de flecha).
6. Cambiá el período arriba a "3 meses", "6 meses" o "Este año".
   - **Qué deberías ver:** ni la frase de comparación con el mes
     anterior ni las flechitas de variación por categoría deberían
     aparecer — es a propósito, esas comparaciones solo tienen sentido
     para "Este mes".

---

## 5. Chequeo general (que nada se haya roto)

1. Entrá a **Créditos** y mirá cualquier tarjeta o movimiento.
   - **Qué deberías ver:** todo exactamente igual que siempre — este
     cambio no debería haber tocado nada de Créditos.
2. Si en algún momento algo se ve raro, vacío, o no carga.
   - Antes de asumir que es un error real: cerrá la app del todo (no
     solo minimizarla) y abrila de nuevo. Muchas veces alcanza con eso.

---

## Si algo falla

Contame en qué número de la lista estabas (por ejemplo "en el punto
3.2") y qué viste en vez de lo que esperabas — con eso puedo ir directo a
revisar el código sin tener que adivinar qué pasó.
