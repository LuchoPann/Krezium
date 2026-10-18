import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/card_movement.dart';
import '../../data/models/card_statement.dart';
import '../../data/models/credit.dart';
import '../../domain/card_statement_engine.dart';
import '../../domain/date_utils.dart';
import '../../providers/credits_provider.dart';
import '../../theme/app_theme.dart';
import '../card_movement_sheet.dart';
import '../confirmar_pago_extracto_sheet.dart';
import '../../utils/credit_display_utils.dart';
import '../krezium_bottom_dialogs.dart';

/// Un extracto junto a los movimientos ligados a él.
class StatementGroup {
  final CardStatement statement;
  final List<CardMovement> movements;
  const StatementGroup(this.statement, this.movements);
}

/// Agrupa [movements] por el extracto (`statementId`) al que están
/// ligados, en el mismo orden que [statements] (que ya viene ordenada
/// cronológicamente — se crean en orden por closeCurrentCycleIfDue). Un
/// extracto sin movimientos propios (ej. uno recién abierto) igual
/// aparece, con lista vacía — nunca se oculta.
List<StatementGroup> groupMovementsByStatement(
    List<CardStatement> statements, List<CardMovement> movements) {
  return [
    for (final s in statements)
      StatementGroup(
        s,
        movements.where((m) => m.statementId == s.id).toList(),
      ),
  ];
}

/// Una fila en la línea de tiempo de extractos: real (ya existe como
/// [CardStatement]) o proyectada (futura, aún no facturada). Nunca ambas.
class _TimelineEntry {
  final DateTime cutoffDate;
  final StatementGroup? group;
  final ProjectedStatement? future;

  const _TimelineEntry._(this.group, this.future, this.cutoffDate);

  factory _TimelineEntry.real(StatementGroup g) =>
      _TimelineEntry._(g, null, parseDateStr(g.statement.cutoffDate));
  factory _TimelineEntry.projected(ProjectedStatement f) =>
      _TimelineEntry._(null, f, f.cutoffDate);

  bool get isFuture => future != null;
  bool get isOpen => group?.statement.status == CardStatementStatus.open;
}

/// Movement history as a single vertical timeline — past, present (hoy) and
/// projected future extractos connected by one line, so the layout itself
/// shows the purchase→cuota→extracto flow instead of a pile of disconnected
/// cards.
class MovementsTab extends ConsumerWidget {
  final CardCredit credit;

  const MovementsTab({super.key, required this.credit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    final movements = credit.movements;

    // Extractos más reciente/abierto primero — ya vienen en orden
    // cronológico de creación, solo invertimos para mostrar lo más nuevo
    // arriba.
    final sortedStatements = credit.statements.toList()
      ..sort((a, b) => b.cutoffDate.compareTo(a.cutoffDate));
    final groups = groupMovementsByStatement(sortedStatements, movements);
    // Extractos futuros (no existen aún, se crean solos cuando su ciclo
    // cierra) van más arriba que el abierto — más lejano en el tiempo primero.
    final futureStatements = projectFutureStatements(credit).reversed.toList();

    final entries = <_TimelineEntry>[
      for (final f in futureStatements) _TimelineEntry.projected(f),
      for (final g in groups) _TimelineEntry.real(g),
    ];
    final defaultExpandedIndex = entries.indexWhere((e) => e.isOpen);

    // El check de "marcar pagado" solo se ofrece en el extracto cerrado más
    // antiguo sin pagar — es el único que un pago de ese monto exacto deja
    // en cero de forma inequívoca (el motor de pago aplica FIFO desde el
    // más viejo). Los demás (si hubiera varios atrasados) solo muestran su
    // estado, sin acción — pagarlos "fuera de orden" no tiene un resultado
    // bien definido.
    final unpaidClosed = credit.statements
        .where((s) => s.status == CardStatementStatus.closed)
        .toList()
      ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));
    final primerExigibleId = unpaidClosed.isEmpty ? null : unpaidClosed.first.id;
    final montoExigibleTotal = getPayableSummary(credit).exigible;

    // Un pago de tarjeta confirma el extracto ya cerrado — no tiene
    // sentido "pagar" algo que todavía se está acumulando en el ciclo
    // abierto (ni siquiera se sabe el total final todavía). Se habilita
    // única y exclusivamente cuando hay algo exigible.
    // Un pago de tarjeta confirma el extracto ya cerrado — no tiene
    // sentido "pagar" algo que todavía se está acumulando en el ciclo
    // abierto (ni siquiera se sabe el total final todavía). Se habilita
    // única y exclusivamente cuando hay algo exigible.
    final puedePagar = montoExigibleTotal > 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.card, AppSpacing.card, AppSpacing.card, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => CardMovementSheet.show(
                    context,
                    creditId: credit.id,
                    movementType: CardMovementType.charge,
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined, size: AppIconSize.small),
                  label: const Text('Nueva compra'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: puedePagar
                      ? () => ConfirmarPagoExtractoSheet.show(context, creditId: credit.id)
                      : null,
                  icon: const Icon(Icons.payments_outlined, size: AppIconSize.small),
                  label: const Text('Confirmar pago'),
                ),
              ),
            ],
          ),
        ),
        if (!puedePagar)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.card, 6, AppSpacing.card, 0),
            child: Text(
              'Podrás confirmar el pago cuando tu extracto cierre y entre en su fecha límite de pago.',
              style: TextStyle(fontSize: AppTextSize.caption, color: kredit.textTertiary),
            ),
          ),
        const SizedBox(height: AppSpacing.card),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Movimientos',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kredit.textPrimary,
              ),
            ),
          ),
        ),
        Expanded(
          child: movements.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: AppIconSize.large,
                          color: kredit.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sin movimientos registrados',
                          style: TextStyle(
                            fontSize: AppTextSize.body,
                            fontWeight: FontWeight.w600,
                            color: kredit.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Los cargos y pagos que registres aparecerán aquí.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTextSize.body,
                            color: kredit.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, AppSpacing.card, 16, AppSpacing.card),
                  children: [
    for (var i = 0; i < entries.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _StatementCard(
                          credit: credit,
                          cutoffDay: credit.cutoffDay,
                          entry: entries[i],
                          collapsible: entries.length > 1,
                          initiallyExpanded:
                              i == (defaultExpandedIndex >= 0 ? defaultExpandedIndex : 0),
                          esElPrimerExigible: entries[i].group != null &&
                              entries[i].group!.statement.id == primerExigibleId,
                          montoAPagar: montoExigibleTotal,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

const _monthsEs = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Builds a human-readable "6 Sep – 5 Oct" range label for a billing cycle
/// that ends on [cycleEnd], given [cutoffDay].
String _cycleRangeLabel(DateTime cycleEnd, int cutoffDay) {
  final clampedCutoff = cutoffDay.clamp(1, 28);
  // Cycle start = cutoffDay of the previous month (cutoff day opens the new
  // period at 00:00; the prior period's last day is cutoffDay - 1).
  final prevMonth = cycleEnd.month == 1 ? 12 : cycleEnd.month - 1;
  final prevYear = cycleEnd.month == 1 ? cycleEnd.year - 1 : cycleEnd.year;
  final startDay = clampedCutoff;
  final endDay = clampedCutoff > 1 ? clampedCutoff - 1 : 28;
  final startMonthLabel = _monthsEs[(prevMonth - 1).clamp(0, 11)];
  final endMonthLabel = _monthsEs[(cycleEnd.month - 1).clamp(0, 11)];
  if (prevMonth == cycleEnd.month && prevYear == cycleEnd.year) {
    return '$startDay–$endDay $endMonthLabel ${cycleEnd.year}';
  }
  return '$startDay $startMonthLabel – $endDay $endMonthLabel ${cycleEnd.year}';
}

/// Tarjeta de un extracto — real o proyectado — siguiendo el mismo lenguaje
/// visual que [AppSectionCard] (bgCard + borderCard + AppRadius.card) en
/// vez de inventar un componente nuevo, más una franja de color a la
/// izquierda y un chip de estado: el patrón que ya reconoce un usuario de
/// apps bancarias (Nubank, Mercado Pago), sin salirse del sistema de la app.
class _StatementCard extends StatefulWidget {
  final CardCredit credit;
  final int cutoffDay;
  final _TimelineEntry entry;
  final bool collapsible;
  final bool initiallyExpanded;
  // Solo true en el extracto cerrado más antiguo sin pagar — el único que
  // ofrece el check de "marcar pagado" (ver comentario en MovementsTab).
  final bool esElPrimerExigible;
  final double montoAPagar;

  const _StatementCard({
    required this.credit,
    required this.cutoffDay,
    required this.entry,
    required this.collapsible,
    required this.initiallyExpanded,
    required this.esElPrimerExigible,
    required this.montoAPagar,
  });

  @override
  State<_StatementCard> createState() => _StatementCardState();
}

class _StatementCardState extends State<_StatementCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    final accent = Theme.of(context).colorScheme.primary;
    final entry = widget.entry;
    final label = _cycleRangeLabel(entry.cutoffDate, widget.cutoffDay);

    final isFuture = entry.isFuture;
    final isOpen = entry.isOpen;
    final isPaid = entry.group?.statement.status == CardStatementStatus.paid;
    final isOverdue = !isFuture &&
        !isOpen &&
        !isPaid &&
        parseDateStr(entry.group!.statement.dueDate).isBefore(DateTime.now());

    final statusColor = isFuture
        ? kredit.textTertiary
        : isOverdue
            ? Colors.red.shade400
            : isOpen
                ? accent
                : isPaid
                    ? kredit.textTertiary
                    : kredit.textPrimary;
    // Antes decía "HOY"/"PRÓXIMO" aunque la fecha real estuviera lejos —
    // confuso, porque el resto de la app (Inicio) siempre cuenta en días.
    // Acá también: cuántos días faltan para la fecha límite de pago real
    // de ESE extracto (el ciclo abierto ya tiene la suya calculada desde
    // que se crea, ver ensureOpenStatement), nunca una palabra fija.
    final hoy = DateTime.now();
    int diasHasta(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day)
        .difference(DateTime(hoy.year, hoy.month, hoy.day))
        .inDays;
    String diasLabel(int dias) {
      if (dias < 0) return 'Vencido hace ${dias.abs()}d';
      if (dias == 0) return 'Hoy';
      if (dias == 1) return 'Mañana';
      return 'En $dias días';
    }

    final statusLabel = isFuture
        ? 'Se genera en ${diasHasta(entry.cutoffDate)}d'
        : isOverdue
            ? diasLabel(diasHasta(parseDateStr(entry.group!.statement.dueDate)))
            : isPaid
                ? 'PAGADO'
                : diasLabel(diasHasta(parseDateStr(entry.group!.statement.dueDate)));

    final movements = entry.group?.movements.reversed.toList() ?? const <CardMovement>[];
    // El monto es la deuda real de ESE extracto — igual fórmula que usa el
    // motor (computeStatementTotal), no una suma manual de cargos: incluye
    // openingBalance y ya descuenta los pagos ligados.
    final amount = isFuture
        ? entry.future!.totalAmount
        : computeStatementTotal(entry.group!.statement, widget.credit.movements);

    return Container(
      decoration: BoxDecoration(
        color: kredit.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: kredit.borderCard.withValues(alpha: isFuture ? 0.35 : 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      // IntrinsicHeight: un Row con stretch dentro de un ListView no tiene
      // altura acotada por sí solo — sin esto, el Container de 4px de ancho
      // intenta estirarse a altura infinita ("BoxConstraints forces an
      // infinite height").
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: statusColor.withValues(alpha: isFuture ? 0.4 : 1)),
          Expanded(
            child: InkWell(
              onTap: widget.collapsible ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: AppTextSize.caption,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Check de "marcar pagado" — mismo lenguaje visual
                        // que el de cuotas de préstamo (schedule_tab.dart),
                        // solo en el extracto cerrado más antiguo sin pagar.
                        if (widget.esElPrimerExigible && (isOverdue || (!isFuture && !isOpen && !isPaid)))
                          Builder(builder: (ctx) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.chip),
                              onTap: () => ConfirmarPagoExtractoSheet.show(ctx, creditId: widget.credit.id),
                              child: Container(
                                width: 22,
                                height: 22,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: statusColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(AppRadius.chip),
                                ),
                                child: Icon(Icons.check, size: 14, color: statusColor),
                              ),
                            );
                          }),
                        if (widget.collapsible)
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.expand_more, size: AppIconSize.small, color: kredit.textTertiary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(fontSize: AppTextSize.body, color: kredit.textSecondary),
                          ),
                        ),
                        Text(
                          formatCOP(amount),
                          style: TextStyle(
                            fontSize: AppTextSize.heading,
                            fontWeight: FontWeight.w800,
                            color: isFuture ? kredit.textSecondary : kredit.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (_expanded) ...[
                      const SizedBox(height: 10),
                      Divider(height: 1, color: kredit.borderCard),
                      const SizedBox(height: 6),
                      if (isFuture)
                        // Nombre de la compra + cuota — con 2+ compras
                        // pendientes en el mismo ciclo, el nombre es lo que
                        // permite diferenciarlas.
                        for (final line in entry.future!.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    line.purchaseNote.isNotEmpty
                                        ? '${line.purchaseNote} · ${line.installmentNumber}/${line.totalInstallments}'
                                        : '${line.installmentNumber}/${line.totalInstallments}',
                                    style: TextStyle(fontSize: AppTextSize.body, color: kredit.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  formatCOP(line.amount),
                                  style: TextStyle(fontSize: AppTextSize.body, color: kredit.textTertiary),
                                ),
                              ],
                            ),
                          )
                      else
                        for (var i = 0; i < movements.length; i++) ...[
                          _MovementTile(
                            credit: widget.credit,
                            movement: movements[i],
                            movementIndex: widget.credit.movements.indexOf(movements[i]),
                          ),
                          if (i != movements.length - 1) Divider(height: 1, color: kredit.borderCard),
                        ],
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

class _MovementTile extends ConsumerWidget {
  final CardCredit credit;
  final CardMovement movement;
  final int movementIndex;

  const _MovementTile({
    required this.credit,
    required this.movement,
    required this.movementIndex,
  });

  Future<bool> _confirmDelete(BuildContext context) async {
    return showAppConfirmSheet(
      context,
      title: 'Eliminar movimiento',
      message: '¿Eliminar "${_labelFor(movement.type)}" por ${formatCOP(movement.amount)}? El saldo de la tarjeta se recalculará. Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      isDanger: true,
      icon: Icons.delete_outline,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    final m = movement;
    final isCredit = m.type == CardMovementType.payment;
    final accent = Theme.of(context).colorScheme.primary;

    final purchase = m.installmentPurchaseId == null
        ? null
        : credit.installmentPurchases.where((p) => p.id == m.installmentPurchaseId).firstOrNull;

    // Payments (money coming off the balance) get the accent color +
    // downward arrow; charges/interest/fees (money added to the balance)
    // share a neutral upward treatment so the sign of each line is legible
    // without reading the amount text.
    return Dismissible(
      key: ValueKey('card-movement-$movementIndex-${m.date}-${m.amount}-${m.type}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref.read(creditsProvider.notifier).deleteMovement(credit.id, movementIndex);
          messenger.showSnackBar(
            const SnackBar(content: Text('Movimiento eliminado')),
          );
        } catch (e) {
          debugPrint('deleteMovement failed: $e');
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudo eliminar el movimiento.')),
          );
        }
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
      ),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // Texto plano, sin ícono — mismo lenguaje visual que la lista de
      // cuotas proyectadas de un extracto futuro (ver _StatementCard),
      // en vez del tratamiento "más grande" con ícono que tenía antes.
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchase != null
                      ? (purchase.note.isNotEmpty ? purchase.note : _labelFor(m.type))
                      : (m.note.isNotEmpty ? m.note : _labelFor(m.type)),
                  style: TextStyle(fontSize: AppTextSize.body, color: kredit.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (purchase != null)
                  Text(
                    '${m.installmentIndex ?? purchase.installmentsBilled}/${purchase.installments}',
                    style: TextStyle(fontSize: AppTextSize.caption, color: kredit.textTertiary),
                  )
                else if (m.type == CardMovementType.charge && m.chargeInstallments != null && m.chargeInstallments! > 1)
                  Text(
                    '${m.chargeInstallments} cuotas',
                    style: TextStyle(fontSize: AppTextSize.caption, color: kredit.textTertiary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isCredit ? '-' : '+'}${formatCOP(m.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.body,
              color: isCredit ? accent : kredit.textPrimary,
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _labelFor(String type) {
    switch (type) {
      case CardMovementType.payment:
        return 'Pago';
      case CardMovementType.interest:
        return 'Interés';
      case CardMovementType.fee:
        return 'Cuota de mantenimiento';
      default:
        return 'Cargo/Compra';
    }
  }
}
