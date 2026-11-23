import ChirograCore
import Foundation

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
    /// estado de resultados de `ReportBuilder` sirven igual). El ingreso se reconoce cuando entra el dinero y el gasto
    /// cuando sale; las cuentas por cobrar y por pagar quedan en cero:
    /// - los asientos de facturas, notas de crédito y facturas de proveedor (y sus reversiones y correcciones) no cuentan;
    /// - cada **cobro** sustituye su línea de cuentas por cobrar por la parte de la factura que liquida (ingresos, sales
    ///   tax, descuento), y cada **pago a proveedor**, la de cuentas por pagar por la parte de la factura del proveedor;
    /// - una **nota de crédito aplicada a su propia factura** la rebaja: lo que falta por cobrar reconoce la factura ya
    ///   rebajada (ese día no se reconoce nada: no se movió dinero);
    /// - el **saldo a favor aplicado a otra factura** (`CreditApplication`, sin asiento) reconoce en su fecha la parte de
    ///   la nota que se consume (resta ingreso e impuesto de la factura original) y la parte de la otra factura que
    ///   liquida: ese dinero ya había entrado, así que el neto del día es cero y solo cambia de cuenta si no coinciden;
    /// - un **reembolso** de saldo a favor sustituye su línea de cuentas por cobrar por la parte de las notas que
    ///   reembolsa (de la más antigua a la más reciente, como `refundCustomerCredit`);
    /// - la **reversión** de un cobro, pago o reembolso (`voidPayment`) quita exactamente lo que reconoció, en su fecha;
    /// - lo demás (gastos pagados al momento, depósitos, transferencias, asientos manuales, saldos iniciales) queda igual.
    ///
    /// Cada documento lleva la cuenta de lo que le falta por reconocer y los hechos se recorren por fecha: cada parte es
    /// proporcional a lo que falta, exacta al centavo, y la que liquida el documento se lleva el resto exacto. Así nada
    /// de lo que pasa después cambia un periodo ya pasado y, liquidado todo, cada cuenta suma lo mismo que en devengo
    /// (`CashBasisCreditTests`). Si los datos no cuadran (p. ej. una sincronización a medias), el asiento se queda como
    /// está, con su cuenta por cobrar o por pagar a la vista, en vez de inventar un reparto.
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
        func billAccounts(_ bill: Bill) -> Set<UUID> { payable.union([bill.payableAccountID].compactMap { $0 }) }

        // Lo que le falta por reconocer a cada factura, nota de crédito y factura de proveedor (por su id).
        var pending: [UUID: CashBasisPending] = [:]
        func take(_ id: UUID, _ seed: @autoclosure () -> [(UUID, Int64)], _ target: Int64) -> [(UUID, Int64)]? {
            var state = pending[id] ?? CashBasisPending(seed())
            defer { pending[id] = state }
            return state.take(target)
        }
        func give(_ id: UUID, _ seed: @autoclosure () -> [(UUID, Int64)], _ parts: [(UUID, Int64)]) {
            var state = pending[id] ?? CashBasisPending(seed())
            state.add(parts)
            pending[id] = state
        }
        func invoiceSeed(_ invoice: Invoice) -> [(UUID, Int64)] { mix(invoice.journalEntryID, excluding: receivable) }
        func noteSeed(_ note: CreditNote) -> [(UUID, Int64)] { mix(note.journalEntryID, excluding: receivable) }
        func billSeed(_ bill: Bill) -> [(UUID, Int64)] { mix(bill.journalEntryID, excluding: billAccounts(bill)) }
        func lines(_ parts: [(UUID, Int64)], date: Date, entryID: UUID) -> [LedgerLine] {
            parts.compactMap { account, net in
                net == 0 ? nil : LedgerLine(accountID: account, date: date, debit: max(net, 0), credit: max(-net, 0), entryID: entryID)
            }
        }

        /// Lo que reconoció cada asiento sustituido: las cuentas que sustituyó y lo tomado de cada documento, para que
        /// su reversión lo quite exacto.
        var recognized: [UUID: (accounts: Set<UUID>, taken: [(document: UUID, seed: [(UUID, Int64)], parts: [(UUID, Int64)])])] = [:]
        var replacements: [UUID: (accounts: Set<UUID>, lines: [LedgerLine])] = [:]
        var synthetic: [LedgerLine] = []

        /// Sustituye las líneas de `replaced` del asiento por lo tomado, si suma lo mismo; si no, lo devuelve.
        func settle(_ entry: JournalEntry, replacing replaced: Set<UUID>,
                    taken: [(document: UUID, seed: [(UUID, Int64)], parts: [(UUID, Int64)])], complete: Bool) {
            let net = (entry.lines ?? []).reduce(Int64(0)) { sum, line in
                guard let id = line.account?.id, replaced.contains(id) else { return sum }
                return sum + line.debit - line.credit
            }
            let parts = taken.flatMap(\.parts)
            guard complete, net != 0, parts.reduce(0, { $0 + $1.1 }) == net else {
                // `take` ya lo restó de lo pendiente: devolverlo es sumarlo tal cual (revisión del 23-nov).
                for item in taken { give(item.document, item.seed, item.parts) }
                return
            }
            recognized[entry.id] = (replaced, taken)
            replacements[entry.id] = (replaced, lines(parts, date: entry.date, entryID: entry.id))
        }

        // Qué notas consumió cada reembolso (no se guarda): en el orden en que se registraron, con las notas que ya
        // existían entonces (`Bookkeeper.refundAllocations`). Hasta lo reembolsado de cada nota.
        let refundShares = Self.refundAllocations(refunds: entries.filter { $0.source == .customerRefund && $0.reversesEntryID == nil },
                                                  notes: notes, receivable: receivable) { $0.refundedAmount }

        // Los hechos que dependen del orden, por fecha: cobros, pagos, reembolsos, sus reversiones y saldo a favor aplicado.
        enum Event { case entry(JournalEntry), credit(CreditApplication) }
        func isRefund(_ entry: JournalEntry) -> Bool {
            entry.source == .customerRefund || entry.reversesEntryID.flatMap { entriesByID[$0] }?.source == .customerRefund
        }
        var events: [(date: Date, created: Date, number: Int, id: String, event: Event)] = entries.compactMap { entry in
            guard let source = entry.sourceDocumentID, !accrualDocuments.contains(source),
                  payments[source] != nil || billPayments[source] != nil || isRefund(entry) else { return nil }
            return (entry.date, entry.createdAt, entry.number, entry.id.uuidString, .entry(entry))
        }
        for application in try fetch(CreditApplication.self) {
            // La de una nota sobre su propia factura nace con la nota: va justo detrás de su asiento.
            let own = application.note.flatMap { note in note.invoice?.id == application.invoice?.id ? note : nil }
            events.append((application.date, own?.createdAt ?? application.date,
                           own?.journalEntryID.flatMap { entriesByID[$0]?.number } ?? Int.max,
                           application.id.uuidString, .credit(application)))
        }
        events.sort { ($0.date, $0.created, $0.number, $0.id) < ($1.date, $1.created, $1.number, $1.id) }

        for item in events {
            switch item.event {
            case .entry(let entry):
                if let originalID = entry.reversesEntryID {
                    // Reversión (cobro anulado): quita lo que reconoció el original y se lo devuelve a cada documento.
                    guard let original = recognized[originalID] else { continue }
                    for taken in original.taken { give(taken.document, taken.seed, taken.parts) }
                    let parts = original.taken.flatMap(\.parts).map { ($0.0, -$0.1) }
                    replacements[entry.id] = (original.accounts, lines(parts, date: entry.date, entryID: entry.id))
                } else if let payment = entry.sourceDocumentID.flatMap({ payments[$0] }) {
                    var taken: [(document: UUID, seed: [(UUID, Int64)], parts: [(UUID, Int64)])] = []
                    var complete = true
                    for application in (payment.applications ?? []).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                        guard let invoice = application.invoice,
                              let parts = take(invoice.id, invoiceSeed(invoice), -application.amount) else { complete = false; break }
                        taken.append((invoice.id, invoiceSeed(invoice), parts))
                    }
                    settle(entry, replacing: receivable, taken: taken, complete: complete)
                } else if let payment = entry.sourceDocumentID.flatMap({ billPayments[$0] }) {
                    guard let bill = payment.bill else { continue }
                    let parts = take(bill.id, billSeed(bill), payment.amount)
                    settle(entry, replacing: billAccounts(bill), taken: parts.map { [(bill.id, billSeed(bill), $0)] } ?? [],
                           complete: parts != nil)
                } else if entry.sourceDocumentID != nil {
                    // Reembolso: consume el saldo reembolsado de las notas del cliente, de la más antigua a la más reciente.
                    let amount = (entry.lines ?? []).reduce(Int64(0)) { sum, line in
                        guard let id = line.account?.id, receivable.contains(id) else { return sum }
                        return sum + line.debit - line.credit
                    }
                    var left = amount
                    var taken: [(document: UUID, seed: [(UUID, Int64)], parts: [(UUID, Int64)])] = []
                    var complete = true
                    for share in refundShares[entry.id] ?? [] {
                        guard let parts = take(share.note.id, noteSeed(share.note), share.amount) else { complete = false; break }
                        taken.append((share.note.id, noteSeed(share.note), parts))
                        left -= share.amount
                    }
                    settle(entry, replacing: receivable, taken: taken, complete: complete && left == 0)
                }
            case .credit(let application):
                guard let note = application.note, let invoice = application.invoice, application.amount > 0,
                      let noteParts = take(note.id, noteSeed(note), application.amount) else { continue }
                if note.invoice?.id == invoice.id {
                    // Sobre su propia factura: la rebaja. Si con eso queda liquidada y las cuentas no coinciden (se había
                    // cobrado una parte antes), lo que queda suma cero y se reconoce ese día.
                    give(invoice.id, invoiceSeed(invoice), noteParts)
                    if var state = pending[invoice.id], state.total == 0 {
                        synthetic += lines(state.drain(), date: application.date, entryID: application.id)
                        pending[invoice.id] = state
                    }
                } else if let invoiceParts = take(invoice.id, invoiceSeed(invoice), -application.amount) {
                    synthetic += lines(noteParts + invoiceParts, date: application.date, entryID: application.id)
                } else {
                    give(note.id, noteSeed(note), noteParts)
                }
            }
        }

        var result: [LedgerLine] = []
        for entry in entries {
            if let source = entry.sourceDocumentID, accrualDocuments.contains(source) { continue }
            let replacement = replacements[entry.id]
            for line in entry.lines ?? [] {
                guard let accountID = line.account?.id else { continue }
                if let replacement, replacement.accounts.contains(accountID) { continue }
                result.append(LedgerLine(accountID: accountID, date: entry.date, debit: line.debit, credit: line.credit, entryID: entry.id))
            }
            result += replacement?.lines ?? []
        }
        return result + synthetic
    }

    /// Qué notas de crédito consumió cada reembolso de saldo a favor (`refundCustomerCredit` solo guarda lo reembolsado
    /// de cada nota): los reembolsos en el orden en que se registraron (`createdAt`, número) y, a cada uno, las notas de
    /// su cliente que ya existían entonces, de la más antigua a la más reciente, hasta `capacity` de cada nota. Una nota
    /// con fecha anterior emitida después no cambia lo que consumió un reembolso anterior (revisión del 23-nov).
    static func refundAllocations(refunds: [JournalEntry], notes: [CreditNote], receivable: Set<UUID>,
                                  capacity: (CreditNote) -> Int64) -> [UUID: [(note: CreditNote, amount: Int64)]] {
        let ordered = notes.sorted { ($0.date, $0.createdAt, $0.id.uuidString) < ($1.date, $1.createdAt, $1.id.uuidString) }
        var left = Dictionary(ordered.map { ($0.id, max(0, capacity($0))) }, uniquingKeysWith: { first, _ in first })
        var result: [UUID: [(note: CreditNote, amount: Int64)]] = [:]
        for refund in refunds.sorted(by: { ($0.createdAt, $0.number, $0.id.uuidString) < ($1.createdAt, $1.number, $1.id.uuidString) }) {
            guard let customerID = refund.sourceDocumentID else { continue }
            var amount = (refund.lines ?? []).reduce(Int64(0)) { sum, line in
                guard let id = line.account?.id, receivable.contains(id) else { return sum }
                return sum + line.debit - line.credit
            }
            var shares: [(note: CreditNote, amount: Int64)] = []
            for note in ordered where amount > 0 && note.customer?.id == customerID && note.createdAt <= refund.createdAt {
                let portion = min(amount, left[note.id, default: 0])
                guard portion > 0 else { continue }
                shares.append((note, portion))
                left[note.id, default: 0] -= portion
                amount -= portion
            }
            result[refund.id] = shares
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
    /// Antigüedad de lo que deben los clientes y de lo que se debe a proveedores, al final del periodo (H19).
    public var receivables: AgingReport
    public var payables: AgingReport
    /// Conciliaciones bancarias al final del periodo (H19).
    public var reconciliations: ReconciliationReport
    public var files: [File]
}

extension Bookkeeper {

    /// Paquete para el contador: estado de resultados, balance general y balanza (en la base pedida), flujo de efectivo,
    /// deducibles por línea del formulario, antigüedad por cobrar y por pagar y conciliaciones bancarias (H19), y los
    /// CSV de todo eso más el diario.
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
        // Al final del periodo o, si aún no termina, hoy: a una fecha futura todo saldría vencido.
        let cut = min(to, Date())
        let receivables = try receivablesAging(asOf: cut, calendar: calendar)
        let payables = try payablesAging(asOf: cut, calendar: calendar)
        let reconciliations = try reconciliationReport(from: from, to: cut, calendar: calendar)
        var files = [
            AccountantPackage.File(name: String(localized: "Estado de resultados") + ".csv", contents: CSVExport.incomeStatement(income, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Balance general") + ".csv", contents: CSVExport.balanceSheet(balance, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Balanza de comprobación") + ".csv", contents: CSVExport.trialBalance(trial, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Flujo de efectivo") + ".csv", contents: CSVExport.cashFlow(cashFlow, calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Diario") + ".csv",
                                   contents: CSVExport.journal(try journalExportRows(from: from, to: to), calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Antigüedad por cobrar") + ".csv",
                                   contents: CSVExport.aging(receivables, title: String(localized: "Antigüedad de cuentas por cobrar"),
                                                             partyTitle: String(localized: "Cliente"), calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Antigüedad por pagar") + ".csv",
                                   contents: CSVExport.aging(payables, title: String(localized: "Antigüedad de cuentas por pagar"),
                                                             partyTitle: String(localized: "Proveedor"), calendar: calendar)),
            AccountantPackage.File(name: String(localized: "Conciliaciones") + ".csv",
                                   contents: CSVExport.reconciliations(reconciliations, calendar: calendar)),
        ]
        if let taxes {
            files.append(AccountantPackage.File(name: "\(taxes.form.title).csv", contents: CSVExport.taxSummary(taxes, locale: locale, calendar: calendar)))
        }
        // Lo registrado en un mes ya cerrado, con su motivo (QA Hudson, H02): solo si hubo algo en el periodo.
        let afterClose = try changesAfterClose(from: from, to: to, calendar: calendar)
        if !afterClose.isEmpty {
            files.append(AccountantPackage.File(name: String(localized: "Cambios después del cierre") + ".csv", contents: CSVExport.table(
                header: [String(localized: "Asiento"), String(localized: "Fecha"), String(localized: "Registrado el"), String(localized: "Concepto"),
                         String(localized: "Importe"), String(localized: "Cerrado hasta"), String(localized: "Motivo"),
                         String(localized: "Quién"), String(localized: "Aparato")],
                rows: afterClose.map { change in
                    [String(change.entryNumber), CSVExport.date(change.entryDate, calendar: calendar), CSVExport.date(change.recordedAt, calendar: calendar),
                     change.memo, CSVExport.amount(change.amount), CSVExport.date(change.lockDate, calendar: calendar),
                     change.reason, change.actor, change.device]
                })))
        }
        return AccountantPackage(companyName: try company()?.name ?? "", from: from, to: to, basis: basis, incomeStatement: income,
                                 balanceSheet: balance, trialBalance: trial, cashFlow: cashFlow, taxSummary: taxes,
                                 receivables: receivables, payables: payables, reconciliations: reconciliations, files: files)
    }
}

/// Lo que a un documento (factura, nota de crédito, factura de proveedor) le falta por reconocer en base caja: el neto
/// (debe − haber) por cuenta de su asiento, sin la cuenta por cobrar o por pagar, en el orden de sus líneas.
struct CashBasisPending {
    private(set) var parts: [(account: UUID, amount: Int64)] = []

    init(_ seed: [(UUID, Int64)]) { add(seed) }

    var total: Int64 { parts.reduce(0) { $0 + $1.amount } }

    mutating func add(_ more: [(UUID, Int64)]) {
        for (account, amount) in more {
            if let index = parts.firstIndex(where: { $0.account == account }) {
                parts[index].amount += amount
            } else {
                parts.append((account, amount))
            }
        }
    }

    /// La parte que liquida `target` (con el signo de `total`), proporcional a lo que falta y exacta al centavo; si
    /// liquida todo lo que falta, exactamente eso. `nil` si no hay nada que repartir o se pide más de lo que falta
    /// (datos que no cuadran): quien llama deja el asiento como está.
    mutating func take(_ target: Int64) -> [(UUID, Int64)]? {
        let sum = total
        guard sum != 0, target != 0, (target > 0) == (sum > 0), target.magnitude <= sum.magnitude else { return nil }
        let live = parts.filter { $0.amount != 0 }
        let share: [(UUID, Int64)] = target == sum
            ? live.map { ($0.account, $0.amount) }
            : zip(live, ReportBuilder.allocateSigned(target, weights: live.map(\.amount))).map { ($0.0.account, $0.1) }
        add(share.map { ($0.0, -$0.1) })
        return share.filter { $0.1 != 0 }
    }

    /// Lo que queda cuando ya no hay nada por liquidar (suma cero, distinto de cero solo si las cuentas no coinciden).
    mutating func drain() -> [(UUID, Int64)] {
        let rest = parts.filter { $0.amount != 0 }.map { ($0.account, $0.amount) }
        parts = parts.map { ($0.account, 0) }
        return rest
    }
}
