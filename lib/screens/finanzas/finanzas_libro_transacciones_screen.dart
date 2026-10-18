import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/finanzas_filtros.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_ledger.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/screens/finanzas/finanzas_plantillas_screen.dart';
import 'package:krezium/screens/finanzas/nueva_transaccion_sheet.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/widgets/krezium_section_card.dart';

// ─── Public screen ────────────────────────────────────────────────────────────
class FinanzasLibroTransaccionesScreen extends ConsumerStatefulWidget {
  final FinanceAccount libro;
  const FinanzasLibroTransaccionesScreen({
    super.key,
    required this.libro,
  });

  @override
  ConsumerState<FinanzasLibroTransaccionesScreen> createState() =>
      _FinanzasLibroTransaccionesScreenState();
}

const _kMeses = [
  '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _kMesesCorto = [
  '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];
const _kDiasCorto = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

DateTime _parseFecha(String fecha) {
  final parts = fecha.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

class _FinanzasLibroTransaccionesScreenState
    extends ConsumerState<FinanzasLibroTransaccionesScreen> {
  late FinanceAccount _libroActual;

  @override
  void initState() {
    super.initState();
    _libroActual = widget.libro;
  }

  // ─── Agrupar — listado único, agrupación puramente visual ───────────────────
  // Ya no filtra por mes: siempre se agrupa el histórico completo recibido.
  // La clave de grupo cambia según filtros.periodo (diario/semanal/mensual),
  // pero los datos mostrados son siempre los mismos.

  String _claveGrupo(FinanceTransaction tx, String periodo) {
    final d = _parseFecha(tx.fecha);
    switch (periodo) {
      case 'sin_agrupar':
        return '_todo';
      case 'anual':
        return '${d.year}';
      case 'semanal':
        final inicioSemana = d.subtract(Duration(days: d.weekday - 1));
        return '${inicioSemana.year}-${inicioSemana.month.toString().padLeft(2, '0')}-${inicioSemana.day.toString().padLeft(2, '0')}';
      case 'mensual':
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      case 'diario':
      default:
        return tx.fecha;
    }
  }

  Map<String, List<FinanceTransaction>> _agrupar(
      List<FinanceTransaction> txs, String periodo, bool ascending) {
    final mapa = <String, List<FinanceTransaction>>{};
    for (final tx in txs) {
      mapa.putIfAbsent(_claveGrupo(tx, periodo), () => []).add(tx);
    }
    final keys = mapa.keys.toList()
      ..sort((a, b) => ascending ? a.compareTo(b) : b.compareTo(a));
    return {for (final k in keys) k: mapa[k]!};
  }

  String _grupoLabel(String clave, String periodo) {
    switch (periodo) {
      case 'sin_agrupar':
        return 'Todas las transacciones';
      case 'anual':
        return clave;
      case 'semanal':
        final inicio = _parseFecha(clave);
        final fin = inicio.add(const Duration(days: 6));
        if (inicio.month == fin.month) {
          return 'Semana del ${inicio.day} al ${fin.day} de ${_kMesesCorto[fin.month]}';
        }
        return 'Semana del ${inicio.day} ${_kMesesCorto[inicio.month]} al ${fin.day} ${_kMesesCorto[fin.month]}';
      case 'mensual':
        final parts = clave.split('-');
        final mes = int.parse(parts[1]);
        return '${_kMeses[mes][0].toUpperCase()}${_kMeses[mes].substring(1)} ${parts[0]}';
      case 'diario':
      default:
        return _fechaLabel(clave);
    }
  }

  String _fechaLabel(String fecha) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = _parseFecha(fecha);
    if (d == today) return 'Hoy';
    if (d == today.subtract(const Duration(days: 1))) return 'Ayer';
    return '${_kDiasCorto[d.weekday - 1]} ${d.day} ${_kMesesCorto[d.month]}';
  }

  // ─── Totales ───────────────────────────────────────────────────────────────

  ({double ingresos, double gastos}) _totales(List<FinanceTransaction> txs) =>
      calcularIngresosGastos(txs, _libroActual.id);

  // ─── Filtros sheet ─────────────────────────────────────────────────────────

  void _mostrarBusqueda(BuildContext context, List<FinanceTransaction> txs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BusquedaSheet(
        txs: txs,
        catMap: {for (final c in ref.read(allFinanceCategoriesProvider).valueOrNull ?? <CatalogoCategoria>[]) c.id: c},
        onTap: (tx) {
          // Antes abría un formulario en blanco, ignorando por completo la
          // transacción tocada — un resultado de búsqueda debe abrir esa
          // transacción para editarla, no crear una nueva sin relación.
          Navigator.pop(ctx);
          showNuevaTransaccionSheet(context, libroId: tx.accountId, editar: tx);
        },
      ),
    );
  }

  void _mostrarPlantillasSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PlantillasSheet(
        libroId: _libroActual.id,
        onPlantillaSeleccionada: (template) {
          Navigator.pop(ctx);
          showNuevaTransaccionSheet(context, libroId: _libroActual.id, template: template);
        },
      ),
    );
  }

  // Ventanita emergente anclada al ícono de filtro (en vez del bottom sheet
  // de antes) — una lista compacta tipo menú que no ocupa toda la pantalla.
  // showMenu por sí solo cierra el menú en cada tap; _FiltrosPopupContent
  // usa un StatefulBuilder interno para que elegir una opción actualice el
  // filtro sin cerrar la ventanita, igual que un menú de "Ordenar por".
  void _mostrarFiltrosPopup(BuildContext anchorContext) {
    final button = anchorContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<void>(
      context: anchorContext,
      position: position,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _FiltrosPopupContent(
            filtros: ref.read(finanzasFiltrosProvider),
            onChanged: (f) => ref.read(finanzasFiltrosProvider.notifier).state = f,
          ),
        ),
      ],
    );
  }

  // ─── Delete ────────────────────────────────────────────────────────────────

  Future<bool> _confirmarEliminar(BuildContext ctx, FinanceTransaction tx) async {
    final result = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Eliminar transacción'),
        content: const Text('¿Seguro que deseas eliminar esta transacción?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Eliminar', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _eliminar(FinanceTransaction tx) async {
    final db = ref.read(databaseProvider);
    await db.deleteFinanceTransaction(tx.id);
    // La transacción pudo afectar tanto a su registro de origen como, si
    // era una transferencia, al de destino — ambos saldos deben refrescarse.
    final cuentasTocadas = <String>{
      tx.accountId,
      if (tx.transferToAccountId != null) tx.transferToAccountId!,
    };
    for (final cuentaId in cuentasTocadas) {
      ref.invalidate(finanzasLibroTxProvider(cuentaId));
      ref.invalidate(financeAccountBalanceProvider(cuentaId));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transacción eliminada')),
      );
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtros = ref.watch(finanzasFiltrosProvider);
    final asyncTx = ref.watch(finanzasLibroTxProvider(_libroActual.id));
    final asyncLibros = ref.watch(financeAccountsProvider);
    final asyncCats = ref.watch(allFinanceCategoriesProvider);
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Scaffold(
      body: asyncTx.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txs) {
          final grupos = _agrupar(txs, filtros.periodo, filtros.ascending);
          final tot = _totales(txs);
          final balanceAsync = ref.watch(financeAccountBalanceProvider(_libroActual.id));
          final balance = balanceAsync.maybeWhen(
            data: (b) => b.saldo,
            orElse: () => _libroActual.saldoInicial,
          );

          final catMap = asyncCats.valueOrNull != null
              ? {for (final c in asyncCats.valueOrNull!) c.id: c}
              : <String, CatalogoCategoria>{};

          // Build list of slivers
          final slivers = <Widget>[];

          // AppBar sliver
          slivers.add(
            SliverAppBar(
              pinned: true,
              floating: false,
              // Antes forzaba Colors.white — invisible en modo claro, donde
              // el AppBar (sin backgroundColor propio) hereda bgPrimary
              // claro del AppBarTheme. colors.textPrimary ya es el color
              // correcto para ese fondo en cualquier modo.
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              title: asyncLibros.maybeWhen(
                data: (rows) {
                  final libros = rows.map(FinanceAccount.fromRow).toList();
                  return DropdownButton<String>(
                    value: _libroActual.id,
                    underline: const SizedBox(),
                    dropdownColor: colors.bgCard,
                    icon: Icon(Icons.arrow_drop_down, color: colors.textPrimary),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.bold,
                    ),
                    items: libros
                        .map((l) => DropdownMenuItem(
                              value: l.id,
                              child: Text(l.nombre),
                            ))
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final nuevo = libros.firstWhere((l) => l.id == id);
                      setState(() => _libroActual = nuevo);
                    },
                  );
                },
                orElse: () => Text(
                  _libroActual.nombre,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () => _mostrarBusqueda(context, txs),
                ),
                Builder(
                  builder: (iconCtx) => IconButton(
                    icon: const Icon(Icons.tune_outlined),
                    onPressed: () => _mostrarFiltrosPopup(iconCtx),
                  ),
                ),
              ],
            ),
          );

          // Chip de filtro por categoría — visible solo cuando se llegó acá
          // desde un resultado de Estadísticas (Fase 06); sin esto, nada en
          // esta pantalla explicaría por qué el listado está recortado.
          if (filtros.categoriaId != null) {
            final cat = catMap[filtros.categoriaId];
            slivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: InputChip(
                    avatar: cat != null ? Icon(cat.icono, size: AppIconSize.small, color: cat.color) : null,
                    label: Text('Categoría: ${cat?.nombre ?? filtros.categoriaId}'),
                    onDeleted: () => ref.read(finanzasFiltrosProvider.notifier).state =
                        filtros.copyWith(limpiarCategoria: true),
                  ),
                ),
              ),
            );
          }

          // Resumen como tarjeta propia (no flotando en el AppBar) — le da
          // peso visual y deja de sentirse "suelto" sobre el fondo.
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: AppSectionCard(
                  children: [_ResumenCard(tot: tot, balance: balance, cantidad: txs.length)],
                ),
              ),
            ),
          );

          if (grupos.isEmpty) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: AppIconSize.large,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sin transacciones',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: AppTextSize.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            for (final entry in grupos.entries) {
              final clave = entry.key;
              final grupoTxs = entry.value;

              // Cada grupo es su propia tarjeta (header + filas + divisores
              // internos), en vez de texto suelto + lista plana — así el
              // histórico se ve "contenido" en bloques, no mezclado con el
              // fondo de la pantalla. El header y el borde/fondo usan
              // DecoratedSliver en vez de AppSectionCard (un Container):
              // con años de historial, un grupo podía tener cientos de filas
              // — SliverList solo materializa lo que entra en viewport, en
              // vez de construir+lay-outear toda la Column de una vez.
              final header = Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _grupoLabel(clave, filtros.periodo),
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // Texto neutro en vez de un monto verde/rojo sin
                    // contexto — un color ahí "sale de la nada" para quien
                    // no sabe de dónde surge.
                    Text(
                      '${grupoTxs.length} ${grupoTxs.length == 1 ? 'registro' : 'registros'}',
                      style: TextStyle(fontSize: AppTextSize.caption, color: colors.textTertiary),
                    ),
                  ],
                ),
              );
              final dividerColor = colors.textTertiary.withValues(alpha: 0.1);

              slivers.add(
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: colors.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: colors.borderCard.withValues(alpha: 0.6)),
                    ),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.card),
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(child: header),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                if (i.isOdd) {
                                  return Divider(height: 1, color: dividerColor);
                                }
                                final tx = grupoTxs[i ~/ 2];
                                return _TxRow(
                                  tx: tx,
                                  libroActualId: _libroActual.id,
                                  cat: catMap[tx.categoryId],
                                  // catMap ya es el catálogo combinado (fijo
                                  // + personalizado) — resolverlo acá en vez
                                  // de dentro de _TxRow evita que esa fila
                                  // busque el padre solo en el catálogo
                                  // fijo estático.
                                  catPadre: catMap[catMap[tx.categoryId]?.parentId],
                                  onConfirmDismiss: () => _confirmarEliminar(context, tx),
                                  onDismissed: () => _eliminar(tx),
                                  onEditar: () => showNuevaTransaccionSheet(
                                    context,
                                    libroId: tx.accountId,
                                    editar: tx,
                                  ),
                                  colors: colors,
                                );
                              },
                              childCount: grupoTxs.length * 2 - 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(finanzasLibroTxProvider(_libroActual.id));
              ref.invalidate(financeAccountBalanceProvider(_libroActual.id));
            },
            child: CustomScrollView(slivers: slivers),
          );
        },
      ),
      // Mismo patrón que credits_list_screen.dart: color de acento explícito
      // + contraste calculado — sin esto el FAB caía al tono por defecto de
      // Material3 (ajeno al acento elegido), y Finanzas no se sentía
      // personalizado aunque el usuario hubiera elegido un color.
      floatingActionButton: Builder(builder: (context) {
        final accentColor = Theme.of(context).colorScheme.primary;
        final fgColor = legibleForegroundOn(accentColor);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // FAB secundario — plantillas
            FloatingActionButton.small(
              heroTag: 'fab_plantillas',
              backgroundColor: accentColor,
              foregroundColor: fgColor,
              onPressed: _mostrarPlantillasSheet,
              child: const Icon(Icons.description_outlined),
            ),
            const SizedBox(height: 8),
            // FAB principal — nueva transacción
            FloatingActionButton(
              heroTag: 'fab_nueva_tx',
              backgroundColor: accentColor,
              foregroundColor: fgColor,
              onPressed: () => showNuevaTransaccionSheet(
                context,
                libroId: _libroActual.id,
              ),
              child: const Icon(Icons.add),
            ),
          ],
        );
      }),
    );
  }
}

// ─── Resumen informativo ────────────────────────────────────────────────────
// Tipografía pura, sin cajas ni barras de color: el color queda reservado
// para el monto de cada transacción en la lista, nunca para decoración del
// resumen — evita que el verde/rojo "invada" la pantalla antes de llegar
// siquiera al histórico.
class _ResumenCard extends StatelessWidget {
  final ({double ingresos, double gastos}) tot;
  final double balance;
  final int cantidad;

  const _ResumenCard({required this.tot, required this.balance, required this.cantidad});

  String _insight() {
    if (cantidad == 0) return 'Aún no hay registros.';
    if (tot.gastos == 0) {
      return '$cantidad ${cantidad == 1 ? 'registro' : 'registros'} · aún no tienes gastos.';
    }
    if (tot.ingresos == 0) {
      return '$cantidad ${cantidad == 1 ? 'registro' : 'registros'} · aún no tienes ingresos.';
    }
    final diff = ((tot.ingresos - tot.gastos).abs() / tot.gastos * 100).round();
    final quien = tot.ingresos >= tot.gastos ? 'ingresos superan gastos' : 'gastos superan ingresos';
    return '$cantidad ${cantidad == 1 ? 'registro' : 'registros'} · $quien en un $diff%.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final totalFlujo = tot.ingresos + tot.gastos;
    final pctIngresos = totalFlujo > 0 ? tot.ingresos / totalFlujo * 100 : 0.0;
    final pctGastos = totalFlujo > 0 ? tot.gastos / totalFlujo * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Balance a la izquierda, protagonista.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BALANCE TOTAL',
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatCOP(balance),
                    style: TextStyle(
                      fontSize: AppTextSize.hero,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 56, color: colors.textTertiary.withValues(alpha: 0.15)),
            const SizedBox(width: 14),
            // Ingresos (arriba) / Gastos (abajo) a la derecha — únicos dos
            // puntos de color de la tarjeta, flechas más chicas que el
            // texto para no competir con el balance.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ResumenDato(
                  icono: Icons.north_east,
                  iconoColor: const Color(0xFF22C55E),
                  texto: formatCOP(tot.ingresos),
                  pct: pctIngresos,
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _ResumenDato(
                  icono: Icons.south_east,
                  iconoColor: const Color(0xFFEF4444),
                  texto: formatCOP(tot.gastos),
                  pct: pctGastos,
                  colors: colors,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _insight(),
          style: TextStyle(fontSize: AppTextSize.caption, color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _ResumenDato extends StatelessWidget {
  final IconData icono;
  final Color iconoColor;
  final String texto;
  final double pct;
  final AppThemeColors colors;

  const _ResumenDato({
    required this.icono,
    required this.iconoColor,
    required this.texto,
    required this.pct,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icono, size: 14, color: iconoColor),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto,
              style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '${pct.toStringAsFixed(0)}% del total',
              style: TextStyle(fontSize: AppTextSize.caption, color: colors.textTertiary),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Fila de transacción ──────────────────────────────────────────────────────
class _TxRow extends StatelessWidget {
  final FinanceTransaction tx;
  final String libroActualId;
  final CatalogoCategoria? cat;
  final CatalogoCategoria? catPadre;
  final Future<bool> Function() onConfirmDismiss;
  final VoidCallback onDismissed;
  final VoidCallback onEditar;
  final AppThemeColors colors;

  const _TxRow({
    required this.tx,
    required this.libroActualId,
    required this.cat,
    required this.catPadre,
    required this.onConfirmDismiss,
    required this.onDismissed,
    required this.onEditar,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Una transferencia entrante (este libro es el destino, no el origen)
    // siempre suma, sin importar que tx.tipo siga siendo 'transferencia' —
    // esa marca describe la transacción desde el lado del origen.
    final esTransferenciaEntrante =
        tx.tipo == 'transferencia' && tx.accountId != libroActualId;
    final isIngreso = tx.tipo == 'ingreso' || esTransferenciaEntrante;
    final montoColor =
        isIngreso ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final montoStr =
        '${isIngreso ? '+' : '-'}${formatCOP(tx.monto)}';

    final catNombre = esTransferenciaEntrante
        ? 'Transferencia recibida'
        : (cat?.nombre ?? tx.categoryId);

    // La subcategoría es el título (protagonista de la fila); la categoría
    // padre pasa al subtítulo junto con nota y ordenante. catPadre viene
    // resuelto desde el catálogo combinado (fijo + personalizado) — antes
    // esto se buscaba acá mismo solo en catalogoCategoriaPadres (fijo), así
    // que una categoría padre personalizada nunca aparecía en el subtítulo.
    final detalle = [
      if (catPadre != null) catPadre!.nombre,
      if (tx.nota.isNotEmpty) tx.nota,
      if (tx.personaSitio != null && tx.personaSitio!.isNotEmpty)
        tx.personaSitio!,
    ].join(' · ');

    return Dismissible(
      key: ValueKey(tx.id),
      direction: DismissDirection.horizontal,
      // Swipe izquierda = eliminar (rojo); swipe derecha = editar (no se
      // elimina nada — confirmDismiss devuelve false para que la fila
      // vuelva a su lugar después de abrir el sheet).
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: colors.textTertiary.withValues(alpha: 0.15),
        child: Icon(Icons.edit_outlined, color: colors.textPrimary),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEditar();
          return false;
        }
        return onConfirmDismiss();
      },
      onDismissed: (_) => onDismissed(),
      child: InkWell(
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ícono neutro (ni verde ni rojo): el único color admitido
              // en la fila es el monto, a la derecha — así no hay dos
              // bloques de color compitiendo por la misma señal.
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  cat?.icono ?? Icons.label_outline,
                  size: AppIconSize.small,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              // Subcategoría como título (protagonista); categoría padre,
              // nota y ordenante quedan en el subtítulo.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      catNombre,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTextSize.body,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detalle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: TextStyle(
                          fontSize: AppTextSize.caption,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Monto como protagonista de la columna derecha; hora debajo,
              // como caption — en vez de ocupar una franja fija a la izquierda.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tx.revisionNota != null) ...[
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tx.revisionNota!)),
                            );
                          },
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: AppIconSize.small,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        montoStr,
                        style: TextStyle(
                          color: montoColor,
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (tx.hora != null && tx.hora!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      tx.hora!,
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Contenido del popup de filtros ───────────────────────────────────────────
// Lista compacta tipo menú (ventanita emergente anclada al ícono de filtro),
// en vez del bottom sheet de antes con segmented buttons/switches — cada
// fila es un ListTile con check a la izquierda cuando está seleccionada,
// agrupadas por sección con un divisor fino.
class _FiltrosPopupContent extends StatefulWidget {
  final FinanzasFiltros filtros;
  final ValueChanged<FinanzasFiltros> onChanged;

  const _FiltrosPopupContent({required this.filtros, required this.onChanged});

  @override
  State<_FiltrosPopupContent> createState() => _FiltrosPopupContentState();
}

class _FiltrosPopupContentState extends State<_FiltrosPopupContent> {
  late FinanzasFiltros _f;

  @override
  void initState() {
    super.initState();
    _f = widget.filtros;
  }

  void _update(FinanzasFiltros f) {
    setState(() => _f = f);
    widget.onChanged(f);
  }

  Widget _opcion({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        label,
        style: TextStyle(color: colors.textPrimary, fontSize: AppTextSize.body),
      ),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: AppIconSize.small,
        color: selected ? Theme.of(context).colorScheme.primary : colors.textTertiary,
      ),
      onTap: onTap,
    );
  }

  Widget _header(BuildContext context, String text) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return Container(
      color: colors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, 'Agrupar por'),
          _opcion(context: context, label: 'Día', selected: _f.periodo == 'diario', onTap: () => _update(_f.copyWith(periodo: 'diario'))),
          _opcion(context: context, label: 'Semana', selected: _f.periodo == 'semanal', onTap: () => _update(_f.copyWith(periodo: 'semanal'))),
          _opcion(context: context, label: 'Mes', selected: _f.periodo == 'mensual', onTap: () => _update(_f.copyWith(periodo: 'mensual'))),
          _opcion(context: context, label: 'Año', selected: _f.periodo == 'anual', onTap: () => _update(_f.copyWith(periodo: 'anual'))),
          _opcion(context: context, label: 'Sin agrupar', selected: _f.periodo == 'sin_agrupar', onTap: () => _update(_f.copyWith(periodo: 'sin_agrupar'))),
          Divider(height: 8, color: colors.textTertiary.withValues(alpha: 0.2)),
          _header(context, 'Orden'),
          _opcion(context: context, label: 'Más reciente primero', selected: !_f.ascending, onTap: () => _update(_f.copyWith(ascending: false))),
          _opcion(context: context, label: 'Más antiguo primero', selected: _f.ascending, onTap: () => _update(_f.copyWith(ascending: true))),
          Divider(height: 8, color: colors.textTertiary.withValues(alpha: 0.2)),
          _header(context, 'Tipo'),
          _opcion(context: context, label: 'Todos', selected: _f.tipoFiltro == 'todos', onTap: () => _update(_f.copyWith(tipoFiltro: 'todos'))),
          _opcion(context: context, label: 'Ingresos', selected: _f.tipoFiltro == 'ingreso', onTap: () => _update(_f.copyWith(tipoFiltro: 'ingreso'))),
          _opcion(context: context, label: 'Gastos', selected: _f.tipoFiltro == 'gasto', onTap: () => _update(_f.copyWith(tipoFiltro: 'gasto'))),
        ],
      ),
    );
  }
}

// ─── Búsqueda sheet ───────────────────────────────────────────────────────────
class _BusquedaSheet extends StatefulWidget {
  final List<FinanceTransaction> txs;
  final Map<String, CatalogoCategoria> catMap;
  final void Function(FinanceTransaction) onTap;

  const _BusquedaSheet({required this.txs, required this.catMap, required this.onTap});

  @override
  State<_BusquedaSheet> createState() => _BusquedaSheetState();
}

class _BusquedaSheetState extends State<_BusquedaSheet> {
  final _ctrl = TextEditingController();
  List<FinanceTransaction> _results = [];

  @override
  void initState() {
    super.initState();
    _results = widget.txs;
    _ctrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_filtrar);
    _ctrl.dispose();
    super.dispose();
  }

  void _filtrar() {
    final q = _ctrl.text.toLowerCase();
    setState(() {
      _results = widget.txs.where((t) {
        final nombreCategoria = widget.catMap[t.categoryId]?.nombre.toLowerCase() ?? '';
        return t.nota.toLowerCase().contains(q) ||
            (t.personaSitio?.toLowerCase().contains(q) ?? false) ||
            t.monto.toString().contains(q) ||
            t.fecha.contains(q) ||
            nombreCategoria.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    // Padding(bottom: viewInsets): un DraggableScrollableSheet no se
    // reacomoda solo con el teclado — sin esto, los resultados de abajo
    // quedaban tapados al escribir.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Material(
        // Material (no Container con color propio): hay un ListTile más
        // abajo que pinta fondo/ripple en el Material más cercano. Color
        // estándar de sheet (scaffoldBackgroundColor), no tc.bgCard — mismo
        // tono que Créditos, ver nota igual en nueva_transaccion_sheet.dart.
        color: Theme.of(ctx).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: tc.borderCard, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar transacciones…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text('Sin resultados', style: TextStyle(color: tc.textSecondary)))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final tx = _results[i];
                        final isIngreso = tx.tipo == 'ingreso';
                        final titulo = tx.personaSitio?.isNotEmpty == true
                            ? tx.personaSitio!
                            : tx.nota.isNotEmpty
                                ? tx.nota
                                : tx.tipo;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isIngreso
                                ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                                : const Color(0xFFEF4444).withValues(alpha: 0.15),
                            child: Icon(
                              isIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                              size: 16,
                              color: isIngreso ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                            ),
                          ),
                          title: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(tx.fecha, style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary)),
                          trailing: Text(
                            formatCOP(tx.monto),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isIngreso ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                            ),
                          ),
                          onTap: () => widget.onTap(tx),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Plantillas sheet (selección rápida) ──────────────────────────────────────
class _PlantillasSheet extends ConsumerWidget {
  final String libroId;
  final void Function(FinanceTemplate) onPlantillaSeleccionada;

  const _PlantillasSheet({
    required this.libroId,
    required this.onPlantillaSeleccionada,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final asyncTemplates = ref.watch(financeTemplatesByTipoProvider(null));

    return Material(
      // Material (no Container con color propio): hay un ListTile más abajo
      // que pinta fondo/ripple en el Material más cercano. Color estándar
      // de sheet (scaffoldBackgroundColor), no tc.bgCard — mismo tono que
      // Créditos, ver nota igual en nueva_transaccion_sheet.dart.
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: tc.borderCard, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Usar plantilla', style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.bold, color: tc.textPrimary)),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanzasPlantillasScreen()),
                  );
                },
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Administrar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          asyncTemplates.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (templates) {
              if (templates.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.description_outlined, size: AppIconSize.large, color: tc.textSecondary),
                        const SizedBox(height: 8),
                        Text('Sin plantillas creadas', style: TextStyle(color: tc.textSecondary)),
                      ],
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 280,
                child: ListView.builder(
                  itemCount: templates.length,
                  itemBuilder: (_, i) {
                    final t = templates[i];
                    final isIngreso = t.tipo == 'ingreso';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isIngreso
                            ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                            : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        child: Icon(
                          isIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 18,
                          color: isIngreso ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        ),
                      ),
                      title: Text(t.nombre),
                      subtitle: t.monto != null
                          ? Text(formatCOP(t.monto!), style: TextStyle(color: tc.textSecondary, fontSize: AppTextSize.caption))
                          : null,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => onPlantillaSeleccionada(t),
                    );
                  },
                ),
              );
            },
          ),
        ],
        ),
      ),
    );
  }
}
