import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/finance_icon_map.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_goal.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/screens/finanzas/nueva_transaccion_sheet.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/utils/monto_input_formatter.dart';
import 'package:uuid/uuid.dart';

Color _colorFromHex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

/// Fase C3: atajo opcional tras guardar un ingreso — "Apartar a una
/// meta". Si no hay ninguna meta 'activa', no hace nada (el llamador no
/// debería ni ofrecer el atajo en ese caso). Con una sola meta activa va
/// directo al sheet de aportar; con varias, pregunta cuál primero.
///
/// Recibe [context] en vez de un WidgetRef porque se dispara desde el
/// action de un SnackBar mostrado *después* de que el formulario de
/// transacción ya se cerró — en ese punto su propio State (y su ref) ya
/// está disposed. `ProviderScope.containerOf` sigue siendo válido porque
/// [context] viene del Navigator (vive por encima de la ruta cerrada).
Future<void> abrirApartarIngresoAMeta(
  BuildContext context, {
  required double monto,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final metas = (container.read(allFinanceReservationsProvider).valueOrNull ?? [])
      .where((m) => m.estado == 'activa')
      .toList();
  if (metas.isEmpty) return;

  FinanceReservationRow? meta;
  if (metas.length == 1) {
    meta = metas.first;
  } else {
    meta = await showModalBottomSheet<FinanceReservationRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final tc = Theme.of(ctx).extension<AppThemeColors>()!;
        return Material(
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
                    child: Text('¿A qué meta apartas?', style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary)),
                  ),
                ),
                for (final m in metas)
                  ListTile(title: Text(m.nombre), onTap: () => Navigator.of(ctx).pop(m)),
              ],
            ),
          ),
        );
      },
    );
  }
  if (meta == null || !context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AportarRetirarSheet(meta: meta!, esAporte: true, montoInicial: monto),
  );
}

/// Fase 05 — Metas de ahorro: el dinero de una meta vive dentro del saldo
/// de su registro (campo `monto` en FinanceReservations, ya restado del
/// disponible desde Fase 01) — nunca se mueve a otro registro ni genera un
/// ingreso o gasto. Aportar/retirar solo ajusta ese monto reservado.
///
/// Sin Scaffold/FAB propios — vive embebida como pestaña de
/// FinanzasPlanificacionScreen; su FAB se expone aparte como [MetasFab].
class FinanzasMetasScreen extends ConsumerStatefulWidget {
  const FinanzasMetasScreen({super.key});

  @override
  ConsumerState<FinanzasMetasScreen> createState() => _FinanzasMetasScreenState();
}

class _FinanzasMetasScreenState extends ConsumerState<FinanzasMetasScreen> {
  // Cache por identidad de `metas` — mismo patrón que
  // `_FilteredListState._apply()` en credits_list_screen.dart (ver Task 12
  // de la auditoría de performance). Evita re-filtrar/re-ordenar las metas
  // en cada rebuild no relacionado.
  List<FinanceReservationRow>? _lastMetas;
  List<FinanceReservationRow>? _cachedActivas;

  List<FinanceReservationRow> _activas(List<FinanceReservationRow> metas) {
    if (identical(_lastMetas, metas) && _cachedActivas != null) {
      return _cachedActivas!;
    }
    _lastMetas = metas;
    _cachedActivas = metas.where((m) => m.estado != 'cancelada').toList()
      ..sort((a, b) => a.estado == b.estado
          ? a.nombre.compareTo(b.nombre)
          : (a.estado == 'activa' ? -1 : 1));
    return _cachedActivas!;
  }

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final metasAsync = ref.watch(allFinanceReservationsProvider);
    final cuentasAsync = ref.watch(financeAccountsProvider);

    return metasAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (metas) => cuentasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cuentasRows) {
          final cuentas = cuentasRows.map(FinanceAccount.fromRow).toList();
          final cuentaPorId = {for (final c in cuentas) c.id: c};
          final activas = _activas(metas);

          return activas.isEmpty
              ? _EstadoVacio(tc: tc, hayCuentas: cuentas.isNotEmpty)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    for (final meta in activas) ...[
                      _MetaCard(
                        meta: meta,
                        cuenta: cuentaPorId[meta.accountId],
                        tc: tc,
                        onTap: () => _abrirAcciones(context, ref, meta, cuentas),
                      ),
                      const SizedBox(height: AppSpacing.tile),
                    ],
                  ],
                );
        },
      ),
    );
  }

  static Future<void> _abrirFormulario(
    BuildContext context,
    WidgetRef ref, {
    required List<FinanceAccount> cuentas,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MetaFormSheet(cuentas: cuentas),
    );
  }

  static Future<void> _abrirAcciones(
    BuildContext context,
    WidgetRef ref,
    FinanceReservationRow meta,
    List<FinanceAccount> cuentas,
  ) async {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final accion = await showModalBottomSheet<String>(
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
              _HistorialMeta(goalId: meta.id, tc: tc),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.add_circle_outline), title: const Text('Aportar'), onTap: () => Navigator.pop(ctx, 'aportar')),
              ListTile(leading: const Icon(Icons.remove_circle_outline), title: const Text('Retirar'), onTap: () => Navigator.pop(ctx, 'retirar')),
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar'), onTap: () => Navigator.pop(ctx, 'editar')),
              if (meta.estado == 'activa')
                ListTile(leading: const Icon(Icons.pause_circle_outline), title: const Text('Pausar'), onTap: () => Navigator.pop(ctx, 'pausar')),
              if (meta.estado == 'pausada')
                ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('Reanudar'), onTap: () => Navigator.pop(ctx, 'reanudar')),
              if (meta.estado != 'finalizada')
                ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Marcar como cumplida'), onTap: () => Navigator.pop(ctx, 'finalizar')),
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: Colors.red.shade400),
                title: Text('Cancelar meta', style: TextStyle(color: Colors.red.shade400)),
                subtitle: const Text('Libera el dinero reservado'),
                onTap: () => Navigator.pop(ctx, 'cancelar'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: tc.textTertiary),
                title: const Text('Eliminar'),
                onTap: () => Navigator.pop(ctx, 'eliminar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (accion == null || !context.mounted) return;

    final db = ref.read(databaseProvider);
    switch (accion) {
      case 'aportar':
      case 'retirar':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AportarRetirarSheet(meta: meta, esAporte: accion == 'aportar'),
        );
      case 'editar':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _MetaFormSheet(cuentas: cuentas, editando: meta),
        );
      case 'pausar':
        await db.upsertFinanceReservation(FinanceReservationsCompanion(
          id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
          monto: Value(meta.monto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
          fechaLimite: Value(meta.fechaLimite), estado: const Value('pausada'),
        ));
        ref.invalidate(allFinanceReservationsProvider);
      case 'reanudar':
        await db.upsertFinanceReservation(FinanceReservationsCompanion(
          id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
          monto: Value(meta.monto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
          fechaLimite: Value(meta.fechaLimite), estado: const Value('activa'),
        ));
        ref.invalidate(allFinanceReservationsProvider);
      case 'finalizar':
      case 'cancelar':
        // Completar y cancelar comparten el mismo flujo de cierre: nunca
        // dejan el dinero reservado en silencio, siempre preguntan qué
        // hacer con él (ver spec Planificación v2, sección 2.5).
        if (!context.mounted) return;
        await _cerrarMeta(context, ref, meta, accion, cuentas);
      case 'eliminar':
        final confirmado = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eliminar meta'),
            content: Text('¿Eliminar "${meta.nombre}" definitivamente? Si tenía dinero reservado, vuelve a estar disponible.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
            ],
          ),
        );
        if (confirmado == true) {
          await db.deleteFinanceReservation(meta.id);
          ref.invalidate(allFinanceReservationsProvider);
          if (meta.accountId != null) {
            ref.invalidate(financeAccountBalanceProvider(meta.accountId!));
          }
        }
    }
  }

  /// Flujo de cierre compartido entre completar ('finalizar') y cancelar —
  /// nunca deja el dinero reservado en silencio: pregunta explícitamente
  /// qué hacer. Si el usuario cierra el sheet sin elegir, no se aplica
  /// ningún cambio (la reserva sigue intacta).
  static Future<void> _cerrarMeta(
    BuildContext context,
    WidgetRef ref,
    FinanceReservationRow meta,
    String tipoCierre, // 'finalizar' | 'cancelar'
    List<FinanceAccount> cuentas,
  ) async {
    final eleccion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final tc = Theme.of(ctx).extension<AppThemeColors>()!;
        return Material(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tipoCierre == 'finalizar' ? '¿Completar esta meta?' : '¿Cancelar esta meta?',
                    style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '¿Qué hacer con ${formatCOP(meta.monto)} reservados?',
                    style: TextStyle(color: tc.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  ListTile(
                    leading: const Icon(Icons.shopping_cart_outlined),
                    title: const Text('Gastar ahora'),
                    subtitle: const Text('Registra un gasto real por este monto'),
                    onTap: () => Navigator.pop(ctx, 'gastar'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: const Text('Mantener en un registro'),
                    subtitle: const Text('Pasa a ser saldo normal de un registro'),
                    onTap: () => Navigator.pop(ctx, 'mantener'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (eleccion == null || !context.mounted) return; // sin elegir, la reserva sigue intacta

    final nuevoEstado = tipoCierre == 'finalizar' ? 'finalizada' : 'cancelada';

    if (eleccion == 'gastar') {
      String? libroDestino = meta.accountId;
      if (libroDestino == null) {
        // Meta virtual: no tiene cuenta propia, hay que elegir dónde se
        // refleja el gasto.
        libroDestino = await _elegirCuentaSimple(context, cuentas);
        if (libroDestino == null || !context.mounted) return;
      }
      await showNuevaTransaccionSheet(
        context,
        libroId: libroDestino,
        tipoInicial: 'gasto',
        montoInicial: meta.monto,
        onGuardado: () {
          final db = ref.read(databaseProvider);
          db.upsertFinanceReservation(FinanceReservationsCompanion(
            id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
            monto: const Value(0), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
            fechaLimite: Value(meta.fechaLimite), estado: Value(nuevoEstado),
          ));
          ref.invalidate(allFinanceReservationsProvider);
          if (meta.accountId != null) {
            ref.invalidate(financeAccountBalanceProvider(meta.accountId!));
          }
        },
      );
    } else if (eleccion == 'mantener') {
      final destino = await _elegirRegistroDestino(context, ref, cuentas, meta.accountId);
      if (destino == null || !context.mounted) return;
      final db = ref.read(databaseProvider);
      final notaMeta = 'Proveniente de meta: ${meta.nombre}';
      final descripcionNueva = destino.descripcion.isEmpty ? notaMeta : '${destino.descripcion}; $notaMeta';
      await db.upsertFinanceAccount(FinanceAccountsCompanion(
        id: Value(destino.id), nombre: Value(destino.nombre), tipo: Value(destino.tipo),
        icono: Value(destino.icono), color: Value(destino.color),
        saldoInicial: Value(destino.saldoInicial + meta.monto),
        activa: Value(destino.activa), orden: Value(destino.orden), esFavorito: Value(destino.esFavorito),
        descripcion: Value(descripcionNueva),
      ));
      await db.upsertFinanceReservation(FinanceReservationsCompanion(
        id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
        monto: const Value(0), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
        fechaLimite: Value(meta.fechaLimite), estado: Value(nuevoEstado),
      ));
      ref.invalidate(allFinanceReservationsProvider);
      ref.invalidate(financeAccountsProvider);
      ref.invalidate(financeAccountBalanceProvider(destino.id));
      if (meta.accountId != null && meta.accountId != destino.id) {
        ref.invalidate(financeAccountBalanceProvider(meta.accountId!));
      }
    }
  }

  /// Selector simple de cuenta (sin opción de crear) — usado para "gastar
  /// ahora" cuando la meta es virtual y no tiene cuenta propia.
  static Future<String?> _elegirCuentaSimple(BuildContext context, List<FinanceAccount> cuentas) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final tc = Theme.of(ctx).extension<AppThemeColors>()!;
        return Material(
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
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in cuentas)
                        ListTile(
                          leading: Icon(iconFromKey(c.icono), color: _colorFromHex(c.color)),
                          title: Text(c.nombre),
                          onTap: () => Navigator.of(ctx).pop(c.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Selector para "mantener en un registro": el actual (si la meta es
  /// vinculada), uno existente, o uno nuevo (nombre corto, sin el resto de
  /// la configuración de un registro — eso puede ajustarse después).
  static Future<FinanceAccount?> _elegirRegistroDestino(
    BuildContext context,
    WidgetRef ref,
    List<FinanceAccount> cuentas,
    String? cuentaActualId,
  ) async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final tc = Theme.of(ctx).extension<AppThemeColors>()!;
        final cuentaActual = cuentas.where((c) => c.id == cuentaActualId).firstOrNull;
        return Material(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cuentaActual != null)
                  ListTile(
                    leading: Icon(iconFromKey(cuentaActual.icono), color: _colorFromHex(cuentaActual.color)),
                    title: Text('Este mismo registro (${cuentaActual.nombre})'),
                    onTap: () => Navigator.pop(ctx, cuentaActual.id),
                  ),
                for (final c in cuentas.where((c) => c.id != cuentaActualId))
                  ListTile(
                    leading: Icon(iconFromKey(c.icono), color: _colorFromHex(c.color)),
                    title: Text(c.nombre),
                    onTap: () => Navigator.pop(ctx, c.id),
                  ),
                ListTile(
                  leading: Icon(Icons.add_circle_outline, color: tc.textSecondary),
                  title: const Text('Crear un registro nuevo'),
                  onTap: () => Navigator.pop(ctx, '__nuevo__'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (opcion == null) return null;
    if (opcion != '__nuevo__') {
      return cuentas.where((c) => c.id == opcion).firstOrNull;
    }
    if (!context.mounted) return null;
    final nombreCtrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo registro'),
        content: TextField(controller: nombreCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'Nombre del registro')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nombreCtrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return null;
    final db = ref.read(databaseProvider);
    final id = const Uuid().v4();
    await db.upsertFinanceAccount(FinanceAccountsCompanion.insert(
      id: id, nombre: nombre, tipo: 'efectivo', icono: 'wallet', color: '#6B7280',
    ));
    return FinanceAccount(
      id: id, nombre: nombre, tipo: 'efectivo', icono: 'wallet', color: '#6B7280',
      saldoInicial: 0, activa: true, orden: '0', esFavorito: false, descripcion: '',
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final AppThemeColors tc;
  final bool hayCuentas;
  const _EstadoVacio({required this.tc, required this.hayCuentas});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: AppIconSize.large, color: tc.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Sin metas de ahorro',
              style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              hayCuentas
                  ? 'Crea una meta dentro de un registro para apartar dinero sin gastarlo.'
                  : 'Crea primero un registro en Finanzas para poder apartar dinero en una meta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTextSize.body, color: tc.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  final FinanceReservationRow meta;
  final FinanceAccount? cuenta;
  final AppThemeColors tc;
  final VoidCallback onTap;

  const _MetaCard({required this.meta, required this.cuenta, required this.tc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = cuenta != null ? _colorFromHex(cuenta!.color) : tc.textTertiary;
    final progreso = progresoMeta(aportado: meta.monto, objetivo: meta.montoObjetivo);
    final restante = montoRestanteMeta(aportado: meta.monto, objetivo: meta.montoObjetivo);
    final fechaLimite = meta.fechaLimite != null ? DateTime.tryParse(meta.fechaLimite!) : null;
    final contribucion = fechaLimite != null
        ? contribucionOrientativa(restante: restante, fechaLimite: fechaLimite, hoy: DateTime.now())
        : null;
    final inactiva = meta.estado != 'activa';

    return Opacity(
      opacity: inactiva ? 0.7 : 1,
      child: Container(
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
              Container(width: 4, color: color),
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
                            Expanded(
                              child: Text(
                                meta.nombre,
                                style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w700, color: tc.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (meta.estado == 'pausada' || meta.estado == 'finalizada')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: tc.borderCard.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(AppRadius.chip),
                                ),
                                child: Text(
                                  meta.estado == 'pausada' ? 'Pausada' : 'Cumplida',
                                  style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: tc.textSecondary),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              cuenta != null ? iconFromKey(cuenta!.icono) : Icons.public,
                              size: AppIconSize.micro,
                              color: tc.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              cuenta?.nombre ?? 'Virtual · disponible global',
                              style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          child: LinearProgressIndicator(
                            value: progreso.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: color.withValues(alpha: 0.12),
                            color: progreso >= 1 ? Colors.green : color,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${formatCOP(meta.monto)} de ${formatCOP(meta.montoObjetivo)}',
                          style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary),
                        ),
                        if (fechaLimite != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            restante <= 0
                                ? 'Meta cumplida'
                                : contribucion != null
                                    ? 'Faltan ${formatCOP(restante)} · aporta ~${formatCOP(contribucion)}/mes para llegar el ${DateFormat('d MMM yyyy', 'es').format(fechaLimite)}'
                                    : 'Faltan ${formatCOP(restante)} · venció el ${DateFormat('d MMM yyyy', 'es').format(fechaLimite)}',
                            style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary),
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
      ),
    );
  }
}

/// Historial de aportes/retiros de solo lectura — Planificación v2, la
/// tabla FinanceGoalMovements es lo que lo hace posible (antes solo
/// existía el acumulado, sin forma de reconstruir qué pasó y cuándo).
class _HistorialMeta extends ConsumerWidget {
  final String goalId;
  final AppThemeColors tc;

  const _HistorialMeta({required this.goalId, required this.tc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movimientosAsync = ref.watch(financeGoalMovementsProvider(goalId));
    return movimientosAsync.maybeWhen(
      data: (movimientos) {
        if (movimientos.isEmpty) return const SizedBox.shrink();
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Historial', style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: tc.textTertiary)),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: movimientos.length,
                  itemBuilder: (ctx, i) {
                    final m = movimientos[i];
                    final esAporte = m.tipo == 'aporte';
                    final fecha = DateTime.tryParse(m.fecha);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        esAporte ? Icons.add_circle_outline : Icons.remove_circle_outline,
                        color: esAporte ? Colors.green : Colors.red.shade400,
                        size: AppIconSize.small,
                      ),
                      title: Text('${esAporte ? 'Aporte' : 'Retiro'} de ${formatCOP(m.monto)}'),
                      subtitle: fecha != null ? Text(DateFormat('d MMM yyyy, HH:mm', 'es').format(fecha)) : null,
                      trailing: Text('= ${formatCOP(m.saldoResultante)}', style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _MetaFormSheet extends ConsumerStatefulWidget {
  final List<FinanceAccount> cuentas;
  final FinanceReservationRow? editando;

  const _MetaFormSheet({required this.cuentas, this.editando});

  @override
  ConsumerState<_MetaFormSheet> createState() => _MetaFormSheetState();
}

class _MetaFormSheetState extends ConsumerState<_MetaFormSheet> {
  late final _nombreCtrl = TextEditingController(text: widget.editando?.nombre ?? '');
  late final _objetivoCtrl = TextEditingController(
    text: widget.editando != null ? agruparMiles(widget.editando!.montoObjetivo.round()) : '',
  );
  // Modalidad: identidad de la meta, no editable una vez creada — igual
  // criterio que la categoría de un presupuesto (ver spec Planificación v2).
  late String _modalidad = widget.editando?.modalidad ?? 'vinculada';
  late FinanceAccount? _cuenta = widget.editando != null
      ? widget.cuentas.where((c) => c.id == widget.editando!.accountId).firstOrNull
      : (widget.cuentas.length == 1 ? widget.cuentas.first : null);
  late DateTime? _fechaLimite =
      widget.editando?.fechaLimite != null ? DateTime.tryParse(widget.editando!.fechaLimite!) : null;
  bool _guardando = false;

  bool get _editando => widget.editando != null;
  bool get _esVirtual => _modalidad == 'virtual';

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _objetivoCtrl.dispose();
    super.dispose();
  }

  double? get _objetivoValido {
    final digitos = _objetivoCtrl.text.replaceAll('.', '');
    if (digitos.isEmpty) return null;
    final v = double.tryParse(digitos);
    return (v != null && v > 0) ? v : null;
  }

  bool get _puedeGuardar {
    if (_objetivoValido == null || _nombreCtrl.text.trim().isEmpty) return false;
    if (!_esVirtual && _cuenta == null) return false;
    return true;
  }

  Future<void> _guardar() async {
    final objetivo = _objetivoValido;
    final nombre = _nombreCtrl.text.trim();
    if (!_puedeGuardar || objetivo == null || nombre.isEmpty) return;
    setState(() => _guardando = true);
    final db = ref.read(databaseProvider);
    final id = widget.editando?.id ?? const Uuid().v4();
    await db.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: id,
      accountId: Value(_esVirtual ? null : _cuenta?.id),
      nombre: nombre,
      monto: widget.editando?.monto ?? 0,
      creadaEn: widget.editando?.creadaEn ?? DateTime.now().toIso8601String(),
      montoObjetivo: Value(objetivo),
      fechaLimite: Value(_fechaLimite != null ? DateFormat('yyyy-MM-dd').format(_fechaLimite!) : null),
      estado: Value(widget.editando?.estado ?? 'activa'),
      modalidad: Value(_modalidad),
    ));
    ref.invalidate(allFinanceReservationsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaLimite ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _fechaLimite = picked);
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editando ? 'Editar meta' : 'Nueva meta de ahorro',
                  style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
                ),
                const SizedBox(height: AppSpacing.section),
                TextField(
                  controller: _nombreCtrl,
                  autofocus: !_editando,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Vacaciones, Fondo de emergencia'),
                ),
                const SizedBox(height: 16),
                Text('CÓMO RESERVAR', style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: tc.textTertiary)),
                const SizedBox(height: 6),
                // Modalidad: identidad de la meta, no editable una vez creada.
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Vinculada a una cuenta'),
                        selected: _modalidad == 'vinculada',
                        onSelected: _editando ? null : (_) => setState(() => _modalidad = 'vinculada'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Virtual (sin cuenta)'),
                        selected: _esVirtual,
                        onSelected: _editando ? null : (_) => setState(() => _modalidad = 'virtual'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _esVirtual
                      ? 'Descuenta del disponible global (todas las cuentas), no de un registro puntual.'
                      : 'Descuenta del disponible del registro elegido.',
                  style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary),
                ),
                if (!_esVirtual) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    // La cuenta es donde vive el dinero reservado — cambiarla
                    // en una meta existente movería la reserva de saldo entre
                    // registros sin que el usuario lo pida explícitamente.
                    onTap: _editando ? null : () => _elegirCuenta(context),
                    child: Row(
                      children: [
                        Icon(_cuenta != null ? iconFromKey(_cuenta!.icono) : Icons.account_balance_wallet_outlined,
                            size: AppIconSize.small, color: tc.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Registro', style: TextStyle(fontSize: AppTextSize.body, color: tc.textSecondary))),
                        Text(
                          _cuenta?.nombre ?? 'Elegir registro',
                          style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600, color: _cuenta != null ? tc.textPrimary : tc.textTertiary),
                        ),
                        if (!_editando) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: AppIconSize.small, color: tc.textTertiary),
                        ],
                      ],
                    ),
                  ),
                ],
                const Divider(height: 24),
                Text('MONTO OBJETIVO', style: TextStyle(fontSize: AppTextSize.caption, fontWeight: FontWeight.w700, color: tc.textTertiary)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _objetivoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [MontoInputFormatter()],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: AppTextSize.emphasis, fontWeight: FontWeight.w700, color: tc.textPrimary),
                  decoration: const InputDecoration(prefixText: '\$ ', hintText: 'Ej. 2.000.000'),
                ),
                const Divider(height: 24),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                  onTap: _elegirFecha,
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined, size: AppIconSize.small, color: tc.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Fecha límite', style: TextStyle(fontSize: AppTextSize.body, color: tc.textSecondary))),
                      Text(
                        _fechaLimite != null ? DateFormat('d MMM yyyy', 'es').format(_fechaLimite!) : 'Sin fecha límite',
                        style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600, color: tc.textPrimary),
                      ),
                      if (_fechaLimite != null)
                        IconButton(
                          icon: Icon(Icons.close, size: AppIconSize.small, color: tc.textTertiary),
                          onPressed: () => setState(() => _fechaLimite = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: (_guardando || !_puedeGuardar) ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_editando ? 'Guardar cambios' : 'Crear meta'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _elegirCuenta(BuildContext context) async {
    final picked = await showModalBottomSheet<FinanceAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final tc = Theme.of(ctx).extension<AppThemeColors>()!;
        return Material(
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
                    child: Text('Registro', style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary)),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in widget.cuentas)
                        ListTile(
                          leading: Icon(iconFromKey(c.icono), color: _colorFromHex(c.color)),
                          title: Text(c.nombre),
                          trailing: c.id == _cuenta?.id ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
                          onTap: () => Navigator.of(ctx).pop(c),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) setState(() => _cuenta = picked);
  }
}

class _AportarRetirarSheet extends ConsumerStatefulWidget {
  final FinanceReservationRow meta;
  final bool esAporte;
  final double? montoInicial;

  const _AportarRetirarSheet({required this.meta, required this.esAporte, this.montoInicial});

  @override
  ConsumerState<_AportarRetirarSheet> createState() => _AportarRetirarSheetState();
}

class _AportarRetirarSheetState extends ConsumerState<_AportarRetirarSheet> {
  late final _montoCtrl = TextEditingController(
    text: widget.montoInicial != null ? agruparMiles(widget.montoInicial!.round()) : '',
  );
  bool _guardando = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  double? get _monto {
    final digitos = _montoCtrl.text.replaceAll('.', '');
    if (digitos.isEmpty) return null;
    return double.tryParse(digitos);
  }

  bool get _valido {
    final m = _monto;
    if (m == null) return false;
    return widget.esAporte
        ? puedeAportar(m)
        : puedeRetirar(monto: m, aportado: widget.meta.monto);
  }

  Future<void> _confirmar() async {
    final m = _monto;
    if (m == null || !_valido) return;
    setState(() => _guardando = true);
    final meta = widget.meta;
    final nuevoMonto = widget.esAporte ? meta.monto + m : meta.monto - m;
    final db = ref.read(databaseProvider);
    await db.upsertFinanceReservation(FinanceReservationsCompanion(
          id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
          monto: Value(nuevoMonto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
          fechaLimite: Value(meta.fechaLimite), estado: Value(meta.estado),
        ));
    // Historial de aportes/retiros (Planificación v2) — permite reconstruir
    // qué pasó y cuándo, el acumulado solo no alcanzaba para eso.
    await db.insertFinanceGoalMovement(FinanceGoalMovementsCompanion.insert(
      id: const Uuid().v4(),
      goalId: meta.id,
      tipo: widget.esAporte ? 'aporte' : 'retiro',
      monto: m,
      fecha: DateTime.now().toIso8601String(),
      saldoResultante: nuevoMonto,
    ));
    ref.invalidate(allFinanceReservationsProvider);
    ref.invalidate(financeGoalMovementsProvider(meta.id));
    if (meta.accountId != null) {
      ref.invalidate(financeAccountBalanceProvider(meta.accountId!));
    }
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
                widget.esAporte ? 'Aportar a "${widget.meta.nombre}"' : 'Retirar de "${widget.meta.nombre}"',
                style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                widget.esAporte
                    ? 'No es un ingreso: el dinero ya está en el registro, solo se aparta.'
                    : 'Disponible para retirar: ${formatCOP(widget.meta.monto)}',
                style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary),
              ),
              const SizedBox(height: AppSpacing.section),
              TextFormField(
                controller: _montoCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MontoInputFormatter()],
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: AppTextSize.emphasis, fontWeight: FontWeight.w700, color: tc.textPrimary),
                decoration: const InputDecoration(prefixText: '\$ ', hintText: 'Monto'),
              ),
              const SizedBox(height: AppSpacing.section),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: (_guardando || !_valido) ? null : _confirmar,
                  child: _guardando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.esAporte ? 'Aportar' : 'Retirar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FAB de la pestaña Metas — ver comentario de clase de [FinanzasMetasScreen].
class MetasFab extends ConsumerWidget {
  const MetasFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuentasAsync = ref.watch(financeAccountsProvider);
    return cuentasAsync.maybeWhen(
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        final cuentas = rows.map(FinanceAccount.fromRow).toList();
        return FloatingActionButton.extended(
          onPressed: () => _FinanzasMetasScreenState._abrirFormulario(context, ref, cuentas: cuentas),
          icon: const Icon(Icons.add),
          label: const Text('Meta'),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
