#if os(macOS)
import ChirograCore
import ChirograData
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Mac: Gastos como tabla + inspector (canvas `MacGastos`). En la barra, el periodo («Octubre 2026»), la búsqueda,
/// «Nuevo gasto» (la hoja de `ExpenseEditorView`, canvas `MacGastoNuevo`) y el inspector. Arriba, el gasto del mes por
/// categoría (el mismo cálculo que la tarjeta del mes de `ExpenseListView` y que «Gastos» de Inicio) y «Solo sin
/// recibo»; la tabla Fecha · Proveedor · Categoría · Cuenta de pago · Recibo · Importe. El inspector muestra el gasto
/// elegido (lo de `ExpenseDetailView` en filas y el recibo) con «Ver recibo» (Vista Rápida) o «Adjuntar recibo…», y
/// acepta que se le suelte una foto o un PDF. Doble clic abre la ficha completa (`ExpenseDetailView`).
///
/// No está en el canvas pero sí en el modelo: Método y Nota en el inspector, varios recibos por gasto. Está en el
/// canvas y no en el modelo: «Corriente ••4821» (la cuenta no guarda sus últimos dígitos; se muestra su nombre) y
/// «Editar» (un gasto contabilizado no se edita: no hay editor ni servicio para eso; «Abrir gasto» en su lugar).
struct ExpenseTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var period: ExpensePeriod
    @State private var withoutReceipt = false
    @State private var query = ""
    @State private var creating = false
    @State private var openedExpense: Expense?
    @State private var openedVendor: Vendor?
    /// Gasto al que se adjunta lo que se elija en «Adjuntar recibo…».
    @State private var attachingTo: Expense?
    @State private var removing: Attachment?
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var errorMessage: String?

    init(selection: Binding<UUID?>) {
        _selection = selection
        _period = State(initialValue: ExpensePeriod.initial)
    }

    // MARK: Datos

    private var rows: [ExpenseTableRow] {
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return expenses.map { ExpenseTableRow($0, accountNames: names) }
    }

    /// Los gastos del periodo, antes de la búsqueda y de «Solo sin recibo».
    private func inPeriod(_ rows: [ExpenseTableRow]) -> [ExpenseTableRow] {
        guard let interval = period.interval else { return rows }
        return rows.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private func filtered(_ rows: [ExpenseTableRow]) -> [ExpenseTableRow] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            (!withoutReceipt || !row.hasReceipt) && (text.isEmpty
                || row.payee.localizedStandardContains(text)
                || (row.expense.vendor?.name ?? "").localizedStandardContains(text)
                || row.category.localizedStandardContains(text)
                || row.account.localizedStandardContains(text)
                || row.expense.memo.localizedStandardContains(text)
                || row.amount.money.contains(text))
        }
    }

    /// Meses del menú «Periodo»: los que tienen gastos y el actual, del más reciente al más antiguo.
    private var months: [Date] {
        var starts = Set(expenses.map { DateInterval.month(containing: $0.date).start })
        starts.insert(DateInterval.month(containing: .now).start)
        if case .month(let start) = period { starts.insert(start) }
        return starts.sorted(by: >)
    }

    /// «34 gastos de octubre», «10 de 34 gastos de octubre»; con todos los meses, «34 gastos».
    private func countText(shown: Int, total: Int) -> String {
        switch period {
        case .month(let start):
            let month = start.formatted(.appDateTime.month(.wide))
            return shown == total ? String(localized: "\(total) gastos de \(month)")
                : String(localized: "\(shown) de \(total) gastos de \(month)")
        case .all:
            return shown == total ? String(localized: "\(total) gastos") : String(localized: "\(shown) de \(total) gastos")
        }
    }

    private func empty(periodRows: [ExpenseTableRow]) -> MacTableEmpty {
        if expenses.isEmpty {
            return MacTableEmpty(systemImage: "wallet.bifold", title: String(localized: "Sin gastos todavía"),
                                 message: String(localized: "Registra un gasto con el botón + y adjunta el recibo."),
                                 actionTitle: String(localized: "Nuevo gasto"), action: { creating = true })
        }
        if periodRows.isEmpty, case .month(let start) = period {
            return MacTableEmpty(systemImage: "calendar",
                                 title: String(localized: "Sin gastos en \(start.formatted(.appDateTime.month(.wide)))"),
                                 message: String(localized: "Elige otro mes o registra un gasto nuevo."),
                                 actionTitle: String(localized: "Ver todos los meses"), action: { period = .all })
        }
        return MacTableEmpty(title: String(localized: "Sin resultados"),
                             message: String(localized: "Ningún gasto coincide con la búsqueda o el filtro."),
                             actionTitle: String(localized: "Quitar filtros"), action: { query = ""; withoutReceipt = false })
    }

    // MARK: Página

    var body: some View {
        let periodRows = inPeriod(rows)
        let shown = filtered(periodRows)
        let count = countText(shown: shown.count, total: periodRows.count)
        MacTablePage(
            title: String(localized: "Gastos"),
            subtitle: count,
            rows: shown, footer: count,
            query: $query, searchPrompt: Text("Proveedor, categoría o monto"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\ExpenseTableRow.date, order: .reverse)],
            addTitle: String(localized: "Nuevo gasto"), onAdd: { creating = true },
            onOpen: { openedExpense = $0.expense },
            empty: empty(periodRows: periodRows),
            inspectorTitle: { _ in String(localized: "Gasto") },
            inspectorPlaceholder: String(localized: "Selecciona un gasto para ver sus detalles.")
        ) {
            TableColumn("Fecha", value: \.date) { row in
                MacCellText(text: row.date.dayMonth)
            }
            .width(min: 52, ideal: 60, max: 100)
            TableColumn("Proveedor", value: \.payee) { row in
                Text(row.payee).lineLimit(1)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Categoría", value: \.category) { row in
                ExpenseCategoryCell(name: row.categoryStyleName, label: row.category)
            }
            .width(min: 110, ideal: 140)
            TableColumn("Cuenta de pago", value: \.account) { row in
                MacCellText(text: row.account).lineLimit(1)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Recibo", value: \.receiptRank) { row in
                ExpenseReceiptCell(hasReceipt: row.hasReceipt)
            }
            .width(min: 44, ideal: 52, max: 64)
            .alignment(.center)
            TableColumn("Importe", value: \.amount) { row in
                Text(row.amount.money).monospacedDigit()
            }
            .width(min: 76, ideal: 90, max: 140)
            .alignment(.trailing)
        } filter: {
            VStack(alignment: .leading, spacing: 14) {
                if case .month(let start) = period {
                    ExpenseMonthCard(month: start, accounts: accounts, journalLines: journalLines)
                }
                Toggle("Solo sin recibo", isOn: $withoutReceipt)
                    .toggleStyle(.checkbox)
            }
        } inspector: { row in
            ExpenseInspector(expense: row.expense, category: row.category, errorMessage: errorMessage,
                             openVendor: { openedVendor = $0 },
                             preview: { preview($0, from: $1) },
                             attach: { attachingTo = row.expense },
                             attachFiles: { files in files.forEach { attach($0, to: row.expense) } },
                             remove: { removing = $0 })
        } actions: { row in
            actions(for: row.expense)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { periodPicker }
        }
        .onChange(of: selection) { errorMessage = nil }
        .sheet(isPresented: $creating) { NavigationStack { ExpenseEditorView() }.editorSheetSizing() }
        .navigationDestination(item: $openedExpense) { ExpenseDetailView(expense: $0) }
        .navigationDestination(item: $openedVendor) { VendorDetailView(vendor: $0) }
        .fileImporter(isPresented: Binding(get: { attachingTo != nil }, set: { if !$0 { attachingTo = nil } }),
                      allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard let expense = attachingTo, case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let file = try? ReceiptFile(url: url, fallback: .data) { attach(file, to: expense) } else {
                    errorMessage = String(localized: "No se pudo adjuntar el archivo: usa una foto o un PDF.")
                }
            }
            attachingTo = nil
        }
        .confirmationDialog("¿Quitar este recibo?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { attachment in
            Button("Quitar \(attachment.filename)", role: .destructive) { remove(attachment) }
        } message: { _ in
            Text("El gasto y su asiento no cambian; solo se borra el archivo adjunto.")
        }
        .quickLookPreview($previewURL, in: previewURLs)
        #if DEBUG
        .task { await runQAActions() }
        #endif
    }

    /// Periodo de la tabla (canvas: «Octubre 2026 ▾» en la barra): los meses con gastos y «Todos los meses».
    private var periodPicker: some View {
        Picker("Periodo", selection: $period) {
            ForEach(months, id: \.self) { start in
                Text(start.formatted(.appDateTime.month(.wide).year()).sentenceCased).tag(ExpensePeriod.month(start))
            }
            Divider()
            Text("Todos los meses").tag(ExpensePeriod.all)
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("Periodo")
    }

    /// Botones al pie del inspector (canvas: «Editar» y la acción del recibo, uno junto al otro).
    @ViewBuilder
    private func actions(for expense: Expense) -> some View {
        let attachments = expense.sortedAttachments
        HStack(spacing: 8) {
            Button("Abrir gasto") { openedExpense = expense }.buttonStyle(.secondary)
            if attachments.isEmpty {
                Button("Adjuntar recibo…") { attachingTo = expense }.buttonStyle(.primary)
            } else {
                Button("Ver recibo") { preview(attachments, from: 0) }.buttonStyle(.primary)
            }
        }
    }

    // MARK: Recibos

    private func attach(_ file: ReceiptFile, to expense: Expense) {
        do {
            try Bookkeeper(context: context).attachReceipt(file.data, filename: file.name, contentType: file.type, to: expense)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "No se pudo adjuntar el archivo: usa una foto o un PDF.")
        }
    }

    private func remove(_ attachment: Attachment) {
        do {
            try Bookkeeper(context: context).removeAttachment(attachment)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "No se pudo quitar el recibo.")
        }
    }

    /// Vista Rápida de los recibos del gasto, empezando por `index`: cada archivo se copia a la carpeta temporal con su
    /// nombre (el título de la ventana de Vista Rápida) y se puede pasar de uno a otro.
    private func preview(_ attachments: [Attachment], from index: Int) {
        let urls = attachments.compactMap(Self.temporaryFile)
        guard !urls.isEmpty else { return }
        previewURLs = urls
        previewURL = urls[min(max(0, index), urls.count - 1)]
    }

    private static func temporaryFile(for attachment: Attachment) -> URL? {
        guard let data = attachment.data else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Recibos", directoryHint: .isDirectory)
            .appending(path: attachment.id.uuidString, directoryHint: .isDirectory)
        var name = attachment.filename.replacingOccurrences(of: "/", with: "-")
        if name.isEmpty { name = String(localized: "Recibo") }
        if (name as NSString).pathExtension.isEmpty,
           let ext = UTType(attachment.contentType)?.preferredFilenameExtension {
            name += ".\(ext)"
        }
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            return url
        } catch {
            return nil
        }
    }

    #if DEBUG
    /// Para QA sin el ratón (con `-qa.fila`): `-qa.adjuntar 1` adjunta al gasto elegido un recibo de prueba hecho aquí,
    /// `-qa.recibo 1` abre su Vista Rápida, `-qa.abrir 1` abre la ficha completa y `-qa.nuevo 1` la hoja «Nuevo gasto».
    /// El periodo se elige con `-qa.periodo todos|anterior|AAAA-MM` (ver `ExpensePeriod.initial`).
    private func runQAActions() async {
        let defaults = UserDefaults.standard
        try? await Task.sleep(for: .seconds(1))
        if defaults.bool(forKey: "qa.nuevo") { creating = true; return }
        guard let id = selection, let expense = expenses.first(where: { $0.id == id }) else { return }
        if defaults.bool(forKey: "qa.adjuntar"), expense.sortedAttachments.isEmpty, let data = Self.qaReceiptPNG(for: expense) {
            attach(ReceiptFile(data: data, name: "recibo-prueba.png", type: .png), to: expense)
        }
        if defaults.bool(forKey: "qa.recibo") {
            try? await Task.sleep(for: .seconds(0.5))
            preview(expense.sortedAttachments, from: 0)
        }
        if defaults.bool(forKey: "qa.abrir") { openedExpense = expense }
    }

    private static func qaReceiptPNG(for expense: Expense) -> Data? {
        let content = VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: expense.payee.uppercased()).font(.system(size: 18, weight: .bold, design: .monospaced))
            Text(verbatim: expense.date.shortDate).font(.system(size: 12, design: .monospaced))
            Rectangle().frame(height: 1)
            Text(verbatim: "QA · \(expense.total.money)").font(.system(size: 16, weight: .semibold, design: .monospaced))
        }
        .padding(24)
        .frame(width: 280, height: 380, alignment: .topLeading)
        .foregroundStyle(Color.black)
        .background(Color(red: 0.98, green: 0.97, blue: 0.95))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
    #endif
}

// MARK: - Periodo

/// Periodo de la tabla de Gastos: un mes (su primer día) o todos.
private enum ExpensePeriod: Hashable {
    case month(Date)
    case all

    var interval: DateInterval? {
        guard case .month(let start) = self else { return nil }
        return DateInterval.month(containing: start)
    }

    /// El mes actual, como el canvas («Gastos de octubre»).
    static var initial: ExpensePeriod {
        let current = ExpensePeriod.month(DateInterval.month(containing: .now).start)
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "qa.periodo") {
        case "todos": return .all
        case "anterior": return .month(DateInterval.month(containing: .now, offset: -1).start)
        case let value?:
            let parts = value.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) {
                return .month(date)
            }
            return current
        case nil: return current
        }
        #else
        return current
        #endif
    }
}

// MARK: - Filas

/// Una fila de la tabla: el gasto con lo que se muestra y ordena ya resuelto (el nombre de la categoría y de la cuenta
/// de pago viven en `Account`, que el gasto solo apunta por id). `nonisolated` para que sus key paths sean `Sendable`
/// (orden de las columnas).
nonisolated private struct ExpenseTableRow: Identifiable {
    let expense: Expense
    let id: UUID
    let date: Date
    let payee: String
    /// «Materiales», «Varias categorías» o «Sin categoría».
    let category: String
    /// Nombre con el que se elige el símbolo y el color (nil si son varias o ninguna).
    let categoryStyleName: String?
    let account: String
    let hasReceipt: Bool
    let amount: Int64

    /// Para ordenar por «Recibo»: primero los que no lo tienen.
    var receiptRank: Int { hasReceipt ? 1 : 0 }

    init(_ expense: Expense, accountNames: [UUID: String]) {
        self.expense = expense
        id = expense.id
        date = expense.date
        payee = expense.payee.isEmpty ? (expense.vendor?.name ?? "") : expense.payee
        let lines = expense.sortedLines
        let names = Set(lines.compactMap { $0.accountID.flatMap { accountNames[$0] } })
        if names.count > 1 {
            category = String(localized: "Varias categorías")
            categoryStyleName = nil
        } else if let name = names.first {
            category = name
            categoryStyleName = name
        } else {
            category = String(localized: "Sin categoría")
            categoryStyleName = nil
        }
        account = expense.paymentAccountID.flatMap { accountNames[$0] } ?? "—"
        hasReceipt = !(expense.attachments ?? []).isEmpty
        amount = expense.total
    }
}

/// Categoría de una fila (canvas: cuadrado de 18 pt con el símbolo blanco y el nombre).
private struct ExpenseCategoryCell: View {
    let name: String?
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: ExpenseCategoryStyle.symbol(for: name))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(ExpenseCategoryStyle.color(for: name), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            Text(label).lineLimit(1)
        }
    }
}

/// Recibo de una fila: el clip si lo tiene, una raya si no (en gris jerárquico: pasa a blanco en la fila elegida).
private struct ExpenseReceiptCell: View {
    let hasReceipt: Bool

    var body: some View {
        if hasReceipt {
            Image(systemName: "paperclip").foregroundStyle(.secondary).accessibilityLabel("Recibo adjunto")
        } else {
            Text(verbatim: "—").foregroundStyle(.secondary).accessibilityLabel("Sin recibo")
        }
    }
}

// MARK: - Tarjeta del mes

/// Gasto del mes por categoría (canvas `MacGastos`: «Gastos de octubre», la cifra, la comparación con el mes anterior,
/// la barra y la leyenda). Las mismas cifras que el estado de resultados (gastos y costo de ventas), como la tarjeta del
/// mes de `ExpenseListView` y «Gastos» de Inicio; las cuatro mayores y el resto en «Otros».
private struct ExpenseMonthCard: View {
    let month: Date
    let accounts: [Account]
    let journalLines: [JournalLine]

    private struct Slice {
        let name: String
        let amount: Int64
        let color: Color
    }

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let rows = categoryRows(ledger, DateInterval.month(containing: month))
        let total = rows.reduce(0) { $0 + $1.amount }
        let previous = categoryRows(ledger, DateInterval.month(containing: month, offset: -1)).reduce(0) { $0 + $1.amount }
        let slices = slices(rows)
        let monthName = month.formatted(.appDateTime.month(.wide))
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                summary(total: total, previous: previous, monthName: monthName).frame(minWidth: 170, alignment: .leading)
                breakdown(slices, total: total).frame(minWidth: 300)
            }
            VStack(alignment: .leading, spacing: 12) {
                summary(total: total, previous: previous, monthName: monthName)
                breakdown(slices, total: total)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.separator, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Gastos del mes por categoría"))
    }

    private func categoryRows(_ ledger: Ledger, _ interval: DateInterval) -> [ReportRow] {
        let statement = ledger.incomeStatement(interval)
        return (statement.costOfGoodsSold + statement.expenses).filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }

    private func slices(_ rows: [ReportRow]) -> [Slice] {
        let top = Array(rows.prefix(4))
        let colors = ExpenseCategoryStyle.barColors(for: top.map(\.account.name))
        var slices = top.indices.map { Slice(name: top[$0].account.name, amount: top[$0].amount, color: colors[$0]) }
        let rest = rows.dropFirst(4).reduce(0) { $0 + $1.amount }
        if rest > 0 { slices.append(Slice(name: String(localized: "Otros"), amount: rest, color: Palette.gray)) }
        return slices
    }

    /// «Gastos de octubre», la cifra de 24 y «▼ 8% vs. septiembre» (si los dos meses tienen gastos).
    private func summary(total: Int64, previous: Int64, monthName: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Gastos de \(monthName)").font(.label).foregroundStyle(Palette.ink2)
            Text(total.money).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            // Sin gastos en el mes (p. ej. el día 1) no se compara: «▼ 100 %» no dice nada.
            if previous > 0 && total > 0 {
                let change = Double(total - previous) / Double(previous)
                let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
                let previousName = DateInterval.month(containing: month, offset: -1).start.formatted(.appDateTime.month(.wide))
                Group {
                    if total < previous {
                        Text("▼ \(percent) vs. \(previousName)").foregroundStyle(Palette.positive)
                            .accessibilityLabel(String(localized: "\(percent) menos que en \(previousName)"))
                    } else if total > previous {
                        Text("▲ \(percent) vs. \(previousName)").foregroundStyle(Palette.warning)
                            .accessibilityLabel(String(localized: "\(percent) más que en \(previousName)"))
                    } else {
                        Text("Igual que en \(previousName)").foregroundStyle(Palette.ink2)
                    }
                }
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func breakdown(_ slices: [Slice], total: Int64) -> some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 10) {
                CategoryBar(amounts: slices.map(\.amount), colors: slices.map(\.color))
                    .accessibilityLabel(String(localized: "Gastos del mes por categoría"))
                    .accessibilityValue(slices.map { "\($0.name) \($0.amount.money)" }.joined(separator: ", "))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 18, alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(slices.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Circle().fill(slices[index].color).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(slices[index].name).foregroundStyle(Palette.ink2).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(slices[index].amount.money).foregroundStyle(Palette.ink).monospacedDigit()
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        } else {
            Text("Sin gastos este mes").font(.subheadline).foregroundStyle(Palette.ink2)
        }
    }
}

// MARK: - Inspector

/// Inspector del gasto (canvas `MacGastos`): icono de la categoría, proveedor e importe de 24; «Detalles» (Fecha,
/// Proveedor, Categoría o sus líneas, Cuenta de pago, Método, Nota) y «Recibo» con su miniatura. Se le puede soltar
/// una foto o un PDF para adjuntarlo.
private struct ExpenseInspector: View {
    let expense: Expense
    let category: String
    let errorMessage: String?
    let openVendor: (Vendor) -> Void
    let preview: ([Attachment], Int) -> Void
    let attach: () -> Void
    let attachFiles: ([ReceiptFile]) -> Void
    let remove: (Attachment) -> Void
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var isTargeted = false

    private func accountName(_ id: UUID?) -> String? { accounts.first { $0.id == id }?.name }
    private var title: String { expense.payee.isEmpty ? (expense.vendor?.name ?? String(localized: "Gasto")) : expense.payee }
    private var styleName: String? { expense.sortedLines.count == 1 ? accountName(expense.sortedLines.first?.accountID) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            HStack(spacing: 10) {
                LargeIconTile(systemImage: ExpenseCategoryStyle.symbol(for: styleName), color: ExpenseCategoryStyle.color(for: styleName))
                MacInspectorSummary(title: title, amount: expense.total.money) { EmptyView() }
            }
            details
            receipts
        }
        .padding(isTargeted ? 6 : 0)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.brand, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .dropDestination(for: ReceiptFile.self) { files, _ in
            attachFiles(files)
            return !files.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    private var details: some View {
        MacInspectorSection(title: String(localized: "Detalles")) {
            MacInspectorRow(String(localized: "Fecha"), value: expense.date.shortDate)
            MacInspectorRow(label: String(localized: "Proveedor")) {
                if let vendor = expense.vendor {
                    Button(vendor.name) { openVendor(vendor) }
                        .buttonStyle(.link)
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                        .help("Ver proveedor")
                } else {
                    Text(expense.payee.isEmpty ? "—" : expense.payee).lineLimit(2)
                }
            }
            let lines = expense.sortedLines
            if lines.count > 1 {
                ForEach(lines) { line in
                    MacInspectorRow(accountName(line.accountID) ?? String(localized: "Sin categoría"), value: line.amount.money)
                }
            } else {
                MacInspectorRow(String(localized: "Categoría"), value: category)
            }
            MacInspectorRow(String(localized: "Cuenta de pago"), value: accountName(expense.paymentAccountID) ?? "—")
            MacInspectorRow(String(localized: "Método"),
                            value: ExpenseEditorView.title(for: PaymentMethod(rawValue: expense.methodRaw) ?? .other))
            if !expense.memo.isEmpty { MacInspectorRow(String(localized: "Nota"), value: expense.memo) }
        }
    }

    private var receipts: some View {
        let attachments = expense.sortedAttachments
        return MacInspectorSection(title: String(localized: "Recibo")) {
            if attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        StatusDot(color: Palette.orange)
                        Text("Sin recibo").foregroundStyle(Palette.warning)
                    }
                    .accessibilityElement(children: .combine)
                    Text("Guarda el comprobante: el IRS pide conservarlo. Puedes soltar aquí una foto o un PDF.")
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    receiptRow(attachment, index: index, all: attachments)
                }
                Button("Adjuntar otro recibo…", action: attach)
                    .buttonStyle(.link)
                    .foregroundStyle(Palette.brand)
                    .frame(minHeight: 26)
            }
        }
    }

    /// Miniatura, nombre y tipo; clic para la Vista Rápida y menú con Compartir y Quitar.
    private func receiptRow(_ attachment: Attachment, index: Int, all: [Attachment]) -> some View {
        let isPDF = attachment.contentType == UTType.pdf.identifier
        return Button { preview(all, index) } label: {
            HStack(spacing: 10) {
                ReceiptThumbnail(data: attachment.data, contentType: attachment.contentType, side: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename).lineLimit(1).truncationMode(.middle).foregroundStyle(Palette.ink)
                    Text(isPDF ? String(localized: "PDF guardado con el gasto") : String(localized: "Imagen guardada con el gasto"))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ver recibo")
        .accessibilityHint("Abre la Vista Rápida")
        .contextMenu {
            Button("Ver recibo", systemImage: "eye") { preview(all, index) }
            if let data = attachment.data {
                ShareLink(item: AttachmentFile(data: data, filename: attachment.filename, contentType: attachment.contentType),
                          preview: SharePreview(attachment.filename)) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
            }
            Divider()
            Button("Quitar recibo", systemImage: "trash", role: .destructive) { remove(attachment) }
        }
    }
}

private extension Expense {
    /// Recibos del gasto, del más antiguo al más nuevo.
    var sortedAttachments: [Attachment] { (attachments ?? []).sorted { $0.createdAt < $1.createdAt } }
}
#endif
