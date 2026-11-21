import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

#if os(iOS)
// iPad: Conciliación y Reglas de Banca con columna maestro y detalle, como Cuentas y Por revisar (pedido del usuario del
// 21-nov: a todo el ancho se veían estiradas). La lista de cuentas o reglas va en la columna; la conciliación de la
// cuenta o la ficha de la regla, en el detalle. El iPhone sigue con `ReconciliationHubView` y `BankRulesView`; el Mac,
// con sus tablas.

// MARK: - Conciliación

/// Cuentas de banco y tarjeta con el estado de su conciliación; la elegida se concilia en el detalle.
struct ReconcileMasterList: View {
    @Binding var selection: UUID?
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Reconciliation.statementDate, order: .reverse) private var reconciliations: [Reconciliation]

    private var shown: [Account] {
        accounts.filter { ($0.subtype == .bank || $0.subtype == .creditCard) && !$0.isArchived }
    }

    var body: some View {
        List(selection: $selection) {
            if shown.isEmpty {
                Text("Añade una cuenta de banco o tarjeta para conciliarla.")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .selectionDisabled()
                    .listRowBackground(Palette.masterColumn)
            }
            ForEach(shown) { account in
                let status = ReconciliationText.status(of: account, reconciliations: reconciliations)
                // El icono de color de la cuenta a la izquierda, como en la lista de antes (sugerencia del usuario, 21-nov).
                HStack(spacing: 12) {
                    IconTile(systemImage: account.bankSymbol, foreground: account.bankColor)
                    MasterRow(title: account.maskedName, amount: "", subtitle: status.text) { EmptyView() }
                }
                .masterRow(account.id, selection: selection)
            }
            if !shown.isEmpty {
                Text("Compara tus libros con el extracto del banco: marca lo que aparece en él hasta que la diferencia sea $0.00.")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Palette.masterColumn)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.masterColumn)
        .tint(Color.clear)
        .focusEffectDisabled()
        .masterHeader(String(localized: "Conciliación"))
        // Panel de clientes: «Conciliación» abre la cuenta más atrasada.
        .onClientRoute({ route in
            if case .reconcile = route { return true }
            return false
        }) { route in
            if case .reconcile(let id) = route { selection = id }
        }
        .task {
            // Con una sola cuenta no hay nada que elegir: se abre.
            if selection == nil, shown.count == 1 { selection = shown.first?.id }
            #if DEBUG
            if let index = QABanking.reconcileIndex, shown.indices.contains(index) { selection = shown[index].id }
            #endif
        }
    }
}

// MARK: - Reglas

/// Reglas por prioridad; la elegida se ve en el detalle (`BankRuleDetail`). «+» crea una y, abajo, «Aplicar ahora».
struct RuleMasterList: View {
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: [SortDescriptor(\BankRule.priority, order: .reverse), SortDescriptor(\BankRule.createdAt)])
    private var rules: [BankRule]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var creating = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        List(selection: $selection) {
            ForEach(rules) { rule in
                MasterRow(title: rule.name, amount: "", subtitle: rule.summary(accounts: byID)) {
                    MasterStatus(chip: StatusChip(text: rule.stateTitle, foreground: Palette.ink2, compact: true, dot: rule.stateColor))
                }
                .masterRow(rule.id, selection: selection)
                .contextMenu {
                    Button(rule.isActive ? "Desactivar" : "Activar") {
                        BankRuleActions.toggle(rule, context: context) { errorMessage = $0 }
                    }
                    Button("Borrar", role: .destructive) {
                        BankRuleActions.delete(rule, context: context) { errorMessage = $0 }
                    }
                }
            }
            if !rules.isEmpty {
                Text("Se prueban de mayor a menor prioridad; la primera que coincide propone la categoría. Las que «registran solas» guardan el movimiento sin pasar por la bandeja.")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Palette.masterColumn)
                Button("Aplicar ahora a la bandeja", systemImage: "wand.and.stars") {
                    BankRuleActions.applyNow(context: context, done: { message = $0 }, failed: { errorMessage = $0 })
                }
                .foregroundStyle(Palette.brand)
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.masterColumn)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.masterColumn)
        .tint(Color.clear)
        .focusEffectDisabled()
        .masterHeader(String(localized: "Reglas"))
        .masterAddButton(String(localized: "Regla"), label: String(localized: "Nueva regla")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { BankRuleEditorView() }.editorSheetSizing() }
        .alert("Reglas aplicadas", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(message ?? "") }
        .failureAlert($errorMessage)
    }
}

/// La regla elegida: qué busca, qué propone y sus acciones (como el inspector del Mac).
struct BankRuleDetail: View {
    let rule: BankRule
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(rule.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    StatusChip(text: rule.stateTitle, foreground: Palette.ink2, compact: false, dot: rule.stateColor)
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Si la descripción contiene", value: rule.matchText)
                LabeledContent("Categoría", value: rule.targetAccountID.flatMap { byID[$0]?.name } ?? "—")
                LabeledContent("Movimientos", value: rule.amountSign.title)
                LabeledContent("Cuenta del banco", value: rule.bankAccountID.flatMap { byID[$0]?.maskedName } ?? String(localized: "Todas"))
                if !rule.payee.isEmpty { LabeledContent("Beneficiario", value: rule.payee) }
                LabeledContent("Prioridad", value: "\(rule.priority)")
            } header: {
                SectionLabel(text: String(localized: "Detalles"))
            } footer: {
                Text(rule.autoApply
                     ? String(localized: "Registra sola los movimientos que coinciden, sin pasar por la bandeja.")
                     : String(localized: "Propone la categoría en la bandeja; tú decides."))
            }
            Section {
                Button("Editar regla…") { SubscriptionStore.shared.whenWritable { editing = true } }
                    .buttonStyle(.primary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Button(rule.isActive ? "Desactivar" : "Activar", systemImage: rule.isActive ? "pause" : "play") {
                    BankRuleActions.toggle(rule, context: context) { errorMessage = $0 }
                }
                .tint(Palette.brand)
                Button("Borrar regla", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .readableDetailWidth()
        .navigationTitle(rule.name)
        .inlineTitle()
        .sheet(isPresented: $editing) { NavigationStack { BankRuleEditorView(rule: rule) }.editorSheetSizing() }
        .confirmationDialog("¿Borrar esta regla?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Borrar regla", role: .destructive) {
                BankRuleActions.delete(rule, context: context) { errorMessage = $0 }
            }
        } message: {
            Text("Los movimientos ya registrados no cambian.")
        }
        .failureAlert($errorMessage)
    }
}

/// Detalle de Reglas sin nada elegido: la explicación mientras no hay reglas; si ya hay, «Elige una regla».
struct RulePlaceholder: View {
    @CompanyQuery private var rules: [BankRule]

    var body: some View {
        Group {
            if rules.isEmpty {
                EmptyStateView(systemImage: "wand.and.stars", title: String(localized: "Aún no tienes reglas"),
                               message: String(localized: "Una regla categoriza sola los movimientos que se parecen: «si la descripción contiene UBER → Transporte»."))
            } else {
                EmptyStateView(systemImage: "wand.and.stars", title: String(localized: "Elige una regla"),
                               message: String(localized: "Lo que elijas en la lista se abre aquí."))
            }
        }
    }
}
#endif
