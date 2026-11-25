import ChirograCore
import Foundation
import SwiftData

// MARK: - Apartado para impuestos estimados (1.4, docs/PLAN-1.4.md §3; canvas «Chirogra 1.4», tableros `Apartado`,
// `PagoIRS`, `MacApartado`)
//
// Cuánto apartar de la ganancia de cada periodo del 1040-ES (`EstimatedTaxCalendar`) y los pagos hechos al IRS. Es una
// guía: el porcentaje lo pone el usuario y el monto real lo dice su contador.

/// Un pago del año en la tabla «Las cuatro fechas».
public struct EstimatedTaxRow: Identifiable, Sendable {
    public let period: EstimatedTaxCalendar.Period
    /// Ganancia del periodo (hasta hoy si está en curso; 0 si aún no empieza).
    public let profit: Int64
    public let toSetAside: Int64
    public let paid: Int64
    /// Último pago registrado de este periodo.
    public let lastPaymentDate: Date?
    public let isStarted: Bool
    public var id: Int { period.number }
    public var isPaid: Bool { paid > 0 }
}

/// Lo que enseñan la tarjeta de Inicio y Reportes y la pantalla de impuestos estimados.
public struct EstimatedTaxSummary: Sendable {
    public let percent: Int
    public let showsCard: Bool
    /// El pago que toca atender (el del periodo de hoy, o el anterior si aún no vence y no se pagó).
    public let focus: EstimatedTaxRow
    /// Días que faltan para que venza (0 = hoy; negativo = vencido).
    public let daysLeft: Int
    /// Los cuatro pagos del año fiscal del pago que toca.
    public let rows: [EstimatedTaxRow]
    public var taxYear: Int { focus.period.year }
    public var paidThisYear: Int64 { rows.reduce(0) { $0 + $1.paid } }
    /// Lo pagado más lo que falta por apartar del pago que toca (canvas: «Apartado en 2026»).
    public var setAsideThisYear: Int64 { paidThisYear + max(0, focus.toSetAside - focus.paid) }
}

extension Bookkeeper {

    // MARK: Ajuste

    /// El ajuste de la empresa (el más antiguo, si iCloud trajo dos), o `nil` si nunca se tocó.
    public func estimatedTaxSetting() throws -> EstimatedTaxSetting? {
        try fetch(EstimatedTaxSetting.self, sortBy: [SortDescriptor(\.createdAt)]).first
    }

    /// Porcentaje (entre 1 y 60) y si la tarjeta sale en Inicio y Reportes.
    public func setEstimatedTax(percent: Int? = nil, showsCard: Bool? = nil) throws {
        try ensureWritable()
        let setting: EstimatedTaxSetting
        if let existing = try estimatedTaxSetting() {
            setting = existing
        } else {
            setting = EstimatedTaxSetting()
            insert(setting)
        }
        var changes = AuditChanges()
        if let percent {
            let clamped = min(60, max(1, percent))
            changes.field(String(localized: "Porcentaje"), "\(setting.percent) %", "\(clamped) %")
            setting.percent = clamped
        }
        if let showsCard {
            changes.field(String(localized: "Tarjeta en Inicio y Reportes"), setting.showsCard ? String(localized: "Sí") : String(localized: "No"),
                        showsCard ? String(localized: "Sí") : String(localized: "No"))
            setting.showsCard = showsCard
        }
        if !changes.isEmpty {
            audit(AuditSubject.estimatedTax.rawValue, setting.id, "update", String(localized: "Apartado para impuestos cambiado"), changes: changes)
        }
        try saveOrRollback()
    }

    // MARK: Resumen

    public func estimatedTaxPayments(taxYear: Int? = nil) throws -> [EstimatedTaxPayment] {
        try fetch(EstimatedTaxPayment.self, sortBy: [SortDescriptor(\.date)]).filter { taxYear == nil || $0.taxYear == taxYear }
    }

    /// La tarjeta y la pantalla de impuestos estimados a `today`. La ganancia sale del estado de resultados en `basis`.
    public func estimatedTaxSummary(today: Date = Date(), basis: AccountingBasis = .accrual,
                                    calendar: Calendar = .current) throws -> EstimatedTaxSummary? {
        let setting = try estimatedTaxSetting()
        let percent = setting?.percent ?? 25
        let payments = try estimatedTaxPayments()
        func paid(_ period: EstimatedTaxCalendar.Period) -> [EstimatedTaxPayment] {
            payments.filter { $0.taxYear == period.year && $0.period == period.number }
        }
        guard let focus = EstimatedTaxCalendar.focus(today: today, isPaid: { !paid($0).isEmpty }, calendar: calendar) else { return nil }
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))?.addingTimeInterval(-1) ?? today
        let rows = try EstimatedTaxCalendar.periods(of: focus.year, calendar: calendar).map { period -> EstimatedTaxRow in
            let started = period.start <= today
            let profit = started
                ? try incomeStatement(from: period.start, to: min(period.end.addingTimeInterval(-1), endOfToday), basis: basis).netIncome
                : 0
            let made = paid(period)
            return EstimatedTaxRow(period: period, profit: profit, toSetAside: EstimatedTaxCalendar.setAside(profit: profit, percent: percent),
                                   paid: made.reduce(0) { $0 + $1.amount }, lastPaymentDate: made.last?.date, isStarted: started)
        }
        guard let focusRow = rows.first(where: { $0.period.number == focus.number }) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: focus.due).day ?? 0
        return EstimatedTaxSummary(percent: percent, showsCard: setting?.showsCard ?? true, focus: focusRow, daysLeft: days, rows: rows)
    }

    // MARK: Pagos

    /// Anota un pago al IRS: el asiento (de la cuenta de la que salió a retiros del dueño) y el pago. Chirogra solo lo
    /// anota; el pago se hace con el IRS.
    @discardableResult
    public func recordEstimatedTaxPayment(taxYear: Int, period: Int, date: Date, amount: Int64, fromAccountID: UUID) throws -> EstimatedTaxPayment {
        try ensureWritable()
        guard (1...4).contains(period) else { throw BookkeepingError.invalidState(String(localized: "El pago tiene que ser del 1.º al 4.º.")) }
        guard amount > 0 else { throw BookkeepingError.invalidState(String(localized: "Escribe cuánto pagaste.")) }
        let draw = try systemAccount(.ownersDraw)
        let payment = EstimatedTaxPayment(taxYear: taxYear, period: period, date: date, amount: amount, accountID: fromAccountID)
        insert(payment)
        let memo = String(localized: "Impuesto estimado \(String(taxYear)) · \(Self.periodTitle(period)) (1040-ES)")
        let entry = try post(JournalEntryDraft(date: date, memo: memo, source: .estimatedTax,
                                               lines: [.debit(draw.id, amount), .credit(fromAccountID, amount)]),
                             sourceDocumentID: payment.id, save: false)
        payment.journalEntryID = entry.id
        audit(AuditSubject.estimatedTax.rawValue, payment.id, "create",
              String(localized: "Pago al IRS: \(AuditFormat.money(amount)) · \(memo)"))
        try saveOrRollback()
        return payment
    }

    /// Quita un pago anotado por error: revierte su asiento en la fecha del pago y lo borra.
    public func deleteEstimatedTaxPayment(_ payment: EstimatedTaxPayment) throws {
        try ensureWritable()
        if let entry = try entry(id: payment.journalEntryID), !entry.isReversed {
            _ = try reverse(entry, on: payment.date, save: false)
        }
        audit(AuditSubject.estimatedTax.rawValue, payment.id, "delete",
              String(localized: "Pago al IRS eliminado: \(AuditFormat.money(payment.amount)) · \(String(payment.taxYear)) \(Self.periodTitle(payment.period))"))
        context.delete(payment)
        try saveOrRollback()
    }

    /// «1.º pago», «2.º pago»…
    public static func periodTitle(_ number: Int) -> String {
        switch number {
        case 1: String(localized: "1.er pago")
        case 2: String(localized: "2.º pago")
        case 3: String(localized: "3.er pago")
        default: String(localized: "4.º pago")
        }
    }
}
