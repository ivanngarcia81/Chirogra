import ChirograCore
import ChirograData
import Foundation
import SwiftData

// MARK: - Registrar con una frase (1.4, docs/PLAN-1.4.md §2, grupo «Registrar»)
//
// Claude pide `preparar_gasto`, `preparar_factura`, `preparar_cobro` o `preparar_cita` con lo que entendió de la frase.
// La app busca en los libros el proveedor, la categoría, la cuenta, el cliente o la factura, y enseña una tarjeta con
// el borrador. **Nunca guarda sola:** guarda el usuario con «Guardar» (o lo corrige con «Editar», que abre el editor
// de siempre ya relleno). A Claude vuelve lo que se entendió y lo que falta, para que lo diga o pregunte.

/// Un borrador del asistente y en qué quedó.
struct AssistantDraft: Identifiable {
    enum Payload {
        case expense(ExpenseInput)
        case invoice(InvoiceDraftInput)
        case payment(PaymentDraft)
        case appointment(AppointmentDraft)
    }

    /// Un cobro listo para `Bookkeeper.recordPayment`.
    struct PaymentDraft {
        let invoice: Invoice?
        let amount: Int64
        let date: Date
        let depositAccount: Account?
        let method: PaymentMethod
    }

    enum State: Equatable {
        case pending
        case saving
        /// Guardado; con la factura, el borrador que se creó (para abrirlo).
        case saved(invoiceID: UUID?)
        case failed(String)
    }

    let id = UUID()
    let payload: Payload
    /// Lo que enseña la tarjeta, en orden: etiqueta y valor.
    let rows: [(label: String, value: String)]
    /// Lo que falta para poder guardar, con el nombre del campo tal como sale en el editor.
    let missing: [String]
    var state: State = .pending

    /// El tipo, para reconocer la misma tarjeta preparada otra vez.
    var kind: String {
        switch payload {
        case .expense: "gasto"
        case .invoice: "factura"
        case .payment: "cobro"
        case .appointment: "cita"
        }
    }

    var title: String {
        switch payload {
        case .expense: String(localized: "Gasto nuevo")
        case .invoice: String(localized: "Factura nueva (borrador)")
        case .payment: String(localized: "Cobro")
        case .appointment: String(localized: "Cita nueva")
        }
    }

    var systemImage: String {
        switch payload {
        case .expense: "wallet.bifold"
        case .invoice: "doc.text"
        case .payment: "dollarsign.circle"
        case .appointment: "calendar"
        }
    }

    var canSave: Bool { missing.isEmpty && (state == .pending || isRetryable) }

    /// Un cobro sin factura no tiene nada que enseñar ni que corregir: no sale tarjeta y Claude pregunta cuál.
    var isShown: Bool {
        if case .payment(let payment) = payload { payment.invoice != nil } else { true }
    }

    private var isRetryable: Bool { if case .failed = state { true } else { false } }

    /// Lo que se le dice a Claude en la vuelta siguiente cuando el usuario guarda.
    var savedNote: String {
        let summary = rows.map { "\($0.label): \($0.value)" }.joined(separator: "; ")
        return switch payload {
        case .invoice: "El usuario guardó el borrador de factura (\(summary)). Todavía no está emitida."
        default: "El usuario guardó \(title.lowercased()) (\(summary))."
        }
    }
}

@MainActor
enum AssistantDrafts {
    static let toolNames: Set<String> = ["preparar_gasto", "preparar_factura", "preparar_cobro", "preparar_cita"]

    /// El borrador que pidió Claude y lo que se le contesta (JSON). `nil` si la herramienta no es de registrar.
    static func prepare(_ name: String, input: JSONValue, context: ModelContext, now: Date = .now) -> (AssistantDraft, String)? {
        let books = Bookkeeper(context: context)
        let draft: AssistantDraft
        var extra: [String: Any] = [:]
        do {
            switch name {
            case "preparar_gasto": (draft, extra) = try expense(input, books: books, now: now)
            case "preparar_factura": (draft, extra) = try invoice(input, books: books, now: now)
            case "preparar_cobro": (draft, extra) = try payment(input, books: books, now: now)
            case "preparar_cita": (draft, extra) = try appointment(input, books: books, now: now)
            default: return nil
            }
        } catch {
            return nil
        }
        var result: [String: Any] = extra
        result["borrador"] = Dictionary(draft.rows.map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })
        result["faltan"] = draft.missing
        result["estado"] = !draft.isShown
            ? "Sin tarjeta: no se sabe qué factura es. Pregunta cuál (las opciones van en «facturas_posibles») y vuelve a preparar el cobro con su número."
            : draft.missing.isEmpty
            ? "Tarjeta en pantalla, SIN GUARDAR: el usuario la revisa y pulsa «Guardar» o «Editar»."
            : "Tarjeta en pantalla, SIN GUARDAR y sin poder guardarse todavía: falta lo de «faltan». Pregúntalo, o el usuario lo completa con «Editar»."
        let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
        return (draft, String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: Gasto

    private static func expense(_ input: JSONValue, books: Bookkeeper, now: Date) throws -> (AssistantDraft, [String: Any]) {
        let accounts = try books.fetch(Account.self).sorted { $0.code < $1.code }
        let vendors = try books.fetch(Vendor.self)
        let amount = cents(input["monto"])
        let date = day(input["fecha"]) ?? now
        let payeeText = text(input["proveedor"])
        let vendor = payeeText.isEmpty ? nil : ReceiptReader.matchVendor(payeeText, in: vendors)
        let payee = vendor?.name ?? payeeText
        let note = text(input["nota"])

        let groups = ExpenseCategories.groups(from: accounts)
        let categories = groups.costs + groups.assetPurchases
        let category = match(text(input["categoria"]), in: categories, name: \.name)
            ?? vendor?.defaultExpenseAccountID.flatMap { id in accounts.first { $0.id == id } }

        let payWith = paymentAccount(text(input["pagado_con"]), in: accounts.paymentAccounts)

        var missing: [String] = []
        if amount <= 0 { missing.append(String(localized: "el monto")) }
        if payee.isEmpty { missing.append(String(localized: "el proveedor (o «Pagado a»)")) }
        if category == nil { missing.append(String(localized: "la categoría")) }
        if payWith.account == nil { missing.append(String(localized: "el método de pago")) }

        let expenseInput = ExpenseInput(
            date: date, payee: payee, vendor: vendor, paymentAccountID: payWith.account?.id, method: payWith.method,
            memo: note, lines: [.init(details: note.isEmpty ? payee : note, amount: max(0, amount), accountID: category?.id)])
        var rows: [(String, String)] = []
        rows.append((String(localized: "Monto"), amount > 0 ? amount.money : "—"))
        rows.append((String(localized: "Pagado a"), payee.isEmpty ? "—" : payee))
        rows.append((String(localized: "Categoría"), category?.name ?? "—"))
        rows.append((String(localized: "Pagado con"), payWith.account?.name ?? "—"))
        rows.append((String(localized: "Fecha"), date.shortDate))
        if !note.isEmpty { rows.append((String(localized: "Nota"), note)) }

        var extra: [String: Any] = ["proveedor_nuevo": vendor == nil && !payee.isEmpty]
        if category == nil { extra["categorias_posibles"] = categories.prefix(60).map(\.name) }
        if payWith.account == nil { extra["cuentas_posibles"] = accounts.paymentAccounts.map(\.name) }
        return (AssistantDraft(payload: .expense(expenseInput), rows: rows, missing: missing), extra)
    }

    /// La cuenta con que se pagó: por su nombre o por la palabra («tarjeta», «efectivo», «banco», «cheque»). Sin decirlo,
    /// la primera cuenta de banco, como el editor.
    private static func paymentAccount(_ said: String, in accounts: [Account]) -> (account: Account?, method: PaymentMethod) {
        let wanted = folded(said)
        let card = ["tarjeta de credito", "credito", "credit", "visa", "mastercard", "amex", "american express"]
        let cash = ["efectivo", "cash"]
        let check = ["cheque", "check"]
        let transfer = ["transferencia", "transfer", "zelle", "ach", "wire"]
        let bank = accounts.first { $0.subtype == .bank }
        if let named = match(said, in: accounts, name: \.name) {
            return (named, PaymentMethodPicker.choices(for: named.subtype).first { method in
                switch method {
                case .check: check.contains { wanted.contains($0) }
                case .bankTransfer: transfer.contains { wanted.contains($0) }
                default: false
                }
            } ?? PaymentMethodPicker.choices(for: named.subtype)[0])
        }
        if cash.contains(where: { wanted.contains($0) }), let account = accounts.first(where: { $0.subtype == .cash }) {
            return (account, .cash)
        }
        if card.contains(where: { wanted.contains($0) }) || wanted == "tarjeta" || wanted == "card",
           let account = accounts.first(where: { $0.subtype == .creditCard }) {
            return (account, .card)
        }
        if check.contains(where: { wanted.contains($0) }) { return (bank, .check) }
        if transfer.contains(where: { wanted.contains($0) }) { return (bank, .bankTransfer) }
        // «Débito», «banco», una tarjeta sin tarjeta de crédito en los libros, o nada: el banco, con tarjeta de débito.
        return (bank ?? accounts.first, bank == nil ? (accounts.first.map { PaymentMethodPicker.choices(for: $0.subtype)[0] } ?? .card) : .card)
    }

    // MARK: Factura

    private static func invoice(_ input: JSONValue, books: Bookkeeper, now: Date) throws -> (AssistantDraft, [String: Any]) {
        let customers = try books.fetch(Customer.self).filter { !$0.isArchived }.sorted { $0.name < $1.name }
        let accounts = try books.fetch(Account.self).sorted { $0.code < $1.code }
        let customer = match(text(input["cliente"]), in: customers, name: \.name)
        let date = day(input["fecha"]) ?? now
        let defaults = try books.newInvoiceDefaults(for: customer, issueDate: date)
        let income = accounts.filtered { $0.accountType == .income }.first

        var said: [JSONValue] = []
        if case .array(let items)? = input["lineas"] { said = items }
        let lines: [InvoiceDraftInput.Line] = said
            .compactMap { line in
                let details = text(line["descripcion"])
                let price = cents(line["precio"])
                guard !details.isEmpty || price > 0 else { return nil }
                let quantity = number(line["cantidad"]).map { Decimal($0) } ?? 1
                return .init(details: details, quantity: quantity > 0 ? quantity : 1, unitPrice: max(0, price), incomeAccountID: income?.id)
            }
        let message = text(input["mensaje"])
        let draftInput = InvoiceDraftInput(customer: customer, issueDate: date, dueDate: defaults.dueDate, taxGroupID: defaults.taxGroupID,
                                           customerMessage: message.isEmpty ? defaults.customerMessage : message, lines: lines,
                                           pricesIncludeTax: defaults.pricesIncludeTax)
        var missing: [String] = []
        if customer == nil { missing.append(String(localized: "el cliente")) }
        if lines.isEmpty || lines.allSatisfy({ $0.amount <= 0 }) { missing.append(String(localized: "una línea con precio")) }

        var rows: [(String, String)] = [(String(localized: "Cliente"), customer?.name ?? "—")]
        for line in lines {
            let quantity = line.quantity == 1 ? "" : "\(NSDecimalNumber(decimal: line.quantity).stringValue) × "
            rows.append((line.details.isEmpty ? String(localized: "Línea") : line.details,
                         "\(quantity)\(line.unitPrice.money)"))
        }
        let subtotal = lines.reduce(Int64(0)) { $0 + $1.amount }
        rows.append((String(localized: "Subtotal"), subtotal.money))
        rows.append((String(localized: "Fecha"), date.shortDate))
        rows.append((String(localized: "Vence"), defaults.dueDate.shortDate))

        var extra: [String: Any] = ["nota": "El impuesto sobre ventas se calcula al abrir el borrador. Guardar crea un borrador; no se emite ni se envía."]
        if customer == nil { extra["clientes_posibles"] = customers.prefix(60).map(\.name) }
        return (AssistantDraft(payload: .invoice(draftInput), rows: rows, missing: missing), extra)
    }

    // MARK: Cobro

    private static func payment(_ input: JSONValue, books: Bookkeeper, now: Date) throws -> (AssistantDraft, [String: Any]) {
        let open = try books.fetch(Invoice.self).filter { $0.isOpen && $0.balanceDue > 0 }.sorted { $0.dueDate < $1.dueDate }
        let accounts = try books.fetch(Account.self).sorted { $0.code < $1.code }
        let number = folded(text(input["factura"]))
        let customerText = text(input["cliente"])
        let amount = cents(input["monto"])

        var candidates = open
        if !number.isEmpty {
            candidates = open.filter { folded($0.number) == number || folded($0.number).hasSuffix(number) }
        } else if !customerText.isEmpty {
            let customers = open.compactMap(\.customer)
            if let customer = match(customerText, in: customers, name: \.name) {
                candidates = open.filter { $0.customer?.id == customer.id }
            } else {
                candidates = []
            }
        }
        // Varias del mismo cliente: la que tiene justo ese saldo.
        if candidates.count > 1, amount > 0, case let exact = candidates.filter({ $0.balanceDue == amount }), exact.count == 1 {
            candidates = exact
        }
        let invoice = candidates.count == 1 ? candidates[0] : nil
        let finalAmount = amount > 0 ? amount : (invoice?.balanceDue ?? 0)
        let date = day(input["fecha"]) ?? now
        let deposits = accounts.filtered { $0.isMoneyAccount && $0 != .creditCard }
        let methodText = folded(text(input["metodo"]))
        let says = { (words: [String]) in words.contains { methodText.contains($0) } }
        let method: PaymentMethod = if says(["efectivo", "cash"]) { .cash }
            else if says(["cheque", "check"]) { .check }
            else if says(["tarjeta", "card"]) { .card }
            else { .bankTransfer }
        let deposit = match(text(input["deposito"]), in: deposits, name: \.name)
            ?? (method == .cash ? deposits.first { $0.subtype == .cash } : nil)
            ?? deposits.first { $0.subtype == .bank } ?? deposits.first

        var missing: [String] = []
        if invoice == nil { missing.append(String(localized: "la factura")) }
        if let invoice, finalAmount > invoice.balanceDue {
            missing.append(String(localized: "un monto que no pase del saldo (\(invoice.balanceDue.money))"))
        }
        if finalAmount <= 0 { missing.append(String(localized: "el monto")) }
        if deposit == nil { missing.append(String(localized: "la cuenta donde entra el dinero")) }

        var rows: [(String, String)] = []
        rows.append((String(localized: "Factura"), invoice.map { "\($0.number) · \($0.customer?.name ?? "")" } ?? "—"))
        if let invoice { rows.append((String(localized: "Saldo"), invoice.balanceDue.money)) }
        rows.append((String(localized: "Cobrado"), finalAmount > 0 ? finalAmount.money : "—"))
        rows.append((String(localized: "Cómo"), method.title))
        rows.append((String(localized: "Entra en"), deposit?.name ?? "—"))
        rows.append((String(localized: "Fecha"), date.shortDate))

        var extra: [String: Any] = [:]
        if invoice == nil {
            extra["facturas_posibles"] = (candidates.isEmpty ? open : candidates).prefix(30).map {
                ["numero": $0.number, "cliente": $0.customer?.name ?? "", "saldo": $0.balanceDue.money] as [String: Any]
            }
        }
        return (AssistantDraft(payload: .payment(.init(invoice: invoice, amount: finalAmount, date: date, depositAccount: deposit, method: method)),
                               rows: rows, missing: missing), extra)
    }

    // MARK: Cita

    private static func appointment(_ input: JSONValue, books: Bookkeeper, now: Date) throws -> (AssistantDraft, [String: Any]) {
        let customers = try books.fetch(Customer.self).filter { !$0.isArchived }
        let customerText = text(input["cliente"])
        let customer = match(customerText, in: customers, name: \.name)
        let start = dateTime(input["inicio"])
        let minutes = number(input["minutos"]).map { Int($0) } ?? 60
        let title = text(input["titulo"])
        let draft = AppointmentDraft(title: title, customerID: customer?.id, start: start ?? now, durationMinutes: max(5, minutes),
                                     location: text(input["lugar"]), notes: text(input["notas"]))
        var missing: [String] = []
        if start == nil { missing.append(String(localized: "el día y la hora")) }
        if title.isEmpty && customer == nil { missing.append(String(localized: "un cliente o un título")) }

        var rows: [(String, String)] = []
        if let customer { rows.append((String(localized: "Cliente"), customer.name)) }
        if !title.isEmpty { rows.append((String(localized: "Título"), title)) }
        rows.append((String(localized: "Cuándo"), start.map { $0.formatted(.appDateTime.weekday(.wide).day().month(.wide).hour().minute()) } ?? "—"))
        rows.append((String(localized: "Duración"), String(localized: "\(draft.durationMinutes) min")))
        if !draft.location.isEmpty { rows.append((String(localized: "Lugar"), draft.location)) }

        var extra: [String: Any] = [:]
        if !customerText.isEmpty && customer == nil {
            extra["cliente_no_encontrado"] = customerText
            extra["clientes_posibles"] = customers.sorted { $0.name < $1.name }.prefix(60).map(\.name)
        }
        return (AssistantDraft(payload: .appointment(draft), rows: rows, missing: missing), extra)
    }

    // MARK: Guardar

    /// Guarda el borrador tal cual se enseñó. Devuelve el estado nuevo de la tarjeta.
    static func save(_ draft: AssistantDraft, context: ModelContext) -> AssistantDraft.State {
        let books = Bookkeeper(context: context)
        do {
            switch draft.payload {
            case .expense(let input):
                _ = try books.createExpense(input, post: true)
                return .saved(invoiceID: nil)
            case .invoice(let input):
                return .saved(invoiceID: try books.saveDraft(input, into: nil).id)
            case .payment(let p):
                guard let invoice = p.invoice, let account = p.depositAccount else { return .failed(String(localized: "Falta la factura o la cuenta donde entra el dinero.")) }
                try books.recordPayment(for: invoice, amount: p.amount, date: p.date, depositAccount: account, method: p.method)
                return .saved(invoiceID: nil)
            case .appointment(let input):
                try books.createAppointment(input)
                return .saved(invoiceID: nil)
            }
        } catch let error as BookkeepingError where PeriodClosing.lockDate(of: error) != nil {
            return .failed(String(localized: "La fecha cae en un periodo cerrado. Pulsa «Editar» para cambiarla."))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Leer lo que manda Claude

    private static func text(_ value: JSONValue?) -> String {
        value?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let n)?: n
        case .string(let s)?: Double(s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        default: nil
        }
    }

    /// Dólares (89.5) a centavos.
    static func cents(_ value: JSONValue?) -> Int64 {
        guard let n = number(value), n.isFinite, abs(n) < 1e11 else { return 0 }
        return Int64((n * 100).rounded())
    }

    /// AAAA-MM-DD en el calendario del aparato.
    static func day(_ value: JSONValue?) -> Date? {
        guard let parts = value?.string?.prefix(10).split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
            .map { Calendar.current.startOfDay(for: $0) }
    }

    /// «AAAA-MM-DD HH:mm» en la hora del aparato.
    static func dateTime(_ value: JSONValue?) -> Date? {
        guard let text = value?.string?.replacingOccurrences(of: "T", with: " ") else { return nil }
        let pieces = text.split(separator: " ")
        guard let date = day(.string(String(pieces.first ?? ""))) else { return nil }
        guard pieces.count > 1 else { return nil }
        let time = pieces[1].split(separator: ":").compactMap { Int($0) }
        guard time.count >= 2, (0..<24).contains(time[0]), (0..<60).contains(time[1]) else { return nil }
        return Calendar.current.date(bySettingHour: time[0], minute: time[1], second: 0, of: date)
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Por nombre: igual, luego empieza igual, luego lo contiene (en los dos sentidos, desde 3 letras).
    static func match<T>(_ said: String, in items: [T], name: (T) -> String) -> T? {
        let wanted = folded(said)
        guard wanted.count >= 2 else { return nil }
        if let exact = items.first(where: { folded(name($0)) == wanted }) { return exact }
        if let prefix = items.first(where: { folded(name($0)).hasPrefix(wanted) }) { return prefix }
        guard wanted.count >= 3 else { return nil }
        let containing = items.filter { folded(name($0)).contains(wanted) || (folded(name($0)).count >= 3 && wanted.contains(folded(name($0)))) }
        return containing.count == 1 ? containing[0] : nil
    }
}
