import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_budget.dart';

FinanceTransaction _gasto(String categoryId, double monto) => FinanceTransaction(
      id: 't-$categoryId-$monto',
      accountId: 'A',
      categoryId: categoryId,
      tipo: 'gasto',
      monto: monto,
      fecha: '2026-10-01',
      nota: '',
      esRecurrente: false,
    );

FinanceTransaction _gastoEn(String categoryId, double monto, String fecha) => FinanceTransaction(
      id: 't-$categoryId-$monto-$fecha',
      accountId: 'A',
      categoryId: categoryId,
      tipo: 'gasto',
      monto: monto,
      fecha: fecha,
      nota: '',
      esRecurrente: false,
    );

void main() {
  group('gastoCategoriaPeriodo', () {
    test('suma gastos con el mismo categoryId que el presupuesto (padre)', () {
      final txs = [_gasto('cat_alimentacion_padre', 100), _gasto('cat_alimentacion_padre', 50)];
      expect(
        gastoCategoriaPeriodo(categoryId: 'cat_alimentacion_padre', transacciones: txs, parentPorCategoria: {}),
        150,
      );
    });

    test('suma también gastos de subcategorías cuyo padre es el presupuesto', () {
      final txs = [_gasto('restaurante', 80), _gasto('supermercado', 40)];
      final parentPorCategoria = {'restaurante': 'cat_alimentacion_padre', 'supermercado': 'cat_alimentacion_padre'};
      expect(
        gastoCategoriaPeriodo(categoryId: 'cat_alimentacion_padre', transacciones: txs, parentPorCategoria: parentPorCategoria),
        120,
      );
    });

    test('ignora gastos de categorías no relacionadas', () {
      final txs = [_gasto('transporte', 80)];
      final parentPorCategoria = {'transporte': 'cat_transporte_padre'};
      expect(
        gastoCategoriaPeriodo(categoryId: 'cat_alimentacion_padre', transacciones: txs, parentPorCategoria: parentPorCategoria),
        0,
      );
    });

    test('ignora ingresos y transferencias aunque compartan categoryId', () {
      final txs = [
        FinanceTransaction(
          id: 'i1',
          accountId: 'A',
          categoryId: 'cat_alimentacion_padre',
          tipo: 'ingreso',
          monto: 500,
          fecha: '2026-10-01',
          nota: '',
          esRecurrente: false,
        ),
      ];
      expect(
        gastoCategoriaPeriodo(categoryId: 'cat_alimentacion_padre', transacciones: txs, parentPorCategoria: {}),
        0,
      );
    });
  });

  group('progresoPresupuesto', () {
    test('límite en 0 no divide por cero', () {
      expect(progresoPresupuesto(gasto: 100, limite: 0), 0);
    });

    test('calcula la proporción sin clamp (permite superar 1.0)', () {
      expect(progresoPresupuesto(gasto: 150, limite: 100), 1.5);
    });
  });

  group('estadoPresupuesto', () {
    test('menos del 80% es normal', () {
      expect(estadoPresupuesto(0.5), EstadoPresupuesto.normal);
    });

    test('80% o más y menos de 100% es cercano', () {
      expect(estadoPresupuesto(0.8), EstadoPresupuesto.cercano);
      expect(estadoPresupuesto(0.99), EstadoPresupuesto.cercano);
    });

    test('100% o más es agotado (incluye excedido)', () {
      expect(estadoPresupuesto(1.0), EstadoPresupuesto.agotado);
      expect(estadoPresupuesto(1.5), EstadoPresupuesto.agotado);
    });
  });

  group('saldoPresupuesto', () {
    test('resta el gasto del límite, puede ser negativo si se excede', () {
      expect(saldoPresupuesto(limite: 100, gasto: 40), 60);
      expect(saldoPresupuesto(limite: 100, gasto: 140), -40);
    });
  });

  group('sugerenciaPresupuesto', () {
    test('sugiere la mediana de 3 meses cuando al menos 2 tienen gasto', () {
      final hoy = DateTime(2026, 10, 15);
      final txs = [
        _gastoEn('comida', 100000, '2026-07-10'),
        _gastoEn('comida', 200000, '2026-08-10'),
        // septiembre sin gasto
      ];
      final r = sugerenciaPresupuesto(
        categoryId: 'comida',
        transacciones: txs,
        parentPorCategoria: {},
        hoy: hoy,
      );
      expect(r, isNotNull);
      expect(r!.sugerido, 100000); // mediana de [100000, 200000, 0]
      expect(r.meses, hasLength(3));
    });

    test('no sugiere nada con menos de 2 meses con gasto', () {
      final hoy = DateTime(2026, 10, 15);
      final txs = [_gastoEn('comida', 100000, '2026-08-10')];
      final r = sugerenciaPresupuesto(
        categoryId: 'comida',
        transacciones: txs,
        parentPorCategoria: {},
        hoy: hoy,
      );
      expect(r, isNull);
    });

    test('suma roll-up de subcategorías igual que gastoCategoriaPeriodo', () {
      final hoy = DateTime(2026, 10, 15);
      final txs = [
        _gastoEn('restaurante', 60000, '2026-07-05'),
        _gastoEn('supermercado', 40000, '2026-07-05'),
        _gastoEn('restaurante', 90000, '2026-08-05'),
      ];
      final parentPorCategoria = {
        'restaurante': 'comida',
        'supermercado': 'comida',
      };
      final r = sugerenciaPresupuesto(
        categoryId: 'comida',
        transacciones: txs,
        parentPorCategoria: parentPorCategoria,
        hoy: hoy,
      );
      expect(r, isNotNull);
      expect(r!.sugerido, 90000); // mediana de [100000, 90000, 0]
    });

    test('ignora el mes en curso, solo mira los 3 meses anteriores completos', () {
      final hoy = DateTime(2026, 10, 15);
      final txs = [
        _gastoEn('comida', 500000, '2026-10-01'), // mes en curso, no cuenta
        _gastoEn('comida', 100000, '2026-09-01'),
        _gastoEn('comida', 100000, '2026-08-01'),
      ];
      final r = sugerenciaPresupuesto(
        categoryId: 'comida',
        transacciones: txs,
        parentPorCategoria: {},
        hoy: hoy,
      );
      expect(r, isNotNull);
      expect(r!.sugerido, 100000);
    });
  });

  group('vaRapido', () {
    test('true cuando el consumo supera el tiempo transcurrido por más del margen', () {
      final result = vaRapido(
        progreso: 0.75,
        inicioPeriodo: DateTime(2026, 10, 1),
        finPeriodo: DateTime(2026, 10, 31),
        hoy: DateTime(2026, 10, 10), // ~30% transcurrido
      );
      expect(result, isTrue);
    });

    test('false si va dentro del margen esperado', () {
      final result = vaRapido(
        progreso: 0.35,
        inicioPeriodo: DateTime(2026, 10, 1),
        finPeriodo: DateTime(2026, 10, 31),
        hoy: DateTime(2026, 10, 10), // ~30% transcurrido, margen 0.15
      );
      expect(result, isFalse);
    });

    test('false si ya está agotado (progreso >= 1.0) — esa alerta ya es suficiente', () {
      final result = vaRapido(
        progreso: 1.2,
        inicioPeriodo: DateTime(2026, 10, 1),
        finPeriodo: DateTime(2026, 10, 31),
        hoy: DateTime(2026, 10, 10),
      );
      expect(result, isFalse);
    });
  });
}
