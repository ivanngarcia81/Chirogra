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
    /// Abre el editor de gasto (sugerencia «Anota un gasto» mientras no hay servidor).
    var registeringExpense = false
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
        conversation.append(.object(["role": .string("user"), "content": .string(trimmed)]))
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await converse(context: context, basis: basis)
            } catch {
                // La conversación vuelve a como estaba: sin la pregunta que no se contestó.
                conversation = before
                messages.append(AssistantMessage(role: .assistant, content: .text(Self.explain(error))))
            }
        }
    }

    private func converse(context: ModelContext, basis: AccountingBasis) async throws {
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
                let output = AssistantTools.run(call["name"]?.string ?? "", input: call["input"] ?? .null,
                                                context: context, basis: basis)
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
