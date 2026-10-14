import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/domain/finance_observaciones.dart';

void main() {
  group('observacionesAumentoCategoria', () {
    test('sin datos del mes anterior, no genera observación (no hay base comparable)', () {
      final obs = observacionesAumentoCategoria(
        gastoActualPorCategoria: {'cat1': 100000},
        gastoAnteriorPorCategoria: {},
        nombrePorCategoria: {'cat1': 'Alimentación'},
      );
      expect(obs, isEmpty);
    });

    test('aumento por debajo del umbral porcentual no genera observación', () {
      final obs = observacionesAumentoCategoria(
        gastoActualPorCategoria: {'cat1': 110000},
        gastoAnteriorPorCategoria: {'cat1': 100000}, // +10%
        nombrePorCategoria: {'cat1': 'Alimentación'},
      );
      expect(obs, isEmpty);
    });

    test('aumento porcentual grande pero de monto insignificante no genera observación (evita ruido)', () {
      final obs = observacionesAumentoCategoria(
        gastoActualPorCategoria: {'cat1': 3000},
        gastoAnteriorPorCategoria: {'cat1': 1000}, // +200% pero solo $2.000 de diferencia
        nombrePorCategoria: {'cat1': 'Otros'},
      );
      expect(obs, isEmpty);
    });

    test('aumento significativo (porcentaje y monto) genera una observación con los datos crudos', () {
      final obs = observacionesAumentoCategoria(
        gastoActualPorCategoria: {'cat1': 400000},
        gastoAnteriorPorCategoria: {'cat1': 200000}, // +100%, +$200.000
        nombrePorCategoria: {'cat1': 'Transporte'},
      );
      expect(obs, hasLength(1));
      expect(obs.single.tipo, TipoObservacion.aumentoCategoria);
      expect(obs.single.refId, 'cat1');
      expect(obs.single.nombre, 'Transporte');
      expect(obs.single.valorActual, 400000);
      expect(obs.single.valorAnterior, 200000);
      expect(obs.single.deltaPct, 100);
    });

    test('una disminución de gasto nunca genera esta observación', () {
      final obs = observacionesAumentoCategoria(
        gastoActualPorCategoria: {'cat1': 100000},
        gastoAnteriorPorCategoria: {'cat1': 400000},
        nombrePorCategoria: {'cat1': 'Transporte'},
      );
      expect(obs, isEmpty);
    });

    test('ordena de mayor a menor aumento porcentual', () {
      final obs = observacionesAumentoCategoria(
        gastoActualPorCategoria: {'cat1': 300000, 'cat2': 800000},
        gastoAnteriorPorCategoria: {'cat1': 100000, 'cat2': 200000}, // +200% vs +300%
        nombrePorCategoria: {'cat1': 'A', 'cat2': 'B'},
      );
      expect(obs.map((o) => o.refId), ['cat2', 'cat1']);
    });
  });

  group('observacionesPresupuestoCercano', () {
    test('sin presupuestos no genera nada', () {
      expect(observacionesPresupuestoCercano([]), isEmpty);
    });

    test('presupuesto por debajo del 80% no genera observación', () {
      final obs = observacionesPresupuestoCercano([
        (categoryId: 'c1', nombre: 'Alimentación', progreso: 0.5),
      ]);
      expect(obs, isEmpty);
    });

    test('presupuesto cercano (80-99%) genera observación', () {
      final obs = observacionesPresupuestoCercano([
        (categoryId: 'c1', nombre: 'Alimentación', progreso: 0.85),
      ]);
      expect(obs, hasLength(1));
      expect(obs.single.tipo, TipoObservacion.presupuestoCercano);
      expect(obs.single.progreso, 0.85);
    });

    test('presupuesto agotado (>=100%) también genera observación', () {
      final obs = observacionesPresupuestoCercano([
        (categoryId: 'c1', nombre: 'Alimentación', progreso: 1.2),
      ]);
      expect(obs, hasLength(1));
    });

    test('ordena por progreso descendente (lo más urgente primero)', () {
      final obs = observacionesPresupuestoCercano([
        (categoryId: 'c1', nombre: 'A', progreso: 0.85),
        (categoryId: 'c2', nombre: 'B', progreso: 1.3),
      ]);
      expect(obs.map((o) => o.refId), ['c2', 'c1']);
    });
  });

  group('observacionesMetaFueraDeRitmo', () {
    test('meta sin fecha límite no genera observación (no hay ritmo esperado que calcular)', () {
      final obs = observacionesMetaFueraDeRitmo([
        (id: 'g1', nombre: 'Viaje', aportado: 100, objetivo: 1000, creadaEn: DateTime(2026, 1, 1), fechaLimite: null, estado: 'activa'),
      ], hoy: DateTime(2026, 6, 1));
      expect(obs, isEmpty);
    });

    test('meta al día o adelantada no genera observación', () {
      // 6 de 12 meses transcurridos (50%), con 60% aportado: va adelantada.
      final obs = observacionesMetaFueraDeRitmo([
        (id: 'g1', nombre: 'Viaje', aportado: 600, objetivo: 1000, creadaEn: DateTime(2026, 1, 1), fechaLimite: DateTime(2027, 1, 1), estado: 'activa'),
      ], hoy: DateTime(2026, 7, 1));
      expect(obs, isEmpty);
    });

    test('meta notablemente rezagada genera observación', () {
      // 6 de 12 meses transcurridos (50% esperado), solo 10% aportado.
      final obs = observacionesMetaFueraDeRitmo([
        (id: 'g1', nombre: 'Viaje', aportado: 100, objetivo: 1000, creadaEn: DateTime(2026, 1, 1), fechaLimite: DateTime(2027, 1, 1), estado: 'activa'),
      ], hoy: DateTime(2026, 7, 1));
      expect(obs, hasLength(1));
      expect(obs.single.tipo, TipoObservacion.metaFueraDeRitmo);
      expect(obs.single.refId, 'g1');
      expect(obs.single.valorActual, closeTo(0.1, 0.001));
      expect(obs.single.valorAnterior, closeTo(0.5, 0.01));
    });

    test('meta ya cumplida no genera observación aunque la fecha límite ya haya pasado', () {
      final obs = observacionesMetaFueraDeRitmo([
        (id: 'g1', nombre: 'Viaje', aportado: 1000, objetivo: 1000, creadaEn: DateTime(2026, 1, 1), fechaLimite: DateTime(2026, 2, 1), estado: 'activa'),
      ], hoy: DateTime(2026, 7, 1));
      expect(obs, isEmpty);
    });

    test('meta pausada o cancelada no genera observación', () {
      final obs = observacionesMetaFueraDeRitmo([
        (id: 'g1', nombre: 'Viaje', aportado: 100, objetivo: 1000, creadaEn: DateTime(2026, 1, 1), fechaLimite: DateTime(2027, 1, 1), estado: 'pausada'),
      ], hoy: DateTime(2026, 7, 1));
      expect(obs, isEmpty);
    });
  });
}
