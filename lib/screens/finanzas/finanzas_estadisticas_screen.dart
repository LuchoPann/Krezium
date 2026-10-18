import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/data/db/database.dart';
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
    // didChangeDependencies corre con cualquier InheritedWidget que cambie
    // (Theme, MediaQuery, etc.), no solo al entrar a la pantalla — recargar
    // ahí reconsultaba la DB entera en cada uno de esos cambios. _changeLibro
    // ya dispara su propio _reloadTx() cuando el usuario cambia de cuenta.
    _allTxFuture ??= _buildTxFuture();
  }

  Future<List<FinanceTransaction>>? _buildTxFuture() {
    if (_libroActual == null) return null;
    final db = ref.read(databaseProvider);
    return db
        .getFinanceTransactionsByLibro(
          libroId: _libroActual!.id,
          mes: null,
          tipo: null,
        )
        .then((rows) => rows.map(FinanceTransaction.fromRow).toList());
  }

  void _reloadTx() {
    _allTxFuture = _buildTxFuture();
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
    // Fase E3: presupuestos del mes en curso — para el acceso directo a
    // Planificación desde la leyenda del pastel cuando esa categoría ya
    // tiene presupuesto asignado.
    final budgetsAsync = ref.watch(
        financeBudgetsProvider((DateTime.now().year, DateTime.now().month)));
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

                // ── Sección 1: Resumen hero ────────────────────────────────────
                _ResumenHero(
                  balance: balanceTarjeta,
                  ingresos: tot.ingresos,
                  gastos: tot.gastos,
                  colors: colors,
                  // Comparación con el mes anterior — solo para "Este mes"
                  // (único periodo donde comparar contra "el bloque
                  // anterior" es inequívoco) y solo si ese mes anterior
                  // tiene datos (ver comparacionPeriodoAnterior).
                  comparacion: _periodo == _Periodo.esteMes
                      ? comparacionPeriodoAnterior(
                          actual: tot.gastos,
                          anterior: _gastosMesAnterior(allTxs),
                        )
                      : null,
                ),
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
                      // Fase E2: variación vs. mes anterior por categoría —
                      // mismo criterio que la comparación de totales (Fase
                      // 06): solo tiene sentido comparar "Este mes" contra
                      // "el mes anterior completo", nunca contra un bloque
                      // de 3/6 meses de distinta duración.
                      gastoPorCategoriaAnterior: _periodo == _Periodo.esteMes
                          ? _gastoPorCategoriaEnMes(
                              allTxs,
                              DateTime(DateTime.now().year, DateTime.now().month - 1),
                            )
                          : null,
                      budgetsPorCategoria: budgetsAsync.valueOrNull != null
                          ? {for (final b in budgetsAsync.value!) b.categoryId: b}
                          : const {},
                      onPresupuestoTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FinanzasPlanificacionScreen()),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Sección 3: BarChart tendencia mensual ─────────────────
                  Text(
                    'Tendencia mensual',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _BarTendencia(tendencia: tendencia, fmt: _fmt, colors: colors),
                  const SizedBox(height: 24),
                ],

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

// ─── Resumen hero ─────────────────────────────────────────────────────────────
// Una sola tarjeta: el Balance es el número protagonista; la barra visualiza
// la proporción ingresos/gastos (sustituye la lectura mental del pastel para
// esto); Ingresos/Gastos abajo son soporte de la misma barra, no una
// repetición — cada monto solo aparece una vez en toda la sección.
class _ResumenHero extends StatelessWidget {
  final double balance;
  final double ingresos;
  final double gastos;
  final AppThemeColors colors;
  final ({double actual, double anterior, double deltaPct})? comparacion;

  const _ResumenHero({
    required this.balance,
    required this.ingresos,
    required this.gastos,
    required this.colors,
    this.comparacion,
  });

  @override
  Widget build(BuildContext context) {
    final total = ingresos + gastos;
    final fracIngresos = total > 0 ? ingresos / total : 0.5;
    final balanceColor = balance >= 0 ? _kIngresos : _kGastos;
    final subio = (comparacion?.deltaPct ?? 0) > 0;
    final pct = comparacion?.deltaPct.abs().round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.card),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderCard.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatCOP(balance),
            style: TextStyle(
              color: balanceColor,
              fontWeight: FontWeight.bold,
              fontSize: AppTextSize.emphasis,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          // Barra ingresos/gastos — única fuente visual de la proporción.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (fracIngresos * 1000).round().clamp(1, 999),
                    child: Container(color: _kIngresos),
                  ),
                  Expanded(
                    flex: ((1 - fracIngresos) * 1000).round().clamp(1, 999),
                    child: Container(color: _kGastos),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroDato(
                  icono: Icons.arrow_downward,
                  label: 'Ingresos',
                  monto: ingresos,
                  color: _kIngresos,
                  colors: colors,
                ),
              ),
              Expanded(
                child: _HeroDato(
                  icono: Icons.arrow_upward,
                  label: 'Gastos',
                  monto: gastos,
                  color: _kGastos,
                  colors: colors,
                  badge: (comparacion != null && pct != null)
                      ? (subio: subio, pct: pct)
                      : null,
                ),
              ),
            ],
          ),
          // Fase E1: tasa de ahorro — oculta sin ingresos registrados (no
          // hay base real sobre la cual calcular un %, ver tasaAhorro).
          Builder(builder: (context) {
            final tasa = tasaAhorro(ingresos: ingresos, gastos: gastos);
            if (tasa == null) return const SizedBox.shrink();
            final pctAhorro = (tasa * 100).round();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                tasa >= 0
                    ? 'Ahorraste el $pctAhorro% de tus ingresos este mes.'
                    : 'Gastaste ${pctAhorro.abs()}% más de lo que ingresó este mes.',
                style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: tasa >= 0 ? colors.textSecondary : _kGastos,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HeroDato extends StatelessWidget {
  final IconData icono;
  final String label;
  final double monto;
  final Color color;
  final AppThemeColors colors;
  final ({bool subio, int pct})? badge;

  const _HeroDato({
    required this.icono,
    required this.label,
    required this.monto,
    required this.color,
    required this.colors,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: AppIconSize.small, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                formatCOP(monto),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppTextSize.body,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Icon(
                badge!.subio ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: badge!.subio ? _kGastos : colors.textSecondary,
              ),
              Text(
                '${badge!.pct}%',
                style: TextStyle(
                  fontSize: 10,
                  color: badge!.subio ? _kGastos : colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
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
  // Fase E2: gasto del mismo mes anterior, por categoría exacta (mismo
  // criterio de agrupación que `data`) — null cuando el periodo activo no
  // es "Este mes" (comparar contra un bloque de distinta duración no es
  // inequívoco, ver Fase 06).
  final Map<String, double>? gastoPorCategoriaAnterior;
  // Fase E3: presupuestos del mes en curso, por categoría padre — para
  // ofrecer un acceso directo a Planificación desde la leyenda.
  final Map<String, FinanceBudgetRow> budgetsPorCategoria;
  final VoidCallback? onPresupuestoTap;

  const _PieDonutSection({
    required this.data,
    required this.catMap,
    required this.touchedIndex,
    required this.onTouch,
    required this.totalGastos,
    required this.onCategoriaTap,
    this.gastoPorCategoriaAnterior,
    this.budgetsPorCategoria = const {},
    this.onPresupuestoTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
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
                  // Fondo de la tarjeta del tema (no el color rojo/verde de
                  // la porción) — el color de la categoría queda solo como
                  // borde, el texto sigue el tema (textPrimary).
                  color: colors.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Text(
                  '$label\n${formatCOP(item.monto)}',
                  style: TextStyle(
                    color: colors.textPrimary,
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
                montoAnterior: gastoPorCategoriaAnterior?[data[i].catId],
                budget: () {
                  if (data[i].catId == '__otros__') return null;
                  final cat = catMap[data[i].catId];
                  final padreId = cat?.parentId ?? data[i].catId;
                  return budgetsPorCategoria[padreId];
                }(),
                onPresupuestoTap: onPresupuestoTap,
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
  // Fase E2: gasto de esta misma categoría el mes anterior — null si no
  // aplica (periodo distinto a "Este mes") o sin comparación válida.
  final double? montoAnterior;
  // Fase E3: si esta categoría (resuelta a su padre) ya tiene presupuesto
  // este mes, se ofrece un segundo acceso directo a Planificación.
  final FinanceBudgetRow? budget;
  final VoidCallback? onPresupuestoTap;

  const _PieLegendItem({
    required this.item,
    required this.cat,
    required this.color,
    required this.totalGastos,
    required this.isOtros,
    this.onTap,
    this.montoAnterior,
    this.budget,
    this.onPresupuestoTap,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = isOtros ? 'Otros' : (cat?.nombre ?? item.catId);
    final pct = totalGastos > 0 ? item.monto / totalGastos * 100 : 0.0;
    final comparacion = montoAnterior != null
        ? comparacionPeriodoAnterior(actual: item.monto, anterior: montoAnterior!)
        : null;
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
        if (comparacion != null) ...[
          const SizedBox(width: 4),
          Icon(
            comparacion.deltaPct > 0 ? Icons.arrow_upward : Icons.arrow_downward,
            size: 10,
            color: comparacion.deltaPct > 0 ? _kGastos : Theme.of(context).extension<AppThemeColors>()!.textSecondary,
          ),
          Text(
            '${comparacion.deltaPct.abs().round()}%',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: comparacion.deltaPct > 0 ? _kGastos : Theme.of(context).extension<AppThemeColors>()!.textSecondary,
            ),
          ),
        ],
        if (budget != null && onPresupuestoTap != null) ...[
          const SizedBox(width: 2),
          InkWell(
            onTap: onPresupuestoTap,
            child: Icon(Icons.pie_chart_outline, size: AppIconSize.micro, color: Theme.of(context).colorScheme.primary),
          ),
        ],
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
  final AppThemeColors colors;

  const _BarTendencia({required this.tendencia, required this.fmt, required this.colors});

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
              // Fondo de la tarjeta del tema (no un color fijo) y texto en
              // textPrimary — ya es blanco en tema oscuro y negro en tema
              // claro, así siempre legible sin depender del color de la serie.
              getTooltipColor: (_) => colors.bgCard,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final t = tendencia[groupIndex];
                final isIng = rodIndex == 0;
                return BarTooltipItem(
                  '${_kMesesCortos[t.month]}\n'
                  '${isIng ? "Ingresos" : "Gastos"}: ${formatCOP(rod.toY)}',
                  TextStyle(
                    color: colors.textPrimary,
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

