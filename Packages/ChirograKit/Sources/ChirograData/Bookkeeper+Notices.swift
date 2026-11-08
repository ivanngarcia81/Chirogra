import ChirograCore
import Foundation
import SwiftData

/// Tipo de aviso de la campana.
public enum NoticeKind: String, CaseIterable, Sendable {
    /// Factura de venta vencida con saldo.
    case overdueInvoice
    /// Factura por pagar que vence en los próximos 7 días (sin pago programado).
    case billDueSoon
    /// Pago programado para hoy o antes, aún sin registrar.
    case scheduledPaymentDue
    /// Gasto o factura generado por una plantilla recurrente en los últimos 7 días.
    case recurringGenerated
    /// Sales tax por declarar: la fecha límite de la agencia cae en los próximos 15 días y hay saldo.
    case salesTaxDue
}

/// Aviso calculado a partir de los datos. La UI pone el texto (el nombre y el importe vienen aquí).
public struct Notice: Identifiable, Hashable, Sendable {
    /// Clave estable (tipo + documento + fecha): con ella se marca leído o descartado.
    public var id: String
    public var kind: NoticeKind
    /// Fecha relevante: vencimiento, pago programado, repetición o fecha límite.
    public var date: Date
    /// Días hasta `date` desde hoy (negativo si ya pasó).
    public var days: Int
    public var amount: Int64
    /// Cliente, proveedor, beneficiario o agencia.
    public var party: String
    /// Número de documento («F-1038», «B-221»), si lo hay.
    public var reference: String
    /// Documento al que lleva el aviso (factura, factura por pagar, gasto o agencia).
    public var documentID: UUID?
    /// Para `recurringGenerated`: el gasto se creó sin asiento y hay que confirmarlo.
    public var needsConfirmation: Bool = false
    public var isRead: Bool = false
}

/// Periodo de declaración de sales tax de una agencia y su fecha límite.
public struct SalesTaxFilingPeriod: Sendable, Equatable {
    public var start: Date
    /// Último día del periodo.
    public var end: Date
    public var deadline: Date
}

// MARK: - Avisos (campana)

extension Bookkeeper {
    /// Día del mes siguiente al periodo en que vence la declaración de sales tax (Texas y la mayoría de estados: el 20).
    public static let salesTaxFilingDueDay = 20
    static let billDueSoonDays = 7
    static let recentRecurringDays = 7
    static let salesTaxNoticeDays = 15

    /// Avisos actuales, de los más urgentes a los menos. No incluye los descartados.
    public func notices(asOf date: Date = Date(), calendar: Calendar = .current) throws -> [Notice] {
        let today = calendar.startOfDay(for: date)
        func days(to day: Date) -> Int { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0 }
        var notices: [Notice] = []

        for invoice in try fetch(Invoice.self) {
            guard let overdue = invoice.daysOverdue(asOf: date, calendar: calendar) else { continue }
            notices.append(Notice(id: "overdueInvoice:\(invoice.id.uuidString)", kind: .overdueInvoice, date: invoice.dueDate, days: -overdue,
                                  amount: invoice.balanceDue, party: invoice.customer?.name ?? "", reference: invoice.number, documentID: invoice.id))
        }

        for bill in try fetch(Bill.self) where bill.isOpen && bill.journalEntryID != nil && bill.balanceDue > 0 {
            if let scheduled = bill.scheduledPaymentDate {
                guard calendar.startOfDay(for: scheduled) <= today else { continue }
                notices.append(Notice(id: "scheduledPayment:\(bill.id.uuidString):\(Self.dayKey(scheduled, calendar))", kind: .scheduledPaymentDue,
                                      date: scheduled, days: days(to: scheduled), amount: bill.balanceDue, party: bill.vendor?.name ?? "",
                                      reference: bill.vendorNumber, documentID: bill.id))
            } else {
                let until = days(to: bill.dueDate)
                guard (0...Self.billDueSoonDays).contains(until) else { continue }
                notices.append(Notice(id: "billDue:\(bill.id.uuidString):\(Self.dayKey(bill.dueDate, calendar))", kind: .billDueSoon,
                                      date: bill.dueDate, days: until, amount: bill.balanceDue, party: bill.vendor?.name ?? "",
                                      reference: bill.vendorNumber, documentID: bill.id))
            }
        }

        let recentStart = calendar.date(byAdding: .day, value: -(Self.recentRecurringDays - 1), to: today) ?? today
        func isRecent(_ day: Date?) -> Bool {
            guard let day else { return false }
            let start = calendar.startOfDay(for: day)
            return start >= recentStart && start <= today
        }
        for expense in try fetch(Expense.self) where expense.recurringTemplateID != nil && !expense.isVoid && isRecent(expense.recurrenceDate) {
            notices.append(Notice(id: "recurring:\(expense.id.uuidString)", kind: .recurringGenerated, date: expense.recurrenceDate ?? expense.date,
                                  days: days(to: expense.date), amount: expense.total, party: expense.payee, reference: "",
                                  documentID: expense.id, needsConfirmation: !expense.isPosted))
        }
        for bill in try fetch(Bill.self) where bill.recurringTemplateID != nil && bill.status != .void && isRecent(bill.recurrenceDate) {
            notices.append(Notice(id: "recurring:\(bill.id.uuidString)", kind: .recurringGenerated, date: bill.recurrenceDate ?? bill.billDate,
                                  days: days(to: bill.billDate), amount: bill.total, party: bill.vendor?.name ?? "", reference: bill.vendorNumber,
                                  documentID: bill.id))
        }

        let lines = try ledgerLines()
        for agency in try fetch(TaxAgency.self) where !agency.isArchived {
            let period = try lastSalesTaxFilingPeriod(for: agency, asOf: date, calendar: calendar)
            let until = days(to: period.deadline)
            guard (0...Self.salesTaxNoticeDays).contains(until) else { continue }
            let liability = try account(id: agency.liabilityAccountID) ?? systemAccount(.salesTaxPayable)
            let owed = ReportBuilder.balance(of: liability.ledgerAccount, lines: lines.filter { $0.date <= Self.endOfDay(period.end, calendar) })
            guard owed > 0 else { continue }
            notices.append(Notice(id: "salesTax:\(agency.id.uuidString):\(Self.dayKey(period.end, calendar))", kind: .salesTaxDue,
                                  date: period.deadline, days: until, amount: owed, party: agency.name, reference: "", documentID: agency.id))
        }

        let states = Dictionary(try fetch(NoticeState.self).map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
        return notices
            .filter { !(states[$0.id]?.isDismissed ?? false) }
            .map { notice in
                var notice = notice
                notice.isRead = states[notice.id]?.isRead ?? false
                return notice
            }
            .sorted { ($0.kind.priority, $0.days, $0.id) < ($1.kind.priority, $1.days, $1.id) }
    }

    /// Avisos sin leer (para el globo de la campana).
    public func unreadNoticeCount(asOf date: Date = Date(), calendar: Calendar = .current) throws -> Int {
        try notices(asOf: date, calendar: calendar).filter { !$0.isRead }.count
    }

    public func markNoticeRead(_ id: String) throws {
        try noticeState(id).isRead = true
        try saveOrRollback()
    }

    public func markAllNoticesRead(asOf date: Date = Date(), calendar: Calendar = .current) throws {
        for notice in try notices(asOf: date, calendar: calendar) where !notice.isRead { try noticeState(notice.id).isRead = true }
        try saveOrRollback()
    }

    /// Descarta un aviso: no vuelve a salir (un aviso nuevo del mismo documento, con otra fecha, sí).
    public func dismissNotice(_ id: String) throws {
        let state = try noticeState(id)
        state.isDismissed = true
        state.isRead = true
        try saveOrRollback()
    }

    private func noticeState(_ key: String) throws -> NoticeState {
        let state = try fetch(NoticeState.self, #Predicate { $0.key == key }).first ?? {
            let created = NoticeState(key: key)
            insert(created)
            return created
        }()
        state.updatedAt = Date()
        return state
    }

    // MARK: Periodos de sales tax

    /// Periodo de declaración (según la frecuencia de la agencia) que contiene `date`, con su fecha límite
    /// (el día `salesTaxFilingDueDay` del mes siguiente al cierre del periodo).
    public func salesTaxFilingPeriod(for agency: TaxAgency, containing date: Date, calendar: Calendar = .current) -> SalesTaxFilingPeriod {
        let months: Int
        switch FilingFrequency(rawValue: agency.filingFrequencyRaw) ?? .quarterly {
        case .monthly: months = 1
        case .quarterly: months = 3
        case .annual: months = 12
        }
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let startMonth = ((month - 1) / months) * months + 1
        let start = calendar.date(from: DateComponents(year: components.year, month: startMonth, day: 1)) ?? date
        let nextStart = calendar.date(byAdding: .month, value: months, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: nextStart) ?? start
        let deadline = calendar.date(bySetting: .day, value: Self.salesTaxFilingDueDay, of: nextStart)
            ?? calendar.date(byAdding: .day, value: Self.salesTaxFilingDueDay - 1, to: nextStart) ?? nextStart
        return SalesTaxFilingPeriod(start: start, end: end, deadline: calendar.startOfDay(for: deadline))
    }

    /// Último periodo ya terminado a `date` (el que toca declarar).
    public func lastSalesTaxFilingPeriod(for agency: TaxAgency, asOf date: Date, calendar: Calendar = .current) throws -> SalesTaxFilingPeriod {
        let current = salesTaxFilingPeriod(for: agency, containing: date, calendar: calendar)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        return salesTaxFilingPeriod(for: agency, containing: previousDay, calendar: calendar)
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func endOfDay(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: date)) ?? date
    }
}

extension NoticeKind {
    /// Orden en la campana: lo de hoy y lo vencido primero.
    var priority: Int {
        switch self {
        case .scheduledPaymentDue: 0
        case .overdueInvoice: 1
        case .salesTaxDue: 2
        case .billDueSoon: 3
        case .recurringGenerated: 4
        }
    }
}
