# Krezium Finanzas — Propuesta de catálogo maestro de categorías

**Estado: propuesta para revisión. No se modifica código, base de datos ni interfaz hasta autorización explícita** (tal como pide el prompt original).

Esta propuesta parte del texto que GPT preparó y lo contrasta contra el código real de `lib/data/finance_categories_catalog.dart` y `lib/data/finance_icon_map.dart`, para no proponer nada que ya esté resuelto ni duplicar trabajo.

## 0. Lo que ya está resuelto en el código actual (no hace falta rediseñar)

- **Identificadores estables**: cada categoría ya tiene un `id` tipo slug (`'salario'`, `'transporte_publico'`, `'cat_vivienda_padre'`) separado de `nombre` — el requisito de GPT de "no usar el nombre visible como identificador" **ya se cumple**.
- **Jerarquía de dos niveles** (padre/hijo vía `parentId`) — ya existe.
- **Tipo de movimiento permitido** (`tipo: 'ingreso'|'gasto'|'ambos'`) por categoría — ya existe.
- **Íconos por clave estable, no por objeto gráfico**: `iconoKey` (string) resuelto a `IconData` vía `iconFromKey()` en `finance_icon_map.dart` — esto es exactamente la arquitectura que pide GPT en la sección 7 ("clave estable, no guardar un objeto gráfico"). Cambiar de librería de íconos el día de mañana implica tocar un solo archivo (`finance_icon_map.dart`), no el catálogo ni la base de datos.
- **Categorías personalizadas**: el usuario ya puede crear categorías propias con nombre, ícono (de una librería de ~140 íconos ya armada), tipo y padre opcional — ya existe (`categoria_selector_sheet.dart`).
- **Catálogo fijo vs. personalizado conviven sin distinción visual** en los selectores — ya existe (`allFinanceCategoriesProvider` combina ambos).

## 1. Estructura del catálogo (sin cambios de forma, solo de contenido)

Se mantiene: `CatalogoCategoria { id, nombre, icono, color, tipo, iconoKey, parentId? }`. No se necesita agregar un campo de "descripción" separado — el nombre ya es lo suficientemente descriptivo en el patrón que ya usa el proyecto (y la regla de esta sesión es "genérico pero indicativo", no hiperespecífico — ver sección 3).

## 2. Catálogo de GASTOS propuesto (consolidado)

GPT propuso ~20 categorías padre de gasto con listas muy largas de subcategorías (algunas de solo 1-2 palabras de diferencia entre sí, ej. "Reparaciones" aparece repetida en Vivienda, Transporte y Tecnología como subcategorías distintas sin problema — eso está bien, son contextos distintos). Mi propuesta es **aceptar la ampliación de 8 a 16 categorías padre de gasto**, pero **consolidar las subcategorías** aplicando la regla ya establecida en esta sesión ("genérico pero indicativo, no hiperespecífico") — es decir, no crear una subcategoría por cada matiz (ej. no separar "Energía eléctrica" / "Agua y alcantarillado" / "Gas" / "Internet del hogar" / "Telefonía fija" como 5 subcategorías — se consolidan en una sola "Servicios públicos", que YA es como está hoy en el código y funciona bien).

### Padres de gasto (16, antes 7 — Ingresos pasa a tratarse aparte en la sección 3)

| Padre (id sugerido) | Ícono (`iconoKey`, Material ya en el mapa) | Subcategorías consolidadas (ejemplo, no exhaustivo) |
|---|---|---|
| `cat_vivienda_padre` (ya existe) | `home` | Arriendo/Hipoteca (ya existe), Servicios públicos (ya existe), Administración, Mantenimiento del hogar (ya existe), Muebles y hogar (ya existe), Mudanza |
| `cat_alimentacion_padre` (ya existe) | `restaurant` | Mercado/Supermercado (ya existe), Restaurantes (ya existe), Domicilios (ya existe), Bebidas (ya existe) — **no** separar "desayunos/almuerzos/cenas/panadería/frutas" como pide el texto original, eso es sobre-fragmentación |
| `cat_transporte_padre` (ya existe) | `directions_car` | Bus/Transporte público (ya existe), Carro (ya existe — incluye gasolina/mantenimiento/parqueadero/peajes/SOAT bajo un mismo concepto "Carro", no categorías separadas), Moto (ya existe), Taxi/App (ya existe), Bicicleta (ya existe), Avión (ya existe), Transporte intermunicipal |
| `cat_salud_padre` (ya existe) | `local_hospital` | Consulta médica (ya existe), Medicamentos (ya existe), Odontología (ya existe), Seguro de salud (ya existe), Salud mental, Cuidado personal/higiene |
| `cat_educacion_padre` (ya existe) | `school` | Matrícula/Pensión (ya existe), Cursos online (ya existe), Libros y material (ya existe), Derechos de grado |
| `cat_tecnologia_padre` **(nuevo)** | `devices` | Dispositivos (celular/computador/tablet), Reparaciones tecnológicas, Software y suscripciones digitales, Videojuegos |
| `cat_suscripciones_padre` **(nuevo)** | `credit_card` | Streaming, Música, Telefonía/Internet, Otras suscripciones — GPT separaba "Comunicaciones y suscripciones" de tecnología; se mantiene aparte porque es recurrente/mensual, distinto a una compra puntual de tecnología |
| `cat_ropa_padre` **(nuevo)** | `checkroom` | Ropa y calzado (ya existía como "Ropa" bajo Otros), Accesorios, Lavandería/arreglos |
| `cat_belleza_padre` **(nuevo)** | `spa` | Peluquería/Barbería, Cosméticos y cuidado personal, Tratamientos estéticos |
| `cat_ocio_padre` (ya existe) | `movie` | Entretenimiento (ya existe), Salidas/eventos, Hobbies, Deporte (ya existe) |
| `cat_viajes_padre` **(nuevo)** | `flight` | Alojamiento, Transporte de viaje, Actividades turísticas, Seguro de viaje — separado de "Transporte" cotidiano porque es un gasto de naturaleza distinta (ocasional, agrupado) |
| `cat_familia_padre` **(nuevo)** | `family_restroom` | Hijos (colegio, ropa, juguetes), Mascotas (ya existía como "Mascotas" bajo Otros), Cuidado de adultos mayores |
| `cat_finanzas_padre` **(nuevo)** | `account_balance` | Cuotas de préstamos, Comisiones bancarias, Impuestos, Seguros (vida/hogar/vehículo agrupados) |
| `cat_compras_padre` **(nuevo)** | `shopping_bag` | Compras generales, Regalos (ya existía como "Regalos" bajo Otros), Envíos |
| `cat_trabajo_padre` **(nuevo)** | `business_center` | Herramientas/equipos de trabajo, Software profesional, Publicidad y marketing, Formación profesional — relevante para quien tiene negocio/freelance, ya cubierto parcialmente por Ingresos pero el GASTO asociado a un emprendimiento necesita su propio padre |
| `cat_imprevistos_padre` **(nuevo)** | `warning_amber` (verificar en mapa, si no existe usar `priority_high`) | Emergencias, Reparaciones urgentes, Imprevistos sin clasificar |
| `cat_otros_padre` (ya existe, se reduce) | `more_horiz` | Otro gasto sin clasificar — ya no necesita cargar Ropa/Mascotas/Tecnología/Belleza/Regalos que ahora tienen padre propio |

**Donaciones y compromisos sociales**: GPT lo propone como padre aparte. Recomiendo consolidarlo dentro de `cat_compras_padre` como subcategoría "Regalos y donaciones" en vez de un padre con una sola subcategoría relevante para la mayoría de usuarios — evita inflar el selector de padres con una categoría de uso poco frecuente.

## 3. Catálogo de INGRESOS propuesto (consolidado, no 10 padres)

GPT propone **10 categorías padre solo para ingresos** (Empleo, Independiente, Negocios, Inversiones, Arriendos, Reembolsos, Apoyos, Ventas de bienes, Extraordinarios, Otros). Para una app de finanzas personales esto es excesivo — la mayoría de usuarios tiene 1-3 fuentes de ingreso reales. Recomiendo **mantener un único padre "Ingresos"** (como ya existe hoy) y ampliar sus subcategorías:

`cat_ingresos_padre` (ya existe, ícono `attach_money`):
- Salario (ya existe)
- Freelance/Independiente (ya existe)
- Negocio/Ventas (ya existe)
- Arriendo recibido (ya existe)
- Intereses/Rendimientos (ya existe, cubre inversiones/CDT/dividendos consolidado)
- Reembolso (ya existe)
- Regalo/Apoyo recibido (ya existe, cubre ayuda familiar/subsidios/donaciones recibidas consolidado)
- Venta de bienes personales **(nueva subcategoría)**
- Ingreso extraordinario **(nueva subcategoría)** — premios, indemnizaciones, herencias
- Otro ingreso (ya existe)

Esto cubre el 100% de los casos de GPT sin fragmentar en 10 padres que la mayoría de usuarios nunca usaría. Si en el futuro se detecta que los usuarios SÍ necesitan separar "ingresos de negocio" de "salario" como padres propios (por ejemplo para un dashboard de "ingresos por fuente"), se puede dividir después — es más fácil separar un padre más adelante que consolidar diez padres ya en uso.

## 4. Reglas de clasificación contable (ya resueltas, documentadas en `docs/finanzas-reglas-contables.md`)

Las distinciones que pide GPT (ingreso/gasto/transferencia/reembolso/préstamo) ya están resueltas a nivel de **tipo de movimiento** (`FinanceTransactions.tipo`), no de categoría — es la arquitectura correcta y ya implementada en Fase 01:
- Transferencia: ya no se contabiliza como ingreso ni gasto (`signedEffectForLibro` en `finance_ledger.dart`).
- Reembolso: hoy se registraría como una categoría de ingreso ("Reembolso") — GPT sugiere que podría restar del gasto en vez de sumar al ingreso. **Esto es una decisión de producto nueva, no la tomo aquí** — dejarla para cuando se diseñe explícitamente (afecta cálculos de Estadísticas/Presupuestos, Fase 06/04). Por ahora, "Reembolso" sigue siendo una subcategoría de ingreso, consistente con el modelo actual.
- Préstamo recibido / pago de capital: Krezium no tiene hoy el concepto de "préstamo personal" en Finanzas (eso vive en el módulo Créditos, con otro modelo de datos). Fuera de alcance de esta propuesta.

## 5. Categorías personalizadas

Ya cumplen lo que pide GPT. Único hallazgo real de esta sesión (ya corregido en Fase 01, no es parte de esta propuesta): el selector de "categoría padre" al crear una subcategoría ahora busca en el catálogo combinado (fijo + personalizado), no solo en el fijo — bug ya corregido.

**Pendiente real no resuelto**: GPT pide que "editar o eliminar una categoría no rompa transacciones históricas". Hoy el modelo tiene un campo `archivada` en `FinanceCategories` pero no hay UI para archivar/eliminar una categoría personalizada desde la app. Si se quiere esa función, es un ítem nuevo de alcance (candidato a Fase 08, pulido) — no se implementa en esta propuesta.

## 6. Búsqueda y selección

Ya existe: buscador por nombre, exploración por padre (acordeón), creación de categoría personalizada embebida en el mismo flujo. **No existe hoy**: búsqueda por sinónimos ("bus" → Transporte, "celular" → Tecnología), categorías recientes/favoritas en el selector de categoría (si existen en otros selectores del proyecto, no en este).

Propuesta mínima para sinónimos (si se aprueba implementar): un mapa estático `Map<String, List<String>> categoriaSinonimos` keyed por `id` de categoría, consultado además del nombre al filtrar en el buscador — cambio acotado, no requiere tocar la base de datos. Ejemplos:
- `'transporte_publico'`: `['bus', 'transmilenio', 'transmetro', 'metro']`
- `'tecnologia_dispositivos'`: `['celular', 'telefono', 'computador', 'pc']`
- `'mercado'`/`'supermercado'`: `['mercado', 'super', 'tienda']`

No lo implemento ahora — es un cambio de código y se espera autorización explícita primero, tal como pide el prompt.

## 7. Íconos — recomendación de librería

**Recomendación: seguir con Material Icons/Material Symbols, NO agregar Font Awesome como dependencia nueva.**

Motivos concretos (no es gusto, es riesgo técnico ya demostrado en este proyecto):
- Esta sesión ya intentó migrar a `phosphor_flutter` y falló: su `PhosphorIconData extends IconData` no compila en Flutter 3.44+ porque `IconData` pasó a ser `final class`. Cualquier librería de íconos de terceros que siga ese mismo patrón (extender `IconData` en vez de instanciarla directamente) tiene el mismo riesgo.
- `font_awesome_flutter` (el paquete real para usar Font Awesome en Flutter) sí evita ese problema — sus íconos son instancias directas de `IconData`, igual que Material Icons — así que **es técnicamente viable**, no tiene el bug de Phosphor. Pero:
  - Agrega una dependencia externa nueva (más superficie de mantenimiento, más riesgo de incompatibilidad futura con versiones de Flutter).
  - El catálogo de Material Icons ya tiene miles de íconos disponibles sin ninguna dependencia nueva, y esta sesión ya amplió el mapa de Krezium a ~140 cuidadosamente verificados contra el SDK real de Flutter.
  - La arquitectura de `iconFromKey()` ya es agnóstica a la librería — si en el futuro de verdad hace falta un ícono que Material no tiene, cambiarlo es un cambio de una línea en el mapa, no una migración.
- Material Symbols (la evolución de Material Icons de Google) está parcialmente ya disponible vía los mismos `Icons.*` de Flutter (muchos símbolos nuevos ya están en el SDK) — no hace falta una librería aparte para la mayoría de casos.

**Conclusión: no cambiar de librería ahora.** Si al armar el catálogo expandido de categorías (sección 2) aparece algún concepto sin buen ícono en Material, se amplía el mapa `finance_icon_map.dart` con el ícono Material más cercano — el mismo proceso ya usado esta sesión, verificado contra el SDK real antes de usar cada clave.

## 8. Observaciones sobre duplicados/ambigüedad (lo que GPT pidió evaluar)

- "Reparaciones" aparece en Vivienda, Transporte y Tecnología en el texto de GPT — **no es un duplicado problemático**, son contextos distintos (reparar la casa, el carro, el celular); si se consolidara en una sola categoría "Reparaciones" perdería la información de en qué se gastó.
- "Comida rápida" / "Restaurantes" / "Domicilios" — GPT las separa, yo las mantengo consolidadas como ya están hoy (una sola subcategoría "Restaurantes" cubre comer afuera, y "Domicilios" cubre que llegue a la casa) — exactamente la regla de "genérico pero indicativo" ya establecida.
- 10 padres de ingresos — ver sección 3, consolidado a 1 padre con más subcategorías.
- "Donaciones y compromisos sociales" como padre aparte — consolidado dentro de Compras (sección 2).
- "Seguros y protección" como padre aparte en el texto de GPT, duplicando seguros que también aparecen en Salud (seguro médico) y Transporte (SOAT/seguro vehicular) — mi propuesta: el seguro médico se queda en Salud, el seguro vehicular se queda en Transporte (son gastos atados al mismo concepto que ya los origina), y solo "Finanzas y obligaciones" absorbe seguros genéricos (vida, hogar) que no calzan en otro padre.

## 9. Resumen de lo que cambiaría si se aprueba esta propuesta

- De 7 padres de gasto + 1 de ingreso (8 total) a **16 padres de gasto + 1 de ingreso (17 total)**.
- De ~35 subcategorías a aproximadamente **90-110 subcategorías** (consolidadas, no las ~280 que listaría una traducción literal del texto de GPT).
- Cero cambios de arquitectura (`CatalogoCategoria`, `iconFromKey`, `allFinanceCategoriesProvider` siguen iguales).
- Cero dependencias nuevas (se sigue con Material Icons).
- Posible ampliación futura (no ahora): sinónimos de búsqueda.

**Esperando tu autorización para implementar esto en código** (editar `lib/data/finance_categories_catalog.dart` y ampliar `lib/data/finance_icon_map.dart` donde haga falta un ícono nuevo) — ¿apruebas la consolidación propuesta, o prefieres ajustar algún padre/subcategoría antes de que lo lleve a código?
