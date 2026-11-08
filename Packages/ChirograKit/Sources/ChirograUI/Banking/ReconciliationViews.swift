import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Conciliación bancaria (DISEÑO §4.6, canvas `Conciliacion`): se empieza con la fecha y el saldo final del extracto,
// se marcan las partidas que salen en él (de entrada, las emparejadas con el banco: `suggestedClearedLines`) hasta que
// la diferencia es $0.00 y entonces se termina. Historial con «Reabrir» en la última y «Cancelar» en la abierta.
// iPhone e iPad: lista con círculos para marcar; Mac: tabla con casillas y un inspector con el resumen.

// MARK: - Datos de pantalla

/// Partida que se puede marcar: una línea del diario de la cuenta.
nonisolated struct ReconciliationItem: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    /// Efecto en la cuenta como debe − haber (en un banco, + depósito; en una tarjeta, + pago).
    let amount: Int64
    let isCleared: Bool
    let order: Int
    var withdrawal: Int64 { amount < 0 ? -amount : 0 }
    var deposit: Int64 { amount > 0 ? amount : 0 }
    /// Para ordenar la columna de la casilla.
    var clearedRank: Int { isCleared ? 1 : 0 }
}

/// Todo lo que pinta una sesión abierta (se calcula en cada dibujo con `Bookkeeper`).
struct ReconciliationSnapshot {
    let reconciliation: Reconciliation
    let items: [ReconciliationItem]
    let lines: [UUID: JournalLine]
    let summary: ReconciliationSummary
    /// Las emparejadas con el banco que aún no están marcadas.
    let suggested: [JournalLine]

    init?(_ reconciliation: Reconciliation, books: Bookkeeper) {
        guard let lines = try? books.reconciliationLines(reconciliation),
              let summary = try? books.summary(of: reconciliation) else { return nil }
        self.reconciliation = reconciliation
        self.summary = summary
        self.lines = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items = lines.enumerated().map { index, line in
            ReconciliationItem(id: line.id, date: line.entry?.date ?? .now, title: line.entry?.bankTitle ?? "",
                               amount: line.debit - line.credit, isCleared: line.reconciliationID == reconciliation.id, order: index)
        }
        suggested = (try? books.suggestedClearedLines(reconciliation)) ?? []
    }

    var clearedText: String { String(localized: "\(summary.clearedCount) de \(items.count)") }
}

extension Account {
    /// «Saldo final del extracto» o, en una tarjeta, lo que se debe según el extracto.
    var statementBalanceTitle: String {
        subtype == .creditCard ? String(localized: "Saldo que debes según el extracto") : String(localized: "Saldo final del extracto")
    }
}

enum ReconciliationText {
    static func status(of account: Account, reconciliations: [Reconciliation]) -> (text: String, color: Color) {
        let own = reconciliations.filter { $0.accountID == account.id }
        if let open = own.first(where: { !$0.isCompleted }) {
            return (String(localized: "En curso · extracto al \(open.statementDate.dayMonth)"), Palette.warning)
        }
        if let last = own.filter(\.isCompleted).max(by: { $0.statementDate < $1.statementDate }) {
            return (String(localized: "Conciliada al \(last.statementDate.dayMonth)"), Palette.positive)
        }
        return (String(localized: "Sin conciliar"), Palette.ink2)
    }
}

// MARK: - Cuentas para conciliar

/// «Conciliar» de Banca: las cuentas de banco y tarjeta con su estado; cada una abre su conciliación. En el iPad y el
/// iPhone, una lista; en el Mac, una tabla con el historial en el inspector.
struct ReconciliationHubView: View {
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Reconciliation.statementDate, order: .reverse) private var reconciliations: [Reconciliation]
    /// La cuenta abierta (en el Mac, desde la tabla; en iOS, solo con `-qa.conciliar`).
    @State private var opened: Account?
    #if os(macOS)
    @State private var selection: UUID?
    @State private var query = ""
    #endif

    private var shown: [Account] {
        accounts.filter { ($0.subtype == .bank || $0.subtype == .creditCard) && !$0.isArchived }
    }

    var body: some View {
        content
            #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1))
                if let index = QABanking.reconcileIndex, shown.indices.contains(index) { opened = shown[index] }
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macBody
        #else
        List {
            Section {
                if shown.isEmpty {
                    Text("Añade una cuenta de banco o tarjeta para conciliarla.").foregroundStyle(Palette.ink2)
                }
                ForEach(shown) { account in
                    let status = ReconciliationText.status(of: account, reconciliations: reconciliations)
                    NavigationLink { ReconciliationView(account: account) } label: {
                        LedgerRow(title: account.maskedName, subtitle: status.text, titleLines: 2) {
                            IconTile(systemImage: account.bankSymbol, foreground: account.bankColor)
                        } trailing: { EmptyView() }
                    }
                }
            } header: {
                SectionLabel(text: String(localized: "Cuentas"))
            } footer: {
                Text("Compara tus libros con el extracto del banco: marca lo que aparece en él hasta que la diferencia sea $0.00.")
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Conciliar")
        .headerTitle()
        .navigationDestination(item: $opened) { ReconciliationView(account: $0) }
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        let rows = shown.filter { query.isEmpty || $0.maskedName.localizedStandardContains(query) }
            .map { ReconcileAccountRow(account: $0, reconciliations: reconciliations) }
        return MacTablePage(
            title: String(localized: "Conciliación"), subtitle: String(localized: "Banca · \(shown.count) cuentas"),
            rows: rows, footer: String(localized: "\(rows.count) cuentas"), query: $query, searchPrompt: Text("Cuenta"),
            selection: $selection, sortOrder: [KeyPathComparator(\ReconcileAccountRow.name)],
            addTitle: String(localized: "Conciliar"), onAdd: { opened = rows.first { $0.id == selection }?.account ?? rows.first?.account },
            onOpen: { opened = $0.account },
            empty: MacTableEmpty(systemImage: "checklist", title: String(localized: "Sin cuentas de banco"),
                                 message: String(localized: "Añade una cuenta de banco o tarjeta para conciliarla.")),
            inspectorTitle: { $0?.name ?? String(localized: "Cuenta") },
            inspectorPlaceholder: String(localized: "Selecciona una cuenta para ver sus conciliaciones.")
        ) {
            TableColumn("Cuenta", value: \.name) { Text($0.name) }.width(min: 140, ideal: 200)
            TableColumn("Estado", value: \.statusText) { row in MacCellText(text: row.statusText, color: row.statusColor) }
                .width(min: 120, ideal: 180)
            TableColumn("Última conciliación", value: \.lastDateSort) { row in MacCellText(text: row.lastText) }
                .width(min: 100, ideal: 140)
        } filter: {
            EmptyView()
        } inspector: { row in
            ReconciliationHistory(account: row.account, reconciliations: reconciliations.filter { $0.accountID == row.id })
        } actions: { row in
            Button(row.hasOpen ? "Seguir conciliando" : "Conciliar…") { opened = row.account }.buttonStyle(.primary)
        }
        .navigationDestination(item: $opened) { ReconciliationView(account: $0) }
    }
    #endif
}

#if os(macOS)
nonisolated struct ReconcileAccountRow: Identifiable {
    let account: Account
    let id: UUID
    let name: String
    let statusText: String
    let statusColor: Color
    let lastText: String
    let lastDateSort: Date
    let hasOpen: Bool

    @MainActor
    init(account: Account, reconciliations: [Reconciliation]) {
        self.account = account
        id = account.id
        name = account.maskedName
        let status = ReconciliationText.status(of: account, reconciliations: reconciliations)
        statusText = status.text
        statusColor = status.color
        let last = reconciliations.filter { $0.accountID == account.id && $0.isCompleted }.max { $0.statementDate < $1.statementDate }
        lastText = last?.statementDate.shortDate ?? "—"
        lastDateSort = last?.statementDate ?? .distantPast
        hasOpen = reconciliations.contains { $0.accountID == account.id && !$0.isCompleted }
    }
}
#endif

// MARK: - Conciliación de una cuenta

/// La conciliación de una cuenta: el formulario para empezar (sin una abierta) o la sesión abierta, y el historial.
struct ReconciliationView: View {
    let account: Account
    /// Propuestos al llegar desde una importación OFX (saldo del extracto, en el lado normal de la cuenta).
    var proposedDate: Date? = nil
    var proposedBalance: Int64? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @CompanyQuery(sort: \Reconciliation.statementDate, order: .reverse) private var allReconciliations: [Reconciliation]
    /// Para redibujar al marcar (las líneas cambian `reconciliationID`).
    @CompanyQuery private var journalLines: [JournalLine]
    @State private var statementDate = Date.now
    @State private var endingBalance: Int64 = 0
    @State private var beginningBalance: Int64 = 0
    @State private var errorMessage: String?
    @State private var confirmingCancel = false
    @State private var reopening: Reconciliation?
    @State private var finished: Reconciliation?
    @State private var prepared = false

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var reconciliations: [Reconciliation] { allReconciliations.filter { $0.accountID == account.id } }
    private var open: Reconciliation? { reconciliations.first { !$0.isCompleted } }
    private var lastCompleted: Reconciliation? { reconciliations.first(where: \.isCompleted) }

    var body: some View {
        _ = journalLines.count
        return Group {
            if let open, let snapshot = ReconciliationSnapshot(open, books: books) {
                session(snapshot)
            } else {
                startForm
            }
        }
        .navigationTitle(account.maskedName)
        #if os(macOS)
        .navigationSubtitle(String(localized: "Conciliación"))
        #else
        .inlineTitle()
        #endif
        .onAppear(perform: prepare)
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("¿Cancelar la conciliación?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancelar conciliación", role: .destructive) { run { try books.cancelReconciliation($0) } }
            Button("Seguir conciliando", role: .cancel) {}
        } message: {
            Text("Se desmarcan sus partidas y se borra. Tus asientos no cambian.")
        }
        .confirmationDialog("¿Reabrir la conciliación?", isPresented: Binding(get: { reopening != nil }, set: { if !$0 { reopening = nil } }),
                            titleVisibility: .visible, presenting: reopening) { reconciliation in
            Button("Reabrir") { act { try books.reopenReconciliation(reconciliation) } }
            Button("No", role: .cancel) {}
        } message: { _ in
            Text("Sus partidas siguen marcadas. Podrás corregirla y terminarla otra vez.")
        }
        .alert("Conciliación terminada", isPresented: Binding(get: { finished != nil }, set: { if !$0 { finished = nil } }), presenting: finished) { _ in
            Button("Aceptar", role: .cancel) {}
        } message: { reconciliation in
            Text("Tus libros cuadran con el extracto al \(reconciliation.statementDate.shortDate). Lo conciliado queda marcado y la app avisará si algo lo cambia.")
        }
        #if DEBUG
        .task { await qaRun() }
        #endif
    }

    #if DEBUG
    /// `-qa.conciliarEmpezar 1` empieza con la fecha y el saldo de `-qa.conciliarFecha`/`-qa.conciliarSaldo`;
    /// `-qa.conciliarMarcar todas` marca todas las partidas (`-qa.conciliarCuadrar 1` pone el saldo del extracto igual al
    /// conciliado); `-qa.conciliarTerminar 1` la termina (si cuadra).
    private func qaRun() async {
        let defaults = UserDefaults.standard
        try? await Task.sleep(for: .seconds(1))
        if open == nil, defaults.bool(forKey: "qa.conciliarEmpezar") { start() }
        try? await Task.sleep(for: .seconds(0.6))
        if let open, defaults.string(forKey: "qa.conciliarMarcar") == "todas", let snapshot = ReconciliationSnapshot(open, books: books) {
            toggle(snapshot.items.filter { !$0.isCleared }.map(\.id), true, snapshot)
            // `-qa.conciliarCuadrar 1`: el saldo del extracto pasa a ser el conciliado (diferencia 0).
            if defaults.bool(forKey: "qa.conciliarCuadrar"), let summary = try? books.summary(of: open) {
                update(nil, summary.clearedBalance)
            }
        }
        try? await Task.sleep(for: .seconds(0.6))
        if defaults.bool(forKey: "qa.conciliarTerminar") { finish() }
    }
    #endif

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let lastMonthEnd = PeriodClosing.endOfMonth(Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now)
        let afterLast = lastCompleted.map { Self.nextStatementDate(after: $0.statementDate) }
        statementDate = proposedDate ?? afterLast.map { max($0, lastMonthEnd) } ?? lastMonthEnd
        endingBalance = proposedBalance ?? 0
        beginningBalance = 0
        #if DEBUG
        if let balance = QABanking.statementBalance { endingBalance = balance }
        if let date = QABanking.statementDate { statementDate = date }
        #endif
    }

    /// Fin del mes siguiente al de `date` (extractos mensuales).
    static func nextStatementDate(after date: Date, calendar: Calendar = .current) -> Date {
        PeriodClosing.endOfMonth(calendar.date(byAdding: .month, value: 1, to: date) ?? date, calendar: calendar)
    }

    // MARK: Empezar

    private var startForm: some View {
        Form {
            Section {
                DatePicker("Fecha del extracto", selection: $statementDate, displayedComponents: .date)
                MoneyField(title: account.statementBalanceTitle, minorUnits: $endingBalance)
                    .labeledField(account.statementBalanceTitle)
                if let lastCompleted {
                    LabeledContent("Saldo inicial", value: lastCompleted.statementEndingBalance.money)
                } else {
                    MoneyField(title: String(localized: "Saldo inicial del extracto"), minorUnits: $beginningBalance)
                        .labeledField(String(localized: "Saldo inicial del extracto"))
                }
            } header: {
                SectionLabel(text: String(localized: "Extracto"))
            } footer: {
                if lastCompleted == nil {
                    Text("Es tu primera conciliación de esta cuenta: pon el saldo con que empieza el extracto (o $0.00 y marca también el asiento de saldos iniciales).")
                } else {
                    Text("El saldo inicial es el final de la conciliación anterior.")
                }
            }
            Section {
                Button("Empezar conciliación", action: start)
                    .buttonStyle(.primary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            historySection
        }
        .formStyle(.grouped)
        .screenBackground()
        .keyboardDoneButton()
    }

    private func start() {
        SubscriptionStore.shared.whenWritable {
            act {
                let reconciliation = try books.startReconciliation(for: account, statementDate: statementDate, endingBalance: endingBalance,
                                                                   beginningBalance: lastCompleted == nil ? beginningBalance : nil)
                // De entrada, marcadas las que ya emparejaste con el banco (canvas: «Marcar sugeridas»).
                let suggested = try books.suggestedClearedLines(reconciliation)
                if !suggested.isEmpty { try books.setCleared(suggested, true, in: reconciliation) }
            }
        }
    }

    private func finish() {
        guard let open else { return }
        act {
            try books.completeReconciliation(open)
            finished = open
            // La próxima, al fin del mes siguiente.
            statementDate = Self.nextStatementDate(after: open.statementDate)
            endingBalance = 0
        }
    }

    // MARK: Sesión

    @ViewBuilder
    private func session(_ snapshot: ReconciliationSnapshot) -> some View {
        #if os(macOS)
        ReconciliationMacSession(account: account, snapshot: snapshot, finish: finish, cancel: { confirmingCancel = true },
                                 toggle: toggle, update: update)
        #else
        List {
            Section {
                differenceCard(snapshot.summary)
            }
            Section {
                LabeledContent("Saldo inicial", value: snapshot.summary.beginningBalance.money)
                StatementFields(reconciliation: snapshot.reconciliation, account: account, update: update)
                LabeledContent("Saldo conciliado", value: snapshot.summary.clearedBalance.money)
                LabeledContent("Partidas marcadas", value: snapshot.clearedText)
            } header: {
                SectionLabel(text: String(localized: "\(account.maskedName) · extracto al \(snapshot.reconciliation.statementDate.dayMonth)"))
            }
            Section {
                if snapshot.items.isEmpty {
                    Text("No hay movimientos de esta cuenta hasta la fecha del extracto.").foregroundStyle(Palette.ink2)
                }
                ForEach(snapshot.items) { item in
                    Button { toggle([item.id], !item.isCleared, snapshot) } label: { ReconciliationRowView(item: item) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(item.isCleared ? [.isSelected] : [])
                        .accessibilityHint(Text(item.isCleared ? "Toca para desmarcar" : "Toca para marcar"))
                }
            } header: {
                HStack {
                    Text("Movimientos hasta el \(snapshot.reconciliation.statementDate.dayMonth)").font(.cardTitle).foregroundStyle(Palette.ink)
                        .textCase(nil).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    markAllButton(snapshot)
                }
            } footer: {
                if !snapshot.suggested.isEmpty {
                    Button("Marcar las \(snapshot.suggested.count) emparejadas con el banco") { toggle(snapshot.suggested.map(\.id), true, snapshot) }
                        .font(.footnote).tint(Palette.brand)
                }
            }
            Section {
                Button("Cancelar conciliación", role: .destructive) { confirmingCancel = true }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Tus marcas se guardan al momento: puedes salir y seguir después.")
            }
        }
        .groupedList()
        .screenBackground()
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { dismiss() }.headerButton()
            }
        }
        #endif
    }

    #if os(iOS)
    private func differenceCard(_ summary: ReconciliationSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.isBalanced ? String(localized: "Cuadra · diferencia") : String(localized: "Diferencia"))
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                Text(summary.difference.money).font(.amount(36)).foregroundStyle(summary.isBalanced ? Palette.positive : Palette.negative)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    StatusDot(color: summary.isBalanced ? Palette.green : Palette.red)
                    Text(summary.isBalanced ? String(localized: "Coincide con el extracto") : String(localized: "Marca las partidas que aparecen en el extracto"))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            Button(summary.isBalanced ? String(localized: "Terminar conciliación") : String(localized: "Marca partidas hasta llegar a $0.00"), action: finish)
                .buttonStyle(.primary)
                .disabled(!summary.isBalanced)
        }
        .padding(.vertical, 6)
    }

    private func markAllButton(_ snapshot: ReconciliationSnapshot) -> some View {
        let allOn = !snapshot.items.isEmpty && snapshot.items.allSatisfy(\.isCleared)
        return Button(allOn ? "Desmarcar todas" : "Marcar todas") {
            toggle(snapshot.items.map(\.id), !allOn, snapshot)
        }
        .font(.body).textCase(nil).tint(Palette.brand)
        .disabled(snapshot.items.isEmpty)
    }
    #endif

    private func toggle(_ ids: [UUID], _ cleared: Bool, _ snapshot: ReconciliationSnapshot) {
        let lines = ids.compactMap { snapshot.lines[$0] }
        SubscriptionStore.shared.whenWritable {
            act { try books.setCleared(lines, cleared, in: snapshot.reconciliation) }
        }
    }

    private func update(_ date: Date?, _ balance: Int64?) {
        guard let open else { return }
        act { try books.updateReconciliation(open, statementDate: date, endingBalance: balance) }
    }

    // MARK: Historial

    @ViewBuilder
    private var historySection: some View {
        let completed = reconciliations.filter(\.isCompleted)
        if !completed.isEmpty {
            Section {
                ForEach(completed) { reconciliation in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Al \(reconciliation.statementDate.shortDate)").foregroundStyle(Palette.ink)
                            Text("Saldo \(reconciliation.statementEndingBalance.money) · terminada el \((reconciliation.closedAt ?? reconciliation.createdAt).shortDate)")
                                .font(.footnote).foregroundStyle(Palette.ink2)
                        }
                        Spacer(minLength: 8)
                        if reconciliation.id == lastCompleted?.id, open == nil {
                            Button("Reabrir") { reopening = reconciliation }.buttonStyle(.borderless).tint(Palette.brand)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                SectionLabel(text: String(localized: "Conciliaciones anteriores"))
            } footer: {
                Text("Solo se reabre la última. Lo conciliado no se cambia sin aviso.")
            }
        }
    }

    // MARK: Acciones

    private func run(_ body: (Reconciliation) throws -> Void) {
        guard let open else { return }
        act { try body(open) }
    }

    private func act(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
    }
}

/// Fecha y saldo final del extracto, editables mientras la conciliación está abierta.
private struct StatementFields: View {
    let reconciliation: Reconciliation
    let account: Account
    let update: (Date?, Int64?) -> Void
    @State private var date = Date.now
    @State private var balance: Int64 = 0
    @State private var loaded = false

    var body: some View {
        Group {
            DatePicker("Fecha del extracto", selection: $date, displayedComponents: .date)
            MoneyField(title: account.statementBalanceTitle, minorUnits: $balance)
                .labeledField(account.statementBalanceTitle)
        }
        .onAppear {
            guard !loaded else { return }
            date = reconciliation.statementDate
            balance = reconciliation.statementEndingBalance
            loaded = true
        }
        .onChange(of: date) { _, new in if loaded, !Calendar.current.isDate(new, inSameDayAs: reconciliation.statementDate) { update(new, nil) } }
        .onChange(of: balance) { _, new in if loaded, new != reconciliation.statementEndingBalance { update(nil, new) } }
        // Si cambia por otro lado (otro aparato, QA), el campo lo sigue.
        .onChange(of: reconciliation.statementEndingBalance) { _, new in if balance != new { balance = new } }
    }
}

/// Fila de una partida: círculo para marcar, descripción y fecha, importe (verde si entra).
private struct ReconciliationRowView: View {
    let item: ReconciliationItem

    var body: some View {
        HStack(spacing: 12) {
            SelectionMark(isOn: item.isCleared)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).foregroundStyle(Palette.ink).lineLimit(1)
                Text(item.date.dayMonth).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            Text(verbatim: item.amount > 0 ? "+\(item.amount.money)" : "−\((-item.amount).money)")
                .monospacedDigit().foregroundStyle(item.amount > 0 ? Palette.positive : Palette.ink)
        }
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.title), \(item.date.shortDate), \(item.amount > 0 ? "+" : "−")\(abs(item.amount).money)"))
    }
}

/// Historial de una cuenta (inspector del Mac): conciliaciones terminadas y la abierta.
private struct ReconciliationHistory: View {
    let account: Account
    let reconciliations: [Reconciliation]

    var body: some View {
        let status = ReconciliationText.status(of: account, reconciliations: reconciliations)
        VStack(alignment: .leading, spacing: 2) {
            Text(account.maskedName).font(.body.weight(.semibold))
            HStack(spacing: 6) { StatusDot(color: status.color); Text(status.text).foregroundStyle(status.color) }.font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        MacInspectorSectionIfAvailable(title: String(localized: "Conciliaciones")) {
            if reconciliations.isEmpty {
                Text("Todavía no has conciliado esta cuenta.").foregroundStyle(Palette.ink2)
            }
            ForEach(reconciliations) { reconciliation in
                HStack {
                    Text(reconciliation.statementDate.shortDate)
                    Spacer(minLength: 8)
                    Text(reconciliation.isCompleted ? reconciliation.statementEndingBalance.money : String(localized: "En curso"))
                        .foregroundStyle(reconciliation.isCompleted ? Palette.ink : Palette.warning)
                }
                .monospacedDigit()
                .frame(minHeight: 26)
            }
        }
    }
}

/// `MacInspectorSection` solo existe en el Mac; en iOS, una sección simple.
private struct MacInspectorSectionIfAvailable<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        MacInspectorSection(title: title) { content }
        #else
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: title)
            content
        }
        #endif
    }
}

// MARK: - Mac

#if os(macOS)
/// Sesión en el Mac: cajas de cifras, tabla de partidas con casilla y el inspector con la diferencia, el extracto y
/// los botones (Terminar con diferencia 0, Marcar todas, Cancelar).
private struct ReconciliationMacSession: View {
    let account: Account
    let snapshot: ReconciliationSnapshot
    let finish: () -> Void
    let cancel: () -> Void
    let toggle: ([UUID], Bool, ReconciliationSnapshot) -> Void
    let update: (Date?, Int64?) -> Void
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\ReconciliationItem.order)]
    @AppStorage("macInspectorShown") private var showsInspector = true

    var body: some View {
        let summary = snapshot.summary
        let rows = snapshot.items.sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 12) {
            KPIGrid(items: [
                KPIItem(title: String(localized: "Saldo inicial"), value: summary.beginningBalance.money),
                KPIItem(title: account.statementBalanceTitle, value: summary.statementEndingBalance.money),
                KPIItem(title: String(localized: "Saldo conciliado"), value: summary.clearedBalance.money, foot: snapshot.clearedText),
                KPIItem(title: summary.isBalanced ? String(localized: "Cuadra · diferencia") : String(localized: "Diferencia"),
                        value: summary.difference.money,
                        foot: summary.isBalanced ? String(localized: "Coincide con el extracto") : String(localized: "Marca lo que sale en el extracto"),
                        footColor: summary.isBalanced ? Palette.positive : Palette.negative),
            ])
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("✓", value: \.clearedRank) { item in
                    Toggle("Marcada", isOn: Binding(get: { item.isCleared }, set: { toggle([item.id], $0, snapshot) }))
                        .toggleStyle(.checkbox).labelsHidden()
                        .accessibilityLabel(Text(verbatim: item.title))
                }
                .width(28)
                TableColumn("Fecha", value: \.order) { MacCellText(text: $0.date.dayMonth) }.width(min: 50, ideal: 60, max: 90)
                TableColumn("Descripción", value: \.title) { Text($0.title).lineLimit(1) }.width(min: 140, ideal: 240)
                TableColumn("Retiro", value: \.withdrawal) { Text($0.withdrawal > 0 ? $0.withdrawal.money : "").monospacedDigit() }
                    .width(min: 70, ideal: 90, max: 130).alignment(.trailing)
                TableColumn("Depósito", value: \.deposit) { item in
                    MacCellText(text: item.deposit > 0 ? item.deposit.money : "", color: Palette.positive).monospacedDigit()
                }
                .width(min: 70, ideal: 90, max: 130).alignment(.trailing)
            }
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.tableRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.tableRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("Sin movimientos", systemImage: "checklist",
                                           description: Text("No hay movimientos de esta cuenta hasta la fecha del extracto."))
                }
            }
            Text("\(snapshot.clearedText) partidas marcadas · se guardan al momento").font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .inspector(isPresented: $showsInspector) {
            inspector(summary).inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
    }

    private func inspector(_ summary: ReconciliationSummary) -> some View {
        let allOn = !snapshot.items.isEmpty && snapshot.items.allSatisfy(\.isCleared)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Conciliación").font(.title3.weight(.bold)).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MacInspectorSummary(title: summary.isBalanced ? String(localized: "Cuadra · diferencia") : String(localized: "Diferencia"),
                                        amount: summary.difference.money) {
                        HStack(spacing: 6) {
                            StatusDot(color: summary.isBalanced ? Palette.green : Palette.red)
                            Text(summary.isBalanced ? String(localized: "Coincide con el extracto") : String(localized: "Marca las partidas que aparecen en el extracto"))
                                .font(.subheadline).foregroundStyle(Palette.ink2)
                        }
                    }
                    MacInspectorSection(title: String(localized: "Extracto")) {
                        StatementFields(reconciliation: snapshot.reconciliation, account: account, update: update)
                    }
                    MacInspectorSection(title: String(localized: "Saldos")) {
                        MacInspectorRow(String(localized: "Saldo inicial"), value: summary.beginningBalance.money)
                        MacInspectorRow(String(localized: "Marcadas que suman"), value: summary.clearedIncreases.money)
                        MacInspectorRow(String(localized: "Marcadas que restan"), value: summary.clearedDecreases.money)
                        MacInspectorRow(String(localized: "Saldo conciliado"), value: summary.clearedBalance.money, bold: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            VStack(spacing: 8) {
                Button(summary.isBalanced ? "Terminar conciliación" : "Marca partidas hasta llegar a $0.00", action: finish)
                    .buttonStyle(.primary).disabled(!summary.isBalanced)
                    .keyboardShortcut(.defaultAction)
                HStack {
                    Button(allOn ? "Desmarcar todas" : "Marcar todas") { toggle(snapshot.items.map(\.id), !allOn, snapshot) }
                        .buttonStyle(.secondary)
                    if !snapshot.suggested.isEmpty {
                        Button("Marcar emparejadas") { toggle(snapshot.suggested.map(\.id), true, snapshot) }.buttonStyle(.secondary)
                    }
                }
                Button("Cancelar conciliación", action: cancel).buttonStyle(.destructive)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Sin fondo propio: el gris del sistema, el de la barra lateral (como Tamio).
    }
}
#endif

extension View {
    /// En el Mac, un campo de formulario con su etiqueta a la izquierda (el `TextField` de `MoneyField` no la pone en
    /// un `Form` agrupado); en iOS, tal cual.
    @ViewBuilder
    func labeledField(_ title: String) -> some View {
        #if os(macOS)
        LabeledContent(title) { self.labelsHidden().multilineTextAlignment(.trailing) }
        #else
        LabeledContent(title) { self.multilineTextAlignment(.trailing) }
        #endif
    }
}
