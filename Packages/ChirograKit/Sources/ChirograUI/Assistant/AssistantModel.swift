import ChirograCore
import ChirograData
import Network
import SwiftData
import SwiftUI

// MARK: - Asistente (1.4, docs/PLAN-1.4.md §2; canvas «Chirogra 1.4», tableros `Asistente*`, `EntradaB`, `iPadAsistente`)
//
// Se abre con la burbuja flotante (decisión del usuario del 25-nov). Las cifras las calcula el aparato (`AssistantTools`):
// es lo que hará también con el servidor, que solo pasará la pregunta a Claude y le devolverá a Claude estas mismas
// cifras. Hasta tener el servidor (clave de Anthropic y Supabase «chirogra», trámites del usuario), contestan las
// sugerencias; una pregunta libre explica que falta conectar el asistente.

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
    /// Abre el editor de gasto (sugerencia «Anota un gasto» mientras no hay servidor).
    var registeringExpense = false
    var consented = UserDefaults.standard.bool(forKey: AssistantState.consentKey) {
        didSet { UserDefaults.standard.set(consented, forKey: Self.consentKey) }
    }

    func reset() { messages = [] }

    func ask(_ suggestion: AssistantSuggestion, context: ModelContext, basis: AccountingBasis) {
        if suggestion == .expense {
            registeringExpense = true
            return
        }
        messages.append(AssistantMessage(role: .user, content: .text(suggestion.title)))
        messages.append(AssistantMessage(role: .assistant, content: AssistantTools.answer(suggestion, context: context, basis: basis)))
    }

    /// Una pregunta escrita. Sin servidor todavía, lo explica.
    func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(AssistantMessage(role: .user, content: .text(trimmed)))
        messages.append(AssistantMessage(role: .assistant, content: .text(String(localized: "Todavía no puedo contestar preguntas escritas: falta conectar el asistente con su servidor. Mientras tanto, prueba las sugerencias de abajo."))))
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
