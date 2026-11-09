import ChirograCore
import Foundation
import SwiftData

// MARK: - Reportes de la fase 2: base caja y flujo de efectivo (DISEÑO §4.7, docs/DATOS-V4.md §4)

/// Base contable de un reporte.
public enum AccountingBasis: String, CaseIterable, Sendable, Codable {
    /// Devengo: lo de siempre (el ingreso al facturar, el gasto al recibir la factura del proveedor).
    case accrual
    /// Caja: el ingreso al cobrar y el gasto al pagar.
    case cash
}

extension Bookkeeper {

    /// Líneas contabilizadas en la base pedida. En devengo, `ledgerLines()`; en caja, `cashBasisLedgerLines()`.
    public func ledgerLines(basis: AccountingBasis) throws -> [LedgerLine] {
        switch basis {
        case .accrual: try ledgerLines()
        case .cash: try cashBasisLedgerLines()
        }
    }

    /// Las líneas del diario vistas en **base caja**, balanceadas asiento por asiento (así la balanza, el balance y el
    /// estado de resultados de `ReportBuilder` sirven igual):
    /// - los asientos de facturas, notas de crédito y facturas de proveedor (y sus reversiones y correcciones) no cuentan;
    /// - en cada **cobro**, la línea de cuentas por cobrar se sustituye por las líneas de la factura cobrada (ingresos,
    ///   sales tax, descuento) en proporción a lo cobrado sobre lo que se debía (total menos notas de crédito de esa
    ///   factura), con el reparto exacto al centavo;
    /// - en cada **pago a proveedor**, la de cuentas por pagar se sustituye igual por las líneas de gasto de la factura;
    /// - en un **reembolso** de saldo a favor, la de cuentas por cobrar, por las líneas de las notas de crédito reembolsadas;
    /// - lo demás (gastos pagados al momento, depósitos, transferencias, asientos manuales, saldos iniciales) queda igual.
    /// Aproximación conocida: una nota de crédito aplicada a **otra** factura del cliente no cambia el reparto.
    public func cashBasisLedgerLines() throws -> [LedgerLine] {
        let entries = try postedEntries()
        let entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let accounts = try accounts(includeArchived: true)
        let receivable = Set(accounts.filter { $0.subtype == .accountsReceivable }.map(\.id))
        let payable = Set(accounts.filter { $0.subtype == .accountsPayable }.map(\.id))
        let invoices = try fetch(Invoice.self)
        let bills = try fetch(Bill.self)
        let notes = try fetch(CreditNote.self)
        let accrualDocuments = Set(invoices.map(\.id) + bills.map(\.id) + notes.map(\.id))
        let payments = Dictionary(try fetch(PaymentReceived.self).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let billPayments = Dictionary(try fetch(BillPayment.self).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        /// Neto (debe − haber) por cuenta de las líneas de un asiento que no son de `excluded`.
        func mix(_ entryID: UUID?, excluding excluded: Set<UUID>) -> [(UUID, Int64)] {
            guard let entryID, let entry = entriesByID[entryID] else { return [] }
            return (entry.lines ?? []).compactMap { line in
                guard let id = line.account?.id, !excluded.contains(id) else { return nil }
                return (id, line.debit - line.credit)
            }
        }
        var invoiceMixes: [UUID: [(UUID, Int64)]] = [:]
        func invoiceMix(_ invoice: Invoice) -> [(UUID, Int64)] {
            if let cached = invoiceMixes[invoice.id] { return cached }
            let result = mix(invoice.journalEntryID, excluding: receivable)
                + (invoice.creditNotes ?? []).flatMap { mix($0.journalEntryID, excluding: receivable) }
            invoiceMixes[invoice.id] = result
            return result
        }
        /// Líneas que suman `total` (debe − haber) repartido según `weights`.
        func allocated(_ total: Int64, over weights: [(UUID, Int64)], date: Date, entryID: UUID) -> [LedgerLine]? {
            guard weights.reduce(0, { $0 + $1.1 }) != 0 else { return nil }
            return zip(weights, ReportBuilder.allocateSigned(total, weights: weights.map(\.1))).compactMap { weight, share in
                share == 0 ? nil : LedgerLine(accountID: weight.0, date: date, debit: max(share, 0), credit: max(-share, 0), entryID: entryID)
            }
        }

        var result: [LedgerLine] = []
        for entry in entries {
            if let source = entry.sourceDocumentID, accrualDocuments.contains(source) { continue }
            for line in entry.lines ?? [] {
                guard let accountID = line.account?.id else { continue }
                let original = LedgerLine(accountID: accountID, date: entry.date, debit: line.debit, credit: line.credit, entryID: entry.id)
                let net = line.debit - line.credit
                var replacement: [LedgerLine]?
                if receivable.contains(accountID), let payment = entry.sourceDocumentID.flatMap({ payments[$0] }) {
                    var lines: [LedgerLine] = []
                    var covered: Int64 = 0
                    for application in payment.applications ?? [] {
                        guard let invoice = application.invoice,
                              let part = allocated(-application.amount, over: invoiceMix(invoice), date: entry.date, entryID: entry.id) else { continue }
                        lines += part
                        covered -= application.amount
                    }
                    if covered == net { replacement = lines }
                } else if payable.contains(accountID), let payment = entry.sourceDocumentID.flatMap({ billPayments[$0] }),
                          let bill = payment.bill {
                    replacement = allocated(net, over: mix(bill.journalEntryID, excluding: payable), date: entry.date, entryID: entry.id)
                } else if receivable.contains(accountID), entry.source == .customerRefund,
                          let customerID = entry.sourceDocumentID {
                    let refunded = notes.filter { $0.customer?.id == customerID && $0.refundedAmount > 0 }
                    let weights = refunded.flatMap { note -> [(UUID, Int64)] in
                        let noteMix = mix(note.journalEntryID, excluding: receivable)
                        let noteTotal = noteMix.reduce(0) { $0 + $1.1 }
                        guard noteTotal != 0 else { return [] }
                        return zip(noteMix, ReportBuilder.allocateSigned(note.refundedAmount, weights: noteMix.map(\.1))).map { ($0.0.0, $0.1) }
                    }
                    replacement = allocated(net, over: weights, date: entry.date, entryID: entry.id)
                }
                result += replacement ?? [original]
            }
        }
        return result
    }

    // MARK: Reportes con base

    public func incomeStatement(from: Date, to: Date, basis: AccountingBasis = .accrual) throws -> IncomeStatement {
        ReportBuilder.incomeStatement(accounts: try ledgerAccounts(), lines: try ledgerLines(basis: basis), from: from, to: to)
    }

    public func balanceSheet(asOf date: Date, basis: AccountingBasis = .accrual, calendar: Calendar = .current) throws -> BalanceSheet {
        ReportBuilder.balanceSheet(accounts: try ledgerAccounts(), lines: try ledgerLines(basis: basis), asOf: date,
                                   fiscalYearStart: try fiscalYearStart(containing: date, calendar: calendar))
    }

    public func trialBalance(asOf date: Date, basis: AccountingBasis = .accrual) throws -> TrialBalance {
        ReportBuilder.trialBalance(accounts: try ledgerAccounts(), lines: try ledgerLines(basis: basis), asOf: date)
    }

    /// Estado de flujo de efectivo (método indirecto) del periodo, a partir de las líneas en devengo.
    public func cashFlowStatement(from: Date, to: Date) throws -> CashFlowStatement {
        ReportBuilder.cashFlow(accounts: try ledgerAccounts(), lines: try ledgerLines(), from: from, to: to)
    }

    /// El libro diario del periodo para exportar, por fecha y número de asiento.
    public func journalExportRows(from: Date, to: Date) throws -> [JournalExportRow] {
        try postedEntries().filter { $0.date >= from && $0.date <= to }
            .sorted { ($0.date, $0.number) < ($1.date, $1.number) }
            .flatMap { entry in
                entry.sortedLines.map { line in
                    JournalExportRow(date: entry.date, entryNumber: entry.number, entryMemo: entry.memo, source: entry.source.rawValue,
                                     accountCode: line.account?.code ?? "", accountName: line.account?.name ?? "",
                                     debit: line.debit, credit: line.credit, lineMemo: line.memo)
                }
            }
    }
}

// MARK: - «Exportar para mi contador» (PLAN-FASE2 §5)

/// Todo lo que el contador necesita de un periodo, listo para exportar: los reportes calculados (para un PDF) y sus CSV.
/// La UI decide cómo entregarlo (carpeta, ZIP, compartir).
public struct AccountantPackage {
    public struct File: Sendable, Equatable {
        /// Nombre sugerido, con extensión («Diario.csv»).
        public var name: String
        public var contents: String
        public var data: Data { Data(contents.utf8) }
    }

    public var companyName: String
    public var from: Date
    public var to: Date
    public var basis: AccountingBasis
    public var incomeStatement: IncomeStatement
    public var balanceSheet: BalanceSheet
    public var trialBalance: TrialBalance
    public var cashFlow: CashFlowStatement
    /// Deducibles por línea del formulario de la empresa (`nil` si su tipo de empresa no tiene formulario en Chirogra).
    public var taxSummary: TaxFormSummary?
    public var files: [File]
}

extension Bookkeeper {

    /// Paquete para el contador: estado de resultados, balance general y balanza (en la base pedida), flujo de efectivo,
    /// deducibles por línea del formulario y los CSV de todo eso más el diario.
    public func accountantPackage(from: Date, to: Date, basis: AccountingBasis = .accrual, locale: Locale = .current,
                                  calendar: Calendar = .current) throws -> AccountantPackage {
        let accounts = try ledgerAccounts()
        let lines = try ledgerLines(basis: basis)
        let income = ReportBuilder.incomeStatement(accounts: accounts, lines: lines, from: from, to: to)
        let balance = ReportBuilder.balanceSheet(accounts: accounts, lines: lines, asOf: to,
                                                 fiscalYearStart: try fiscalYearStart(containing: to, calendar: calendar))
        let trial = ReportBuilder.trialBalance(accounts: accounts, lines: lines, asOf: to)
        let cashFlow = try cashFlowStatement(from: from, to: to)
        let year = calendar.component(.year, from: to)
        let taxes = try taxForm().map { try taxSummary(from: from, to: to, basis: basis, form: $0, year: year) }
        var files = [
            AccountantPackage.File(name: String(localized: "Estado de resultados") + ".csv", contents: CSVExport.incomeStatement(income, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Balance general") + ".csv", contents: CSVExport.balanceSheet(balance, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Balanza de comprobación") + ".csv", contents: CSVExport.trialBalance(trial, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Flujo de efectivo") + ".csv", contents: CSVExport.cashFlow(cashFlow, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Diario") + ".csv",
                                   contents: CSVExport.journal(try journalExportRows(from: from, to: to), calendar: calendar)),
        ]
        if let taxes {
            files.append(AccountantPackage.File(name: "\(taxes.form.title).csv", contents: CSVExport.taxSummary(taxes, locale: locale, calendar: calendar)))
        }
        return AccountantPackage(companyName: try company()?.name ?? "", from: from, to: to, basis: basis, incomeStatement: income,
                                 balanceSheet: balance, trialBalance: trial, cashFlow: cashFlow, taxSummary: taxes, files: files)
    }
}
