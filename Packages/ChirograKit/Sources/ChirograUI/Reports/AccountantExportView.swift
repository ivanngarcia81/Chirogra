import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - «Exportar para mi contador» (fase 2, PLAN-FASE2 §5)
//
// Se abre desde Reportes («Exportar» de la barra), desde Impuestos › Deducibles (canvas `Impuestos`, `MacImpuestos`) y
// desde el inspector del flujo de efectivo en el Mac. Se elige el periodo y la base; el paquete
// (`Bookkeeper.accountantPackage`) sale en una carpeta con «Reportes.pdf» (portada, estado de resultados, balance,
// balanza, flujo de efectivo y deducibles) y los CSV (los mismos más el diario), y en un ZIP de esa carpeta. En iOS se
// comparte el ZIP con el panel del sistema; en el Mac se guarda el ZIP o la carpeta donde el usuario diga.

/// Periodo del paquete.
enum PackagePeriod: String, CaseIterable, Identifiable {
    case thisYear, lastYear, thisQuarter, lastQuarter, thisMonth, lastMonth, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisYear: String(localized: "Este año")
        case .lastYear: String(localized: "Año pasado")
        case .thisQuarter: String(localized: "Este trimestre")
        case .lastQuarter: String(localized: "Trimestre anterior")
        case .thisMonth: String(localized: "Este mes")
        case .lastMonth: String(localized: "Mes pasado")
        case .custom: String(localized: "Otras fechas")
        }
    }

    func interval(calendar: Calendar = .current, now: Date = .now) -> DateInterval? {
        let component: Calendar.Component
        let offset: Int
        switch self {
        case .thisYear: (component, offset) = (.year, 0)
        case .lastYear: (component, offset) = (.year, -1)
        case .thisQuarter: (component, offset) = (.quarter, 0)
        case .lastQuarter: (component, offset) = (.quarter, -1)
        case .thisMonth: (component, offset) = (.month, 0)
        case .lastMonth: (component, offset) = (.month, -1)
        case .custom: return nil
        }
        let step = component == .quarter ? 3 : 1
        let date = calendar.date(byAdding: component == .quarter ? .month : component, value: offset * step, to: now) ?? now
        return calendar.dateInterval(of: component, for: date)
    }
}

/// Lo que se escribe en el disco: la carpeta con sus archivos y el ZIP.
struct PreparedPackage {
    let folder: URL
    let zip: URL?
    let files: [String]
}

/// Escribe el paquete (PDF + CSV) en una carpeta temporal y la comprime. Sin pantalla: lo usan la hoja y las pruebas.
enum AccountantPackageWriter {
    /// Nombre de archivo sin barras ni dos puntos (el nombre de la empresa puede llevarlos).
    static func safeName(_ text: String) -> String {
        let cleaned = text.map { "/:\\?%*|\"<>".contains($0) ? "-" : $0 }
        return String(cleaned).trimmingCharacters(in: .whitespaces)
    }

    /// Carpeta «Contador · Empresa · 2026-01-01 a 2026-12-31».
    static func folderName(company: String, from: Date, to: Date) -> String {
        let format = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        let base = String(localized: "Contador")
        return safeName([base, company, "\(from.formatted(format)) – \(to.formatted(format))"].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    /// Los reportes del paquete como documentos para el PDF (con el flujo en la base elegida, `cashFlow`).
    static func documents(_ package: AccountantPackage, cashFlow: CashFlowStatement, currency: String) -> [ReportDocument] {
        let range = (package.from..<package.to).formatted(.interval.day().month(.abbreviated).year().locale(.appText))
        let basis = package.basis.subtitle
        var documents: [ReportDocument] = [
            .incomeStatement(package.incomeStatement, columns: [String(localized: "Periodo")], subtitle: "\(range) · \(basis) · \(currency)"),
            .balanceSheet(package.balanceSheet, subtitle: String(localized: "Al \(package.to.shortDate) · \(basis) · \(currency)")),
            .trialBalance(package.trialBalance, subtitle: String(localized: "Al \(package.to.shortDate) · \(basis) · \(currency)")),
            .cashFlow(cashFlow, columns: [String(localized: "Periodo")], subtitle: "\(range) · \(basis) · \(currency)"),
        ]
        if let taxes = package.taxSummary {
            documents.append(.taxSummary(taxes, subtitle: "\(range) · \(basis)"))
        }
        return documents
    }

    @MainActor
    static func prepare(_ package: AccountantPackage, cashFlow: CashFlowStatement, currency: String,
                        in parent: URL = FileManager.default.temporaryDirectory) throws -> PreparedPackage {
        let root = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let folder = root.appending(path: folderName(company: package.companyName, from: package.from, to: package.to), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let documents = documents(package, cashFlow: cashFlow, currency: currency)
        let range = (package.from..<package.to).formatted(.interval.day().month(.abbreviated).year().locale(.appText))
        let cover = ReportCover(title: String(localized: "Paquete para el contador"), period: range, basis: package.basis.subtitle,
                                contents: documents.map(\.title) + [String(localized: "CSV: los mismos reportes y el libro diario")],
                                note: DeductionsText.disclaimer)
        let pdf = ReportPDF.render(documents, companyName: package.companyName, cover: cover)
        var names = [String(localized: "Reportes") + ".pdf"]
        try pdf.write(to: folder.appending(path: names[0]))
        // El flujo del paquete de datos va siempre en devengo: aquí se pone el de la base elegida, igual que en el PDF.
        let flowName = String(localized: "Flujo de efectivo") + ".csv"
        for file in package.files {
            let name = safeName(file.name)
            let contents = name == flowName ? CSVExport.cashFlow(cashFlow) : file.contents
            try Data(contents.utf8).write(to: folder.appending(path: name))
            names.append(name)
        }
        return PreparedPackage(folder: folder, zip: try? zip(folder), files: names)
    }

    /// ZIP de la carpeta con el coordinador de archivos del sistema (sin dependencias): queda junto a la carpeta.
    static func zip(_ folder: URL) throws -> URL {
        var coordinatorError: NSError?
        var result: Result<URL, Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zipped in
            let target = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".zip")
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: zipped, to: target)
                result = .success(target)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }
}

/// Hoja «Exportar para mi contador».
struct AccountantExportView: View {
    var initialInterval: DateInterval? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ActiveCompanyQuery private var companies: [Company]
    @ReportBasisSetting private var storedBasis
    @State private var period: PackagePeriod = .thisYear
    @State private var from = Date.now
    @State private var to = Date.now
    @State private var basis: AccountingBasis = .accrual
    @State private var prepared: PreparedPackage?
    @State private var errorMessage: String?
    @State private var loaded = false
    #if os(macOS)
    @State private var exportingFolder = false
    @State private var exportingZip = false
    @State private var savedMessage: String?
    #endif

    private var range: (from: Date, to: Date) {
        let calendar = Calendar.current
        if let interval = period.interval() { return (interval.start, interval.end.addingTimeInterval(-1)) }
        let start = calendar.startOfDay(for: min(from, to))
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: max(from, to))) ?? to
        return (start, end)
    }

    private var form: TaxForm? { companies.first.flatMap { TaxForm.forEntity($0.entityType) } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                Picker("Periodo", selection: $period) {
                    ForEach(PackagePeriod.allCases) { Text($0.title).tag($0) }
                }
                if period == .custom {
                    DatePicker("Desde", selection: $from, displayedComponents: .date)
                    DatePicker("Hasta", selection: $to, displayedComponents: .date)
                } else {
                    LabeledContent("Fechas", value: (range.from..<range.to).formatted(.interval.day().month(.abbreviated).year().locale(.appText)))
                }
                HStack {
                    Picker("Base contable", selection: $basis) {
                        ForEach(AccountingBasis.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TermHelp(.accountingBasis)
                }
            } header: {
                SectionLabel(text: String(localized: "Periodo y base"))
            }
            Section {
                contentRow("doc.richtext", String(localized: "Reportes.pdf"),
                           String(localized: "Portada, estado de resultados, balance general, balanza, flujo de efectivo y deducibles"))
                contentRow("tablecells", String(localized: "Archivos CSV"),
                           String(localized: "Los mismos reportes y el libro diario, para abrirlos en una hoja de cálculo"))
                if let form {
                    contentRow("list.number", form.title, String(localized: "Totales por línea del formulario, con sus cuentas"))
                }
            } header: {
                SectionLabel(text: String(localized: "Qué incluye"))
            } footer: {
                Text(DeductionsText.disclaimer)
            }
            if let prepared {
                Section {
                    ForEach(prepared.files, id: \.self) { name in
                        Label(name, systemImage: name.hasSuffix(".pdf") ? "doc.richtext" : "tablecells").foregroundStyle(Palette.ink)
                    }
                    #if os(macOS)
                    if let savedMessage { Text(savedMessage).foregroundStyle(Palette.positive) }
                    #endif
                } header: {
                    SectionLabel(text: String(localized: "Listo · \(prepared.folder.lastPathComponent)"))
                }
            }
            Section { actions }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Exportar para mi contador")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.headerButton() }
        }
        .onAppear(perform: load)
        .onChange(of: period) { prepared = nil }
        .onChange(of: basis) { prepared = nil }
        .onChange(of: from) { prepared = nil }
        .onChange(of: to) { prepared = nil }
        #if os(macOS)
        .fileExporter(isPresented: $exportingZip, document: prepared.map { PackageDocument(url: $0.zip ?? $0.folder) },
                      contentType: .zip, defaultFilename: prepared?.folder.lastPathComponent) { result in saved(result) }
        .fileExporter(isPresented: $exportingFolder, document: prepared.map { PackageDocument(url: $0.folder) },
                      contentType: .folder, defaultFilename: prepared?.folder.lastPathComponent) { result in saved(result) }
        #endif
        #if DEBUG
        .task { await applyQA() }
        #endif
    }

    @ViewBuilder
    private var actions: some View {
        if let prepared {
            #if os(macOS)
            Button("Guardar ZIP…") { exportingZip = true }.buttonStyle(.primary).disabled(prepared.zip == nil)
            Button("Guardar carpeta…") { exportingFolder = true }.buttonStyle(.secondary)
            #else
            if let zip = prepared.zip {
                ShareLink(item: zip) { Label("Compartir ZIP…", systemImage: "square.and.arrow.up") }.buttonStyle(.primary)
            }
            ShareLink(item: prepared.folder) { Label("Compartir carpeta…", systemImage: "folder") }.buttonStyle(.secondary)
            #endif
        } else {
            Button("Preparar paquete", action: prepare).buttonStyle(.primary)
        }
    }

    private func contentRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Palette.brand).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Palette.ink)
                Text(detail).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        basis = storedBasis
        if let initialInterval {
            from = initialInterval.start
            to = initialInterval.end.addingTimeInterval(-1)
            period = PackagePeriod.allCases.first { $0.interval().map { $0 == initialInterval } ?? false } ?? .thisYear
        }
    }

    private func prepare() {
        do {
            let books = Bookkeeper(context: context)
            let span = range
            let package = try books.accountantPackage(from: span.from, to: span.to, basis: basis, locale: .appText)
            let cashFlow = ReportBuilder.cashFlow(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(basis: basis),
                                                  from: span.from, to: span.to)
            prepared = try AccountantPackageWriter.prepare(package, cashFlow: cashFlow, currency: companies.first?.currencyCode ?? "USD")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(macOS)
    private func saved(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): savedMessage = String(localized: "Guardado en \(url.path(percentEncoded: false))")
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }
    #endif

    #if DEBUG
    /// `-qa.contadorCarpeta <ruta>` prepara el paquete al abrir la hoja y copia la carpeta y el ZIP a esa ruta (sin
    /// ruta absoluta, a la carpeta temporal de la app, en «qa-contador»); `-qa.contadorPeriodo añoPasado|año|trimestre`.
    private func applyQA() async {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "qa.contadorPeriodo") {
        case "añoPasado": period = .lastYear
        case "trimestre": period = .thisQuarter
        case "año": period = .thisYear
        default: break
        }
        guard let target = defaults.string(forKey: "qa.contadorCarpeta") else { return }
        try? await Task.sleep(for: .seconds(1))
        prepare()
        guard let prepared else { return }
        let destination = target.hasPrefix("/") ? URL(filePath: target, directoryHint: .isDirectory)
            : FileManager.default.temporaryDirectory.appending(path: "qa-contador", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in [prepared.folder, prepared.zip].compactMap({ $0 }) {
            let copy = destination.appending(path: item.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: item, to: copy)
        }
        print("qa.contador: \(destination.path(percentEncoded: false))")
    }
    #endif
}

#if os(macOS)
/// La carpeta o el ZIP ya escritos, para «Guardar…» del Mac.
private struct PackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .folder] }
    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
#endif
