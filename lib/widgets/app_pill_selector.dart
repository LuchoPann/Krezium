import 'package:flutter/material.dart';
import 'package:krezium/theme/app_theme.dart';

/// Una opción dentro de [AppPillSelector]. [color] es opcional — si se omite,
/// el segmento seleccionado usa el acento de la app (`colorScheme.primary`)
/// en vez de un color semántico propio (como verde/rojo para ingreso/gasto).
class PillOption<T> {
  final T value;
  final String label;
  final Color? color;

  const PillOption({required this.value, required this.label, this.color});
}

/// Selector horizontal tipo píldora: contenedor redondeado con borde sutil,
/// el segmento activo recibe un fondo tenue de su color + texto en ese color;
/// los inactivos quedan en texto plano sin fondo ni ícono. Reemplaza el uso
/// de `SegmentedButton` (con bordes, íconos y relleno sólido) en toda la app
/// — un único componente visual para "elegir una de N opciones en una fila"
/// en Créditos y Finanzas.
class AppPillSelector<T> extends StatelessWidget {
  final List<PillOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const AppPillSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tc.bgCard,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: tc.borderCard),
      ),
      child: Row(
        children: [
          for (final opcion in options)
            Expanded(
              child: _Segmento(
                label: opcion.label,
                selected: opcion.value == value,
                color: opcion.color ?? accent,
                tc: tc,
                onTap: () => onChanged(opcion.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segmento extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final AppThemeColors tc;
  final VoidCallback onTap;

  const _Segmento({
    required this.label,
    required this.selected,
    required this.color,
    required this.tc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w700,
              color: selected ? color : tc.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
