/// Una compra registrada a N cuotas. La cuota 1 se factura de inmediato
/// (al momento de la compra); cada cuota siguiente se factura sola,
/// automáticamente, cuando el extracto correspondiente abre — ver
/// `closeCurrentCycleIfDue` en lib/domain/card_statement_engine.dart.
class InstallmentPurchase {
  final String id;
  final String creditId;

  /// "YYYY-MM-DD"
  final String purchaseDate;

  final double totalAmount;
  final int installments;

  /// Monto redondeado a 2 decimales de cada cuota, excepto la última.
  final double perInstallmentAmount;

  /// Monto de la última cuota — absorbe el remanente de redondeo para que
  /// la suma de todas las cuotas sea exactamente [totalAmount].
  final double lastInstallmentAmount;

  final String note;
  final String? categoria;

  /// Cuántas cuotas ya se facturaron como CardMovement (empieza en 1: la
  /// cuota 1 se factura al momento de la compra).
  int installmentsBilled;

  /// "YYYY-MM-DD"
  final String createdAt;

  InstallmentPurchase({
    required this.id,
    required this.creditId,
    required this.purchaseDate,
    required this.totalAmount,
    required this.installments,
    required this.perInstallmentAmount,
    required this.lastInstallmentAmount,
    this.note = '',
    this.categoria,
    this.installmentsBilled = 1,
    required this.createdAt,
  });

  bool get isFullyBilled => installmentsBilled >= installments;

  double get remainingAmount {
    final remainingCount = installments - installmentsBilled;
    if (remainingCount <= 0) return 0;
    return perInstallmentAmount * (remainingCount - 1) + lastInstallmentAmount;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'creditId': creditId,
        'purchaseDate': purchaseDate,
        'totalAmount': totalAmount,
        'installments': installments,
        'perInstallmentAmount': perInstallmentAmount,
        'lastInstallmentAmount': lastInstallmentAmount,
        'note': note,
        'categoria': categoria,
        'installmentsBilled': installmentsBilled,
        'createdAt': createdAt,
      };

  factory InstallmentPurchase.fromJson(Map<String, dynamic> json) =>
      InstallmentPurchase(
        id: json['id'] as String,
        creditId: json['creditId'] as String,
        purchaseDate: json['purchaseDate'] as String,
        totalAmount: (json['totalAmount'] as num).toDouble(),
        installments: (json['installments'] as num).toInt(),
        perInstallmentAmount: (json['perInstallmentAmount'] as num).toDouble(),
        lastInstallmentAmount:
            (json['lastInstallmentAmount'] as num).toDouble(),
        note: json['note'] as String? ?? '',
        categoria: json['categoria'] as String?,
        installmentsBilled: (json['installmentsBilled'] as num?)?.toInt() ?? 1,
        createdAt: json['createdAt'] as String,
      );
}
