import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Nuevo gasto y editar un gasto (canvas `MacGastoNuevo`; en el iPhone, el formulario agrupado). Todo cambio contable
/// pasa por `Bookkeeper`: alta con `createExpense`, edición con `updateExpense`, que en un gasto ya contabilizado no
/// toca su asiento: lo revierte en su fecha y registra uno nuevo (docs/DATOS-V2.md §3). «Impuesto incluido» es
/// informativo; «Cliente o proyecto» marca el gasto como facturable; «Gasto recurrente» guarda además una plantilla
/// que repite el gasto (§2).
struct ExpenseEditorView: View {
    /// El gasto que se edita; `nil` para uno nuevo.
    var expense: Expense? = nil
    /// Desde la ficha de un proveedor («+ Gasto», «Recibo»).
    var preselectedVendor: Vendor? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query private var companies: [Company]

    /// Una línea del gasto (categoría e importe). Un gasto normal tiene una; se puede repartir en varias categorías.
    struct LineDraft: Identifiable, Equatable {
        let id = UUID()
        var details = ""
        var amount: Int64 = 0
        var accountID: UUID?
    }

    @State private var payee = ""
    @State private var vendorID: UUID?
    @State private var customerID: UUID?
    @State private var date = Date()
    @State private var lines: [LineDraft] = [LineDraft()]
    @State private var salesTaxIncluded: Int64 = 0
    @State private var paymentAccountID: UUID?
    @State private var memo = ""
    @State private var receipts: [ReceiptFile] = []
    @State private var method: PaymentMethod = .card
    @State private var repeats = false
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var autoCharge = true
    @State private var errorMessage: String?
    @State private var editorWidth: CGFloat = 0
    @State private var loaded = false
    /// La fecha (la nueva o la original) cae en un periodo cerrado: se pide la contraseña de cierre para seguir.
    @State private var askingUnlock = false
    @State private var closingPassword = ""
    @State private var pendingAnother = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    private var isEditing: Bool { expense != nil }
    private var isPosted: Bool { expense?.isPosted ?? false }

    /// `MacGastoNuevo` en iPad y Mac (hasta AX3): el recibo a la izquierda y el formulario a la derecha. En el
    /// iPhone, el formulario con el recibo como una sección más. Al editar, solo el formulario (los recibos se
    /// gestionan en el detalle).
    private var isWide: Bool {
        guard !isEditing else { return false }
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    private var total: Int64 { lines.reduce(0) { $0 + $1.amount } }

    private var canSave: Bool {
        total > 0 && lines.allSatisfy { $0.amount > 0 && $0.accountID != nil } && paymentAccountID != nil
            && !(payee.trimmingCharacters(in: .whitespaces).isEmpty && vendorID == nil)
            && salesTaxIncluded >= 0 && salesTaxIncluded < total
    }

    private var paymentAccounts: [Account] { accounts.paymentAccounts }
    private var hasClosingPassword: Bool { companies.first?.hasClosingPassword ?? false }

    private var tracking: String {
        let lineText = lines.map { "\($0.amount):\($0.accountID?.uuidString ?? "")" }.joined(separator: ",")
        return "\(payee)|\(vendorID?.uuidString ?? "")|\(customerID?.uuidString ?? "")|\(date)|\(lineText)|\(salesTaxIncluded)|"
            + "\(paymentAccountID?.uuidString ?? "")|\(memo)|\(receipts.count)|\(method)|\(repeats)|\(frequency)|\(autoCharge)"
    }

    var body: some View {
        Group {
            if isWide { wideForm } else { compactForm }
        }
        .navigationTitle(isEditing ? "Editar gasto" : "Nuevo gasto")
        .inlineTitle()
        .discardableEditor(tracking: tracking, token: editorToken)
        .toolbar {
            #if os(macOS)
            // Una hoja del Mac solo muestra «Cancelar» y la acción de confirmar (con Return); «Guardar y nuevo» va en
            // el contenido.
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Guardar cambios" : "Guardar gasto") { save() }.disabled(!canSave)
            }
            #else
            if isWide {
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar y nuevo") { save(another: true) }.disabled(!canSave).headerButton()
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar gasto") { save() }.disabled(!canSave).headerButton()
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(!canSave).headerButton()
                }
            }
            #endif
        }
        .onChange(of: vendorID) { old, new in
            // «Nuevo proveedor…» pasa un instante por su etiqueta y vuelve a la de antes: eso no es elegir.
            guard loaded, old != VendorPicker.newVendorTag, new != VendorPicker.newVendorTag else { return }
            if let vendor = vendors.first(where: { $0.id == new }) { use(vendor) }
        }
        .onAppear(perform: load)
        .alert(hasClosingPassword ? "Periodo cerrado" : "¿Registrar en un periodo cerrado?", isPresented: $askingUnlock) {
            if hasClosingPassword {
                SecureField("Contraseña de cierre", text: $closingPassword)
            }
            Button("Registrar") { unlockAndSave() }
            Button("Cancelar", role: .cancel) { closingPassword = "" }
        } message: {
            Text(hasClosingPassword
                 ? "La fecha cae en un periodo cerrado. Escribe la contraseña de cierre para registrar el cambio; quedará en el historial."
                 : "La fecha cae en un periodo cerrado. El cambio quedará en el historial.")
        }
    }

    /// Proveedor recién elegido (o creado desde el menú): su nombre pasa a «Pagado a», que se esconde, y su
    /// categoría por defecto a la línea si solo hay una.
    private func use(_ vendor: Vendor) {
        payee = vendor.name
        if lines.count == 1, let defaultAccount = vendor.defaultExpenseAccountID { lines[0].accountID = defaultAccount }
    }

    private func load() {
        guard !loaded else { return }
        defer { Task { @MainActor in loaded = true } }
        if let expense {
            let input = ExpenseInput(expense)
            payee = input.payee
            vendorID = input.vendor?.id
            customerID = input.customer?.id
            date = input.date
            paymentAccountID = input.paymentAccountID
            method = input.method
            memo = input.memo
            salesTaxIncluded = input.salesTaxIncluded
            lines = input.lines.isEmpty ? [LineDraft()] : input.lines.map { LineDraft(details: $0.details, amount: $0.amount, accountID: $0.accountID) }
        } else {
            paymentAccountID = paymentAccounts.first { $0.subtype == .bank }?.id
            if let preselectedVendor {
                vendorID = preselectedVendor.id
                payee = preselectedVendor.name
                lines[0].accountID = preselectedVendor.defaultExpenseAccountID
            }
        }
    }

    // MARK: Secciones (las mismas en las dos formas)

    @ViewBuilder
    private var postedNotice: some View {
        if isPosted {
            Section {
                Label {
                    Text("Este gasto ya está en tus libros. Si cambias la fecha, los importes, la categoría, la cuenta, el proveedor o el cliente, Chirogra revierte su asiento y registra uno nuevo; los dos quedan en el historial del gasto.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Palette.info)
                }
                .foregroundStyle(Palette.ink)
            }
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        Section {
            if lines.count == 1 {
                MoneyRow(String(localized: "Monto"), minorUnits: $lines[0].amount, font: .amount(isWide ? 17 : 24))
            }
            DatePicker("Fecha", selection: $date, displayedComponents: .date)
            MoneyRow(String(localized: "Impuesto incluido"), minorUnits: $salesTaxIncluded)
        } header: {
            SectionLabel(text: String(localized: "Importe"))
        } footer: {
            if salesTaxIncluded > 0 && salesTaxIncluded >= total {
                Text("El impuesto incluido debe ser menor que el monto.").foregroundStyle(Palette.negative)
            } else if salesTaxIncluded > 0 {
                Text("Subtotal \((total - salesTaxIncluded).money) + impuesto \(salesTaxIncluded.money). Es informativo: en EE. UU. el sales tax de tus compras forma parte del gasto.")
            } else {
                Text("En EE. UU. el sales tax de tus compras forma parte del gasto. Si el recibo lo desglosa, anótalo en «Impuesto incluido».")
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            VendorPicker(vendors: vendors, selection: $vendorID, proposedName: payee) { use($0) }
            // Con un proveedor elegido, su nombre es el «Pagado a»: basta con uno de los dos.
            if vendorID == nil {
                TextField("Pagado a (comercio o persona)", text: $payee)
            }
            if lines.count == 1 {
                ExpenseCategoryPicker(title: String(localized: "Categoría"), accounts: accounts, selection: $lines[0].accountID)
            }
            PaymentAccountPicker(title: String(localized: "Cuenta de pago"), accounts: paymentAccounts, selection: $paymentAccountID)
            Picker("Método de pago", selection: $method) {
                ForEach(Self.methods, id: \.self) { Text(Self.title(for: $0)).tag($0) }
            }
            Picker(selection: $customerID) {
                Text("Ninguno").tag(UUID?.none)
                ForEach(customers.filter { !$0.isArchived || $0.id == customerID }) { Text($0.name).tag(Optional($0.id)) }
            } label: {
                Text("Cliente o proyecto")
                Text("Opcional: para refacturárselo")
            }
            if lines.count == 1 {
                Button("Repartir en varias categorías", systemImage: "square.split.2x1") { addLine() }
                    .frame(minHeight: Metrics.target)
            }
        } header: {
            SectionLabel(text: String(localized: "Detalles"))
        } footer: {
            if vendorID == nil {
                Text("Elige un proveedor si le compras a menudo o le pagas facturas; si no, basta con escribir en «Pagado a» a quién le pagaste.")
            }
        }
    }

    @ViewBuilder
    private var linesSection: some View {
        if lines.count > 1 {
            Section {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 6) {
                        ExpenseCategoryPicker(title: String(localized: "Categoría"), accounts: accounts, selection: $line.accountID)
                        MoneyRow(String(localized: "Importe"), minorUnits: $line.amount)
                    }
                    .padding(.vertical, 2)
                    .swipeActions {
                        Button("Quitar", systemImage: "trash", role: .destructive) { remove(line.id) }
                    }
                    .contextMenu {
                        Button("Quitar línea", systemImage: "trash", role: .destructive) { remove(line.id) }
                    }
                }
                Button("Añadir categoría", systemImage: "plus.circle") { addLine() }
                    .frame(minHeight: Metrics.target)
                LabeledContent("Total") { Text(total.money).monospacedDigit().fontWeight(.semibold) }
            } header: {
                SectionLabel(text: String(localized: "Categorías"))
            } footer: {
                Text("Desliza una línea (o usa su menú) para quitarla.")
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        Section {
            TextField("Ej. materiales para una obra", text: $memo, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityLabel("Nota")
        } header: {
            SectionLabel(text: String(localized: "Nota"))
        }
    }

    /// «Repetición» (canvas `MacGastoNuevo`): al guardar, además del gasto, una plantilla que lo repite desde la
    /// siguiente fecha.
    @ViewBuilder
    private var recurrenceSection: some View {
        if !isEditing {
            Section {
                Toggle("Gasto recurrente", isOn: $repeats.animation())
                if repeats {
                    Picker("Frecuencia", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Se repite") {
                        Text(frequency.summary(anchor: date, end: nil)).foregroundStyle(Palette.ink2)
                    }
                    Toggle("Cargo automático", isOn: $autoCharge)
                }
            } header: {
                SectionLabel(text: String(localized: "Repetición"))
            } footer: {
                if repeats {
                    Text(autoCharge
                         ? "Próximo el \(RecurringSchedule.nextStart(after: date, frequency: frequency).shortDate). Cada repetición se registra sola. Lo cambias en Gastos › Recurrentes."
                         : "Próximo el \(RecurringSchedule.nextStart(after: date, frequency: frequency).shortDate). Cada repetición queda «por confirmar» hasta que la registres.")
                }
            }
        }
    }

    // MARK: iPhone

    private var compactForm: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            postedNotice
            amountSection
            detailsSection
            linesSection
            noteSection
            recurrenceSection
            if !isEditing {
                Section {
                    ForEach(receipts) { receipt in
                        HStack(spacing: 12) {
                            ReceiptThumbnail(data: receipt.data, contentType: receipt.type.identifier, side: 48)
                            Text(receipt.name).lineLimit(1)
                        }
                    }
                    .onDelete { receipts.remove(atOffsets: $0) }
                    ReceiptPickerButtons { receipts.append($0) }
                } header: {
                    SectionLabel(text: String(localized: "Recibo"))
                }
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
    }

    // MARK: iPad y Mac (`MacGastoNuevo`)

    /// Recibo a la izquierda (zona para arrastrar una foto o un PDF) y el formulario agrupado a la derecha.
    private var wideForm: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                    ReceiptDropPanel(receipts: $receipts)
                    #if os(macOS)
                    Button("Guardar y nuevo") { save(another: true) }
                        .disabled(!canSave)
                    #endif
                }
                .padding(Metrics.gutter)
            }
            .frame(width: editorWidth >= 700 ? 300 : 260)
            Divider()
            Form {
                amountSection
                detailsSection
                linesSection
                noteSection
                recurrenceSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .keyboardDoneButton()
        }
        .background(Palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 600)
        #endif
    }

    private static let methods: [PaymentMethod] = [.card, .bankTransfer, .cash, .check]

    static func title(for method: PaymentMethod) -> String {
        switch method {
        case .card: String(localized: "Tarjeta")
        case .bankTransfer: String(localized: "Transferencia")
        case .cash: String(localized: "Efectivo")
        case .check: String(localized: "Cheque")
        case .other: String(localized: "Otro")
        }
    }

    // MARK: Líneas

    private func addLine() {
        withAnimation {
            if lines.count == 1, lines[0].details.isEmpty { lines[0].details = memo }
            lines.append(LineDraft(accountID: nil))
        }
    }

    private func remove(_ id: UUID) {
        guard lines.count > 1 else { return }
        withAnimation { lines.removeAll { $0.id == id } }
    }

    // MARK: Guardar

    private var input: ExpenseInput {
        let vendor = vendors.first { $0.id == vendorID }
        let name = payee.trimmingCharacters(in: .whitespaces).isEmpty ? (vendor?.name ?? "") : payee.trimmingCharacters(in: .whitespaces)
        return ExpenseInput(
            date: date, payee: name, vendor: vendor, customer: customers.first { $0.id == customerID },
            paymentAccountID: paymentAccountID, method: method, reference: expense?.reference ?? "", memo: memo,
            salesTaxIncluded: salesTaxIncluded,
            lines: lines.map { ExpenseInput.Line(details: $0.details.isEmpty ? (memo.isEmpty ? name : memo) : $0.details,
                                                 amount: $0.amount, accountID: $0.accountID) }
        )
    }

    private func unlockAndSave() {
        do {
            let books = try Bookkeeper(context: context).unlockedForClosedPeriod(password: hasClosingPassword ? closingPassword : nil)
            closingPassword = ""
            save(another: pendingAnother, using: books)
        } catch {
            closingPassword = ""
            errorMessage = error.localizedDescription
        }
    }

    /// Con `another`, deja el formulario limpio para el siguiente gasto («Guardar y nuevo»).
    private func save(another: Bool = false, using override: Bookkeeper? = nil) {
        let books = override ?? Bookkeeper(context: context)
        let input = self.input
        let created: Expense
        do {
            if let expense {
                try books.updateExpense(expense, with: input)
                unsavedChanges?.remove(editorToken); dismiss()
                return
            }
            created = try books.createExpense(input, post: true)
        } catch let error as BookkeepingError {
            if case .invalidEntry(.periodLocked) = error {
                pendingAnother = another
                askingUnlock = true
            } else {
                errorMessage = error.localizedDescription
            }
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // El gasto ya está registrado; un recibo ilegible o la repetición no lo deshacen, solo se avisa.
        var problems: [String] = []
        var failed: [String] = []
        for receipt in receipts {
            do { try books.attachReceipt(receipt.data, filename: receipt.name, contentType: receipt.type, to: created) }
            catch { failed.append(receipt.name) }
        }
        if !failed.isEmpty {
            problems.append(String(localized: "El gasto se guardó, pero no se pudo adjuntar: \(failed.joined(separator: ", ")). Ábrelo desde la lista para reintentar."))
        }
        if repeats {
            do {
                try books.saveRecurringTemplate(RecurringTemplateInput(
                    name: input.payee, kind: .expense, vendor: input.vendor, payee: input.payee, memo: memo,
                    lines: input.lines, paymentAccountID: paymentAccountID, method: method, frequency: frequency,
                    startDate: RecurringSchedule.nextStart(after: date, frequency: frequency), autoCharge: autoCharge))
            } catch {
                problems.append(String(localized: "El gasto se guardó, pero no se pudo crear la repetición: \(error.localizedDescription)"))
            }
        }
        if !problems.isEmpty {
            errorMessage = problems.joined(separator: " ")
        } else if another {
            lines = [LineDraft()]; payee = ""; vendorID = nil; customerID = nil; memo = ""; receipts = []
            salesTaxIncluded = 0; repeats = false; errorMessage = nil
        } else {
            unsavedChanges?.remove(editorToken); dismiss()
        }
    }
}

/// Fechas de una repetición creada desde un gasto: la primera es la siguiente a la del gasto que ya caiga de hoy en
/// adelante (un gasto de hace dos meses no genera de golpe los meses que pasaron).
enum RecurringSchedule {
    static func nextStart(after date: Date, frequency: RecurrenceFrequency, today: Date = .now, calendar: Calendar = .current) -> Date {
        let anchor = calendar.startOfDay(for: date)
        let limit = calendar.startOfDay(for: today)
        var n = 1
        while n < 1_000 {
            let candidate = frequency.adding(n, to: anchor, calendar: calendar)
            if candidate >= limit { return candidate }
            n += 1
        }
        return frequency.adding(1, to: anchor, calendar: calendar)
    }
}

extension RecurrenceFrequency {
    /// «Mensual», «Trimestral»…
    var title: String {
        switch self {
        case .weekly: String(localized: "Semanal")
        case .monthly: String(localized: "Mensual")
        case .quarterly: String(localized: "Trimestral")
        case .annual: String(localized: "Anual")
        }
    }

    func adding(_ count: Int, to date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .weekOfYear, value: count, to: date) ?? date
        case .monthly: calendar.date(byAdding: .month, value: count, to: date) ?? date
        case .quarterly: calendar.date(byAdding: .month, value: 3 * count, to: date) ?? date
        case .annual: calendar.date(byAdding: .year, value: count, to: date) ?? date
        }
    }

    /// «Cada mes, el día 29 · sin fecha de fin» (canvas `MacGastoNuevo`).
    func summary(anchor: Date, end: Date?, calendar: Calendar = .current) -> String {
        let day = calendar.component(.day, from: anchor)
        let rule: String = switch self {
        case .weekly: String(localized: "Cada semana, el \(anchor.formatted(.appDateTime.weekday(.wide)))")
        case .monthly: String(localized: "Cada mes, el día \(day)")
        case .quarterly: String(localized: "Cada 3 meses, el día \(day)")
        case .annual: String(localized: "Cada año, el \(anchor.dayMonth)")
        }
        let until = end.map { String(localized: "hasta el \($0.shortDate)") } ?? String(localized: "sin fecha de fin")
        return "\(rule) · \(until)"
    }
}
