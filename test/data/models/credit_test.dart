import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';

void main() {
  group('CardCredit closedStatements', () {
    test('defaults to empty list', () {
      final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank');
      expect(card.closedStatements, isEmpty);
    });

    test('toJson/fromJson round-trips closedStatements', () {
      final card = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        closedStatements: [
          const CardStatement(
            id: 'c1-2026-01-15',
            creditId: 'c1',
            cutoffDate: '2026-01-15',
            dueDate: '2026-02-05',
            closingBalance: 100000,
            createdAt: '2026-01-15',
          ),
        ],
      );

      final decoded = CardCredit.fromJson(card.toJson());

      expect(decoded.closedStatements, hasLength(1));
      expect(decoded.closedStatements.first.cutoffDate, '2026-01-15');
    });

    test('fromJson defaults closedStatements to empty when absent '
        '(backup v3 compat)', () {
      final decoded = CardCredit.fromJson({
        'id': 'c1',
        'name': 'Test',
        'lender': 'Bank',
      });
      expect(decoded.closedStatements, isEmpty);
    });
  });

  group('LoanCredit cupo comercial fields', () {
    test('fromJson without new fields defaults safely', () {
      final loan = LoanCredit.fromJson({
        'id': 'l1',
        'name': 'Compra Totto',
        'lender': 'Totto',
        'totalAmount': 250000.0,
        'quotaAmount': 46500.0,
        'totalInstallments': 6,
        'frequency': 'monthly',
        'startDate': '2026-09-01',
      });

      expect(loan.quotaId, isNull);
      expect(loan.interestUnknown, isFalse);
      expect(loan.earlyPaymentWaivesInterest, isFalse);
    });

    test('toJson/fromJson round-trips the new fields', () {
      final loan = LoanCredit(
        id: 'l2',
        name: 'Compra Lili Pink',
        lender: 'Lili Pink',
        totalAmount: 100000,
        quotaAmount: 34000,
        totalInstallments: 3,
        frequency: CreditFrequency.monthly,
        startDate: '2026-09-01',
        quotaId: 'q1',
        interestUnknown: true,
        earlyPaymentWaivesInterest: true,
      );

      final restored = LoanCredit.fromJson(loan.toJson());

      expect(restored.quotaId, 'q1');
      expect(restored.interestUnknown, isTrue);
      expect(restored.earlyPaymentWaivesInterest, isTrue);
    });
  });
}
