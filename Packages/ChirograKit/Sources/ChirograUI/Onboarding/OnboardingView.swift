import ChirograData
import SwiftData
import SwiftUI

/// Alta de empresa (canvas `OnbEmpresa`, `OnbTipo`; `AltaPaso1`, `AltaPaso2` e `iPadAltaPaso1` en iPad y Mac).
/// Paso 1: nombre, idioma de la app, estado (con lo que se hará con su sales tax), año fiscal e ID fiscal. Paso 2: tipo
/// de negocio, que decide la plantilla del plan de cuentas. Paso 3 (en el sitio del «Conectar banco» del canvas, que es
/// de la fase 2): con cuánto dinero empieza la cuenta del banco y, opcional, lo que se debe en la tarjeta; se puede
/// saltar y hacerlo después desde los primeros pasos de Inicio.
/// Los tres como formularios agrupados del sistema con un encabezado grande centrado; en iPhone e iPad, una barra de
/// vidrio abajo con los puntos de paso y «Continuar»; en el Mac, el pie de la ventana con «Atrás» y «Continuar».
/// Al crear la empresa se crean también la tasa estatal base como impuesto predeterminado (`setUpStateSalesTax`) y el
/// asiento de apertura (`recordOpeningBalances`). El logotipo de la empresa no está en el MVP.
struct OnboardingView: View {
    /// Tipos de negocio del canvas; cada uno usa una de las plantillas de plan de cuentas.
    enum Kind: String, CaseIterable, Identifiable {
        case professional, retail, construction, food, health, freelance
        var id: String { rawValue }

        var title: String {
            switch self {
            case .professional: String(localized: "Servicios profesionales")
            case .retail: String(localized: "Comercio o tienda")
            case .construction: String(localized: "Construcción y oficios")
            case .food: String(localized: "Restaurante y comida")
            case .health: String(localized: "Salud y bienestar")
            case .freelance: String(localized: "Independiente")
            }
        }

        var systemImage: String {
            switch self {
            case .professional: "briefcase.fill"
            case .retail: "storefront.fill"
            case .construction: "hammer.fill"
            case .food: "fork.knife"
            case .health: "heart.fill"
            case .freelance: "person.fill"
            }
        }

        /// Color del icono de la fila (canvas `OnbTipo`).
        var color: Color {
            switch self {
            case .professional: Palette.blue
            case .retail: Palette.green
            case .construction: Palette.orange
            case .food: Palette.red
            case .health: Palette.pink
            case .freelance: Palette.purple
            }
        }

        var sector: BusinessSector {
            switch self {
            case .retail, .food: .retail
            case .construction: .construction
            case .professional, .health, .freelance: .services
            }
        }
    }

    @Environment(\.modelContext) private var context
    @State private var step = 1
    @State private var displayName = ""
    @State private var legalName = ""
    @State private var state = ""
    @State private var fiscalStartMonth = 1
    @State private var ein = ""
    @State private var entityType: EntityType = .soleProprietorship
    /// El usuario eligió el tipo de empresa a mano: el nombre ya no lo cambia.
    @State private var entityTypeChosen = false
    @State private var kind: Kind = .construction
    @State private var openingBank: Int64 = 0
    @State private var openingCard: Int64 = 0
    @State private var openingDate = Date()
    @State private var errorMessage: String?

    private static let stepCount = 3

    var body: some View {
        Form {
            switch step {
            case 1: companyStep
            case 2: typeStep
            default: bankStep
            }
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: Self.columnWidth)
        .frame(maxWidth: .infinity)
        .background(Palette.background)
        // Cada paso empieza arriba: el paso 2 heredaba el desplazamiento del 1.
        .id(step)
        // «Listo» sobre el teclado decimal de los saldos (paso 3), que no tiene tecla para cerrarse.
        .keyboardDoneButton()
        .onChange(of: displayName) { suggestEntityType() }
        .onChange(of: legalName) { suggestEntityType() }
        #if os(iOS)
        .safeAreaBar(edge: .top, spacing: 0) { if step > 1 { backBar } }
        // Mientras se escribe, la barra se esconde: subía con el teclado y tapaba los campos (en el paso 3, «Fecha del
        // saldo» y la tarjeta).
        .bottomBarHiddenWithKeyboard { bottomBar }
        #else
        .safeAreaInset(edge: .bottom, spacing: 0) { macFooter }
        #endif
        #if DEBUG
        .onAppear(perform: applyQALaunch)
        #endif
    }

    #if DEBUG
    /// Argumentos de QA (solo Debug), para capturas del alta sin tocar la pantalla: `-qa.alta N` abre el paso N con el
    /// nombre «Taller Uno»; `-qa.altaEstado TX` elige el estado; `-qa.altaBanco 1250000` y `-qa.altaTarjeta 30000`
    /// ponen los saldos (en centavos); `-qa.altaCrear 1` crea la empresa al momento.
    private func applyQALaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "qa.alta") != nil, displayName.isEmpty else { return }
        displayName = "Taller Uno"
        state = defaults.string(forKey: "qa.altaEstado") ?? state
        openingBank = Int64(defaults.integer(forKey: "qa.altaBanco"))
        openingCard = Int64(defaults.integer(forKey: "qa.altaTarjeta"))
        step = min(max(defaults.integer(forKey: "qa.alta"), 1), Self.stepCount)
        guard defaults.bool(forKey: "qa.altaCrear") else { return }
        createCompany()
        // `-qa.altaGasto 1`: además, un gasto de $45 pagado con el banco (Inicio pasa al tablero con los pasos pendientes).
        guard defaults.bool(forKey: "qa.altaGasto"), let accounts = try? Bookkeeper(context: context).accounts(),
              let bank = accounts.first(where: { $0.subtype == .bank }),
              let supplies = accounts.first(where: { $0.subtype == .operatingExpense }) else { return }
        let expense = Expense(payee: "Office Depot", paymentAccountID: bank.id)
        context.insert(expense)
        let line = ExpenseLine(details: "Office Depot", amount: 4_500, accountID: supplies.id)
        line.expense = expense
        context.insert(line)
        try? Bookkeeper(context: context).record(expense)
    }
    #endif

    #if os(macOS)
    private static let columnWidth: CGFloat = 560
    #else
    private static let columnWidth: CGFloat = 600
    #endif

    /// El estado es obligatorio: decide qué sales tax se cobra.
    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && !state.isEmpty
    }

    /// Tipo de empresa según el final del nombre comercial o de la razón social, mientras no se elija a mano.
    private func suggestEntityType() {
        guard !entityTypeChosen else { return }
        entityType = EntityType.suggested(forName: displayName) ?? EntityType.suggested(forName: legalName) ?? .soleProprietorship
    }

    private func advance() {
        if step < Self.stepCount { step += 1 } else { createCompany() }
    }

    // MARK: Encabezado

    /// Encabezado grande centrado del paso (canvas: logotipo o símbolo, título de 34 pt y una frase gris), seguido del
    /// título del primer grupo.
    private func header<Icon: View>(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, group: String,
                                    @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                icon().padding(.bottom, 8)
                Text(title).font(Self.titleFont).foregroundStyle(Palette.ink)
                    // En el iPad el encabezado de la sección lo dejaba en una línea («…tu cu…»).
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(Self.subtitleFont).foregroundStyle(Palette.ink2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 22)
            SectionLabel(text: group).frame(maxWidth: .infinity, alignment: .leading)
        }
        .textCase(nil)
    }

    #if os(macOS)
    private static let titleFont = Font.system(size: 26, weight: .bold)
    private static let subtitleFont = Font.body
    private static let logoSize: CGFloat = 64
    #else
    private static let titleFont = Font.largeTitle.bold()
    private static let subtitleFont = Font.body
    private static let logoSize: CGFloat = 72
    #endif

    // MARK: Paso 1 (`OnbEmpresa`, `AltaPaso1`)

    @ViewBuilder
    private var companyStep: some View {
        Section {
            TextField("Nombre de la empresa", text: $displayName, prompt: Text("Nombre"))
                // En iOS el título del campo no llega a VoiceOver dentro de un formulario: solo leía «Nombre».
                .accessibilityLabel(Text("Nombre de la empresa"))
                #if os(iOS)
                .textContentType(.organizationName)
                #endif
        } header: {
            header("Creemos tu empresa", subtitle: "Estos datos aparecen en tus facturas. Puedes cambiarlos cuando quieras en Ajustes.",
                   group: String(localized: "Nombre de la empresa")) {
                LogoMark(size: Self.logoSize)
            }
        }

        AppLanguageSection()

        Section {
            LabeledContent("País o región") { Text("Estados Unidos") }
            LabeledContent("Moneda") { Text("USD · Dólar") }
            Picker("Estado de EE. UU.", selection: $state) {
                Text("Elige tu estado").tag("")
                ForEach(StateSalesTax.all, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
            }
            // Lo que se hará con su sales tax, justo debajo del estado (al pie quedaba detrás de la barra de abajo).
            if let note = StateTaxNote.text(for: state) {
                Label { Text(note) } icon: { Image(systemName: "percent").foregroundStyle(Palette.brand) }
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Inicio del año fiscal", selection: $fiscalStartMonth) {
                ForEach(1...12, id: \.self) { month in
                    Text(Calendar.current.standaloneMonthSymbols[month - 1].sentenceCased).tag(month)
                }
            }
            // Preelegido por el nombre («… LLC» → LLC); antes el alta no lo preguntaba y toda empresa quedaba como
            // negocio propio.
            Picker("Tipo de empresa", selection: Binding(get: { entityType }, set: { entityType = $0; entityTypeChosen = true })) {
                ForEach(EntityType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            optionalField("Razón social", text: $legalName)
            optionalField("ID fiscal (EIN)", text: $ein)
        } header: {
            SectionLabel(text: String(localized: "Detalles"))
        } footer: {
            Text("Tus libros se llevan en dólares (USD). El estado decide el sales tax que cobras; es obligatorio.")
        }
    }

    /// Campo opcional con su nombre a la izquierda y el texto a la derecha, como las filas del canvas. En iOS el
    /// `TextField` de un formulario no muestra su título, así que va dentro de un `LabeledContent`.
    @ViewBuilder
    private func optionalField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        #if os(macOS)
        TextField(title, text: text, prompt: Text("Opcional"))
        #else
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text("Opcional"))
                .multilineTextAlignment(.trailing)
        }
        // El estilo de la app fija el ancho del valor (`fixedSize`): el campo quedaba del tamaño del texto de ayuda.
        .labeledContentStyle(.automatic)
        #endif
    }

    // MARK: Paso 2 (`OnbTipo`, `AltaPaso2`)

    @ViewBuilder
    private var typeStep: some View {
        Section {
            ForEach(Kind.allCases) { option in kindRow(option) }
        } header: {
            header("¿A qué se dedica tu negocio?", subtitle: "Te sugerimos un plan de cuentas listo para usar.",
                   group: String(localized: "Tipo de negocio")) {
                Image(systemName: "building.2")
                    .font(.system(size: Self.logoSize * 0.55, weight: .regular))
                    .foregroundStyle(Palette.brand)
                    .accessibilityHidden(true)
            }
        }

        let entries = kind.sector.template.entries
        Section {
            Text(suggestedAccounts(entries))
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: String(localized: "Plan de cuentas sugerido"))
                Spacer(minLength: 8)
                SectionLabel(text: String(localized: "\(entries.count) cuentas"))
            }
        } footer: {
            Text("Podrás añadir, renombrar o archivar cuentas en Contabilidad.")
        }
    }

    /// Tipo de negocio como fila de lista con su icono de color y la marca de selección en Tinta (en el Mac, también
    /// cuántas cuentas trae su plan, como `AltaPaso2`).
    private func kindRow(_ option: Kind) -> some View {
        let selected = kind == option
        return Button { kind = option } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: option.systemImage, foreground: option.color)
                Text(option.title).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                Text("\(option.sector.template.entries.count) cuentas").font(.subheadline).foregroundStyle(Palette.ink2)
                #endif
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.brand)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Cuentas propias del sector (ingresos, costos, inventario) en una frase, y cuántas más se crearán. En el mismo
    /// idioma con que `setUpCompany` creará las cuentas.
    private func suggestedAccounts(_ entries: [ChartTemplate.Entry]) -> String {
        let featured = entries.filter { [.sales, .costOfGoodsSold, .inventory, .operatingExpense].contains($0.subtype) }
            .prefix(6).map { $0.name(for: .current) }
        let names = featured.joined(separator: ", ")
        let rest = entries.count - featured.count
        return rest > 0 ? String(localized: "\(names) y \(rest) más.") : names
    }

    // MARK: Paso 3: saldo del banco

    @ViewBuilder
    private var bankStep: some View {
        OpeningBalanceFields(bank: $openingBank, card: $openingCard, date: $openingDate) {
            header("¿Cuánto dinero tiene hoy tu cuenta del negocio?",
                   subtitle: "Así «Efectivo disponible» empieza con el dinero que de verdad tienes. Si ahora no lo sabes, salta este paso: podrás ponerlo desde Inicio.",
                   group: String(localized: "Cuenta del banco")) {
                Image(systemName: "building.columns")
                    .font(.system(size: Self.logoSize * 0.55, weight: .regular))
                    .foregroundStyle(Palette.brand)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hasOpeningBalances: Bool { openingBank > 0 || openingCard > 0 }

    /// «Saltar por ahora»: crea la empresa sin saldos.
    private func skipBalances() {
        openingBank = 0
        openingCard = 0
        createCompany()
    }

    // MARK: Barra de abajo

    /// Puntos de paso (canvas: el actual en `label`, los demás al 25 %).
    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(1...Self.stepCount, id: \.self) { index in
                Circle().fill(Palette.ink).opacity(index == step ? 1 : 0.25).frame(width: Self.dotSide, height: Self.dotSide)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Paso \(step) de \(Self.stepCount)"))
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case 1: "Continuar"
        #if os(macOS)
        case 2: "Continuar"
        #else
        case 2: "Usar este plan"
        #endif
        default: "Crear empresa"
        }
    }

    #if os(macOS)
    private static let dotSide: CGFloat = 7
    #else
    private static let dotSide: CGFloat = 8
    #endif

    #if os(iOS)
    /// Barra de vidrio que flota abajo (canvas `OnbEmpresa`): puntos de paso, «Continuar» y, en el paso 1, los datos de
    /// ejemplo para probar la app.
    private var bottomBar: some View {
        VStack(spacing: 12) {
            stepDots
            Button(primaryTitle, action: advance)
                .buttonStyle(.primary)
                .disabled(!canContinue)
            if step == 1 {
                Button("Probar con datos de ejemplo", action: loadSample)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: Metrics.target)
            } else if step == Self.stepCount {
                Button("Saltar por ahora", action: skipBalances)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: Metrics.target)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, step == 2 ? 12 : 2)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: Self.columnWidth)
    }

    /// «Atrás» del paso 2: círculo de vidrio arriba a la izquierda (canvas `OnbTipo`).
    private var backBar: some View {
        HStack {
            Button { step -= 1 } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Palette.ink)
            .accessibilityLabel("Atrás")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .frame(maxWidth: Self.columnWidth)
    }
    #else
    /// Pie de la ventana del Mac (`AltaPaso1`, `AltaPaso2`): puntos de paso a la izquierda; «Atrás» y la acción a la
    /// derecha, con Retorno.
    private var macFooter: some View {
        HStack(spacing: 12) {
            stepDots
            Spacer(minLength: 12)
            if step == 1 {
                Button("Probar con datos de ejemplo", action: loadSample).buttonStyle(.link)
            } else if step == Self.stepCount {
                Button("Saltar por ahora", action: skipBalances).buttonStyle(.link)
            }
            Button("Atrás") { step -= 1 }
                .disabled(step == 1)
            Button(primaryTitle, action: advance)
                .buttonStyle(.primaryCompact)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
        .controlSize(.regular)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background(Palette.background)
    }
    #endif

    // MARK: Acciones

    private func createCompany() {
        do {
            let name = displayName.trimmingCharacters(in: .whitespaces)
            let company = try Bookkeeper(context: context).setUpCompany(
                legalName: legalName.isEmpty ? name : legalName, displayName: name, entityType: entityType,
                state: state, sector: kind.sector
            )
            company.fiscalYearStartMonth = fiscalStartMonth
            company.ein = ein.trimmingCharacters(in: .whitespaces)
            try context.save()
            let books = Bookkeeper(context: context)
            // La tasa estatal base como impuesto predeterminado (nada en los estados sin sales tax estatal).
            try books.setUpStateSalesTax()
            if hasOpeningBalances {
                try books.recordOpeningBalances(bank: openingBank, creditCard: openingCard,
                                                on: Calendar.current.startOfDay(for: openingDate))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSample() {
        do { try SampleData.populate(context) } catch { errorMessage = error.localizedDescription }
    }
}

/// Coloca las vistas en filas y pasa a la siguiente cuando no caben (chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    OnboardingView().modelContainer(try! ChirograStore.makeContainer(inMemory: true))
}
