import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// Importar un extracto (CSV, OFX o QFX) a una cuenta de banco o tarjeta (DISEÑO §4.6; canvas `OnbBanco` para el
// resultado y `EstadoError` para las filas que no se leen). En iOS el archivo llega con `fileImporter`; en el Mac,
// además, arrastrándolo a Banca. Para un CSV se proponen las columnas (`CSVImportSettings.suggested(for:)` o el perfil
// guardado de la cuenta), se ven las primeras filas y se puede recordar el mapeo para la próxima vez.

// MARK: - Archivo y lectura

/// Un extracto elegido por el usuario, ya leído como texto.
struct BankImportFile: Equatable {
    enum Kind { case csv, ofx }
    let name: String
    let size: Int
    let text: String

    var kind: Kind {
        let lower = name.lowercased()
        if lower.hasSuffix(".ofx") || lower.hasSuffix(".qfx") || text.uppercased().contains("<OFX>") { return .ofx }
        return .csv
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }

    init(name: String, data: Data) {
        self.name = name
        size = data.count
        text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Lee un archivo de Archivos, iCloud Drive o el Finder (con su permiso de acceso).
    static func load(_ url: URL) throws -> BankImportFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return BankImportFile(name: url.lastPathComponent, data: try Data(contentsOf: url))
    }

    /// Tipos que ofrece el selector de archivos: CSV, texto, OFX y QFX (y cualquier archivo, por si el banco le pone
    /// otra extensión: se reconoce por el contenido).
    static var contentTypes: [UTType] {
        [.commaSeparatedText, .tabSeparatedText, .plainText] + ["ofx", "qfx"].compactMap { UTType(filenameExtension: $0) } + [.data]
    }
}

/// Lectura del CSV para la pantalla: columnas, filas de muestra y una lectura que puede saltarse las filas ilegibles.
enum BankCSVImport {
    /// Formatos de fecha que se ofrecen (los mismos que prueba `CSVImportSettings.suggested`).
    static let dateFormats = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "yyyy-MM-dd", "dd/MM/yyyy", "yyyyMMdd", "MM-dd-yyyy", "dd-MM-yyyy"]

    static func rows(_ text: String, delimiter: Character) -> [[String]] { CSVBankSource.rows(text, delimiter: delimiter) }

    /// Nombres de las columnas: los de la cabecera o «Columna 1», «Columna 2»…
    static func columnNames(_ rows: [[String]], hasHeaderRow: Bool) -> [String] {
        let width = rows.map(\.count).max() ?? 0
        return (0..<width).map { index in
            let name = hasHeaderRow ? (rows.first.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "") : ""
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? String(localized: "Columna \(index + 1)") : trimmed
        }
    }

    /// Columnas del perfil que caben en este archivo (si no, el perfil es de otro formato y se propone de nuevo).
    static func fits(_ settings: CSVImportSettings, columns: Int) -> Bool {
        let used = [settings.mapping.date, settings.mapping.details] + [settings.mapping.amount, settings.mapping.debit,
                    settings.mapping.credit, settings.mapping.payee, settings.mapping.memo, settings.mapping.reference,
                    settings.mapping.checkNumber].compactMap { $0 }
        return used.allSatisfy { $0 < columns }
    }

    /// Propuesta para el archivo: el perfil guardado de la cuenta si encaja, la de `suggested(for:)` o, si no
    /// reconoce la cabecera, las tres primeras columnas.
    static func initialSettings(for text: String, profile: CSVImportSettings?) -> CSVImportSettings {
        if let profile {
            let width = rows(text, delimiter: profile.delimiter).first?.count ?? 0
            if width > 1, fits(profile, columns: width) { return profile }
        }
        if let suggested = CSVImportSettings.suggested(for: text) { return suggested }
        return CSVImportSettings(mapping: CSVColumnMapping(date: 0, details: 1, amount: 2))
    }

    /// Lee el CSV. Con `skippingUnreadable`, las filas con fecha o importe ilegible se dejan fuera y se dicen sus
    /// números (canvas `EstadoError`: «Importar 186 y omitir 3»); sin él, la primera ilegible es un error.
    static func parse(_ text: String, settings: CSVImportSettings, skippingUnreadable: Bool,
                      calendar: Calendar = .current) throws -> (lines: [BankStatementLine], skipped: [Int]) {
        guard skippingUnreadable else {
            return (try CSVBankSource(text: text, settings: settings, calendar: calendar).parse(), [])
        }
        var current = rows(text, delimiter: settings.delimiter)
        var original = current.indices.map { $0 + 1 }
        var skipped: [Int] = []
        while true {
            let rebuilt = serialize(current, delimiter: settings.delimiter)
            do {
                return (try CSVBankSource(text: rebuilt, settings: settings, calendar: calendar).parse(), skipped.sorted())
            } catch BankStatementError.unreadableRow(let row) where current.indices.contains(row - 1) {
                skipped.append(original[row - 1])
                current.remove(at: row - 1)
                original.remove(at: row - 1)
            }
        }
    }

    /// Filas de vuelta a CSV (comillas donde hacen falta), para leerlas otra vez sin las que se saltan.
    static func serialize(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { row in
            row.map { field in
                guard field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r") else { return field }
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            .joined(separator: String(delimiter))
        }
        .joined(separator: "\n")
    }

    /// «mes/día/año · 11/04/2026».
    static func dateFormatTitle(_ format: String) -> String {
        let order: String
        if format.hasPrefix("y") { order = String(localized: "año-mes-día") }
        else if format.hasPrefix("d") { order = String(localized: "día/mes/año") }
        else { order = String(localized: "mes/día/año") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        let example = formatter.string(from: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 4).date ?? .now)
        return "\(order) · \(example)"
    }
}

/// Lo que se cuenta al terminar (canvas `OnbBanco`: «214 transacciones · 168 auto-categorizadas · 2 duplicadas omitidas»).
struct BankImportOutcome {
    let account: Account
    let imported: Int
    let duplicates: Int
    let autoApplied: Int
    /// Por revisar con una propuesta (regla o coincidencia).
    let suggested: Int
    let skippedRows: [Int]
    /// Saldo y fecha del extracto OFX, en el lado normal de la cuenta (en una tarjeta, lo que se debe).
    let statementBalance: Int64?
    let statementDate: Date?
    let failureMessage: String?
}

/// Pide la hoja de importar (con el archivo arrastrado o el de QA, si lo hay).
struct BankImportRequest: Identifiable {
    let id = UUID()
    let file: BankImportFile?
}

/// Pide el editor de reglas con un borrador sacado de un movimiento.
struct BankRuleDraftRequest: Identifiable {
    let id = UUID()
    let input: BankRuleInput
}

// MARK: - Pantalla

/// Hoja «Importar movimientos». Se abre desde Banca (iPhone, iPad y Mac), desde la bandeja y arrastrando un archivo
/// a Banca en el Mac (`initialFile`).
struct BankImportView: View {
    var initialFile: BankImportFile? = nil
    /// Cuenta propuesta (la que se está viendo en Banca).
    var preferredAccountID: UUID? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSidebarItem) private var openSidebarItem
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @State private var file: BankImportFile?
    @State private var pickingFile = false
    @State private var accountID: UUID?
    @State private var settings = CSVImportSettings(mapping: CSVColumnMapping(date: 0, details: 1, amount: 2))
    @State private var rememberColumns = true
    @State private var skipUnreadable = false
    @State private var outcome: BankImportOutcome?
    @State private var errorMessage: String?
    @State private var isImporting = false

    private var bankAccounts: [Account] {
        accounts.filter { ($0.subtype == .bank || $0.subtype == .creditCard) && !$0.isArchived && $0.isPostable }
    }

    private var account: Account? { bankAccounts.first { $0.id == accountID } }

    var body: some View {
        Group {
            if let outcome { resultView(outcome) } else { form }
        }
        .navigationTitle("Importar movimientos")
        .inlineTitle()
        .toolbar {
            if outcome == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.headerButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") { importNow() }
                        .disabled(!canImport)
                        .headerButton()
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }.headerButton()
                }
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: BankImportFile.contentTypes) { result in
            switch result {
            case .success(let url): load { try BankImportFile.load(url) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            if file == nil, let initialFile { use(initialFile) }
            #if DEBUG
            if file == nil, let pending = QABanking.pendingImport { use(pending); QABanking.pendingImport = nil }
            #endif
            if accountID == nil { accountID = preferredAccountID.flatMap { id in bankAccounts.first { $0.id == id }?.id } ?? bankAccounts.first?.id }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "qa.importarAuto") {
                Task { @MainActor in try? await Task.sleep(for: .seconds(1)); if canImport { importNow() } }
            }
            #endif
        }
    }

    // MARK: Formulario

    private var form: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
            fileSection
            if file != nil {
                Section {
                    Picker("Cuenta", selection: $accountID) {
                        ForEach(bankAccounts) { account in
                            Text(account.maskedName).tag(Optional(account.id))
                        }
                    }
                } header: {
                    SectionLabel(text: String(localized: "A qué cuenta van"))
                } footer: {
                    if let hint = accountHint { Text(hint) }
                }
                // La vista previa antes que las columnas: lo primero que se ve es si el archivo se lee bien.
                previewSection
                if file?.kind == .csv { columnsSections }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load { try BankImportFile.load(url) }
            return true
        }
        #endif
        .safeAreaInset(edge: .bottom) {
            if file != nil {
                Button(importTitle) { importNow() }
                    .buttonStyle(.primary)
                    .disabled(!canImport)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 10)
            }
        }
    }

    private var fileSection: some View {
        Section {
            if let file {
                HStack(spacing: 12) {
                    IconTile(systemImage: file.kind == .ofx ? "doc.text" : "tablecells", foreground: Palette.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: "\(file.kind == .ofx ? "OFX" : "CSV") · \(file.sizeText)").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 8)
                    Button("Cambiar") { pickingFile = true }.buttonStyle(.borderless).tint(Palette.brand)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button { pickingFile = true } label: {
                    Label("Elegir archivo CSV, OFX o QFX…", systemImage: "doc.badge.plus")
                }
                .tint(Palette.brand)
                .frame(minHeight: Metrics.target)
            }
        } header: {
            SectionLabel(text: String(localized: "Extracto del banco"))
        } footer: {
            if file == nil {
                #if os(macOS)
                Text("Bájalo de la web de tu banco («Descargar movimientos» o «Exportar») o arrástralo aquí. Los movimientos que ya importaste no se repiten.")
                #else
                Text("Bájalo de la web de tu banco («Descargar movimientos» o «Exportar») y elígelo desde Archivos o iCloud Drive. Los movimientos que ya importaste no se repiten.")
                #endif
            }
        }
    }

    @ViewBuilder
    private var columnsSections: some View {
        let rows = BankCSVImport.rows(file?.text ?? "", delimiter: settings.delimiter)
        let names = BankCSVImport.columnNames(rows, hasHeaderRow: settings.hasHeaderRow)
        Section {
            columnPicker("Fecha", selection: Binding(get: { settings.mapping.date }, set: { settings.mapping.date = $0 }), names: names)
            columnPicker("Descripción", selection: Binding(get: { settings.mapping.details }, set: { settings.mapping.details = $0 }), names: names)
            Picker("Importe en", selection: Binding(get: { settings.mapping.amount == nil }, set: setsTwoColumns)) {
                Text("Una columna").tag(false)
                Text("Cargos y abonos").tag(true)
            }
            if settings.mapping.amount != nil {
                columnPicker("Importe", selection: Binding(get: { settings.mapping.amount ?? 0 }, set: { settings.mapping.amount = $0 }), names: names)
                Picker("Signo del importe", selection: $settings.amountSign) {
                    Text("Positivo = entra dinero").tag(CSVAmountSign.signed)
                    Text("Positivo = sale dinero").tag(CSVAmountSign.inverted)
                }
            } else {
                columnPicker("Cargos (salidas)", selection: Binding(get: { settings.mapping.debit ?? 0 }, set: { settings.mapping.debit = $0 }), names: names)
                columnPicker("Abonos (entradas)", selection: Binding(get: { settings.mapping.credit ?? 0 }, set: { settings.mapping.credit = $0 }), names: names)
            }
            optionalColumnPicker("Beneficiario", selection: Binding(get: { settings.mapping.payee }, set: { settings.mapping.payee = $0 }), names: names)
            optionalColumnPicker("Referencia del banco", selection: Binding(get: { settings.mapping.reference }, set: { settings.mapping.reference = $0 }), names: names)
        } header: {
            SectionLabel(text: String(localized: "Columnas"))
        } footer: {
            Text("Propuestas por los nombres de la cabecera; corrígelas si alguna no es. La referencia evita repetir un movimiento si lo vuelves a importar.")
        }
        Section {
            Picker("Fecha escrita como", selection: $settings.dateFormat) {
                ForEach(BankCSVImport.dateFormats, id: \.self) { Text(BankCSVImport.dateFormatTitle($0)).tag($0) }
            }
            Picker("Separador", selection: $settings.delimiter) {
                Text("Coma").tag(Character(","))
                Text("Punto y coma").tag(Character(";"))
                Text("Tabulador").tag(Character("\t"))
            }
            Toggle("La primera fila tiene los nombres", isOn: $settings.hasHeaderRow)
            Toggle("Recordar estas columnas para esta cuenta", isOn: $rememberColumns)
        } header: {
            SectionLabel(text: String(localized: "Formato"))
        }
    }

    private func setsTwoColumns(_ two: Bool) {
        if two {
            settings.mapping.debit = settings.mapping.debit ?? settings.mapping.amount ?? 0
            settings.mapping.credit = settings.mapping.credit ?? settings.mapping.amount ?? 0
            settings.mapping.amount = nil
        } else {
            settings.mapping.amount = settings.mapping.amount ?? settings.mapping.debit ?? 0
            settings.mapping.debit = nil
            settings.mapping.credit = nil
        }
    }

    private func columnPicker(_ title: LocalizedStringKey, selection: Binding<Int>, names: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) }
        }
    }

    private func optionalColumnPicker(_ title: LocalizedStringKey, selection: Binding<Int?>, names: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Ninguna").tag(Int?.none)
            ForEach(names.indices, id: \.self) { Text(names[$0]).tag(Optional($0)) }
        }
    }

    // MARK: Vista previa

    /// Lo que se importaría con lo elegido: movimientos, filas omitidas o el error.
    private var parsed: Result<(lines: [BankStatementLine], skipped: [Int], ofx: OFXStatement?), Error>? {
        guard let file else { return nil }
        return Result {
            switch file.kind {
            case .ofx:
                let statement = try OFXBankSource(text: file.text).parse()
                return (statement.lines, [], statement)
            case .csv:
                let result = try BankCSVImport.parse(file.text, settings: settings, skippingUnreadable: skipUnreadable)
                return (result.lines, result.skipped, nil)
            }
        }
    }

    private var previewSection: some View {
        Section {
            switch parsed {
            case .success(let value):
                ForEach(Array(value.lines.prefix(5).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line.date.dayMonth).foregroundStyle(Palette.ink2).monospacedDigit()
                        Text(line.details).lineLimit(1).foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        Text(verbatim: line.amount > 0 ? "+\(line.amount.money)" : "−\((-line.amount).money)")
                            .monospacedDigit().foregroundStyle(line.amount > 0 ? Palette.positive : Palette.ink)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                if !value.skipped.isEmpty {
                    Label(String(localized: "Se omitirán \(value.skipped.count) filas que no se leen: \(value.skipped.map(String.init).joined(separator: ", "))"),
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(Palette.warning)
                }
            case .failure(let error):
                ErrorBanner(message: BankImportText.message(for: error))
                if case BankStatementError.unreadableRow = error {
                    Toggle("Omitir las filas que no se lean", isOn: $skipUnreadable)
                }
            case nil:
                EmptyView()
            }
        } header: {
            SectionLabel(text: String(localized: "Vista previa"))
        } footer: {
            if case .success(let value) = parsed {
                Text("\(value.lines.count) movimientos en el archivo · los ya importados se omiten")
            }
        }
    }

    private var lineCount: Int {
        if case .success(let value) = parsed { return value.lines.count }
        return 0
    }

    private var importTitle: String {
        lineCount > 0 ? String(localized: "Importar \(lineCount) movimientos") : String(localized: "Importar")
    }

    private var canImport: Bool { account != nil && lineCount > 0 && !isImporting }

    private var accountHint: String? {
        guard case .success(let value) = parsed, let statement = value.ofx else { return nil }
        if !statement.accountLast4.isEmpty, bankAccounts.contains(where: { $0.last4 == statement.accountLast4 }) {
            return String(localized: "Propuesta por los últimos dígitos del extracto (••\(statement.accountLast4)).")
        }
        return statement.isCreditCard ? String(localized: "El extracto es de una tarjeta de crédito.") : nil
    }

    // MARK: Acciones

    private func load(_ read: () throws -> BankImportFile) {
        do { use(try read()) } catch { errorMessage = error.localizedDescription }
    }

    private func use(_ loaded: BankImportFile) {
        errorMessage = nil
        skipUnreadable = false
        file = loaded
        if loaded.kind == .ofx, let statement = try? OFXBankSource(text: loaded.text).parse() {
            if let match = bankAccounts.first(where: { !statement.accountLast4.isEmpty && $0.last4 == statement.accountLast4 })
                ?? (statement.isCreditCard ? bankAccounts.first { $0.subtype == .creditCard } : nil) {
                accountID = match.id
            }
        }
        refreshSettings()
    }

    private func refreshSettings() {
        guard let file, file.kind == .csv else { return }
        let profile = account.flatMap { try? Bookkeeper(context: context).importProfiles(for: $0).first?.settings }
        settings = BankCSVImport.initialSettings(for: file.text, profile: profile ?? nil)
    }

    private func importNow() {
        guard let account, let file, case .success(let value) = parsed else { return }
        SubscriptionStore.shared.whenWritable {
            isImporting = true
            defer { isImporting = false }
            let books = Bookkeeper(context: context)
            do {
                if file.kind == .csv, rememberColumns {
                    try books.saveImportProfile(settings, for: account)
                }
                let result = try books.importStatementLines(value.lines, source: file.kind == .ofx ? .ofx : .csv, into: account)
                let inbox = BankInboxContext(books: books, accounts: accounts, invoices: invoices, bills: bills)
                let pending = result.imported.filter(\.isPending)
                let balance = value.ofx?.ledgerBalance.map { account.subtype == .creditCard ? -$0 : $0 }
                #if DEBUG
                QABanking.importHandled = true
                #endif
                outcome = BankImportOutcome(
                    account: account, imported: result.imported.count, duplicates: result.duplicates,
                    autoApplied: result.autoApplied.count,
                    suggested: pending.filter { inbox.suggestion(for: $0).isActionable }.count,
                    skippedRows: value.skipped, statementBalance: balance, statementDate: value.ofx?.balanceDate,
                    failureMessage: result.failures.first.map { $0.error.localizedDescription })
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Resultado

    private func resultView(_ outcome: BankImportOutcome) -> some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(Palette.green).accessibilityHidden(true)
                    Text(outcome.imported == 0 ? String(localized: "Nada nuevo que importar") : String(localized: "Movimientos importados"))
                        .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(outcome.account.maskedName).font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            Section {
                HStack(spacing: 0) {
                    stat(outcome.imported, String(localized: "nuevos"))
                    Divider()
                    stat(outcome.autoApplied + outcome.suggested, String(localized: "con propuesta"))
                    Divider()
                    stat(outcome.duplicates, String(localized: "repetidos omitidos"))
                }
                .padding(.vertical, 4)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if outcome.autoApplied > 0 {
                        Text("\(outcome.autoApplied) se registraron solos con una regla automática.")
                    }
                    if !outcome.skippedRows.isEmpty {
                        Text("Filas omitidas por no leerse: \(outcome.skippedRows.map(String.init).joined(separator: ", ")).")
                    }
                    if let failure = outcome.failureMessage {
                        Text("Una regla no pudo registrar: \(failure)").foregroundStyle(Palette.warning)
                    }
                }
            }
            Section {
                let pending = outcome.imported - outcome.autoApplied
                if pending > 0 {
                    Button(String(localized: "Revisar \(pending) movimientos")) {
                        openSidebarItem?(.banking(.inbox))
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                if let balance = outcome.statementBalance {
                    NavigationLink {
                        ReconciliationView(account: outcome.account, proposedDate: outcome.statementDate, proposedBalance: balance)
                    } label: {
                        LedgerRow(title: String(localized: "Conciliar con este extracto"),
                                  subtitle: String(localized: "Saldo del banco \(balance.money) · \((outcome.statementDate ?? .now).shortDate)")) {
                            IconTile(systemImage: "checklist", foreground: Palette.teal)
                        } trailing: { EmptyView() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
    }

    private func stat(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(value)").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Palette.ink)
            Text(title).font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
