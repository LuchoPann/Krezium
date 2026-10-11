import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/card_movement.dart';
import 'package:krezium/widgets/credit_detail/movements_tab.dart';

void main() {
  test('a charge exactly on the cutoff day groups under that same cutoff '
      '(not next month) — regression for the day==cutoff bug', () {
    final movements = [
      CardMovement(date: '2026-01-15', type: CardMovementType.charge, amount: 10000),
    ];
    final groups = groupMovementsByCycle(movements, 15);
    expect(groups.keys, contains('2026-01-15'));
    expect(groups.keys, isNot(contains('2026-02-15')));
  });

  test('an installment movement with statementCutoff groups by that field, '
      'ignoring its purchase date', () {
    final movements = [
      CardMovement(
        date: '2026-01-10', // fecha real de compra
        type: CardMovementType.charge,
        amount: 50000,
        chargeInstallments: 3,
        installmentIndex: 2,
        statementCutoff: '2026-02-15', // extracto al que pertenece esta cuota
      ),
    ];
    final groups = groupMovementsByCycle(movements, 15);
    expect(groups.keys, contains('2026-02-15'));
    expect(groups.keys, isNot(contains('2026-01-15')));
  });
}
