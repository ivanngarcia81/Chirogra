#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: bandeja «Por revisar» como tabla + inspector (no hay tablero del Mac: sigue `BancaCuentas` y `iPadBanca`).
/// Tabla Fecha · Descripción · Cuenta · Propuesta · Importe con el filtro Por revisar · Revisados · Excluidos y la
/// cuenta; el inspector muestra el movimiento con su sugerencia y los botones: aceptarla, «Revisar…» (la hoja de
/// revisión), crear una regla, excluir o, si ya se revisó, devolverlo a la bandeja. En la barra, «Aceptar sugeridas»
/// e «Importar extracto» (también arrastrando el archivo a la tabla).
struct BankInboxTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var modelContext
    @CompanyQuery(sort: [SortDescriptor(\BankTransaction.date, order: .reverse), SortDescriptor(\BankTransaction.importedAt)])
    private var transactions: [BankTransaction]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var filter: BankInboxFilter = .pending
    @State private var accountID: UUID?
    @State private var query = ""
    @State private var reviewing: BankTransaction?
    @State private var importing: BankImportRequest?
    @State private var ruleDraft: BankRuleDraftRequest?
    /// «Excluir»: se pregunta el motivo (1.2).
    @State private var excluding: BankTransaction?
    @State private var errorMessage: String?

    var body: some View {
        let context = BankInboxContext(books: Bookkeeper(context: modelContext), accounts: accounts, invoices: invoices, bills: bills)
        // La cuenta corta en la tabla («••4821»), como el segmentado del iPad: el nombre completo empujaba el importe.
        let names = Dictionary(accounts.map { ($0.id, $0.last4.isEmpty ? $0.name : "••\($0.last4)") }, uniquingKeysWith: { first, _ in first })
        let fullNames = Dictionary(accounts.map { ($0.id, $0.maskedName) }, uniquingKeysWith: { first, _ in first })
        let inAccount = transactions.filter { accountID == nil || $0.accountID == accountID }
        let rows = inAccount.filter { filter.matches($0) && BankInboxSearch.matches($0, query) }.enumerated().map { index, transaction in
            BankInboxRow(transaction: transaction, order: index, accountName: names[transaction.accountID ?? UUID()] ?? "—",
                         accountFullName: fullNames[transaction.accountID ?? UUID()] ?? "—",
                         suggestion: context.suggestion(for: transaction))
        }
        let pending = inAccount.filter(\.isPending)
        MacTablePage(
            title: String(localized: "Por revisar"),
            subtitle: String(localized: "Banca · \(pending.count) por revisar"),
            rows: rows, footer: String(localized: "\(rows.count) movimientos"),
            query: $query, searchPrompt: Text("Descripción o monto"),
            selection: $selection, sortOrder: [KeyPathComparator(\BankInboxRow.order)],
            addTitle: String(localized: "Importar extracto"), onAdd: { importing = BankImportRequest(file: nil) },
            onOpen: { if $0.transaction.isPending { reviewing = $0.transaction } },
            empty: empty(filter: filter, total: transactions.count),
            inspectorTitle: { _ in String(localized: "Movimiento") },
            inspectorPlaceholder: String(localized: "Selecciona un movimiento para revisarlo.")
        ) {
            TableColumn("Fecha", value: \.order) { MacCellText(text: $0.transaction.date.dayMonth) }.width(min: 50, ideal: 58, max: 90)
            TableColumn("Descripción", value: \.title) { Text($0.title).lineLimit(1) }.width(min: 120, ideal: 170)
            TableColumn("Cuenta", value: \.accountName) { MacCellText(text: $0.accountName) }.width(min: 50, ideal: 64, max: 180)
            TableColumn(filter == .pending ? "Propuesta" : "Estado", value: \.statusText) { row in
                MacCellStatus(chip: StatusChip(text: row.statusText, foreground: row.statusColor, background: .clear, compact: true, dot: row.dot))
            }
            .width(min: 110, ideal: 150)
            TableColumn("Importe", value: \.amount) { row in
                MacCellText(text: row.transaction.signedAmount, color: row.transaction.amountColor).monospacedDigit()
            }
            .width(min: 72, ideal: 88, max: 140)
            .alignment(.trailing)
        } filter: {
            HStack(spacing: 12) {
                MacTableFilter(title: String(localized: "Filtrar"), options: BankInboxFilter.allCases, selection: $filter,
                               label: \.localizedTitle) { option in inAccount.filter { option.matches($0) }.count }
                Picker("Cuenta", selection: $accountID) {
                    Text("Todas las cuentas").tag(UUID?.none)
                    ForEach(accounts.filter { ($0.subtype == .bank || $0.subtype == .creditCard) && !$0.isArchived }) {
                        Text($0.maskedName).tag(Optional($0.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer(minLength: 0)
            }
        } inspector: { row in
            BankInboxInspector(row: row)
        } actions: { row in
            actions(for: row, context: context)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    SubscriptionStore.shared.whenWritable {
                        let result = BankReview.acceptAll(pending, context: context)
                        if let error = result.error { errorMessage = error.localizedDescription }
                    }
                } label: {
                    Label("Aceptar sugeridas", systemImage: "checkmark.circle").labelStyle(.titleAndIcon)
                }
                .help("Registra todos los movimientos que tienen una propuesta")
                .disabled(!pending.contains { context.suggestion(for: $0).isActionable })
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let file = try? BankImportFile.load(url) else { return false }
            importing = BankImportRequest(file: file)
            return true
        }
        .sheet(item: $reviewing) { BankReviewSheet(start: $0).editorSheetSizing() }
        .bankExclusionDialog($excluding) { target, reason in
            act { try Bookkeeper(context: modelContext).ignore(target, reason: reason) } then: { selectNext(after: target) }
        }
        .sheet(item: $importing) { request in
            NavigationStack { BankImportView(initialFile: request.file, preferredAccountID: accountID) }.editorSheetSizing()
        }
        .sheet(item: $ruleDraft) { request in
            NavigationStack { BankRuleEditorView(draft: request.input) }.editorSheetSizing()
        }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        #if DEBUG
        .task {
            try? await Task.sleep(for: .seconds(1))
            if let file = QABanking.importFile { importing = BankImportRequest(file: file) }
            if let index = QABanking.reviewIndex, pending.indices.contains(index) { reviewing = pending[index] }
            if UserDefaults.standard.bool(forKey: "qa.aceptarSugeridas") { _ = BankReview.acceptAll(pending, context: context) }
        }
        #endif
    }

    @ViewBuilder
    private func actions(for row: BankInboxRow, context: BankInboxContext) -> some View {
        let transaction = row.transaction
        if transaction.isPending {
            if row.suggestion.isActionable {
                Button(row.suggestion.acceptTitle) {
                    act { try BankReview.accept(row.suggestion, for: transaction, books: context.books) } then: { selectNext(after: transaction) }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                Button("Revisar…") { reviewing = transaction }.buttonStyle(.secondary)
            } else {
                Button("Revisar…") { reviewing = transaction }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
            HStack {
                Button("Crear regla…") { ruleDraft = BankRuleDraftRequest(input: draftRule(for: transaction)) }.buttonStyle(.secondary)
                Button("Excluir", role: .destructive) { excluding = transaction }
                .buttonStyle(.destructive)
            }
        } else {
            Button("Devolver a la bandeja") { act { try context.books.returnToInbox(transaction) } then: {} }.buttonStyle(.secondary)
        }
    }

    private func draftRule(for transaction: BankTransaction) -> BankRuleInput {
        let text = BankRuleDraft.matchText(from: transaction.details)
        return BankRuleInput(name: text, matchText: text, amountSign: transaction.amount < 0 ? .outflow : .inflow,
                             targetAccountID: transaction.categoryAccountID, vendorID: transaction.vendorID)
    }

    private func selectNext(after transaction: BankTransaction) {
        let pending = transactions.filter { $0.isPending && (accountID == nil || $0.accountID == accountID) }
        selection = BankReview.next(after: transaction, in: pending.filter { $0.id != transaction.id })?.id
    }

    private func act(_ body: () throws -> Void, then: () -> Void) {
        SubscriptionStore.shared.whenWritable {
            do { try body(); then() } catch { errorMessage = error.localizedDescription }
        }
    }

    private func empty(filter: BankInboxFilter, total: Int) -> MacTableEmpty {
        if total == 0 {
            return MacTableEmpty(systemImage: "tray", title: String(localized: "Aún no has importado movimientos"),
                                 message: String(localized: "Baja el extracto de tu banco en CSV u OFX y arrástralo aquí: verás cada movimiento con lo que la app propone para registrarlo."),
                                 actionTitle: String(localized: "Importar extracto"), action: { importing = BankImportRequest(file: nil) }, isGuide: true)
        }
        if !query.isEmpty {
            return MacTableEmpty(title: String(localized: "Sin resultados"), message: String(localized: "Ningún movimiento coincide con la búsqueda."),
                                 actionTitle: String(localized: "Quitar búsqueda"), action: { query = "" })
        }
        return filter == .pending
            ? MacTableEmpty(systemImage: "checkmark.circle", title: String(localized: "Todo revisado"),
                            message: String(localized: "No queda nada por revisar. Importa el próximo extracto cuando lo tengas."))
            : MacTableEmpty(systemImage: "tray", title: String(localized: "Nada por aquí todavía"), message: "")
    }
}

/// Fila de la tabla. Claves de orden `nonisolated` (REDISEÑO-NATIVO §5).
nonisolated struct BankInboxRow: Identifiable {
    let transaction: BankTransaction
    let id: UUID
    let order: Int
    let title: String
    let accountName: String
    let accountFullName: String
    let amount: Int64
    let statusText: String
    let statusColor: Color
    let dot: Color
    let suggestion: BankSuggestion

    @MainActor
    init(transaction: BankTransaction, order: Int, accountName: String, accountFullName: String, suggestion: BankSuggestion) {
        self.transaction = transaction
        id = transaction.id
        self.order = order
        title = transaction.shownTitle
        self.accountName = accountName
        self.accountFullName = accountFullName
        amount = transaction.amount
        self.suggestion = suggestion
        if transaction.isPending {
            statusText = suggestion.title
            statusColor = suggestion.textColor
            dot = suggestion.dotColor
        } else {
            statusText = transaction.statusWithReason
            statusColor = Palette.ink2
            dot = transaction.statusDot
        }
    }
}

/// Inspector del movimiento: importe, descripción, sugerencia y detalles del banco.
private struct BankInboxInspector: View {
    let row: BankInboxRow

    var body: some View {
        let transaction = row.transaction
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: transaction.signedAmount).font(.amount(24)).foregroundStyle(transaction.amountColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(transaction.shownTitle).font(.body).foregroundStyle(Palette.ink)
            Text(verbatim: "\(row.accountFullName) · \(transaction.date.shortDate)").font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        if transaction.isPending {
            MacInspectorSection(title: String(localized: "Sugerencia")) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        StatusDot(color: row.suggestion.dotColor)
                        Text(row.suggestion.title).foregroundStyle(row.suggestion.textColor).fontWeight(.semibold)
                    }
                    Text(row.suggestion.reason).font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .padding(.vertical, 4)
            }
        }
        MacInspectorSection(title: String(localized: "Del banco")) {
            MacInspectorRow(String(localized: "Fecha"), value: transaction.date.shortDate)
            MacInspectorRow(String(localized: "Cuenta"), value: row.accountFullName)
            if !transaction.payee.isEmpty, transaction.payee != transaction.details {
                MacInspectorRow(String(localized: "Beneficiario"), value: transaction.payee)
            }
            if !transaction.memo.isEmpty { MacInspectorRow(String(localized: "Nota"), value: transaction.memo) }
            if !transaction.checkNumber.isEmpty { MacInspectorRow(String(localized: "Cheque"), value: transaction.checkNumber) }
            MacInspectorRow(String(localized: "Origen"), value: transaction.source == .ofx ? "OFX" : "CSV")
            MacInspectorRow(String(localized: "Importado"), value: transaction.importedAt.shortDate)
        }
        MacInspectorSection(title: String(localized: "Estado")) {
            MacInspectorRow(label: String(localized: "Estado")) {
                StatusChip(text: transaction.statusTitle, foreground: Palette.ink2, background: .clear, compact: true, dot: transaction.statusDot)
            }
            if let reviewed = transaction.reviewedAt { MacInspectorRow(String(localized: "Revisado"), value: reviewed.shortDate) }
        }
    }
}
#endif
