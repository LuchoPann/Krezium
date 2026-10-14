/// Proporción aportado/objetivo, sin acotar a 1.0 — una meta puede llegar a
/// más del 100% si el usuario sigue aportando tras cumplirla.
double progresoMeta({required double aportado, required double objetivo}) {
  if (objetivo <= 0) return 0;
  return aportado / objetivo;
}

/// Lo que falta por aportar — nunca negativo (una meta ya cumplida no
/// "debe" dinero).
double montoRestanteMeta({required double aportado, required double objetivo}) {
  final restante = objetivo - aportado;
  return restante > 0 ? restante : 0;
}

/// Cuánto aportar por mes, en promedio, para llegar a [fechaLimite]
/// aportando [restante] — es una referencia orientativa, no una obligación.
/// Devuelve null cuando no hay un plazo sobre el cual calcular un ritmo: sin
/// fecha límite, con la fecha ya vencida, o cuando ya no queda nada por
/// aportar.
double? contribucionOrientativa({
  required double restante,
  required DateTime? fechaLimite,
  required DateTime hoy,
}) {
  if (fechaLimite == null) return null;
  if (restante <= 0) return null;
  if (!fechaLimite.isAfter(hoy)) return null;

  final mesesCompletos =
      (fechaLimite.year - hoy.year) * 12 + (fechaLimite.month - hoy.month) - (fechaLimite.day < hoy.day ? 1 : 0);
  final meses = mesesCompletos > 0 ? mesesCompletos : 1;
  return (restante / meses * 100).ceilToDouble() / 100;
}

/// Un aporte a una meta siempre debe sumar dinero real, nunca cero ni
/// negativo.
bool puedeAportar(double monto) => monto > 0;

/// Un retiro nunca puede sacar más de lo que la meta tiene aportado — eso
/// liberaría dinero que nunca estuvo reservado.
bool puedeRetirar({required double monto, required double aportado}) =>
    monto > 0 && monto <= aportado;
