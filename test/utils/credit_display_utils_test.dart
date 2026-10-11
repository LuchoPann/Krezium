import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';
import 'package:krezium/data/models/credit.dart';
import 'package:krezium/domain/date_utils.dart';
import 'package:krezium/utils/credit_display_utils.dart';

void main() {
  test('getNextDueDate for a card with no closed statements returns null', () {
    final card = CardCredit(id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15);
    expect(getNextDueDate(card), isNull);
  });

  test('getNextDueDate for a card with an unpaid closed statement returns '
      'that statement\'s dueDate', () {
    final card = CardCredit(
      id: 'c1', name: 'Test', lender: 'Bank', cutoffDay: 15,
      statements: [
        const CardStatement(
          id: 's1', creditId: 'c1', cutoffDate: '2026-01-15',
          dueDate: '2026-02-05', closingBalance: 100000,
          status: CardStatementStatus.closed, createdAt: '2026-01-15',
        ),
      ],
    );
    expect(getNextDueDate(card), parseDateStr('2026-02-05'));
  });
}
