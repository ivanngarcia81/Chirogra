import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Bandeja «Por revisar» (canvas `Banca`, `BancaRevisar`, `iPadBanca`): los movimientos importados que faltan por
// registrar, con lo que la app propone (coincidencia, factura abierta o regla). iPhone: sección en Banca con ✓ para
// aceptar de un toque y una hoja «Revisar transacción» que pasa a la siguiente; iPad: columna maestro + detalle;
// Mac: tabla + inspector (`BankInboxTablePage`).

// MARK: - Subsecciones de Banca (barra lateral de iPad y Mac)

/// Páginas de Banca en la barra lateral: Cuentas (la de siempre), Por revisar, Reglas y Conciliación.
enum BankingPage: String, CaseIterable, Identifiable, Hashable {
    case accounts, inbox, rules, reconcile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: String(localized: "Cuentas")
        case .inbox: String(localized: "Por revisar")
        case .rules: String(localized: "Reglas")
        case .reconcile: String(localized: "Conciliación")
        }
    }

    /// Pantalla a todo el ancho (iPad con letra de accesibilidad y páginas sin columna maestro).
    @ViewBuilder
    var destination: some View {
        switch self {
        case .accounts: BankingView()
        case .inbox: BankInboxScreen()
        case .rules: BankRulesView()
        case .reconcile: ReconciliationHubView()
        }
    }
}

/// Pide a la columna maestro de la bandeja que elija otro movimiento (el detalle, tras «… y siguiente», no tiene la
/// selección: vive en `AppShell`).
@Observable
final class BankInboxFocus {
    static let shared = BankInboxFocus()
    var requested: UUID?
}

/// Filtro de la bandeja (los `rawValue` son las etiquetas en español del catálogo).
enum BankInboxFilter: String, CaseIterable, Identifiable {
    case pending = "Por revisar", reviewed = "Revisados", ignored = "Excluidos"
    var id: String { rawValue }

    func matches(_ transaction: BankTransaction) -> Bool {
        switch self {
        case .pending: transaction.status == .toReview
        case .reviewed: transaction.status == .categorized || transaction.status == .matched
        case .ignored: transaction.status == .ignored
        }
    }
}

// MARK: - Fila

/// Fila de un movimiento (canvas `Banca`): descripción e importe; fecha, punto de color y la propuesta debajo.
struct BankTransactionRow: View {
    let transaction: BankTransaction
    let suggestion: BankSuggestion
    var accountName: String? = nil
    @Environment(\.isMasterRowSelected) private var isSelected

    var body: some View {
        let colors = MasterRowColors(isSelected: isSelected)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(transaction.shownTitle).lineLimit(1).foregroundStyle(colors.primary)
                Spacer(minLength: 8)
                Text(verbatim: transaction.signedAmount).monospacedDigit()
                    .foregroundStyle(colors.amount(transaction.amountColor)).fixedSize()
            }
            HStack(spacing: 6) {
                Text(transaction.date.dayMonth).fixedSize()
                if let accountName { Text(verbatim: "· \(accountName)").lineLimit(1) }
                if transaction.isPending {
                    StatusDot(color: isSelected ? Palette.onBrandFill : suggestion.dotColor)
                    Text(suggestion.title).foregroundStyle(isSelected ? colors.secondary : suggestion.textColor).lineLimit(1)
                } else {
                    StatusDot(color: isSelected ? Palette.onBrandFill : transaction.statusDot)
                    Text(transaction.statusTitle).foregroundStyle(colors.secondary).lineLimit(1)
                }
            }
            .font(MasterRowColors.detailFont)
            .foregroundStyle(colors.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - iPhone: sección de Banca

/// «Por revisar N · Aceptar sugeridas» y sus filas, dentro de la lista de Banca del iPhone.
struct BankInboxSection: View {
    let transactions: [BankTransaction]
    let context: BankInboxContext
    let accountNames: [UUID: String]
    let review: (BankTransaction) -> Void
    let importStatement: () -> Void
    let report: (String) -> Void

    var body: some View {
        Section {
            if transactions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Todo revisado", systemImage: "checkmark.circle").foregroundStyle(Palette.positive).font(.body.weight(.semibold))
                    Text("Importa el extracto de tu banco (CSV u OFX) y aquí verás cada movimiento para registrarlo con un toque.")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                    Button("Importar extracto", action: importStatement).buttonStyle(.primaryCompact)
                }
                .padding(.vertical, 8)
            }
            ForEach(transactions) { transaction in
                let suggestion = context.suggestion(for: transaction)
                HStack(spacing: 4) {
                    Button { review(transaction) } label: {
                        BankTransactionRow(transaction: transaction, suggestion: suggestion, accountName: accountNames[transaction.accountID ?? UUID()])
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Abre «Revisar transacción»"))
                    if suggestion.isActionable {
                        Button { accept(suggestion, transaction) } label: {
                            Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(Palette.brand)
                                .frame(width: Metrics.target, height: Metrics.target)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Aceptar: \(suggestion.title)"))
                    }
                }
                .swipeActions(edge: .leading) {
                    if suggestion.isActionable {
                        Button(suggestion.acceptTitle) { accept(suggestion, transaction) }.tint(Palette.green)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Excluir", role: .destructive) { ignore(transaction) }
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Por revisar").font(.cardTitle).foregroundStyle(Palette.ink)
                    Text(verbatim: "\(transactions.count)").font(.title3).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if transactions.contains(where: { context.suggestion(for: $0).isActionable }) {
                    Button("Aceptar sugeridas", action: acceptAll).font(.body).tint(Palette.brand)
                }
            }
            .textCase(nil)
        } footer: {
            if !transactions.isEmpty {
                Text("✓ acepta lo que propone la app. Toca un movimiento para elegir otra categoría, emparejarlo o excluirlo.")
            }
        }
    }

    private func accept(_ suggestion: BankSuggestion, _ transaction: BankTransaction) {
        SubscriptionStore.shared.whenWritable {
            do { try BankReview.accept(suggestion, for: transaction, books: context.books) } catch { report(error.localizedDescription) }
        }
    }

    private func acceptAll() {
        SubscriptionStore.shared.whenWritable {
            let result = BankReview.acceptAll(transactions, context: context)
            if let error = result.error { report(error.localizedDescription) }
        }
    }

    private func ignore(_ transaction: BankTransaction) {
        SubscriptionStore.shared.whenWritable {
            do { try context.books.ignore(transaction) } catch { report(error.localizedDescription) }
        }
    }
}

// MARK: - Bandeja a pantalla completa (revisados y excluidos)

/// La bandeja en una lista: filtro Por revisar · Revisados · Excluidos, para devolver a la bandeja lo revisado. En el
/// iPhone se abre desde Banca; en el iPad, cuando no cabe la columna maestro (letra de accesibilidad).
struct BankInboxScreen: View {
    var initialFilter: BankInboxFilter = .pending
    @Environment(\.modelContext) private var modelContext
    @CompanyQuery(sort: [SortDescriptor(\BankTransaction.date, order: .reverse), SortDescriptor(\BankTransaction.importedAt)])
    private var transactions: [BankTransaction]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @State private var filter: BankInboxFilter?
    @State private var query = ""
    @State private var reviewing: BankTransaction?
    @State private var errorMessage: String?

    var body: some View {
        let current = filter ?? initialFilter
        let context = BankInboxContext(books: Bookkeeper(context: modelContext), accounts: accounts, invoices: invoices, bills: bills)
        let names = Dictionary(accounts.map { ($0.id, $0.maskedName) }, uniquingKeysWith: { first, _ in first })
        let shown = transactions.filter { current.matches($0) && BankInboxSearch.matches($0, query) }
        List {
            Section {
                FilterPicker(title: String(localized: "Filtrar"), options: BankInboxFilter.allCases, selection: Binding(get: { current }, set: { filter = $0 }), label: \.localizedTitle)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                if shown.isEmpty {
                    Text(current == .pending ? String(localized: "No hay movimientos por revisar.") : String(localized: "Nada por aquí todavía."))
                        .foregroundStyle(Palette.ink2)
                }
                ForEach(shown) { transaction in
                    Button { if transaction.isPending { reviewing = transaction } } label: {
                        BankTransactionRow(transaction: transaction, suggestion: context.suggestion(for: transaction),
                                           accountName: names[transaction.accountID ?? UUID()])
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if transaction.isPending {
                            Button("Excluir", role: .destructive) { act { try context.books.ignore(transaction) } }
                        } else {
                            Button("Devolver a la bandeja") { act { try context.books.returnToInbox(transaction) } }.tint(Palette.blue)
                        }
                    }
                    .contextMenu {
                        if !transaction.isPending {
                            Button("Devolver a la bandeja", systemImage: "tray.and.arrow.up") { act { try context.books.returnToInbox(transaction) } }
                        }
                    }
                }
            } footer: {
                if current != .pending, !shown.isEmpty {
                    Text("Devolver a la bandeja quita el emparejamiento o la exclusión. Lo que se registró desde el movimiento se queda: anúlalo aparte si sobra.")
                }
            }
        }
        .groupedList()
        .screenBackground()
        .searchable(text: $query, prompt: Text("Descripción o monto"))
        .navigationTitle("Movimientos del banco")
        .inlineTitle()
        .sheet(item: $reviewing) { BankReviewSheet(start: $0).editorSheetSizing() }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func act(_ body: () throws -> Void) {
        SubscriptionStore.shared.whenWritable {
            do { try body() } catch { errorMessage = error.localizedDescription }
        }
    }
}

enum BankInboxSearch {
    static func matches(_ transaction: BankTransaction, _ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return transaction.details.localizedStandardContains(text) || transaction.payee.localizedStandardContains(text)
            || abs(transaction.amount).money.contains(text)
    }
}

// MARK: - Revisar un movimiento

/// Hoja «Revisar transacción» (iPhone y Mac): × a la izquierda, «N de M por revisar» y ✓ que registra y pasa al
/// siguiente; se cierra cuando ya no queda ninguno.
struct BankReviewSheet: View {
    let start: BankTransaction
    @Environment(\.dismiss) private var dismiss
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" },
                  sort: [SortDescriptor(\BankTransaction.date, order: .reverse), SortDescriptor(\BankTransaction.importedAt)])
    private var pending: [BankTransaction]
    @State private var current: BankTransaction?

    var body: some View {
        NavigationStack {
            let shown = current ?? start
            BankReviewForm(transaction: shown, position: position(of: shown)) { done in
                if let next = BankReview.next(after: done, in: pending.filter { $0.id != done.id }) { current = next } else { dismiss() }
            }
            .id(shown.id)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", systemImage: "xmark") { dismiss() }.headerButton()
                }
            }
        }
    }

    private func position(of transaction: BankTransaction) -> String {
        let index = (pending.firstIndex { $0.id == transaction.id } ?? 0) + 1
        return String(localized: "\(index) de \(max(pending.count, index)) por revisar")
    }
}

/// Detalle del movimiento elegido en la columna maestro del iPad.
struct BankReviewDetail: View {
    let transaction: BankTransaction
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" },
                  sort: [SortDescriptor(\BankTransaction.date, order: .reverse), SortDescriptor(\BankTransaction.importedAt)])
    private var pending: [BankTransaction]

    var body: some View {
        if transaction.isPending {
            let index = (pending.firstIndex { $0.id == transaction.id } ?? 0) + 1
            BankReviewForm(transaction: transaction, position: String(localized: "\(index) de \(max(pending.count, index)) por revisar")) { done in
                BankInboxFocus.shared.requested = BankReview.next(after: done, in: pending.filter { $0.id != done.id })?.id
            }
        } else {
            BankReviewedSummary(transaction: transaction)
        }
    }
}

/// Un movimiento ya revisado: qué se hizo y «Devolver a la bandeja».
struct BankReviewedSummary: View {
    let transaction: BankTransaction
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section { BankReviewHeader(transaction: transaction, accountName: nil) }
            Section {
                LabeledContent("Estado", value: transaction.statusTitle)
                if let reviewed = transaction.reviewedAt { LabeledContent("Revisado", value: reviewed.shortDate) }
            } footer: {
                Text("Devolver a la bandeja quita el emparejamiento o la exclusión. Lo que se registró desde el movimiento se queda: anúlalo aparte si sobra.")
            }
            Section {
                Button("Devolver a la bandeja") {
                    SubscriptionStore.shared.whenWritable {
                        do { try Bookkeeper(context: context).returnToInbox(transaction) } catch { errorMessage = error.localizedDescription }
                    }
                }
                .frame(maxWidth: .infinity)
                if let errorMessage { ErrorBanner(message: errorMessage) }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(transaction.shownTitle)
        .inlineTitle()
    }
}

/// Cabecera de la revisión (canvas `BancaRevisar`): fecha y cuenta, importe grande y la descripción del banco.
struct BankReviewHeader: View {
    let transaction: BankTransaction
    let accountName: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: [transaction.date.shortDate, accountName].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(Palette.ink2)
            Text(verbatim: transaction.signedAmount).font(.amount(34)).foregroundStyle(transaction.amountColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(transaction.details).font(.footnote.monospaced()).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Formulario de revisión: Categorizar o Emparejar (canvas `BancaRevisar`; «Dividir» necesita una API de varias
/// líneas que aún no hay), la sugerencia, la regla automática y «Excluir transacción». El ✓ de la barra registra.
struct BankReviewForm: View {
    let transaction: BankTransaction
    let position: String
    /// Se llama con el movimiento ya registrado (para pasar al siguiente).
    let onDone: (BankTransaction) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case categorize = "Categorizar", match = "Emparejar"
        var id: String { rawValue }
    }

    /// Una opción de «Emparejar»: algo registrado (línea del diario), o una factura o factura de proveedor abierta.
    enum MatchOption: Identifiable, Equatable {
        case line(BankMatchCandidate)
        case invoice(Invoice)
        case bill(Bill)

        var id: UUID {
            switch self {
            case .line(let candidate): candidate.id
            case .invoice(let invoice): invoice.id
            case .bill(let bill): bill.id
            }
        }

        static func == (lhs: MatchOption, rhs: MatchOption) -> Bool { lhs.id == rhs.id }
    }

    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Vendor.name) private var vendors: [Vendor]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "categorized" }) private var history: [BankTransaction]
    @State private var mode: Mode = .categorize
    @State private var categoryID: UUID?
    @State private var payee = ""
    @State private var matchID: UUID?
    @State private var createsRule = false
    @State private var ruleText = ""
    @State private var errorMessage: String?
    @State private var confirmingIgnore = false
    @State private var closedPeriodRetry: ClosedPeriodRetry?
    @State private var loaded = false

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var inbox: BankInboxContext { BankInboxContext(books: books, accounts: accounts, invoices: invoices, bills: bills) }
    private var bankAccount: Account? { accounts.first { $0.id == transaction.accountID } }
    private var groups: [BankCategoryOptions.Group] {
        BankCategoryOptions.groups(for: transaction.amount, bankAccountID: transaction.accountID, accounts: accounts)
    }
    private var category: Account? { accounts.first { $0.id == categoryID } }

    /// Lo ya registrado por el mismo importe y las facturas abiertas por ese importe o, si el cliente o el proveedor
    /// sale en la descripción, por más (un cobro o pago parcial). Las demás abiertas no: serían ruido.
    private var matchOptions: [MatchOption] {
        var options = ((try? books.matchCandidates(for: transaction)) ?? []).map(MatchOption.line)
        let text = BankStatementLine.normalized(transaction.details + " " + transaction.payee)
        func named(_ name: String?) -> Bool {
            let words = BankStatementLine.normalized(name ?? "").split(separator: " ").filter { $0.count > 2 }
            return !words.isEmpty && words.allSatisfy { text.contains($0) }
        }
        let amount = abs(transaction.amount)
        if transaction.amount > 0 {
            options += invoices.filter { $0.isOpen && ($0.balanceDue == amount || ($0.balanceDue > amount && named($0.customer?.name))) }
                .sorted { $0.dueDate < $1.dueDate }.map(MatchOption.invoice)
        } else {
            options += bills.filter { $0.isOpen && ($0.balanceDue == amount || ($0.balanceDue > amount && named($0.vendor?.name))) }
                .sorted { $0.dueDate < $1.dueDate }.map(MatchOption.bill)
        }
        return options
    }

    private var canConfirm: Bool {
        mode == .categorize ? categoryID != nil && (!createsRule || !ruleText.trimmingCharacters(in: .whitespaces).isEmpty)
            : matchOptions.contains { $0.id == matchID }
    }

    private var confirmTitle: String {
        guard mode == .match else { return String(localized: "Categorizar y siguiente") }
        guard let option = matchOptions.first(where: { $0.id == matchID }) else { return String(localized: "Emparejar y siguiente") }
        switch option {
        case .line: return String(localized: "Emparejar y siguiente")
        case .invoice: return String(localized: "Registrar cobro y siguiente")
        case .bill: return String(localized: "Registrar pago y siguiente")
        }
    }

    var body: some View {
        Form {
            Section { BankReviewHeader(transaction: transaction, accountName: bankAccount?.maskedName) }
            Section {
                Picker("Acción", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            suggestionSection
            switch mode {
            case .categorize: categorizeSections
            case .match: matchSection
            }
            Section {
                Button("Excluir transacción", role: .destructive) { confirmingIgnore = true }
                    .frame(maxWidth: .infinity, minHeight: Metrics.target)
                    .confirmationDialog("¿Excluir este movimiento?", isPresented: $confirmingIgnore, titleVisibility: .visible) {
                        Button("Excluir", role: .destructive, action: ignore)
                    } message: {
                        Text("No se incluirá en tus libros (un gasto personal, un duplicado, una transferencia que ya registraste). Puedes devolverlo a la bandeja desde «Movimientos del banco».")
                    }
            } footer: {
                Text("\(confirmTitle): al confirmar pasarás al siguiente.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Revisar transacción")
        #if os(macOS)
        .navigationSubtitle(position)
        #else
        .inlineTitle()
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Revisar transacción").font(.headline)
                    Text(position).font(.footnote).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
            }
            #endif
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle, systemImage: "checkmark", action: confirm)
                    .disabled(!canConfirm)
                    .help(confirmTitle)
                    .headerButton()
            }
        }
        .closedPeriodUnlock($closedPeriodRetry) { errorMessage = $0 }
        .onAppear(perform: load)
    }

    // MARK: Secciones

    @ViewBuilder
    private var suggestionSection: some View {
        let suggestion = inbox.suggestion(for: transaction)
        Section {
            HStack(spacing: 12) {
                IconTile(systemImage: suggestion.systemImage, foreground: suggestion.kind == .match ? Palette.green
                         : suggestion.kind == .rule ? Palette.indigo : Palette.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title).foregroundStyle(Palette.ink)
                    Text(suggestion.reason).font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            SectionLabel(text: String(localized: "Sugerencia"))
        }
    }

    @ViewBuilder
    private var categorizeSections: some View {
        let picks = BankCategoryOptions.quickPicks(for: transaction, groups: groups, history: history)
        Section {
            TextField(transaction.amount < 0 ? "Proveedor" : "Pagador", text: $payee, prompt: Text(transaction.details))
                .labeledField(transaction.amount < 0 ? String(localized: "Proveedor") : String(localized: "Pagador"))
        }
        Section {
            ForEach(picks) { account in
                Button { categoryID = account.id } label: {
                    HStack {
                        Text(account.name).foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        if categoryID == account.id {
                            Image(systemName: "checkmark").foregroundStyle(Palette.brand).fontWeight(.semibold).accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: Metrics.target)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(categoryID == account.id ? [.isSelected] : [])
            }
            if let category, !picks.contains(where: { $0.id == category.id }) {
                HStack {
                    Text(category.name).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark").foregroundStyle(Palette.brand).fontWeight(.semibold).accessibilityHidden(true)
                }
                .frame(minHeight: Metrics.target)
                .accessibilityAddTraits(.isSelected)
            }
            NavigationLink {
                BankCategoryPicker(groups: groups, selection: $categoryID)
            } label: {
                Text("Más categorías…").foregroundStyle(Palette.brand)
            }
        } header: {
            SectionLabel(text: String(localized: "Categoría"))
        } footer: {
            if let category { Text(categorizeFootnote(category)) }
        }
        Section {
            Toggle(isOn: $createsRule) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "bolt", foreground: Palette.indigo)
                    Text("Crear regla automática")
                }
            }
            if createsRule {
                TextField("Si la descripción contiene", text: $ruleText)
                    .labeledField(String(localized: "Si la descripción contiene"))
                    .autocorrectionDisabled()
            }
        } footer: {
            if createsRule {
                Text("Si la descripción contiene «\(ruleText)», se propondrá \(category?.name ?? String(localized: "esta categoría")). Las próximas llegarán ya categorizadas: solo tendrás que aceptarlas.")
            }
        }
    }

    private func categorizeFootnote(_ category: Account) -> String {
        if category.subtype.isMoneyAccount { return String(localized: "Se registra como transferencia con \(category.maskedName).") }
        return transaction.amount < 0 ? String(localized: "Se registra como un gasto pagado con \(bankAccount?.maskedName ?? "").")
            : String(localized: "Se registra como un depósito en \(bankAccount?.maskedName ?? "") (ingreso sin factura, aportación o devolución).")
    }

    @ViewBuilder
    private var matchSection: some View {
        let options = matchOptions
        Section {
            if options.isEmpty {
                Text("No hay nada registrado por este importe cerca de esta fecha, ni facturas abiertas que lo cubran.")
                    .foregroundStyle(Palette.ink2)
            }
            ForEach(options) { option in
                Button { matchID = option.id } label: { matchRow(option) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(matchID == option.id ? [.isSelected] : [])
            }
        } header: {
            SectionLabel(text: String(localized: "Posibles coincidencias"))
        } footer: {
            Text("Emparejar enlaza este movimiento con algo que ya registraste, sin duplicarlo. Con una factura abierta se registra su cobro o su pago.")
        }
    }

    private func matchRow(_ option: MatchOption) -> some View {
        let (icon, color, title, subtitle, amount): (String, Color, String, String, Int64) = switch option {
        case .line(let candidate):
            ("doc.plaintext", Palette.orange, candidate.entry.bankTitle,
             "\(candidate.entry.date.dayMonth) · \(candidate.entry.source.title)", abs(candidate.line.debit - candidate.line.credit))
        case .invoice(let invoice):
            ("doc.text", Palette.blue, String(localized: "Factura \(invoice.number) · \(invoice.customer?.name ?? "")"),
             String(localized: "Saldo \(invoice.balanceDue.money) · vence \(invoice.dueDate.dayMonth)"), invoice.balanceDue)
        case .bill(let bill):
            ("doc.text", Palette.blue, String(localized: "Factura por pagar \(bill.bankTitle)"),
             String(localized: "Saldo \(bill.balanceDue.money) · vence \(bill.dueDate.dayMonth)"), bill.balanceDue)
        }
        return HStack(spacing: 12) {
            IconTile(systemImage: icon, foreground: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Palette.ink).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            Text(amount.money).monospacedDigit().foregroundStyle(Palette.ink)
            Image(systemName: "checkmark").fontWeight(.semibold)
                .foregroundStyle(matchID == option.id ? Palette.brand : .clear).accessibilityHidden(true)
        }
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Acciones

    private func load() {
        guard !loaded else { return }
        loaded = true
        payee = transaction.payee.isEmpty ? "" : transaction.payee
        ruleText = BankRuleDraft.matchText(from: transaction.details)
        switch inbox.suggestion(for: transaction) {
        case .match(let candidate): mode = .match; matchID = candidate.id
        case .invoice(let invoice): mode = .match; matchID = invoice.id
        case .bill(let bill): mode = .match; matchID = bill.id
        case .category(let account, _): categoryID = account.id
        case .none:
            if let vendorID = transaction.vendorID, let vendor = vendors.first(where: { $0.id == vendorID }) {
                payee = vendor.name
                categoryID = vendor.defaultExpenseAccountID
            }
        }
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "qa.revisarModo") {
        case "emparejar": mode = .match
        case "categorizar": mode = .categorize
        case "regla": mode = .categorize; createsRule = true
        default: break
        }
        if UserDefaults.standard.bool(forKey: "qa.revisarCategoria"), categoryID == nil {
            categoryID = BankCategoryOptions.quickPicks(for: transaction, groups: groups, history: history).first?.id
        }
        #endif
    }

    private func confirm() {
        SubscriptionStore.shared.whenWritable { perform(with: books) }
    }

    private func perform(with books: Bookkeeper) {
        errorMessage = nil
        do {
            switch mode {
            case .categorize:
                guard let category else { return }
                let name = payee.trimmingCharacters(in: .whitespaces)
                let vendor = transaction.amount < 0 ? BankReview.vendor(named: name, in: vendors) : nil
                try books.categorize(transaction, as: category, vendor: vendor, payee: name.isEmpty ? nil : name)
                if createsRule {
                    let text = ruleText.trimmingCharacters(in: .whitespaces)
                    try books.saveBankRule(BankRuleDraft.input(for: transaction, matchText: text, target: category, vendor: vendor, payee: name))
                }
            case .match:
                switch matchOptions.first(where: { $0.id == matchID }) {
                case .line(let candidate): try books.match(transaction, to: candidate.line)
                case .invoice(let invoice): try books.recordPayment(from: transaction, for: invoice)
                case .bill(let bill): try books.payBill(from: transaction, bill: bill)
                case nil: return
                }
            }
            onDone(transaction)
        } catch {
            if let lockDate = PeriodClosing.lockDate(of: error) {
                closedPeriodRetry = ClosedPeriodRetry(lockDate: lockDate) { unlocked in perform(with: unlocked) }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ignore() {
        SubscriptionStore.shared.whenWritable {
            do {
                try books.ignore(transaction)
                onDone(transaction)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// «Más categorías…»: todas las cuentas que sirven para este movimiento, por grupos, con búsqueda.
struct BankCategoryPicker: View {
    let groups: [BankCategoryOptions.Group]
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            ForEach(groups) { group in
                let shown = group.accounts.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
                if !shown.isEmpty {
                    Section(heading: group.title) {
                        ForEach(shown) { account in
                            Button { selection = account.id; dismiss() } label: {
                                HStack {
                                    Text(account.displayName).foregroundStyle(Palette.ink)
                                    Spacer(minLength: 8)
                                    if selection == account.id { Image(systemName: "checkmark").foregroundStyle(Palette.brand).accessibilityHidden(true) }
                                }
                                .frame(minHeight: Metrics.target)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == account.id ? [.isSelected] : [])
                        }
                    }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .searchable(text: $query, prompt: Text("Buscar categoría"))
        .navigationTitle("Categoría")
        .inlineTitle()
    }
}

// MARK: - iPad: columna maestro

/// Columna «Por revisar» del iPad (canvas `iPadBanca`): título, «N de M · cuenta», buscador, cuentas en segmentado y
/// las filas; lo elegido se revisa en el detalle.
struct BankInboxMasterList: View {
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var modelContext
    @CompanyQuery(sort: [SortDescriptor(\BankTransaction.date, order: .reverse), SortDescriptor(\BankTransaction.importedAt)])
    private var transactions: [BankTransaction]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @State private var focus = BankInboxFocus.shared
    @State private var filter: BankInboxFilter = .pending
    @State private var accountID: UUID?
    @State private var query = ""
    @State private var importing = false
    @State private var errorMessage: String?

    private var bankAccounts: [Account] { accounts.filter { ($0.subtype == .bank || $0.subtype == .creditCard) && !$0.isArchived } }

    var body: some View {
        let context = BankInboxContext(books: Bookkeeper(context: modelContext), accounts: accounts, invoices: invoices, bills: bills)
        let inAccount = transactions.filter { accountID == nil || $0.accountID == accountID }
        let shown = inAccount.filter { filter.matches($0) && BankInboxSearch.matches($0, query) }
        // La cuenta corta («••4821»), como el segmentado: el nombre completo cortaba la propuesta.
        let names = Dictionary(accounts.map { ($0.id, $0.last4.isEmpty ? $0.name : "••\($0.last4)") }, uniquingKeysWith: { first, _ in first })
        List(selection: $selection) {
            ForEach(shown) { transaction in
                BankTransactionRow(transaction: transaction, suggestion: context.suggestion(for: transaction),
                                   accountName: accountID == nil ? names[transaction.accountID ?? UUID()] : nil)
                    .masterRow(transaction.id, selection: selection)
                    .contextMenu {
                        if transaction.isPending {
                            let suggestion = context.suggestion(for: transaction)
                            if suggestion.isActionable {
                                Button(suggestion.acceptTitle, systemImage: "checkmark.circle") {
                                    act { try BankReview.accept(suggestion, for: transaction, books: context.books) }
                                }
                            }
                            Button("Excluir", systemImage: "nosign", role: .destructive) { act { try context.books.ignore(transaction) } }
                        } else {
                            Button("Devolver a la bandeja", systemImage: "tray.and.arrow.up") { act { try context.books.returnToInbox(transaction) } }
                        }
                    }
            }
            if shown.isEmpty {
                Text(filter == .pending ? String(localized: "No hay movimientos por revisar.") : String(localized: "Nada por aquí todavía."))
                    .font(.subheadline).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden).listRowBackground(Palette.masterColumn)
            }
        }
        .masterList(String(localized: "Por revisar"), query: $query, prompt: "Descripción o monto")
        .masterFilter {
            VStack(spacing: 6) {
                Text(verbatim: subtitle(pending: inAccount.filter(\.isPending).count, total: inAccount.count))
                    .font(.footnote).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity, alignment: .leading)
                if bankAccounts.count > 1 {
                    Picker("Cuenta", selection: $accountID) {
                        Text("Todas").tag(UUID?.none)
                        ForEach(bankAccounts) { Text(verbatim: $0.last4.isEmpty ? $0.name : "••\($0.last4)").tag(Optional($0.id)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                FilterPicker(title: String(localized: "Filtrar"), options: BankInboxFilter.allCases, selection: $filter, label: \.localizedTitle)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Importar extracto…", systemImage: "square.and.arrow.down") { importing = true }
                    if shown.contains(where: { context.suggestion(for: $0).isActionable }) {
                        Button("Aceptar sugeridas", systemImage: "checkmark.circle") {
                            SubscriptionStore.shared.whenWritable {
                                let result = BankReview.acceptAll(shown, context: context)
                                if let error = result.error { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                } label: {
                    Label("Más opciones", systemImage: "ellipsis")
                }
                .headerButton()
            }
        }
        .sheet(isPresented: $importing) { NavigationStack { BankImportView(preferredAccountID: accountID) }.editorSheetSizing() }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .onChange(of: focus.requested) { _, id in
            guard let id else { return }
            selection = id
            focus.requested = nil
        }
        #if DEBUG
        .task {
            if let file = QABanking.importFile { importing = true; QABanking.pendingImport = file }
            guard UserDefaults.standard.object(forKey: "qa.fila") != nil, selection == nil else { return }
            let index = UserDefaults.standard.integer(forKey: "qa.fila")
            if shown.indices.contains(index) { selection = shown[index].id }
        }
        #endif
    }

    private func subtitle(pending: Int, total: Int) -> String {
        let account = bankAccounts.first { $0.id == accountID }?.maskedName ?? String(localized: "todas las cuentas")
        return String(localized: "\(pending) de \(total) · \(account)")
    }

    private func act(_ body: () throws -> Void) {
        SubscriptionStore.shared.whenWritable {
            do { try body() } catch { errorMessage = error.localizedDescription }
        }
    }
}

/// Detalle sin nada elegido: «Todo revisado» o «Elige un movimiento».
struct BankInboxPlaceholder: View {
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" }) private var pending: [BankTransaction]
    @State private var importing = false

    var body: some View {
        Group {
            if pending.isEmpty {
                EmptyStateView(systemImage: "checkmark.circle", title: String(localized: "Todo revisado"),
                               message: String(localized: "Importa el extracto de tu banco (CSV u OFX) y aquí verás cada movimiento para registrarlo con un toque."),
                               actionTitle: String(localized: "Importar extracto")) { importing = true }
            } else {
                EmptyStateView(systemImage: "tray", title: String(localized: "Elige un movimiento"),
                               message: String(localized: "\(pending.count) movimientos esperan: acepta lo que propone la app o elige otra categoría."))
            }
        }
        .sheet(isPresented: $importing) { NavigationStack { BankImportView() }.editorSheetSizing() }
    }
}

// MARK: - Accesos desde Cuentas (iPad) e Inicio

/// «Bandeja» de la columna de cuentas del iPad (canvas `iPadBancaCuentas`): Por revisar N, Conciliar, Reglas e
/// Importar. Cambian la barra lateral (`SectionLink`).
struct BankingShortcutsSection: View {
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" }) private var pending: [BankTransaction]
    @CompanyQuery(filter: #Predicate<BankRule> { $0.isActive }) private var rules: [BankRule]
    @State private var importing = false

    var body: some View {
        Section {
            SectionLink(item: .banking(.inbox)) { BankInboxScreen() } label: {
                shortcut("Por revisar", systemImage: "tray", color: Palette.orange, value: "\(pending.count)")
            }
            SectionLink(item: .banking(.reconcile)) { ReconciliationHubView() } label: {
                shortcut("Conciliar", systemImage: "checklist", color: Palette.teal, value: nil)
            }
            SectionLink(item: .banking(.rules)) { BankRulesView() } label: {
                shortcut("Reglas", systemImage: "bolt", color: Palette.purple, value: String(localized: "\(rules.count) activas"))
            }
            Button { importing = true } label: {
                shortcut("Importar extracto", systemImage: "square.and.arrow.down", color: Palette.blue, value: nil)
            }
        } header: {
            Text("Bandeja").font(.footnote).foregroundStyle(Palette.ink2).textCase(nil)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .listRowBackground(Palette.masterColumn)
        .sheet(isPresented: $importing) { NavigationStack { BankImportView() }.editorSheetSizing() }
    }

    private func shortcut(_ title: LocalizedStringKey, systemImage: String, color: Color, value: String?) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, foreground: color)
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value { Text(verbatim: value).foregroundStyle(Palette.ink2).monospacedDigit() }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron).accessibilityHidden(true)
        }
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Enlace de «Cuentas» en Inicio (canvas `MacInicio`: «Revisar 12»): con movimientos por revisar lleva a la bandeja;
/// si no, a Banca, como antes.
struct BankingHomeLink: View {
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" }) private var pending: [BankTransaction]

    var body: some View {
        Group {
            if pending.isEmpty {
                SectionLink(item: .section(.banking)) { BankingView() } label: { Text("Banca") }
            } else {
                SectionLink(item: .banking(.inbox)) { BankingView() } label: { Text("Revisar \(pending.count)") }
                    .accessibilityLabel(Text("Revisar \(pending.count) movimientos del banco"))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
    }
}
