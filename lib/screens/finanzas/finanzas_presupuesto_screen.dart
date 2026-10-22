import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_budget.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/screens/account/how_it_works_screen.dart';
import 'package:krezium/screens/finanzas/finanzas_libro_transacciones_screen.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/utils/monto_input_formatter.dart';

final _presupuestoMesProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Fase C1: abre el flujo guiado de crear presupuesto desde fuera de esta
/// pantalla (atajo "Crear presupuesto para {categoría}" en Nueva
/// Transacción), con la categoría padre ya resuelta — salta el paso 0.
Future<void> abrirCrearPresupuestoParaCategoria(
  BuildContext context, {
  required CatalogoCategoria categoriaPadre,
  required int anio,
  required int mes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PresupuestoFormSheet(
      anio: anio,
      mes: mes,
      categoriasDisponibles: [categoriaPadre],
      categoriaPreseleccionada: categoriaPadre,
    ),
  );
}

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
            autoRepetir: b.autoRepetir,
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
        autoRepetirInicial: editando?.autoRepetir ?? false,
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
  final bool autoRepetir;

  _BudgetItemData({
    required this.rowId,
    required this.categoryId,
    required this.cat,
    required this.limite,
    required this.gasto,
    required this.progreso,
    required this.estado,
    required this.vaRapido,
    required this.autoRepetir,
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
                  ? 'Crea uno con el botón "+" para limitar cuánto planeas gastar en una categoría este mes.'
                  : 'Ya tienes un presupuesto en cada categoría de gasto disponible.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTextSize.body, color: tc.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HowItWorksScreen()),
            ),
            icon: const Icon(Icons.help_outline, size: AppIconSize.small),
            label: const Text('¿Cómo funcionan los presupuestos?'),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  final _BudgetItemData data;
  final AppThemeColors tc;
  final VoidCallback onTap;
  final VoidCallback onEliminar;

  const _BudgetCard({required this.data, required this.tc, required this.onTap, required this.onEliminar});

  /// Fase C2: drill-down a los movimientos de esta categoría. Un
  /// presupuesto es global (no por registro), así que si hay más de un
  /// registro se pregunta primero; con uno solo va directo — sin
  /// selector de por medio cuando no hace falta elegir nada.
  Future<void> _verMovimientos(BuildContext context, WidgetRef ref) async {
    final rows = ref.read(financeAccountsProvider).valueOrNull ?? [];
    final libros = rows.map(FinanceAccount.fromRow).toList();
    if (libros.isEmpty) return;

    FinanceAccount? libro;
    if (libros.length == 1) {
      libro = libros.first;
    } else {
      libro = await showModalBottomSheet<FinanceAccount>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Material(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('¿En qué registro?', style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary)),
                  ),
                ),
                for (final l in libros)
                  ListTile(title: Text(l.nombre), onTap: () => Navigator.of(ctx).pop(l)),
              ],
            ),
          ),
        ),
      );
    }
    if (libro == null || !context.mounted) return;

    ref.read(finanzasFiltrosProvider.notifier).state =
        ref.read(finanzasFiltrosProvider).copyWith(categoriaId: data.categoryId);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FinanzasLibroTransaccionesScreen(libro: libro!)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                            icon: Icon(Icons.receipt_long_outlined, size: AppIconSize.small, color: tc.textTertiary),
                            tooltip: 'Ver movimientos',
                            onPressed: () => _verMovimientos(context, ref),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
  // Fase C1: abrir el flujo desde fuera de esta pantalla (atajo "Crear
  // presupuesto" en Nueva Transacción) con la categoría ya resuelta —
  // a diferencia de categoriaInicial, esto NO activa el modo edición,
  // solo evita mostrar el selector de categoría porque ya se conoce.
  final CatalogoCategoria? categoriaPreseleccionada;
  final bool autoRepetirInicial;

  const _PresupuestoFormSheet({
    required this.anio,
    required this.mes,
    required this.categoriasDisponibles,
    this.categoriaInicial,
    this.montoInicial,
    this.categoriaPreseleccionada,
    this.autoRepetirInicial = false,
  });

  @override
  ConsumerState<_PresupuestoFormSheet> createState() => _PresupuestoFormSheetState();
}

/// Antes era un wizard de 4 pasos (elegir categoría → revisar sugerencia →
/// ajustar límite → confirmar) para crear un solo presupuesto — demasiada
/// fricción para algo conceptualmente simple ("cuánto quiero gastar en X
/// este mes"). Ahora es una sola pantalla: chips de categoría, la
/// sugerencia como un chip tocable (no un paso aparte) y el campo de monto
/// con vista previa en vivo de lo gastado/disponible.
class _PresupuestoFormSheetState extends ConsumerState<_PresupuestoFormSheet> {
  late CatalogoCategoria? _categoria = widget.categoriaInicial ?? widget.categoriaPreseleccionada;
  late final _montoCtrl = TextEditingController(
    text: widget.montoInicial != null ? agruparMiles(widget.montoInicial!.round()) : '',
  );
  bool _guardando = false;
  late bool _autoRepetir = widget.autoRepetirInicial;

  bool get _editando => widget.categoriaInicial != null;
  // Solo se puede volver a elegir categoría si esta pantalla la dejó elegir
  // a mano (ni editando un presupuesto existente ni viniendo con una ya
  // resuelta desde fuera).
  bool get _categoriaEditable => !_editando && widget.categoriaPreseleccionada == null;

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
          autoRepetir: Value(_autoRepetir),
        ));
    ref.invalidate(financeBudgetsProvider((widget.anio, widget.mes)));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final categoria = _categoria;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
                _editando
                    ? 'Este cambio aplica desde este mes — los meses anteriores quedan igual.'
                    : 'Se repite automáticamente cada mes con este mismo límite; solo edítalo cuando cambie.',
                style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary),
              ),
              const SizedBox(height: AppSpacing.section),
              if (categoria == null)
                _CategoriaChips(
                  categorias: widget.categoriasDisponibles,
                  onSeleccionar: (c) => setState(() => _categoria = c),
                )
              else ...[
                Row(
                  children: [
                    Icon(categoria.icono, color: categoria.color, size: AppIconSize.medium),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        categoria.nombre,
                        style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w700, color: tc.textPrimary),
                      ),
                    ),
                    if (_categoriaEditable)
                      TextButton(
                        onPressed: () => setState(() => _categoria = null),
                        child: const Text('Cambiar'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                _SugerenciaChip(
                  categoria: categoria,
                  anio: widget.anio,
                  mes: widget.mes,
                  onAplicar: (monto) => setState(() {
                    _montoCtrl.text = agruparMiles(monto.round());
                  }),
                ),
                const SizedBox(height: AppSpacing.tile),
                _LimiteField(
                  categoria: categoria,
                  montoCtrl: _montoCtrl,
                  anio: widget.anio,
                  mes: widget.mes,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.tile),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _autoRepetir,
                  onChanged: (v) => setState(() => _autoRepetir = v),
                  title: const Text('Repetir automáticamente cada mes'),
                  subtitle: const Text(
                    'Este presupuesto se sumará solo al mes siguiente, sin preguntar.',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.section),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: (categoria != null && _montoValido != null && !_guardando) ? _guardar : null,
                  child: _guardando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_editando ? 'Guardar cambios' : 'Crear presupuesto'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector de categoría como chips tocables (no una lista de 320px ni un
/// paso de wizard aparte) — de un vistazo se ven todas las opciones y un
/// solo toque elige.
class _CategoriaChips extends StatelessWidget {
  final List<CatalogoCategoria> categorias;
  final ValueChanged<CatalogoCategoria> onSeleccionar;

  const _CategoriaChips({required this.categorias, required this.onSeleccionar});

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CATEGORÍA',
          style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: tc.textTertiary),
        ),
        const SizedBox(height: 10),
        // Grid de 2 columnas con altura uniforme en vez de Wrap: con nombres
        // de distinta longitud, los chips quedaban en filas irregulares,
        // difíciles de escanear rápido. Una grilla pareja es más fácil de
        // mirar de un vistazo.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: categorias
              .map((c) => Material(
                    color: tc.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                      onTap: () => onSeleccionar(c),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                          border: Border.all(color: tc.borderCard),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Icon(c.icono, color: c.color, size: AppIconSize.small),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppTextSize.body,
                                  color: tc.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

/// Sugerencia (mediana de los últimos 3 meses) como un chip tocable — antes
/// era un paso completo del wizard con su propio "Siguiente". Si no hay
/// suficiente historial, no se muestra nada (nunca se fabrica un número).
class _SugerenciaChip extends ConsumerWidget {
  final CatalogoCategoria categoria;
  final int anio, mes;
  final ValueChanged<double> onAplicar;

  const _SugerenciaChip({
    required this.categoria,
    required this.anio,
    required this.mes,
    required this.onAplicar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final txsAsync = ref.watch(financeTransactionsProvider(null));
    final catsAsync = ref.watch(allFinanceCategoriesProvider);
    if (!txsAsync.hasValue || !catsAsync.hasValue) return const SizedBox.shrink();

    final parentPorCategoria = {for (final c in catsAsync.value!) c.id: c.parentId};
    final transacciones = txsAsync.value!.map(FinanceTransaction.fromRow).toList();
    final sugerencia = sugerenciaPresupuesto(
      categoryId: categoria.id,
      transacciones: transacciones,
      parentPorCategoria: parentPorCategoria,
      hoy: DateTime(anio, mes),
    );
    if (sugerencia == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ActionChip(
        avatar: Icon(Icons.auto_awesome_outlined, size: AppIconSize.small, color: tc.textSecondary),
        label: Text('Sugerido: ${formatCOP(sugerencia.sugerido)}'),
        onPressed: () => onAplicar(sugerencia.sugerido),
      ),
    );
  }
}

/// Campo de límite con vista previa en vivo de lo ya gastado y lo que
/// quedaría disponible con el valor actual del campo.
class _LimiteField extends ConsumerWidget {
  final CatalogoCategoria categoria;
  final TextEditingController montoCtrl;
  final int anio, mes;
  final VoidCallback onChanged;

  const _LimiteField({
    required this.categoria,
    required this.montoCtrl,
    required this.anio,
    required this.mes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final mesStr = '$anio-${mes.toString().padLeft(2, '0')}';
    final txsAsync = ref.watch(financeTransactionsProvider(mesStr));
    final catsAsync = ref.watch(allFinanceCategoriesProvider);

    double gastoAcumulado = 0;
    if (txsAsync.hasValue && catsAsync.hasValue) {
      final parentPorCategoria = {for (final c in catsAsync.value!) c.id: c.parentId};
      final transacciones = txsAsync.value!.map(FinanceTransaction.fromRow).toList();
      gastoAcumulado = gastoCategoriaPeriodo(
        categoryId: categoria.id,
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
          autofocus: true,
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
