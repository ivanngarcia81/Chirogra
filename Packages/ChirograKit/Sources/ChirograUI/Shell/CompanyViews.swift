import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Varias empresas: selector, lista y alta (versión 1.1, PLAN-FASE2 §1)
//
// - Selector: en Inicio, el «Empresa · Mes ▾» del iPhone y de la columna del iPad (canvas `Home`, `iPadInicio`) y, en
//   iPad y Mac, la ficha de la empresa al pie de la barra lateral con «⌃⌄» (canvas `Sidebar`). Los dos abren el mismo
//   menú: las empresas, «Añadir empresa…» y «Empresas…».
// - «Empresas» (Ajustes › Empresas, y la hoja del selector): lo pendiente de cada una, orden, archivar y borrar.
// - «Añadir empresa»: el alta de siempre (`OnboardingView`) en una hoja, sin «Probar con datos de ejemplo».
// - Límite por plan (`SubscriptionStore.companyLimit`): al pasarlo se ofrece el plan para contadores.

/// Hojas de empresas que presenta la raíz (`companySheets()`), para que sigan abiertas al cambiar la empresa activa
/// (la app se rehace debajo) y no choquen entre sí: de la lista se pasa al alta o al plan cambiando `sheet`.
@MainActor
@Observable
final class CompanyHub {
    static let shared = CompanyHub()

    enum Sheet: String, Identifiable {
        /// Lista de empresas («Empresas…» del selector).
        case list
        /// Alta de otra empresa.
        case add
        /// Plan para contadores, al llegar al límite del plan normal.
        case accountantPlan
        var id: String { rawValue }
    }

    /// Por qué no se puede añadir otra empresa, cuando no hay plan que ofrecer.
    enum LimitNotice: Identifiable {
        /// Los libros son los de ejemplo: «Empezar con mi empresa» los borra y deja crear la propia.
        case sampleBooks
        /// Ya tiene el plan para contadores (o el plan no está a la venta) y llegó a su límite.
        case full(Int)
        var id: String {
            switch self {
            case .sampleBooks: "sample"
            case .full(let limit): "full-\(limit)"
            }
        }
    }

    var sheet: Sheet?
    var limitNotice: LimitNotice?
    /// Empresa elegida con un editor sin guardar a la vista: `AppShell` pregunta «¿Descartar los cambios?» antes de
    /// cambiar (como al cambiar de pantalla). Si se cancela, no se cambia.
    var pendingCompanyID: UUID?
    /// Cambios sin guardar de la ventana (`AppShell` registra los suyos al aparecer).
    @ObservationIgnored weak var unsavedChanges: UnsavedChanges?

    /// Deja activa otra empresa (la raíz rehace la app con ella). Con un editor sin guardar, primero se pregunta
    /// (`pendingCompanyID`); si hay un aviso de «Cancelar» cerrándose, se espera a que termine, como la barra lateral.
    func select(_ id: UUID) {
        guard id != CompanySession.scope?.id else { return }
        if let unsaved = unsavedChanges, unsaved.hasChanges, unsaved.isSettling() {
            Task { @MainActor in
                while let unsaved = unsavedChanges, unsaved.hasChanges, unsaved.isSettling() {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                decide(id)
            }
        } else {
            decide(id)
        }
    }

    private func decide(_ id: UUID) {
        if unsavedChanges?.hasChanges == true { pendingCompanyID = id } else { ActiveCompany.id = id }
    }

    /// «Descartar» del aviso: se pierden los cambios y se cambia de empresa.
    func discardAndSwitch() {
        unsavedChanges?.discardAll()
        if let id = pendingCompanyID { ActiveCompany.id = id }
        pendingCompanyID = nil
    }

    /// «Añadir empresa…»: el alta si cabe en el plan; si no, el plan para contadores (o por qué no se puede). En solo
    /// lectura, la pantalla de suscripción.
    func requestAdd(in context: ModelContext) {
        let store = SubscriptionStore.shared
        if store.isReadOnly {
            sheet = nil
            store.paywallFocus = .all
            store.showsPaywall = true
            return
        }
        Task {
            // Antes de la primera respuesta de la App Store el límite es el del plan normal: se pregunta primero.
            if store.status == .unknown { await store.refresh() }
            let books = Bookkeeper(context: context)
            if (try? books.canAddCompany()) == true {
                sheet = .add
            } else if (try? SampleData.isSample(context)) == true {
                sheet = nil
                limitNotice = .sampleBooks
            } else if store.plan == .standard && store.sellsAccountantPlan {
                sheet = .accountantPlan
            } else {
                sheet = nil
                limitNotice = .full(Bookkeeper.companyLimit)
            }
        }
    }
}

extension View {
    /// En la raíz: la lista de empresas, el alta de otra y el plan para contadores (`CompanyHub`).
    func companySheets() -> some View {
        modifier(CompanySheets())
    }
}

private struct CompanySheets: ViewModifier {
    @State private var hub = CompanyHub.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $hub.sheet) { sheet in
                switch sheet {
                case .list:
                    NavigationStack { CompaniesView(inSheet: true) }
                        #if os(macOS)
                        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 600)
                        #endif
                case .add:
                    AddCompanySheet()
                case .accountantPlan:
                    PaywallView(focus: .accountant)
                }
            }
            .alert(item: $hub.limitNotice) { notice in
                switch notice {
                case .sampleBooks:
                    Alert(title: Text("Estás usando los datos de ejemplo"),
                          message: Text("Tu plan es para una empresa y la de ejemplo ya la ocupa. Bórrala con «Empezar con mi empresa» y crea la tuya."),
                          primaryButton: .default(Text("Empezar con mi empresa")) { SampleBooks.shared.confirm() },
                          secondaryButton: .cancel(Text("Cancelar")))
                case .full(let limit):
                    Alert(title: Text("Llegaste al límite de empresas"),
                          message: Text("Tu plan permite \(limit) empresas, contando las archivadas. Para añadir otra, borra una que ya no uses en Ajustes › Empresas."),
                          dismissButton: .cancel(Text("Aceptar")))
                }
            }
    }
}

// MARK: - Selector

/// Opciones del selector de empresa (para un `Menu`): las empresas con la activa marcada, «Añadir empresa…» y
/// «Empresas…». `companies` las pasa la vista que tiene el menú (todas, también las archivadas: aquí se quitan).
struct CompanyMenuItems: View {
    let companies: [Company]
    @Environment(\.modelContext) private var context

    var body: some View {
        let shown = companies.filter { !$0.isArchived }.inSelectorOrder
        let active = CompanySession.scope?.id
        // Plan para contadores: el panel con todas (canvas `iPhoneEntrada`).
        if ClientsRouter.isAvailable(companies: companies) {
            SettingsSection {
                Button("Todos los clientes", systemImage: "building.2") { ClientsRouter.shared.showPanel() }
            }
        }
        SettingsSection {
            Picker(selection: Binding(get: { active }, set: { if let id = $0 { CompanyHub.shared.select(id) } })) {
                ForEach(shown) { company in
                    Text(company.shownName).tag(Optional(company.id))
                }
            } label: {
                Text("Empresa")
            }
            .pickerStyle(.inline)
        } header: {
            Text("Empresa")
        }
        SettingsSection {
            Button("Añadir empresa…", systemImage: "plus") { CompanyHub.shared.requestAdd(in: context) }
            Button("Empresas…", systemImage: "building.2") { CompanyHub.shared.sheet = .list }
        }
    }
}

// MARK: - Lista de empresas

/// «Empresas» (Ajustes › Empresas y la hoja del selector): cada empresa con lo pendiente (por cobrar, vencidas, por pagar,
/// sales tax por pagar, avisos y movimientos por revisar), la activa marcada; tocar una la deja activa. Se ordenan
/// arrastrando («Editar» en iPhone y iPad), se archivan (salen del selector; siguen contando para el límite del plan)
/// y se borran con confirmación (irreversible, también en iCloud; antes se ofrece una copia).
struct CompaniesView: View {
    /// En la hoja del selector: «Listo» y, al elegir una, se cierra.
    var inSheet = false
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var companies: [Company]
    @Query(filter: SampleData.sampleCreationsPredicate) private var sampleCreations: [AuditEvent]
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @State private var overviews: [UUID: CompanyOverview] = [:]
    @State private var salesTaxOwed: [UUID: Int64] = [:]
    @State private var deleting: Company?
    @State private var errorMessage: String?
    @State private var backup: BackupDocument?
    @State private var backupName = ""
    private let store = SubscriptionStore.shared

    private var shown: [Company] { companies.filter { !$0.isArchived }.inSelectorOrder }
    private var archived: [Company] { companies.filter(\.isArchived).inSelectorOrder }
    private var sampleIDs: Set<UUID> { Set(sampleCreations.compactMap(\.entityID)) }
    private var activeID: UUID? { CompanySession.scope?.id }

    var body: some View {
        SettingsForm {
            SettingsSection {
                ForEach(shown) { company in row(company) }
                    .onMove(perform: move)
                Button { CompanyHub.shared.requestAdd(in: context) } label: {
                    Label("Añadir empresa…", systemImage: "plus.circle.fill")
                        .foregroundStyle(Palette.brand)
                        .frame(minHeight: Metrics.target)
                }
                .buttonStyle(.borderless)
            } header: {
                SectionLabel(text: String(localized: "Empresas"))
            } footer: {
                Text(limitText)
            }
            if !archived.isEmpty {
                SettingsSection {
                    ForEach(archived) { company in row(company) }
                } header: {
                    SectionLabel(text: String(localized: "Archivadas"))
                } footer: {
                    Text("No salen en el selector, pero sus libros siguen guardados y cuentan para el límite del plan. Bórrala para dejar sitio.")
                }
            }
            if let errorMessage {
                SettingsSection(plain: true) { ErrorBanner(message: errorMessage) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        #if os(macOS)
        .navigationTitle(embedded ? String(localized: "Ajustes") : String(localized: "Empresas"))
        #else
        .navigationTitle("Empresas")
        #endif
        .toolbar {
            #if os(iOS)
            if shown.count > 1 { ToolbarItem(placement: .primaryAction) { EditButton() } }
            #endif
            if inSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
        .task(id: companies.map { "\($0.id)\($0.isArchived)" }) { reload() }
        .alert(deleting.map { String(localized: "¿Borrar «\($0.shownName)» y todos sus libros?") } ?? "",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { company in
            Button("Crear una copia antes…") { makeBackup(of: company) }
            Button("Borrar para siempre", role: .destructive) { delete(company) }
            Button("Cancelar", role: .cancel) {}
        } message: { company in
            Text(deleteMessage(company))
        }
        .fileExporter(isPresented: Binding(get: { backup != nil }, set: { if !$0 { backup = nil } }),
                      document: backup, contentType: .chirograBackup,
                      defaultFilename: BackupArchive.suggestedFilename(companyName: backupName)) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
    }

    // MARK: Fila

    private func row(_ company: Company) -> some View {
        let isActive = company.id == activeID
        return HStack(spacing: 12) {
            Button { choose(company) } label: {
                HStack(spacing: 12) {
                    CompanyMonogram(name: company.shownName, side: Self.monogramSide)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(company.shownName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                .layoutPriority(1)
                            if sampleIDs.contains(company.id) {
                                Text("Ejemplo").font(.caption.weight(.semibold)).foregroundStyle(Palette.orange)
                                    .fixedSize()
                            }
                        }
                        ForEach(details(company), id: \.self) { line in
                            Text(line).font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    }
                    .lineLimit(2)
                    Spacer(minLength: 8)
                    if isActive {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.brand)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: Metrics.target)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(company.isArchived)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityHint(company.isArchived ? Text("Archivada") : isActive ? Text("Es la empresa activa") : Text("Cambia a esta empresa"))
            actionsMenu(company)
        }
        .contextMenu { actions(company) }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleting = company } label: { Label("Borrar…", systemImage: "trash") }
            if company.isArchived {
                Button { unarchive(company) } label: { Label("Mostrar", systemImage: "tray.and.arrow.up") }
            } else {
                Button { archive(company) } label: { Label("Archivar", systemImage: "archivebox") }.tint(Palette.gray)
            }
        }
        #endif
    }

    /// «⋯» de la fila: las mismas acciones del menú contextual, a la vista (en el Mac no hay deslizar).
    private func actionsMenu(_ company: Company) -> some View {
        Menu { actions(company) } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Palette.brand)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(Text("Acciones de \(company.shownName)"))
    }

    @ViewBuilder
    private func actions(_ company: Company) -> some View {
        if !company.isArchived && company.id != activeID {
            Button("Usar esta empresa", systemImage: "checkmark.circle") { choose(company) }
        }
        #if os(macOS)
        // En el Mac las empresas van en tarjetas (`SettingsForm`), no en la lista del sistema: no se arrastran, se
        // suben y se bajan desde aquí.
        if !company.isArchived, shown.count > 1, let index = shown.firstIndex(where: { $0.id == company.id }) {
            if index > 0 {
                Button("Subir", systemImage: "arrow.up") { move(from: IndexSet(integer: index), to: index - 1) }
            }
            if index < shown.count - 1 {
                Button("Bajar", systemImage: "arrow.down") { move(from: IndexSet(integer: index), to: index + 2) }
            }
        }
        #endif
        Button("Crear copia…", systemImage: "externaldrive.badge.plus") { makeBackup(of: company) }
        if company.isArchived {
            Button("Mostrar en el selector", systemImage: "tray.and.arrow.up") { unarchive(company) }
        } else if shown.count > 1 {
            Button("Archivar", systemImage: "archivebox") { archive(company) }
        }
        Divider()
        Button("Borrar…", systemImage: "trash", role: .destructive) { deleting = company }
    }

    /// Lo pendiente, en una o dos líneas: «Por cobrar $1,250 · 2 vencidas» y «Por pagar $300 · Sales tax $82».
    private func details(_ company: Company) -> [String] {
        guard let overview = overviews[company.id] else { return [] }
        var first: [String] = [String(localized: "Por cobrar \(overview.receivables.moneyWhole)")]
        if overview.overdueInvoices > 0 { first.append(String(localized: "\(overview.overdueInvoices) vencidas")) }
        var second: [String] = [String(localized: "Por pagar \(overview.payables.moneyWhole)")]
        if let tax = salesTaxOwed[company.id], tax > 0 { second.append(String(localized: "Sales tax \(tax.moneyWhole)")) }
        if overview.unreadNotices > 0 { second.append(String(localized: "\(overview.unreadNotices) avisos")) }
        if overview.bankTransactionsToReview > 0 { second.append(String(localized: "\(overview.bankTransactionsToReview) por revisar")) }
        return [first.joined(separator: " · "), second.joined(separator: " · ")]
    }

    private var limitText: String {
        let limit = Bookkeeper.companyLimit
        let used = companies.count
        if store.plan == .accountant && !store.isReadOnly && CompanyLimits.isUnlimited(limit) {
            return String(localized: "Plan para contadores: \(used) empresas, sin límite.")
        }
        if limit <= CompanyLimits.standard {
            return String(localized: "Tu plan es para una empresa. Con el plan para contadores llevas todas las que quieras.")
        }
        if CompanyLimits.isUnlimited(limit) { return String(localized: "\(used) empresas, sin límite.") }
        return String(localized: "Hasta \(limit) empresas, contando las archivadas.")
    }

    private func deleteMessage(_ company: Company) -> String {
        var text = String(localized: "Se borran sus clientes, proveedores, facturas, gastos, asientos, recibos y ajustes. No se puede deshacer.")
        if iCloudSyncEnabled { text += " " + String(localized: "También se borran en iCloud y en tus otros aparatos.") }
        text += " " + String(localized: "Si quieres conservarlos, crea antes una copia.")
        return text
    }

    // MARK: Acciones

    private func reload() {
        let books = Bookkeeper(context: context)
        let list = (try? books.companyOverviews(includeArchived: true)) ?? []
        overviews = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var taxes: [UUID: Int64] = [:]
        // Solo las cuentas de sales tax por pagar, por sus propias líneas (con muchas empresas, leer todo el diario de
        // cada una tardaba segundos).
        for company in companies {
            let scoped = books.forCompany(company.id)
            guard let accounts = try? scoped.accounts(includeArchived: true) else { continue }
            taxes[company.id] = accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + scoped.postedBalance(of: $1) }
        }
        salesTaxOwed = taxes
    }

    private func choose(_ company: Company) {
        guard !company.isArchived else { return }
        if inSheet {
            // Primero se cierra la hoja: si hay cambios sin guardar, el aviso sale en la ventana.
            dismiss()
            let id = company.id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                CompanyHub.shared.select(id)
            }
        } else {
            CompanyHub.shared.select(company.id)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = shown
        ordered.move(fromOffsets: source, toOffset: destination)
        perform { try Bookkeeper(context: context).reorderCompanies(ordered) }
    }

    private func archive(_ company: Company) {
        perform { try Bookkeeper(context: context).archiveCompany(company) }
    }

    private func unarchive(_ company: Company) {
        perform { try Bookkeeper(context: context).unarchiveCompany(company) }
    }

    private func delete(_ company: Company) {
        perform { try Bookkeeper(context: context).deleteCompany(company) }
    }

    private func makeBackup(of company: Company) {
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            backupName = company.shownName
            backup = BackupDocument(data: try BackupArchive.make(from: context, companyID: company.id, appVersion: version))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(macOS)
    private static let monogramSide: CGFloat = 32
    #else
    private static let monogramSide: CGFloat = 40
    #endif
}

// MARK: - Añadir empresa

/// «Añadir empresa»: el alta de siempre en una hoja (`OnboardingView(addsCompany: true)`), sin los datos de ejemplo
/// (ya hay empresa: probar la app con otra inventada no tiene sentido, y los de ejemplo se reconocen solo si **todas** las
/// empresas lo son). Al terminar, la empresa nueva queda activa y la hoja se cierra.
struct AddCompanySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OnboardingView(addsCompany: true, onFinish: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                }
        }
        .editorSheetSizing()
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 640, minHeight: 640, idealHeight: 720)
        #endif
    }
}
