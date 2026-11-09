import ChirograCore
import ChirograData
import Foundation
import SwiftUI

// Lógica de pantalla de la bandeja «Por revisar» (DISEÑO §4.6, docs/DATOS-V4.md §3): qué se propone para cada
// movimiento, cómo se acepta, qué cuentas se ofrecen al categorizar, el texto de la regla que se crea desde un
// movimiento y los mensajes de los errores de importación. Las pantallas (iPhone, iPad, Mac) usan esto y solo llaman a
// `Bookkeeper`; nada aquí escribe en el modelo por su cuenta.

// MARK: - Sugerencia

/// Lo que la app propone para un movimiento por revisar, en este orden: una línea del diario que ya lo registra
/// (emparejar, para no duplicar), una factura o una factura de proveedor abierta por el mismo importe, o la categoría
/// que puso una regla.
enum BankSuggestion {
    case match(BankMatchCandidate)
    case invoice(Invoice)
    case bill(Bill)
    case category(Account, fromRule: Bool)
    case none

    enum Kind { case match, rule, none }

    /// Color del punto y del texto (canvas `Banca`: verde = coincide, azul = regla, naranja = sin categoría).
    var kind: Kind {
        switch self {
        case .match, .invoice, .bill: .match
        case .category: .rule
        case .none: .none
        }
    }

    var isActionable: Bool { kind != .none }

    /// «Coincide con F-1042», «Transporte · regla», «Sin categoría».
    var title: String {
        switch self {
        case .match(let candidate): String(localized: "Coincide con \(candidate.entry.bankTitle)")
        case .invoice(let invoice): String(localized: "Cobro de \(invoice.number)")
        case .bill(let bill): String(localized: "Pago de \(bill.bankTitle)")
        case .category(let account, let fromRule): fromRule ? String(localized: "\(account.name) · regla") : account.name
        case .none: String(localized: "Sin categoría")
        }
    }

    /// Por qué se propone (canvas `iPadBanca`, «Sugerencia»).
    var reason: String {
        switch self {
        case .match(let candidate):
            candidate.daysApart == 0 ? String(localized: "Mismo importe y mismo día, ya registrado en tus libros")
                : String(localized: "Mismo importe, registrado con \(candidate.daysApart) días de diferencia")
        case .invoice(let invoice):
            String(localized: "Factura abierta de \(invoice.customer?.name ?? "") por el mismo importe")
        case .bill(let bill):
            String(localized: "Factura de \(bill.vendor?.name ?? "") por pagar por el mismo importe")
        case .category(_, let fromRule):
            fromRule ? String(localized: "Una regla del banco coincide con la descripción") : String(localized: "Categoría elegida")
        case .none:
            String(localized: "Elige una categoría o empareja con algo que ya registraste")
        }
    }

    /// Texto del botón de aceptar.
    var acceptTitle: String {
        switch self {
        case .match: String(localized: "Emparejar")
        case .invoice: String(localized: "Registrar cobro")
        case .bill: String(localized: "Registrar pago")
        case .category: String(localized: "Categorizar")
        case .none: String(localized: "Revisar")
        }
    }

    var dotColor: Color {
        switch kind {
        case .match: Palette.green
        case .rule: Palette.blue
        case .none: Palette.orange
        }
    }

    var textColor: Color {
        switch kind {
        case .match: Palette.positive
        case .rule: Palette.info
        case .none: Palette.warning
        }
    }

    var systemImage: String {
        switch kind {
        case .match: "link"
        case .rule: "sparkles"
        case .none: "questionmark"
        }
    }
}

/// Datos que la bandeja necesita una sola vez por dibujo (cuentas, facturas abiertas) para proponer sin buscar fila a fila.
struct BankInboxContext {
    let books: Bookkeeper
    let accounts: [UUID: Account]
    let openInvoices: [Invoice]
    let openBills: [Bill]

    init(books: Bookkeeper, accounts: [Account], invoices: [Invoice], bills: [Bill]) {
        self.books = books
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        openInvoices = invoices.filter { $0.isOpen && $0.balanceDue > 0 }
        openBills = bills.filter { $0.isOpen && $0.balanceDue > 0 }
    }

    func suggestion(for transaction: BankTransaction) -> BankSuggestion {
        guard transaction.isPending else { return .none }
        if let candidate = (try? books.matchCandidates(for: transaction))?.first { return .match(candidate) }
        let text = BankStatementLine.normalized(transaction.details + " " + transaction.payee)
        if transaction.amount > 0 {
            let same = openInvoices.filter { $0.balanceDue == transaction.amount }
            if let invoice = Self.best(same, name: { $0.customer?.name ?? "" }, in: text) { return .invoice(invoice) }
        } else if transaction.amount < 0 {
            let same = openBills.filter { $0.balanceDue == -transaction.amount }
            if let bill = Self.best(same, name: { $0.vendor?.name ?? "" }, in: text) { return .bill(bill) }
        }
        if let id = transaction.categoryAccountID, let account = accounts[id] {
            return .category(account, fromRule: transaction.ruleID != nil)
        }
        return .none
    }

    /// Una sola con ese importe, o la que tiene el nombre del cliente o proveedor en la descripción.
    private static func best<T>(_ items: [T], name: (T) -> String, in text: String) -> T? {
        if items.count == 1 { return items[0] }
        return items.first { item in
            let words = BankStatementLine.normalized(name(item)).split(separator: " ").filter { $0.count > 2 }
            return !words.isEmpty && words.allSatisfy { text.contains($0) }
        }
    }
}

enum BankReview {
    /// Acepta la propuesta: empareja, registra el cobro o el pago, o categoriza con la cuenta de la regla.
    static func accept(_ suggestion: BankSuggestion, for transaction: BankTransaction, books: Bookkeeper) throws {
        switch suggestion {
        case .match(let candidate): try books.match(transaction, to: candidate.line)
        case .invoice(let invoice): try books.recordPayment(from: transaction, for: invoice)
        case .bill(let bill): try books.payBill(from: transaction, bill: bill)
        case .category(let account, _): try books.categorize(transaction, as: account)
        case .none: break
        }
    }

    /// «Aceptar sugeridas» (canvas `Banca`): todas las que tienen propuesta. Devuelve cuántas se registraron y el
    /// primer error (las demás siguen).
    static func acceptAll(_ transactions: [BankTransaction], context: BankInboxContext) -> (accepted: Int, error: Error?) {
        var accepted = 0
        var firstError: Error?
        for transaction in transactions where transaction.isPending {
            let suggestion = context.suggestion(for: transaction)
            guard suggestion.isActionable else { continue }
            do {
                try accept(suggestion, for: transaction, books: context.books)
                accepted += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return (accepted, firstError)
    }

    /// El proveedor que se llama así (sin mayúsculas ni acentos), para pasarlo a `categorize`.
    static func vendor(named name: String, in vendors: [Vendor]) -> Vendor? {
        let wanted = BankStatementLine.normalized(name)
        guard !wanted.isEmpty else { return nil }
        return vendors.first { !$0.isArchived && BankStatementLine.normalized($0.name) == wanted }
    }

    /// Movimiento siguiente por revisar tras `current` (o el primero), para «… y siguiente».
    static func next(after current: BankTransaction?, in pending: [BankTransaction]) -> BankTransaction? {
        let open = pending.filter(\.isPending)
        guard let current, let index = pending.firstIndex(where: { $0.id == current.id }) else { return open.first }
        return pending[(index + 1)...].first(where: \.isPending) ?? open.first { $0.id != current.id }
    }
}

// MARK: - Cuentas para categorizar

/// Cuentas que se ofrecen al categorizar un movimiento, en grupos: para una salida, gastos, compras de equipo o
/// inventario, transferencias a otra cuenta de dinero y pagos de préstamos o retiros del dueño; para una entrada,
/// ingresos, transferencias, aportaciones o préstamos y devoluciones de gastos. Nunca la propia cuenta del movimiento
/// ni las por cobrar, por pagar o el sales tax (eso se registra con su documento).
enum BankCategoryOptions {
    struct Group: Identifiable {
        let title: String
        let accounts: [Account]
        var id: String { title }
    }

    static func groups(for amount: Int64, bankAccountID: UUID?, accounts: [Account]) -> [Group] {
        let postable = accounts.filter { $0.isPostable && $0.id != bankAccountID }
        let money = postable.filter { $0.subtype.isMoneyAccount && $0.subtype != .undepositedFunds }
        let financing = postable.filter {
            [.otherCurrentLiability, .longTermLiability, .ownersEquity, .ownersDraw].contains($0.subtype)
        }
        let categories = ExpenseCategories.groups(from: postable)
        let groups: [Group]
        if amount < 0 {
            groups = [
                Group(title: String(localized: "Gastos"), accounts: categories.costs),
                Group(title: String(localized: "Equipo e inventario"), accounts: categories.assetPurchases),
                Group(title: String(localized: "Transferencia a otra cuenta"), accounts: money),
                Group(title: String(localized: "Préstamos y retiros del dueño"), accounts: financing),
            ]
        } else {
            groups = [
                Group(title: String(localized: "Ingresos"), accounts: postable.filter { $0.type == .income && $0.subtype != .salesDiscount }),
                Group(title: String(localized: "Transferencia desde otra cuenta"), accounts: money),
                Group(title: String(localized: "Aportaciones y préstamos"), accounts: financing),
                Group(title: String(localized: "Devolución de un gasto"), accounts: categories.costs),
            ]
        }
        return groups.filter { !$0.accounts.isEmpty }
    }

    /// Las que salen a la vista sin abrir «Más categorías…» (canvas `BancaRevisar`: cuatro): la propuesta, las más
    /// usadas en movimientos ya categorizados del mismo signo y, si faltan, las primeras del primer grupo.
    static func quickPicks(for transaction: BankTransaction, groups: [Group], history: [BankTransaction], limit: Int = 4) -> [Account] {
        let allowed = Dictionary(groups.flatMap(\.accounts).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var picks: [Account] = []
        func add(_ id: UUID?) {
            guard let id, let account = allowed[id], !picks.contains(where: { $0.id == id }), picks.count < limit else { return }
            picks.append(account)
        }
        add(transaction.categoryAccountID)
        let sameSign = history.filter { $0.status == .categorized && ($0.amount < 0) == (transaction.amount < 0) }
        let counts = Dictionary(grouping: sameSign.compactMap(\.categoryAccountID), by: { $0 }).mapValues(\.count)
        for id in counts.sorted(by: { ($1.value, $0.key.uuidString) < ($0.value, $1.key.uuidString) }).map(\.key) { add(id) }
        for account in groups.first?.accounts ?? [] { add(account.id) }
        return picks
    }
}

// MARK: - Regla desde un movimiento

enum BankRuleDraft {
    /// Palabras que los bancos ponen delante y no dicen quién es («POS», «DEBIT», «PURCHASE», «DEPOSITO»…).
    private static let noise: Set<String> = [
        "pos", "debit", "credit", "card", "purchase", "checkcard", "visa", "mastercard", "ach", "dda", "withdrawal",
        "deposit", "deposito", "pago", "compra", "cargo", "abono", "transferencia", "transfer", "online", "recurring",
        "payment", "web", "id", "ppd", "ccd", "des", "the",
    ]

    /// Texto que buscará la regla, sacado de la descripción del banco: sin números, referencias ni palabras de relleno,
    /// las tres primeras palabras que quedan, en mayúsculas («POS 8812 FERRET LA LLAVE» → «FERRET LA LLAVE»,
    /// «UBER *TRIP HELP.UBER.COM» → «UBER»). El usuario puede cambiarlo antes de guardar.
    static func matchText(from details: String) -> String {
        let words = details.split(whereSeparator: \.isWhitespace).compactMap { raw -> String? in
            let token = String(raw)
            if token.hasPrefix("*") || token.hasPrefix("#") || token.contains(".") || token.contains("/") { return nil }
            if token.contains(where: \.isNumber) { return nil }
            let cleaned = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard cleaned.count > 1 else { return nil }
            return cleaned
        }
        let meaningful = words.drop { noise.contains(BankStatementLine.normalized($0)) }
        let picked = (meaningful.isEmpty ? words[...] : meaningful).prefix(3)
        let text = picked.joined(separator: " ").uppercased()
        return text.isEmpty ? details.trimmingCharacters(in: .whitespaces).uppercased() : text
    }

    /// Lo que guarda la regla: el signo del movimiento, para todas las cuentas del banco y sin registrar sola (propone).
    static func input(for transaction: BankTransaction, matchText: String, target: Account, vendor: Vendor?, payee: String) -> BankRuleInput {
        BankRuleInput(name: matchText, matchText: matchText, amountSign: transaction.amount < 0 ? .outflow : .inflow,
                      targetAccountID: target.id, vendorID: vendor?.id,
                      payee: payee == transaction.details ? "" : payee, autoApply: false, priority: 0)
    }
}

// MARK: - Textos

extension JournalEntry {
    /// «F-1042», «Renta del taller»…: el asiento como lo reconoce el usuario.
    var bankTitle: String {
        if !memo.isEmpty { return memo }
        return String(localized: "\(source.title) · asiento \(number)")
    }
}

extension Bill {
    var bankTitle: String {
        let name = vendor?.name ?? String(localized: "proveedor")
        return vendorNumber.isEmpty ? name : "\(name) \(vendorNumber)"
    }
}

extension BankTransaction {
    /// Descripción para la lista: la del banco o, si una regla o el usuario puso un beneficiario, ese.
    var shownTitle: String { details.isEmpty ? payee : details }

    /// «+$2,250.00» / «−$18.40».
    var signedAmount: String {
        amount > 0 ? "+\(amount.money)" : "−\((-amount).money)"
    }

    var amountColor: Color { amount > 0 ? Palette.positive : Palette.ink }

    var statusTitle: String {
        switch status {
        case .toReview: String(localized: "Por revisar")
        case .categorized: String(localized: "Registrado")
        case .matched: String(localized: "Emparejado")
        case .ignored: String(localized: "Excluido")
        }
    }

    var statusDot: Color {
        switch status {
        case .toReview: Palette.orange
        case .categorized, .matched: Palette.green
        case .ignored: Palette.gray
        }
    }
}

enum BankImportText {
    /// Texto claro para los errores de la importación (`BankStatementError` no trae texto: lo pone la pantalla).
    static func message(for error: Error) -> String {
        guard let error = error as? BankStatementError else { return error.localizedDescription }
        switch error {
        case .empty:
            return String(localized: "El archivo no tiene movimientos que podamos leer. Revisa que sea el extracto que bajaste del banco.")
        case .unreadableRow(let row):
            return String(localized: "No pudimos leer la fila \(row): revisa el formato de fecha y la columna del importe.")
        case .missingColumn(let column):
            return String(localized: "Falta elegir la columna «\(columnTitle(column))».")
        case .notOFX:
            return String(localized: "Este archivo no es un OFX ni un QFX. Si lo bajaste como CSV, elige el archivo .csv.")
        }
    }

    static func columnTitle(_ key: String) -> String {
        switch key {
        case "date": String(localized: "Fecha")
        case "details": String(localized: "Descripción")
        case "amount": String(localized: "Importe")
        default: key
        }
    }
}
