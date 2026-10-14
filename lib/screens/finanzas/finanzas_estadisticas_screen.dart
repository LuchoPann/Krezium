import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_budget.dart';
import 'package:krezium/domain/finance_ledger.dart';
import 'package:krezium/domain/finance_observaciones.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/screens/finanzas/finanzas_libro_transacciones_screen.dart';
import 'package:krezium/screens/finanzas/finanzas_planificacion_screen.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:intl/intl.dart' show DateFormat;

// ─── Color helpers ─────────────────────────────────────────────────────────────

Color _colorFromHex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

const _kIngresos = Color(0xFF22C55E);
const _kGastos = Color(0xFFEF4444);
const _kPieColors = [
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFF6B7280),
];

const _kMesesCortos = [
  '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

// ─── Período ───────────────────────────────────────────────────────────────────

enum _Periodo { esteMes, tresMeses, seisMeses, esteAnio }

extension _PeriodoLabel on _Periodo {
  String get label {
    switch (this) {
      case _Periodo.esteMes:     return 'Este mes';
      case _Periodo.tresMeses:   return '3 meses';
      case _Periodo.seisMeses:   return '6 meses';
      case _Periodo.esteAnio:    return 'Este año';
    }
  }

  bool isInRange(String fecha) {
    final now = DateTime.now();
    final parts = fecha.split('-');
    if (parts.length < 2) return false;
    final year  = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    switch (this) {
      case _Periodo.esteMes:
        return year == now.year && month == now.month;
      case _Periodo.tresMeses:
        final from = DateTime(now.year, now.month - 2);
        return DateTime(year, month).isAfter(from.subtract(const Duration(days: 1)));
      case _Periodo.seisMeses:
        final from = DateTime(now.year, now.month - 5);
        return DateTime(year, month).isAfter(from.subtract(const Duration(days: 1)));
      case _Periodo.esteAnio:
        return year == now.year;
    }
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class FinanzasEstadisticasScreen extends ConsumerStatefulWidget {
  final FinanceAccount? libroInicial;

  const FinanzasEstadisticasScreen({super.key, this.libroInicial});

  @override
  ConsumerState<FinanzasEstadisticasScreen> createState() =>
      _FinanzasEstadisticasScreenState();
}

class _FinanzasEstadisticasScreenState
    extends ConsumerState<FinanzasEstadisticasScreen> {
  FinanceAccount? _libroActual;
  _Periodo _periodo = _Periodo.esteMes;
  int? _touchedPieIndex;

  // All transactions for the active libro (no period filter)
  Future<List<FinanceTransaction>>? _allTxFuture;

  @override
  void initState() {
    super.initState();
    _libroActual = widget.libroInicial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_libroActual == null) {
      final accounts = ref.read(financeAccountsProvider);
      final rows = accounts.valueOrNull;
      if (rows != null && rows.isNotEmpty) {
        _libroActual = FinanceAccount.fromRow(rows.first);
      }
    }
    _reloadTx();
  }

  void _reloadTx() {
    if (_libroActual == null) return;
    final db = ref.read(databaseProvider);
    _allTxFuture = db
        .getFinanceTransactionsByLibro(
          libroId: _libroActual!.id,
          mes: null,
          tipo: null,
        )
        .then((rows) => rows.map(FinanceTransaction.fromRow).toList());
  }

  void _changeLibro(FinanceAccount libro) {
    setState(() {
      _libroActual = libro;
      _touchedPieIndex = null;
    });
    _reloadTx();
  }

  // ─── Totales ────────────────────────────────────────────────────────────────

  ({double ingresos, double gastos, double balance}) _totales(
      List<FinanceTransaction> txs) {
    final enPeriodo =
        txs.where((t) => _periodo.isInRange(t.fecha)).toList();
    final ig = calcularIngresosGastos(enPeriodo, _libroActual?.id ?? '');
    return (
      ingresos: ig.ingresos,
      gastos: ig.gastos,
      balance: (_libroActual?.saldoInicial ?? 0) + ig.ingresos - ig.gastos,
    );
  }

  // ─── Comparación con el mes anterior (Fase 06) ──────────────────────────────
  // Solo tiene sentido para "Este mes": comparar "3 meses" o "6 meses" contra
  // el bloque inmediatamente anterior de igual longitud sería más confuso
  // que útil, así que esa comparación queda fuera de alcance por ahora.

  double _gastosMesAnterior(List<FinanceTransaction> txs) {
    final now = DateTime.now();
    final anterior = DateTime(now.year, now.month - 1);
    final prefix = '${anterior.year}-${anterior.month.toString().padLeft(2, '0')}';
    return txs
        .where((t) => t.tipo == 'gasto' && t.fecha.startsWith(prefix))
        .fold(0.0, (s, t) => s + t.monto);
  }

  Map<String, double> _gastoPorCategoriaEnMes(List<FinanceTransaction> txs, DateTime mes) {
    final prefix = '${mes.year}-${mes.month.toString().padLeft(2, '0')}';
    final mapa = <String, double>{};
    for (final t in txs) {
      if (t.tipo != 'gasto') continue;
      if (!t.fecha.startsWith(prefix)) continue;
      mapa[t.categoryId] = (mapa[t.categoryId] ?? 0) + t.monto;
    }
    return mapa;
  }

  // ─── Pie data (gastos por categoría) ────────────────────────────────────────

  List<({String catId, double monto})> _gastosPorCategoria(
      List<FinanceTransaction> txs) {
    final mapa = <String, double>{};
    for (final t in txs) {
      if (t.tipo != 'gasto') continue;
      if (!_periodo.isInRange(t.fecha)) continue;
      mapa[t.categoryId] = (mapa[t.categoryId] ?? 0) + t.monto;
    }
    final lista = mapa.entries
        .map((e) => (catId: e.key, monto: e.value))
        .toList()
      ..sort((a, b) => b.monto.compareTo(a.monto));

    if (lista.length <= 6) return lista;

    final top5 = lista.sublist(0, 6);
    final otros = lista.sublist(6).fold<double>(0, (s, e) => s + e.monto);
    return [...top5, (catId: '__otros__', monto: otros)];
  }

  // ─── Bar chart: últimos 6 meses ─────────────────────────────────────────────

  List<({int year, int month, double ingresos, double gastos})> _tendencia(
      List<FinanceTransaction> txs) {
    final now = DateTime.now();
    final result = <({int year, int month, double ingresos, double gastos})>[];

    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      final prefix =
          '${d.year}-${d.month.toString().padLeft(2, '0')}';
      double ing = 0, gas = 0;
      for (final t in txs) {
        if (!t.fecha.startsWith(prefix)) continue;
        if (t.tipo == 'ingreso') ing += t.monto;
        if (t.tipo == 'gasto')   gas += t.monto;
      }
      result.add((year: d.year, month: d.month, ingresos: ing, gastos: gas));
    }
    return result;
  }

  // ─── Fase 06: navegar desde un resultado a los movimientos que lo originan ──

  void _irAMovimientosDeCategoria(String categoriaId) {
    if (_libroActual == null) return;
    ref.read(finanzasFiltrosProvider.notifier).state =
        ref.read(finanzasFiltrosProvider).copyWith(categoriaId: categoriaId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanzasLibroTransaccionesScreen(libro: _libroActual!),
      ),
    );
  }

  // ─── Formato compacto ────────────────────────────────────────────────────────

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asyncLibros = ref.watch(financeAccountsProvider);
    final asyncCats   = ref.watch(allFinanceCategoriesProvider);
    final colors      = Theme.of(context).extension<AppThemeColors>()!;
    // Balance "oficial" (transfer-aware) del libro activo — la tarjeta
    // "Balance" de la fila Resumen lo usa en vez del balance period-scoped
    // de _totales, que viene de una query solo-origen y no refleja
    // transferencias recibidas dentro del periodo.
    final balanceOficial = _libroActual == null
        ? null
        : ref.watch(financeAccountBalanceProvider(_libroActual!.id));

    // Auto-set libro from provider if still null (first frame after accounts load)
    if (_libroActual == null) {
      final rows = asyncLibros.valueOrNull;
      if (rows != null && rows.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _libroActual = FinanceAccount.fromRow(rows.first);
              _reloadTx();
            });
          }
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final libroColor  = _colorFromHex(_libroActual!.color);

    return Scaffold(
      appBar: AppBar(
        title: asyncLibros.maybeWhen(
          data: (rows) {
            final libros = rows.map(FinanceAccount.fromRow).toList();
            return DropdownButton<String>(
              value: _libroActual!.id,
              underline: const SizedBox(),
              dropdownColor: colors.bgCard,
              icon: const Icon(Icons.arrow_drop_down),
              style: TextStyle(
                color: Theme.of(context).appBarTheme.foregroundColor ??
                    Colors.white,
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
                _changeLibro(nuevo);
              },
            );
          },
          orElse: () => const Text('Estadísticas'),
        ),
        actions: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: libroColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<FinanceTransaction>>(
        future: _allTxFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final allTxs = snap.data ?? [];

          // Map categorías
          final catMap = asyncCats.valueOrNull != null
              ? {for (final c in asyncCats.valueOrNull!) c.id: c}
              : <String, CatalogoCategoria>{};

          final tot = _totales(allTxs);
          final pieData = _gastosPorCategoria(allTxs);
          final tendencia = _tendencia(allTxs);
          final hayDatos = pieData.isNotEmpty || tot.ingresos > 0 || tot.gastos > 0;
          // Balance "oficial" (transfer-aware) para la tarjeta de Resumen —
          // tot.balance es period-scoped y viene de una query solo-origen,
          // así que no refleja transferencias recibidas dentro del periodo.
          // Mientras el provider carga/falla, se usa tot.balance como
          // fallback visual.
          final balanceTarjeta = balanceOficial?.maybeWhen(
                data: (b) => b.saldo,
                orElse: () => tot.balance,
              ) ??
              tot.balance;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Selector período ──────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _Periodo.values
                        .map((p) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(p.label),
                                selected: _periodo == p,
                                onSelected: (_) =>
                                    setState(() {
                                      _periodo = p;
                                      _touchedPieIndex = null;
                                    }),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Sección 1: Resumen cards ──────────────────────────────────
                Text(
                  'Resumen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ResumenCard(
                      label: 'Ingresos',
                      monto: tot.ingresos,
                      color: _kIngresos,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),
                    _ResumenCard(
                      label: 'Gastos',
                      monto: tot.gastos,
                      color: _kGastos,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),
                    _ResumenCard(
                      label: 'Balance',
                      monto: balanceTarjeta,
                      color: balanceTarjeta >= 0 ? _kIngresos : _kGastos,
                      colors: colors,
                    ),
                  ],
                ),
                // Comparación con el mes anterior — solo para "Este mes" (el
                // único periodo donde comparar contra "el bloque anterior"
                // es inequívoco) y solo si ese mes anterior tiene datos
                // (si no, no hay base real para un %, ver comparacionPeriodoAnterior).
                if (_periodo == _Periodo.esteMes) ...[
                  Builder(builder: (context) {
                    final comparacion = comparacionPeriodoAnterior(
                      actual: tot.gastos,
                      anterior: _gastosMesAnterior(allTxs),
                    );
                    if (comparacion == null) return const SizedBox.shrink();
                    final ahora = DateTime.now();
                    final mesAnterior = DateTime(ahora.year, ahora.month - 1);
                    final subio = comparacion.deltaPct > 0;
                    final pct = comparacion.deltaPct.abs().round();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        comparacion.deltaPct == 0
                            ? 'Gastaste igual que en ${_kMesesCortos[mesAnterior.month]}: ${formatCOP(tot.gastos)}.'
                            : 'Gastaste $pct% ${subio ? 'más' : 'menos'} que en '
                                '${_kMesesCortos[mesAnterior.month]} '
                                '(${formatCOP(comparacion.anterior)} → ${formatCOP(comparacion.actual)}).',
                        style: TextStyle(
                          fontSize: AppTextSize.caption,
                          color: subio ? _kGastos : colors.textSecondary,
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 24),

                // ── Sección Observaciones (Fase 07) ───────────────────────
                // Solo reglas deterministas sobre datos reales — nunca se
                // muestra nada sin evidencia suficiente (ver finance_observaciones.dart).
                _ObservacionesSection(
                  libro: _libroActual!,
                  allTxs: allTxs,
                  catMap: catMap,
                  gastoPorCategoriaMes: _gastoPorCategoriaEnMes,
                ),

                if (!hayDatos) ...[
                  // ── Estado vacío ──────────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 32),
                        Icon(Icons.bar_chart,
                            size: 64,
                            color: colors.textSecondary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'Sin datos para este período',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // ── Sección 2: PieChart donut ─────────────────────────────
                  if (pieData.isNotEmpty) ...[
                    Text(
                      'Gastos por categoría',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _PieDonutSection(
                      data: pieData,
                      catMap: catMap,
                      touchedIndex: _touchedPieIndex,
                      onTouch: (idx) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _touchedPieIndex =
                              _touchedPieIndex == idx ? null : idx;
                        });
                      },
                      totalGastos: pieData.fold(0, (s, e) => s + e.monto),
                      onCategoriaTap: _irAMovimientosDeCategoria,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Sección 3: BarChart tendencia mensual ─────────────────
                  Text(
                    'Tendencia mensual',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _BarTendencia(tendencia: tendencia, fmt: _fmt),
                  const SizedBox(height: 24),
                ],

                // ── Sección 4: Balance por libros ─────────────────────────
                asyncLibros.maybeWhen(
                  data: (rows) {
                    final libros = rows.map(FinanceAccount.fromRow).toList();
                    if (libros.length <= 1) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Balance por libro',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: libros.length,
                            separatorBuilder: (ctx2, i2) =>
                                const SizedBox(width: 12),
                            itemBuilder: (ctx, i) {
                              final l = libros[i];
                              final lColor = _colorFromHex(l.color);
                              return _LibroBalanceCard(
                                libro: l,
                                libroColor: lColor,
                                colors: colors,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Resumen card ─────────────────────────────────────────────────────────────

// ─── Observaciones (Fase 07) ────────────────────────────────────────────────
// Combina 3 reglas deterministas: aumento de gasto en una categoría (del
// libro activo, mes actual vs. anterior), presupuesto cercano a su límite
// y meta de ahorro fuera de ritmo (ambas globales — no son por libro).
// Se oculta por completo si ninguna regla encontró evidencia suficiente.
class _ObservacionesSection extends ConsumerWidget {
  final FinanceAccount libro;
  final List<FinanceTransaction> allTxs;
  final Map<String, CatalogoCategoria> catMap;
  final Map<String, double> Function(List<FinanceTransaction>, DateTime) gastoPorCategoriaMes;

  const _ObservacionesSection({
    required this.libro,
    required this.allTxs,
    required this.catMap,
    required this.gastoPorCategoriaMes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final now = DateTime.now();

    final obsAumento = observacionesAumentoCategoria(
      gastoActualPorCategoria: gastoPorCategoriaMes(allTxs, now),
      gastoAnteriorPorCategoria: gastoPorCategoriaMes(allTxs, DateTime(now.year, now.month - 1)),
      nombrePorCategoria: {for (final c in catMap.values) c.id: c.nombre},
    );

    final mes = DateFormat('yyyy-MM').format(now);
    final budgetsAsync = ref.watch(financeBudgetsProvider((now.year, now.month)));
    final txMesAsync = ref.watch(financeTransactionsProvider(mes));
    final catsAsync = ref.watch(allFinanceCategoriesProvider);
    final metasAsync = ref.watch(allFinanceReservationsProvider);

    final obsPresupuesto = (budgetsAsync.valueOrNull != null &&
            txMesAsync.valueOrNull != null &&
            catsAsync.valueOrNull != null)
        ? observacionesPresupuestoCercano(budgetsAsync.value!.map((b) {
            final cat = catsAsync.value!.where((c) => c.id == b.categoryId).firstOrNull;
            final parentPorCategoria = {for (final c in catsAsync.value!) c.id: c.parentId};
            final txs = txMesAsync.value!.map(FinanceTransaction.fromRow).toList();
            final gasto = gastoCategoriaPeriodo(
              categoryId: b.categoryId, transacciones: txs, parentPorCategoria: parentPorCategoria,
            );
            return (
              categoryId: b.categoryId,
              nombre: cat?.nombre ?? b.categoryId,
              progreso: progresoPresupuesto(gasto: gasto, limite: b.montoLimite),
            );
          }).toList())
        : <Observacion>[];

    final obsMetas = metasAsync.valueOrNull != null
        ? observacionesMetaFueraDeRitmo(
            metasAsync.value!.map((m) => (
                  id: m.id,
                  nombre: m.nombre,
                  aportado: m.monto,
                  objetivo: m.montoObjetivo,
                  creadaEn: DateTime.tryParse(m.creadaEn) ?? now,
                  fechaLimite: m.fechaLimite != null ? DateTime.tryParse(m.fechaLimite!) : null,
                  estado: m.estado,
                )).toList(),
            hoy: now,
          )
        : <Observacion>[];

    final todas = [...obsAumento, ...obsPresupuesto, ...obsMetas];
    if (todas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Observaciones', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final obs in todas) ...[
            _ObservacionCard(obs: obs, colors: colors, libro: libro),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ObservacionCard extends ConsumerWidget {
  final Observacion obs;
  final AppThemeColors colors;
  final FinanceAccount libro;

  const _ObservacionCard({required this.obs, required this.colors, required this.libro});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icono, color, titulo, descripcion) = switch (obs.tipo) {
      TipoObservacion.aumentoCategoria => (
          Icons.trending_up,
          _kGastos,
          'Aumento en ${obs.nombre}',
          'Gastaste ${obs.deltaPct!.round()}% más en ${obs.nombre} este mes '
              '(${formatCOP(obs.valorAnterior!)} → ${formatCOP(obs.valorActual!)}).',
        ),
      TipoObservacion.presupuestoCercano => (
          Icons.pie_chart_outline,
          obs.progreso! >= 1 ? _kGastos : Colors.amber.shade800,
          obs.progreso! >= 1 ? 'Presupuesto agotado: ${obs.nombre}' : 'Cerca del límite: ${obs.nombre}',
          'Vas en ${(obs.progreso! * 100).round()}% del presupuesto de ${obs.nombre} este mes.',
        ),
      TipoObservacion.metaFueraDeRitmo => (
          Icons.flag_outlined,
          Colors.amber.shade800,
          'Meta atrasada: ${obs.nombre}',
          'Llevas ${(obs.valorActual! * 100).round()}% aportado, cuando lo esperado a este punto '
              'del plazo era ${(obs.valorAnterior! * 100).round()}%.',
        ),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        switch (obs.tipo) {
          case TipoObservacion.aumentoCategoria:
            // Mismo patrón de drill-down que la leyenda del donut (Fase 06):
            // filtra el historial de este libro a la categoría que originó
            // la observación. El filtro se fija antes de navegar, nunca
            // dentro del build de la ruta nueva.
            ref.read(finanzasFiltrosProvider.notifier).state =
                ref.read(finanzasFiltrosProvider).copyWith(categoriaId: obs.refId);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FinanzasLibroTransaccionesScreen(libro: libro)),
            );
          case TipoObservacion.presupuestoCercano:
          case TipoObservacion.metaFueraDeRitmo:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinanzasPlanificacionScreen()),
            );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: AppIconSize.medium),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, color: colors.textPrimary, fontSize: AppTextSize.body)),
                  const SizedBox(height: 2),
                  Text(descripcion, style: TextStyle(color: colors.textSecondary, fontSize: AppTextSize.caption)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: AppIconSize.small, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _ResumenCard extends StatelessWidget {
  final String label;
  final double monto;
  final Color color;
  final AppThemeColors colors;

  const _ResumenCard({
    required this.label,
    required this.monto,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatCOP(monto),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.body,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pie donut section ────────────────────────────────────────────────────────

class _PieDonutSection extends StatelessWidget {
  final List<({String catId, double monto})> data;
  final Map<String, CatalogoCategoria> catMap;
  final int? touchedIndex;
  final ValueChanged<int> onTouch;
  final double totalGastos;
  final ValueChanged<String> onCategoriaTap;

  const _PieDonutSection({
    required this.data,
    required this.catMap,
    required this.touchedIndex,
    required this.onTouch,
    required this.totalGastos,
    required this.onCategoriaTap,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[];
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final isOtros = item.catId == '__otros__';
      final cat = isOtros ? null : catMap[item.catId];
      final color = _kPieColors[i % _kPieColors.length];
      final isTouched = touchedIndex == i;
      final pct = totalGastos > 0 ? item.monto / totalGastos * 100 : 0.0;
      final label = isOtros
          ? 'Otros'
          : (cat?.nombre ?? item.catId);

      sections.add(PieChartSectionData(
        value: item.monto,
        color: color,
        radius: isTouched ? 70 : 60,
        title: isTouched ? '${pct.toStringAsFixed(1)}%' : '',
        // Color de categoría arbitrario — texto blanco fijo se volvía
        // ilegible en las tonalidades claras de _kPieColors.
        titleStyle: TextStyle(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.bold,
          color: legibleForegroundOn(color),
        ),
        badgeWidget: isTouched
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$label\n${formatCOP(item.monto)}',
                  style: TextStyle(
                    color: legibleForegroundOn(color),
                    fontSize: AppTextSize.caption,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : null,
        badgePositionPercentageOffset: 1.4,
      ));
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 50,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions) return;
                  final idx = response?.touchedSection?.touchedSectionIndex;
                  if (idx != null && idx >= 0) onTouch(idx);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Leyenda
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (int i = 0; i < data.length; i++)
              _PieLegendItem(
                item: data[i],
                cat: data[i].catId == '__otros__'
                    ? null
                    : catMap[data[i].catId],
                color: _kPieColors[i % _kPieColors.length],
                totalGastos: totalGastos,
                isOtros: data[i].catId == '__otros__',
                onTap: data[i].catId == '__otros__' ? null : () => onCategoriaTap(data[i].catId),
              ),
          ],
        ),
      ],
    );
  }
}

class _PieLegendItem extends StatelessWidget {
  final ({String catId, double monto}) item;
  final CatalogoCategoria? cat;
  final Color color;
  final double totalGastos;
  final bool isOtros;
  // Fase 06: navega a los movimientos que originan esta porción — null
  // para "Otros" (agrupa varias categorías, no hay un único filtro posible).
  final VoidCallback? onTap;

  const _PieLegendItem({
    required this.item,
    required this.cat,
    required this.color,
    required this.totalGastos,
    required this.isOtros,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = isOtros ? 'Otros' : (cat?.nombre ?? item.catId);
    final pct = totalGastos > 0 ? item.monto / totalGastos * 100 : 0.0;
    final contenido = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(
          '$nombre  ${formatCOP(item.monto)} (${pct.toStringAsFixed(1)}%)',
          style: const TextStyle(fontSize: AppTextSize.caption),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: AppIconSize.micro, color: Theme.of(context).colorScheme.primary),
        ],
      ],
    );
    if (onTap == null) return contenido;
    return InkWell(onTap: onTap, child: contenido);
  }
}

// ─── Bar chart tendencia ──────────────────────────────────────────────────────

class _BarTendencia extends StatelessWidget {
  final List<({int year, int month, double ingresos, double gastos})> tendencia;
  final String Function(double) fmt;

  const _BarTendencia({required this.tendencia, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final maxVal = tendencia.fold<double>(
      0,
      (m, e) => math.max(m, math.max(e.ingresos, e.gastos)),
    );
    final maxY = maxVal == 0 ? 100.0 : (maxVal * 1.2);

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < tendencia.length; i++) {
      final t = tendencia[i];
      groups.add(BarChartGroupData(
        x: i,
        groupVertically: false,
        barRods: [
          BarChartRodData(
            toY: t.ingresos,
            color: _kIngresos,
            width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: t.gastos,
            color: _kGastos,
            width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
        barsSpace: 4,
      ));
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: groups,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, meta) => Text(
                  fmt(v),
                  style: const TextStyle(fontSize: AppTextSize.caption),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= tendencia.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    _kMesesCortos[tendencia[idx].month],
                    style: const TextStyle(fontSize: AppTextSize.caption),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final t = tendencia[groupIndex];
                final isIng = rodIndex == 0;
                return BarTooltipItem(
                  '${_kMesesCortos[t.month]}\n'
                  '${isIng ? "Ingresos" : "Gastos"}: ${formatCOP(rod.toY)}',
                  TextStyle(
                    color: isIng ? _kIngresos : _kGastos,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.caption,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Libro balance card ───────────────────────────────────────────────────────

class _LibroBalanceCard extends ConsumerWidget {
  final FinanceAccount libro;
  final Color libroColor;
  final AppThemeColors colors;

  const _LibroBalanceCard({
    required this.libro,
    required this.libroColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(financeAccountBalanceProvider(libro.id));
    return balanceAsync.when(
      loading: () => _buildCard(libro.saldoInicial),
      error: (e, st) => _buildCard(libro.saldoInicial),
      data: (b) => _buildCard(b.saldo),
    );
  }

  Widget _buildCard(double balance) {
    final balanceColor = balance >= 0 ? _kIngresos : _kGastos;
    return Container(
          width: 140,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: libroColor.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: libroColor.withValues(alpha: 0.2),
                    child: Text(
                      libro.nombre.isNotEmpty
                          ? libro.nombre[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: libroColor,
                          fontSize: AppTextSize.caption,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      libro.nombre,
                      style: const TextStyle(
                          fontSize: AppTextSize.caption, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatCOP(balance),
                style: TextStyle(
                  color: balanceColor,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.body,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
  }
}
