import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Contabilidad (canvas: `MacDiario`, `MacLibroMayor`): plan de cuentas, asientos, libro mayor y cierre.
struct AccountingView: View {
    var body: some View {
        List {
            NavigationLink { ChartOfAccountsView() } label: { Label("Plan de cuentas", systemImage: "list.bullet.indent") }
            NavigationLink { JournalListView() } label: { Label("Asientos de diario", systemImage: "doc.plaintext") }
            NavigationLink { LedgerAccountPickerView() } label: { Label("Libro mayor", systemImage: "book.closed") }
            NavigationLink { PeriodCloseView() } label: { Label("Cierre de periodo", systemImage: "lock") }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Contabilidad")
        .headerTitle()
    }
}

extension AccountType {
    var title: String {
        switch self {
        case .asset: String(localized: "Activos")
        case .liability: String(localized: "Pasivos")
        case .equity: String(localized: "Patrimonio")
        case .income: String(localized: "Ingresos")
        case .expense: String(localized: "Gastos")
        }
    }
}

extension AccountSubtype {
    var title: String {
        switch self {
        case .cash: String(localized: "Efectivo")
        case .bank: String(localized: "Banco")
        case .accountsReceivable: String(localized: "Cuentas por cobrar")
        case .undepositedFunds: String(localized: "Fondos no depositados")
        case .inventory: String(localized: "Inventario")
        case .otherCurrentAsset: String(localized: "Otro activo corriente")
        case .fixedAsset: String(localized: "Activo fijo")
        case .otherAsset: String(localized: "Otro activo")
        case .accountsPayable: String(localized: "Cuentas por pagar")
        case .creditCard: String(localized: "Tarjeta de crédito")
        case .salesTaxPayable: String(localized: "Sales tax por pagar")
        case .otherCurrentLiability: String(localized: "Otro pasivo corriente")
        case .longTermLiability: String(localized: "Pasivo a largo plazo")
        case .ownersEquity: String(localized: "Capital")
        case .ownersDraw: String(localized: "Retiros")
        case .retainedEarnings: String(localized: "Resultados acumulados")
        case .openingBalanceEquity: String(localized: "Saldos de apertura")
        case .sales: String(localized: "Ventas")
        case .salesDiscount: String(localized: "Descuentos sobre ventas")
        case .otherIncome: String(localized: "Otros ingresos")
        case .costOfGoodsSold: String(localized: "Costo de ventas")
        case .operatingExpense: String(localized: "Gasto operativo")
        case .otherExpense: String(localized: "Otro gasto")
        }
    }
}

struct ChartOfAccountsView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @ScaledMetric(relativeTo: .body) private var codeWidth: CGFloat = 48
    @Query private var journalLines: [JournalLine]
    @State private var showingNew = false
    @State private var showArchived = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacPlanCuentas` en iPad y Mac (hasta AX3); la lista del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        if isWide { ChartOfAccountsWideView() } else { compactBody }
    }

    @ViewBuilder
    private var compactBody: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        List {
            ForEach(AccountType.allCases, id: \.self) { type in
                Section(heading: type.title) {
                    ForEach(accounts.filter { $0.type == type && (showArchived || !$0.isArchived) }) { account in
                        NavigationLink { LedgerView(account: account) } label: {
                            HStack {
                                Text(account.code).foregroundStyle(Palette.ink3).frame(minWidth: codeWidth, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name).strikethrough(account.isArchived)
                                    Text(account.subtype.title).font(.caption).foregroundStyle(Palette.ink3)
                                }
                                Spacer()
                                Text(ledger.balance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink2)
                            }
                        }
                        .swipeActions {
                            if !account.isSystem {
                                Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                            }
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        .navigationTitle("Plan de cuentas")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddButton(title: "Nueva cuenta") { showingNew = true } }
            ToolbarItem { Toggle("Archivadas", isOn: $showArchived).headerButton() }
        }
        .sheet(isPresented: $showingNew) { NavigationStack { AccountEditorView() } }
    }
}

struct AccountEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query private var accounts: [Account]
    @State private var code = ""
    @State private var name = ""
    @State private var subtype: AccountSubtype = .operatingExpense

    private var codeTaken: Bool { accounts.contains { $0.code == code && !code.isEmpty } }

    var body: some View {
        Form {
            TextField("Código", text: $code)
            if codeTaken { Text("Ya existe una cuenta con ese código.").foregroundStyle(Palette.negative).font(.footnote) }
            TextField("Nombre", text: $name)
            Picker("Tipo", selection: $subtype) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Section(heading: type.title) {
                        ForEach(AccountSubtype.allCases.filter { $0.accountType == type }, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Nueva cuenta")
        .inlineTitle()
        .discardableEditor(tracking: "\(code)|\(name)|\(subtype)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    context.insert(Account(code: code, name: name, subtype: subtype))
                    try? context.save()
                    unsavedChanges?.remove(editorToken); dismiss()
                }
                .disabled(name.isEmpty || codeTaken)
                .headerButton()
            }
        }
    }
}

/// Asientos de diario. En iPhone, lista; en iPad y Mac, tabla Nº · FECHA · CONCEPTO · ORIGEN · IMPORTE.
struct JournalListView: View {
    @Query(sort: [SortDescriptor(\JournalEntry.date, order: .reverse), SortDescriptor(\JournalEntry.number, order: .reverse)])
    private var entries: [JournalEntry]
    @State private var showingEditor = false
    @State private var selection: JournalEntry.ID?
    @State private var opened: JournalEntry?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    private var isWide: Bool {
        #if os(iOS)
        if sizeClass == .compact { return false }
        #endif
        return dynamicTypeSize < .accessibility4 && !entries.isEmpty
    }

    var body: some View {
        Group {
            if isWide { table } else { list }
        }
        .navigationTitle("Asientos de diario")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddButton(title: "Nuevo asiento") { showingEditor = true } }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { JournalEntryEditorView() }
                .presentationSizing(.page)
        }
        .navigationDestination(item: $opened) { JournalEntryDetailView(entry: $0) }
    }

    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn("Nº") { entry in
                Text("#\(entry.number)").monospacedDigit().foregroundStyle(Palette.ink3)
            }
            .width(min: 50, ideal: 64, max: 90)
            TableColumn("Fecha") { entry in Text(entry.date.shortDate).monospacedDigit().foregroundStyle(Palette.ink) }
                .width(min: 90, ideal: 120, max: 160)
            TableColumn("Concepto") { entry in
                HStack(spacing: 8) {
                    Text(entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo).lineLimit(1).foregroundStyle(Palette.ink)
                    if entry.isReversed || entry.reversesEntryID != nil {
                        StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"),
                                   foreground: Palette.ink3, background: Palette.surface2)
                    }
                }
            }
            TableColumn("Origen") { entry in Text(entry.source.title).foregroundStyle(Palette.ink2).lineLimit(1) }
                .width(min: 100, ideal: 160, max: 220)
            TableColumn("Importe") { entry in
                Text(entry.totalDebits.money).monospacedDigit().foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 100, ideal: 130, max: 180)
        }
        // Tocar (iPad) o doble clic (Mac) abre el asiento.
        .contextMenu(forSelectionType: JournalEntry.ID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            opened = entries.first { ids.contains($0.id) }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private var list: some View {
        List {
            if entries.isEmpty {
                EmptyStateView(systemImage: "doc.plaintext", title: String(localized: "Sin asientos"), message: String(localized: "Los documentos generan asientos automáticamente; también puedes crear uno manual."))
            }
            ForEach(entries) { entry in
                NavigationLink { JournalEntryDetailView(entry: entry) } label: {
                    LedgerRow(title: entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo,
                              subtitle: "#\(entry.number) · \(entry.date.shortDate) · \(entry.source.title)") {
                        EmptyView()
                    } trailing: {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                            Text(entry.totalDebits.money).monospacedDigit()
                            if entry.isReversed || entry.reversesEntryID != nil {
                                StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"), foreground: Palette.ink3, background: Palette.surface2)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
    }
}

extension EntrySource {
    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .invoice: String(localized: "Factura")
        case .creditNote: String(localized: "Nota de crédito")
        case .paymentReceived: String(localized: "Cobro")
        case .bill: String(localized: "Factura de proveedor")
        case .billPayment: String(localized: "Pago a proveedor")
        case .expense: String(localized: "Gasto")
        case .salesTaxPayment: String(localized: "Pago de sales tax")
        case .customerRefund: String(localized: "Reembolso a cliente")
        case .reversal: String(localized: "Reversión")
        case .opening: String(localized: "Saldos iniciales")
        }
    }
}

/// Editor de asiento: totales en vivo y aviso hasta que débitos = créditos. En iPhone es un formulario; en iPad y
/// Mac sigue `MacDiario`: tabla de líneas a la izquierda y el plan de cuentas a la derecha.
struct JournalEntryEditorView: View {
    struct LineDraft: Identifiable {
        let id = UUID()
        var accountID: UUID?
        var memo = ""
        var debit: Int64 = 0
        var credit: Int64 = 0
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 120
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var companies: [Company]

    @State private var date = Date()
    @State private var editorWidth: CGFloat = 0
    @State private var memo = ""
    @State private var lines: [LineDraft] = [LineDraft(), LineDraft()]
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var postable: [Account] { accounts.filter(\.isPostable) }

    /// Totales de todo lo escrito, también de las líneas sin cuenta (el asiento sólo cuenta las que la tienen).
    private var typedDebits: Int64 { lines.reduce(0) { $0 + $1.debit } }
    private var typedCredits: Int64 { lines.reduce(0) { $0 + $1.credit } }

    /// Número (desde 1) de la primera línea con importe y sin cuenta.
    private var lineWithoutAccount: Int? {
        lines.firstIndex { $0.accountID == nil && ($0.debit != 0 || $0.credit != 0) }.map { $0 + 1 }
    }

    private var draft: JournalEntryDraft {
        JournalEntryDraft(date: date, memo: memo, source: .manual, lines: lines.compactMap { line in
            guard let accountID = line.accountID else { return nil }
            return JournalLineDraft(accountID: accountID, debit: line.debit, credit: line.credit, memo: line.memo)
        })
    }

    private var validationErrors: [JournalValidationError] {
        guard let validator = try? books.validator() else { return [] }
        return validator.errors(for: draft)
    }

    /// Diseño de `MacDiario` en iPad y Mac, salvo con los dos tamaños de accesibilidad más grandes.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass == .compact { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        let entry = draft
        let isValid = validationErrors.isEmpty && lines.allSatisfy { $0.accountID != nil || ($0.debit == 0 && $0.credit == 0) }
        Group {
            if isWide { wideEditor(entry) } else { formEditor(entry) }
        }
        .navigationTitle("Nuevo asiento")
        .inlineTitle()
        .discardableEditor(tracking: "\(date)|\(memo)|" + lines.map { "\($0.accountID?.uuidString ?? "")/\($0.debit)/\($0.credit)" }.joined(separator: ";"), token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Registrar asiento", action: save).disabled(!isValid).headerButton() }
        }
    }

    private func formEditor(_ entry: JournalEntryDraft) -> some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Concepto", text: $memo)
            }
            Section {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        AccountPicker(title: String(localized: "Cuenta"), accounts: postable, selection: $line.accountID)
                        TextField("Descripción", text: $line.memo).font(.subheadline)
                        HStack {
                            MoneyField(title: String(localized: "Débito"), minorUnits: $line.debit)
                            MoneyField(title: String(localized: "Crédito"), minorUnits: $line.credit)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
            } header: {
                SectionLabel(text: String(localized: "Líneas"))
            } footer: {
                HStack {
                    Text("Totales")
                    Spacer()
                    Text("Debe \(typedDebits.money)  ·  Haber \(typedCredits.money)").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
            }

            Section {
                statusBanner(entry)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .screenBackground()
    }

    // MARK: iPad y Mac (`MacDiario`)

    private func wideEditor(_ entry: JournalEntryDraft) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                    HStack(alignment: .bottom, spacing: 12) {
                        fieldLabel(String(localized: "Fecha")) {
                            DatePicker("Fecha", selection: $date, displayedComponents: .date).labelsHidden()
                        }
                        .fixedSize()
                        fieldLabel(String(localized: "Concepto")) {
                            TextField("Concepto", text: $memo).fieldBox()
                        }
                    }
                    linesTable(entry)
                    statusBanner(entry)
                    if let lockDate = companies.first?.lockDate {
                        Label("El periodo está cerrado hasta el \(lockDate.shortDate). Para registrar con una fecha anterior, cambia el cierre en Cierre de periodo.",
                              systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                // El plan de cuentas de consulta sólo si queda sitio para la tabla (en la hoja del iPad, no).
                if editorWidth >= 1000 { chartOfAccounts.frame(width: 300) }
            }
            .padding(20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
        .background(Palette.background)
    }

    private func fieldLabel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            content()
        }
    }

    /// Tabla de líneas: # · CUENTA · DESCRIPCIÓN · DÉBITO · CRÉDITO, con «Añadir línea» y totales al pie.
    private func linesTable(_ entry: JournalEntryDraft) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
                Text("Descripción").frame(maxWidth: .infinity, alignment: .leading)
                Text("Débito").frame(width: amountWidth, alignment: .trailing)
                Text("Crédito").frame(width: amountWidth, alignment: .trailing)
                Color.clear.frame(width: 28, height: 1)
            }
            .font(.label).tracking(0.6).textCase(.uppercase).foregroundStyle(Palette.ink3)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityHidden(true)

            ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                Divider()
                HStack(spacing: 12) {
                    Text("\(index + 1)").foregroundStyle(Palette.ink3).frame(width: 24, alignment: .leading)
                        .accessibilityHidden(true)
                    AccountPicker(title: String(localized: "Cuenta"), accounts: postable, selection: $line.accountID)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Descripción", text: $line.memo).fieldBox().frame(maxWidth: .infinity)
                    MoneyField(title: String(localized: "Débito"), minorUnits: $line.debit)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountWidth)
                    MoneyField(title: String(localized: "Crédito"), minorUnits: $line.credit)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountWidth)
                    Button { lines.remove(at: index) } label: {
                        Image(systemName: "minus.circle").frame(width: 28, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
                    .disabled(lines.count <= 2)
                    .accessibilityLabel("Quitar la línea \(index + 1)")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }

            Divider()
            HStack(spacing: 12) {
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.brand)
                    .frame(minHeight: 44)
                Spacer()
                Text("Totales").fontWeight(.semibold).foregroundStyle(Palette.ink2)
                Text(typedDebits.money).fontWeight(.bold).frame(width: amountWidth, alignment: .trailing)
                Text(typedCredits.money).fontWeight(.bold).frame(width: amountWidth, alignment: .trailing)
                Color.clear.frame(width: 28, height: 1)
            }
            .monospacedDigit()
            .padding(.horizontal, 16).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
        }
        .card(padding: 0)
    }

    /// Plan de cuentas de consulta (`MacDiario`, columna derecha): grupos por tipo con código, nombre y saldo.
    private var chartOfAccounts: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let active = accounts.filter { !$0.isArchived }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan de cuentas").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(active.count) cuentas").font(.caption).foregroundStyle(Palette.ink3)
            }
            ForEach(AccountType.allCases, id: \.self) { type in
                Text(type.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 6)
                ForEach(active.filter { $0.type == type }) { account in
                    HStack(spacing: 8) {
                        Text(account.code).foregroundStyle(Palette.ink3).frame(width: 40, alignment: .leading)
                        Text(account.name).foregroundStyle(Palette.ink2).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ledger.balance(of: account).money).foregroundStyle(Palette.ink3).lineLimit(1)
                    }
                    .font(.footnote)
                    .monospacedDigit()
                    .padding(.leading, 12)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func statusBanner(_ entry: JournalEntryDraft) -> some View {
        let balanced = entry.isBalanced && entry.totalDebits > 0
        let message: String = if let line = lineWithoutAccount {
            String(localized: "Elige la cuenta de la línea \(line)")
        } else if balanced {
            validationErrors.first?.localizedMessage ?? String(localized: "El asiento cuadra: débitos = créditos")
        } else if entry.difference > 0 {
            String(localized: "No cuadra: faltan créditos por \(abs(entry.difference).money)")
        } else if entry.difference < 0 {
            String(localized: "No cuadra: faltan débitos por \(abs(entry.difference).money)")
        } else {
            String(localized: "Escribe los importes al debe y al haber")
        }
        let ok = balanced && validationErrors.isEmpty && lineWithoutAccount == nil
        Label(message, systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ok ? Palette.positive : Palette.negative)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ok ? Palette.positiveWash : Palette.negativeWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func save() {
        do {
            try books.post(draft)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JournalEntryDetailView: View {
    /// Lo que lee VoiceOver de una línea del asiento, como frase completa para traducirla entera.
    static func spokenLine(account: String, memo: String, debit: Int64, credit: Int64) -> String {
        let name = memo.isEmpty ? account : "\(account), \(memo)"
        return debit > 0 ? String(localized: "\(name), debe \(debit.money)") : String(localized: "\(name), haber \(credit.money)")
    }

    let entry: JournalEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 100

    /// Fila con columnas Debe/Haber; con tamaños de accesibilidad los importes van debajo, rotulados.
    @ViewBuilder
    private func entryRow(_ title: String, memo: String, debit: Int64, credit: Int64, bold: Bool = false) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(bold ? .semibold : .regular)
                if !memo.isEmpty { Text(memo).font(.caption).foregroundStyle(Palette.ink3) }
                if debit > 0 { Text("Debe \(debit.money)") }
                if credit > 0 { Text("Haber \(credit.money)") }
            }
            .monospacedDigit()
        } else {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).fontWeight(bold ? .semibold : .regular)
                    if !memo.isEmpty { Text(memo).font(.caption).foregroundStyle(Palette.ink3) }
                }
                Spacer()
                Text(debit > 0 ? debit.money : "").frame(width: columnWidth, alignment: .trailing)
                Text(credit > 0 ? credit.money : "").frame(width: columnWidth, alignment: .trailing)
            }
            .fontWeight(bold ? .semibold : .regular)
            .monospacedDigit()
        }
    }
    @State private var errorMessage: String?
    @State private var confirming = false

    var body: some View {
        List {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Número", value: "#\(entry.number)")
                LabeledContent("Fecha", value: entry.date.shortDate)
                LabeledContent("Origen", value: entry.source.title)
                if !entry.memo.isEmpty { LabeledContent("Concepto", value: entry.memo) }
            }
            Section {
                ForEach(entry.sortedLines) { line in
                    let account = line.account?.displayName ?? String(localized: "Cuenta eliminada")
                    entryRow(account, memo: line.memo, debit: line.debit, credit: line.credit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.spokenLine(account: account, memo: line.memo, debit: line.debit, credit: line.credit))
                }
                entryRow(String(localized: "Totales"), memo: "", debit: entry.totalDebits, credit: entry.totalCredits, bold: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Totales: debe \(entry.totalDebits.money), haber \(entry.totalCredits.money)")
            } header: {
                HStack {
                    Text("Cuenta")
                    Spacer()
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Debe").frame(width: columnWidth, alignment: .trailing)
                        Text("Haber").frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.label).tracking(0.6).textCase(.uppercase).foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
            }
            if entry.source == .manual && !entry.isReversed && entry.reversesEntryID == nil {
                Section {
                    Button("Revertir asiento", role: .destructive) { confirming = true }
                } footer: {
                    Text("Los asientos contabilizados no se editan ni se borran: se corrigen con un asiento de reversión.")
                }
            }
        }
        .screenBackground()
        .navigationTitle("Asiento #\(entry.number)")
        .inlineTitle()
        .confirmationDialog("¿Revertir este asiento?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Revertir", role: .destructive) {
                do { try Bookkeeper(context: context).reverse(entry) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

struct LedgerAccountPickerView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    var body: some View {
        List(accounts.filter { !$0.isArchived }) { account in
            NavigationLink(account.displayName) { LedgerView(account: account) }
                .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .navigationTitle("Libro mayor")
        .headerTitle()
    }
}

/// Libro mayor de una cuenta con saldo acumulado (canvas: `MacLibroMayor`).
/// El signo de cada movimiento sigue la naturaleza de la cuenta: en pasivo, patrimonio e ingreso
/// un crédito aumenta el saldo (+); en activo y gasto lo aumenta un débito.
struct LedgerView: View {
    let account: Account
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filterByDate = false
    @State private var from = DateInterval.month(containing: .now).start
    @State private var to = Date()

    /// Rango de fechas completo de los días elegidos (del inicio de `from` al final de `to`).
    private var range: (from: Date, to: Date)? {
        guard filterByDate else { return nil }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: to)) ?? to
        return (calendar.startOfDay(for: from), end)
    }

    /// Lo que lee VoiceOver de un movimiento: una frase completa por caso, para que se traduzca entera.
    static func spokenMovement(_ row: AccountLedger.Row) -> String {
        let memo = row.movement.memo, date = row.movement.date.shortDate, balance = row.balance.money
        let amount = max(row.movement.debit, row.movement.credit).money
        switch (row.movement.debit > 0, row.increasesBalance) {
        case (true, true): return String(localized: "\(memo), \(date), débito de \(amount), aumenta el saldo a \(balance)")
        case (true, false): return String(localized: "\(memo), \(date), débito de \(amount), reduce el saldo a \(balance)")
        case (false, true): return String(localized: "\(memo), \(date), crédito de \(amount), aumenta el saldo a \(balance)")
        case (false, false): return String(localized: "\(memo), \(date), crédito de \(amount), reduce el saldo a \(balance)")
        }
    }

    private var ledger: AccountLedger { Self.ledger(for: account, from: range?.from, to: range?.to) }

    /// Movimientos contabilizados de la cuenta con saldo acumulado; también lo usa `LedgerBrowserView`.
    static func ledger(for account: Account, from: Date?, to: Date?) -> AccountLedger {
        let movements = (account.lines ?? []).compactMap { line -> LedgerMovement? in
            guard let entry = line.entry, entry.status == .posted else { return nil }
            return LedgerMovement(id: line.id, date: entry.date, memo: entry.memo, debit: line.debit, credit: line.credit)
        }
        return ReportBuilder.accountLedger(account: account.ledgerAccount, movements: movements, from: from, to: to)
    }

    var body: some View {
        let ledger = ledger
        List {
            Section {
                // El nombre también va aquí: en el título se recorta con «…» si es largo o el texto es grande.
                LabeledContent("Cuenta", value: account.displayName)
                LabeledContent("Tipo", value: "\(account.type.title) · \(account.subtype.title)")
                LabeledContent("Aumenta con", value: account.type.normalBalance == .debit ? String(localized: "Débitos") : String(localized: "Créditos"))
                Toggle("Filtrar por fechas", isOn: $filterByDate)
                if filterByDate {
                    DatePicker("Desde", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("Hasta", selection: $to, in: from..., displayedComponents: .date)
                }
            }
            Section {
                if filterByDate { LabeledContent("Saldo inicial", value: ledger.openingBalance.money) }
                LabeledContent("Débitos", value: ledger.totalDebit.money)
                LabeledContent("Créditos", value: ledger.totalCredit.money)
                LabeledContent(filterByDate ? "Saldo final" : "Saldo", value: ledger.closingBalance.money).font(.headline)
            }
            .monospacedDigit()
            Section {
                if ledger.rows.isEmpty { Text("Sin movimientos").foregroundStyle(Palette.ink3) }
                ForEach(ledger.rows.reversed()) { row in
                    AdaptiveRow(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo).lineLimit(2)
                            Text(row.movement.debit > 0 ? "\(row.movement.date.shortDate) · Débito" : "\(row.movement.date.shortDate) · Crédito")
                                .font(.caption).foregroundStyle(Palette.ink3)
                        }
                    } trailing: {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 2) {
                            Text("\(row.increasesBalance ? "+" : "−")\(abs(row.effect).money)")
                                .foregroundStyle(row.increasesBalance ? Palette.ink : Palette.outflow)
                            Text("Saldo \(row.balance.money)").font(.caption).foregroundStyle(Palette.ink3)
                        }
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Self.spokenMovement(row))
                }
            } header: {
                SectionLabel(text: String(localized: "Movimientos"))
            } footer: {
                Text("+ aumenta el saldo de la cuenta y − lo reduce, según su naturaleza.")
            }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle(account.name)
        .headerTitle()
    }
}

/// Cierre de periodo: fecha hasta la que no se admiten asientos (DISEÑO §4.2).
struct PeriodCloseView: View {
    @Query private var companies: [Company]
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacCierre` en iPad y Mac (hasta AX3); la lista del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        if isWide { PeriodCloseWideView() } else { compactBody }
    }

    private var compactBody: some View {
        Form {
            if let company = companies.first {
                Section {
                    Toggle("Cerrar periodos", isOn: Binding(
                        get: { company.lockDate != nil },
                        set: { company.lockDate = $0 ? Calendar.current.date(byAdding: .day, value: -1, to: DateInterval.month(containing: .now).start) : nil }
                    ))
                    if let lockDate = company.lockDate {
                        DatePicker("Cerrado hasta", selection: Binding(get: { lockDate }, set: { company.lockDate = $0 }), displayedComponents: .date)
                    }
                } footer: {
                    Text("No se podrá registrar nada con fecha igual o anterior al cierre. Así los reportes que ya entregaste no cambian.")
                }
            }
        }
        .screenBackground()
        .navigationTitle("Cierre de periodo")
        .headerTitle()
        .onDisappear { try? context.save() }
    }
}
