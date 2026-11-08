import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Recurrentes (canvas `Gastos` · Recurrentes, `MacGastoNuevo` «Repetición», `MacPorPagar` «Recurrente · cargo
// automático»; docs/DATOS-V2.md §2): la lista de plantillas, su editor y los gastos «por confirmar» que generan las
// plantillas sin cargo automático.

extension Expense {
    /// Sin asiento y sin anular: lo generó una recurrente sin cargo automático y falta registrarlo.
    nonisolated var isPendingConfirmation: Bool { !isPosted && !isVoid }
}

extension RecurringKind {
    var title: String {
        switch self {
        case .expense: String(localized: "Gasto")
        case .bill: String(localized: "Factura por pagar")
        }
    }
}

/// Lo que la app hace sola: genera las repeticiones que tocan hasta hoy y registra los pagos de cargo automático que
/// vencen (`Bookkeeper.runAutomations`, idempotente). Lo debería llamar la app al abrirse y al volver al primer plano
/// (`Shell/RootView`, de otro agente); mientras tanto lo llaman las pantallas de Gastos y Por pagar al aparecer, como
/// mucho una vez por minuto.
@MainActor
enum RecurringAutomation {
    private static var lastRun: Date?

    static func run(in context: ModelContext, now: Date = .now) {
        if let lastRun, now.timeIntervalSince(lastRun) < 60 { return }
        lastRun = now
        _ = try? Bookkeeper(context: context).runAutomations(asOf: now)
    }
}

// MARK: - Lista

/// Plantillas recurrentes (canvas `Gastos` · Recurrentes: «Renta del taller · Próximo cargo el 3 nov · $1,200.00»),
/// con los gastos «por confirmar» arriba. En el iPhone es la tercera opción del segmentado de Gastos; en el iPad, una
/// hoja desde Gastos; en el Mac, una página desde la barra de Gastos.
struct RecurringListView: View {
    var section: Binding<ExpensesView.Segment>? = nil
    /// Pone su propio «+» (en la hoja del iPad y la página del Mac; en el iPhone lo pone `ExpensesView`).
    var showsAddButton = false
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \RecurringTemplate.nextDate) private var templates: [RecurringTemplate]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var editing: RecurringTemplate?
    @State private var creating = false
    @State private var deleting: RecurringTemplate?
    @State private var errorMessage: String?

    private var pending: [Expense] { expenses.filter(\.isPendingConfirmation) }
    private var active: [RecurringTemplate] { templates.filter { $0.isActive && !$0.isFinished } }
    private var inactive: [RecurringTemplate] { templates.filter { !$0.isActive || $0.isFinished } }

    private func category(_ id: UUID?) -> Account? { accounts.account(id) }

    var body: some View {
        List {
            if let section { ExpensesSegmentRow(selection: section) }
            if let errorMessage { ErrorBanner(message: errorMessage).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { expense in
                        PendingExpenseRow(expense: expense, category: category(expense.sortedLines.first?.accountID)) { record(expense) }
                    }
                } header: {
                    SectionLabel(text: String(localized: "Por confirmar"))
                } footer: {
                    Text("Los generó una recurrente sin cargo automático: revisa el importe y regístralos.")
                }
            }

            if templates.isEmpty {
                Section {
                    EmptyStateView(guide: .recurring) { creating = true }
                }
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { row($0) }
                } header: {
                    SectionLabel(text: String(localized: "Cargos recurrentes"))
                } footer: {
                    Text("Con cargo automático se registran solos; sin él, quedan por confirmar.")
                }
            }
            if !inactive.isEmpty {
                Section {
                    ForEach(inactive) { row($0) }
                } header: {
                    SectionLabel(text: String(localized: "En pausa o terminadas"))
                }
            }
        }
        .groupedList()
        .screenBackground()
        .toolbar {
            if showsAddButton {
                ToolbarItem(placement: .primaryAction) {
                    AddButton(title: "Nueva recurrente") { creating = true }
                }
            }
        }
        .sheet(item: $editing) { template in
            NavigationStack { RecurringTemplateEditorView(template: template) }.editorSheetSizing()
        }
        .sheet(isPresented: $creating) {
            NavigationStack { RecurringTemplateEditorView() }.editorSheetSizing()
        }
        .confirmationDialog("¿Borrar esta recurrente?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { template in
            Button("Borrar \(template.name)", role: .destructive) { delete(template) }
        } message: { _ in
            Text("Lo que ya generó se queda en tus libros; solo deja de repetirse.")
        }
    }

    private func row(_ template: RecurringTemplate) -> some View {
        Button { editing = template } label: {
            RecurringTemplateRow(template: template, category: category(template.sortedLines.first?.accountID))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Borrar", systemImage: "trash", role: .destructive) { deleting = template }
            Button(template.isActive ? "Pausar" : "Reanudar", systemImage: template.isActive ? "pause" : "play") { toggle(template) }
                .tint(Palette.indigo)
        }
        .contextMenu {
            Button("Editar…", systemImage: "pencil") { editing = template }
            Button(template.isActive ? "Pausar" : "Reanudar", systemImage: template.isActive ? "pause" : "play") { toggle(template) }
            Divider()
            Button("Borrar", systemImage: "trash", role: .destructive) { deleting = template }
        }
    }

    private func toggle(_ template: RecurringTemplate) {
        do {
            try Bookkeeper(context: context).setRecurringTemplate(template, active: !template.isActive)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ template: RecurringTemplate) {
        do {
            try Bookkeeper(context: context).deleteRecurringTemplate(template)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func record(_ expense: Expense) {
        do {
            try Bookkeeper(context: context).record(expense)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Fila de una plantilla: icono de su categoría, nombre, «Próximo cargo el 3 nov · Mensual» y el importe, con
/// «Cargo automático» o «En pausa» debajo.
struct RecurringTemplateRow: View {
    let template: RecurringTemplate
    let category: Account?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        if template.isFinished { return String(localized: "Terminada · \(template.frequency.title)") }
        let next = String(localized: "Próximo el \(template.nextDate.dayMonth)")
        return "\(next) · \(template.frequency.title)"
    }

    var body: some View {
        LedgerRow(title: template.name, subtitle: subtitle) {
            IconTile(systemImage: ExpenseCategoryStyle.symbol(for: category?.name), foreground: ExpenseCategoryStyle.color(for: category?.name))
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text(template.total.money).monospacedDigit().foregroundStyle(Palette.ink)
                if !template.isActive {
                    StatusChip(text: String(localized: "En pausa"), foreground: Palette.ink2, background: .clear, compact: true, dot: Palette.gray)
                } else if template.autoCharge {
                    StatusChip(text: String(localized: "Automático"), foreground: Palette.info, background: .clear, compact: true, dot: Palette.teal)
                } else {
                    StatusChip(text: String(localized: "Manual"), foreground: Palette.ink2, background: .clear, compact: true, dot: Palette.orange)
                }
            }
        }
    }
}

/// Gasto «por confirmar» (sin asiento): el beneficiario, la categoría y el día, el importe y «Registrar». Su menú
/// abre el gasto (para revisarlo o editarlo antes de registrarlo).
struct PendingExpenseRow: View {
    let expense: Expense
    let category: Account?
    let record: () -> Void

    var body: some View {
        AdaptiveRow {
            NavigationLink { ExpenseDetailView(expense: expense) } label: { label }
                .navigationLinkIndicatorVisibility(.hidden)
        } trailing: {
            Button("Registrar", action: record)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .frame(minHeight: Metrics.target)
                .accessibilityLabel(String(localized: "Registrar \(expense.payee)"))
        }
        .contextMenu {
            Button("Registrar", systemImage: "checkmark.circle", action: record)
        }
    }

    private var label: some View {
        LedgerRow(title: expense.payee, subtitle: "\(category?.name ?? String(localized: "Sin categoría")) · \(expense.date.relativeDay)") {
            IconTile(systemImage: ExpenseCategoryStyle.symbol(for: category?.name), foreground: ExpenseCategoryStyle.color(for: category?.name))
        } trailing: {
            Text(expense.total.money).monospacedDigit().foregroundStyle(Palette.ink)
        }
    }
}

// MARK: - Editor

/// Alta y edición de una plantilla recurrente: gasto o factura por pagar, importe y categoría, proveedor, cuenta de
/// pago, frecuencia, primera fecha, fin, cargo automático y pausa.
struct RecurringTemplateEditorView: View {
    var template: RecurringTemplate? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Vendor.name) private var vendors: [Vendor]

    @State private var name = ""
    @State private var kind: RecurringKind = .expense
    @State private var vendorID: UUID?
    @State private var payee = ""
    @State private var memo = ""
    @State private var amount: Int64 = 0
    @State private var categoryID: UUID?
    /// Las líneas de una plantilla con varias categorías se conservan tal cual (el editor cambia el resto).
    @State private var extraLines: [ExpenseInput.Line] = []
    @State private var paymentAccountID: UUID?
    @State private var method: PaymentMethod = .card
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var autoCharge = true
    @State private var isPaused = false
    @State private var billTermsDays = 30
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var isMultiLine: Bool { !extraLines.isEmpty }
    private var paymentAccounts: [Account] { accounts.paymentAccounts }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard isMultiLine || (amount > 0 && categoryID != nil) else { return false }
        if kind == .expense || autoCharge, paymentAccountID == nil { return false }
        if kind == .bill, vendorID == nil { return false }
        return !hasEnd || Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: startDate)
    }

    private var tracking: String {
        "\(name)|\(kind)|\(vendorID?.uuidString ?? "")|\(payee)|\(memo)|\(amount)|\(categoryID?.uuidString ?? "")|"
            + "\(paymentAccountID?.uuidString ?? "")|\(method)|\(frequency)|\(startDate)|\(hasEnd)|\(endDate)|\(autoCharge)|\(isPaused)|\(billTermsDays)"
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                TextField("Nombre (ej. Renta del taller)", text: $name)
                Picker("Crea", selection: $kind) {
                    ForEach(RecurringKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Qué crea cada repetición")
            } header: {
                SectionLabel(text: String(localized: "Recurrente"))
            } footer: {
                Text(kind == .expense ? "Cada repetición es un gasto pagado de la cuenta elegida."
                                      : "Cada repetición es una factura por pagar del proveedor, que vence a los días elegidos.")
            }

            Section {
                if isMultiLine {
                    LabeledContent("Importe", value: (extraLines.reduce(0) { $0 + $1.amount }).money)
                    LabeledContent("Categoría", value: String(localized: "Varias categorías"))
                } else {
                    MoneyRow(String(localized: "Importe"), minorUnits: $amount)
                    ExpenseCategoryPicker(title: String(localized: "Categoría"), accounts: accounts, selection: $categoryID)
                }
                VendorPicker(vendors: vendors, selection: $vendorID, noneTitle: kind == .bill ? "Elegir…" : "Ninguno",
                             proposedName: payee.isEmpty ? name : payee) { use($0) }
                if kind == .expense {
                    // Con un proveedor elegido, cada gasto lleva su nombre: basta con uno de los dos.
                    if vendorID == nil {
                        TextField("Pagado a (comercio o persona)", text: $payee)
                    }
                } else {
                    Picker("Vence a los", selection: $billTermsDays) {
                        Text("Al recibir").tag(0); Text("15 días").tag(15); Text("30 días").tag(30); Text("60 días").tag(60)
                    }
                }
                PaymentAccountPicker(title: kind == .expense ? String(localized: "Cuenta de pago") : String(localized: "Pagar desde"),
                                     accounts: paymentAccounts, selection: $paymentAccountID)
                PaymentMethodPicker(account: paymentAccounts.first { $0.id == paymentAccountID }, selection: $method)
                TextField("Nota (opcional)", text: $memo)
            } header: {
                SectionLabel(text: String(localized: "Detalles"))
            } footer: {
                if kind == .expense && vendorID == nil {
                    Text("Elige un proveedor si le compras a menudo o le pagas facturas; si no, basta con escribir en «Pagado a» a quién le pagas.")
                }
            }

            Section {
                Picker("Frecuencia", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                DatePicker(template == nil ? "Primera fecha" : "Desde", selection: $startDate, displayedComponents: .date)
                if let template, template.isActive, !template.isFinished {
                    LabeledContent("Próxima", value: template.nextDate.shortDate)
                }
                Toggle("Con fecha de fin", isOn: $hasEnd.animation())
                if hasEnd {
                    DatePicker("Termina", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                LabeledContent("Se repite") {
                    Text(frequency.summary(anchor: startDate, end: hasEnd ? endDate : nil)).foregroundStyle(Palette.ink2)
                }
            } header: {
                SectionLabel(text: String(localized: "Repetición"))
            }

            Section {
                Toggle("Cargo automático", isOn: $autoCharge)
                if template != nil {
                    Toggle("En pausa", isOn: $isPaused)
                }
            } footer: {
                Text(autoChargeFooter)
            }

            if template != nil {
                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Borrar recurrente", systemImage: "trash").frame(minHeight: Metrics.target)
                    }
                    .foregroundStyle(Palette.negative)
                }
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
        .navigationTitle(template == nil ? "Nueva recurrente" : "Editar recurrente")
        .inlineTitle()
        .discardableEditor(tracking: tracking, token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(!canSave).headerButton()
            }
        }
        .onChange(of: vendorID) { old, new in
            // «Nuevo proveedor…» pasa un instante por su etiqueta y vuelve a la de antes: eso no es elegir.
            guard loaded, old != VendorPicker.newVendorTag, new != VendorPicker.newVendorTag else { return }
            if let vendor = vendors.first(where: { $0.id == new }) { use(vendor) }
        }
        .onAppear(perform: load)
        .confirmationDialog("¿Borrar esta recurrente?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive, action: delete)
        } message: {
            Text("Lo que ya generó se queda en tus libros; solo deja de repetirse.")
        }
    }

    /// Lo que se toma del proveedor elegido (o recién creado desde el menú). Su nombre sustituye a «Pagado a»,
    /// que se esconde: cada gasto generado lleva el nombre del proveedor.
    private func use(_ vendor: Vendor) {
        payee = ""
        if name.isEmpty { name = vendor.name }
        if !isMultiLine, categoryID == nil { categoryID = vendor.defaultExpenseAccountID }
        if kind == .bill { billTermsDays = vendor.paymentTermsDays }
        if let preferred = vendor.preferredPaymentAccountID { paymentAccountID = preferred }
        if let preferred = vendor.preferredPaymentMethod { method = preferred }
    }

    private var autoChargeFooter: String {
        switch (kind, autoCharge) {
        case (.expense, true): String(localized: "Cada repetición se registra sola en la cuenta elegida.")
        case (.expense, false): String(localized: "Cada repetición queda «por confirmar» en Gastos hasta que la registres.")
        case (.bill, true): String(localized: "El pago de cada factura queda programado a su vencimiento y se registra solo.")
        case (.bill, false): String(localized: "Cada factura queda por pagar; la pagas o programas tú.")
        }
    }

    private func load() {
        guard !loaded else { return }
        defer { Task { @MainActor in loaded = true } }
        guard let template else {
            paymentAccountID = paymentAccounts.first { $0.subtype == .bank }?.id
            return
        }
        name = template.name; kind = template.kind; vendorID = template.vendor?.id; payee = template.payee; memo = template.memo
        let lines = template.sortedLines
        if lines.count == 1 {
            amount = lines[0].amount; categoryID = lines[0].accountID
        } else {
            extraLines = lines.map { ExpenseInput.Line(details: $0.details, amount: $0.amount, accountID: $0.accountID) }
        }
        paymentAccountID = template.paymentAccountID; method = template.method; frequency = template.frequency
        startDate = template.startDate; hasEnd = template.endDate != nil
        if let end = template.endDate { endDate = end }
        autoCharge = template.autoCharge; isPaused = !template.isActive; billTermsDays = template.billTermsDays
    }

    private func save() {
        let books = Bookkeeper(context: context)
        let vendor = vendors.first { $0.id == vendorID }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lines = isMultiLine ? extraLines
            : [ExpenseInput.Line(details: template?.sortedLines.first?.details ?? trimmed, amount: amount, accountID: categoryID)]
        let input = RecurringTemplateInput(
            name: trimmed, kind: kind, vendor: vendor, payee: kind == .expense ? payee.trimmingCharacters(in: .whitespaces) : "",
            memo: memo, lines: lines, paymentAccountID: paymentAccountID, method: method, frequency: frequency,
            startDate: startDate, endDate: hasEnd ? endDate : nil, autoCharge: autoCharge,
            isActive: template?.isActive ?? true, billTermsDays: billTermsDays)
        do {
            let saved = try books.saveRecurringTemplate(input, into: template)
            // Pausar y reanudar van por su servicio: al reanudar no se genera lo que pasó en pausa.
            if saved.isActive == isPaused { try books.setRecurringTemplate(saved, active: !isPaused) }
            // Si la primera fecha ya llegó, genera lo que toca hoy (es idempotente).
            let run = try books.generateRecurring(through: .now)
            if let failure = run.failures.first(where: { $0.template.id == saved.id }) {
                errorMessage = String(localized: "La recurrente se guardó, pero no se pudo generar la del \(failure.date.shortDate): \(failure.error.localizedDescription)")
                return
            }
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let template else { return }
        do {
            try Bookkeeper(context: context).deleteRecurringTemplate(template)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
