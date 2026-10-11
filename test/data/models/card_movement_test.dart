import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';

void main() {
  test('toJson/fromJson round-trips installmentIndex and statementCutoff', () {
    final mv = CardMovement(
      date: '2026-01-10',
      type: CardMovementType.charge,
      amount: 50000,
      chargeInstallments: 3,
      installmentIndex: 2,
      statementCutoff: '2026-02-15',
    );

    final decoded = CardMovement.fromJson(mv.toJson());

    expect(decoded.chargeInstallments, 3);
    expect(decoded.installmentIndex, 2);
    expect(decoded.statementCutoff, '2026-02-15');
  });

  test('installmentIndex and statementCutoff default to null', () {
    final decoded = CardMovement.fromJson({
      'date': '2026-01-10',
      'type': CardMovementType.payment,
      'amount': 10000.0,
    });

    expect(decoded.installmentIndex, isNull);
    expect(decoded.statementCutoff, isNull);
  });
}
