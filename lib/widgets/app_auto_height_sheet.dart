import 'package:flutter/material.dart';
import 'package:krezium/theme/app_theme.dart';

/// Regla estandarizada para bottom sheets de la app: en vez de un
/// `DraggableScrollableSheet` con una fracción inicial fija (ej. 0.7 de la
/// pantalla) que obliga al usuario a arrastrar hacia arriba para ver el
/// resto del contenido (típicamente el botón de confirmar, que quedaba
/// oculto hasta ese gesto manual), este widget deja que el sheet se ajuste
/// a su propio contenido:
/// - Si el contenido es más bajo que el límite, el sheet solo ocupa lo que
///   necesita — nunca sube de más ni deja espacio vacío abajo.
/// - Si el contenido es más alto que el límite (el caso típico), el sheet
///   sube hasta el límite superior (`maxHeightFraction` del alto de
///   pantalla) y el contenido se desplaza/scrollea dentro de ese espacio —
///   el usuario sigue pudiendo bajar más si quiere, pero nunca hace falta
///   ese gesto para ver el final del contenido (ej. el botón "Guardar").
///
/// [child] debe ser un widget "shrinkWrap-friendly": una `ListView` o
/// `Column` con `shrinkWrap: true` (o `mainAxisSize: MainAxisSize.min`) si
/// se espera que el contenido pueda ser más corto que la pantalla; un paso
/// que siempre deba ocupar todo el espacio disponible (ej. una lista larga
/// para buscar/elegir) puede usar `Expanded`/`ListView.builder` normal sin
/// `shrinkWrap` — en ese caso simplemente siempre ocupa el límite completo.
class AppAutoHeightSheet extends StatelessWidget {
  final Widget child;
  final double maxHeightFraction;

  const AppAutoHeightSheet({
    super.key,
    required this.child,
    this.maxHeightFraction = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    // bottom: viewInsets del teclado — sin esto el teclado tapaba campos de
    // más abajo en vez de empujar el sheet hacia arriba.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * maxHeightFraction,
        ),
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tc.borderCard,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
