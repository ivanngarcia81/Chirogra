import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Campana de avisos de Inicio (canvas `Home`, `iPadInicio`: «Notificaciones, 2 nuevas»; en el Mac, en la barra de
/// `MacInicio`). El botón lleva un globo rojo con los avisos sin leer (`Bookkeeper.unreadNoticeCount`) y abre la lista
/// de `notices()`: marcar como leído, descartar e ir al documento. Los avisos se calculan de los datos (pagos
/// programados, facturas vencidas, sales tax por declarar, por pagar esta semana y recurrentes recién generados).
struct NoticesButton: View {
    /// Abre el documento del aviso (la lista ya se cerró).
    let onOpen: (Notice) -> Void
    @Environment(\.modelContext) private var context
    // Se observan para recalcular los avisos cuando cambian los datos de los que salen.
    @CompanyQuery private var states: [NoticeState]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery private var expenses: [Expense]
    @CompanyQuery private var lines: [JournalLine]
    @State private var showing = false

    var body: some View {
        let _ = (states.count, invoices.count, bills.count, expenses.count, lines.count)
        let unread = ((try? Bookkeeper(context: context).notices()) ?? []).filter { !$0.isRead }.count
        Button { showing = true } label: {
            Label("Avisos", systemImage: "bell")
                .labelStyle(.iconOnly)
        }
        // El globo del sistema en el botón de la barra (iOS 26 y macOS 26), con el número sin leer.
        .badge(unread)
        .accessibilityLabel(unread > 0 ? String(localized: "Avisos, \(unread) sin leer") : String(localized: "Avisos"))
        .help("Avisos")
        // Panel de clientes: «Avisos».
        .onClientRoute({ $0 == .notices }) { _ in showing = true }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            NavigationStack {
                NoticesList { notice in
                    showing = false
                    onOpen(notice)
                }
            }
            #if os(macOS)
            .frame(width: 380, height: 460)
            #else
            .frame(minWidth: 360, idealWidth: 400, minHeight: 420, idealHeight: 560)
            #endif
            .presentationDetents([.medium, .large])
        }
        #if DEBUG
        // `-qa.avisos 1` abre la lista al aparecer (solo Debug).
        .task {
            guard UserDefaults.standard.bool(forKey: "qa.avisos") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showing = true
        }
        #endif
    }
}

/// Lista de avisos: los más urgentes primero, los no leídos con punto azul. Tocar uno lo marca leído y abre su
/// documento; deslizar (o el menú contextual) lo marca leído o lo descarta.
struct NoticesList: View {
    let onOpen: (Notice) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @CompanyQuery private var states: [NoticeState]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery private var expenses: [Expense]
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }

    var body: some View {
        let _ = (states.count, invoices.count, bills.count, expenses.count)
        let notices = (try? books.notices()) ?? []
        List {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            ForEach(notices) { notice in
                Button {
                    act { try books.markNoticeRead(notice.id) }
                    onOpen(notice)
                } label: {
                    NoticeRow(notice: notice)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Descartar", systemImage: "xmark", role: .destructive) { act { try books.dismissNotice(notice.id) } }
                        .tint(Palette.red)
                }
                .swipeActions(edge: .leading) {
                    if !notice.isRead {
                        Button("Leído", systemImage: "envelope.open") { act { try books.markNoticeRead(notice.id) } }
                            .tint(Palette.blue)
                    }
                }
                .contextMenu {
                    Button("Abrir", systemImage: "arrow.forward") {
                        act { try books.markNoticeRead(notice.id) }
                        onOpen(notice)
                    }
                    if !notice.isRead {
                        Button("Marcar como leído", systemImage: "envelope.open") { act { try books.markNoticeRead(notice.id) } }
                    }
                    Button("Descartar", systemImage: "xmark", role: .destructive) { act { try books.dismissNotice(notice.id) } }
                }
                .accessibilityAction(named: "Descartar") { act { try books.dismissNotice(notice.id) } }
                .accessibilityAction(named: "Marcar como leído") { act { try books.markNoticeRead(notice.id) } }
            }
        }
        .overlay {
            if notices.isEmpty {
                ContentUnavailableView("Sin avisos", systemImage: "bell",
                                       description: Text("Aquí verás los pagos programados, las facturas vencidas y el impuesto por declarar."))
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Avisos")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Marcar todo como leído") { act { try books.markAllNoticesRead() } }
                    .disabled(!notices.contains { !$0.isRead })
            }
            #if os(iOS)
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
            #endif
        }
    }

    private func act(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }
}

/// Fila del aviso: icono de su tipo, qué pasa, a quién y cuándo, el importe y el punto de no leído.
private struct NoticeRow: View {
    let notice: Notice
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var failures = AutomationFailures.shared

    /// Motivo si el cargo automático de este pago programado falló al abrir la app.
    private var failure: String? {
        guard notice.kind == .scheduledPaymentDue, let id = notice.documentID else { return nil }
        return failures.byBill[id]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: failure == nil ? notice.symbol : "exclamationmark.circle", foreground: failure == nil ? notice.color : Palette.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(failure == nil ? notice.title : String(localized: "Falló el cargo automático a \(notice.party)"))
                    .font(.body.weight(notice.isRead ? .regular : .semibold)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure ?? notice.detail).font(.footnote)
                    .foregroundStyle(failure != nil ? Palette.negative : notice.isUrgent ? Palette.warning : Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(notice.amount.money).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink)
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(notice.amount.money).monospacedDigit().foregroundStyle(Palette.ink)
            }
            Circle().fill(notice.isRead ? Color.clear : Palette.blue).frame(width: 8, height: 8).padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(notice.isRead ? "" : String(localized: "Sin leer"))
        .accessibilityHint("Abre el documento")
    }
}

extension Notice {
    var symbol: String {
        switch kind {
        case .overdueInvoice: "exclamationmark.triangle"
        case .billDueSoon: "calendar"
        case .scheduledPaymentDue: "clock"
        case .recurringGenerated: "arrow.triangle.2.circlepath"
        case .salesTaxDue: "percent"
        }
    }

    var color: Color {
        switch kind {
        case .overdueInvoice: Palette.red
        case .billDueSoon: Palette.orange
        case .scheduledPaymentDue: Palette.blue
        case .recurringGenerated: needsConfirmation ? Palette.orange : Palette.indigo
        case .salesTaxDue: Palette.pink
        }
    }

    /// Lo de hoy o lo vencido va en naranja.
    var isUrgent: Bool { days <= 0 || needsConfirmation }

    var title: String {
        switch kind {
        case .overdueInvoice: String(localized: "Factura \(reference) vencida")
        case .billDueSoon: String(localized: "Pagar a \(party)")
        case .scheduledPaymentDue: String(localized: "Pago programado a \(party)")
        case .recurringGenerated:
            needsConfirmation ? String(localized: "Confirma el gasto recurrente de \(party)")
                              : String(localized: "Se registró el recurrente de \(party)")
        case .salesTaxDue: String(localized: "Declarar sales tax · \(party)")
        }
    }

    /// «Hotel Mirador · venció hace 8 días», «Vence en 3 días», «Programado para hoy»…
    var detail: String {
        switch kind {
        case .overdueInvoice:
            String(localized: "\(party) · venció hace \(-days) días")
        case .billDueSoon:
            [reference, dueText].filter { !$0.isEmpty }.joined(separator: " · ")
        case .scheduledPaymentDue:
            [reference, days < 0 ? String(localized: "Programado para el \(date.shortDate)") : String(localized: "Programado para hoy")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .recurringGenerated:
            needsConfirmation ? String(localized: "Por confirmar · \(date.shortDate)") : date.shortDate
        case .salesTaxDue:
            String(localized: "Fecha límite \(date.shortDate) · \(dueText)")
        }
    }

    /// «Vence hoy», «Vence mañana», «Vence en 5 días».
    private var dueText: String {
        switch days {
        case ..<0: String(localized: "Venció hace \(-days) días")
        case 0: String(localized: "Vence hoy")
        case 1: String(localized: "Vence mañana")
        default: String(localized: "Vence en \(days) días")
        }
    }
}

/// Documento de un aviso, para abrirlo encima de Inicio.
struct NoticeDestination: View {
    let notice: Notice
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery private var expenses: [Expense]

    var body: some View {
        let id = notice.documentID
        switch notice.kind {
        case .overdueInvoice:
            if let invoice = invoices.first(where: { $0.id == id }) { InvoiceDetailView(invoice: invoice) } else { missing }
        case .billDueSoon, .scheduledPaymentDue:
            if let bill = bills.first(where: { $0.id == id }) { BillDetailView(bill: bill) } else { missing }
        case .recurringGenerated:
            if let expense = expenses.first(where: { $0.id == id }) {
                ExpenseDetailView(expense: expense)
            } else if let bill = bills.first(where: { $0.id == id }) {
                BillDetailView(bill: bill)
            } else { missing }
        case .salesTaxDue:
            TaxesView()
        }
    }

    private var missing: some View {
        ContentUnavailableView("El documento ya no existe", systemImage: "doc.questionmark")
    }
}
