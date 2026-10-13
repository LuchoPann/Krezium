# Cómo funciona hoy el módulo de Finanzas (Krezium)

Este documento explica, en lenguaje natural, cómo está construido y cómo se comporta en la práctica el módulo de Finanzas de la app. Es para dar contexto a alguien que no conoce el código (por ejemplo, para discutir mejoras o rediseños), no un manual técnico de referencia exhaustivo.

## Qué es el módulo de Finanzas dentro de la app

Krezium es una app de gestión financiera personal que originalmente nació enfocada en créditos y deudas (tarjetas de crédito, préstamos). Finanzas es un segundo módulo, independiente del de Créditos, pensado para que el usuario también pueda llevar su día a día de ingresos y gastos cotidianos, sin que eso tenga nada que ver con sus tarjetas o préstamos.

La app tiene una navegación inferior "dual": hay un botón central que permite saltar entre el entorno de Créditos y el entorno de Finanzas, cada uno con sus propias pestañas internas. Es decir, Finanzas no es una pestaña más dentro de Créditos, es un mundo aparte con su propia navegación, aunque comparten la misma base de datos SQLite y el mismo sistema de temas (colores, tipografía, etc.).

## El concepto central: "registros" (cuentas)

Dentro de Finanzas, lo primero que el usuario ve es una pantalla tipo "lobby" donde puede crear uno o varios **registros**. Un registro es básicamente una cuenta o bolsillo de dinero: puede ser "Efectivo", "Cuenta de ahorros", "Nequi", "Tarjeta débito", lo que sea. Cada registro tiene:

- Un nombre.
- Un tipo general (efectivo, digital o bancaria) — esto es más que todo informativo/visual.
- Un ícono y un color propios, elegidos por el usuario al crearlo.
- Un saldo inicial (el dinero con el que "arranca" ese registro).
- Si está activo o no, si es el favorito/principal, una descripción opcional, y un orden para la lista.

El usuario puede tener varios registros a la vez y todos aparecen como tarjetas en esa pantalla lobby, cada una mostrando su balance actual (saldo inicial + ingresos − gastos de ese registro) de forma protagonista, y debajo los totales de ingresos y gastos de ese registro en texto más discreto.

Todas las transacciones (ingresos y gastos) pertenecen siempre a un registro específico. No existe un "balance global" real de ingresos/gastos mezclando registros más allá de una suma visual en el header de la pantalla lobby — cada registro vive su vida de forma independiente.

## El concepto central: transacciones

Una transacción es un movimiento de dinero: un ingreso o un gasto. Cada transacción tiene:

- A qué registro pertenece.
- Qué tipo es (ingreso o gasto).
- A qué categoría pertenece (ver más abajo).
- Un monto.
- Una fecha y, opcionalmente, una hora.
- Una nota libre (texto corto describiendo qué fue).
- Un "lugar u ordenante" opcional: dónde se hizo el gasto o de quién vino el ingreso (por ejemplo "Supermercado Éxito" o "Juan Pérez").
- Opcionalmente, puede ser parte de una transferencia entre dos registros del propio usuario (mover plata de un registro a otro sin que cuente como ingreso o gasto real).

Las transacciones no tienen todavía un sistema de recurrencia real implementado en la interfaz (hay campos en la base de datos preparados para eso, pero no se usan activamente hoy).

## El sistema de categorías y subcategorías

Esta es la parte más elaborada del módulo. Las categorías existen en dos niveles:

1. **Categorías padre**: son agrupadores grandes y fijos, definidos por la propia app (no los crea el usuario). Hoy existen ocho: Ingresos, Alimentación, Transporte, Salud, Vivienda, Educación, Ocio y Otros.
2. **Subcategorías**: son las categorías reales que se le asignan a cada transacción. Cada subcategoría pertenece a una categoría padre. Por ejemplo, dentro de "Transporte" existen subcategorías como Carro, Moto, Bicicleta, Taxi/App, Bus/Transporte público, Avión.

Además del catálogo fijo que trae la app (unas 35 subcategorías predefinidas, repartidas en esos 8 grupos), el usuario puede crear sus propias categorías personalizadas: les pone nombre, elige a qué categoría padre pertenecen (o ninguna), les asigna un ícono de una biblioteca amplia de íconos (recientemente se amplió bastante, de unos 40 a más de 140 opciones, organizadas por temas: comida, transporte, hogar, salud, tecnología, etc.), y el tipo (ingreso, gasto o ambos). Esas categorías personalizadas quedan guardadas en la base de datos del usuario, mientras que las categorías fijas del sistema viven directamente en el código de la app (no en la base de datos).

Internamente, cuando la app necesita mostrar "todas las categorías disponibles" en cualquier selector, combina las categorías fijas del sistema con las que el usuario haya creado, de forma que ambas aparecen mezcladas sin distinción visual.

Un detalle de diseño importante que se decidió recientemente: el color de los íconos de categoría **no** varía libremente por categoría (antes cada categoría tenía su propio color asignado, lo cual generaba una paleta muy variada y algo caótica). Ahora el color del ícono de una categoría depende únicamente de si es de tipo ingreso o gasto: un solo tono de verde para todo lo que es ingreso, un solo tono de rojo para todo lo que es gasto. Esto es deliberado: se busca que el usuario entienda de un vistazo si algo entra o sale dinero, sin que un arcoíris de colores por categoría le reste claridad a eso.

## Cómo se registra una transacción nueva

Cuando el usuario quiere agregar un ingreso o un gasto, se abre un panel que sube desde abajo de la pantalla (un "bottom sheet"). Este panel tiene varios pasos que van cambiando dentro del mismo panel (no se abren paneles nuevos encima, cosa que antes sí pasaba y se sentía confuso):

1. Si hace falta, primero se elige a qué registro va la transacción (y si es una transferencia, también a qué registro destino).
2. Luego aparece el formulario principal: el monto se escribe en un campo grande, centrado, que automáticamente le pone los separadores de miles mientras el usuario escribe (por ejemplo, al escribir "45000" se muestra "45.000" en tiempo real, igual que se vería ya guardado en el historial). Debajo hay un interruptor tipo píldora para elegir entre Ingreso o Gasto. Luego, una fila de "chips" horizontales con las categorías más usadas, para elegir rápido sin tener que entrar a un listado completo; si ninguna de esas sirve, hay un chip de "Más" que lleva al paso completo de categorías. Más abajo están la fecha y la hora (cada una se edita de forma independiente, tocando cada una por separado abre su propio selector), el campo de lugar/persona con autocompletado basado en lugares usados antes, y un campo de nota que crece hacia abajo si el usuario escribe más de una línea.
3. Si el usuario necesita elegir una categoría distinta a las rápidas, se pasa a un paso de selección completa: tiene un buscador (porque el catálogo puede ser bastante grande), chips de "recientes", y un acordeón donde se despliega cada categoría padre para ver y elegir sus subcategorías. Desde ahí también se puede crear una categoría nueva, incluyendo elegir a qué categoría padre pertenece y qué ícono tendrá.

Este mismo panel también permite editar una transacción ya existente, y permite prellenar los datos a partir de una plantilla guardada.

## Plantillas

Para transacciones que se repiten seguido (por ejemplo "Pago de arriendo" o "Mercado semanal"), el usuario puede guardar una plantilla: un molde con nombre, categoría, tipo, y opcionalmente un monto fijo, un lugar/persona y una nota predefinidos. Hay una pantalla dedicada para administrar plantillas, separadas por pestañas de Gasto, Ingreso o Todas. Al usar una plantilla, se abre el mismo panel de nueva transacción pero ya con esos campos prellenados, listo para solo confirmar o ajustar el monto si hace falta.

## El historial de un registro

Dentro de cada registro, el usuario puede ver su historial completo de transacciones. Esta pantalla fue rediseñada varias veces durante el desarrollo reciente, buscando un balance entre que se vea informativo pero no sature de colores. El estado actual:

- Arriba hay un resumen: el balance total de ese registro en grande, y a la derecha, en una columna separada por una línea vertical, los montos de ingresos (con una flechita verde hacia arriba) y de gastos (con una flechita roja hacia abajo), cada uno acompañado del porcentaje real que representa sobre el total de movimientos de ese registro. Debajo hay una frase corta tipo "N registros · ingresos superan gastos en un X%", calculada de verdad a partir de los datos, no un texto genérico.
- Debajo, el historial se agrupa visualmente por periodo (puede ser por día, semana, mes, año, o sin agrupar nada en absoluto, según lo que el usuario elija en un menú de filtros). Cada grupo es una especie de tarjeta que contiene su encabezado (la fecha del grupo y cuántos registros tiene, en texto neutro, ya no en un color llamativo) y debajo, una por una, las transacciones de ese grupo, separadas por una línea delgada.
- Cada fila de transacción muestra: un ícono neutro (ni verde ni rojo) representando la categoría, el nombre de la subcategoría como texto principal, debajo en texto más pequeño la categoría padre junto con la nota y el lugar/persona si los hay, y a la derecha el monto (ese sí coloreado verde o rojo según sea ingreso o gasto, con el signo + o −) junto con la hora.
- Deslizando una fila hacia la izquierda se elimina (con confirmación), deslizando hacia la derecha se abre para editarla.
- Hay un buscador y un botón de filtros que abre un menú flotante (no un panel de pantalla completa) donde se elige el tipo de agrupación, el orden (más reciente o más antiguo primero) y si se quiere ver todo, solo ingresos o solo gastos.

## Estadísticas

Hay una pantalla de estadísticas con dos vistas principales: un gráfico de pastel mostrando en qué categorías se ha gastado más dinero en un periodo (con porcentajes), y un gráfico de barras comparando ingresos contra gastos mes a mes, para ver la tendencia a lo largo del tiempo.

## Presupuestos

Existe una funcionalidad de presupuestos (asignarle un tope de gasto mensual a una categoría), pero está en un estado bastante básico todavía, es la parte menos desarrollada del módulo.

## Personalización visual

La app permite al usuario elegir un color de acento personalizado para toda la interfaz (hay un selector de color tipo "cuentagotas"). Ese color se usa de forma consistente en Finanzas en elementos como los botones flotantes de acción (crear transacción, crear plantilla, crear registro) y el botón central de navegación que cambia entre Créditos y Finanzas. El sistema calcula automáticamente si el texto o ícono sobre ese color de acento debe verse blanco o negro, según cuál ofrezca mejor contraste, para que nunca quede un texto invisible encima de un color claro o un texto oscuro invisible sobre un color oscuro.

Aparte de ese acento personalizado, el único lugar donde se usa el código de colores verde/rojo de forma fija es para distinguir ingresos de gastos (en el monto de cada transacción y en las flechitas del resumen) — es una decisión de diseño consciente: se prefirió sacrificar "personalización total" en ese punto específico a cambio de mantener una convención financiera universal y clara (verde entra, rojo sale), después de que en versiones anteriores el exceso de verde/rojo en todos los elementos de la pantalla (barras, íconos, fondos) generara una sensación de saturación visual.

## Estado general / qué tan maduro está cada parte

- **Registros, transacciones, categorías y subcategorías, creación/edición**: bastante maduro y pulido, con varias iteraciones de diseño ya hechas.
- **Historial con filtros y agrupación**: maduro, con varios rediseños recientes enfocados en reducir saturación visual y hacerlo más informativo sin ser invasivo.
- **Plantillas**: funcional, cumple su propósito, menos pulido visualmente que el resto.
- **Estadísticas**: funcional pero más simple, cubre lo básico (pastel por categoría, tendencia mensual).
- **Presupuestos**: la parte menos desarrollada, apenas funcional.
- **Recurrencia de transacciones**: preparada en la base de datos pero sin interfaz real todavía.
- **Sinergia entre Créditos y Finanzas** (por ejemplo, que un pago de tarjeta de crédito se refleje también como un gasto en Finanzas, o que Finanzas muestre alertas de vencimientos de Créditos): es una idea que se discutió pero deliberadamente **no** se ha implementado todavía — se decidió mantener ambos módulos independientes por ahora.
