import 'package:flutter_test/flutter_test.dart';
import 'package:krezium/data/models/installment_purchase.dart';

void main() {
  InstallmentPurchase build({int billed = 1}) => InstallmentPurchase(
        id: 'ip1',
        creditId: 'c1',
        purchaseDate: '2026-01-10',
        totalAmount: 100000,
        installments: 3,
        perInstallmentAmount: 33333,
        lastInstallmentAmount: 33334,
        note: 'TV',
        categoria: 'otro',
        installmentsBilled: billed,
        createdAt: '2026-01-10',
      );

  test('toJson/fromJson round-trip preserves all fields', () {
    final p = build();
    final decoded = InstallmentPurchase.fromJson(p.toJson());
    expect(decoded.id, 'ip1');
    expect(decoded.totalAmount, 100000);
    expect(decoded.installments, 3);
    expect(decoded.perInstallmentAmount, 33333);
    expect(decoded.lastInstallmentAmount, 33334);
    expect(decoded.installmentsBilled, 1);
  });

  test('isFullyBilled is true once installmentsBilled reaches installments', () {
    expect(build(billed: 2).isFullyBilled, isFalse);
    expect(build(billed: 3).isFullyBilled, isTrue);
  });

  test('remainingAmount sums the still-unbilled cuotas, using '
      'lastInstallmentAmount for the final one', () {
    expect(build(billed: 1).remainingAmount, 33333 + 33334);
    expect(build(billed: 3).remainingAmount, 0);
  });
}
