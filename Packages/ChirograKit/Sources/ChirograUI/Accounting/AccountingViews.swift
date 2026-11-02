import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Contabilidad del iPhone (canvas `Mas` · Contabilidad): plan de cuentas, asientos, libro mayor y cierre, como filas
/// de Ajustes con su icono de color. En iPad y Mac son subsecciones de la barra lateral.
struct AccountingView: View {
    @Query private var accounts: [Account]
    @Query private var entries: [JournalEntry]
    @Query private var companies: [Company]

    var body: some View {
        List {
            Section {
                row(String(localized: "Plan de cuentas"), String(localized: "\(accounts.filter { !$0.isArchived }.count) cuentas"),
                    "list.bullet.indent", Palette.blue) { ChartOfAccountsView() }
                row(String(localized: "Asientos de diario"), String(localized: "\(entries.count) asientos"),
                    "doc.plaintext", Palette.indigo) { JournalListView() }
                row(String(localized: "Libro mayor"), String(localized: "Movimientos por cuenta"),
                    "book.closed", Palette.teal) { LedgerAccountPickerView() }
                row(String(localized: "Cierre de periodo"),
                    companies.first?.lockDate.map { String(localized: "Cerrado hasta el \($0.shortDate)") } ?? String(localized: "Sin cierre"),
                    "lock", Palette.gray) { PeriodCloseView() }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Contabilidad")
        .headerTitle()
    }

    private func row<Destination: View>(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            LedgerRow(title: title, subtitle: subtitle) { IconTile(systemImage: symbol, foreground: color) } trailing: { EmptyView() }
        }
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

/// Plan de cuentas del iPhone: grupos por tipo con código, nombre, tipo de detalle y saldo (canvas `MacPlanCuentas`,
/// en lista). Cada cuenta abre su libro mayor.
struct ChartOfAccountsView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @ScaledMetric(relativeTo: .body) private var codeWidth: CGFloat = 48
    @Query private var journalLines: [JournalLine]
    @State private var showingNew = false
    @State private var showArchived = false
    @State private var query = ""

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let text = query.trimmingCharacters(in: .whitespaces)
        List {
            ForEach(AccountType.allCases, id: \.self) { type in
                let rows = accounts.filter {
                    $0.type == type && (showArchived || !$0.isArchived)
                        && (text.isEmpty || $0.code.localizedStandardContains(text) || $0.name.localizedStandardContains(text))
                }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { account in
                            NavigationLink { LedgerView(account: account) } label: {
                                HStack(spacing: 12) {
                                    Text(account.code).foregroundStyle(Palette.ink2).monospacedDigit().frame(minWidth: codeWidth, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(account.name).strikethrough(account.isArchived).foregroundStyle(Palette.ink)
                                        Text(account.subtype.title).font(.footnote).foregroundStyle(Palette.ink2)
                                    }
                                    Spacer(minLength: 8)
                                    Text(ledger.balance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .swipeActions {
                                if !account.isSystem {
                                    Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(type.title)
                            Spacer()
                            Text(String(localized: "\(rows.count) cuentas"))
                        }
                        .font(.label).foregroundStyle(Palette.ink2).textCase(nil)
                    }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        .searchable(text: $query, prompt: Text("Código o nombre"))
        .navigationTitle("Plan de cuentas")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddButton(title: "Nueva cuenta") { showingNew = true } }
            ToolbarItem { Toggle("Archivadas", isOn: $showArchived).headerButton() }
        }
        .sheet(isPresented: $showingNew) { NavigationStack { AccountEditorView() }.editorSheetSizing() }
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
            Section {
                TextField("Código", text: $code)
                TextField("Nombre", text: $name)
                Picker("Tipo", selection: $subtype) {
                    ForEach(AccountType.allCases, id: \.self) { type in
                        Section(heading: type.title) {
                            ForEach(AccountSubtype.allCases.filter { $0.accountType == type }, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
            } header: {
                SectionLabel(text: String(localized: "Cuenta"))
            } footer: {
                if codeTaken {
                    Text("Ya existe una cuenta con ese código.").foregroundStyle(Palette.negative)
                } else {
                    Text("El tipo decide dónde aparece la cuenta en los reportes.")
                }
            }
        }
        .formStyle(.grouped)
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

/// Asientos de diario del iPhone: concepto, número, fecha y origen, e importe.
struct JournalListView: View {
    @Query(sort: [SortDescriptor(\JournalEntry.date, order: .reverse), SortDescriptor(\JournalEntry.number, order: .reverse)])
    private var entries: [JournalEntry]
    @State private var showingEditor = false

    var body: some View {
        List {
            if entries.isEmpty {
                EmptyStateView(systemImage: "doc.plaintext", title: String(localized: "Sin asientos"), message: String(localized: "Los documentos generan asientos automáticamente; también puedes crear uno manual."))
            }
            Section {
                ForEach(entries) { entry in
                    NavigationLink { JournalEntryDetailView(entry: entry) } label: { JournalEntryRow(entry: entry) }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        .navigationTitle("Asientos de diario")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddButton(title: "Nuevo asiento") { showingEditor = true } }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { JournalEntryEditorView() }
                .presentationSizing(.page)
        }
    }
}

/// Fila de asiento: concepto, número, fecha y origen, importe y si está revertido.
struct JournalEntryRow: View {
    let entry: JournalEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerRow(title: entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo,
                  subtitle: "#\(entry.number) · \(entry.date.shortDate) · \(entry.source.title)") {
            EmptyView()
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text(entry.totalDebits.money).monospacedDigit().foregroundStyle(Palette.ink)
                if entry.isReversed || entry.reversesEntryID != nil {
                    StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"),
                               foreground: Palette.ink2, background: Palette.surface2, compact: true, dot: Palette.gray)
                }
            }
        }
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
/// Mac sigue `MacDiario`: datos del asiento en una caja, la tabla de líneas, el estado y, si cabe, el plan de cuentas.
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
    @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 110
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
            } header: {
                SectionLabel(text: String(localized: "Datos del asiento"))
            }
            Section {
                ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                    VStack(alignment: .leading, spacing: 8) {
                        AccountPicker(title: String(localized: "Cuenta \(index + 1)"), accounts: postable, selection: $line.accountID)
                        TextField("Descripción", text: $line.memo).font(.subheadline)
                        HStack {
                            MoneyField(title: String(localized: "Débito"), minorUnits: $line.debit).fieldBox()
                            MoneyField(title: String(localized: "Crédito"), minorUnits: $line.credit).fieldBox()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
            } header: {
                SectionLabel(text: String(localized: "Líneas del asiento"))
            } footer: {
                Text("Los débitos deben ser iguales a los créditos.")
            }

            Section {
                statusBanner(entry)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .screenBackground()
    }

    // MARK: iPad y Mac (`MacDiario`)

    private func wideEditor(_ entry: JournalEntryDraft) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                    entryBox
                    VStack(alignment: .leading, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                linesTitle
                                Spacer(minLength: 12)
                                linesNote
                            }
                            VStack(alignment: .leading, spacing: 2) { linesTitle; linesNote }
                        }
                        linesTable(entry)
                    }
                    statusBanner(entry)
                    if let lockDate = companies.first?.lockDate {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "lock").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                            Text("El periodo está cerrado hasta el \(lockDate.shortDate). Para registrar con una fecha anterior, cambia el cierre en Cierre de periodo.")
                                .font(.footnote).foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 0)
                    }
                }
                // El plan de cuentas de consulta sólo si queda sitio para la tabla (en la hoja del iPad, no).
                if editorWidth >= 1000 { chartOfAccounts.frame(width: 300) }
            }
            .padding(Metrics.gutter)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
        .background(Palette.background)
    }

    private var linesTitle: some View {
        Text("Líneas del asiento").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
    }

    private var linesNote: some View {
        Text("Los débitos deben ser iguales a los créditos").font(.footnote).foregroundStyle(Palette.ink2)
    }

    /// Datos del asiento (canvas: caja con filas «Fecha» y «Concepto», la etiqueta a la izquierda y el campo a la derecha).
    private var entryBox: some View {
        VStack(spacing: 0) {
            formRow(String(localized: "Fecha")) {
                DatePicker("Fecha", selection: $date, displayedComponents: .date).labelsHidden()
            }
            Divider()
            formRow(String(localized: "Concepto")) {
                TextField("Concepto", text: $memo).fieldBox().frame(maxWidth: 440)
            }
        }
        .padding(.horizontal, 12)
        .card(padding: 0)
    }

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(Palette.ink).frame(minWidth: 90, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
        .frame(minHeight: Self.formRowHeight)
    }

    #if os(macOS)
    private static let formRowHeight: CGFloat = 38
    #else
    private static let formRowHeight: CGFloat = 52
    #endif

    /// Tabla de líneas: # · Cuenta · Descripción · Débito · Crédito, con «Añadir línea» y totales al pie.
    private func linesTable(_ entry: JournalEntryDraft) -> some View {
        TableCard {
            Text("#").frame(width: 22, alignment: .leading)
            Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
            Text("Descripción").frame(maxWidth: .infinity, alignment: .leading)
            Text("Débito").frame(width: amountWidth, alignment: .trailing)
            Text("Crédito").frame(width: amountWidth, alignment: .trailing)
            Color.clear.frame(width: Metrics.target, height: 1)
        } rows: {
            ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                TableRow {
                    Text("\(index + 1)").foregroundStyle(Palette.ink2).frame(width: 22, alignment: .leading)
                        .accessibilityHidden(true)
                    AccountPicker(title: String(localized: "Cuenta de la línea \(index + 1)"), accounts: postable, selection: $line.accountID)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Descripción", text: $line.memo).fieldBox().frame(maxWidth: .infinity)
                    MoneyField(title: String(localized: "Débito"), minorUnits: $line.debit)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountWidth)
                    MoneyField(title: String(localized: "Crédito"), minorUnits: $line.credit)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountWidth)
                    Button { lines.remove(at: index) } label: {
                        Image(systemName: "minus.circle").frame(width: Metrics.target, height: Metrics.target)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink2)
                    .disabled(lines.count <= 2)
                    .accessibilityLabel("Quitar la línea \(index + 1)")
                }
                .padding(.vertical, 2)
                .zebra(index)
            }
            TableRow {
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.brand)
                    .frame(minHeight: Metrics.target)
                Spacer()
                Text("Totales").fontWeight(.semibold).foregroundStyle(Palette.ink2)
                Text(typedDebits.money).fontWeight(.bold).frame(width: amountWidth, alignment: .trailing)
                Text(typedCredits.money).fontWeight(.bold).frame(width: amountWidth, alignment: .trailing)
                Color.clear.frame(width: Metrics.target, height: 1)
            }
            .background(Palette.surface)
            .accessibilityElement(children: .contain)
        }
    }

    /// Plan de cuentas de consulta (`MacDiario`, inspector): grupos por tipo con código, nombre y saldo.
    private var chartOfAccounts: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let active = accounts.filter { !$0.isArchived }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: String(localized: "Plan de cuentas"))
                Spacer()
                Text("\(active.count) cuentas").font(.footnote).foregroundStyle(Palette.ink2)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Text(type.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 6)
                    ForEach(active.filter { $0.type == type }) { account in
                        HStack(spacing: 8) {
                            Text(account.code).foregroundStyle(Palette.ink2).frame(width: 40, alignment: .leading)
                            Text(account.name).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(ledger.balance(of: account).money).foregroundStyle(Palette.ink2).lineLimit(1)
                        }
                        .font(.footnote)
                        .monospacedDigit()
                        .padding(.leading, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .card(padding: 12)
        }
    }

    /// Estado del asiento (canvas `MacDiario`): círculo verde o rojo, el mensaje, los totales y la diferencia.
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
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(ok ? Palette.green : Palette.red, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(message).font(.subheadline.weight(.semibold)).foregroundStyle(ok ? Palette.positive : Palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Débitos \(typedDebits.money) · Créditos \(typedCredits.money)").font(.footnote).foregroundStyle(Palette.ink2)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(abs(typedDebits - typedCredits).money).font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(ok ? Palette.positive : Palette.negative)
                .accessibilityLabel("Diferencia \(abs(typedDebits - typedCredits).money)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
        .accessibilityElement(children: .combine)
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

/// Un asiento contabilizado: número, fecha, origen y concepto, y sus líneas con el debe y el haber. Los manuales se
/// corrigen con una reversión.
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
                if !memo.isEmpty { Text(memo).font(.footnote).foregroundStyle(Palette.ink2) }
                if debit > 0 { Text("Debe \(debit.money)") }
                if credit > 0 { Text("Haber \(credit.money)") }
            }
            .monospacedDigit()
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(bold ? .semibold : .regular)
                    if !memo.isEmpty { Text(memo).font(.footnote).foregroundStyle(Palette.ink2) }
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
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo)
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                    Text(entry.totalDebits.money).font(.amount(40)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                    if entry.isReversed || entry.reversesEntryID != nil {
                        StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"),
                                   foreground: Palette.ink2, background: Palette.surface2, dot: Palette.gray)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            Section {
                LabeledContent("Número", value: "#\(entry.number)")
                LabeledContent("Fecha", value: entry.date.shortDate)
                LabeledContent("Origen", value: entry.source.title)
                if !entry.memo.isEmpty { LabeledContent("Concepto", value: entry.memo) }
            } header: {
                SectionLabel(text: String(localized: "Asiento"))
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
                .font(.label).foregroundStyle(Palette.ink2).textCase(nil)
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
        .formStyle(.grouped)
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

/// Libro mayor del iPhone: elegir la cuenta, por tipo.
struct LedgerAccountPickerView: View {
    @Query(sort: \Account.code) private var accounts: [Account]

    var body: some View {
        List {
            ForEach(AccountType.allCases, id: \.self) { type in
                let rows = accounts.filter { $0.type == type && !$0.isArchived }
                if !rows.isEmpty {
                    Section(heading: type.title) {
                        ForEach(rows) { account in
                            NavigationLink { LedgerView(account: account) } label: {
                                HStack(spacing: 12) {
                                    Text(account.code).foregroundStyle(Palette.ink2).monospacedDigit()
                                    Text(account.name).foregroundStyle(Palette.ink)
                                }
                            }
                        }
                    }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Libro mayor")
        .headerTitle()
    }
}

/// Libro mayor de una cuenta con saldo acumulado (canvas `MacLibroMayor`, `iPadBancaCuentas`). Con sitio (columna de
/// detalle del iPad o del Mac): la cuenta y su saldo en grande, el resumen del periodo y la tabla de movimientos; en
/// el iPhone o una columna estrecha, la lista. El signo de cada movimiento sigue la naturaleza de la cuenta: en pasivo,
/// patrimonio e ingreso un crédito aumenta el saldo (+); en activo y gasto lo aumenta un débito.
struct LedgerView: View {
    let account: Account
    /// En la columna de detalle de iPad y Mac (Plan de cuentas, Banca): título pequeño en la barra, como la factura,
    /// el gasto y las demás fichas, sin repetir en grande lo que el contenido ya dice (canvas `iPadVentas`,
    /// `iPadBancaCuentas`: lo grande es la cifra). Abierto encima de otra pantalla, el título de pantalla de siempre.
    var inDetailColumn = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filterByDate = false
    @State private var from = DateInterval.month(containing: .now).start
    @State private var to = Date()
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .subheadline) private var kindWidth: CGFloat = 110

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

    /// Tipo de cada movimiento (cobro, gasto…) según el documento que generó el asiento.
    static func kinds(for account: Account) -> [UUID: String] {
        Dictionary((account.lines ?? []).compactMap { line in line.entry.map { (line.id, $0.source.title) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Tabla si la vista mide al menos 640 pt y el texto no es de accesibilidad.
    private var isWide: Bool { width >= 640 && !dynamicTypeSize.isAccessibilitySize }

    /// Una cuenta de dinero (banco, caja) muestra en verde lo que entra, como Banca.
    private var isCashAccount: Bool { account.type == .asset && account.subtype.isMoneyAccount }

    var body: some View {
        let ledger = ledger
        Group {
            if isWide { wideBody(ledger) } else { listBody(ledger) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(account.name)
        .modifier(LedgerTitle(inDetailColumn: inDetailColumn))
    }

    /// Nombre, saldo en grande y tipo (canvas `iPadBancaCuentas`: «Corriente ••4821 · $42,130.18 · Saldo en libros»).
    private func hero(_ ledger: AccountLedger) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Con el título grande ya a la vista, no se repite el nombre.
            if inDetailColumn || isWide { Text(account.displayName).font(.subheadline).foregroundStyle(Palette.ink2) }
            Text(ledger.closingBalance.money).font(.amount(40)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(filterByDate ? String(localized: "Saldo final del periodo") : String(localized: "Saldo en libros · \(account.type.title) · \(account.subtype.title)"))
                .font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var dateFilter: some View {
        Group {
            Toggle("Filtrar por fechas", isOn: $filterByDate)
            if filterByDate {
                DatePicker("Desde", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("Hasta", selection: $to, in: from..., displayedComponents: .date)
            }
        }
    }

    // MARK: Lista (iPhone, columna estrecha)

    private func listBody(_ ledger: AccountLedger) -> some View {
        List {
            Section { hero(ledger) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            Section {
                LabeledContent("Aumenta con", value: account.type.normalBalance == .debit ? String(localized: "Débitos") : String(localized: "Créditos"))
                dateFilter
                if filterByDate { LabeledContent("Saldo inicial", value: ledger.openingBalance.money).monospacedDigit() }
                LabeledContent("Débitos", value: ledger.totalDebit.money).monospacedDigit()
                LabeledContent("Créditos", value: ledger.totalCredit.money).monospacedDigit()
            } header: {
                SectionLabel(text: String(localized: "Cuenta"))
            }
            Section {
                if ledger.rows.isEmpty { Text("Sin movimientos").foregroundStyle(Palette.ink2) }
                ForEach(ledger.rows.reversed()) { row in
                    AdaptiveRow(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo).lineLimit(2)
                                .foregroundStyle(Palette.ink)
                            Text(row.movement.debit > 0 ? "\(row.movement.date.dayMonth) · \(String(localized: "Débito"))"
                                                        : "\(row.movement.date.dayMonth) · \(String(localized: "Crédito"))")
                                .font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    } trailing: {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                            Text("\(row.increasesBalance ? "+" : "−")\(abs(row.effect).money)")
                                .foregroundStyle(row.increasesBalance && isCashAccount ? Palette.positive : Palette.ink)
                            Text("Saldo \(row.balance.money)").font(.footnote).foregroundStyle(Palette.ink2)
                        }
                        .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Self.spokenMovement(row))
                }
            } header: {
                SectionLabel(text: String(localized: "Movimientos"))
            } footer: {
                Text("+ aumenta el saldo de la cuenta y − lo reduce, según su naturaleza.")
            }
        }
        .groupedList()
        .screenBackground()
    }

    // MARK: Tabla (iPad y Mac, `MacLibroMayor`)

    private func wideBody(_ ledger: AccountLedger) -> some View {
        let kinds = Self.kinds(for: account)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(ledger)
                LedgerSummary(opening: ledger.openingBalance, debits: ledger.totalDebit, credits: ledger.totalCredit,
                              closing: ledger.closingBalance,
                              debitCount: ledger.rows.filter { $0.movement.debit > 0 }.count,
                              creditCount: ledger.rows.filter { $0.movement.credit > 0 }.count,
                              from: range?.from, to: range?.to ?? .now)
                HStack(spacing: 12) {
                    Toggle("Filtrar por fechas", isOn: $filterByDate).fixedSize()
                    if filterByDate {
                        DatePicker("Desde", selection: $from, in: ...to, displayedComponents: .date).fixedSize()
                        DatePicker("Hasta", selection: $to, in: from..., displayedComponents: .date).fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                LedgerTable(ledger: ledger, kinds: kinds, from: range?.from, to: range?.to ?? .now,
                            dateWidth: dateWidth, kindWidth: kindWidth, amountWidth: amountWidth)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
    }
}

/// Saldo inicial · Débitos · Créditos · Saldo final en una caja con separadores verticales (canvas `MacLibroMayor`).
struct LedgerSummary: View {
    let opening: Int64
    let debits: Int64
    let credits: Int64
    let closing: Int64
    let debitCount: Int
    let creditCount: Int
    let from: Date?
    let to: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let items: [(String, Int64, String)] = [
            (String(localized: "Saldo inicial"), opening, from.map { String(localized: "Al \($0.shortDate)") } ?? String(localized: "Desde el inicio")),
            (String(localized: "Débitos"), debits, String(localized: "\(debitCount) movimientos")),
            (String(localized: "Créditos"), credits, String(localized: "\(creditCount) movimientos")),
            (String(localized: "Saldo final"), closing, String(localized: "Al \(to.shortDate)")),
        ]
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { cells(items, dividers: true) }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { cell(items[0]); cell(items[1]) }
                GridRow { cell(items[2]); cell(items[3]) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    @ViewBuilder
    private func cells(_ items: [(String, Int64, String)], dividers: Bool) -> some View {
        ForEach(items.indices, id: \.self) { index in
            if index > 0 && dividers { Divider() }
            cell(items[index]).frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cell(_ item: (String, Int64, String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.0).font(.label).foregroundStyle(Palette.ink2)
            Text(item.1.money).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(item.2).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tabla Fecha · Tipo · Detalle · Débito · Crédito · Saldo entre el saldo inicial y el final (canvas `MacLibroMayor`),
/// con cebra en el Mac.
struct LedgerTable: View {
    let ledger: AccountLedger
    let kinds: [UUID: String]
    let from: Date?
    let to: Date
    let dateWidth: CGFloat
    let kindWidth: CGFloat
    let amountWidth: CGFloat

    var body: some View {
        TableCard {
            Text("Fecha").frame(width: dateWidth, alignment: .leading)
            Text("Tipo").frame(width: kindWidth, alignment: .leading)
            Text("Detalle").frame(maxWidth: .infinity, alignment: .leading)
            Text("Débito").frame(width: amountWidth, alignment: .trailing)
            Text("Crédito").frame(width: amountWidth, alignment: .trailing)
            Text("Saldo").frame(width: amountWidth, alignment: .trailing)
        } rows: {
            row(date: from?.dayMonth ?? "—", kind: "—", detail: String(localized: "Saldo inicial"), debit: "", credit: "",
                balance: ledger.openingBalance.money)
                .fontWeight(.semibold)
            ForEach(Array(ledger.rows.enumerated()), id: \.element.id) { index, item in
                row(date: item.movement.date.dayMonth, kind: kinds[item.movement.id] ?? "—",
                    detail: item.movement.memo.isEmpty ? String(localized: "Asiento") : item.movement.memo,
                    debit: item.movement.debit > 0 ? item.movement.debit.money : "",
                    credit: item.movement.credit > 0 ? item.movement.credit.money : "",
                    balance: item.balance.money)
                    .zebra(index + 1)
                    .accessibilityLabel(LedgerView.spokenMovement(item))
            }
            if ledger.rows.isEmpty {
                Text("Sin movimientos en el periodo").font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            row(date: to.dayMonth, kind: "", detail: String(localized: "Saldo final"), debit: ledger.totalDebit.money,
                credit: ledger.totalCredit.money, balance: ledger.closingBalance.money)
                .fontWeight(.semibold)
                .background(Palette.surface)
        }
    }

    private func row(date: String, kind: String, detail: String, debit: String, credit: String, balance: String) -> some View {
        TableRow {
            Text(date).foregroundStyle(Palette.ink2).frame(width: dateWidth, alignment: .leading)
            Text(kind).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: kindWidth, alignment: .leading)
            Text(detail).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(debit).frame(width: amountWidth, alignment: .trailing)
            Text(credit).frame(width: amountWidth, alignment: .trailing)
            Text(balance).frame(width: amountWidth, alignment: .trailing)
        }
    }
}

private struct LedgerTitle: ViewModifier {
    let inDetailColumn: Bool
    func body(content: Content) -> some View {
        if inDetailColumn { content.inlineTitle() } else { content.headerTitle() }
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
                    HStack(spacing: 12) {
                        LargeIconTile(systemImage: company.lockDate == nil ? "lock.open" : "lock", color: Palette.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(company.lockDate == nil ? String(localized: "Libros abiertos") : String(localized: "Libros cerrados hasta"))
                                .font(.footnote).foregroundStyle(Palette.ink2)
                            Text(company.lockDate?.shortDate ?? String(localized: "Sin cierre")).font(.amount(24)).foregroundStyle(Palette.ink)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
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
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Cierre de periodo")
        .headerTitle()
        .onDisappear { try? context.save() }
    }
}
