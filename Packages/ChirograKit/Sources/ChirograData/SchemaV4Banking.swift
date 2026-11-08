import ChirograCore
import Foundation
import SwiftData

// Modelos nuevos del esquema 4 (docs/DATOS-V4.md): banca y conciliación (DISEÑO §4.6) y presupuestos. Mismas reglas
// que el resto (`SchemaV4Models.swift`). Las referencias a cuentas, documentos y asientos van por `UUID`, sin relación,
// para no multiplicar inversas en `Account` ni en `JournalEntry`.

extension SchemaV4 {

    /// Movimiento de un extracto bancario o de tarjeta, venga de donde venga (`BankTransactionSource`: CSV, OFX/QFX y,
    /// en el futuro, Plaid). Nace «por revisar» y termina emparejado con una línea del diario, categorizado (se creó
    /// un gasto, cobro o transferencia desde él) o ignorado.
    ///
    /// **Signo de `amount`:** el efecto en la cuenta contable vista como debe − haber. En un banco, positivo = depósito
    /// y negativo = cargo; en una tarjeta, negativo = compra (aumenta la deuda) y positivo = pago o devolución.
    @Model
    public final class BankTransaction {
        public var id: UUID = UUID()
        public var companyID: UUID?
        /// Cuenta contable de banco o tarjeta a la que pertenece el extracto.
        public var accountID: UUID?
        public var date: Date = Date()
        public var amount: Int64 = 0
        /// Descripción tal como viene del banco («UBER *TRIP HELP.UBER.COM»).
        public var details: String = ""
        /// Beneficiario o pagador, si el extracto lo separa (OFX `NAME`) o si una regla lo puso.
        public var payee: String = ""
        public var memo: String = ""
        public var checkNumber: String = ""
        /// Identificador del banco (OFX `FITID`) o, si el CSV no trae uno, un hash estable de fecha, importe y
        /// descripción (`BankStatementLine.stableID`). Con él no se importa dos veces lo mismo.
        public var externalID: String = ""
        public var sourceRaw: String = BankSourceKind.csv.rawValue
        public var statusRaw: String = BankTransactionStatus.toReview.rawValue
        /// Cuenta (de gasto, ingreso…) propuesta por una regla o elegida por el usuario para categorizarlo.
        public var categoryAccountID: UUID?
        public var vendorID: UUID?
        public var customerID: UUID?
        /// Regla que lo categorizó, si alguna.
        public var ruleID: UUID?
        /// Asiento y línea del diario con que quedó emparejado (la línea es la de `accountID`).
        public var matchedEntryID: UUID?
        public var matchedLineID: UUID?
        /// Documento creado desde el movimiento (gasto, cobro, asiento de transferencia).
        public var createdDocumentID: UUID?
        /// Importación en la que llegó (todas las líneas de un archivo comparten el mismo).
        public var importBatchID: UUID?
        public var importedAt: Date = Date()
        public var reviewedAt: Date?

        public init(accountID: UUID?, date: Date, amount: Int64, details: String, externalID: String, source: BankSourceKind) {
            self.accountID = accountID
            self.date = date
            self.amount = amount
            self.details = details
            self.externalID = externalID
            self.sourceRaw = source.rawValue
        }

        public var status: BankTransactionStatus {
            get { BankTransactionStatus(rawValue: statusRaw) ?? .toReview }
            set { statusRaw = newValue.rawValue }
        }

        public var source: BankSourceKind { BankSourceKind(rawValue: sourceRaw) ?? .csv }
        /// Entra dinero (depósito, o pago/devolución en una tarjeta).
        public var isInflow: Bool { amount > 0 }
        public var isPending: Bool { status == .toReview }
    }

    /// Regla de la bandeja «Por revisar»: «si la descripción contiene X → cuenta Y / proveedor Z». Se prueban por
    /// prioridad (mayor primero; a igualdad, la más antigua); la primera que encaja propone la categoría y, con
    /// `autoApply`, además registra el gasto o cobro sin pasar por la bandeja.
    @Model
    public final class BankRule {
        public var id: UUID = UUID()
        public var companyID: UUID?
        public var name: String = ""
        /// Texto que debe contener la descripción o el beneficiario (sin distinguir mayúsculas ni acentos).
        public var matchText: String = ""
        public var amountSignRaw: String = BankAmountSign.any.rawValue
        /// Solo para los movimientos de esta cuenta de banco o tarjeta; `nil` = de todas.
        public var bankAccountID: UUID?
        /// Cuenta en la que se categoriza (gasto, ingreso, otra cuenta de banco para transferencias…).
        public var targetAccountID: UUID?
        public var vendorID: UUID?
        /// Beneficiario con que se registra (vacío = el del movimiento).
        public var payee: String = ""
        public var autoApply: Bool = false
        public var priority: Int = 0
        public var isActive: Bool = true
        public var createdAt: Date = Date()

        public init(name: String, matchText: String, targetAccountID: UUID?, priority: Int = 0) {
            self.name = name
            self.matchText = matchText
            self.targetAccountID = targetAccountID
            self.priority = priority
        }

        public var amountSign: BankAmountSign {
            get { BankAmountSign(rawValue: amountSignRaw) ?? .any }
            set { amountSignRaw = newValue.rawValue }
        }
    }

    /// Cómo leer el CSV de un banco o tarjeta: columnas, formato de fecha y signo. Se guarda al importar por primera
    /// vez y se reutiliza (DISEÑO §4.6).
    @Model
    public final class BankImportProfile {
        public var id: UUID = UUID()
        public var companyID: UUID?
        public var accountID: UUID?
        public var name: String = ""
        /// `CSVColumnMapping` en JSON (columnas de fecha, descripción, importe o débito/crédito…).
        public var columnsJSON: String = ""
        /// Formato de fecha de `DateFormatter` («MM/dd/yyyy», «yyyy-MM-dd»…).
        public var dateFormat: String = "MM/dd/yyyy"
        public var amountSignRaw: String = CSVAmountSign.signed.rawValue
        public var delimiter: String = ","
        public var hasHeaderRow: Bool = true
        public var createdAt: Date = Date()
        public var lastUsedAt: Date?

        public init(accountID: UUID?, name: String) {
            self.accountID = accountID
            self.name = name
        }
    }

    /// Sesión de conciliación de una cuenta contra un extracto (DISEÑO §4.6): saldo inicial (el final de la anterior),
    /// fecha y saldo final del extracto. Se marcan líneas del diario (`JournalLine.reconciliationID`) hasta que la
    /// diferencia es 0 y entonces se cierra. Los saldos van en el lado normal de la cuenta (en una tarjeta, lo que se debe).
    @Model
    public final class Reconciliation {
        public var id: UUID = UUID()
        public var companyID: UUID?
        public var accountID: UUID?
        public var statementDate: Date = Date()
        public var statementEndingBalance: Int64 = 0
        public var beginningBalance: Int64 = 0
        public var statusRaw: String = ReconciliationStatus.inProgress.rawValue
        public var closedAt: Date?
        public var createdAt: Date = Date()

        public init(accountID: UUID?, statementDate: Date, statementEndingBalance: Int64, beginningBalance: Int64) {
            self.accountID = accountID
            self.statementDate = statementDate
            self.statementEndingBalance = statementEndingBalance
            self.beginningBalance = beginningBalance
        }

        public var status: ReconciliationStatus {
            get { ReconciliationStatus(rawValue: statusRaw) ?? .inProgress }
            set { statusRaw = newValue.rawValue }
        }

        public var isCompleted: Bool { status == .completed }
    }

    /// Presupuesto de un año fiscal: importes por cuenta y mes (`BudgetLine`).
    @Model
    public final class Budget {
        public var id: UUID = UUID()
        public var companyID: UUID?
        public var name: String = ""
        /// Año natural en que **empieza** el año fiscal (con inicio en julio, 2026 = jul 2026 – jun 2027).
        public var fiscalYear: Int = 0
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \BudgetLine.budget)
        public var lines: [BudgetLine]? = []

        public init(name: String, fiscalYear: Int) {
            self.name = name
            self.fiscalYear = fiscalYear
        }

        /// Importe presupuestado de una cuenta en un mes (1–12, mes natural).
        public func amount(accountID: UUID, month: Int) -> Int64 {
            (lines ?? []).filter { $0.accountID == accountID && $0.month == month }.reduce(0) { $0 + $1.amount }
        }

        public var total: Int64 { (lines ?? []).reduce(0) { $0 + $1.amount } }
    }

    /// Importe presupuestado de una cuenta en un mes. `amount` va en el lado normal de la cuenta: lo que se espera
    /// ingresar en una de ingresos y gastar en una de gastos.
    @Model
    public final class BudgetLine {
        public var id: UUID = UUID()
        public var companyID: UUID?
        public var accountID: UUID?
        /// Mes natural (1 = enero … 12 = diciembre); el año sale de `Budget.fiscalYear` y del inicio del año fiscal.
        public var month: Int = 1
        public var amount: Int64 = 0

        public var budget: Budget?

        public init(accountID: UUID?, month: Int, amount: Int64) {
            self.accountID = accountID
            self.month = month
            self.amount = amount
        }
    }
}

// MARK: - Enums de banca

/// Estado de un movimiento en la bandeja.
public enum BankTransactionStatus: String, CaseIterable, Sendable, Codable {
    /// Por revisar (puede traer una categoría propuesta por una regla).
    case toReview
    /// Se creó un gasto, cobro o transferencia desde él.
    case categorized
    /// Emparejado con una línea del diario que ya existía.
    case matched
    /// Ignorado (duplicado, movimiento interno ya registrado…).
    case ignored
}

/// Signo de los movimientos a los que aplica una regla.
public enum BankAmountSign: String, CaseIterable, Sendable, Codable {
    case any
    /// Solo entradas (depósitos, pagos a la tarjeta).
    case inflow
    /// Solo salidas (cargos, compras).
    case outflow

    public func matches(_ amount: Int64) -> Bool {
        switch self {
        case .any: true
        case .inflow: amount > 0
        case .outflow: amount < 0
        }
    }
}

public enum ReconciliationStatus: String, CaseIterable, Sendable, Codable {
    case inProgress, completed
}
