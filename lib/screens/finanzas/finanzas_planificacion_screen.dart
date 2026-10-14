import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/screens/finanzas/finanzas_metas_screen.dart';
import 'package:krezium/screens/finanzas/finanzas_presupuesto_screen.dart';
import 'package:krezium/widgets/app_pill_selector.dart';

final _planificacionTabProvider = StateProvider<int>((ref) => 0);

/// Un único destino de navegación para Presupuestos y Metas de ahorro, per
/// la arquitectura objetivo del roadmap ("Planificación: presupuestos y
/// metas de ahorro") — no crea una pestaña de navegación nueva, solo agrupa
/// dos pantallas bajo la misma, con un selector tipo píldora entre ambas.
class FinanzasPlanificacionScreen extends ConsumerWidget {
  const FinanzasPlanificacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_planificacionTabProvider);
    return Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: AppPillSelector<int>(
            value: tab,
            onChanged: (v) => ref.read(_planificacionTabProvider.notifier).state = v,
            options: const [
              PillOption(value: 0, label: 'Presupuestos'),
              PillOption(value: 1, label: 'Metas'),
            ],
          ),
        ),
      ),
      body: tab == 0 ? const FinanzasPresupuestoScreen() : const FinanzasMetasScreen(),
      floatingActionButton: tab == 0 ? const PresupuestoFab() : const MetasFab(),
    );
  }
}
