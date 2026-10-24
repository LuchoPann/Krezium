/// Registro de cambios visible al usuario por versión.
/// Para añadir una release: insertar una nueva VersionEntry AL INICIO de [changelog].
/// La versión de pubspec.yaml es la única fuente de verdad — no duplicar aquí.
///
/// Nota: versiones 0.1.0–0.8.0 son reconstrucciones retrospectivas
/// (el proyecto no tenía versionado formal antes de 0.9.0).
library changelog;

class VersionEntry {
  final String version;
  final String date;
  final List<ChangeItem> changes;

  const VersionEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

class ChangeItem {
  final ChangeType type;
  final String description;

  const ChangeItem(this.type, this.description);
}

enum ChangeType { nuevo, mejora, correccion }

const List<VersionEntry> changelog = [
  VersionEntry(
    version: '2.7.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'La app ya puede revisar si hay una versión nueva (Cuenta → Buscar actualizaciones, o automático al abrir) y descargarla e instalarla desde ahí mismo — tú sigues confirmando la instalación como siempre hace Android.'),
    ],
  ),
  VersionEntry(
    version: '2.6.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.correccion,
          'Presupuestos: un gasto nuevo ya se refleja de inmediato en el consumo de su categoría — antes la pantalla quedaba con datos viejos hasta reiniciar la app.'),
      ChangeItem(ChangeType.nuevo,
          'Metas: aportar o retirar ahora mueve la plata de verdad (como una transferencia a tu ahorro) y queda visible en el historial del registro — antes el dinero "salía de la nada" sin dejar rastro. Las metas virtuales eligen de/hacia qué registro mover la plata en cada aporte.'),
      ChangeItem(ChangeType.mejora,
          'El balance de un registro vuelve a mostrar primero el total real (con transferencias incluidas) — mostrarlo sin transferencias hacía que un registro que solo había recibido dinero se viera en \$0.'),
      ChangeItem(ChangeType.correccion,
          'El índice clicable de la guía "Cómo funciona Krezium" ya salta a cualquier sección, no solo a la primera.'),
    ],
  ),
  VersionEntry(
    version: '2.5.5',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'Logos de bancos (Itaú, Occidente, Popular, AV Villas, Tuya) reescalados a su tamaño real de uso — 90% menos peso en la app, sin pérdida de nitidez.'),
    ],
  ),
  VersionEntry(
    version: '2.5.4',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'El formulario de "Nuevo crédito" ya no recalcula el cronograma completo de amortización en cada tecla que escribes en el paso de confirmación — solo cuando algo relevante realmente cambió.'),
    ],
  ),
  VersionEntry(
    version: '2.5.3',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'Reduce el tamaño de la app quitando un peso de fuente que no se usaba en ningún lado.'),
    ],
  ),
  VersionEntry(
    version: '2.5.2',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'Más mejoras de rendimiento: listas y buscadores más ágiles, menos trabajo repetido al cargar créditos, fotos de perfil más livianas y los respaldos (exportar/importar) ya no congelan la pantalla mientras procesan.'),
    ],
  ),
  VersionEntry(
    version: '2.5.1',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'Mejoras de rendimiento en la base de datos: índices nuevos en las tablas más consultadas y consultas optimizadas para que la app responda más rápido, especialmente con muchos registros, créditos o movimientos.'),
    ],
  ),
  VersionEntry(
    version: '2.5.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Guía "Cómo funciona Krezium" renovada: índice clicable y una sección completa dedicada a Finanzas (registros, transacciones, categorías, presupuestos, metas y estadísticas), separada de Créditos.'),
      ChangeItem(ChangeType.mejora,
          'Los presupuestos ya no muestran el aviso de "¿mantener los del mes pasado?" — ahora solo se repiten los que marcaste como automáticos; el resto simplemente no vuelve a aparecer si no lo creas de nuevo.'),
      ChangeItem(ChangeType.mejora,
          'Tarjetas de registros rediseñadas: balance e ingresos/gastos en paneles separados, menos espacio desperdiciado y mejor jerarquía visual.'),
    ],
  ),
  VersionEntry(
    version: '2.4.1',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'El balance vuelve a mostrar primero el total sin transferencias, con el total "con transferencias" como dato secundario.'),
      ChangeItem(ChangeType.mejora,
          'Vuelve el aviso debajo del balance con un vistazo rápido de cómo van tus ingresos y gastos.'),
    ],
  ),
  VersionEntry(
    version: '2.4.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Presupuestos: ahora puedes marcar uno para que se repita automáticamente cada mes, sin que vuelva a aparecer el aviso de "¿mantener presupuestos del mes anterior?".'),
      ChangeItem(ChangeType.mejora,
          'El resumen del libro de movimientos ahora muestra el balance con y sin transferencias, para que quede claro de dónde sale cada cambio.'),
      ChangeItem(ChangeType.mejora,
          'El cuadro de balance ocupa menos espacio en altura, dejando más aire para el histórico de movimientos.'),
    ],
  ),
  VersionEntry(
    version: '2.3.3',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'El resumen del libro de movimientos ahora muestra una línea de "Transferencias" cuando aplica, para explicar la diferencia entre el balance y tus ingresos/gastos.'),
      ChangeItem(ChangeType.mejora,
          'Los íconos de cada movimiento ya tienen color según el tipo: rojo (gasto), verde (ingreso), azul (transferencia) — antes solo el monto llevaba color.'),
    ],
  ),
  VersionEntry(
    version: '2.3.2',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.correccion,
          'Las transferencias entre tus propios registros ya no se ven como un gasto (rojo, con signo "-") en el libro de movimientos — ahora son neutras, con su propio ícono y etiqueta ("Transferencia enviada/recibida"), porque mover dinero entre registros no es ni ingreso ni gasto.'),
    ],
  ),
  VersionEntry(
    version: '2.3.1',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Ya puedes eliminar las categorías y subcategorías que creaste tú mismo (las predeterminadas de la app se mantienen).'),
      ChangeItem(ChangeType.mejora,
          'En el libro de movimientos, la fecha/hora de cada fila ahora se ajusta a cómo estés agrupando: solo hora por día, día y hora por semana/mes, día+mes y hora por año o sin agrupar.'),
      ChangeItem(ChangeType.mejora,
          'Los menús desplegables (como Nueva Transacción) ya no requieren arrastrar hacia arriba para ver el botón de guardar — se ajustan solos a su contenido.'),
    ],
  ),
  VersionEntry(
    version: '2.3.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Nueva Transacción tiene un diseño nuevo: selector de tipo rediseñado, campos agrupados por secciones y una vista previa antes de guardar.'),
      ChangeItem(ChangeType.nuevo,
          'Al registrar un gasto puedes marcar "Cargar a otro presupuesto" — útil cuando pagas algo de una categoría con la plata que tenías apartada para otra (ej. una gaseosa pagada con el dinero de Transporte).'),
      ChangeItem(ChangeType.mejora,
          'Crear o editar un presupuesto ahora es una sola pantalla con categorías en grilla, en vez de un asistente de varios pasos.'),
      ChangeItem(ChangeType.mejora,
          'Al entrar a un mes sin presupuestos, Krezium pregunta si quieres mantener los del mes anterior y te deja elegir cuáles, con el monto editable.'),
    ],
  ),
  VersionEntry(
    version: '2.2.1',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.mejora,
          'Al cambiar entre Créditos y Finanzas ahora siempre vuelves a la vista inicial de ese módulo.'),
      ChangeItem(ChangeType.mejora,
          'El cambio entre módulos se ve con una transición suave en vez de un salto brusco.'),
    ],
  ),
  VersionEntry(
    version: '2.2.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Planificación: los presupuestos ahora te sugieren un límite basado en lo que gastaste los últimos meses en esa categoría.'),
      ChangeItem(ChangeType.nuevo,
          'Metas de ahorro: puedes crearlas vinculadas a un registro o como reserva virtual, con historial de cada aporte y retiro.'),
      ChangeItem(ChangeType.nuevo,
          'Al registrar un gasto, ves de una vez el presupuesto de esa categoría y puedes crear uno si no existe, sin salir del formulario.'),
      ChangeItem(ChangeType.nuevo,
          'Estadísticas muestra ahora tu tasa de ahorro del mes y la variación de cada categoría frente al mes anterior.'),
      ChangeItem(ChangeType.nuevo,
          'Inicio detecta cuando dos pagos de tarjetas o préstamos caen cerca en el calendario y te deja marcarlos pagados juntos o por separado.'),
      ChangeItem(ChangeType.mejora,
          'Inicio muestra el extracto que se avecina de cada tarjeta (no la deuda total) y el contador de días siempre apunta a la fecha límite real.'),
      ChangeItem(ChangeType.mejora,
          '"Confirmar pago" de una tarjeta ahora es una pantalla de solo revisar y confirmar, sin campos que llenar, y solo se habilita cuando el extracto ya está en su fecha límite.'),
      ChangeItem(ChangeType.mejora,
          'Al registrar una compra con tarjeta, el nombre es obligatorio y las cuotas se escriben libremente, como las hayas negociado.'),
      ChangeItem(ChangeType.mejora,
          'El Disponible y el Límite de un cupo de tienda ahora se ven igual en Resumen que en Cronograma.'),
      ChangeItem(ChangeType.correccion,
          'La lista de "Tus créditos" en Inicio ahora ordena correctamente por los días reales que faltan para cada pago.'),
      ChangeItem(ChangeType.correccion,
          'Se eliminó el selector "Pagar extracto / Abono a la deuda", que no cambiaba nada real entre sus dos opciones.'),
      ChangeItem(ChangeType.correccion,
          'Se quitó el recordatorio de notificación personalizado por crédito.'),
    ],
  ),
  VersionEntry(
    version: '2.0.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Módulo Finanzas: registra gastos e ingresos con categorías, cuentas y presupuesto mensual.'),
      ChangeItem(ChangeType.nuevo,
          'Navegación dual: alterna entre el entorno de Créditos y Finanzas con el botón central del nav.'),
      ChangeItem(ChangeType.nuevo,
          'Catálogo de 30 categorías predefinidas para clasificar gastos e ingresos, con soporte para categorías personalizadas.'),
      ChangeItem(ChangeType.nuevo,
          'Estadísticas de Finanzas: gráfica de gastos por categoría y saldo actual de cada cuenta o bolsillo.'),
      ChangeItem(ChangeType.nuevo,
          'Al instalar Krezium por primera vez, puedes elegir qué vista quieres ver al abrirla.'),
      ChangeItem(ChangeType.mejora,
          'Los respaldos incluyen ahora los datos de Finanzas. Los respaldos anteriores se siguen importando sin cambios.'),
    ],
  ),
  VersionEntry(
    version: '1.1.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'La app es ahora Krezium — nueva identidad visual con animación de apertura renovada y logotipo actualizado en toda la interfaz.'),
      ChangeItem(ChangeType.mejora,
          'El modo claro ahora muestra los textos en tonos oscuros bien definidos, igual que el modo oscuro muestra blancos nítidos. La jerarquía visual es clara en ambos temas.'),
      ChangeItem(ChangeType.mejora,
          'El patrón decorativo del perfil (KREZIUM_OUTLINE) ahora se adapta al tema: oscuro en modo claro, blanco en modo oscuro.'),
      ChangeItem(ChangeType.mejora,
          'La animación del splash tiene dirección de aparición personalizada para cada segmento del logotipo KREZIUM.'),
      ChangeItem(ChangeType.mejora,
          'La sección "Cómo funciona" está actualizada con información precisa sobre los tonos de tema, los estilos de voucher y el acento adaptativo.'),
    ],
  ),
  VersionEntry(
    version: '1.0.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'El simulador ahora funciona con cupos de tienda y app (Addi, Sistecrédito, etc.), no solo con tarjetas de crédito.'),
      ChangeItem(ChangeType.nuevo,
          'Simulación en tiempo real: los resultados se actualizan automáticamente mientras escribes, sin necesidad de presionar un botón.'),
      ChangeItem(ChangeType.nuevo,
          'Al crear un crédito de tarjeta con saldo inicial, ahora puedes indicar la fecha en que comenzó esa deuda.'),
      ChangeItem(ChangeType.mejora,
          'El simulador ya no parpadea al cambiar valores — los datos se actualizan en su lugar sin rehacer la interfaz.'),
      ChangeItem(ChangeType.mejora,
          'Se eliminó la tabla "Comparar escenarios" del simulador de abono extra, que generaba más confusión que claridad.'),
      ChangeItem(ChangeType.correccion,
          'Las copias de respaldo automáticas ya no se disparan en cada reinicio de la app durante desarrollo.'),
      ChangeItem(ChangeType.correccion,
          'Se resolvió el conflicto de recursos duplicados del ícono de notificación que impedía compilar en Android.'),
    ],
  ),
  VersionEntry(
    version: '0.9.2',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Puedes deshacer un abono registrado por accidente: aparece un botón "DESHACER" durante 5 segundos en el mensaje de confirmación.'),
      ChangeItem(ChangeType.nuevo,
          'Los créditos de préstamo ahora permiten editar la fecha de inicio directamente desde la pantalla de edición.'),
      ChangeItem(ChangeType.mejora,
          'La sección de abonos se expande automáticamente al registrar uno nuevo, y el último abono recibe la etiqueta "Reciente".'),
      ChangeItem(ChangeType.correccion,
          'Corregido: el gráfico "Cuándo termina cada crédito" ahora muestra el progreso real de cuotas pagadas, no un estimado incorrecto.'),
      ChangeItem(ChangeType.mejora,
          'Los textos informativos y de advertencia en toda la app ahora tienen un estilo visual consistente (cursiva, tamaño uniforme, borde).'),
    ],
  ),
  VersionEntry(
    version: '0.9.1',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Simulador: nuevo tab "Libertad" que proyecta tu fecha libre de deuda y cuánto ahorras en intereses si pagas un monto extra al mes.'),
      ChangeItem(ChangeType.nuevo,
          'Estrategias Avalanche y Snowball en el simulador: elige la que mejor se adapte a tu perfil.'),
      ChangeItem(ChangeType.mejora,
          'El simulador muestra tu deuda total, interés mensual estimado y fecha libre de deuda desde que lo abres, sin necesidad de simular nada.'),
      ChangeItem(ChangeType.correccion,
          'Corregido crash al abrir las sub-vistas de "Respaldo automático" y "Seguridad" dentro del panel deslizable de configuración.'),
      ChangeItem(ChangeType.mejora,
          'Las sub-vistas de configuración ahora deslizan internamente dentro del panel, sin abrir una pantalla completa.'),
    ],
  ),
  VersionEntry(
    version: '0.9.0',
    date: 'Octubre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Respaldo automático: los archivos ahora se guardan en Krezium/backups/ del almacenamiento principal del teléfono.'),
      ChangeItem(ChangeType.nuevo,
          'Configuración de hora para el respaldo automático.'),
      ChangeItem(ChangeType.nuevo,
          'Ícono personalizado de Krezium en la barra de notificaciones.'),
      ChangeItem(ChangeType.mejora,
          'Nueva pantalla de cuenta: diseño limpio con foto de perfil editable y acceso rápido a cada sección.'),
      ChangeItem(ChangeType.mejora,
          'Los diálogos de confirmación ahora se muestran como paneles deslizables desde abajo.'),
      ChangeItem(ChangeType.mejora,
          'La edición de tarjetas y cupos de tienda tiene formularios separados adaptados a cada tipo.'),
      ChangeItem(ChangeType.mejora,
          'Mejoras visuales en el modo claro: colores más diferenciados entre variantes.'),
      ChangeItem(ChangeType.correccion,
          'Corregido error que impedía mostrar valores de días de pago fuera del rango del selector.'),
      ChangeItem(ChangeType.correccion,
          'Las notificaciones ahora se envían correctamente con todos sus parámetros.'),
    ],
  ),
  VersionEntry(
    version: '0.8.0',
    date: 'Septiembre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Rework completo del formulario de edición de créditos: secciones organizadas, advertencias claras y campo de saldo de solo lectura.'),
      ChangeItem(ChangeType.nuevo,
          'La hoja de movimientos de tarjeta fue rediseñada con mejor organización visual.'),
      ChangeItem(ChangeType.mejora,
          'El modo claro tiene ahora tres variantes visualmente más distintas: Puro, Nube y Arena.'),
      ChangeItem(ChangeType.correccion,
          'Corregida la lógica del ciclo de facturación: el corte ocurre al inicio del día indicado, no el día siguiente.'),
    ],
  ),
  VersionEntry(
    version: '0.7.0',
    date: 'Septiembre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Rediseño de la vista de detalle de tarjeta: fechas de ciclo en el encabezado, línea de tiempo visual del ciclo y marcador del día actual.'),
      ChangeItem(ChangeType.nuevo,
          'Flujo de tienda mejorado: hero de monto, primeros pagos y selector de voucher deslizable.'),
      ChangeItem(ChangeType.mejora,
          'La vista de resumen muestra ahora la gráfica completa del ciclo y el cupo debajo de la tarjeta.'),
      ChangeItem(ChangeType.correccion,
          'El picker de voucher ahora muestra la selección activa en tiempo real.'),
      ChangeItem(ChangeType.correccion,
          'Los vouchers en la vista de confirmación muestran el diseño correcto según el tipo de crédito.'),
    ],
  ),
  VersionEntry(
    version: '0.6.0',
    date: 'Septiembre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'El registro de créditos ahora tiene flujos separados para tienda, tarjeta y préstamo, con una pantalla de selección inicial.'),
      ChangeItem(ChangeType.nuevo,
          'Nuevo campo "Día de pago" y política de interés a una cuota en tarjetas de crédito.'),
      ChangeItem(ChangeType.mejora,
          'Hints educativos en el flujo de registro para guiar al usuario en cada campo.'),
    ],
  ),
  VersionEntry(
    version: '0.5.0',
    date: 'Septiembre 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Pantalla de carga animada con reveal direccional y efecto de brillo.'),
      ChangeItem(ChangeType.nuevo,
          'Arquitectura entidad-primero: el banco o tienda emisora ahora es el punto de partida al registrar un crédito.'),
      ChangeItem(ChangeType.nuevo,
          'Picker visual de entidades con búsqueda y presets de bancos y apps populares.'),
      ChangeItem(ChangeType.mejora,
          'La app ahora carga más rápido: SharedPreferences inyectado y tabs cargados de forma diferida.'),
    ],
  ),
  VersionEntry(
    version: '0.4.0',
    date: 'Agosto 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Dashboard rediseñado con logo, tiles de próximos pagos y resumen de créditos.'),
      ChangeItem(ChangeType.nuevo,
          'Sistema tipográfico unificado (AppTextSize) y escala de iconos consistente en toda la app.'),
      ChangeItem(ChangeType.nuevo,
          'Tarjeta de sección compartida (AppSectionCard) en todas las pantallas.'),
      ChangeItem(ChangeType.mejora,
          'Buscador de créditos, estados vacíos y vista de detalle mejorados.'),
    ],
  ),
  VersionEntry(
    version: '0.3.0',
    date: 'Agosto 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Voucher de comprobante estilo Nequi para registrar movimientos de cupos de tienda.'),
      ChangeItem(ChangeType.nuevo,
          'Abonos extra con reamortización real: las cuotas adelantadas se marcan correctamente.'),
      ChangeItem(ChangeType.nuevo,
          'Estimación de mora en el cronograma de pagos.'),
      ChangeItem(ChangeType.mejora,
          'El interés ya no se descuenta del cupo disponible, solo el capital.'),
    ],
  ),
  VersionEntry(
    version: '0.2.0',
    date: 'Agosto 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Simulador financiero: calcula el impacto de una compra adicional o un abono extra.'),
      ChangeItem(ChangeType.nuevo,
          'Bloqueo de app con PIN y biometría (huella/face ID).'),
      ChangeItem(ChangeType.nuevo,
          'Re-autenticación requerida antes de borrar todos los datos.'),
      ChangeItem(ChangeType.correccion,
          'El teclado numérico nativo aparece correctamente en la pantalla de bloqueo.'),
    ],
  ),
  VersionEntry(
    version: '0.1.0',
    date: 'Agosto 2026',
    changes: [
      ChangeItem(ChangeType.nuevo,
          'Primera versión de Krezium: gestión de tarjetas de crédito, cupos de tienda y préstamos.'),
      ChangeItem(ChangeType.nuevo,
          'Registro de movimientos, cronograma de cuotas y resumen financiero.'),
      ChangeItem(ChangeType.nuevo,
          'Temas claro y oscuro con color de acento personalizable.'),
      ChangeItem(ChangeType.nuevo,
          'Exportación e importación de datos en formato JSON.'),
      ChangeItem(ChangeType.nuevo,
          'Recordatorios de vencimiento con notificaciones locales.'),
    ],
  ),
];
