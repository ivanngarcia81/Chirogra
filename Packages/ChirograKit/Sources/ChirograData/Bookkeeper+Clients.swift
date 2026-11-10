import ChirograCore
import Foundation
import SwiftData

// MARK: - Panel de clientes (plan para contadores, docs/PANEL-CLIENTES.md)
//
// Lo que el contador ve de cada empresa sin abrirla: su estado (urgente, pendiente, al día o archivada), lo pendiente
// (banco por revisar, facturas vencidas, sales tax, conciliación, avisos) y cómo están sus libros (cierre, último
// movimiento, por cobrar y por pagar). Todo sale de los datos que ya existen: no cambia el esquema.

/// Resumen de una empresa para el panel de clientes.
public struct ClientSummary: Identifiable, Sendable, Equatable {
    /// Estado general, en el orden de urgencia del panel.
    public enum Status: Int, Comparable, Sendable, CaseIterable {
        /// Sales tax vencido o que vence en 7 días o menos, o un banco sin conciliar hace más de 60 días.
        case urgent
        /// Banco por revisar, facturas vencidas, conciliación de más de 30 días o avisos sin leer.
        case pending
        case upToDate
        case archived

        public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Sales tax por declarar: el del último periodo terminado si queda saldo, si no el del periodo en curso.
    public struct SalesTaxDue: Sendable, Equatable {
        public var amount: Int64
        public var deadline: Date
        /// Días hasta la fecha límite (negativo: vencido).
        public var days: Int
        public var agencyName: String
    }

    /// La cuenta de banco o tarjeta con la conciliación más atrasada.
    public struct ReconciliationLag: Sendable, Equatable {
        public var accountID: UUID
        /// Nombre con los últimos dígitos («Chase ••4410»).
        public var accountName: String
        /// Fecha del extracto de la última conciliación terminada; `nil` si nunca se concilió.
        public var reconciledThrough: Date?
        /// Días sin conciliar: desde el extracto o, si nunca se concilió, desde el primer movimiento.
        public var days: Int
    }

    /// Días antes de la fecha límite del sales tax en que la empresa pasa a urgente.
    public static let salesTaxUrgentDays = 7
    /// Días sin conciliar para que cuente como pendiente y como urgente.
    public static let reconciliationLateDays = 30
    public static let reconciliationUrgentDays = 60

    public var id: UUID
    public var name: String
    public var entityType: EntityType
    /// Código del estado («TX»).
    public var state: String
    public var isArchived: Bool
    public var isActive: Bool
    public var bankToReview: Int
    public var overdueInvoices: Int
    public var overdueAmount: Int64
    public var unreadNotices: Int
    public var salesTax: SalesTaxDue?
    public var reconciliation: ReconciliationLag?
    /// Hay una conciliación empezada sin terminar.
    public var reconciliationInProgress: Bool
    /// Libros cerrados hasta esta fecha (incluida).
    public var lockDate: Date?
    /// Cuándo se registró el último asiento.
    public var lastActivity: Date?
    public var receivables: Int64
    public var payables: Int64

    public var salesTaxIsUrgent: Bool { salesTax.map { $0.days <= Self.salesTaxUrgentDays } ?? false }
    public var reconciliationIsLate: Bool { (reconciliation?.days ?? 0) > Self.reconciliationLateDays }
    public var reconciliationIsUrgent: Bool { (reconciliation?.days ?? 0) > Self.reconciliationUrgentDays }

    public var status: Status {
        if isArchived { return .archived }
        if salesTaxIsUrgent || reconciliationIsUrgent { return .urgent }
        if bankToReview > 0 || overdueInvoices > 0 || reconciliationIsLate || unreadNotices > 0 { return .pending }
        return .upToDate
    }

    public var needsAttention: Bool { status == .urgent || status == .pending }
}

extension Bookkeeper {

    /// Resumen de cada empresa para el panel de clientes, en el orden del selector (las archivadas al final).
    public func clientSummaries(includeArchived: Bool = true, asOf date: Date = Date(),
                                calendar: Calendar = .current) throws -> [ClientSummary] {
        let active = try resolvedCompanyID()
        let all = try companies(includeArchived: includeArchived)
        return try (all.filter { !$0.isArchived } + all.filter(\.isArchived)).map { company in
            try forCompany(company.id).clientSummary(of: company, isActive: company.id == active, asOf: date, calendar: calendar)
        }
    }

    /// Resumen de la empresa de este `Bookkeeper`.
    func clientSummary(of company: Company, isActive: Bool, asOf date: Date, calendar: Calendar) throws -> ClientSummary {
        let invoices = try fetch(Invoice.self).filter { $0.isOpen && $0.balanceDue != 0 }
        let overdue = invoices.filter { $0.daysOverdue(asOf: date) != nil }
        let bills = try fetch(Bill.self).filter { $0.isOpen && $0.journalEntryID != nil }
        let toReview = BankTransactionStatus.toReview.rawValue
        let reconciliations = try fetch(Reconciliation.self)
        let lastEntry = try fetch(JournalEntry.self, sortBy: [SortDescriptor(\.createdAt, order: .reverse)], limit: 1).first
        return ClientSummary(
            id: company.id, name: company.name, entityType: company.entityType, state: company.state,
            isArchived: company.isArchived, isActive: isActive,
            bankToReview: try count(BankTransaction.self, #Predicate { $0.statusRaw == toReview }),
            overdueInvoices: overdue.count,
            overdueAmount: overdue.reduce(0) { $0 + $1.balanceDue },
            unreadNotices: try unreadNoticeCount(asOf: date, calendar: calendar),
            salesTax: try nextSalesTaxDue(asOf: date, calendar: calendar),
            reconciliation: try reconciliationLag(reconciliations: reconciliations, asOf: date, calendar: calendar),
            reconciliationInProgress: reconciliations.contains { !$0.isCompleted },
            lockDate: company.lockDate,
            lastActivity: lastEntry?.createdAt,
            receivables: invoices.reduce(0) { $0 + $1.balanceDue },
            payables: bills.reduce(0) { $0 + $1.balanceDue }
        )
    }

    /// El sales tax que toca declarar antes: por cada agencia, el saldo del último periodo terminado que aún no se pagó
    /// (lo que había al cierre menos los cargos posteriores a la cuenta) o, si ya está pagado, lo acumulado en el periodo
    /// en curso. De todas las agencias, el de fecha límite más próxima.
    func nextSalesTaxDue(asOf date: Date, calendar: Calendar) throws -> ClientSummary.SalesTaxDue? {
        var candidates: [ClientSummary.SalesTaxDue] = []
        let today = calendar.startOfDay(for: date)
        func days(to deadline: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: deadline)).day ?? 0
        }
        for agency in try fetch(TaxAgency.self) where !agency.isArchived {
            let liability = try account(id: agency.liabilityAccountID) ?? systemAccount(.salesTaxPayable)
            let last = try lastSalesTaxFilingPeriod(for: agency, asOf: date, calendar: calendar)
            let lastEnd = Self.endOfDay(last.end, calendar)
            let atEnd = postedBalance(of: liability, asOf: lastEnd)
            let paidSince = postedLedgerLines(of: liability).filter { $0.date > lastEnd }.reduce(0) { $0 + $1.debit }
            let unpaid = atEnd - paidSince
            if unpaid > 0 {
                candidates.append(.init(amount: unpaid, deadline: last.deadline, days: days(to: last.deadline), agencyName: agency.name))
                continue
            }
            let accrued = postedBalance(of: liability, asOf: Self.endOfDay(date, calendar))
            guard accrued > 0 else { continue }
            let current = salesTaxFilingPeriod(for: agency, containing: date, calendar: calendar)
            candidates.append(.init(amount: accrued, deadline: current.deadline, days: days(to: current.deadline), agencyName: agency.name))
        }
        return candidates.min { ($0.deadline, $0.agencyName) < ($1.deadline, $1.agencyName) }
    }

    /// La cuenta de banco o tarjeta más atrasada en conciliar. Las que no tienen movimientos ni conciliaciones no cuentan.
    func reconciliationLag(reconciliations: [Reconciliation], asOf date: Date,
                           calendar: Calendar) throws -> ClientSummary.ReconciliationLag? {
        let today = calendar.startOfDay(for: date)
        let banks = try accounts().filter { $0.subtype == .bank || $0.subtype == .creditCard }
        let lags: [ClientSummary.ReconciliationLag] = banks.compactMap { account in
            let through = reconciliations.filter { $0.accountID == account.id && $0.isCompleted }.map(\.statementDate).max()
            guard let since = through ?? postedLedgerLines(of: account).map(\.date).min() else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: today).day ?? 0
            return .init(accountID: account.id, accountName: account.maskedName, reconciledThrough: through, days: max(days, 0))
        }
        return lags.max { ($0.days, $1.accountName) < ($1.days, $0.accountName) }
    }
}
