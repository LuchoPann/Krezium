import 'dart:async';
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
import 'package:krezium/screens/finanzas/nueva_transaccion_sheet.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/widgets/krezium_logo.dart';
import 'package:uuid/uuid.dart';

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
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Señala (sin modificar datos de negocio) las transferencias históricas
    // dudosas cada vez que se abre el módulo — idempotente y barato, evita
    // acoplar esta lógica a la migración de schema (Task 7).
    unawaited(aplicarSenalamientoTransferenciasDudosas(ref.read(databaseProvider)));
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

  Future<void> _archivarLibro(FinanceAccount libro) async {
    final db = ref.read(databaseProvider);
    await db.archiveFinanceAccount(libro.id);
    ref.invalidate(financeAccountsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro archivado')),
      );
    }
  }

  Future<void> _eliminarLibro(BuildContext context, FinanceAccount libro) async {
    final db = ref.read(databaseProvider);
    try {
      final count = await db.countTransactionsForAccount(libro.id);
      if (count == 0) {
        await db.deleteFinanceAccountSafely(libro.id);
        ref.invalidate(financeAccountsProvider);
        return;
      }
      if (!context.mounted) return;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar definitivamente'),
          content: Text(
            'Este registro tiene $count movimiento(s). Eliminarlo borrará también '
            'todo su historial de forma irreversible. Si solo quieres dejar de '
            'verlo pero conservar los datos, usa "Archivar" en su lugar.\n\n'
            '¿Seguro que quieres eliminarlo y perder su historial para siempre?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar y perder historial')),
          ],
        ),
      );
      if (confirmado == true) {
        await db.deleteFinanceAccountAndHistory(libro.id);
        if (context.mounted) ref.invalidate(financeAccountsProvider);
      }
    } on AccountHasTransactionsException catch (_) {
      if (!context.mounted) return;
      // Puede ser por transacciones (el count==0 de arriba ya las
      // descartó en este punto) o por una meta vinculada activa/pausada —
      // si es lo segundo, ofrecer un atajo directo a resolverlo en vez de
      // un mensaje genérico.
      final metas = (await db.getFinanceReservations(libro.id))
          .where((r) => r.estado == 'activa' || r.estado == 'pausada')
          .toList();
      if (metas.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo eliminar el registro.')),
          );
        }
        return;
      }
      if (!context.mounted) return;
      await _ofrecerResolverMetaVinculada(context, libro, metas);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar el registro: $e')),
        );
      }
    }
  }

  /// Un registro con una meta vinculada activa/pausada no se puede borrar
  /// (onDelete: restrict) — en vez de un error genérico, ofrece resolverlo
  /// directo: reasignar la meta a otra cuenta o convertirla a virtual.
  Future<void> _ofrecerResolverMetaVinculada(
    BuildContext context,
    FinanceAccount libro,
    List<FinanceReservationRow> metas,
  ) async {
    final meta = metas.first;
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se puede eliminar este registro'),
        content: Text(
          'Tiene la meta "${meta.nombre}" vinculada con dinero reservado. '
          'Reasígnala a otra cuenta o conviértela a virtual antes de eliminar el registro.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'virtual'), child: const Text('Convertir a virtual')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'reasignar'), child: const Text('Reasignar')),
        ],
      ),
    );
    if (accion == null || !context.mounted) return;
    final db = ref.read(databaseProvider);

    if (accion == 'virtual') {
      await db.upsertFinanceReservation(FinanceReservationsCompanion(
        id: Value(meta.id), accountId: const Value(null), nombre: Value(meta.nombre),
        monto: Value(meta.monto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
        fechaLimite: Value(meta.fechaLimite), estado: Value(meta.estado), modalidad: const Value('virtual'),
      ));
      ref.invalidate(allFinanceReservationsProvider);
      return;
    }

    // Reasignar: elegir otra cuenta existente (distinta de la que se
    // quiere borrar).
    final rows = ref.read(financeAccountsProvider).valueOrNull ?? [];
    final otras = rows.map(FinanceAccount.fromRow).where((c) => c.id != libro.id).toList();
    if (otras.isEmpty || !context.mounted) return;
    final destino = await showModalBottomSheet<FinanceAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in otras)
                ListTile(title: Text(c.nombre), onTap: () => Navigator.of(ctx).pop(c)),
            ],
          ),
        ),
      ),
    );
    if (destino == null) return;
    await db.upsertFinanceReservation(FinanceReservationsCompanion(
      id: Value(meta.id), accountId: Value(destino.id), nombre: Value(meta.nombre),
      monto: Value(meta.monto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
      fechaLimite: Value(meta.fechaLimite), estado: Value(meta.estado), modalidad: const Value('vinculada'),
    ));
    ref.invalidate(allFinanceReservationsProvider);
  }

  void _mostrarArchivadosSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => _ArchivadosSheet(
        onReactivado: () => ref.invalidate(financeAccountsProvider),
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
                onVerArchivados: _mostrarArchivadosSheet,
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
                              onTap: () {
                                // Entrar por el flujo normal siempre arranca
                                // sin filtro de categoría — ese filtro solo
                                // lo activa el drill-down desde Estadísticas
                                // (ver finanzas_estadisticas_screen.dart).
                                ref.read(finanzasFiltrosProvider.notifier).state =
                                    ref.read(finanzasFiltrosProvider).copyWith(limpiarCategoria: true);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        FinanzasLibroTransaccionesScreen(libro: libro),
                                  ),
                                );
                              },
                              onFavorito: () => _marcarFavorito(libro),
                              onEditar: () => _mostrarEditarRegistroSheet(libro),
                              onArchivar: () => _archivarLibro(libro),
                              onEliminar: () => _eliminarLibro(context, libro),
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
          ? _FinanzasSpeedDial(
              libros: asyncLibros.value!.map(FinanceAccount.fromRow).toList(),
              onNuevoRegistro: _mostrarNuevoRegistroSheet,
            )
          : null,
    );
  }

  Future<void> _marcarFavorito(FinanceAccount libro) async {
    HapticFeedback.mediumImpact();
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
  final VoidCallback onVerArchivados;

  const _GlobalHeader({
    required this.libros,
    required this.accentColor,
    required this.onVerArchivados,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double balance = 0;
    bool loading = false;

    // Una sola consulta batcheada para todas las cuentas, en vez de un
    // watch por cuenta (antes: 3×N queries para N cuentas visibles).
    final balancesAsync = ref.watch(allFinanceAccountBalancesProvider);
    for (final libro in libros) {
      final balanceAsync = balancesAsync.whenData((m) => m[libro.id]);
      balanceAsync.when(
        data: (b) => balance += b?.saldo ?? 0,
        loading: () => loading = true,
        error: (e, st) {},
      );
    }
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
            const SizedBox(height: AppSpacing.section),
            Row(
              children: [
                Text(
                  '${libros.length} ${libros.length == 1 ? 'registro' : 'registros'}',
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onVerArchivados,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'Archivados',
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        fontWeight: FontWeight.w600,
                        color: colors.textTertiary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── FAB expandible: Nuevo registro + accesos rápidos de transacción ─────────
// Antes había una fila fija de 3 botones (Ingreso/Gasto/Transferir) debajo
// del resumen, compitiendo visualmente con el resto del header. Se
// consolidan detrás de un único FAB que se expande hacia arriba al tocarlo,
// como pidió el usuario explícitamente tras ver la pantalla real.
class _FinanzasSpeedDial extends StatefulWidget {
  final List<FinanceAccount> libros;
  final VoidCallback onNuevoRegistro;

  const _FinanzasSpeedDial({required this.libros, required this.onNuevoRegistro});

  @override
  State<_FinanzasSpeedDial> createState() => _FinanzasSpeedDialState();
}

class _FinanzasSpeedDialState extends State<_FinanzasSpeedDial> {
  bool _abierto = false;

  void _toggle() => setState(() => _abierto = !_abierto);

  void _cerrarYEjecutar(VoidCallback accion) {
    setState(() => _abierto = false);
    accion();
  }

  void _abrirTransaccion(String tipo) {
    showNuevaTransaccionSheet(
      context,
      libroId: widget.libros.length == 1 ? widget.libros.first.id : null,
      tipoInicial: tipo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_abierto) ...[
          _SpeedDialOption(
            label: 'Nuevo registro',
            icon: Icons.account_balance_wallet_outlined,
            colors: colors,
            onTap: () => _cerrarYEjecutar(widget.onNuevoRegistro),
          ),
          const SizedBox(height: 10),
          _SpeedDialOption(
            label: 'Transferir',
            icon: Icons.swap_horiz,
            colors: colors,
            onTap: () => _cerrarYEjecutar(() => _abrirTransaccion('transferencia')),
          ),
          const SizedBox(height: 10),
          _SpeedDialOption(
            label: 'Gasto',
            icon: Icons.arrow_upward,
            colors: colors,
            onTap: () => _cerrarYEjecutar(() => _abrirTransaccion('gasto')),
          ),
          const SizedBox(height: 10),
          _SpeedDialOption(
            label: 'Ingreso',
            icon: Icons.arrow_downward,
            colors: colors,
            onTap: () => _cerrarYEjecutar(() => _abrirTransaccion('ingreso')),
          ),
          const SizedBox(height: 14),
        ],
        FloatingActionButton(
          backgroundColor: cs.primary,
          foregroundColor: legibleForegroundOn(cs.primary),
          onPressed: _toggle,
          child: AnimatedRotation(
            turns: _abierto ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }
}

class _SpeedDialOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppThemeColors colors;
  final VoidCallback onTap;

  const _SpeedDialOption({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: colors.borderCard),
                ),
                child: Text(label, style: TextStyle(fontSize: AppTextSize.body, color: colors.textPrimary)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.bgCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.borderCard),
                ),
                child: Icon(icon, size: AppIconSize.medium, color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
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
  final VoidCallback onArchivar;
  final VoidCallback onEliminar;

  const _LibroCard({
    required this.libro,
    required this.onTap,
    required this.onFavorito,
    required this.onEditar,
    required this.onArchivar,
    required this.onEliminar,
  });

  // Color fijo del ★ de favorito — ya no distingue registros por color
  // propio (rediseño "caja + contenido simple": sin avatar ni franja
  // lateral), así que una sola insignia dorada identifica el favorito
  // igual en todas las tarjetas.
  static const _favoritoColor = Color(0xFFFACC15);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final balanceAsync = ref.watch(financeAccountBalanceProvider(libro.id));

    return Dismissible(
      key: ValueKey(libro.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.card),
        decoration: BoxDecoration(
          color: _favoritoColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Row(
          children: [
            Icon(Icons.star_rounded, color: _favoritoColor),
            SizedBox(width: 8),
            Text(
              'Predeterminado',
              style: TextStyle(
                color: _favoritoColor,
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
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.card, 10, AppSpacing.tile, AppSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Nombre + ★ favorito + menú — pegado arriba, menú
                // desplazado hacia el borde derecho de la tarjeta.
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              libro.nombre,
                              style: TextStyle(
                                fontSize: AppTextSize.body,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (libro.esFavorito) ...[
                            const SizedBox(width: 8),
                            Text(
                              'PRINCIPAL',
                              style: TextStyle(
                                fontSize: AppTextSize.caption,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: _favoritoColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(8, 0),
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.more_vert_rounded, size: AppIconSize.small, color: colors.textTertiary),
                        onSelected: (value) {
                          switch (value) {
                            case 'editar':
                              onEditar();
                              break;
                            case 'archivar':
                              onArchivar();
                              break;
                            case 'eliminar':
                              onEliminar();
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'editar',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Editar'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'archivar',
                            child: ListTile(
                              leading: Icon(Icons.archive_outlined),
                              title: Text('Archivar'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'eliminar',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Eliminar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (libro.descripcion.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(0, -10),
                    child: Text(
                      libro.descripcion,
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        fontStyle: FontStyle.italic,
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 6),
                // ── Split: balance a la izquierda, Ingresos/Gastos a la
                // derecha — mismo patrón que el resumen dentro de un
                // registro, pensado para ahorrar altura en vez de apilar
                // balance y montos en filas separadas.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'BALANCE',
                              style: TextStyle(
                                fontSize: AppTextSize.caption,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: colors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            balanceAsync.when(
                              loading: () => SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: colors.textTertiary),
                              ),
                              error: (e, st) => const SizedBox(height: AppTextSize.emphasis),
                              data: (b) {
                                final balance = b.saldoSinTransferencias;
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(width: 1, color: colors.borderCard.withValues(alpha: 0.6)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: balanceAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, st) => const SizedBox.shrink(),
                          data: (b) => Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RegistroStat(
                                icono: Icons.north_east_rounded,
                                iconoColor: const Color(0xFF22C55E),
                                label: 'Ingresos',
                                valor: formatCOP(b.ingresos),
                                colors: colors,
                              ),
                              const SizedBox(height: 6),
                              _RegistroStat(
                                icono: Icons.south_east_rounded,
                                iconoColor: const Color(0xFFEF4444),
                                label: 'Gastos',
                                valor: formatCOP(b.gastos),
                                colors: colors,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _RegistroStat extends StatelessWidget {
  final IconData icono;
  final Color iconoColor;
  final String label;
  final String valor;
  final AppThemeColors colors;

  const _RegistroStat({
    required this.icono,
    required this.iconoColor,
    required this.label,
    required this.valor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: AppIconSize.micro, color: iconoColor),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: AppTextSize.caption, color: colors.textTertiary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Sheet de registros archivados ────────────────────────────────────────────
class _ArchivadosSheet extends ConsumerStatefulWidget {
  final VoidCallback onReactivado;
  const _ArchivadosSheet({required this.onReactivado});

  @override
  ConsumerState<_ArchivadosSheet> createState() => _ArchivadosSheetState();
}

class _ArchivadosSheetState extends ConsumerState<_ArchivadosSheet> {
  late Future<List<FinanceAccountRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<FinanceAccountRow>> _cargar() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getFinanceAccounts(incluirArchivadas: true);
    return rows.where((r) => !r.activa).toList();
  }

  Future<void> _reactivar(String id) async {
    final db = ref.read(databaseProvider);
    await db.reactivateFinanceAccount(id);
    widget.onReactivado();
    setState(() => _future = _cargar());
  }

  @override
  Widget build(BuildContext context) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
            Text(
              'Registros archivados',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<FinanceAccountRow>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final archivados = snapshot.data!;
                if (archivados.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No hay registros archivados.',
                      style: TextStyle(color: kredit.textSecondary),
                    ),
                  );
                }
                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: archivados.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: kredit.borderCard),
                    itemBuilder: (context, index) {
                      final row = archivados[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(row.nombre),
                        trailing: TextButton(
                          onPressed: () => _reactivar(row.id),
                          child: const Text('Reactivar'),
                        ),
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
      // La tarjeta ya no distingue registros por color (diseño sin avatar
      // ni franja lateral) — se conserva el que ya tenía al editar, y uno
      // neutro fijo al crear, solo para no dejar la columna sin valor.
      color: Value(widget.editar?.color ?? '#EF4444'),
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
