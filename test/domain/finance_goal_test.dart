import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/domain/finance_goal.dart';

void main() {
  group('progresoMeta', () {
    test('objetivo en 0 no divide por cero', () {
      expect(progresoMeta(aportado: 50, objetivo: 0), 0);
    });

    test('calcula la proporción sin clamp (permite superar 1.0)', () {
      expect(progresoMeta(aportado: 150, objetivo: 100), 1.5);
    });
  });

  group('montoRestanteMeta', () {
    test('resta lo aportado del objetivo, nunca negativo (ya se cumplió)', () {
      expect(montoRestanteMeta(aportado: 40, objetivo: 100), 60);
      expect(montoRestanteMeta(aportado: 140, objetivo: 100), 0);
    });
  });

  group('contribucionOrientativa', () {
    test('null sin fecha límite — no hay plazo para calcular un ritmo', () {
      expect(
        contribucionOrientativa(restante: 300, fechaLimite: null, hoy: DateTime(2026, 10, 1)),
        null,
      );
    });

    test('null si la fecha límite ya pasó — no hay meses futuros sobre los que repartir', () {
      expect(
        contribucionOrientativa(
          restante: 300,
          fechaLimite: DateTime(2026, 9, 1),
          hoy: DateTime(2026, 10, 1),
        ),
        null,
      );
    });

    test('null si ya no queda nada por aportar', () {
      expect(
        contribucionOrientativa(restante: 0, fechaLimite: DateTime(2026, 12, 1), hoy: DateTime(2026, 10, 1)),
        null,
      );
    });

    test('reparte lo restante entre los meses completos que faltan, redondeando hacia arriba', () {
      // 2026-10-01 -> 2027-01-01 son 3 meses completos.
      final c = contribucionOrientativa(
        restante: 300,
        fechaLimite: DateTime(2027, 1, 1),
        hoy: DateTime(2026, 10, 1),
      );
      expect(c, 100);
    });

    test('si falta menos de un mes completo, igual pide el resto en 1 cuota', () {
      final c = contribucionOrientativa(
        restante: 90,
        fechaLimite: DateTime(2026, 10, 15),
        hoy: DateTime(2026, 10, 1),
      );
      expect(c, 90);
    });
  });

  group('puedeAportar / puedeRetirar', () {
    test('un aporte debe ser positivo', () {
      expect(puedeAportar(100), isTrue);
      expect(puedeAportar(0), isFalse);
      expect(puedeAportar(-10), isFalse);
    });

    test('un retiro no puede superar lo aportado hasta ahora', () {
      expect(puedeRetirar(monto: 50, aportado: 100), isTrue);
      expect(puedeRetirar(monto: 100, aportado: 100), isTrue);
      expect(puedeRetirar(monto: 101, aportado: 100), isFalse);
    });

    test('un retiro debe ser positivo', () {
      expect(puedeRetirar(monto: 0, aportado: 100), isFalse);
      expect(puedeRetirar(monto: -5, aportado: 100), isFalse);
    });
  });
}
