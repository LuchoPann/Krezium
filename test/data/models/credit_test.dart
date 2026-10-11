import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/data/models/installment_purchase.dart';

void main() {
  group('CardCredit statements', () {
    test('defaults to empty list', () {
      final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank');
      expect(card.statements, isEmpty);
      expect(card.installmentPurchases, isEmpty);
    });

    test('toJson/fromJson round-trips statements and installmentPurchases', () {
      final card = CardCredit(
        id: 'c1',
        name: 'Test',
        lender: 'Bank',
        statements: [
          const CardStatement(
            id: 's1', creditId: 'c1', cutoffDate: '2026-01-15',
            dueDate: '2026-02-05', closingBalance: 0,
            status: CardStatementStatus.open, createdAt: '2026-01-01',
          ),
        ],
        installmentPurchases: [
          InstallmentPurchase(
            id: 'ip1', creditId: 'c1', purchaseDate: '2026-01-10',
            totalAmount: 100000, installments: 3,
            perInstallmentAmount: 33333, lastInstallmentAmount: 33334,
            createdAt: '2026-01-10',
          ),
        ],
      );

      final decoded = CardCredit.fromJson(card.toJson());

      expect(decoded.statements, hasLength(1));
      expect(decoded.statements.first.status, CardStatementStatus.open);
      expect(decoded.installmentPurchases, hasLength(1));
    });

    test('fromJson defaults both to empty when absent (backup v4 compat)', () {
      final decoded = CardCredit.fromJson({'id': 'c1', 'name': 'Test', 'lender': 'Bank'});
      expect(decoded.statements, isEmpty);
      expect(decoded.installmentPurchases, isEmpty);
    });

    test('fromJson reads the legacy "closedStatements" key when '
        '"statements" is absent (backup v4 compat)', () {
      final decoded = CardCredit.fromJson({
        'id': 'c1', 'name': 'Test', 'lender': 'Bank',
        'closedStatements': [
          {
            'id': 's1', 'creditId': 'c1', 'cutoffDate': '2026-01-15',
            'dueDate': '2026-02-05', 'closingBalance': 100000.0,
            'createdAt': '2026-01-15',
          }
        ],
      });
      expect(decoded.statements, hasLength(1));
      expect(decoded.statements.first.cutoffDate, '2026-01-15');
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
