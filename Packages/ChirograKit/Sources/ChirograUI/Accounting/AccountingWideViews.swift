import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Cierre de periodo (`MacCierre`)

/// Cierre de periodo (DISEÑO §4.2, canvas `MacCierre`): fecha hasta la que no se admite nada, con historial de cierres y
/// reaperturas y contraseña de cierre opcional. Todo pasa por `Bookkeeper.closeBooks` / `reopenBooks` /
/// `setClosingPassword` / `removeClosingPassword`, que dejan su rastro en el historial y en la auditoría.
/// - iPad y Mac: caja «Libros cerrados hasta», la lista de revisión del mes que se va a cerrar, «Cerrar periodo» con la
///   nueva fecha y la contraseña, y la tabla «Historial de cierres» (en el Mac, el inspector con el elegido).
/// - iPhone (o letra muy grande): lo mismo como formulario agrupado.
struct PeriodCloseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ActiveCompanyQuery private var companies: [Company]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var expenses: [Expense]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery(sort: \PeriodClose.date, order: .reverse) private var history: [PeriodClose]
    @State private var newDate: Date?
    @State private var errorMessage: String?
    /// Reabrir pendiente de confirmar (con la contraseña, si hay): la fecha que quedará (`nil` = quitar el cierre).
    @State private var reopening: ReopenRequest?
    @State private var password = ""
    @State private var editingPassword = false
    @State private var removingPassword = false
    #if os(macOS)
    /// Cierre elegido en el historial para el inspector; sin elegir, el más reciente.
    @State private var macPick: UUID?
    #endif

    private let calendar = Calendar.current

    struct ReopenRequest: Identifiable {
        let id = UUID()
        let target: Date?
        let title: String
    }

    /// `MacCierre` en iPad y Mac (hasta AX3); el formulario en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    private var company: Company? { companies.first }

    /// Propuesta: el mes siguiente al cierre actual o, sin cierre, el mes pasado.
    private func proposedDate(_ company: Company) -> Date {
        if let lock = company.lockDate {
            return PeriodClosing.endOfMonth(calendar.date(byAdding: .day, value: 1, to: lock) ?? lock)
        }
        return PeriodClosing.endOfMonth(calendar.date(byAdding: .month, value: -1, to: .now) ?? .now)
    }

    private func target(_ company: Company) -> Date { newDate ?? proposedDate(company) }

    /// Solo hacia adelante y nunca más allá de hoy (no se cierra un mes que aún no termina de pasar).
    private func canClose(_ company: Company, target: Date) -> Bool {
        let day = calendar.startOfDay(for: target)
        guard day <= calendar.startOfDay(for: .now) else { return false }
        return company.lockDate.map { day > calendar.startOfDay(for: $0) } ?? true
    }

    private func isFuture(_ date: Date) -> Bool { calendar.startOfDay(for: date) > calendar.startOfDay(for: .now) }

    /// «Cerrar octubre 2026» si la fecha es fin de mes; si no, «Cerrar hasta el 15/10/26».
    private func closeTitle(_ target: Date) -> String {
        calendar.isDate(target, inSameDayAs: PeriodClosing.endOfMonth(target))
            ? String(localized: "Cerrar \(target.formatted(.appDateTime.month(.wide).year()))")
            : String(localized: "Cerrar hasta el \(target.shortDate)")
    }

    var body: some View {
        Group {
            if isWide { wideBody } else { compactBody }
        }
        .navigationTitle("Cierre de periodo")
        #if os(macOS)
        .navigationSubtitle(String(localized: "Bloquea los meses ya revisados para que nadie los cambie por error"))
        #endif
        .headerTitle()
        #if os(macOS)
        .macInspectorToggle(isAvailable: !history.isEmpty)
        .macReportInspector(title: macSelected?.periodTitle ?? String(localized: "Historial"), hasSelection: macSelected != nil,
                            placeholder: String(localized: "Aún no has cerrado ningún periodo."),
                            selectionKey: macPick?.uuidString, qaSelectRow: { index in
                                if history.indices.contains(index) { macPick = history[index].id }
                            }, isAvailable: !history.isEmpty) {
            if let record = macSelected { historyInspector(record) }
        } actions: {
            HStack(spacing: 8) {
                SectionLink(item: .report(.trial)) { ReportsView(fixedKind: .trial) } label: { Text("Ver balanza") }
                    .buttonStyle(.secondary)
                SectionLink(item: .accounting(.journal)) { JournalListView() } label: { Text("Ver asientos") }
                    .buttonStyle(.secondary)
            }
        }
        #endif
        .sheet(isPresented: $editingPassword) { NavigationStack { ClosingPasswordEditor() }.editorSheetSizing() }
        .alert(item: $reopening, password: $password, hasPassword: company?.hasClosingPassword ?? false) { request, typed in
            reopen(to: request.target, password: typed)
        }
        .alert("Quitar la contraseña de cierre", isPresented: $removingPassword) {
            SecureField("Contraseña actual", text: $password)
            Button("Quitar", role: .destructive) { removePassword() }
            Button("Cancelar", role: .cancel) { password = "" }
        } message: {
            Text("Sin contraseña, cualquiera con acceso a la app podrá reabrir los periodos cerrados.")
        }
        #if DEBUG
        .task { await qaActions() }
        #endif
    }

    // MARK: Acciones

    private func close(through target: Date) {
        do {
            try Bookkeeper(context: context).closeBooks(through: target, device: PeriodClosing.deviceName)
            newDate = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askReopenLast(_ lock: Date) {
        reopening = ReopenRequest(target: PeriodClosing.reopenTarget(from: lock),
                                  title: String(localized: "Reabrir \(lock.formatted(.appDateTime.month(.wide).year()))"))
    }

    private func reopen(to target: Date?, password: String?) {
        do {
            try Bookkeeper(context: context).reopenBooks(to: target, password: password, device: PeriodClosing.deviceName)
            newDate = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePassword() {
        let typed = password
        password = ""
        do {
            try Bookkeeper(context: context).removeClosingPassword(current: typed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - iPhone

    private var compactBody: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            if let company {
                let target = target(company)
                Section {
                    statusHeader(company, compact: true)
                }
                Section {
                    DatePicker("Nueva fecha de cierre", selection: Binding(get: { target }, set: { newDate = $0 }),
                               displayedComponents: .date)
                    Button(closeTitle(target)) { close(through: target) }
                        .disabled(!canClose(company, target: target))
                    if let lock = company.lockDate {
                        Button(String(localized: "Reabrir \(lock.formatted(.appDateTime.month(.wide).year()))")) { askReopenLast(lock) }
                        Button("Quitar cierre", role: .destructive) {
                            reopening = ReopenRequest(target: nil, title: String(localized: "Quitar cierre"))
                        }
                    }
                } header: {
                    SectionLabel(text: String(localized: "Cerrar periodo"))
                } footer: {
                    Text(isFuture(target) ? String(localized: "Solo se puede cerrar hasta hoy: elige una fecha que ya pasó.")
                         : String(localized: "No se podrá registrar nada con fecha igual o anterior al cierre. Así los reportes que ya entregaste no cambian."))
                }
                Section {
                    passwordControls(company)
                } header: {
                    SectionLabel(text: String(localized: "Contraseña de cierre"))
                } footer: {
                    Text(passwordFooter(company))
                }
                Section {
                    if history.isEmpty {
                        Text("Aún no has cerrado ningún periodo.").foregroundStyle(Palette.ink2)
                    }
                    ForEach(history) { record in
                        LedgerRow(title: "\(record.actionTitle) · \(record.periodTitle)",
                                  subtitle: [record.date.shortDate, record.origin].filter { !$0.isEmpty }.joined(separator: " · ")) {
                            EmptyView()
                        } trailing: {
                            Text(record.lockTitle).monospacedDigit().foregroundStyle(Palette.ink2)
                        }
                    }
                } header: {
                    SectionLabel(text: String(localized: "Historial de cierres"))
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
    }

    @ViewBuilder
    private func passwordControls(_ company: Company) -> some View {
        LabeledContent("Contraseña", value: company.hasClosingPassword ? String(localized: "Activada") : String(localized: "Sin contraseña"))
        if company.hasClosingPassword {
            Button("Cambiar contraseña…") { editingPassword = true }
            Button("Quitar contraseña…", role: .destructive) { password = ""; removingPassword = true }
        } else {
            Button("Fijar contraseña…") { editingPassword = true }
        }
    }

    private func passwordFooter(_ company: Company) -> String {
        company.hasClosingPassword
            ? String(localized: "Se pide para reabrir un periodo y para registrar algo con una fecha cerrada.")
            : String(localized: "Opcional: con contraseña, nadie puede reabrir un periodo ni registrar con una fecha cerrada sin escribirla.")
    }

    /// Candado en índigo y «Libros cerrados hasta» con la fecha en grande.
    private func statusHeader(_ company: Company, compact: Bool) -> some View {
        HStack(spacing: 12) {
            LargeIconTile(systemImage: company.lockDate == nil ? "lock.open" : "lock", color: Palette.indigo)
            VStack(alignment: .leading, spacing: 1) {
                Text(company.lockDate == nil ? String(localized: "Libros abiertos") : String(localized: "Libros cerrados hasta"))
                    .font(compact ? .footnote : .label).foregroundStyle(Palette.ink2)
                Text(company.lockDate?.shortDate ?? String(localized: "Sin cierre")).font(.amount(24)).foregroundStyle(Palette.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - iPad y Mac

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                if let company {
                    let target = target(company)
                    let checks = checklist(for: target)
                    statusBox(company, checks: checks, target: target)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            checklistBox(checks, target: target).frame(minWidth: 320, maxWidth: .infinity)
                            closeBox(company, target: target).frame(minWidth: 320, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 16) { checklistBox(checks, target: target); closeBox(company, target: target) }
                    }
                    historyBox
                }
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
    }

    /// Estado del mes a cerrar y el aviso (canvas: «Para corregirlas hay que reabrir el periodo con la contraseña»).
    private func statusBox(_ company: Company, checks: [Check], target: Date) -> some View {
        let pending = checks.filter { !$0.ok }.count
        let month = target.formatted(.appDateTime.month(.wide)).sentenceCased
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                statusHeader(company, compact: false)
                Spacer(minLength: 8)
                StatusChip(text: pending == 0 ? String(localized: "\(month) listo para cerrar") : String(localized: "\(month) tiene pendientes"),
                           foreground: pending == 0 ? Palette.positive : Palette.warning, background: .clear, compact: true,
                           dot: pending == 0 ? Palette.green : Palette.orange)
            }
            if let lock = company.lockDate {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    Text(company.hasClosingPassword
                         ? String(localized: "Las transacciones con fecha hasta el \(lock.shortDate) están bloqueadas. Para corregirlas hay que reabrir el periodo con la contraseña de cierre.")
                         : String(localized: "Las transacciones con fecha hasta el \(lock.shortDate) están bloqueadas. Para corregirlas, reabre el periodo."))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    // MARK: Lista de revisión

    fileprivate struct Check: Identifiable {
        let id: String
        let ok: Bool
        let title: String
        var note: String? = nil
        let item: SidebarItem
    }

    /// Lo que conviene revisar del mes que se va a cerrar, sacado de los datos (no se marca a mano).
    private func checklist(for target: Date) -> [Check] {
        let month = DateInterval.month(containing: target)
        let name = target.formatted(.appDateTime.month(.wide))
        let issued = invoices.filter { $0.status != .draft && $0.status != .void && month.contains($0.issueDate) }.count
        let drafts = invoices.filter { $0.status == .draft && month.contains($0.issueDate) }.count
        let monthExpenses = expenses.filter { month.contains($0.date) }
        let noReceipt = monthExpenses.filter { ($0.attachments ?? []).isEmpty }.count
        let monthBills = bills.filter { $0.status != .void && month.contains($0.billDate) }.count
        var checks = [Check(id: "invoices", ok: true, title: String(localized: "Facturas de \(name) emitidas (\(issued))"), item: .sales(.invoices))]
        if drafts > 0 {
            checks.append(Check(id: "drafts", ok: false, title: String(localized: "\(drafts) borradores de factura sin emitir"),
                                note: String(localized: "Emítelos o bórralos antes de cerrar"), item: .sales(.invoices)))
        }
        checks += [
            Check(id: "expenses", ok: true, title: String(localized: "Gastos de \(name) registrados (\(monthExpenses.count))"), item: .expenses(.expenses)),
            Check(id: "receipts", ok: noReceipt == 0,
                  title: noReceipt == 0 ? String(localized: "Todos los gastos tienen recibo") : String(localized: "\(noReceipt) gastos sin recibo adjunto"),
                  note: noReceipt == 0 ? nil : String(localized: "Adjunta los recibos que te falten"), item: .expenses(.expenses)),
            Check(id: "bills", ok: true, title: String(localized: "Facturas de proveedor de \(name) (\(monthBills))"), item: .expenses(.bills)),
            Check(id: "tax", ok: true, title: String(localized: "Revisa el impuesto sobre ventas"), item: .report(.salesTax)),
        ]
        return checks
    }

    private func checklistBox(_ checks: [Check], target: Date) -> some View {
        let ready = checks.filter(\.ok).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Antes de cerrar \(target.formatted(.appDateTime.month(.wide)))").font(.cardTitle).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(ready) de \(checks.count) listos").font(.footnote).foregroundStyle(Palette.ink2)
            }
            VStack(spacing: 0) {
                ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                    if index > 0 { Divider() }
                    checkRow(check)
                }
            }
            .padding(.horizontal, 12)
            .card(padding: 0)
        }
    }

    private func checkRow(_ check: Check) -> some View {
        SectionLink(item: check.item) {
            check.item.destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: check.ok ? "checkmark" : "exclamationmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(check.ok ? Palette.green : Palette.orange, in: Circle())
                    .accessibilityLabel(check.ok ? String(localized: "Listo") : String(localized: "Revisar"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.title).foregroundStyle(Palette.ink)
                    if let note = check.note { Text(note).font(.footnote).foregroundStyle(Palette.warning) }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.chevron).accessibilityHidden(true)
            }
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
    private static let rowHeight: CGFloat = 38
    #else
    private static let rowHeight: CGFloat = 52
    #endif

    // MARK: Cerrar periodo

    /// «Nueva fecha de cierre» y «Contraseña de cierre» en una caja; debajo «Reabrir …» y «Cerrar …».
    private func closeBox(_ company: Company, target: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cerrar periodo").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Nueva fecha de cierre").foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    DatePicker("Nueva fecha de cierre", selection: Binding(get: { target }, set: { newDate = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                        .fixedSize()
                        // En cifras sigue la región (1e6efbf): «10/31/26» en EE. UU.
                        .environment(\.locale, .app)
                }
                .frame(minHeight: Self.rowHeight)
                Divider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Contraseña de cierre").foregroundStyle(Palette.ink)
                        Text(company.hasClosingPassword ? String(localized: "Activada") : String(localized: "Sin contraseña"))
                            .font(.footnote).foregroundStyle(company.hasClosingPassword ? Palette.positive : Palette.ink2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    if company.hasClosingPassword {
                        Button("Quitar…") { password = ""; removingPassword = true }
                            .buttonStyle(.borderless).foregroundStyle(Palette.negative)
                            .accessibilityLabel("Quitar contraseña de cierre")
                        Button("Cambiar…") { editingPassword = true }
                            .buttonStyle(.secondary).fixedSize()
                            .accessibilityLabel("Cambiar contraseña de cierre")
                    } else {
                        Button("Fijar…") { editingPassword = true }
                            .buttonStyle(.secondary).fixedSize()
                            .accessibilityLabel("Fijar contraseña de cierre")
                    }
                }
                .frame(minHeight: Self.rowHeight)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 12)
            .card(padding: 0)
            if isFuture(target) {
                Text("Solo se puede cerrar hasta hoy: elige una fecha que ya pasó.")
                    .font(.footnote).foregroundStyle(Palette.ink2).padding(.horizontal, 2)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { Spacer(minLength: 0); closeButtons(company, target: target) }
                VStack(alignment: .trailing, spacing: 8) { closeButtons(company, target: target) }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func closeButtons(_ company: Company, target: Date) -> some View {
        if let lock = company.lockDate {
            Button("Quitar cierre", role: .destructive) {
                reopening = ReopenRequest(target: nil, title: String(localized: "Quitar cierre"))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.negative)
            Button(String(localized: "Reabrir \(lock.formatted(.appDateTime.month(.wide).year()))")) { askReopenLast(lock) }
                .buttonStyle(.secondary)
                .fixedSize()
        }
        Button(closeTitle(target)) { close(through: target) }
            .buttonStyle(.primaryCompact)
            .disabled(!canClose(company, target: target))
    }

    // MARK: Historial

    /// «Historial de cierres» (canvas): Periodo · Acción · Fecha de cierre · Cuándo · Aparato, del más reciente al más
    /// antiguo. En el Mac, la fila se elige para verla en el inspector.
    private var historyBox: some View {
        let closes = history.filter { !$0.wasReopen }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Historial de cierres").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(closes) periodos cerrados").font(.footnote).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 2)
            TableCard {
                Text("Periodo").frame(maxWidth: .infinity, alignment: .leading)
                Text("Acción").frame(width: 100, alignment: .leading)
                Text("Fecha de cierre").frame(width: 110, alignment: .leading)
                Text("Hecho el").frame(width: 100, alignment: .leading)
                Text("Aparato").frame(maxWidth: .infinity, alignment: .leading)
            } rows: {
                if history.isEmpty {
                    Text("Aún no has cerrado ningún periodo.").font(.subheadline).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(Array(history.enumerated()), id: \.element.id) { index, record in
                    historyRow(record, index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ record: PeriodClose, index: Int) -> some View {
        #if os(macOS)
        MacReportRow(isSelected: record.id == macSelected?.id, zebra: !index.isMultiple(of: 2), select: { macPick = record.id }) {
            historyCells(record)
        }
        #else
        TableRow { historyCells(record) }
        #endif
    }

    @ViewBuilder
    private func historyCells(_ record: PeriodClose) -> some View {
        Text(record.periodTitle).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        ReportCellText(text: record.actionTitle, color: record.wasReopen ? Palette.warning : Palette.ink2)
            .lineLimit(1).frame(width: 100, alignment: .leading)
        Text(record.lockTitle).lineLimit(1).frame(width: 110, alignment: .leading)
        ReportCellText(text: record.date.shortDate).lineLimit(1).frame(width: 100, alignment: .leading)
        ReportCellText(text: record.origin.isEmpty ? "—" : record.origin).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(macOS)
    private var macSelected: PeriodClose? { history.first { $0.id == macPick } ?? history.first }

    /// Inspector (canvas `MacCierre`): el periodo elegido, el resumen y «Acerca del cierre».
    @ViewBuilder
    private func historyInspector(_ record: PeriodClose) -> some View {
        MacInspectorSection(title: String(localized: "Periodo seleccionado")) {
            MacInspectorRow(String(localized: "Periodo"), value: record.periodTitle)
            MacInspectorRow(String(localized: "Acción"), value: record.actionTitle)
            MacInspectorRow(String(localized: "Fecha de cierre"), value: record.lockTitle)
            if let previous = record.previousLockDate { MacInspectorRow(String(localized: "Antes"), value: previous.shortDate) }
            MacInspectorRow(String(localized: "Hecho el"), value: record.date.formatted(.appDateTime.day().month(.abbreviated).year().hour().minute()))
            if !record.device.isEmpty { MacInspectorRow(String(localized: "Aparato"), value: record.device) }
            if !record.actor.isEmpty { MacInspectorRow(String(localized: "Por"), value: record.actor) }
            if !record.note.isEmpty { MacInspectorRow(String(localized: "Nota"), value: record.note) }
        }
        if let company {
            let target = target(company)
            let checks = checklist(for: target)
            MacInspectorSection(title: String(localized: "Resumen")) {
                MacInspectorRow(String(localized: "Libros cerrados hasta"), value: company.lockDate?.shortDate ?? String(localized: "Sin cierre"))
                MacInspectorRow(String(localized: "Lista de revisión"), value: String(localized: "\(checks.filter(\.ok).count) de \(checks.count) listos"))
                MacInspectorRow(String(localized: "Siguiente cierre"), value: target.shortDate)
                MacInspectorRow(String(localized: "Contraseña de cierre"),
                                value: company.hasClosingPassword ? String(localized: "Activada") : String(localized: "Sin contraseña"))
            }
        }
        MacInspectorSection(title: String(localized: "Acerca del cierre")) {
            Text("Cerrar un periodo impide crear, editar o borrar transacciones con fecha igual o anterior a la fecha de cierre. Solo se puede reabrir el último periodo cerrado.")
                .font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
    }
    #endif

    #if DEBUG
    /// QA sin ratón: `-qa.cierre cerrar|reabrir|contraseña` con `-qa.clave …` (solo Debug).
    private func qaActions() async {
        let defaults = UserDefaults.standard
        guard let action = defaults.string(forKey: "qa.cierre"), !QAOnce.cierre else { return }
        QAOnce.cierre = true
        try? await Task.sleep(for: .seconds(1))
        guard let company else { return }
        let key = defaults.string(forKey: "qa.clave")
        switch action {
        case "cerrar": close(through: target(company))
        case "reabrir":
            // Con `-qa.clave`, reabre con esa contraseña (sin pasar por la alerta); sin ella, abre la alerta.
            if let lock = company.lockDate {
                if let key { reopen(to: PeriodClosing.reopenTarget(from: lock), password: key) } else { askReopenLast(lock) }
            }
        case "quitar": password = ""; removingPassword = true
        case "contraseña": editingPassword = true
        case "fijar":
            // Fija `-qa.clave` como contraseña sin pasar por la hoja (para probar después la alerta de reabrir).
            if let key { do { try Bookkeeper(context: context).setClosingPassword(key) } catch { errorMessage = error.localizedDescription } }
        default: break
        }
    }
    #endif
}

#if DEBUG
/// La página puede aparecer dos veces al arrancar: la acción de QA, una sola vez.
private enum QAOnce { static var cierre = false }
#endif

// MARK: - Alerta de reapertura

private extension View {
    /// «Reabrir septiembre 2026»: con contraseña de cierre, la pide en la alerta; sin ella, solo confirma.
    func alert(item: Binding<PeriodCloseView.ReopenRequest?>, password: Binding<String>, hasPassword: Bool,
               perform: @escaping (PeriodCloseView.ReopenRequest, String?) -> Void) -> some View {
        alert(item.wrappedValue?.title ?? "", isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
              presenting: item.wrappedValue) { request in
            if hasPassword { SecureField("Contraseña de cierre", text: password) }
            Button(request.target == nil ? "Quitar cierre" : "Reabrir", role: request.target == nil ? .destructive : nil) {
                let typed = password.wrappedValue
                password.wrappedValue = ""
                perform(request, hasPassword ? typed : nil)
            }
            Button("Cancelar", role: .cancel) { password.wrappedValue = "" }
        } message: { request in
            if let target = request.target {
                Text("Los libros quedarán cerrados hasta el \(target.shortDate) y se podrá registrar otra vez en el periodo reabierto. Quedará en el historial.")
            } else {
                Text("No quedará ningún periodo cerrado. Quedará en el historial.")
            }
        }
    }
}
