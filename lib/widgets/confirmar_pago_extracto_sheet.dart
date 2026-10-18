import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/card_movement.dart';
import '../data/models/card_statement.dart';
import '../data/models/credit.dart';
import '../domain/card_statement_engine.dart';
import '../domain/date_utils.dart';
import '../providers/credits_provider.dart';
import '../theme/app_theme.dart';
import '../utils/credit_display_utils.dart';

const _mesesEs = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _fechaCorta(DateTime d) => '${d.day} ${_mesesEs[d.month - 1]} ${d.year}';

/// Confirmar el pago de un extracto es solo eso: confirmar — no un
/// formulario. El usuario no escribe nada acá, solo revisa el extracto
/// (de dónde sale, cuánto es, cuándo vence) en un solo lugar y confirma.
/// Si quiere pagar un monto distinto al exigible (pago parcial), ese
/// sigue siendo un caso de "Nueva compra"/ajuste manual, no esta pantalla.
class ConfirmarPagoExtractoSheet extends ConsumerWidget {
  final String creditId;

  const ConfirmarPagoExtractoSheet({super.key, required this.creditId});

  static Future<void> show(BuildContext context, {required String creditId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConfirmarPagoExtractoSheet(creditId: creditId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kredit = Theme.of(context).extension<AppThemeColors>()!;
    final accent = Theme.of(context).colorScheme.primary;

    final credits = ref.watch(creditsProvider).value ?? [];
    final credit = credits.whereType<CardCredit>().where((c) => c.id == creditId).firstOrNull;

    if (credit == null) return const SizedBox.shrink();

    final unpaidClosed = credit.statements
        .where((s) => s.status == CardStatementStatus.closed)
        .toList()
      ..sort((a, b) => a.cutoffDate.compareTo(b.cutoffDate));
    final summary = getPayableSummary(credit);
    final monto = summary.exigible;
    final statement = unpaidClosed.firstOrNull;
    final cutoffLabel = statement != null ? _fechaCorta(parseDateStr(statement.cutoffDate)) : null;
    final dueLabel = summary.dueDate != null ? _fechaCorta(summary.dueDate!) : null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: kredit.borderCard,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Confirmar pago',
                  style: TextStyle(
                    fontSize: AppTextSize.heading,
                    fontWeight: FontWeight.w700,
                    color: kredit.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Revisa el extracto antes de confirmar — este monto no se puede editar acá.',
                  style: TextStyle(fontSize: AppTextSize.body, color: kredit.textTertiary),
                ),
                const SizedBox(height: 16),
                // ── Detalle del extracto, de solo lectura ──────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kredit.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kredit.borderCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        credit.name,
                        style: TextStyle(fontSize: AppTextSize.body, color: kredit.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCOP(monto),
                        style: TextStyle(
                          fontSize: AppTextSize.emphasis,
                          fontWeight: FontWeight.w800,
                          color: kredit.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: kredit.borderCard),
                      const SizedBox(height: 12),
                      _FilaDetalle(
                        label: 'Extracto cerrado el',
                        valor: cutoffLabel ?? '—',
                        kredit: kredit,
                      ),
                      const SizedBox(height: 8),
                      _FilaDetalle(
                        label: 'Fecha límite de pago',
                        valor: dueLabel ?? '—',
                        kredit: kredit,
                        destacado: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: accent,
                      foregroundColor: legibleForegroundOn(accent),
                    ),
                    onPressed: monto > 0
                        ? () => _confirmar(context, ref, credit, monto)
                        : null,
                    child: const Text('Confirmar pago'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmar(
    BuildContext context,
    WidgetRef ref,
    CardCredit credit,
    double monto,
  ) async {
    HapticFeedback.mediumImpact();
    await ref.read(creditsProvider.notifier).registerMovement(
          credit.id,
          CardMovementType.payment,
          monto,
          'Extracto confirmado como pagado',
        );
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago confirmado')),
      );
    }
  }
}

class _FilaDetalle extends StatelessWidget {
  final String label;
  final String valor;
  final AppThemeColors kredit;
  final bool destacado;

  const _FilaDetalle({
    required this.label,
    required this.valor,
    required this.kredit,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: AppTextSize.body, color: kredit.textSecondary)),
        Text(
          valor,
          style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
            color: destacado ? kredit.textPrimary : kredit.textSecondary,
          ),
        ),
      ],
    );
  }
}
