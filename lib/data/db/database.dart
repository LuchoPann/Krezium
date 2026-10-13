import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/interest_rate.dart';
import '../models/card_movement.dart';
import '../models/card_statement.dart';
import '../models/installment_purchase.dart';
import '../models/commercial_quota.dart';
import '../models/credit.dart';
import '../models/installment.dart';
import '../models/loan_abono.dart';
import '../models/pago_realizado.dart';
import 'connection.dart';
import 'tables.dart';
import 'tables_finance.dart';

part 'database.g.dart';

/// Thrown by [AppDatabase.deleteCommercialQuota] when [activeCount]
/// purchases still reference the quota and aren't fully paid off — the UI
/// surfaces this as a specific, accurate message instead of a raw
/// exception or a generic "still has purchases" that's wrong once every
/// purchase has actually been paid.
class QuotaHasActivePurchasesException implements Exception {
  final int activeCount;
  const QuotaHasActivePurchasesException(this.activeCount);
  @override
  String toString() =>
      'QuotaHasActivePurchasesException: $activeCount active purchase(s)';
}

/// Thrown by [AppDatabase.deleteFinanceAccountSafely] when [count]
/// transactions still reference the account (as origin or transfer
/// destination) — the UI should offer archiving or a confirmed hard delete
/// instead of silently losing history.
class AccountHasTransactionsException implements Exception {
  final int count;
  const AccountHasTransactionsException(this.count);
  @override
  String toString() =>
      'AccountHasTransactionsException: $count transacción(es) asociada(s)';
}

/// App-wide Drift database. Replaces app.js's single Dexie `kv` table (which
/// just stashed the whole `state` object as one JSON blob) with a proper
/// relational schema — see lib/data/db/tables.dart for the mapping notes.
@DriftDatabase(tables: [
  Credits, Installments, CardMovements, CardStatements,
  InstallmentPurchases, LoanAbonos, CommercialQuotas, PagosRealizados,
  FinanceAccounts, FinanceCategories, FinanceTransactions, FinanceBudgets,
  FinancePlaces, FinanceTemplates, FinanceReservations,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  /// For tests: pass an in-memory executor directly.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Algunos dispositivos (incl. el de desarrollo) ya tienen estas
          // columnas/tablas de iteraciones previas de hot-restart aunque su
          // PRAGMA user_version no haya llegado a esa versión todavía.
          // Verificar con PRAGMA table_info / sqlite_master antes de cada
          // ADD COLUMN / CREATE TABLE evita "duplicate column name"/"table
          // exists".
          Future<Set<String>> colsOf(String table) async {
            final rows = await customSelect('PRAGMA table_info($table)').get();
            return rows.map((r) => r.read<String>('name')).toSet();
          }

          Future<bool> tableExists(String table) async {
            final rows = await customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'")
                .get();
            return rows.isNotEmpty;
          }

          if (from < 2) {
            await m.addColumn(credits, credits.interestRateType);
          }
          if (from < 3) {
            await m.createTable(loanAbonos);
          }
          if (from < 4) {
            await m.addColumn(credits, credits.scheduleManuallyAdjusted);
          }
          if (from < 5) {
            await m.addColumn(loanAbonos, loanAbonos.previousQuotaAmount);
            await m.addColumn(
                loanAbonos, loanAbonos.previousInstallmentsSnapshot);
          }
          if (from < 6) {
            await m.createTable(commercialQuotas);
            await m.addColumn(credits, credits.quotaId);
            await m.addColumn(credits, credits.interestUnknown);
            await m.addColumn(credits, credits.earlyPaymentWaivesInterest);
          }
          if (from < 7) {
            await m.addColumn(commercialQuotas, commercialQuotas.voucherPattern);
          }
          if (from < 8) {
            await m.addColumn(commercialQuotas, commercialQuotas.entityType);
            await m.addColumn(commercialQuotas, commercialQuotas.cutoffDay);
            await m.addColumn(
                commercialQuotas, commercialQuotas.paymentOffsetDays);
            await m.addColumn(commercialQuotas, commercialQuotas.managementFee);
            await m.addColumn(
                commercialQuotas, commercialQuotas.managementFeeFrequency);
          }
          if (from < 9) {
            await m.addColumn(credits, credits.cardDesign);
          }
          if (from < 10) {
            await m.addColumn(credits, credits.paymentDueDay);
            await m.addColumn(credits, credits.oneInstallmentInterestPolicy);
            // Poblar paymentDueDay para tarjetas existentes.
            // Si no hay filas card, el UPDATE no falla (afecta 0 filas).
            await customStatement('''
              UPDATE credits
              SET payment_due_day = ((cutoff_day + payment_due_offset_days - 1) % 31) + 1
              WHERE type = 'card'
                AND cutoff_day IS NOT NULL
                AND payment_due_offset_days IS NOT NULL
            ''');
          }
          if (from < 11) {
            await m.addColumn(cardMovements, cardMovements.advanceInstallments);
            await m.addColumn(cardMovements, cardMovements.advanceInterestRate);
            await m.addColumn(cardMovements, cardMovements.advanceInterestRateType);
            await m.addColumn(cardMovements, cardMovements.advanceCommission);
            await m.addColumn(cardMovements, cardMovements.advanceFirstPaymentDate);
            await m.addColumn(cardMovements, cardMovements.advanceDestination);
          }
          if (from < 13) {
            await m.createTable(financeAccounts);
            await m.createTable(financeCategories);
            await m.createTable(financeTransactions);
            await m.createTable(financeBudgets);
          }
          if (from < 14) {
            if (from == 13) {
              // Para dispositivos en v12, las tablas Finance ya se crean con
              // el schema completo en el bloque if(from<13) de arriba, por lo
              // que addColumn solo aplica para upgrades v13→v14.
              await m.addColumn(financeAccounts, financeAccounts.esFavorito);
              await m.addColumn(financeCategories, financeCategories.parentId);
              await m.addColumn(financeTransactions, financeTransactions.personaSitio);
              await m.addColumn(financeTransactions, financeTransactions.hora);
              await m.addColumn(financeTransactions, financeTransactions.transferToAccountId);
            }
            await m.createTable(financePlaces);
            await m.createTable(financeTemplates);
          }
          if (from < 12) {
            // notification_days_before may already exist on devices that ran
            // the CosasNuevas branch (where it was added at v11 before the
            // schema version was bumped). Guard with PRAGMA table_info to
            // avoid "duplicate column name" on those devices.
            final creditCols =
                await customSelect('PRAGMA table_info(credits)').get();
            final creditColNames =
                creditCols.map((r) => r.read<String>('name')).toSet();
            if (!creditColNames.contains('notification_days_before')) {
              await m.addColumn(credits, credits.notificationDaysBefore);
            }

            final movCols =
                await customSelect('PRAGMA table_info(card_movements)').get();
            final movColNames =
                movCols.map((r) => r.read<String>('name')).toSet();
            if (!movColNames.contains('categoria')) {
              await m.addColumn(cardMovements, cardMovements.categoria);
            }

            // pagosRealizados table may not exist yet — only create if absent.
            final tables =
                await customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='pagos_realizados'").get();
            if (tables.isEmpty) {
              await m.createTable(pagosRealizados);
            }
          }
          if (from < 17) {
            // v15/v16/v17 se desarrollaron en vivo esta sesión: algunos
            // dispositivos (incl. el de desarrollo) ya tienen estas
            // columnas/tablas de iteraciones previas de hot-restart aunque
            // su PRAGMA user_version no haya llegado a esa versión todavía.
            // Igual que el guard de from<12 para notification_days_before:
            // verificar con PRAGMA table_info antes de cada ADD COLUMN /
            // CREATE TABLE evita "duplicate column name"/"table exists".
            if (from < 15) {
              if (!await tableExists('card_statements')) {
                await m.createTable(cardStatements);
              }
              final movCols = await colsOf('card_movements');
              if (!movCols.contains('installment_index')) {
                await m.addColumn(cardMovements, cardMovements.installmentIndex);
              }
              if (!movCols.contains('statement_cutoff')) {
                await m.addColumn(cardMovements, cardMovements.statementCutoff);
              }
            }
            if (from < 16) {
              if (!await tableExists('installment_purchases')) {
                await m.createTable(installmentPurchases);
              }
              final movCols = await colsOf('card_movements');
              if (!movCols.contains('statement_id')) {
                await m.addColumn(cardMovements, cardMovements.statementId);
              }
              if (!movCols.contains('installment_purchase_id')) {
                await m.addColumn(
                    cardMovements, cardMovements.installmentPurchaseId);
              }
            }
            if (from >= 15 && from < 17) {
              final stmtCols = await colsOf('card_statements');
              if (!stmtCols.contains('opening_balance')) {
                await m.addColumn(cardStatements, cardStatements.openingBalance);
              }
            }
          }
          if (from < 18) {
            final acctCols = await customSelect('PRAGMA table_info(finance_accounts)').get();
            if (!acctCols.map((r) => r.read<String>('name')).contains('descripcion')) {
              await m.addColumn(financeAccounts, financeAccounts.descripcion);
            }
          }
          if (from < 19) {
            if (!await tableExists('finance_reservations')) {
              await m.createTable(financeReservations);
            }
            final txCols = await colsOf('finance_transactions');
            if (!txCols.contains('revision_nota')) {
              await m.addColumn(financeTransactions, financeTransactions.revisionNota);
            }
          }
        },
        // SQLite ignores FK constraints (like Credits.quotaId's
        // onDelete: restrict) unless this pragma is set per-connection —
        // it does not persist in the schema itself.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // --- Domain <-> row mapping -------------------------------------------

  LoanCredit _loanFromRow(
      CreditRow row, List<Installment> installments, List<LoanAbono> abonos) {
    return LoanCredit(
      id: row.id,
      name: row.name,
      lender: row.lender,
      color: row.color,
      notes: row.notes,
      location: row.location,
      card: row.card,
      totalAmount: row.totalAmount ?? 0,
      quotaAmount: row.quotaAmount ?? 0,
      totalInstallments: row.totalInstallments ?? 0,
      frequency: row.frequency ?? CreditFrequency.monthly,
      startDate: row.startDate ?? '',
      interestRate: row.interestRate ?? 0,
      interestRateType:
          row.interestRateType ?? InterestRateType.effectiveAnnual,
      installments: installments,
      abonos: abonos,
      scheduleManuallyAdjusted: row.scheduleManuallyAdjusted,
      quotaId: row.quotaId,
      interestUnknown: row.interestUnknown,
      earlyPaymentWaivesInterest: row.earlyPaymentWaivesInterest,
      cardDesign: row.cardDesign,
      notificationDaysBefore: row.notificationDaysBefore,
    );
  }

  CardCredit _cardFromRow(
      CreditRow row, List<CardMovement> movements,
      List<CardStatement> statements,
      List<InstallmentPurchase> installmentPurchases) {
    return CardCredit(
      id: row.id,
      name: row.name,
      lender: row.lender,
      color: row.color,
      notes: row.notes,
      creditLimit: row.creditLimit ?? 0,
      currentBalance: row.currentBalance ?? 0,
      cutoffDay: row.cutoffDay ?? 1,
      paymentDueOffsetDays: row.paymentDueOffsetDays ?? 20,
      interestRate: row.interestRate ?? 0,
      interestRateType:
          row.interestRateType ?? InterestRateType.effectiveAnnual,
      managementFee: row.managementFee ?? 0,
      managementFeeFrequency:
          row.managementFeeFrequency ?? ManagementFeeFrequency.monthly,
      cycleCount: row.cycleCount ?? 0,
      lastAccrualCutoff: row.lastAccrualCutoff,
      quotaId: row.quotaId,
      cardDesign: row.cardDesign,
      paymentDueDay: row.paymentDueDay,
      oneInstallmentInterestPolicy: row.oneInstallmentInterestPolicy,
      notificationDaysBefore: row.notificationDaysBefore,
      movements: movements,
      statements: statements,
      installmentPurchases: installmentPurchases,
    );
  }

  CreditsCompanion _creditToCompanion(Credit credit) {
    if (credit is LoanCredit) {
      return CreditsCompanion.insert(
        id: credit.id,
        type: CreditType.loan,
        name: credit.name,
        lender: credit.lender,
        color: Value(credit.color),
        notes: Value(credit.notes),
        location: Value(credit.location),
        card: Value(credit.card),
        totalAmount: Value(credit.totalAmount),
        quotaAmount: Value(credit.quotaAmount),
        totalInstallments: Value(credit.totalInstallments),
        frequency: Value(credit.frequency),
        startDate: Value(credit.startDate),
        interestRate: Value(credit.interestRate),
        interestRateType: Value(credit.interestRateType),
        scheduleManuallyAdjusted: Value(credit.scheduleManuallyAdjusted),
        quotaId: Value(credit.quotaId),
        interestUnknown: Value(credit.interestUnknown),
        earlyPaymentWaivesInterest: Value(credit.earlyPaymentWaivesInterest),
        cardDesign: Value(credit.cardDesign),
        notificationDaysBefore: Value(credit.notificationDaysBefore),
      );
    } else if (credit is CardCredit) {
      return CreditsCompanion.insert(
        id: credit.id,
        type: CreditType.card,
        name: credit.name,
        lender: credit.lender,
        color: Value(credit.color),
        notes: Value(credit.notes),
        interestRate: Value(credit.interestRate),
        interestRateType: Value(credit.interestRateType),
        creditLimit: Value(credit.creditLimit),
        currentBalance: Value(credit.currentBalance),
        cutoffDay: Value(credit.cutoffDay),
        paymentDueOffsetDays: Value(credit.paymentDueOffsetDays),
        managementFee: Value(credit.managementFee),
        managementFeeFrequency: Value(credit.managementFeeFrequency),
        cycleCount: Value(credit.cycleCount),
        lastAccrualCutoff: Value(credit.lastAccrualCutoff),
        quotaId: Value(credit.quotaId),
        cardDesign: Value(credit.cardDesign),
        paymentDueDay: Value(credit.paymentDueDay),
        oneInstallmentInterestPolicy:
            Value(credit.oneInstallmentInterestPolicy),
        notificationDaysBefore: Value(credit.notificationDaysBefore),
      );
    }
    throw ArgumentError('Unknown credit subtype: ${credit.runtimeType}');
  }

  // --- Public API ----------------------------------------------------------

  /// Loads the full list of credits (with their installments/movements),
  /// equivalent to app.js's `state.credits` after loadState().
  Future<List<Credit>> loadAllCredits() async {
    final rows = await select(credits).get();
    final result = <Credit>[];
    for (final row in rows) {
      if (row.type == CreditType.card) {
        final movementRows = await (select(cardMovements)
              ..where((m) => m.creditId.equals(row.id))
              ..orderBy([(m) => OrderingTerm.asc(m.rowId)]))
            .get();
        final statementRows = await (select(cardStatements)
              ..where((s) => s.creditId.equals(row.id))
              ..orderBy([(s) => OrderingTerm.asc(s.cutoffDate)]))
            .get();
        final installmentPurchaseRows = await (select(installmentPurchases)
              ..where((p) => p.creditId.equals(row.id))
              ..orderBy([(p) => OrderingTerm.asc(p.purchaseDate)]))
            .get();
        result.add(_cardFromRow(
          row,
          movementRows
              .map((m) => CardMovement(
                    date: m.date,
                    type: m.type,
                    amount: m.amount,
                    note: m.note,
                    advanceInstallments: m.advanceInstallments,
                    advanceInterestRate: m.advanceInterestRate,
                    advanceInterestRateType: m.advanceInterestRateType,
                    advanceCommission: m.advanceCommission,
                    advanceFirstPaymentDate: m.advanceFirstPaymentDate,
                    advanceDestination: m.advanceDestination,
                    categoria: m.categoria,
                    installmentIndex: m.installmentIndex,
                    statementCutoff: m.statementCutoff,
                    statementId: m.statementId,
                    installmentPurchaseId: m.installmentPurchaseId,
                  ))
              .toList(),
          statementRows
              .map((s) => CardStatement(
                    id: s.id,
                    creditId: s.creditId,
                    cutoffDate: s.cutoffDate,
                    dueDate: s.dueDate,
                    closingBalance: s.closingBalance,
                    openingBalance: s.openingBalance,
                    paidAmount: s.paidAmount,
                    status: s.status,
                    createdAt: s.createdAt,
                  ))
              .toList(),
          installmentPurchaseRows
              .map((p) => InstallmentPurchase(
                    id: p.id,
                    creditId: p.creditId,
                    purchaseDate: p.purchaseDate,
                    totalAmount: p.totalAmount,
                    installments: p.installments,
                    perInstallmentAmount: p.perInstallmentAmount,
                    lastInstallmentAmount: p.lastInstallmentAmount,
                    note: p.note,
                    categoria: p.categoria,
                    installmentsBilled: p.installmentsBilled,
                    createdAt: p.createdAt,
                  ))
              .toList(),
        ));
      } else {
        final instRows = await (select(installments)
              ..where((i) => i.creditId.equals(row.id))
              ..orderBy([(i) => OrderingTerm.asc(i.number)]))
            .get();
        final abonoRows = await (select(loanAbonos)
              ..where((a) => a.creditId.equals(row.id))
              ..orderBy([(a) => OrderingTerm.asc(a.rowId)]))
            .get();
        result.add(_loanFromRow(
          row,
          instRows
              .map((i) => Installment(
                    number: i.number,
                    dueDate: i.dueDate,
                    amount: i.amount,
                    principal: i.principal,
                    interest: i.interest,
                    paid: i.paid,
                    paymentDate: i.paymentDate,
                    interestWaived: i.interestWaived,
                  ))
              .toList(),
          abonoRows
              .map((a) => LoanAbono(
                    date: a.date,
                    amount: a.amount,
                    note: a.note,
                    installmentsSkipped: a.installmentsSkipped,
                    previousQuotaAmount: a.previousQuotaAmount,
                    previousInstallmentsSnapshot:
                        a.previousInstallmentsSnapshot == null
                            ? null
                            : (jsonDecode(a.previousInstallmentsSnapshot!)
                                    as List<dynamic>)
                                .map((e) => Installment.fromJson(
                                    e as Map<String, dynamic>))
                                .toList(),
                  ))
              .toList(),
        ));
      }
    }
    return result;
  }

  /// Inserts or fully replaces [credit] and its children (installments or
  /// movements), matching app.js's pattern of always writing the whole
  /// credit object back on save.
  Future<List<CommercialQuota>> loadAllCommercialQuotas() async {
    final rows = await select(commercialQuotas).get();
    return rows
        .map((r) => CommercialQuota(
              id: r.id,
              brand: r.brand,
              limit: r.limit,
              notes: r.notes,
              voucherPattern: r.voucherPattern,
              entityType: r.entityType,
              cutoffDay: r.cutoffDay,
              paymentOffsetDays: r.paymentOffsetDays,
              managementFee: r.managementFee,
              managementFeeFrequency: r.managementFeeFrequency,
            ))
        .toList();
  }

  Future<void> upsertCommercialQuota(CommercialQuota quota) async {
    await into(commercialQuotas).insertOnConflictUpdate(
      CommercialQuotasCompanion.insert(
        id: quota.id,
        brand: quota.brand,
        limit: quota.limit,
        notes: Value(quota.notes),
        voucherPattern: Value(quota.voucherPattern),
        entityType: Value(quota.entityType),
        cutoffDay: Value(quota.cutoffDay),
        paymentOffsetDays: Value(quota.paymentOffsetDays),
        managementFee: Value(quota.managementFee),
        managementFeeFrequency: Value(quota.managementFeeFrequency),
      ),
    );
  }

  /// Throws a Drift/SQLite foreign-key-violation exception if any Credits
  /// row still references this quota (onDelete: restrict on Credits.quotaId
  /// — see tables.dart). Callers must catch and show a clear message
  /// instead of letting the raw exception reach the user.
  /// A purchase counts as "active" (blocks deletion) unless it has at
  /// least one installment and every one of them is paid — a purchase
  /// with zero installments is never treated as safely paid off.
  Future<bool> _isPurchaseFullyPaid(String creditId) async {
    final rows = await (select(installments)
          ..where((i) => i.creditId.equals(creditId)))
        .get();
    if (rows.isEmpty) return false;
    return rows.every((i) => i.paid);
  }

  /// Deletes [id] if none of its referencing purchases are still active.
  /// Purchases that are fully paid off are unlinked (their `quotaId` set to
  /// null) instead of blocking the delete, so paying off every purchase in
  /// a cupo never traps the user with an undeletable, permanently "active"
  /// quota — but their payment history is kept, just no longer grouped.
  /// Throws [QuotaHasActivePurchasesException] if any purchase is still
  /// active.
  Future<void> deleteCommercialQuota(String id) async {
    await transaction(() async {
      final purchases = await (select(credits)
            ..where((c) => c.quotaId.equals(id)))
          .get();

      var activeCount = 0;
      final paidIds = <String>[];
      for (final row in purchases) {
        if (await _isPurchaseFullyPaid(row.id)) {
          paidIds.add(row.id);
        } else {
          activeCount++;
        }
      }

      if (activeCount > 0) {
        throw QuotaHasActivePurchasesException(activeCount);
      }

      for (final purchaseId in paidIds) {
        await (update(credits)..where((c) => c.id.equals(purchaseId)))
            .write(const CreditsCompanion(quotaId: Value(null)));
      }
      await (delete(commercialQuotas)..where((q) => q.id.equals(id))).go();
    });
  }

  Future<void> upsertCredit(Credit credit) async {
    await transaction(() async {
      await into(credits).insertOnConflictUpdate(_creditToCompanion(credit));

      if (credit is LoanCredit) {
        await (delete(installments)..where((i) => i.creditId.equals(credit.id)))
            .go();
        for (final inst in credit.installments) {
          await into(installments).insert(InstallmentsCompanion.insert(
            creditId: credit.id,
            number: inst.number,
            dueDate: inst.dueDate,
            amount: inst.amount,
            principal: inst.principal,
            interest: inst.interest,
            paid: Value(inst.paid),
            paymentDate: Value(inst.paymentDate),
            interestWaived: Value(inst.interestWaived),
          ));
        }
        await (delete(loanAbonos)..where((a) => a.creditId.equals(credit.id)))
            .go();
        for (final abono in credit.abonos) {
          await into(loanAbonos).insert(LoanAbonosCompanion.insert(
            creditId: credit.id,
            date: abono.date,
            amount: abono.amount,
            note: Value(abono.note),
            installmentsSkipped: Value(abono.installmentsSkipped),
            previousQuotaAmount: Value(abono.previousQuotaAmount),
            previousInstallmentsSnapshot: Value(
              abono.previousInstallmentsSnapshot == null
                  ? null
                  : jsonEncode(abono.previousInstallmentsSnapshot!
                      .map((i) => i.toJson())
                      .toList()),
            ),
          ));
        }
      } else if (credit is CardCredit) {
        await (delete(cardMovements)
              ..where((m) => m.creditId.equals(credit.id)))
            .go();
        for (final mv in credit.movements) {
          await into(cardMovements).insert(CardMovementsCompanion.insert(
            creditId: credit.id,
            date: mv.date,
            type: mv.type,
            amount: mv.amount,
            note: Value(mv.note),
            advanceInstallments: Value(mv.advanceInstallments),
            advanceInterestRate: Value(mv.advanceInterestRate),
            advanceInterestRateType: Value(mv.advanceInterestRateType),
            advanceCommission: Value(mv.advanceCommission),
            advanceFirstPaymentDate: Value(mv.advanceFirstPaymentDate),
            advanceDestination: Value(mv.advanceDestination),
            categoria: Value(mv.categoria),
            installmentIndex: Value(mv.installmentIndex),
            statementCutoff: Value(mv.statementCutoff),
            statementId: Value(mv.statementId),
            installmentPurchaseId: Value(mv.installmentPurchaseId),
          ));
        }
        await (delete(cardStatements)
              ..where((s) => s.creditId.equals(credit.id)))
            .go();
        for (final s in credit.statements) {
          await into(cardStatements).insert(CardStatementsCompanion.insert(
            id: s.id,
            creditId: credit.id,
            cutoffDate: s.cutoffDate,
            dueDate: s.dueDate,
            closingBalance: s.closingBalance,
            openingBalance: Value(s.openingBalance),
            paidAmount: Value(s.paidAmount),
            status: Value(s.status),
            createdAt: s.createdAt,
          ));
        }
        await (delete(installmentPurchases)
              ..where((p) => p.creditId.equals(credit.id)))
            .go();
        for (final p in credit.installmentPurchases) {
          await into(installmentPurchases)
              .insert(InstallmentPurchasesCompanion.insert(
            id: p.id,
            creditId: credit.id,
            purchaseDate: p.purchaseDate,
            totalAmount: p.totalAmount,
            installments: p.installments,
            perInstallmentAmount: p.perInstallmentAmount,
            lastInstallmentAmount: p.lastInstallmentAmount,
            note: Value(p.note),
            categoria: Value(p.categoria),
            installmentsBilled: Value(p.installmentsBilled),
            createdAt: p.createdAt,
          ));
        }
      }
    });
  }

  // --- PagosRealizados API -------------------------------------------------

  Future<void> insertPagoRealizado(PagoRealizado pago) async {
    await into(pagosRealizados).insert(PagosRealizadosCompanion.insert(
      creditId: pago.creditId,
      fecha: pago.fecha,
      monto: pago.monto,
      tipo: pago.tipo,
      numeroCuota: Value(pago.numeroCuota),
      nota: Value(pago.nota),
    ));
  }

  Future<List<PagoRealizado>> loadPagosRealizados(String creditId) async {
    final rows = await (select(pagosRealizados)
          ..where((p) => p.creditId.equals(creditId))
          ..orderBy([(p) => OrderingTerm.asc(p.rowId)]))
        .get();
    return rows
        .map((r) => PagoRealizado(
              rowId: r.rowId,
              creditId: r.creditId,
              fecha: r.fecha,
              monto: r.monto,
              tipo: r.tipo,
              numeroCuota: r.numeroCuota,
              nota: r.nota,
            ))
        .toList();
  }

  Future<void> deletePagoRealizado(int rowId) async {
    await (delete(pagosRealizados)..where((p) => p.rowId.equals(rowId))).go();
  }

  // -------------------------------------------------------------------------

  // --- Finance Accounts ---

  Future<List<FinanceAccountRow>> getFinanceAccounts({bool incluirArchivadas = false}) {
    final q = select(financeAccounts);
    if (!incluirArchivadas) q.where((t) => t.activa.equals(true));
    return q.get();
  }

  Future<void> archiveFinanceAccount(String id) =>
      (update(financeAccounts)..where((t) => t.id.equals(id)))
          .write(const FinanceAccountsCompanion(activa: Value(false)));

  Future<void> reactivateFinanceAccount(String id) =>
      (update(financeAccounts)..where((t) => t.id.equals(id)))
          .write(const FinanceAccountsCompanion(activa: Value(true)));

  Future<int> countTransactionsForAccount(String accountId) async {
    final rows = await (select(financeTransactions)
          ..where((t) =>
              t.accountId.equals(accountId) | t.transferToAccountId.equals(accountId)))
        .get();
    return rows.length;
  }

  Future<void> deleteFinanceAccountSafely(String id) async {
    final count = await countTransactionsForAccount(id);
    if (count > 0) throw AccountHasTransactionsException(count);
    await deleteFinanceAccount(id);
  }

  /// Borrado físico definitivo: elimina las transacciones donde esta cuenta
  /// es el origen y luego la cuenta. Las transacciones donde esta cuenta
  /// era el destino de una transferencia (transferToAccountId) quedan con
  /// ese campo en null por el FK onDelete: setNull — se conservan como
  /// ingreso/gasto normal del otro lado, pero pierden la referencia de
  /// destino. Solo se invoca tras confirmación explícita del usuario.
  Future<void> deleteFinanceAccountAndHistory(String id) => transaction(() async {
        await (delete(financeTransactions)..where((t) => t.accountId.equals(id))).go();
        await deleteFinanceAccount(id);
      });

  Future<void> upsertFinanceAccount(FinanceAccountsCompanion row) =>
      into(financeAccounts).insertOnConflictUpdate(row);

  Future<void> deleteFinanceAccount(String id) =>
      (delete(financeAccounts)..where((t) => t.id.equals(id))).go();

  Future<void> clearFinanceAccountFavoritos() async {
    await (update(financeAccounts)..where((_) => const Constant(true)))
        .write(const FinanceAccountsCompanion(esFavorito: Value(false)));
  }

  // --- Finance Categories ---

  Future<List<FinanceCategoryRow>> getFinanceCategories() =>
      select(financeCategories).get();

  Future<void> upsertFinanceCategory(FinanceCategoriesCompanion row) =>
      into(financeCategories).insertOnConflictUpdate(row);

  // --- Finance Transactions ---

  Future<List<FinanceTransactionRow>> getFinanceTransactions({
    String? accountId,
    String? mes, // 'YYYY-MM'
  }) async {
    final query = select(financeTransactions);
    query.where((t) {
      Expression<bool> cond = const Constant(true);
      if (accountId != null) cond = cond & t.accountId.equals(accountId);
      if (mes != null) cond = cond & t.fecha.like('$mes%');
      return cond;
    });
    query.orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    return query.get();
  }

  Future<void> upsertFinanceTransaction(FinanceTransactionsCompanion row) =>
      into(financeTransactions).insertOnConflictUpdate(row);

  Future<void> deleteFinanceTransaction(String id) =>
      (delete(financeTransactions)..where((t) => t.id.equals(id))).go();

  // --- Finance Places ---

  Future<List<FinancePlaceRow>> getFinancePlaces() =>
      (select(financePlaces)..orderBy([(t) => OrderingTerm.desc(t.usados)])).get();

  Future<void> upsertFinancePlace(FinancePlacesCompanion place) =>
      into(financePlaces).insertOnConflictUpdate(place);

  // --- Finance Templates ---

  Future<List<FinanceTemplateRow>> getFinanceTemplates({String? tipo}) {
    final q = select(financeTemplates);
    if (tipo != null) q.where((t) => t.tipo.equals(tipo));
    return q.get();
  }

  Future<void> upsertFinanceTemplate(FinanceTemplatesCompanion template) =>
      into(financeTemplates).insertOnConflictUpdate(template);

  Future<void> deleteFinanceTemplate(String id) =>
      (delete(financeTemplates)..where((t) => t.id.equals(id))).go();

  // --- Finance Transactions by libro ---

  Future<List<FinanceTransactionRow>> getFinanceTransactionsByLibro({
    required String libroId,
    String? mes, // 'YYYY-MM'
    String? tipo, // 'ingreso'|'gasto'|null
    bool ascending = false,
  }) {
    final q = select(financeTransactions)
      ..where((t) => t.accountId.equals(libroId));
    if (mes != null) q.where((t) => t.fecha.like('$mes%'));
    if (tipo != null) q.where((t) => t.tipo.equals(tipo));
    q.orderBy([(t) => ascending
        ? OrderingTerm.asc(t.fecha)
        : OrderingTerm.desc(t.fecha)]);
    return q.get();
  }

  /// Igual que [getFinanceTransactionsByLibro] pero incluye también las
  /// transferencias cuyo destino es [libroId] — necesario para que el
  /// registro destino vea el dinero que recibió.
  Future<List<FinanceTransactionRow>> getFinanceTransactionsInvolvingLibro({
    required String libroId,
    String? mes,
    bool ascending = false,
  }) {
    final q = select(financeTransactions)
      ..where((t) =>
          t.accountId.equals(libroId) | t.transferToAccountId.equals(libroId));
    if (mes != null) q.where((t) => t.fecha.like('$mes%'));
    q.orderBy([(t) => ascending
        ? OrderingTerm.asc(t.fecha)
        : OrderingTerm.desc(t.fecha)]);
    return q.get();
  }

  // --- Finance Budgets ---

  Future<List<FinanceBudgetRow>> getFinanceBudgets(int anio, int mes) =>
      (select(financeBudgets)
            ..where((t) => t.anio.equals(anio) & t.mes.equals(mes)))
          .get();

  Future<void> upsertFinanceBudget(FinanceBudgetsCompanion row) =>
      into(financeBudgets).insertOnConflictUpdate(row);

  // --- Finance Reservations ---

  Future<List<FinanceReservationRow>> getFinanceReservations(String accountId) =>
      (select(financeReservations)..where((r) => r.accountId.equals(accountId))).get();

  Future<void> upsertFinanceReservation(FinanceReservationsCompanion row) =>
      into(financeReservations).insertOnConflictUpdate(row);

  Future<void> deleteFinanceReservation(String id) =>
      (delete(financeReservations)..where((r) => r.id.equals(id))).go();

  // -------------------------------------------------------------------------

  /// Deletes [creditId] and (via FK cascade) all its installments/movements.
  Future<void> deleteCredit(String creditId) =>
      (delete(credits)..where((c) => c.id.equals(creditId))).go();

  /// Deletes everything (clearAllData, app.js ~L1660-1669), including
  /// commercial quotas — a wipe must not leave orphaned cupo cards behind.
  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(installments).go();
      await delete(cardMovements).go();
      await delete(cardStatements).go();
      await delete(installmentPurchases).go();
      await delete(loanAbonos).go();
      await delete(pagosRealizados).go();
      await delete(credits).go();
      await delete(commercialQuotas).go();
    });
  }

  /// Replaces both the credits and commercial-quotas tables with
  /// [newCredits]/[newQuotas] in a single transaction — a backup restore
  /// must never leave the database with some rows cleared and others not
  /// inserted (e.g. on a mid-restore FK failure). A credit whose `quotaId`
  /// doesn't match any of [newQuotas] has it nulled out instead of failing
  /// the whole restore (defends against a backup file edited by hand, or a
  /// future backup format that dropped a quota some credit still points
  /// to).
  Future<void> replaceAllData(
      List<Credit> newCredits, List<CommercialQuota> newQuotas) async {
    final quotaIds = newQuotas.map((q) => q.id).toSet();
    await transaction(() async {
      await delete(installments).go();
      await delete(cardMovements).go();
      await delete(cardStatements).go();
      await delete(installmentPurchases).go();
      await delete(loanAbonos).go();
      await delete(pagosRealizados).go();
      await delete(credits).go();
      await delete(commercialQuotas).go();
      for (final q in newQuotas) {
        await upsertCommercialQuota(q);
      }
      for (final c in newCredits) {
        // Clear orphaned quotaId on both LoanCredit and CardCredit — a credit
        // referencing a quota that isn't in this backup would fail the FK
        // constraint (credits.quotaId → commercialQuotas.id) and silently
        // mis-group the credit. Nullifying it lets it render as a standalone
        // credit instead.
        if (c is CardCredit && c.quotaId != null && !quotaIds.contains(c.quotaId)) {
          c.quotaId = null;
        } else if (c is LoanCredit && c.quotaId != null && !quotaIds.contains(c.quotaId)) {
          c.quotaId = null;
        }
        await upsertCredit(c);
      }
    });
  }
}
