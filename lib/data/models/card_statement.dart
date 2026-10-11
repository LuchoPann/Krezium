/// Un extracto de tarjeta ya CERRADO (histórico). El extracto actualmente
/// abierto nunca tiene una fila de este tipo — se calcula on-the-fly desde
/// `CardCredit.movements` (ver `getCardCycleDates` en card_calculator.dart).
/// Creado una sola vez por `accrueCardCredit` cuando detecta que un ciclo
/// de facturación cruzó su fecha de corte.
class CardStatementStatus {
  static const closed = 'closed';
  static const paid = 'paid';
}

class CardStatement {
  final String id;
  final String creditId;

  /// "YYYY-MM-DD" — fecha de corte que cerró este extracto.
  final String cutoffDate;

  /// "YYYY-MM-DD" — fecha límite de pago de este extracto.
  final String dueDate;

  /// Saldo total a pagar de este extracto, fijado al momento de cerrar.
  final double closingBalance;

  /// Monto abonado a este extracto específico.
  final double paidAmount;

  /// Uno de [CardStatementStatus].
  final String status;

  /// "YYYY-MM-DD" — fecha en que se generó este registro (debug/orden).
  final String createdAt;

  const CardStatement({
    required this.id,
    required this.creditId,
    required this.cutoffDate,
    required this.dueDate,
    required this.closingBalance,
    this.paidAmount = 0,
    this.status = CardStatementStatus.closed,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'creditId': creditId,
        'cutoffDate': cutoffDate,
        'dueDate': dueDate,
        'closingBalance': closingBalance,
        'paidAmount': paidAmount,
        'status': status,
        'createdAt': createdAt,
      };

  factory CardStatement.fromJson(Map<String, dynamic> json) => CardStatement(
        id: json['id'] as String,
        creditId: json['creditId'] as String,
        cutoffDate: json['cutoffDate'] as String,
        dueDate: json['dueDate'] as String,
        closingBalance: (json['closingBalance'] as num).toDouble(),
        paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? CardStatementStatus.closed,
        createdAt: json['createdAt'] as String,
      );
}
