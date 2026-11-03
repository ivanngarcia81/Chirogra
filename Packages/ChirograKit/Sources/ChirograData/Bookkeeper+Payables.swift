import ChirograCore
import Foundation
import SwiftData

/// Resultado de registrar pagos programados: los que se registraron y los que no se pudieron (con el motivo).
public struct ScheduledPaymentRun {
    public var paid: [BillPayment] = []
    public var failures: [(bill: Bill, error: Error)] = []
}

/// Resultado de `Bookkeeper.runAutomations(asOf:)`.
public struct AutomationRun {
    public var recurring: RecurringRun
    public var autoPayments: ScheduledPaymentRun
}

// MARK: - Por pagar: pagos programados y en lote (canvas `MacPorPagar`, `ProveedorFicha`)

extension Bookkeeper {

    /// Programa el pago de una factura por pagar registrada. No mueve dinero ni hace asiento: Chirogra lo recuerda
    /// (campana, filtro «Programadas») y lo registra con `payScheduledBills` cuando se pida.
    public func schedulePayment(for bill: Bill, on date: Date, from account: Account, method: PaymentMethod = .bankTransfer) throws {
        guard bill.isOpen, bill.journalEntryID != nil else {
            throw BookkeepingError.invalidState(String(localized: "La factura del proveedor no está pendiente."))
        }
        guard account.subtype.isMoneyAccount, !account.isArchived else {
            throw BookkeepingError.invalidState(String(localized: "Elige una cuenta de banco, caja o tarjeta para el pago."))
        }
        bill.scheduledPaymentDate = Calendar.current.startOfDay(for: date)
        bill.scheduledPaymentAccountID = account.id
        bill.scheduledPaymentMethodRaw = method.rawValue
        audit("Bill", bill.id, "schedulePayment",
              String(localized: "Pago programado de \(bill.vendorNumber) para el \(date.formatted(date: .abbreviated, time: .omitted))"))
        try saveOrRollback()
    }

    /// Quita el pago programado (también el cargo automático) de una factura.
    public func unschedulePayment(for bill: Bill) throws {
        guard bill.scheduledPaymentDate != nil || bill.autoPay else { return }
        clearSchedule(of: bill)
        audit("Bill", bill.id, "unschedulePayment", String(localized: "Pago desprogramado de \(bill.vendorNumber)"))
        try saveOrRollback()
    }

    func clearSchedule(of bill: Bill) {
        bill.scheduledPaymentDate = nil
        bill.scheduledPaymentAccountID = nil
        bill.scheduledPaymentMethodRaw = ""
        bill.autoPay = false
    }

    /// Pago en lote: paga el saldo completo de cada factura, **un pago (y un asiento) por factura**, todos con la misma
    /// fecha, cuenta y método. Todo o nada: si una falla, no se guarda ninguno.
    @discardableResult
    public func payBills(
        _ bills: [Bill], on date: Date = Date(), from paymentAccount: Account, method: PaymentMethod = .bankTransfer, reference: String = ""
    ) throws -> [BillPayment] {
        guard !bills.isEmpty else { throw BookkeepingError.invalidState(String(localized: "Elige al menos una factura.")) }
        guard Set(bills.map(\.id)).count == bills.count else {
            throw BookkeepingError.invalidState(String(localized: "Hay facturas repetidas en el lote."))
        }
        do {
            let payments = try bills.map { bill in
                try pay(bill, amount: bill.balanceDue, date: date, from: paymentAccount, method: method, reference: reference, save: false)
            }
            audit("BillPayment", nil, "batchPay", String(localized: "Pago en lote de \(bills.count) facturas: \(Money(minorUnits: payments.reduce(0) { $0 + $1.amount }).formatted())"))
            try context.save()
            return payments
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Facturas abiertas con pago programado para `date` o antes (incluidas las de cargo automático).
    public func scheduledBills(dueOnOrBefore date: Date = Date(), calendar: Calendar = .current) throws -> [Bill] {
        let limit = calendar.startOfDay(for: date)
        return try context.fetch(FetchDescriptor<Bill>())
            .filter { $0.isOpen && $0.journalEntryID != nil }
            .filter { bill in bill.scheduledPaymentDate.map { calendar.startOfDay(for: $0) <= limit } ?? false }
            .sorted { ($0.scheduledPaymentDate ?? .distantPast) < ($1.scheduledPaymentDate ?? .distantPast) }
    }

    /// Registra los pagos programados que vencen `date` o antes, cada uno con su fecha programada, su cuenta y su método.
    /// Cada factura se guarda por separado: las que fallan (p. ej. periodo cerrado, cuenta archivada) quedan en `failures`
    /// y siguen programadas. Con `onlyAutoPay` solo las de cargo automático.
    @discardableResult
    public func payScheduledBills(dueOnOrBefore date: Date = Date(), onlyAutoPay: Bool = false, calendar: Calendar = .current) throws -> ScheduledPaymentRun {
        var run = ScheduledPaymentRun()
        for bill in try scheduledBills(dueOnOrBefore: date, calendar: calendar) where !onlyAutoPay || bill.autoPay {
            do {
                guard let account = try account(id: bill.scheduledPaymentAccountID ?? bill.vendor?.preferredPaymentAccountID) else {
                    throw BookkeepingError.unknownAccount
                }
                let payDate = min(bill.scheduledPaymentDate ?? date, date)
                let payment = try pay(bill, amount: bill.balanceDue, date: payDate, from: account,
                                      method: bill.scheduledPaymentMethod ?? .bankTransfer, save: false)
                audit("Bill", bill.id, "payScheduled", String(localized: "Pago programado registrado: \(bill.vendorNumber)"))
                try saveOrRollback()
                run.paid.append(payment)
            } catch {
                context.rollback()
                run.failures.append((bill, error))
            }
        }
        return run
    }

    /// Lo que la app hace sola al abrirse o volver al primer plano: genera los recurrentes hasta hoy y registra los
    /// pagos de cargo automático que vencen hoy o antes. Es idempotente.
    @discardableResult
    public func runAutomations(asOf date: Date = Date(), calendar: Calendar = .current) throws -> AutomationRun {
        let recurring = try generateRecurring(through: date, calendar: calendar)
        let payments = try payScheduledBills(dueOnOrBefore: date, onlyAutoPay: true, calendar: calendar)
        return AutomationRun(recurring: recurring, autoPayments: payments)
    }

    /// Anula una factura de proveedor sin pagos revirtiendo su asiento (con su fecha original).
    public func void(_ bill: Bill) throws {
        guard bill.isOpen, bill.amountPaid == 0 else {
            throw BookkeepingError.invalidState(String(localized: "Solo se anulan facturas de proveedor sin pagos."))
        }
        if let entry = try entry(id: bill.journalEntryID) {
            try reverse(entry, on: entry.date, memo: String(localized: "Anulación factura \(bill.vendorNumber)"), save: false)
        }
        clearSchedule(of: bill)
        bill.status = .void
        audit("Bill", bill.id, "void", String(localized: "Factura de proveedor anulada: \(bill.vendorNumber)"))
        try saveOrRollback()
    }
}
