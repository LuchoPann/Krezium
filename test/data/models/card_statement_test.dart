import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_statement.dart';

void main() {
  test('toJson/fromJson round-trip preserves all fields', () {
    final statement = CardStatement(
      id: 'card1-2026-01-15',
      creditId: 'card1',
      cutoffDate: '2026-01-15',
      dueDate: '2026-02-05',
      closingBalance: 150000.50,
      paidAmount: 50000,
      status: 'closed',
      createdAt: '2026-01-15',
    );

    final decoded = CardStatement.fromJson(statement.toJson());

    expect(decoded.id, 'card1-2026-01-15');
    expect(decoded.creditId, 'card1');
    expect(decoded.cutoffDate, '2026-01-15');
    expect(decoded.dueDate, '2026-02-05');
    expect(decoded.closingBalance, 150000.50);
    expect(decoded.paidAmount, 50000);
    expect(decoded.status, 'closed');
    expect(decoded.createdAt, '2026-01-15');
  });

  test('fromJson defaults paidAmount to 0 and status to closed when absent', () {
    final decoded = CardStatement.fromJson({
      'id': 'x',
      'creditId': 'card1',
      'cutoffDate': '2026-01-15',
      'dueDate': '2026-02-05',
      'closingBalance': 1000.0,
      'createdAt': '2026-01-15',
    });

    expect(decoded.paidAmount, 0);
    expect(decoded.status, 'closed');
  });
}
