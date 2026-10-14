import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_budget.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/utils/monto_input_formatter.dart';

final _presupuestoMesProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Fase 04 — Presupuestos: límites de gasto por categoría padre, con
/// consumo real (incluye subcategorías), estados vacío/cercano/agotado,
/// y CRUD completo (antes la pantalla ni siquiera estaba enrutada y no
/// existía forma de crear, editar o eliminar un presupuesto).
///
/// Sin Scaffold/AppBar propios — vive embebida como una pestaña de
/// FinanzasPlanificacionScreen (junto a Metas), que es quien provee el
/// único AppBar/FAB de esa pantalla. El FAB de esta pestaña se expone
/// aparte como [PresupuestoFab].
class FinanzasPresupuestoScreen extends ConsumerWidget {
  const FinanzasPresupuestoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final fecha = ref.watch(_presupuestoMesProvider);
    final anio = fecha.year;
    final mes = fecha.month;
    final budgetsAsync = ref.watch(financeBudgetsProvider((anio, mes)));
    final txAsync = ref.watch(financeTransactionsProvider(DateFormat('yyyy-MM').format(fecha)));
    final catsAsync = ref.watch(allFinanceCategoriesProvider);

    return _combinarAsync(budgetsAsync, txAsync, catsAsync, (budgets, txRows, cats) {
        final transacciones = txRows.map(FinanceTransaction.fromRow).toList();
        final parentPorCategoria = {for (final c in cats) c.id: c.parentId};
        final catPorId = {for (final c in cats) c.id: c};

        final items = budgets.map((b) {
          final cat = catPorId[b.categoryId] ??
              CatalogoCategoria(
                id: b.categoryId,
                nombre: b.categoryId,
                icono: Icons.label_outline,
                color: tc.textTertiary,
                tipo: 'gasto',
                iconoKey: 'label',
              );
          final gasto = gastoCategoriaPeriodo(
            categoryId: b.categoryId,
            transacciones: transacciones,
            parentPorCategoria: parentPorCategoria,
          );
          final progreso = progresoPresupuesto(gasto: gasto, limite: b.montoLimite);
          final hoy = DateTime.now();
          final inicioPeriodo = DateTime(anio, mes, 1);
          final finPeriodo = DateTime(anio, mes + 1, 1).subtract(const Duration(days: 1));
          return _BudgetItemData(
            rowId: b.rowId,
            categoryId: b.categoryId,
            cat: cat,
            limite: b.montoLimite,
            gasto: gasto,
            progreso: progreso,
            estado: estadoPresupuesto(progreso),
            vaRapido: vaRapido(
              progreso: progreso,
              inicioPeriodo: inicioPeriodo,
              finPeriodo: finPeriodo,
              hoy: hoy,
            ),
          );
        }).toList()
          ..sort((a, b) => b.progreso.compareTo(a.progreso));

        final totalLimite = items.fold(0.0, (s, i) => s + i.limite);
        final totalGasto = items.fold(0.0, (s, i) => s + i.gasto);

        // Categorías gasto padre (fijas + personalizadas) sin presupuesto
        // este mes — las únicas que el selector de "nuevo presupuesto" debe
        // ofrecer (evita presupuestos duplicados para la misma categoría).
        final idsConPresupuesto = items.map((i) => i.categoryId).toSet();
        final padresDisponibles = cats
            .where((c) =>
                c.parentId == null &&
                (c.tipo == 'gasto' || c.tipo == 'ambos') &&
                !idsConPresupuesto.contains(c.id))
            .toList();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(financeBudgetsProvider((anio, mes)));
            ref.invalidate(financeTransactionsProvider(DateFormat('yyyy-MM').format(fecha)));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Mes anterior',
                    onPressed: () => ref.read(_presupuestoMesProvider.notifier).state =
                        DateTime(anio, mes - 1),
                  ),
                  SizedBox(
                    width: 160,
                    child: Text(
                      _tituloMes(fecha),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600, color: tc.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Mes siguiente',
                    onPressed: () => ref.read(_presupuestoMesProvider.notifier).state =
                        DateTime(anio, mes + 1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isNotEmpty) ...[
                _ResumenPresupuesto(limite: totalLimite, gasto: totalGasto, tc: tc),
                const SizedBox(height: AppSpacing.section),
              ],
              if (items.isEmpty)
                _EstadoVacio(tc: tc, hayPadresDisponibles: padresDisponibles.isNotEmpty)
              else
                for (final item in items) ...[
                  _BudgetCard(
                    data: item,
                    tc: tc,
                    onTap: () => _abrirFormulario(
                      context,
                      ref,
                      anio: anio,
                      mes: mes,
                      editando: item,
                      padresDisponibles: padresDisponibles,
                    ),
                    onEliminar: () => _confirmarEliminar(context, ref, item, anio, mes),
                  ),
                  const SizedBox(height: AppSpacing.tile),
                ],
            ],
          ),
        );
      });
  }

  static String _tituloMes(DateTime fecha) {
    final f = DateFormat('MMMM yyyy', 'es').format(fecha);
    return f[0].toUpperCase() + f.substring(1);
  }

  static Future<void> _abrirFormulario(
    BuildContext context,
    WidgetRef ref, {
    required int anio,
    required int mes,
    _BudgetItemData? editando,
    required List<CatalogoCategoria> padresDisponibles,
  }) async {
    final disponiblesParaSheet = editando != null
        ? [editando.cat, ...padresDisponibles]
        : padresDisponibles;
    if (disponiblesParaSheet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya hay un presupuesto para cada categoría de gasto disponible.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PresupuestoFormSheet(
        anio: anio,
        mes: mes,
        categoriasDisponibles: disponiblesParaSheet,
        categoriaInicial: editando?.cat,
        montoInicial: editando?.limite,
      ),
    );
  }

  static Future<void> _confirmarEliminar(
    BuildContext context,
    WidgetRef ref,
    _BudgetItemData item,
    int anio,
    int mes,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar presupuesto'),
        content: Text('¿Eliminar el presupuesto de "${item.cat.nombre}" para este mes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true) return;
    await ref.read(databaseProvider).deleteFinanceBudget(item.rowId);
    ref.invalidate(financeBudgetsProvider((anio, mes)));
  }
}

/// Combina tres AsyncValue en un único body — evita el anidamiento de 3
/// `.when` que tenía la versión anterior y deja loading/error consistentes.
Widget _combinarAsync<A, B, C>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  AsyncValue<C> c,
  Widget Function(A, B, C) builder,
) {
  if (a.hasError) return Center(child: Text('Error: ${a.error}'));
  if (b.hasError) return Center(child: Text('Error: ${b.error}'));
  if (c.hasError) return Center(child: Text('Error: ${c.error}'));
  if (!a.hasValue || !b.hasValue || !c.hasValue) {
    return const Center(child: CircularProgressIndicator());
  }
  return builder(a.value as A, b.value as B, c.value as C);
}

class _BudgetItemData {
  final int rowId;
  final String categoryId;
  final CatalogoCategoria cat;
  final double limite;
  final double gasto;
  final double progreso;
  final EstadoPresupuesto estado;
  final bool vaRapido;

  _BudgetItemData({
    required this.rowId,
    required this.categoryId,
    required this.cat,
    required this.limite,
    required this.gasto,
    required this.progreso,
    required this.estado,
    required this.vaRapido,
  });
}

class _ResumenPresupuesto extends StatelessWidget {
  final double limite, gasto;
  final AppThemeColors tc;
  const _ResumenPresupuesto({required this.limite, required this.gasto, required this.tc});

  @override
  Widget build(BuildContext context) {
    final disponible = saldoPresupuesto(limite: limite, gasto: gasto);
    final pct = limite > 0 ? ((gasto / limite) * 100).clamp(0, 999).round() : 0;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.card),
      decoration: BoxDecoration(
        color: tc.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tc.borderCard.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ResumenCifra(label: 'Asignado', valor: formatCOP(limite), tc: tc),
              _ResumenCifra(label: 'Gastado', valor: formatCOP(gasto), tc: tc),
              _ResumenCifra(
                label: 'Disponible',
                valor: formatCOP(disponible),
                tc: tc,
                color: disponible < 0 ? Colors.red : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.tile),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: LinearProgressIndicator(
              value: limite > 0 ? (gasto / limite).clamp(0.0, 1.0) : 0,
              minHeight: 8,
              backgroundColor: tc.borderCard.withValues(alpha: 0.4),
              color: pct >= 100 ? Colors.red : (pct >= 80 ? Colors.amber : Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text('$pct% utilizado en total', style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary)),
        ],
      ),
    );
  }
}

class _ResumenCifra extends StatelessWidget {
  final String label, valor;
  final AppThemeColors tc;
  final Color? color;
  const _ResumenCifra({required this.label, required this.valor, required this.tc, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary)),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w700, color: color ?? tc.textPrimary),
        ),
      ],
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final AppThemeColors tc;
  final bool hayPadresDisponibles;
  const _EstadoVacio({required this.tc, required this.hayPadresDisponibles});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.savings_outlined, size: AppIconSize.large, color: tc.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Sin presupuestos este mes',
            style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              hayPadresDisponibles
                  ? 'Crea un límite de gasto por categoría para ver cuánto llevas consumido.'
                  : 'Ya tienes un presupuesto en cada categoría de gasto disponible.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTextSize.body, color: tc.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final _BudgetItemData data;
  final AppThemeColors tc;
  final VoidCallback onTap;
  final VoidCallback onEliminar;

  const _BudgetCard({required this.data, required this.tc, required this.onTap, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final cat = data.cat;
    final estadoColor = switch (data.estado) {
      EstadoPresupuesto.agotado => Colors.red,
      EstadoPresupuesto.cercano => Colors.amber.shade800,
      EstadoPresupuesto.normal => cat.color,
    };
    return Container(
      decoration: BoxDecoration(
        color: tc.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tc.borderCard.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: cat.color),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(cat.icono, color: cat.color, size: AppIconSize.medium),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              cat.nombre,
                              style: TextStyle(
                                fontSize: AppTextSize.body,
                                fontWeight: FontWeight.w700,
                                color: tc.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (data.estado != EstadoPresupuesto.normal)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: estadoColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.chip),
                              ),
                              child: Text(
                                data.estado == EstadoPresupuesto.agotado ? 'Agotado' : 'Cerca del límite',
                                style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: estadoColor),
                              ),
                            ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: AppIconSize.small, color: tc.textTertiary),
                            tooltip: 'Eliminar presupuesto',
                            onPressed: onEliminar,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        child: LinearProgressIndicator(
                          value: data.progreso.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: cat.color.withValues(alpha: 0.12),
                          color: estadoColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${formatCOP(data.gasto)} de ${formatCOP(data.limite)}',
                            style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary),
                          ),
                          Text(
                            data.progreso > 1
                                ? '${(data.progreso * 100).round()}%'
                                : 'Disponible: ${formatCOP(saldoPresupuesto(limite: data.limite, gasto: data.gasto))}',
                            style: TextStyle(
                              fontSize: AppTextSize.caption,
                              fontWeight: FontWeight.w600,
                              color: data.progreso > 1 ? Colors.red : tc.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (data.vaRapido) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Vas más rápido de lo esperado para este punto del mes',
                          style: TextStyle(fontSize: AppTextSize.caption, color: Colors.amber.shade800),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet de creación/edición — bg = scaffoldBackgroundColor (sheet completo,
/// no tarjeta/overlay) según la regla de diseño estandarizado del proyecto.
///
/// Flujo guiado de 4 pasos (Planificación v2): 1) elegir categoría,
/// 2) revisar sugerencia (mediana de los últimos 3 meses, solo si hay
/// datos suficientes), 3) ajustar el límite con vista previa en vivo del
/// gasto ya acumulado, 4) confirmar. Al editar, la categoría es la
/// identidad del presupuesto y no es editable — el flujo arranca directo
/// en el paso de ajustar el límite.
class _PresupuestoFormSheet extends ConsumerStatefulWidget {
  final int anio, mes;
  final List<CatalogoCategoria> categoriasDisponibles;
  final CatalogoCategoria? categoriaInicial;
  final double? montoInicial;

  const _PresupuestoFormSheet({
    required this.anio,
    required this.mes,
    required this.categoriasDisponibles,
    this.categoriaInicial,
    this.montoInicial,
  });

  @override
  ConsumerState<_PresupuestoFormSheet> createState() => _PresupuestoFormSheetState();
}

class _PresupuestoFormSheetState extends ConsumerState<_PresupuestoFormSheet> {
  late CatalogoCategoria? _categoria = widget.categoriaInicial;
  late final _montoCtrl = TextEditingController(
    text: widget.montoInicial != null ? agruparMiles(widget.montoInicial!.round()) : '',
  );
  bool _guardando = false;
  bool _sugerenciaAplicada = false;
  late int _paso = _editando ? 2 : 0;

  bool get _editando => widget.categoriaInicial != null;

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  double? get _montoValido {
    final digitos = _montoCtrl.text.replaceAll('.', '');
    if (digitos.isEmpty) return null;
    final v = double.tryParse(digitos);
    return (v != null && v > 0) ? v : null;
  }

  Future<void> _guardar() async {
    final categoria = _categoria;
    final monto = _montoValido;
    if (categoria == null || monto == null) return;
    setState(() => _guardando = true);
    await ref.read(databaseProvider).upsertFinanceBudget(FinanceBudgetsCompanion.insert(
          categoryId: categoria.id,
          anio: widget.anio,
          mes: widget.mes,
          montoLimite: monto,
        ));
    ref.invalidate(financeBudgetsProvider((widget.anio, widget.mes)));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editando ? 'Editar presupuesto' : 'Nuevo presupuesto',
                style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                _editando ? 'Ajustar límite' : _tituloPaso(_paso),
                style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary),
              ),
              const SizedBox(height: AppSpacing.section),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _contenidoPaso(tc),
              ),
              const SizedBox(height: AppSpacing.section),
              _botonesPaso(tc),
            ],
          ),
        ),
      ),
    );
  }

  String _tituloPaso(int paso) => switch (paso) {
        0 => 'Paso 1 de 4 · Elegir categoría',
        1 => 'Paso 2 de 4 · Revisar sugerencia',
        2 => 'Paso 3 de 4 · Ajustar el límite',
        _ => 'Paso 4 de 4 · Confirmar',
      };

  Widget _contenidoPaso(AppThemeColors tc) {
    switch (_paso) {
      case 0:
        return _PasoCategoria(
          key: const ValueKey('paso0'),
          categorias: widget.categoriasDisponibles,
          seleccionada: _categoria,
          onSeleccionar: (c) => setState(() {
            _categoria = c;
            _paso = 1;
          }),
        );
      case 1:
        return _PasoSugerencia(
          key: const ValueKey('paso1'),
          categoria: _categoria!,
          anio: widget.anio,
          mes: widget.mes,
          onUsarSugerencia: (monto) => setState(() {
            _montoCtrl.text = agruparMiles(monto.round());
            _sugerenciaAplicada = true;
          }),
        );
      case 2:
        return _PasoLimite(
          key: const ValueKey('paso2'),
          categoria: _categoria,
          montoCtrl: _montoCtrl,
          anio: widget.anio,
          mes: widget.mes,
          autofocus: !_sugerenciaAplicada,
          onChanged: () => setState(() {}),
        );
      default:
        return _PasoConfirmar(
          key: const ValueKey('paso3'),
          categoria: _categoria!,
          monto: _montoValido,
          anio: widget.anio,
          mes: widget.mes,
        );
    }
  }

  Widget _botonesPaso(AppThemeColors tc) {
    final esPrimerPaso = _paso == (_editando ? 2 : 0);
    final puedeAvanzar = switch (_paso) {
      0 => false, // paso 0 avanza al tocar una categoría, no con botón
      2 => _montoValido != null,
      _ => true,
    };
    return Row(
      children: [
        if (!esPrimerPaso)
          TextButton(
            onPressed: _guardando ? null : () => setState(() => _paso--),
            child: const Text('Atrás'),
          ),
        const Spacer(),
        if (_paso < 3 && _paso != 0)
          FilledButton(
            onPressed: puedeAvanzar ? () => setState(() => _paso++) : null,
            child: const Text('Siguiente'),
          )
        else if (_paso == 3)
          SizedBox(
            width: 180,
            height: 50,
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_editando ? 'Guardar cambios' : 'Crear presupuesto'),
            ),
          ),
      ],
    );
  }
}

/// Paso 1: elegir categoría (lista inline, no un sub-sheet aparte).
class _PasoCategoria extends StatelessWidget {
  final List<CatalogoCategoria> categorias;
  final CatalogoCategoria? seleccionada;
  final ValueChanged<CatalogoCategoria> onSeleccionar;

  const _PasoCategoria({super.key, required this.categorias, required this.seleccionada, required this.onSeleccionar});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: ListView.builder(
        itemCount: categorias.length,
        itemBuilder: (ctx, i) {
          final c = categorias[i];
          return ListTile(
            leading: Icon(c.icono, color: c.color),
            title: Text(c.nombre),
            trailing: c.id == seleccionada?.id ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
            onTap: () => onSeleccionar(c),
          );
        },
      ),
    );
  }
}

/// Paso 2: sugerencia basada en la mediana de los últimos 3 meses — solo
/// se muestra si sugerenciaPresupuesto encontró datos suficientes (≥2 de
/// esos 3 meses con gasto registrado); si no, el paso simplemente informa
/// que no hay base suficiente, sin fabricar un número.
class _PasoSugerencia extends ConsumerWidget {
  final CatalogoCategoria categoria;
  final int anio, mes;
  final ValueChanged<double> onUsarSugerencia;

  const _PasoSugerencia({
    super.key,
    required this.categoria,
    required this.anio,
    required this.mes,
    required this.onUsarSugerencia,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final txsAsync = ref.watch(financeTransactionsProvider(null));
    final catsAsync = ref.watch(allFinanceCategoriesProvider);

    return txsAsync.when(
      loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => SizedBox(height: 120, child: Center(child: Text('Error: $e'))),
      data: (txRows) {
        final cats = catsAsync.valueOrNull ?? const [];
        final parentPorCategoria = {for (final c in cats) c.id: c.parentId};
        final transacciones = txRows.map(FinanceTransaction.fromRow).toList();
        final hoy = DateTime(anio, mes);
        final sugerencia = sugerenciaPresupuesto(
          categoryId: categoria.id,
          transacciones: transacciones,
          parentPorCategoria: parentPorCategoria,
          hoy: hoy,
        );
        if (sugerencia == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Todavía no hay suficiente historial de gasto en "${categoria.nombre}" '
              'para sugerir un límite. Puedes escribirlo tú en el siguiente paso.',
              style: TextStyle(color: tc.textSecondary),
            ),
          );
        }
        const nombresMes = [
          '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
        ];
        final desglose = sugerencia.meses
            .map((m) => '${nombresMes[m.month]} ${formatCOP(m.monto)}')
            .join(', ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sugerencia para ${categoria.nombre}', style: TextStyle(color: tc.textSecondary)),
            const SizedBox(height: 4),
            Text(
              formatCOP(sugerencia.sugerido),
              style: TextStyle(fontSize: AppTextSize.emphasis, fontWeight: FontWeight.w700, color: tc.textPrimary),
            ),
            const SizedBox(height: 8),
            Text('Basado en tus últimos 3 meses: $desglose.', style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary)),
            const SizedBox(height: AppSpacing.tile),
            OutlinedButton(
              onPressed: () => onUsarSugerencia(sugerencia.sugerido),
              child: const Text('Usar esta sugerencia'),
            ),
          ],
        );
      },
    );
  }
}

/// Paso 3: ajustar el límite, con vista previa en vivo de lo ya gastado y
/// lo que quedaría disponible con el valor actual del campo.
class _PasoLimite extends ConsumerWidget {
  final CatalogoCategoria? categoria;
  final TextEditingController montoCtrl;
  final int anio, mes;
  final bool autofocus;
  final VoidCallback onChanged;

  const _PasoLimite({
    super.key,
    required this.categoria,
    required this.montoCtrl,
    required this.anio,
    required this.mes,
    required this.autofocus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final mesStr = '$anio-${mes.toString().padLeft(2, '0')}';
    final txsAsync = ref.watch(financeTransactionsProvider(mesStr));
    final catsAsync = ref.watch(allFinanceCategoriesProvider);
    final cat = categoria;

    double gastoAcumulado = 0;
    if (cat != null && txsAsync.hasValue && catsAsync.hasValue) {
      final parentPorCategoria = {for (final c in catsAsync.value!) c.id: c.parentId};
      final transacciones = txsAsync.value!.map(FinanceTransaction.fromRow).toList();
      gastoAcumulado = gastoCategoriaPeriodo(
        categoryId: cat.id,
        transacciones: transacciones,
        parentPorCategoria: parentPorCategoria,
      );
    }
    final digitos = montoCtrl.text.replaceAll('.', '');
    final montoActual = double.tryParse(digitos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LÍMITE MENSUAL', style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: tc.textTertiary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: montoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [MontoInputFormatter()],
          autofocus: autofocus,
          onChanged: (_) => onChanged(),
          style: TextStyle(fontSize: AppTextSize.emphasis, fontWeight: FontWeight.w700, color: tc.textPrimary),
          decoration: const InputDecoration(prefixText: '\$ ', hintText: 'Ej. 500.000'),
        ),
        if (gastoAcumulado > 0) ...[
          const SizedBox(height: AppSpacing.tile),
          Text('Ya gastado este mes: ${formatCOP(gastoAcumulado)}', style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary)),
          if (montoActual != null)
            Text(
              'Con este límite quedarían: ${formatCOP(montoActual - gastoAcumulado)}',
              style: TextStyle(
                fontSize: AppTextSize.caption,
                fontWeight: FontWeight.w600,
                color: (montoActual - gastoAcumulado) < 0 ? Colors.red : tc.textSecondary,
              ),
            ),
        ],
      ],
    );
  }
}

/// Paso 4: resumen final antes de guardar.
class _PasoConfirmar extends StatelessWidget {
  final CatalogoCategoria categoria;
  final double? monto;
  final int anio, mes;

  const _PasoConfirmar({super.key, required this.categoria, required this.monto, required this.anio, required this.mes});

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    const nombresMes = [
      '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(categoria.icono, color: categoria.color, size: AppIconSize.medium),
          const SizedBox(width: 10),
          Text(categoria.nombre, style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w700, color: tc.textPrimary)),
        ]),
        const SizedBox(height: 8),
        Text('Periodo: ${nombresMes[mes]} $anio', style: TextStyle(color: tc.textSecondary)),
        const SizedBox(height: 4),
        Text(
          'Límite: ${monto != null ? formatCOP(monto!) : '—'}',
          style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
        ),
      ],
    );
  }
}

/// FAB de la pestaña Presupuestos — vive aparte porque FinanzasPresupuestoScreen
/// ya no tiene Scaffold propio (ver comentario de clase); observa los mismos
/// providers (cacheados por riverpod, no duplica trabajo real).
class PresupuestoFab extends ConsumerWidget {
  const PresupuestoFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fecha = ref.watch(_presupuestoMesProvider);
    final anio = fecha.year;
    final mes = fecha.month;
    final catsAsync = ref.watch(allFinanceCategoriesProvider);
    final budgetsAsync = ref.watch(financeBudgetsProvider((anio, mes)));

    return catsAsync.maybeWhen(
      data: (cats) => FloatingActionButton.extended(
        onPressed: () => budgetsAsync.whenData((budgets) {
          final idsConPresupuesto = budgets.map((b) => b.categoryId).toSet();
          final padresDisponibles = cats
              .where((c) =>
                  c.parentId == null &&
                  (c.tipo == 'gasto' || c.tipo == 'ambos') &&
                  !idsConPresupuesto.contains(c.id))
              .toList();
          FinanzasPresupuestoScreen._abrirFormulario(
            context, ref, anio: anio, mes: mes, padresDisponibles: padresDisponibles,
          );
        }),
        icon: const Icon(Icons.add),
        label: const Text('Presupuesto'),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
