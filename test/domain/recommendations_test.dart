import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/card_statement_engine.dart';
import 'package:krezium/domain/date_utils.dart';
import 'package:krezium/domain/loan_calculator.dart';
import 'package:krezium/domain/recommendations.dart';

void main() {
  group('buildPendingPayments', () {
    test('orders payments by urgency with overdue items first', () {
      final ref = DateTime(2026, 1, 10);
      final overdue = _loan(
        id: 'overdue',
        name: 'Cupo vencido',
        dueDate: '2026-01-08',
        amount: 100000,
      );
      final upcomingLarge = _loan(
        id: 'large',
        name: 'Pago grande',
        dueDate: '2026-01-12',
        amount: 900000,
      );

      final payments = buildPendingPayments(
        [upcomingLarge, overdue],
        now: ref,
      );

      expect(payments.first.credit.id, 'overdue');
      expect(payments.last.credit.id, 'large');
    });
  });

  group('buildPaymentWeekSummary', () {
    test('counts overdue, today and next 7 days totals', () {
      final ref = DateTime(2026, 1, 10);
      final payments = buildPendingPayments(
        [
          _loan(id: 'a', dueDate: '2026-01-09', amount: 100000),
          _loan(id: 'b', dueDate: '2026-01-10', amount: 200000),
          _loan(id: 'c', dueDate: '2026-01-14', amount: 300000),
        ],
        now: ref,
      );

      final summary = buildPaymentWeekSummary(payments, now: ref);

      expect(summary.overdueCount, 1);
      expect(summary.dueTodayCount, 1);
      expect(summary.dueSoonCount, 1);
      expect(summary.dueWithin7Days, 600000);
      expect(summary.nextPayment?.credit.id, 'a');
    });
  });

  group('buildPrimaryRecommendation', () {
    test('returns calm state when there are no pending payments', () {
      final loan = _loan(id: 'paid', dueDate: '2026-01-10', amount: 100000);
      loan.installments.first.paid = true;

      final recommendation = buildPrimaryRecommendation([loan]);

      expect(recommendation.severity, RecommendationSeverity.calm);
      expect(recommendation.payment, isNull);
    });

    test('prioritizes overdue payments as danger', () {
      final recommendation = buildPrimaryRecommendation(
        [
          _loan(id: 'loan', name: 'Cupo personal', dueDate: '2026-01-08'),
        ],
        now: DateTime(2026, 1, 10),
      );

      expect(recommendation.severity, RecommendationSeverity.danger);
      expect(recommendation.payment?.credit.name, 'Cupo personal');
    });
  });

  group('buildRiskRecommendations', () {
    test('flags debt concentration when one lender dominates', () {
      final big = _loan(id: 'big', name: 'Prestamo grande', amount: 900000);
      final small = _loan(id: 'small', name: 'Prestamo chico', amount: 100000);

      final risks = buildRiskRecommendations([big, small]);

      expect(risks.any((r) => r.title == 'Deuda concentrada'), isTrue);
    });

    test('does not flag concentration when debt is balanced', () {
      final a = _loan(id: 'a', amount: 500000);
      final b = _loan(id: 'b', amount: 500000);

      final risks = buildRiskRecommendations([a, b]);

      expect(risks.any((r) => r.title == 'Deuda concentrada'), isFalse);
    });

    test('flags a card near its limit', () {
      final card = CardCredit(
        id: 'card',
        name: 'Tarjeta',
        lender: 'Banco',
        creditLimit: 1000000,
        currentBalance: 900000,
      );

      final risks = buildRiskRecommendations([card]);

      expect(risks.any((r) => r.title == 'Cupo casi agotado'), isTrue);
    });

    test('returns no risks for a single healthy loan', () {
      final loan = _loan(id: 'only', amount: 100000, dueDate: '2026-01-10');

      expect(
        buildRiskRecommendations([loan], now: DateTime(2026, 1, 5)),
        isEmpty,
      );
    });

    test('flags a single loan overdue 30-59 days as warning', () {
      final loan = _loan(id: 'stale', name: 'Cupo viejo', dueDate: '2026-01-01');

      final risks = buildRiskRecommendations([loan], now: DateTime(2026, 2, 5));
      final mora = risks.firstWhere((r) => r.title == 'Mora acumulada');

      expect(mora.severity, RecommendationSeverity.warning);
    });

    test('flags a single loan overdue 60+ days as danger', () {
      final loan = _loan(id: 'stale', name: 'Cupo muy viejo', dueDate: '2026-01-01');

      final risks = buildRiskRecommendations([loan], now: DateTime(2026, 3, 15));
      final mora = risks.firstWhere((r) => r.title == 'Mora acumulada');

      expect(mora.severity, RecommendationSeverity.danger);
    });

    test('flags 2 credits overdue at once as warning', () {
      final a = _loan(id: 'a', dueDate: '2026-01-05');
      final b = _loan(id: 'b', dueDate: '2026-01-06');

      final risks = buildRiskRecommendations([a, b], now: DateTime(2026, 1, 10));
      final mora = risks.firstWhere((r) => r.title == 'Mora acumulada');

      expect(mora.severity, RecommendationSeverity.warning);
    });

    test('flags 3+ credits overdue at once as danger', () {
      final a = _loan(id: 'a', dueDate: '2026-01-05');
      final b = _loan(id: 'b', dueDate: '2026-01-06');
      final c = _loan(id: 'c', dueDate: '2026-01-07');

      final risks = buildRiskRecommendations([a, b, c], now: DateTime(2026, 1, 10));
      final mora = risks.firstWhere((r) => r.title == 'Mora acumulada');

      expect(mora.severity, RecommendationSeverity.danger);
    });

    test('does not flag mora for a single recently overdue payment', () {
      final loan = _loan(id: 'a', dueDate: '2026-01-08');

      final risks = buildRiskRecommendations([loan], now: DateTime(2026, 1, 10));

      expect(risks.any((r) => r.title == 'Mora acumulada'), isFalse);
    });

    test('flags the costliest loan when its rate dwarfs the others', () {
      final expensive = _loan(id: 'exp', name: 'Gota a gota', interestRate: 90);
      final cheap1 = _loan(id: 'c1', name: 'Banco A', interestRate: 15);
      final cheap2 = _loan(id: 'c2', name: 'Banco B', interestRate: 18);

      final risks = buildRiskRecommendations([expensive, cheap1, cheap2]);

      expect(risks.any((r) => r.title == 'Deuda mas costosa'), isTrue);
    });

    test('does not flag costliest when rates are similar', () {
      final a = _loan(id: 'a', interestRate: 20);
      final b = _loan(id: 'b', interestRate: 22);

      expect(
        buildRiskRecommendations([a, b]).any((r) => r.title == 'Deuda mas costosa'),
        isFalse,
      );
    });
  });

  group('effectiveAnnualRate', () {
    test('returns 0 for a credit without an interest rate', () {
      expect(effectiveAnnualRate(_loan(id: 'a', interestRate: 0)), 0);
    });

    test('returns a positive annualized rate for a loan with E.A. rate', () {
      final rate = effectiveAnnualRate(_loan(id: 'a', interestRate: 24));
      expect(rate, closeTo(24, 0.5));
    });
  });

  group('buildBestPrepaymentRecommendation', () {
    test('returns null with fewer than two active loans', () {
      expect(buildBestPrepaymentRecommendation([_loan(id: 'a', interestRate: 20)]), isNull);
    });

    test('picks the loan with the highest effective annual rate', () {
      final expensive = _loan(id: 'exp', name: 'Gota a gota', interestRate: 90);
      final cheap = _loan(id: 'cheap', name: 'Banco A', interestRate: 15);

      final rec = buildBestPrepaymentRecommendation([expensive, cheap]);

      expect(rec, isNotNull);
      expect(rec!.description, contains('Gota a gota'));
    });

    test('ignores fully paid loans', () {
      final expensive = _loan(id: 'exp', name: 'Gota a gota', interestRate: 90);
      expensive.installments.first.paid = true;
      final cheap = _loan(id: 'cheap', name: 'Banco A', interestRate: 15);

      final rec = buildBestPrepaymentRecommendation([expensive, cheap]);

      expect(rec, isNull);
    });
  });

  group('diasHastaProximoPago', () {
    test('usa daysUntilDue de nextPayment cuando existe (extracto exigible o cuota)', () {
      final ref = DateTime(2026, 1, 10);
      final loan = _loan(id: 'l1', dueDate: '2026-01-15');
      final payment = buildPendingPayments([loan], now: ref).single;

      expect(diasHastaProximoPago(loan, payment, ref), 5);
    });

    test('tarjeta sin extracto exigible: cuenta hasta la fecha límite '
        'proyectada del ciclo abierto, no se queda en null', () {
      final ref = DateTime(2026, 1, 10);
      final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
      final open = ensureOpenStatement(card, ref);

      final dias = diasHastaProximoPago(card, null, ref);

      final esperado = parseDateStr(open.dueDate).difference(ref).inDays;
      expect(dias, esperado);
      expect(dias, isNotNull);
    });

    test('préstamo sin ninguna cuota pendiente: null (nada que contar)', () {
      final loan = _loan(id: 'l1');
      // Todas las cuotas ya pagadas → buildPendingPayments no genera nada.
      final loanPaid = LoanCredit(
        id: loan.id, name: loan.name, lender: loan.lender,
        totalAmount: loan.totalAmount, quotaAmount: loan.quotaAmount,
        totalInstallments: loan.totalInstallments, frequency: loan.frequency,
        startDate: loan.startDate, interestRate: loan.interestRate,
        installments: loan.installments
            .map((i) => i.copyWith(paid: true))
            .toList(),
      );
      expect(diasHastaProximoPago(loanPaid, null), isNull);
    });
  });

  group('encontrarPagoCercano', () {
    test('encuentra el más cercano dentro de la ventana de 6 días', () {
      final ref = DateTime(2026, 1, 10);
      final principal = _loan(id: 'p', dueDate: '2026-01-13'); // en 3 días
      final cercano = _loan(id: 'c', dueDate: '2026-01-16'); // en 6 días, diff=3
      final lejano = _loan(id: 'l', dueDate: '2026-01-30'); // diff grande

      final upcoming = buildPendingPayments([principal, cercano, lejano], now: ref);
      final pPrincipal = upcoming.firstWhere((p) => p.credit.id == 'p');

      final resultado = encontrarPagoCercano(upcoming, pPrincipal, now: ref);

      expect(resultado, isNotNull);
      expect(resultado!.cercano.credit.id, 'c');
    });

    test('ninguno dentro de la ventana: null, no inventa un "cercano" falso', () {
      final ref = DateTime(2026, 1, 10);
      final principal = _loan(id: 'p', dueDate: '2026-01-13');
      final lejano = _loan(id: 'l', dueDate: '2026-02-01');

      final upcoming = buildPendingPayments([principal, lejano], now: ref);
      final pPrincipal = upcoming.firstWhere((p) => p.credit.id == 'p');

      expect(encontrarPagoCercano(upcoming, pPrincipal, now: ref), isNull);
    });

    test('elige el más cercano cuando hay varios candidatos dentro de la ventana', () {
      final ref = DateTime(2026, 1, 10);
      final principal = _loan(id: 'p', dueDate: '2026-01-13'); // 3 días
      final masCercano = _loan(id: 'mc', dueDate: '2026-01-15'); // 5 días, diff=2
      final menosCercano = _loan(id: 'lc', dueDate: '2026-01-18'); // 8 días, diff=5

      final upcoming = buildPendingPayments([principal, masCercano, menosCercano], now: ref);
      final pPrincipal = upcoming.firstWhere((p) => p.credit.id == 'p');

      final resultado = encontrarPagoCercano(upcoming, pPrincipal, now: ref);

      expect(resultado!.cercano.credit.id, 'mc');
    });
  });
}

LoanCredit _loan({
  required String id,
  String name = 'Credito',
  String dueDate = '2026-01-10',
  double amount = 100000,
  double interestRate = 0,
}) {
  return LoanCredit(
    id: id,
    name: name,
    lender: 'Banco',
    totalAmount: amount,
    quotaAmount: amount,
    totalInstallments: 1,
    frequency: CreditFrequency.monthly,
    startDate: dueDate,
    interestRate: interestRate,
    installments: buildLoanInstallments(
      totalAmount: amount,
      totalInstallments: 1,
      quotaAmount: amount,
      frequency: CreditFrequency.monthly,
      startDate: dueDate,
    ),
  );
}
