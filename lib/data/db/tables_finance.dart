import 'package:drift/drift.dart';

@DataClassName('FinanceAccountRow')
class FinanceAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  TextColumn get tipo => text()(); // 'efectivo'|'digital'|'bancaria'
  TextColumn get icono => text()();
  TextColumn get color => text()();
  RealColumn get saldoInicial => real().withDefault(const Constant(0.0))();
  BoolColumn get activa => boolean().withDefault(const Constant(true))();
  TextColumn get orden => text().withDefault(const Constant('0'))();
  BoolColumn get esFavorito => boolean().withDefault(const Constant(false))();
  TextColumn get descripcion => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FinanceCategoryRow')
class FinanceCategories extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  TextColumn get icono => text()();
  TextColumn get color => text()();
  TextColumn get tipo => text()(); // 'ingreso'|'gasto'|'ambos'
  BoolColumn get archivada => boolean().withDefault(const Constant(false))();
  TextColumn get parentId => text().nullable()
      .references(FinanceCategories, #id, onDelete: KeyAction.setNull)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FinanceTransactionRow')
class FinanceTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId =>
      text().references(FinanceAccounts, #id, onDelete: KeyAction.restrict)();
  TextColumn get categoryId => text()();
  TextColumn get tipo => text()(); // 'ingreso'|'gasto'
  RealColumn get monto => real()();
  TextColumn get fecha => text()(); // YYYY-MM-DD
  TextColumn get nota => text().withDefault(const Constant(''))();
  BoolColumn get esRecurrente => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenciaConfig => text().nullable()();
  TextColumn get personaSitio => text().nullable()();
  TextColumn get hora => text().nullable()(); // "HH:mm"
  @ReferenceName('transferTransactions')
  TextColumn get transferToAccountId => text().nullable()
      .references(FinanceAccounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get revisionNota => text().nullable()();
  // Cargar este gasto al presupuesto de OTRA categoría padre en vez de la
  // suya propia — ej. una gaseosa (categoryId = Alimentación) pagada con
  // el dinero que tenías apartado para Transporte: el gasto real es de
  // Alimentación, pero el usuario quiere que descuente del presupuesto de
  // Transporte porque de ahí salió la plata. Nullable: por defecto el gasto
  // cuenta contra el presupuesto de su propia categoría, como siempre.
  TextColumn get cargaPresupuestoCategoryId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FinancePlaceRow')
class FinancePlaces extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  IntColumn get usados => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FinanceTemplateRow')
class FinanceTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  TextColumn get libroId => text().nullable()
      .references(FinanceAccounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get categoryId => text()();
  TextColumn get tipo => text()(); // 'ingreso'|'gasto'
  RealColumn get monto => real().nullable()();
  TextColumn get personaSitio => text().nullable()();
  TextColumn get nota => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FinanceBudgetRow')
class FinanceBudgets extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get categoryId => text()();
  IntColumn get anio => integer()();
  IntColumn get mes => integer()(); // 1-12
  RealColumn get montoLimite => real()();
  // Si true, este presupuesto se copia solo (sin preguntar) al mes
  // siguiente cuando el usuario entra a un mes vacío — opt-in explícito
  // por presupuesto, no un ajuste global. Los que NO lo tienen activado
  // siguen pasando por el aviso "¿mantener presupuestos del mes
  // anterior?" de siempre.
  BoolColumn get autoRepetir => boolean().withDefault(const Constant(false))();
}

/// Metas de ahorro (Fase 05): el dinero reservado vive dentro del saldo de
/// [accountId] — nunca se mueve a otro registro ni crea un ingreso/gasto —
/// así que una meta sigue descontando del "disponible" vía [totalReservado]
/// mientras esté 'activa' o 'pausada'. [monto] es lo aportado hasta ahora;
/// [montoObjetivo] es la meta. Cancelar libera el dinero (deja de contar
/// como reservado); finalizar lo mantiene reservado hasta que el usuario lo
/// retire explícitamente.
@DataClassName('FinanceReservationRow')
class FinanceReservations extends Table {
  TextColumn get id => text()();
  // Nullable desde Planificación v2: una meta 'virtual' no vive dentro de
  // ningún registro — descuenta del disponible global, no del de una
  // cuenta puntual. Una meta 'vinculada' sigue requiriendo accountId.
  TextColumn get accountId => text()
      .nullable()
      .references(FinanceAccounts, #id, onDelete: KeyAction.restrict)();
  TextColumn get nombre => text()();
  RealColumn get monto => real()();
  TextColumn get creadaEn => text()(); // ISO8601
  RealColumn get montoObjetivo => real().withDefault(const Constant(0))();
  TextColumn get fechaLimite => text().nullable()(); // YYYY-MM-DD, opcional
  // 'activa'|'pausada'|'finalizada'|'cancelada'
  TextColumn get estado => text().withDefault(const Constant('activa'))();
  // 'virtual' (sin cuenta, descuenta del disponible global) |
  // 'vinculada' (accountId fijo, descuenta del disponible de esa cuenta).
  TextColumn get modalidad => text().withDefault(const Constant('vinculada'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Historial de aportes/retiros de una meta (Planificación v2) — antes
/// solo existía el acumulado en FinanceReservations.monto, sin forma de
/// reconstruir qué pasó y cuándo.
@DataClassName('FinanceGoalMovementRow')
class FinanceGoalMovements extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()
      .references(FinanceReservations, #id, onDelete: KeyAction.cascade)();
  TextColumn get tipo => text()(); // 'aporte' | 'retiro'
  RealColumn get monto => real()();
  TextColumn get fecha => text()(); // ISO8601
  RealColumn get saldoResultante => real()();

  @override
  Set<Column> get primaryKey => {id};
}
