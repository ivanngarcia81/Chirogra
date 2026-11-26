import ChirograCore
import ChirograData
import Network
import SwiftData
import SwiftUI

// MARK: - Asistente (1.4, docs/PLAN-1.4.md §2; canvas «Chirogra 1.4», tableros `Asistente*`, `EntradaB`, `iPadAsistente`)
//
// Se abre con la burbuja flotante (decisión del usuario del 25-nov). Las sugerencias se contestan en el aparato, sin
// servidor ni costo. Las preguntas escritas van al servidor (`AssistantServer`), que se las pasa a Claude; cuando Claude
// pide una cifra, la calcula el aparato (`AssistantTools.run`) y vuelve solo el resultado.

/// Lo que contesta el asistente: texto o una tarjeta con cifras (canvas `AsistenteRespuesta`).
enum AssistantContent {
    case text(String)
    case profit(income: Int64, expenses: Int64, net: Int64, period: DateInterval)
    case receivables(total: Int64, rows: [AssistantReceivable], count: Int)
    case setAside(EstimatedTaxSummary)
    /// Un borrador para registrar (`AssistantDrafts`): su tarjeta con «Guardar» y «Editar». El estado vive en
    /// `AssistantState.drafts`, para que la tarjeta cambie al guardarlo.
    case draft(UUID)
    /// «Ir a…» una pantalla que pidió Claude al explicar cómo se hace algo (`abrir_pantalla`).
    case screen(SidebarItem)
}

struct AssistantReceivable: Identifiable {
    let id: UUID
    let customer: String
    let status: String
    let amount: Int64
    let isOverdue: Bool
}

struct AssistantMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let content: AssistantContent
}

/// Las sugerencias de la primera pantalla (canvas `Asistente`).
enum AssistantSuggestion: CaseIterable, Identifiable {
    case profit, receivables, expense, setAside
    var id: Self { self }

    var title: String {
        switch self {
        case .profit: String(localized: "¿Cuánto gané este mes?")
        case .receivables: String(localized: "¿Quién me debe?")
        case .expense: String(localized: "Anota un gasto")
        case .setAside: String(localized: "¿Cuánto aparto para impuestos?")
        }
    }

    var systemImage: String {
        switch self {
        case .profit: "chart.bar"
        case .receivables: "person.badge.plus"
        case .expense: "wallet.bifold"
        case .setAside: "percent"
        }
    }
}

/// Estado del asistente en la sesión: abierto o no, la conversación y el permiso (por aparato).
@MainActor @Observable
final class AssistantState {
    static let shared = AssistantState()
    static let consentKey = "assistant.consent"

    var isOpen = false
    private(set) var messages: [AssistantMessage] = []
    /// La conversación con el servidor, en el formato de la API (las sugerencias no entran: se contestan aquí).
    private var conversation: [JSONValue] = []
    /// Esperando al servidor.
    private(set) var isWorking = false
    /// Abre el editor de gasto (sugerencia «Anota un gasto»).
    var registeringExpense = false
    /// Los borradores de «registrar con una frase», por id de su tarjeta.
    private(set) var drafts: [UUID: AssistantDraft] = [:]
    /// El borrador que se corrige en su editor («Editar» en la tarjeta).
    var editingDraft: UUID?
    /// La factura (borrador) que se abre desde su tarjeta, ya guardada.
    var openingInvoice: Invoice?
    /// Lo que el usuario hizo con las tarjetas desde la última pregunta: se le dice a Claude con la siguiente.
    private var notes: [String] = []
    var consented = UserDefaults.standard.bool(forKey: AssistantState.consentKey) {
        didSet { UserDefaults.standard.set(consented, forKey: Self.consentKey) }
    }

    #if DEBUG
    static var askedQAQuestion = false
    #endif

    init() {
        #if DEBUG
        // `-qa.asistente 1`: abierto al arrancar (capturas del Mac, donde no hay toques). Con `-qa.asistentePregunta`,
        // también con el permiso dado (solo en esta sesión).
        isOpen = UserDefaults.standard.bool(forKey: "qa.asistente")
        if UserDefaults.standard.string(forKey: "qa.asistentePregunta") != nil { consented = true }
        #endif
    }

    func reset() {
        guard !isWorking else { return }
        messages = []
        conversation = []
        drafts = [:]
        notes = []
    }

    // MARK: Tarjetas de borrador

    /// «Guardar» en la tarjeta: lo guarda tal cual se enseñó.
    func save(draft id: UUID, context: ModelContext) {
        guard var draft = drafts[id], draft.canSave else { return }
        draft.state = AssistantDrafts.save(draft, context: context)
        drafts[id] = draft
        guard case .saved = draft.state else { return }
        notes.append(draft.savedNote)
        // Como en el editor de citas: la primera cita con aviso pide el permiso del sistema y se programan los avisos.
        if case .appointment(let appointment) = draft.payload, appointment.reminderMinutes >= 0, AppointmentReminders.isEnabled {
            Task { @MainActor in
                await AppointmentReminders.requestAuthorizationIfNeeded()
                await AppointmentReminders.reschedule(context: context)
            }
        }
    }

    /// Guardado desde su editor («Editar»): la tarjeta pasa a guardada (con lo que se haya cambiado allí).
    func markSaved(draft id: UUID) {
        guard var draft = drafts[id] else { return }
        draft.state = .saved(invoiceID: nil)
        drafts[id] = draft
        notes.append("El usuario corrigió en el editor y guardó: \(draft.title.lowercased()).")
    }

    func ask(_ suggestion: AssistantSuggestion, context: ModelContext, basis: AccountingBasis) {
        guard !isWorking else { return }
        if suggestion == .expense {
            registeringExpense = true
            return
        }
        messages.append(AssistantMessage(role: .user, content: .text(suggestion.title)))
        messages.append(AssistantMessage(role: .assistant, content: AssistantTools.answer(suggestion, context: context, basis: basis)))
    }

    /// Las vueltas como mucho por pregunta (cada herramienta que pide Claude es una vuelta más).
    static let maxRounds = 8

    /// Una pregunta escrita: va al servidor; las herramientas que pida Claude se ejecutan aquí con los libros.
    func ask(_ text: String, context: ModelContext, basis: AccountingBasis) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        messages.append(AssistantMessage(role: .user, content: .text(trimmed)))
        let before = conversation
        let pendingNotes = notes
        // Lo hecho con las tarjetas va delante de la pregunta, como nota de la app (no lo escribió el usuario).
        let content: JSONValue = pendingNotes.isEmpty ? .string(trimmed) : .array(
            pendingNotes.map { .object(["type": .string("text"), "text": .string("[Nota de la app] \($0)")]) }
            + [.object(["type": .string("text"), "text": .string(trimmed)])])
        notes = []
        conversation.append(.object(["role": .string("user"), "content": content]))
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await converse(context: context, basis: basis)
            } catch {
                // La conversación vuelve a como estaba: sin la pregunta que no se contestó.
                conversation = before
                notes = pendingNotes + notes
                messages.append(AssistantMessage(role: .assistant, content: .text(Self.explain(error))))
            }
        }
    }

    private func converse(context: ModelContext, basis: AccountingBasis) async throws {
        // Los botones «Ir a…» van debajo de la respuesta final, no entre las vueltas.
        var screens: [SidebarItem] = []
        defer {
            for item in screens { messages.append(AssistantMessage(role: .assistant, content: .screen(item))) }
        }
        let books = Bookkeeper(context: context)
        let company = (try? books.company())?.displayName ?? ""
        let purchase = await AssistantServer.purchaseProof()
        let app = purchase == nil ? await AssistantServer.appProof() : nil
        for _ in 0..<Self.maxRounds {
            let reply = try await AssistantServer.send(.init(
                idioma: AssistantServer.languageCode, hoy: AssistantTools.day(.now),
                aparato: AssistantServer.deviceName, empresa: company, base: basis.rawValue,
                compra: purchase, app: app, mensajes: conversation))
            let blocks = reply.contenido ?? []
            conversation.append(.object(["role": .string("assistant"), "content": .array(blocks)]))
            let text = blocks.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }
                .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { messages.append(AssistantMessage(role: .assistant, content: .text(text))) }

            let calls = blocks.filter { $0["type"]?.string == "tool_use" }
            guard reply.parada == "tool_use", !calls.isEmpty else {
                if reply.parada == "refusal" && text.isEmpty {
                    messages.append(AssistantMessage(role: .assistant, content: .text(String(localized: "No puedo ayudarte con esa pregunta. Prueba a preguntarlo de otra forma."))))
                }
                return
            }
            let results: [JSONValue] = calls.map { call in
                let name = call["name"]?.string ?? ""
                let output: String
                if let (draft, json) = AssistantDrafts.prepare(name, input: call["input"] ?? .null, context: context) {
                    drafts[draft.id] = draft
                    messages.append(AssistantMessage(role: .assistant, content: .draft(draft.id)))
                    output = json
                } else {
                    output = AssistantTools.run(name, input: call["input"] ?? .null, context: context, basis: basis)
                    if name == "abrir_pantalla", let item = AssistantScreens.item(call["input"]?["pantalla"]?.string ?? ""),
                       !screens.contains(item) {
                        screens.append(item)
                    }
                }
                return .object(["type": .string("tool_result"), "tool_use_id": call["id"] ?? .null, "content": .string(output)])
            }
            conversation.append(.object(["role": .string("user"), "content": .array(results)]))
        }
        // Demasiadas vueltas: se cierra la pregunta para que la conversación quede bien formada.
        throw AssistantServerError.server
    }

    static func explain(_ error: Error) -> String {
        switch error as? AssistantServerError {
        case .notConfigured?:
            String(localized: "Todavía no puedo contestar preguntas escritas: falta conectar el asistente con su servidor. Mientras tanto, prueba las sugerencias de abajo.")
        case .offline?:
            String(localized: "No hay conexión. El asistente necesita internet para contestar; las sugerencias de abajo funcionan sin ella.")
        case .noSubscription?:
            String(localized: "No pude comprobar tu suscripción con la App Store. Si acabas de suscribirte, espera un momento y prueba otra vez.")
        case .limit(let freeUse)?:
            freeUse ? String(localized: "Ya usaste las 20 preguntas de prueba. Con la suscripción tienes 100 preguntas al mes.")
                    : String(localized: "Llegaste a las 100 preguntas de este mes. Se renuevan el día 1. Las sugerencias de abajo siguen funcionando.")
        case .busy?:
            String(localized: "El asistente está muy ocupado ahora mismo. Prueba otra vez en un momento.")
        default:
            String(localized: "No pude contestar ahora. Prueba otra vez en un momento.")
        }
    }
}

/// Las cifras que pide el asistente, calculadas en el aparato con `Bookkeeper` (plan §2, «las herramientas se ejecutan
/// en el aparato»). Con el servidor serán las respuestas de `resumen_periodo`, `por_cobrar` y el apartado.
@MainActor
enum AssistantTools {
    static func answer(_ suggestion: AssistantSuggestion, context: ModelContext, basis: AccountingBasis, now: Date = .now) -> AssistantContent {
        let books = Bookkeeper(context: context)
        switch suggestion {
        case .profit:
            let month = DateInterval.month(containing: now, offset: 0)
            guard let statement = try? books.incomeStatement(from: month.start, to: now, basis: basis) else {
                return .text(String(localized: "No pude leer tus números."))
            }
            return .profit(income: statement.totalIncome, expenses: statement.totalExpenses + statement.totalCostOfGoodsSold,
                           net: statement.netIncome, period: DateInterval(start: month.start, end: now))
        case .receivables:
            let open = ((try? books.fetch(Invoice.self)) ?? []).filter { $0.isOpen && $0.balanceDue > 0 }
            guard !open.isEmpty else { return .text(String(localized: "Nadie te debe ahora mismo: no tienes facturas pendientes de cobro.")) }
            let sorted = open.sorted { ($0.daysOverdue() ?? -1, $1.dueDate) > ($1.daysOverdue() ?? -1, $0.dueDate) }
            let rows = sorted.prefix(4).map { invoice in
                AssistantReceivable(id: invoice.id, customer: invoice.customer?.name ?? invoice.number,
                                    status: invoice.daysOverdue().map { String(localized: "Vencida · \($0) días") }
                                        ?? String(localized: "Vence el \(invoice.dueDate.dayMonth)"),
                                    amount: invoice.balanceDue, isOverdue: invoice.daysOverdue() != nil)
            }
            return .receivables(total: open.reduce(0) { $0 + $1.balanceDue }, rows: Array(rows), count: open.count)
        case .setAside:
            guard let summary = try? books.estimatedTaxSummary(today: now, basis: basis) else {
                return .text(String(localized: "No pude calcular el apartado."))
            }
            return .setAside(summary)
        case .expense:
            return .text("")
        }
    }

    // MARK: Herramientas del servidor (`servidor/supabase/functions/asistente/herramientas.ts`)

    /// Ejecuta una herramienta que pidió Claude y devuelve el resultado en JSON: cifras ya sumadas y formateadas.
    static func run(_ name: String, input: JSONValue, context: ModelContext, basis: AccountingBasis, now: Date = .now) -> String {
        let books = Bookkeeper(context: context)
        let result: [String: Any]
        do {
            switch name {
            case "resumen_periodo":
                let (from, to) = try period(input)
                let s = try books.incomeStatement(from: from, to: to, basis: basis)
                result = ["periodo": label(from, to), "base": basis == .cash ? "caja" : "devengado",
                          "ingresos": s.totalIncome.money, "costo_de_ventas": s.totalCostOfGoodsSold.money,
                          "gastos": s.totalExpenses.money, "ganancia_neta": s.netIncome.money]
            case "gastos_por_categoria", "ingresos_por_categoria":
                let (from, to) = try period(input)
                let s = try books.incomeStatement(from: from, to: to, basis: basis)
                let rows = name == "ingresos_por_categoria" ? s.income : s.costOfGoodsSold + s.expenses
                result = ["periodo": label(from, to), "base": basis == .cash ? "caja" : "devengado",
                          "total": rows.reduce(0) { $0 + $1.amount }.money,
                          "categorias": rows.filter { $0.amount != 0 }.sorted { $0.amount > $1.amount }
                              .map { ["categoria": $0.account.name, "importe": $0.amount.money] }]
            case "por_cobrar":
                let open = try books.fetch(Invoice.self).filter { $0.isOpen && $0.balanceDue > 0 }
                    .sorted { $0.dueDate < $1.dueDate }
                result = ["total": open.reduce(0) { $0 + $1.balanceDue }.money, "facturas": open.count,
                          "detalle": open.prefix(40).map { invoice in
                              ["cliente": invoice.customer?.name ?? "", "numero": invoice.number,
                               "vence": day(invoice.dueDate), "saldo": invoice.balanceDue.money,
                               "dias_de_atraso": invoice.daysOverdue(asOf: now) ?? 0] as [String: Any]
                          }]
            case "por_pagar":
                let open = try books.fetch(Bill.self).filter { $0.isOpen && $0.balanceDue > 0 }
                    .sorted { $0.dueDate < $1.dueDate }
                result = ["total": open.reduce(0) { $0 + $1.balanceDue }.money, "facturas": open.count,
                          "detalle": open.prefix(40).map { bill in
                              let late = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: bill.dueDate),
                                                                         to: Calendar.current.startOfDay(for: now)).day ?? 0
                              return ["proveedor": bill.vendor?.name ?? "", "numero": bill.vendorNumber,
                                      "vence": day(bill.dueDate), "saldo": bill.balanceDue.money,
                                      "dias_de_atraso": max(0, late)] as [String: Any]
                          }]
            case "apartado_impuestos":
                guard let s = try books.estimatedTaxSummary(today: now, basis: basis) else {
                    result = ["error": "No pude calcular el apartado (falta el año fiscal de la empresa)."]
                    break
                }
                result = ["porcentaje": s.percent, "ano_fiscal": s.taxYear,
                          "pago_que_toca": ["periodo": label(s.focus.period.start, s.focus.period.end.addingTimeInterval(-1)),
                                            "vence": day(s.focus.period.due), "dias_que_faltan": s.daysLeft,
                                            "ganancia": s.focus.profit.money, "apartar": s.focus.toSetAside.money,
                                            "pagado": s.focus.paid.money],
                          "periodos": s.rows.map { row in
                              ["numero": row.period.number, "vence": day(row.period.due), "empezado": row.isStarted,
                               "ganancia": row.profit.money, "apartar": row.toSetAside.money, "pagado": row.paid.money] as [String: Any]
                          },
                          "pagado_en_el_ano": s.paidThisYear.money,
                          "nota": "Guía con el porcentaje que eligió el usuario; no es asesoría fiscal."]
            case "saldos_cuentas":
                let ledger = Ledger(accounts: try books.fetch(Account.self), lines: try books.fetch(JournalLine.self))
                result = ["efectivo_disponible": ledger.availableCash.money,
                          "cuentas": ledger.moneyAccounts.map { account in
                              ["cuenta": account.name, "tipo": account.subtype == .creditCard ? "tarjeta de crédito" : "dinero",
                               "saldo": ledger.cashBalance(of: account).money]
                          }]
            case "citas":
                let (from, to) = try period(input)
                let names = Dictionary(try books.fetch(Customer.self).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
                let items = try books.appointments(in: DateInterval(start: from, end: to))
                    .filter { $0.status != .removed }
                result = ["periodo": label(from, to), "citas": items.prefix(60).map { o in
                    ["inicio": day(o.start, time: true),
                     "minutos": o.appointment.durationMinutes,
                     "cliente": o.appointment.customerID.flatMap { names[$0] } ?? "",
                     "titulo": o.appointment.title, "lugar": o.appointment.location,
                     "estado": o.status.rawValue] as [String: Any]
                }]
            case "sales_tax":
                result = try salesTax(books: books, now: now)
            case "buscar_movimientos":
                result = try search(input, books: books)
            case "abrir_pantalla":
                // La pide Claude con la respuesta; el botón lo pone `AssistantState` (aquí solo se confirma).
                let screen = AssistantScreens.item(input["pantalla"]?.string ?? "")
                result = screen.map { ["boton": String(localized: "Ir a \(AssistantScreens.title($0))")] }
                    ?? ["error": "No existe esa pantalla."]
            default:
                result = ["error": "No existe la herramienta \(name)."]
            }
        } catch ToolError.badDates {
            result = ["error": "Fechas no válidas: usa AAAA-MM-DD y que «desde» no sea después de «hasta»."]
        } catch {
            result = ["error": "No pude leer los libros."]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private enum ToolError: Error { case badDates }

    /// Sales tax: lo pendiente según los libros, el periodo de declaración en curso y el anterior con su fecha límite.
    private static func salesTax(books: Bookkeeper, now: Date) throws -> [String: Any] {
        let cal = Calendar.current
        let agencies = try books.fetch(TaxAgency.self).filter { !$0.isArchived }
        let liabilities = try books.fetch(Account.self).filter { $0.subtype == .salesTaxPayable && !$0.isArchived }
        let frequency = FilingFrequency.shownForSalesTax(agencies)
        let current = Bookkeeper.salesTaxFilingPeriod(frequency, containing: now)
        let previous = Bookkeeper.salesTaxFilingPeriod(frequency, containing: cal.date(byAdding: .day, value: -1, to: current.start) ?? current.start)
        func owed(asOf date: Date?) -> Int64 { liabilities.reduce(0) { $0 + books.postedBalance(of: $1, asOf: date) } }
        func summary(_ from: Date, _ to: Date) throws -> [String: Any] {
            let s = try books.salesTaxSummary(from: from, to: to)
            return ["periodo": label(from, to), "ventas": s.totalSales.money, "ventas_gravables": s.taxableSales.money,
                    "impuesto_cobrado": s.totalTax.money,
                    "por_tasa": s.rows.map { ["tasa": $0.name, "porcentaje": "\($0.percent)", "impuesto": $0.tax.money] as [String: Any] }]
        }
        let endOfPrevious = cal.date(byAdding: DateComponents(day: 1, second: -1), to: cal.startOfDay(for: previous.end)) ?? previous.end
        var last = try summary(previous.start, endOfPrevious)
        last["fecha_limite"] = day(previous.deadline)
        last["pendiente_al_cierre"] = owed(asOf: endOfPrevious).money
        var running = try summary(current.start, now)
        running["fecha_limite"] = day(current.deadline)
        return ["frecuencia": frequency.rawValue, "agencias": agencies.map(\.name), "pendiente_hoy": owed(asOf: nil).money,
                "periodo_anterior": last, "periodo_en_curso": running,
                "nota": "Saldo de la cuenta de sales tax según los libros. La declaración se presenta en la agencia del estado."]
    }

    /// Movimientos que nombran a alguien o algo: gastos, facturas por pagar, facturas y cobros, con sus totales.
    private static func search(_ input: JSONValue, books: Bookkeeper) throws -> [String: Any] {
        let wanted = AssistantDrafts.folded(input["texto"]?.string ?? "")
        guard wanted.count >= 2 else { return ["error": "Falta qué buscar (un nombre, un número o una palabra)."] }
        var from = Date.distantPast, to = Date.distantFuture
        // Sin «desde» o sin «hasta», abierto por ese lado.
        if input["desde"]?.string != nil || input["hasta"]?.string != nil {
            (from, to) = try period(.object(["desde": .string(input["desde"]?.string ?? "1900-01-01"),
                                             "hasta": .string(input["hasta"]?.string ?? "2999-12-31")]))
        }
        func hit(_ texts: String...) -> Bool { texts.contains { AssistantDrafts.folded($0).contains(wanted) } }
        func inRange(_ date: Date) -> Bool { date >= from && date <= to }
        typealias Row = (date: Date, kind: String, who: String, reference: String, amount: Int64, memo: String)
        var rows: [Row] = []
        for e in try books.fetch(Expense.self) where !e.isVoid && inRange(e.date)
            && hit(e.payee, e.vendor?.name ?? "", e.memo, e.reference, e.customer?.name ?? "") {
            rows.append((e.date, "gasto", e.vendor?.name ?? e.payee, e.reference, e.total, e.memo))
        }
        for b in try books.fetch(Bill.self) where b.status != .void && inRange(b.billDate)
            && hit(b.vendor?.name ?? "", b.vendorNumber, b.memo) {
            rows.append((b.billDate, "factura por pagar", b.vendor?.name ?? "", b.vendorNumber, b.total, b.memo))
        }
        for i in try books.fetch(Invoice.self) where i.status != .void && i.status != .draft && inRange(i.issueDate)
            && hit(i.customer?.name ?? "", i.number) {
            rows.append((i.issueDate, "factura", i.customer?.name ?? "", i.number, i.total, ""))
        }
        for p in try books.fetch(PaymentReceived.self) where !books.isVoided(p) && inRange(p.date) && hit(p.customer?.name ?? "") {
            let invoices = (p.applications ?? []).compactMap { $0.invoice?.number }.sorted().joined(separator: ", ")
            rows.append((p.date, "cobro", p.customer?.name ?? "", invoices, p.amount, invoices.isEmpty ? "" : "aplicado a \(invoices)"))
        }
        rows.sort { $0.date > $1.date }
        let totals = Dictionary(grouping: rows, by: \.kind).mapValues { group in
            ["cuantos": group.count, "total": group.reduce(Int64(0)) { $0 + $1.amount }.money] as [String: Any]
        }
        return ["buscado": input["texto"]?.string ?? "", "periodo": from == .distantPast && to == .distantFuture ? "todo" : label(from, to),
                "encontrados": rows.count, "totales_por_tipo": totals,
                "detalle": rows.prefix(40).map { r in
                    ["fecha": day(r.date), "tipo": r.kind, "quien": r.who, "referencia": r.reference, "importe": r.amount.money,
                     "nota": r.memo] as [String: Any]
                },
                "nota": rows.count > 40 ? "Solo los 40 más recientes en «detalle»; los totales son de todos." : ""]
    }

    /// «desde» y «hasta» (incluido) en el calendario del aparato: del inicio de «desde» al último instante de «hasta».
    private static func period(_ input: JSONValue) throws -> (Date, Date) {
        let cal = Calendar.current
        func parse(_ key: String) -> Date? {
            guard let text = input[key]?.string else { return nil }
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        guard let from = parse("desde"), let toDay = parse("hasta"), from <= toDay,
              let to = cal.date(byAdding: .day, value: 1, to: toDay)?.addingTimeInterval(-1) else { throw ToolError.badDates }
        return (from, to)
    }

    /// AAAA-MM-DD en la zona horaria del aparato (el formato ISO de Foundation usa UTC y cambiaba el día por la noche).
    static func day(_ date: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func label(_ from: Date, _ to: Date) -> String { "\(day(from)) a \(day(to))" }
}

/// ¿Hay internet? (canvas `AsistenteSinConexion`). Las sugerencias funcionan sin conexión; las preguntas escritas, no.
@MainActor @Observable
final class AssistantConnectivity {
    static let shared = AssistantConnectivity()
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in AssistantConnectivity.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "chirogra.asistente.red"))
    }
}

/// Las pantallas a las que el asistente puede llevar (`abrir_pantalla`). Los ids son los del servidor
/// (`servidor/supabase/functions/asistente/herramientas.ts`): si se cambia uno, cambiarlo en los dos sitios.
enum AssistantScreens {
    static let all: [(id: String, item: SidebarItem)] = [
        ("inicio", .section(.home)), ("agenda", .section(.agenda)), ("ajustes", .section(.settings)),
        ("facturas", .sales(.invoices)), ("estimados", .sales(.estimates)), ("clientes", .sales(.customers)),
        ("gastos", .expenses(.expenses)), ("proveedores", .expenses(.vendors)), ("facturas_por_pagar", .expenses(.bills)),
        ("gastos_recurrentes", .expenses(.recurring)),
        ("banca_cuentas", .banking(.accounts)), ("banca_por_revisar", .banking(.inbox)), ("banca_reglas", .banking(.rules)),
        ("conciliacion", .banking(.reconcile)),
        ("reporte_resultados", .report(.income)), ("reporte_balance_general", .report(.balance)), ("reporte_balanza", .report(.trial)),
        ("reporte_flujo_de_efectivo", .report(.cashFlow)), ("reporte_por_cobrar", .report(.receivables)),
        ("reporte_por_pagar", .report(.payables)), ("reporte_sales_tax", .report(.salesTax)), ("presupuestos", .report(.budget)),
        ("plan_de_cuentas", .accounting(.chart)), ("asientos_de_diario", .accounting(.journal)), ("libro_mayor", .accounting(.ledger)),
        ("cierre_de_periodo", .accounting(.close)), ("bitacora", .accounting(.auditLog)),
        ("impuesto_sobre_ventas", .taxes(.salesTax)), ("impuestos_estimados", .taxes(.estimated)),
    ]

    static func item(_ id: String) -> SidebarItem? { all.first { $0.id == id }?.item }

    /// El nombre tal como sale en la barra lateral.
    static func title(_ item: SidebarItem) -> String {
        switch item {
        case .section(let section): return section.title
        case .expenses(.recurring): return String(localized: "Gastos recurrentes")
        case .report(let kind): return kind.fullTitle
        case .accounting(let page): return page.title
        case .banking(let page): return page.title
        case .taxes(let page): return page.title
        case .sales, .expenses:
            return SidebarItem.subsections(of: item.section).first { $0.item == item }?.title ?? item.section.title
        }
    }
}
