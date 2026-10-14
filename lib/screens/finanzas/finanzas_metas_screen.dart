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
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/utils/credit_display_utils.dart';
import 'package:krezium/utils/monto_input_formatter.dart';
import 'package:uuid/uuid.dart';

Color _colorFromHex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

/// Fase 05 — Metas de ahorro: el dinero de una meta vive dentro del saldo
/// de su registro (campo `monto` en FinanceReservations, ya restado del
/// disponible desde Fase 01) — nunca se mueve a otro registro ni genera un
/// ingreso o gasto. Aportar/retirar solo ajusta ese monto reservado.
///
/// Sin Scaffold/FAB propios — vive embebida como pestaña de
/// FinanzasPlanificacionScreen; su FAB se expone aparte como [MetasFab].
class FinanzasMetasScreen extends ConsumerWidget {
  const FinanzasMetasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          final activas = metas.where((m) => m.estado != 'cancelada').toList()
            ..sort((a, b) => a.estado == b.estado
                ? a.nombre.compareTo(b.nombre)
                : (a.estado == 'activa' ? -1 : 1));

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
        await db.upsertFinanceReservation(FinanceReservationsCompanion(
          id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
          monto: Value(meta.monto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
          fechaLimite: Value(meta.fechaLimite), estado: const Value('finalizada'),
        ));
        ref.invalidate(allFinanceReservationsProvider);
      case 'cancelar':
        final confirmado = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancelar meta'),
            content: Text(
              '¿Cancelar "${meta.nombre}"? El dinero reservado (${formatCOP(meta.monto)}) vuelve a estar disponible en el registro.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar meta')),
            ],
          ),
        );
        if (confirmado == true) {
          await db.upsertFinanceReservation(FinanceReservationsCompanion(
            id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
            monto: Value(meta.monto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
            fechaLimite: Value(meta.fechaLimite), estado: const Value('cancelada'),
          ));
          ref.invalidate(allFinanceReservationsProvider);
          // Meta virtual (accountId null) no descuenta de ningún registro
          // puntual — no hay balance de cuenta que invalidar.
          if (meta.accountId != null) {
            ref.invalidate(financeAccountBalanceProvider(meta.accountId!));
          }
        }
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
                        if (cuenta != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(iconFromKey(cuenta!.icono), size: AppIconSize.micro, color: tc.textTertiary),
                              const SizedBox(width: 4),
                              Text(cuenta!.nombre, style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary)),
                            ],
                          ),
                        ],
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
  late FinanceAccount? _cuenta = widget.editando != null
      ? widget.cuentas.where((c) => c.id == widget.editando!.accountId).firstOrNull
      : (widget.cuentas.length == 1 ? widget.cuentas.first : null);
  late DateTime? _fechaLimite =
      widget.editando?.fechaLimite != null ? DateTime.tryParse(widget.editando!.fechaLimite!) : null;
  bool _guardando = false;

  bool get _editando => widget.editando != null;

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

  Future<void> _guardar() async {
    final cuenta = _cuenta;
    final objetivo = _objetivoValido;
    final nombre = _nombreCtrl.text.trim();
    if (cuenta == null || objetivo == null || nombre.isEmpty) return;
    setState(() => _guardando = true);
    final db = ref.read(databaseProvider);
    final id = widget.editando?.id ?? const Uuid().v4();
    await db.upsertFinanceReservation(FinanceReservationsCompanion.insert(
      id: id,
      accountId: Value(cuenta.id),
      nombre: nombre,
      monto: widget.editando?.monto ?? 0,
      creadaEn: widget.editando?.creadaEn ?? DateTime.now().toIso8601String(),
      montoObjetivo: Value(objetivo),
      fechaLimite: Value(_fechaLimite != null ? DateFormat('yyyy-MM-dd').format(_fechaLimite!) : null),
      estado: Value(widget.editando?.estado ?? 'activa'),
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
                    onPressed: (_guardando || _cuenta == null || _objetivoValido == null || _nombreCtrl.text.trim().isEmpty)
                        ? null
                        : _guardar,
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

  const _AportarRetirarSheet({required this.meta, required this.esAporte});

  @override
  ConsumerState<_AportarRetirarSheet> createState() => _AportarRetirarSheetState();
}

class _AportarRetirarSheetState extends ConsumerState<_AportarRetirarSheet> {
  final _montoCtrl = TextEditingController();
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
    await ref.read(databaseProvider).upsertFinanceReservation(FinanceReservationsCompanion(
          id: Value(meta.id), accountId: Value(meta.accountId), nombre: Value(meta.nombre),
          monto: Value(nuevoMonto), creadaEn: Value(meta.creadaEn), montoObjetivo: Value(meta.montoObjetivo),
          fechaLimite: Value(meta.fechaLimite), estado: Value(meta.estado),
        ));
    ref.invalidate(allFinanceReservationsProvider);
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
          onPressed: () => FinanzasMetasScreen._abrirFormulario(context, ref, cuentas: cuentas),
          icon: const Icon(Icons.add),
          label: const Text('Meta'),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
