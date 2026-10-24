import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_ledger.dart';

FinanceReservationRow _reserva(
  double monto, {
  String estado = 'activa',
  String? accountId = 'A',
  String modalidad = 'vinculada',
}) => FinanceReservationRow(
      id: 'r-$monto-$estado',
      accountId: accountId,
      nombre: 'meta',
      monto: monto,
      creadaEn: '2026-10-01',
      montoObjetivo: monto,
      estado: estado,
      modalidad: modalidad,
    );

FinanceTransaction _tx({
  required String accountId,
  required String tipo,
  required double monto,
  String? transferToAccountId,
}) => FinanceTransaction(
      id: 't-$accountId-$tipo-$monto',
      accountId: accountId,
      categoryId: 'cat',
      tipo: tipo,
      monto: monto,
      fecha: '2026-10-01',
      nota: '',
      esRecurrente: false,
      transferToAccountId: transferToAccountId,
    );

void main() {
  group('signedEffectForLibro', () {
    test('ingreso en el propio libro suma', () {
      final t = _tx(accountId: 'A', tipo: 'ingreso', monto: 100);
      expect(signedEffectForLibro(t, 'A'), 100);
    });

    test('gasto en el propio libro resta', () {
      final t = _tx(accountId: 'A', tipo: 'gasto', monto: 50);
      expect(signedEffectForLibro(t, 'A'), -50);
    });

    test('transferencia: resta en el origen', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 30, transferToAccountId: 'B');
      expect(signedEffectForLibro(t, 'A'), -30);
    });

    test('transferencia: suma en el destino', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 30, transferToAccountId: 'B');
      expect(signedEffectForLibro(t, 'B'), 30);
    });

    test('transferencia sin destino no afecta ningún otro libro', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 30);
      expect(signedEffectForLibro(t, 'B'), 0);
    });

    test('autotransferencia (origen == destino) no tiene efecto', () {
      final t = _tx(accountId: 'A', tipo: 'transferencia', monto: 75, transferToAccountId: 'A');
      expect(signedEffectForLibro(t, 'A'), 0);
    });

    test('transacción de otro libro no afecta', () {
      final t = _tx(accountId: 'A', tipo: 'ingreso', monto: 100);
      expect(signedEffectForLibro(t, 'Z'), 0);
    });

    test('meta_aporte: resta del saldo del registro de origen', () {
      final t = _tx(accountId: 'A', tipo: 'meta_aporte', monto: 20);
      expect(signedEffectForLibro(t, 'A'), -20);
    });

    test('meta_aporte: no afecta a otro registro', () {
      final t = _tx(accountId: 'A', tipo: 'meta_aporte', monto: 20);
      expect(signedEffectForLibro(t, 'B'), 0);
    });

    test('meta_retiro: suma de vuelta al saldo del registro', () {
      final t = _tx(accountId: 'A', tipo: 'meta_retiro', monto: 20);
      expect(signedEffectForLibro(t, 'A'), 20);
    });

    test('meta_retiro: no afecta a otro registro', () {
      final t = _tx(accountId: 'A', tipo: 'meta_retiro', monto: 20);
      expect(signedEffectForLibro(t, 'B'), 0);
    });
  });

  group('calcularSaldo', () {
    test('saldo inicial más efectos de todas las transacciones involucradas', () {
      final txs = [
        _tx(accountId: 'A', tipo: 'ingreso', monto: 200),
        _tx(accountId: 'A', tipo: 'gasto', monto: 50),
        _tx(accountId: 'A', tipo: 'transferencia', monto: 30, transferToAccountId: 'B'),
        _tx(accountId: 'C', tipo: 'transferencia', monto: 500, transferToAccountId: 'A'),
      ];
      final saldo = calcularSaldo(saldoInicial: 100, txsInvolucradas: txs, libroId: 'A');
      expect(saldo, 100 + 200 - 50 - 30 + 500);
    });
  });

  group('calcularIngresosGastos', () {
    test('una transferencia no cuenta como ingreso ni como gasto', () {
      final txs = [
        _tx(accountId: 'A', tipo: 'ingreso', monto: 100),
        _tx(accountId: 'A', tipo: 'gasto', monto: 40),
        _tx(accountId: 'A', tipo: 'transferencia', monto: 999, transferToAccountId: 'B'),
        _tx(accountId: 'B', tipo: 'transferencia', monto: 999, transferToAccountId: 'A'),
      ];
      final r = calcularIngresosGastos(txs, 'A');
      expect(r.ingresos, 100);
      expect(r.gastos, 40);
    });

    test('aportes/retiros de metas no cuentan como ingreso ni como gasto', () {
      final txs = [
        _tx(accountId: 'A', tipo: 'ingreso', monto: 100),
        _tx(accountId: 'A', tipo: 'meta_aporte', monto: 20),
        _tx(accountId: 'A', tipo: 'meta_retiro', monto: 5),
      ];
      final r = calcularIngresosGastos(txs, 'A');
      expect(r.ingresos, 100);
      expect(r.gastos, 0);
    });
  });

  group('esTransferenciaValida', () {
    test('origen y destino distintos y presentes: válida', () {
      expect(esTransferenciaValida(origenId: 'A', destinoId: 'B'), true);
    });
    test('origen igual a destino: inválida', () {
      expect(esTransferenciaValida(origenId: 'A', destinoId: 'A'), false);
    });
    test('destino nulo: inválida', () {
      expect(esTransferenciaValida(origenId: 'A', destinoId: null), false);
    });
    test('origen nulo: inválida', () {
      expect(esTransferenciaValida(origenId: null, destinoId: 'B'), false);
    });
  });

  group('totalReservado', () {
    test('suma reservas activas y pausadas', () {
      final reservas = [_reserva(100), _reserva(50, estado: 'pausada')];
      expect(totalReservado(reservas), 150);
    });

    test('las metas finalizadas siguen contando como reservadas hasta que el usuario retire el dinero', () {
      final reservas = [_reserva(100, estado: 'finalizada')];
      expect(totalReservado(reservas), 100);
    });

    test('las metas canceladas liberan el dinero: no cuentan como reservado', () {
      final reservas = [_reserva(100), _reserva(80, estado: 'cancelada')];
      expect(totalReservado(reservas), 100);
    });
  });

  group('calcularDisponibleEstimado', () {
    test('sin reservas, disponible == saldo', () {
      final r = calcularDisponibleEstimado(saldo: 500, reservado: 0);
      expect(r.disponibleEstimado, 500);
      expect(r.reservasExcedenSaldo, false);
    });

    test('con reservas, se descuentan del saldo', () {
      final r = calcularDisponibleEstimado(saldo: 500, reservado: 150);
      expect(r.disponibleEstimado, 350);
      expect(r.reservasExcedenSaldo, false);
    });

    test('reservas que exceden el saldo: no se oculta, se señala', () {
      final r = calcularDisponibleEstimado(saldo: 100, reservado: 300);
      expect(r.disponibleEstimado, -200);
      expect(r.reservasExcedenSaldo, true);
    });

    test('saldo negativo sin reservas no se marca como reservas excedidas', () {
      final r = calcularDisponibleEstimado(saldo: -50, reservado: 0);
      expect(r.disponibleEstimado, -50);
      expect(r.reservasExcedenSaldo, false);
    });

    test('reservado igual al saldo: disponible en cero y no se marca como excedido', () {
      final r = calcularDisponibleEstimado(saldo: 200, reservado: 200);
      expect(r.disponibleEstimado, 0);
      expect(r.reservasExcedenSaldo, false);
    });
  });

  group('comparacionPeriodoAnterior', () {
    test('sin datos en el periodo anterior, no hay comparación posible', () {
      expect(comparacionPeriodoAnterior(actual: 100, anterior: 0), null);
    });

    test('calcula el delta porcentual cuando hay base comparable', () {
      final r = comparacionPeriodoAnterior(actual: 150, anterior: 100);
      expect(r!.deltaPct, 50);
    });

    test('delta negativo cuando el actual es menor', () {
      final r = comparacionPeriodoAnterior(actual: 50, anterior: 100);
      expect(r!.deltaPct, -50);
    });
  });

  group('observacionPeriodo', () {
    test('sin ingresos ni gastos: no hay observación', () {
      expect(observacionPeriodo(ingresos: 0, gastos: 0), isNull);
    });

    test('ingresos superan gastos: observación con el porcentaje de diferencia', () {
      final obs = observacionPeriodo(ingresos: 1000, gastos: 500);
      expect(obs, contains('ingresos'));
      expect(obs, contains('100%'));
    });

    test('gastos superan ingresos: observación con el porcentaje de diferencia', () {
      final obs = observacionPeriodo(ingresos: 400, gastos: 500);
      expect(obs, contains('gastos'));
      expect(obs, contains('25%'));
    });

    test('ingresos y gastos iguales (y mayores a cero): observación de equilibrio sin porcentaje', () {
      final obs = observacionPeriodo(ingresos: 300, gastos: 300);
      expect(obs, isNotNull);
      expect(obs, isNot(contains('%')));
    });

    test('solo ingresos, sin gastos registrados: no divide por cero, da una observación simple', () {
      final obs = observacionPeriodo(ingresos: 200, gastos: 0);
      expect(obs, isNotNull);
      expect(obs, isNot(contains('%')));
    });

    test('solo gastos, sin ingresos registrados: no divide por cero, da una observación simple', () {
      final obs = observacionPeriodo(ingresos: 0, gastos: 200);
      expect(obs, isNotNull);
      expect(obs, isNot(contains('%')));
    });
  });

  group('totalReservadoVirtual', () {
    test('suma solo reservas virtuales activas/pausadas', () {
      final reservas = [
        _reserva(500, accountId: null, modalidad: 'virtual', estado: 'activa'),
        _reserva(300, accountId: null, modalidad: 'virtual', estado: 'cancelada'),
        _reserva(100, accountId: 'cta1', modalidad: 'vinculada', estado: 'activa'),
      ];
      expect(totalReservadoVirtual(reservas), 500);
    });

    test('incluye pausadas, nunca canceladas', () {
      final reservas = [
        _reserva(200, accountId: null, modalidad: 'virtual', estado: 'pausada'),
      ];
      expect(totalReservadoVirtual(reservas), 200);
    });

    test('lista vacía da 0', () {
      expect(totalReservadoVirtual([]), 0);
    });
  });

  group('tasaAhorro', () {
    test('porcentaje de ingresos que no se gastó', () {
      expect(tasaAhorro(ingresos: 1000, gastos: 700), 0.3);
    });

    test('negativa cuando los gastos superan los ingresos — se muestra tal cual, sin clamp', () {
      expect(tasaAhorro(ingresos: 100, gastos: 150), -0.5);
    });

    test('100% cuando no hubo ningún gasto', () {
      expect(tasaAhorro(ingresos: 500, gastos: 0), 1.0);
    });

    test('null sin ingresos registrados — no hay base, no un 0% engañoso', () {
      expect(tasaAhorro(ingresos: 0, gastos: 200), isNull);
      expect(tasaAhorro(ingresos: 0, gastos: 0), isNull);
    });
  });
}
