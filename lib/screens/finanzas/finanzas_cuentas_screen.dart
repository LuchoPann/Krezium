import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/providers/theme_provider.dart';
import 'package:krezium/screens/finanzas/finanzas_libro_transacciones_screen.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/widgets/color_picker_field.dart';
import 'package:krezium/widgets/krezium_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─── Color helper ─────────────────────────────────────────────────────────────
Color _colorFromHex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

String _fmt(double v) =>
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

// ─── Saludo por hora del día ──────────────────────────────────────────────────
final _greeting = () {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Buenos días';
  if (hour >= 12 && hour < 18) return 'Buenas tardes';
  return 'Buenas noches';
}();

// ─── Public screen ────────────────────────────────────────────────────────────
class FinanzasCuentasScreen extends ConsumerStatefulWidget {
  const FinanzasCuentasScreen({super.key});

  @override
  ConsumerState<FinanzasCuentasScreen> createState() =>
      _FinanzasCuentasScreenState();
}

class _FinanzasCuentasScreenState extends ConsumerState<FinanzasCuentasScreen> {
  bool _autoPushDone = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    ref.listenManual<AsyncValue<List<FinanceAccountRow>>>(
      financeAccountsProvider,
      (prev, next) {
        if (next.hasValue && !_autoPushDone) {
          _checkAndAutoPush(next.value!);
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndAutoPush(List<FinanceAccountRow> rows) async {
    if (_autoPushDone) return;
    final prefs = await SharedPreferences.getInstance();
    final defaultId = prefs.getString('finanzas_libro_default');
    if (defaultId == null || !mounted) return;
    final match = rows.where((r) => r.id == defaultId).toList();
    if (match.isEmpty || !mounted) return;
    _autoPushDone = true;
    final libro = FinanceAccount.fromRow(match.first);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanzasLibroTransaccionesScreen(libro: libro),
      ),
    );
  }

  void _mostrarNuevoRegistroSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => _NuevoRegistroSheet(
        onCreado: () => ref.invalidate(financeAccountsProvider),
      ),
    );
  }

  void _mostrarEditarRegistroSheet(FinanceAccount libro) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => _NuevoRegistroSheet(
        editar: libro,
        onCreado: () => ref.invalidate(financeAccountsProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncLibros = ref.watch(financeAccountsProvider);
    final prefs = ref.watch(themePreferencesProvider);
    final accentColor = resolveEffectiveAccent(prefs.accentColor, prefs.isDarkMode);

    return Scaffold(
      body: asyncLibros.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return _EmptyState(
              accentColor: accentColor,
              onCrear: _mostrarNuevoRegistroSheet,
            );
          }
          final libros = rows.map(FinanceAccount.fromRow).toList();
          final filtered = _query.isEmpty
              ? libros
              : libros.where((l) => l.nombre.toLowerCase().contains(_query)).toList();
          return CustomScrollView(
            slivers: [
              _GlobalHeader(
                libros: libros,
                accentColor: accentColor,
              ),
              if (libros.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _SearchField(controller: _searchCtrl, query: _query),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: filtered.isEmpty
                    ? SliverToBoxAdapter(
                        child: _NoResultsState(query: _query),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final libro = filtered[index];
                            return _LibroCard(
                              libro: libro,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FinanzasLibroTransaccionesScreen(libro: libro),
                                ),
                              ),
                              onFavorito: () => _marcarFavorito(libro),
                              onEditar: () => _mostrarEditarRegistroSheet(libro),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: asyncLibros.hasValue && asyncLibros.value!.isNotEmpty
          ? Builder(builder: (context) {
              final accentColor = Theme.of(context).colorScheme.primary;
              return FloatingActionButton.extended(
                backgroundColor: accentColor,
                foregroundColor: legibleForegroundOn(accentColor),
                onPressed: _mostrarNuevoRegistroSheet,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nuevo registro'),
              );
            })
          : null,
    );
  }

  Future<void> _marcarFavorito(FinanceAccount libro) async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('finanzas_libro_default', libro.id);
    final db = ref.read(databaseProvider);
    await db.clearFinanceAccountFavoritos();
    if (!mounted) return;
    await db.upsertFinanceAccount(
      FinanceAccountsCompanion(
        id: Value(libro.id),
        nombre: Value(libro.nombre),
        tipo: Value(libro.tipo),
        icono: Value(libro.icono),
        color: Value(libro.color),
        saldoInicial: Value(libro.saldoInicial),
        activa: Value(libro.activa),
        orden: Value(libro.orden),
        esFavorito: const Value(true),
      ),
    );
    ref.invalidate(financeAccountsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro predeterminado actualizado')),
      );
    }
  }
}

// ─── Header global con balance total ─────────────────────────────────────────
class _GlobalHeader extends ConsumerWidget {
  final List<FinanceAccount> libros;
  final Color accentColor;

  const _GlobalHeader({
    required this.libros,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double totalIngresos = 0;
    double totalGastos = 0;
    double totalInicial = 0;
    bool loading = false;

    for (final libro in libros) {
      totalInicial += libro.saldoInicial;
      final summary = ref.watch(financeAccountSummaryProvider(libro.id));
      summary.when(
        data: (s) {
          totalIngresos += s.ingresos;
          totalGastos += s.gastos;
        },
        loading: () => loading = true,
        error: (e, st) {},
      );
    }

    final balance = totalInicial + totalIngresos - totalGastos;
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final topPad = MediaQuery.of(context).padding.top;

    final profileName = ref.watch(
      themePreferencesProvider.select((p) => p.profileName),
    );
    final avatarPath = ref.watch(
      themePreferencesProvider.select((p) => p.avatarPath),
    );

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.card, topPad + AppSpacing.card, AppSpacing.card, AppSpacing.tile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Saludo (mismo patrón que el dashboard) ──────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accentColor.withValues(alpha: 0.18),
                  backgroundImage: avatarPath != null ? FileImage(File(avatarPath)) : null,
                  child: avatarPath == null
                      ? Text(
                          profileName.isNotEmpty ? profileName[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: AppTextSize.heading,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_greeting, $profileName',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tu salud financiera',
                        style: TextStyle(
                          fontSize: AppTextSize.body,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const AppLogo(height: 26),
              ],
            ),
            const SizedBox(height: 28),
            // ── Balance: misma tipografía desnuda que "DEUDA TOTAL" en el
            // dashboard de Créditos — sin card/borde propio, la jerarquía
            // viene del contraste de tamaño, no de una caja.
            Text(
              'BALANCE TOTAL',
              style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            loading
                ? SizedBox(
                    height: AppTextSize.hero,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          color: accentColor, strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                : Text(
                    formatCOP(balance),
                    style: const TextStyle(
                      fontSize: AppTextSize.hero,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
            const SizedBox(height: 22),
            // ── Fila de stats secundarios (Ingresos | Gastos) + contador de
            // registros debajo — mismo patrón que "Por pagar · Créditos
            // activos" del dashboard.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SecondaryStat(
                    label: 'Ingresos',
                    value: formatCOP(totalIngresos),
                    valueColor: colors.textPrimary,
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: colors.borderCard,
                ),
                Expanded(
                  child: _SecondaryStat(
                    label: 'Gastos',
                    value: formatCOP(totalGastos),
                    valueColor: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.section),
            Text(
              '${libros.length} ${libros.length == 1 ? 'registro' : 'registros'}',
              style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mismo patrón que `_SecondaryStat` del dashboard de Créditos: valor arriba
/// (tipografía, sin ícono ni caja propia) y etiqueta en mayúsculas debajo.
/// [valueColor] queda neutro para Ingresos/Gastos — el verde/rojo se
/// reservó solo para el balance y los montos individuales, no para cada
/// cifra agregada (el usuario reportó que tanto color en el resumen
/// saturaba la vista).
class _SecondaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SecondaryStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AppTextSize.heading,
            letterSpacing: -0.3,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: kredit.textTertiary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Buscador (mismo lenguaje visual que CreditsListScreen) ──────────────────
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;

  const _SearchField({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Buscar registro...',
        hintStyle: TextStyle(fontSize: AppTextSize.body, color: kredit.textTertiary),
        prefixIcon: Icon(Icons.search, size: AppIconSize.small, color: kredit.textSecondary),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: AppIconSize.small),
                onPressed: controller.clear,
              )
            : null,
        filled: true,
        fillColor: kredit.bgCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: kredit.borderCard.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: kredit.borderCard.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final String query;
  const _NoResultsState({required this.query});

  @override
  Widget build(BuildContext context) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: AppIconSize.large, color: kredit.textTertiary),
            const SizedBox(height: 12),
            Text(
              'Sin resultados para "$query"',
              style: TextStyle(fontSize: AppTextSize.body, color: kredit.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onCrear;

  const _EmptyState({required this.accentColor, required this.onCrear});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 40,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Empieza a registrar',
                style: TextStyle(
                  fontSize: AppTextSize.heading,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea tu primer registro para llevar el control de tus ingresos y gastos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onCrear,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crear registro'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Libro card con patrón único ──────────────────────────────────────────────
class _LibroCard extends ConsumerWidget {
  final FinanceAccount libro;
  final VoidCallback onTap;
  final VoidCallback onFavorito;
  final VoidCallback onEditar;

  const _LibroCard({
    required this.libro,
    required this.onTap,
    required this.onFavorito,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libroColor = _colorFromHex(libro.color);
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final balanceAsync = ref.watch(financeAccountBalanceProvider(libro.id));

    return Dismissible(
      key: ValueKey(libro.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.card),
        decoration: BoxDecoration(
          color: libroColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(Icons.star_rounded, color: libroColor),
            const SizedBox(width: 8),
            Text(
              'Predeterminado',
              style: TextStyle(
                color: libroColor,
                fontWeight: FontWeight.w600,
                fontSize: AppTextSize.body,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        onFavorito();
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.tile),
        decoration: BoxDecoration(
          color: colors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.borderCard.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        // IntrinsicHeight: la franja de color de 4px necesita una altura
        // acotada para poder estirarse (ver bug en movements_tab.dart con
        // el mismo patrón — Row+stretch sin esto fuerza altura infinita).
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: libroColor),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Nombre + chip "Principal" + flecha ────────────
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                libro.nombre,
                                style: TextStyle(
                                  fontSize: AppTextSize.body,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (libro.esFavorito) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: libroColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppRadius.chip),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded, color: libroColor, size: AppIconSize.micro),
                                    const SizedBox(width: 3),
                                    Text(
                                      'PRINCIPAL',
                                      style: TextStyle(
                                        fontSize: AppTextSize.caption,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: libroColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: onEditar,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.edit_outlined, size: AppIconSize.small, color: colors.textTertiary),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: AppIconSize.small, color: colors.textTertiary),
                          ],
                        ),
                        if (libro.descripcion.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            libro.descripcion,
                            style: TextStyle(fontSize: AppTextSize.caption, color: colors.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        // ── Balance: protagonista, grande y contundente —
                        // lo primero que se lee al escanear la tarjeta.
                        balanceAsync.when(
                          loading: () => SizedBox(
                            height: AppTextSize.emphasis,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: libroColor),
                              ),
                            ),
                          ),
                          error: (e, st) => const SizedBox(height: AppTextSize.emphasis),
                          data: (b) {
                            final balance = b.saldo;
                            final positivo = balance >= 0;
                            final balanceColor = positivo
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444);
                            return Text(
                              '${positivo ? '' : '-'}${formatCOP(balance.abs())}',
                              style: TextStyle(
                                fontSize: AppTextSize.emphasis,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                color: balanceColor,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Divider(height: 1, color: colors.borderCard),
                        const SizedBox(height: 10),
                        // Ingresos/Gastos en texto neutro — el balance de
                        // arriba ya es el único color de la tarjeta; una
                        // barra y cifras verdes/rojas acá encima saturaban.
                        balanceAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, st) => const SizedBox.shrink(),
                          data: (b) => Row(
                            children: [
                              _StatColumn(
                                label: 'Ingresos',
                                value: formatCOP(b.ingresos),
                                valueColor: colors.textPrimary,
                                colors: colors,
                              ),
                              const SizedBox(width: AppSpacing.section),
                              _StatColumn(
                                label: 'Gastos',
                                value: formatCOP(b.gastos),
                                valueColor: colors.textPrimary,
                                colors: colors,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final AppThemeColors colors;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextSize.caption,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ─── Sheet crear registro ─────────────────────────────────────────────────────
class _NuevoRegistroSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreado;
  // Si no es null, el sheet edita este registro en vez de crear uno nuevo
  // — mismo formulario, los campos arrancan prellenados con sus valores.
  final FinanceAccount? editar;
  const _NuevoRegistroSheet({required this.onCreado, this.editar});

  @override
  ConsumerState<_NuevoRegistroSheet> createState() => _NuevoRegistroSheetState();
}

class _NuevoRegistroSheetState extends ConsumerState<_NuevoRegistroSheet> {
  late final _nombreController =
      TextEditingController(text: widget.editar?.nombre ?? '');
  late final _saldoController = TextEditingController(
      text: widget.editar != null ? _fmt(widget.editar!.saldoInicial) : '');
  late final _descripcionController =
      TextEditingController(text: widget.editar?.descripcion ?? '');
  late Color _color = widget.editar != null
      ? _colorFromHex(widget.editar!.color)
      : const Color(0xFFEF4444);
  bool _guardando = false;

  bool get _esEdicion => widget.editar != null;

  @override
  void dispose() {
    _nombreController.dispose();
    _saldoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _guardando = true);
    final db = ref.read(databaseProvider);
    final id = widget.editar?.id ?? const Uuid().v4();
    final inicial = double.tryParse(_saldoController.text.replaceAll(',', '.')) ?? 0.0;
    final descripcion = _descripcionController.text.trim();
    await db.upsertFinanceAccount(FinanceAccountsCompanion(
      id: Value(id),
      nombre: Value(nombre),
      tipo: Value(widget.editar?.tipo ?? 'registro'),
      icono: Value(widget.editar?.icono ?? nombre),
      color: Value('#${colorToHex(_color)}'),
      saldoInicial: Value(inicial),
      activa: Value(widget.editar?.activa ?? true),
      orden: Value(widget.editar?.orden ?? '0'),
      esFavorito: Value(widget.editar?.esFavorito ?? false),
      descripcion: Value(descripcion),
    ));
    widget.onCreado();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kredit = theme.extension<AppThemeColors>()!;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: kredit.borderCard,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(_esEdicion ? 'Editar registro' : 'Nuevo registro',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _nombreController,
            autofocus: !_esEdicion,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre del registro',
              hintText: 'Ej: Gastos personales',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descripcionController,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              hintText: 'Para qué usas este registro',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _saldoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Saldo inicial (opcional)',
              hintText: '0',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 16),
          Text('Color', style: TextStyle(fontSize: AppTextSize.caption, color: kredit.textSecondary)),
          const SizedBox(height: 8),
          ColorPickerField(
            color: _color,
            onColorChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : Text(_esEdicion ? 'Guardar cambios' : 'Crear registro'),
            ),
          ),
        ],
      ),
    );
  }
}
