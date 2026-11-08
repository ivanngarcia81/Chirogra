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
    /// Recibo recién escaneado (Gastos › «Escanear recibo»): se adjunta y se lee al abrir.
    var initialReceipt: ReceiptFile? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Vendor.name) private var vendors: [Vendor]
    @CompanyQuery(sort: \Customer.name) private var customers: [Customer]
    @ActiveCompanyQuery private var companies: [Company]

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
    /// «Impuesto incluido» sigue al monto con la tasa predeterminada de la empresa hasta que el usuario lo escribe.
    @State private var taxFollowsRate = true
    @State private var paymentAccountID: UUID?
    @State private var memo = ""
    @State private var receipts: [ReceiptFile] = []
    @State private var method: PaymentMethod = .card
    @State private var repeats = false
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var autoCharge = true
    @State private var errorMessage: String?
    /// Banca 1.2: corregir un gasto conciliado pide confirmación (`ReconciledChange`).
    @State private var reconciledRetry: ReconciledChangeRetry?
    @State private var editorWidth: CGFloat = 0
    @State private var loaded = false
    /// La fecha (la nueva o la original) cae en un periodo cerrado: se pide la contraseña de cierre para seguir.
    @State private var askingUnlock = false
    @State private var closingPassword = ""
    @State private var pendingAnother = false
    // Recibo leído (`Receipts/`): qué se leyó, de qué archivo y qué campos rellenó (para marcarlos y no pisar lo que
    // el usuario escribió).
    @State private var readingState: ReceiptReadingState = .idle
    @State private var readReceiptID: UUID?
    @State private var scanFilled: Set<ScanField> = []
    @State private var initialDate = Date()
    @State private var creatingScannedVendor = false
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

    // MARK: Impuesto incluido automático

    /// La tasa predeterminada de la empresa (la que cobran sus facturas): en una compra local es la misma del recibo.
    private var defaultTaxComponents: [TaxComponent] {
        (try? Bookkeeper(context: context).taxComponents(groupID: companies.first?.defaultTaxGroupID, on: date)) ?? []
    }

    /// El impuesto que ya va dentro de `gross` con la tasa predeterminada (0 sin tasa).
    private func estimatedTax(in gross: Int64) -> Int64 {
        let components = defaultTaxComponents
        guard gross > 0, !components.isEmpty else { return 0 }
        return gross - SalesTaxCalculator.taxesIncluded(inGross: gross, components: components).base
    }

    /// El impuesto que se guarda: el calculado mientras sigue al monto (aunque el campo aún no se haya refrescado).
    private var effectiveTax: Int64 { taxFollowsRate ? estimatedTax(in: total) : salesTaxIncluded }

    /// Pone en «Impuesto incluido» el calculado, al terminar de escribir el monto (no en cada tecla).
    private func refreshAutoTax() {
        if taxFollowsRate { salesTaxIncluded = estimatedTax(in: total) }
    }

    /// «Austin, TX (8.25%)»: con qué se calculó el impuesto incluido.
    private var defaultTaxLabel: String? {
        let components = defaultTaxComponents
        guard !components.isEmpty else { return nil }
        let rate = components.reduce(0) { $0 + $1.rateMillionths }
        let name = (try? Bookkeeper(context: context).defaultTaxCode())??.name ?? components[0].name
        return "\(name) (\(StateTaxNote.percent(rate)))"
    }

    private var canSave: Bool {
        total > 0 && lines.allSatisfy { $0.amount > 0 && $0.accountID != nil } && paymentAccountID != nil
            && !(payee.trimmingCharacters(in: .whitespaces).isEmpty && vendorID == nil)
            && effectiveTax >= 0 && effectiveTax < total
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
        .onChange(of: receipts.map(\.id)) { _, _ in readNewReceiptIfNeeded() }
        .sheet(isPresented: $creatingScannedVendor) {
            NavigationStack {
                VendorEditorView(initialName: scannedReading?.merchant ?? payee) { vendor in
                    vendorID = vendor.id
                    use(vendor)
                }
            }
            .editorSheetSizing()
        }
        .onChange(of: lines.count) { refreshAutoTax() }
        .onChange(of: salesTaxIncluded) { _, new in
            // Escrito a mano (o puesto en 0): deja de seguir al monto.
            if loaded, new != estimatedTax(in: total) { taxFollowsRate = false }
        }
        .reconciledChangeConfirmation($reconciledRetry) { errorMessage = $0 }
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
            // Si lo guardado es justo lo calculado, al corregir el monto el impuesto se recalcula.
            taxFollowsRate = input.salesTaxIncluded == estimatedTax(in: input.lines.reduce(0) { $0 + $1.amount })
            lines = input.lines.isEmpty ? [LineDraft()] : input.lines.map { LineDraft(details: $0.details, amount: $0.amount, accountID: $0.accountID) }
        } else {
            paymentAccountID = paymentAccounts.first { $0.subtype == .bank }?.id
            initialDate = date
            ReceiptTextRecognizer.warmUp()
            if let initialReceipt, receipts.isEmpty { receipts.append(initialReceipt) }
            #if DEBUG
            if initialReceipt == nil, receipts.isEmpty, let file = ReceiptQA.launchReceipt() { receipts.append(file) }
            #endif
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
                MoneyRow(String(localized: "Monto"), minorUnits: $lines[0].amount, font: .amount(isWide ? 17 : 24),
                         marked: isMarked(.amount), onEndEditing: refreshAutoTax)
            }
            DatePicker(selection: $date, displayedComponents: .date) {
                ScannedLabel(title: String(localized: "Fecha"), marked: isMarked(.date))
            }
            MoneyRow(String(localized: "Impuesto incluido"), minorUnits: $salesTaxIncluded, marked: isMarked(.tax))
        } header: {
            SectionLabel(text: String(localized: "Importe"))
        } footer: {
            if salesTaxIncluded > 0 && salesTaxIncluded >= total {
                Text("El impuesto incluido debe ser menor que el monto.").foregroundStyle(Palette.negative)
            } else if salesTaxIncluded > 0, taxFollowsRate, let label = defaultTaxLabel {
                Text("Subtotal \((total - salesTaxIncluded).money) + impuesto \(salesTaxIncluded.money), calculado con \(label). Si el recibo dice otra cifra, escríbela; si no lleva impuesto, pon 0.")
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
                if isMarked(.merchant) {
                    LabeledContent {
                        TextField("Pagado a (comercio o persona)", text: $payee).labelsHidden()
                            #if os(iOS)
                            .multilineTextAlignment(.trailing)
                            #endif
                    } label: {
                        ScannedLabel(title: String(localized: "Comercio"), marked: true)
                    }
                } else {
                    TextField("Pagado a (comercio o persona)", text: $payee)
                }
            }
            if lines.count == 1 {
                ExpenseCategoryPicker(title: String(localized: "Categoría"), accounts: accounts, selection: $lines[0].accountID,
                                      suggested: isMarked(.category))
            }
            PaymentAccountPicker(title: String(localized: "Cuenta de pago"), accounts: paymentAccounts, selection: $paymentAccountID)
            PaymentMethodPicker(account: paymentAccounts.first { $0.id == paymentAccountID }, selection: $method)
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
                        MoneyRow(String(localized: "Importe"), minorUnits: $line.amount, onEndEditing: refreshAutoTax)
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
            if readingState != .idle {
                Section { scanCard } footer: { scanFooter }
            }
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
                    if readingState != .idle {
                        VStack(alignment: .leading, spacing: 6) {
                            scanCard.padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
                            scanFooter.font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
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


    static func title(for method: PaymentMethod) -> String {
        switch method {
        case .card: String(localized: "Tarjeta")
        case .bankTransfer: String(localized: "Transferencia")
        case .cash: String(localized: "Efectivo")
        case .check: String(localized: "Cheque")
        case .other: String(localized: "Otro")
        }
    }

    // MARK: Recibo leído (`Receipts/`)

    enum ScanField: Hashable { case amount, merchant, date, category, tax }

    private var scannedReading: ReceiptReading? {
        if case .done(let reading) = readingState { return reading }
        return nil
    }

    private var readReceipt: ReceiptFile? { receipts.first { $0.id == readReceiptID } }

    /// El campo se rellenó con el recibo y sigue con ese valor (si el usuario lo cambia, la marca se va).
    private func isMarked(_ field: ScanField) -> Bool {
        guard scanFilled.contains(field), let reading = scannedReading else { return false }
        switch field {
        case .amount: return lines.count == 1 && lines[0].amount == reading.total
        case .merchant: return vendorID == nil ? payee == reading.merchant : vendorID == reading.vendorID
        case .date: return reading.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        case .category: return lines.count == 1 && lines[0].accountID == reading.categoryAccountID
        case .tax: return salesTaxIncluded == reading.salesTax
        }
    }

    /// «Crear proveedor»: el comercio leído no es ninguno de los proveedores y no se ha elegido otro.
    private var unmatchedMerchant: String? {
        guard let reading = scannedReading, reading.vendorID == nil, vendorID == nil,
              let merchant = reading.merchant, payee == merchant else { return nil }
        return merchant
    }

    private var scanCard: some View {
        ReceiptScanCard(state: readingState, receipt: readReceipt, unmatchedMerchant: unmatchedMerchant,
                        onRescan: { file in
                            receipts.removeAll { $0.id == readReceiptID }
                            readReceiptID = nil
                            receipts.append(file)
                        },
                        onCreateVendor: { creatingScannedVendor = true })
    }

    @ViewBuilder
    private var scanFooter: some View {
        if case .done(let reading) = readingState, !reading.isEmpty {
            Text(reading.usedModel
                 ? "Leído con Apple Intelligence en este aparato. Revisa los datos marcados antes de guardar: nada se registra hasta que pulses «Guardar»."
                 : "Revisa los datos marcados antes de guardar: nada se registra hasta que pulses «Guardar».")
        }
    }

    /// Lee el recibo recién adjuntado de un gasto nuevo, si aún no se leyó ninguno (o se quitó el que se leyó).
    private func readNewReceiptIfNeeded() {
        guard !isEditing else { return }
        if let readReceiptID, receipts.contains(where: { $0.id == readReceiptID }) { return }
        guard let file = receipts.last else {
            readReceiptID = nil
            readingState = .idle
            return
        }
        readReceiptID = file.id
        readingState = .reading
        Task {
            let reading = await ReceiptReader.read(file, accounts: accounts, vendors: vendors)
            guard readReceiptID == file.id else { return }
            apply(reading)
            readingState = .done(reading)
            #if DEBUG
            // `-qa.guardarGasto 1` (con `-qa.escanear`): pulsa «Guardar» al terminar de leer (pruebas sin teclado).
            if UserDefaults.standard.bool(forKey: "qa.guardarGasto"), canSave {
                try? await Task.sleep(for: .seconds(2))
                save()
            }
            #endif
        }
    }

    /// Rellena lo que el usuario no ha escrito (o lo que rellenó el recibo anterior y sigue igual).
    private func apply(_ reading: ReceiptReading) {
        var filled: Set<ScanField> = []
        let previous = scanFilled.filter(isMarked)
        if let total = reading.total, lines.count == 1, lines[0].amount == 0 || previous.contains(.amount) {
            lines[0].amount = total
            filled.insert(.amount)
        }
        if let id = reading.vendorID, let vendor = vendors.first(where: { $0.id == id }),
           (vendorID == nil && payee.isEmpty) || previous.contains(.merchant) {
            vendorID = id
            use(vendor)
            filled.insert(.merchant)
        } else if let merchant = reading.merchant, (vendorID == nil && payee.isEmpty) || previous.contains(.merchant) {
            vendorID = nil
            payee = merchant
            filled.insert(.merchant)
        }
        if let scanned = reading.date, Calendar.current.isDate(date, inSameDayAs: initialDate) || previous.contains(.date) {
            date = scanned
            filled.insert(.date)
        }
        if let category = reading.categoryAccountID, lines.count == 1,
           lines[0].accountID == nil || previous.contains(.category) || filled.contains(.merchant) {
            lines[0].accountID = category
            filled.insert(.category)
        }
        if let tax = reading.salesTax, taxFollowsRate || previous.contains(.tax) {
            taxFollowsRate = false
            salesTaxIncluded = tax
            filled.insert(.tax)
        } else {
            refreshAutoTax()
        }
        scanFilled = filled
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
            salesTaxIncluded: effectiveTax,
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
            } else if case .reconciledLines = error, let expense {
                reconciledRetry = ReconciledChangeRetry { books in
                    try books.updateExpense(expense, with: input)
                    unsavedChanges?.remove(editorToken); dismiss()
                }
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
            salesTaxIncluded = 0; taxFollowsRate = true; repeats = false; errorMessage = nil
            readingState = .idle; readReceiptID = nil; scanFilled = []; initialDate = date
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
