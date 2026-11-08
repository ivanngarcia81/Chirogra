import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Reglas del banco (canvas `Banca` · «Reglas · 5 activas», `BancaRevisar` · «Crear regla automática»): «si la
// descripción contiene X → categoría Y». Lista con alta, edición, activar/desactivar, prioridad y «Aplicar ahora» a la
// bandeja. iPhone e iPad: lista; Mac: tabla + inspector.

extension BankAmountSign {
    var title: String {
        switch self {
        case .any: String(localized: "Entradas y salidas")
        case .inflow: String(localized: "Solo entradas")
        case .outflow: String(localized: "Solo salidas")
        }
    }
}

extension BankRule {
    /// «contiene «UBER» → Transporte».
    func summary(accounts: [UUID: Account]) -> String {
        let target = targetAccountID.flatMap { accounts[$0]?.name } ?? "—"
        return String(localized: "contiene «\(matchText)» → \(target)")
    }

    var stateTitle: String {
        guard isActive else { return String(localized: "Desactivada") }
        return autoApply ? String(localized: "Registra sola") : String(localized: "Propone")
    }

    var stateColor: Color { isActive ? (autoApply ? Palette.blue : Palette.green) : Palette.gray }
}

/// Lista de reglas.
struct BankRulesView: View {
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: [SortDescriptor(\BankRule.priority, order: .reverse), SortDescriptor(\BankRule.createdAt)])
    private var rules: [BankRule]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var editing: BankRule?
    @State private var creating = false
    @State private var message: String?
    @State private var errorMessage: String?
    #if os(macOS)
    @State private var selection: UUID?
    @State private var query = ""
    #endif

    private var accountsByID: [UUID: Account] { Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    var body: some View {
        content
            .sheet(isPresented: $creating) { NavigationStack { BankRuleEditorView() }.editorSheetSizing() }
            .sheet(item: $editing) { rule in NavigationStack { BankRuleEditorView(rule: rule) }.editorSheetSizing() }
            .alert("Reglas aplicadas", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(message ?? "") }
            .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1))
                if UserDefaults.standard.bool(forKey: "qa.reglaNueva") { creating = true }
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macTable
        #else
        List {
            Section {
                if rules.isEmpty {
                    Text("Aún no tienes reglas. Créalas aquí o desde un movimiento de la bandeja, con «Crear regla».")
                        .foregroundStyle(Palette.ink2)
                }
                ForEach(rules) { rule in
                    Button { editing = rule } label: { row(rule) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(rule.isActive ? "Desactivar" : "Activar") { toggle(rule) }.tint(rule.isActive ? Palette.gray : Palette.green)
                        }
                        .contextMenu {
                            Button(rule.isActive ? "Desactivar" : "Activar") { toggle(rule) }
                            Button("Borrar", role: .destructive) { delete(rule) }
                        }
                }
            } header: {
                SectionLabel(text: String(localized: "Por prioridad"))
            } footer: {
                Text("Se prueban de mayor a menor prioridad; la primera que coincide propone la categoría. Las que «registran solas» guardan el movimiento sin pasar por la bandeja.")
            }
            if !rules.isEmpty {
                Section {
                    Button("Aplicar ahora a la bandeja", systemImage: "wand.and.stars", action: applyNow)
                        .tint(Palette.brand)
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Reglas")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { SubscriptionStore.shared.whenWritable { creating = true } } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Regla") }
                }
                .accessibilityLabel("Nueva regla")
                .headerButton()
            }
        }
        #endif
    }

    private func row(_ rule: BankRule) -> some View {
        LedgerRow(title: rule.name, subtitle: rule.summary(accounts: accountsByID)) {
            IconTile(systemImage: "bolt", foreground: rule.isActive ? Palette.purple : Palette.gray)
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                StatusChip(text: rule.stateTitle, foreground: rule.isActive ? Palette.ink2 : Palette.ink2, background: .clear, compact: true, dot: rule.stateColor)
                Text("Prioridad \(rule.priority)").font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .contentShape(Rectangle())
    }

    #if os(macOS)
    private var macTable: some View {
        let filtered = rules.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.matchText.localizedStandardContains(query) }
            .map { BankRuleRow(rule: $0, accounts: accountsByID) }
        return MacTablePage(
            title: String(localized: "Reglas"), subtitle: String(localized: "Banca · \(rules.filter(\.isActive).count) activas"),
            rows: filtered, footer: String(localized: "\(filtered.count) reglas"), query: $query, searchPrompt: Text("Nombre o texto"),
            selection: $selection, sortOrder: [KeyPathComparator(\BankRuleRow.priority, order: .reverse)],
            addTitle: String(localized: "Nueva regla"), onAdd: { creating = true }, onOpen: { editing = $0.rule },
            empty: rules.isEmpty
                ? MacTableEmpty(systemImage: "bolt", title: String(localized: "Aún no tienes reglas"),
                                message: String(localized: "Una regla categoriza sola los movimientos que se parecen: «si la descripción contiene UBER → Transporte»."),
                                actionTitle: String(localized: "Nueva regla"), action: { creating = true }, isGuide: true)
                : MacTableEmpty(title: String(localized: "Sin resultados"), message: String(localized: "Ninguna regla coincide con la búsqueda."),
                                actionTitle: String(localized: "Quitar búsqueda"), action: { query = "" }),
            inspectorTitle: { _ in String(localized: "Regla") },
            inspectorPlaceholder: String(localized: "Selecciona una regla para ver sus detalles.")
        ) {
            TableColumn("Nombre", value: \.name) { Text($0.name).lineLimit(1) }.width(min: 90, ideal: 120)
            TableColumn("Contiene", value: \.matchText) { MacCellText(text: $0.matchText) }.width(min: 70, ideal: 100)
            TableColumn("Categoría", value: \.target) { MacCellText(text: $0.target) }.width(min: 90, ideal: 130)
            TableColumn("Movimientos", value: \.signTitle) { MacCellText(text: $0.signTitle) }.width(min: 70, ideal: 90)
            TableColumn("Prioridad", value: \.priority) { Text(verbatim: "\($0.priority)").monospacedDigit() }.width(min: 56, ideal: 62, max: 80)
                .alignment(.trailing)
            TableColumn("Estado", value: \.stateTitle) { row in
                MacCellStatus(chip: StatusChip(text: row.stateTitle, foreground: Palette.ink2, background: .clear, compact: true, dot: row.stateColor))
            }
            .width(min: 80, ideal: 90)
        } filter: {
            EmptyView()
        } inspector: { row in
            let rule = row.rule
            MacInspectorSummary(title: rule.name, amount: rule.matchText) {
                StatusChip(text: rule.stateTitle, foreground: Palette.ink2, background: .clear, compact: true, dot: rule.stateColor)
            }
            MacInspectorSection(title: String(localized: "Detalles")) {
                MacInspectorRow(String(localized: "Si la descripción contiene"), value: rule.matchText)
                MacInspectorRow(String(localized: "Categoría"), value: row.target)
                MacInspectorRow(String(localized: "Movimientos"), value: row.signTitle)
                MacInspectorRow(String(localized: "Cuenta del banco"),
                                value: rule.bankAccountID.flatMap { accountsByID[$0]?.maskedName } ?? String(localized: "Todas"))
                if !rule.payee.isEmpty { MacInspectorRow(String(localized: "Beneficiario"), value: rule.payee) }
                MacInspectorRow(String(localized: "Prioridad"), value: "\(rule.priority)")
            }
        } actions: { row in
            Button("Editar regla…") { editing = row.rule }.buttonStyle(.primary)
            HStack {
                Button(row.rule.isActive ? "Desactivar" : "Activar") { toggle(row.rule) }.buttonStyle(.secondary)
                Button("Borrar", role: .destructive) { delete(row.rule) }.buttonStyle(.destructive)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: applyNow) { Label("Aplicar ahora", systemImage: "wand.and.stars").labelStyle(.titleAndIcon) }
                    .help("Aplica las reglas activas a los movimientos por revisar")
                    .disabled(rules.isEmpty)
            }
        }
    }
    #endif

    // MARK: Acciones

    private func toggle(_ rule: BankRule) {
        SubscriptionStore.shared.whenWritable {
            var input = BankRuleInput(rule)
            input.isActive.toggle()
            do { try Bookkeeper(context: context).saveBankRule(input, into: rule) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ rule: BankRule) {
        SubscriptionStore.shared.whenWritable {
            do { try Bookkeeper(context: context).deleteBankRule(rule) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func applyNow() {
        SubscriptionStore.shared.whenWritable {
            do {
                let run = try Bookkeeper(context: context).applyBankRules()
                var parts = [String(localized: "\(run.categorized.count) movimientos con categoría propuesta.")]
                if !run.applied.isEmpty { parts.append(String(localized: "\(run.applied.count) se registraron solos.")) }
                if let failure = run.failures.first { parts.append(failure.error.localizedDescription) }
                message = parts.joined(separator: " ")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if os(macOS)
nonisolated struct BankRuleRow: Identifiable {
    let rule: BankRule
    let id: UUID
    let name: String
    let matchText: String
    let target: String
    let signTitle: String
    let priority: Int
    let stateTitle: String
    let stateColor: Color

    @MainActor
    init(rule: BankRule, accounts: [UUID: Account]) {
        self.rule = rule
        id = rule.id
        name = rule.name
        matchText = rule.matchText
        target = rule.targetAccountID.flatMap { accounts[$0]?.name } ?? "—"
        signTitle = rule.amountSign.title
        priority = rule.priority
        stateTitle = rule.stateTitle
        stateColor = rule.stateColor
    }
}
#endif

// MARK: - Editor

/// Alta y edición de una regla. `draft` la rellena desde un movimiento de la bandeja.
struct BankRuleEditorView: View {
    var rule: BankRule? = nil
    var draft: BankRuleInput? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var input = BankRuleInput(matchText: "", targetAccountID: nil)
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    private var bankAccounts: [Account] { accounts.filter { ($0.subtype == .bank || $0.subtype == .creditCard) && !$0.isArchived } }

    private var groups: [BankCategoryOptions.Group] {
        let outflow = BankCategoryOptions.groups(for: -1, bankAccountID: input.bankAccountID, accounts: accounts)
        let inflow = BankCategoryOptions.groups(for: 1, bankAccountID: input.bankAccountID, accounts: accounts)
        switch input.amountSign {
        case .outflow: return outflow
        case .inflow: return inflow
        case .any:
            var seen = Set<UUID>()
            return (outflow + inflow).compactMap { group in
                let fresh = group.accounts.filter { seen.insert($0.id).inserted }
                return fresh.isEmpty ? nil : BankCategoryOptions.Group(title: group.title, accounts: fresh)
            }
        }
    }

    private var canSave: Bool {
        !input.matchText.trimmingCharacters(in: .whitespaces).isEmpty && input.targetAccountID != nil
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
            Section {
                TextField("Si la descripción contiene", text: $input.matchText, prompt: Text(verbatim: "UBER"))
                    .labeledField(String(localized: "Si la descripción contiene"))
                    .autocorrectionDisabled()
                Picker("Movimientos", selection: $input.amountSign) {
                    ForEach(BankAmountSign.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Cuenta del banco", selection: $input.bankAccountID) {
                    Text("Todas").tag(UUID?.none)
                    ForEach(bankAccounts) { Text($0.maskedName).tag(Optional($0.id)) }
                }
            } header: {
                SectionLabel(text: String(localized: "Cuándo"))
            } footer: {
                Text("Sin distinguir mayúsculas ni acentos, en la descripción del banco o el beneficiario.")
            }
            Section {
                Picker("Categoría", selection: $input.targetAccountID) {
                    Text("Elegir…").tag(UUID?.none)
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.accounts) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                    }
                }
                Picker("Proveedor", selection: $input.vendorID) {
                    Text("Ninguno").tag(UUID?.none)
                    ForEach(vendors.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Beneficiario", text: $input.payee, prompt: Text("El del banco"))
                    .labeledField(String(localized: "Beneficiario"))
            } header: {
                SectionLabel(text: String(localized: "Qué hace"))
            }
            Section {
                TextField("Nombre", text: $input.name, prompt: Text(input.matchText.isEmpty ? String(localized: "Igual que el texto") : input.matchText))
                    .labeledField(String(localized: "Nombre"))
                Stepper(value: $input.priority, in: -99...99) {
                    LabeledContent("Prioridad", value: "\(input.priority)")
                }
                Toggle("Registrar sola, sin pasar por la bandeja", isOn: $input.autoApply)
                Toggle("Activa", isOn: $input.isActive)
            } header: {
                SectionLabel(text: String(localized: "Opciones"))
            } footer: {
                Text("Con varias reglas que coinciden, gana la de mayor prioridad. Si registra sola y no puede (periodo cerrado…), el movimiento queda por revisar con su propuesta.")
            }
            if let rule {
                Section {
                    Button("Borrar regla", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                        .confirmationDialog("¿Borrar la regla «\(rule.name)»?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Borrar", role: .destructive) { delete(rule) }
                        } message: {
                            Text("Los movimientos que ya categorizó no cambian.")
                        }
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(rule == nil ? "Nueva regla" : "Editar regla")
        .inlineTitle()
        .discardableEditor(tracking: "\(input.name)|\(input.matchText)|\(input.amountSign)|\(String(describing: input.targetAccountID))|\(input.priority)|\(input.autoApply)|\(input.isActive)|\(input.payee)",
                           token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(!canSave).headerButton()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let rule { input = BankRuleInput(rule) } else if let draft { input = draft }
        }
    }

    private func save() {
        SubscriptionStore.shared.whenWritable {
            do {
                try Bookkeeper(context: context).saveBankRule(input, into: rule)
                unsavedChanges?.remove(editorToken)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ rule: BankRule) {
        do {
            try Bookkeeper(context: context).deleteBankRule(rule)
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
