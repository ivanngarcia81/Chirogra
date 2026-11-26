import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// El símbolo del asistente: los lápices y la ρ del icono de Chirogra, sin el cuadro de fondo (decisión del usuario del
/// 26-nov, en vez de la chispa de siempre). Lápices en el color de la marca con las puntas más claras; la ρ, azafrán.
struct AssistantMark: View {
    var size: CGFloat = 24

    /// Lo que ocupan las piezas en el lienzo de 1024 de `LogoGlyph` (de x 173 a 854 y de y 280 a 759).
    private static let glyphWidth: CGFloat = 681
    private static let glyphCenterY: CGFloat = 519.5

    var body: some View {
        let canvas = size * 1024 / Self.glyphWidth
        ZStack {
            ForEach(LogoGlyph.Part.allCases, id: \.self) { part in
                LogoGlyph(part: part).fill(color(part))
            }
        }
        .frame(width: canvas, height: canvas)
        .offset(y: (512 - Self.glyphCenterY) * canvas / 1024)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func color(_ part: LogoGlyph.Part) -> Color {
        switch part {
        case .penBody, .pencilBody, .penBall: Palette.brand
        case .penCone, .pencilTip: Palette.brand.opacity(0.5)
        case .rho, .shine: Palette.logoRho
        }
    }
}

/// La burbuja flotante (canvas `EntradaB`, `iPadEntradaB`; decisión del usuario del 25-nov): botón redondo de vidrio con
/// el símbolo del asistente, abajo a la derecha, en todas las pantallas.
struct AssistantBubble: View {
    @State private var assistant = AssistantState.shared

    var body: some View {
        if !assistant.isOpen {
            Button { assistant.isOpen = true } label: {
                AssistantMark(size: 30)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Asistente")
            .accessibilityHint(Text("Pregunta por tus números o registra con una frase"))
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// El asistente: hoja en el iPhone y panel al lado en el iPad y el Mac (canvas `Asistente`, `iPadAsistente`).
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @State private var assistant = AssistantState.shared
    @State private var connectivity = AssistantConnectivity.shared
    @State private var subscription = SubscriptionStore.shared
    @ReportBasisSetting private var basis
    @State private var draft = ""
    @FocusState private var composing: Bool

    /// En el panel de la derecha (iPad y Mac): cabecera propia con el título y la «X» dentro del panel. Con la pila de
    /// navegación de la hoja, en el iPad la «X» y el título se iban a la barra del detalle, lejos del panel (26-nov).
    var panel = false

    var body: some View {
        Group {
            if panel {
                VStack(spacing: 0) {
                    panelHeader
                    Divider()
                    content
                }
                .background(Palette.assistantPanel)
                // La línea que lo separa de la pantalla: los dos tienen el mismo fondo gris.
                .overlay(alignment: .leading) {
                    Rectangle().fill(Palette.separator).frame(width: 1).ignoresSafeArea()
                }
            } else {
                NavigationStack {
                    content
                        .navigationTitle("Asistente")
                        .inlineTitle()
                        // Solo con el asistente abierto: evita una «X» de más al cerrarlo.
                        .toolbar {
                            if assistant.isOpen {
                                ToolbarItem(placement: .cancellationAction) { closeButton }
                            }
                            if assistant.isOpen && assistant.consented && !assistant.messages.isEmpty {
                                ToolbarItem(placement: .primaryAction) { newConversationButton }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $assistant.registeringExpense) {
            NavigationStack { ExpenseEditorView() }.editorSheetSizing()
        }
        // «Editar» en una tarjeta de borrador: el editor de siempre, relleno con lo que entendió el asistente.
        .sheet(isPresented: Binding(get: { assistant.editingDraft != nil }, set: { if !$0 { assistant.editingDraft = nil } })) {
            if let id = assistant.editingDraft, let draft = assistant.drafts[id] {
                NavigationStack {
                    switch draft.payload {
                    case .expense(let input):
                        ExpenseEditorView(prefill: input, onSaved: { _ in assistant.markSaved(draft: id) })
                    case .appointment(let input):
                        AppointmentEditorView(prefill: input, onSaved: { _ in assistant.markSaved(draft: id) })
                    case .payment(let payment):
                        if let invoice = payment.invoice { InvoiceDetailView(invoice: invoice) }
                    case .invoice:
                        EmptyView()
                    }
                }
                .editorSheetSizing()
            }
        }
        .sheet(item: $assistant.openingInvoice) { invoice in
            NavigationStack { InvoiceEditorView(editing: invoice) }.editorSheetSizing()
        }
    }

    private var content: some View {
        Group {
            if subscription.isReadOnly {
                locked
            } else if !assistant.consented {
                consent
            } else {
                conversation
            }
        }
        .scrollContentBackground(.hidden)
        .background(panel ? Palette.assistantPanel : Palette.background)
    }

    /// Cabecera del panel: el símbolo y «Asistente» a la izquierda; conversación nueva y cerrar a la derecha.
    private var panelHeader: some View {
        HStack(spacing: 10) {
            AssistantMark(size: 22)
            Text("Asistente").font(.headline).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if assistant.consented && !assistant.messages.isEmpty {
                newConversationButton.labelStyle(.iconOnly).buttonStyle(.bordered).buttonBorderShape(.circle)
            }
            closeButton.labelStyle(.iconOnly).buttonStyle(.bordered).buttonBorderShape(.circle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    private var closeButton: some View {
        Button { assistant.isOpen = false } label: { Label("Cerrar el asistente", systemImage: "xmark") }
            .help(Text("Cerrar el asistente"))
    }

    private var newConversationButton: some View {
        Button { assistant.reset() } label: { Label("Conversación nueva", systemImage: "square.and.pencil") }
            .disabled(assistant.isWorking)
            .help(Text("Conversación nueva"))
    }

    // MARK: Conversación

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if assistant.messages.isEmpty { start } else {
                        ForEach(assistant.messages) { message in
                            AssistantBubbleRow(message: message).id(message.id)
                        }
                        if assistant.isWorking {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Pensando…").font(.subheadline).foregroundStyle(Palette.ink2)
                            }
                            .id("pensando")
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(Metrics.gutter)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: assistant.messages.count) {
                if let last = assistant.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
            }
            .onChange(of: assistant.isWorking) {
                if assistant.isWorking { withAnimation { proxy.scrollTo("pensando", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            #if DEBUG
            // `-qa.asistentePregunta "texto"`: la pregunta se hace sola al abrir (capturas, sin teclear). Solo Debug.
            .task {
                guard !AssistantState.askedQAQuestion, assistant.messages.isEmpty,
                      let question = UserDefaults.standard.string(forKey: "qa.asistentePregunta"), !question.isEmpty else { return }
                AssistantState.askedQAQuestion = true
                assistant.ask(question, context: context, basis: basis)
            }
            #endif
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                AssistantMark(size: 52)
                Text("¿En qué te ayudo?").font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("Pregunta por tus números, busca algo o registra con una frase.")
                    .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            if !connectivity.isOnline {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wifi.slash").foregroundStyle(Palette.warning).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sin conexión").font(.subheadline.weight(.semibold))
                        Text("El asistente necesita internet. Tus libros siguen aquí y puedes registrar a mano.")
                            .font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.warningWash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(spacing: 8) {
                ForEach(AssistantSuggestion.allCases) { suggestion in
                    Button { assistant.ask(suggestion, context: context, basis: basis) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: suggestion.systemImage).foregroundStyle(Palette.brand).frame(width: 24)
                            Text(suggestion.title).foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            // Con la conversación empezada, las sugerencias siguen a mano encima del campo.
            if !assistant.messages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(AssistantSuggestion.allCases) { suggestion in
                            Button { assistant.ask(suggestion, context: context, basis: basis) } label: {
                                Label(suggestion.title, systemImage: suggestion.systemImage)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12).frame(minHeight: 36)
                                    .background(Palette.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.ink)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            HStack(spacing: 8) {
                TextField("Mensaje para el asistente", text: $draft, prompt: Text("Pregunta o pide algo…"), axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.leading, 16)
                    .padding(.vertical, 10)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundStyle(canSend ? Palette.brand : Palette.ink2)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Enviar")
                .padding(.trailing, 8)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 8)
    }

    private var canSend: Bool { !assistant.isWorking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        guard canSend else { return }
        assistant.ask(draft, context: context, basis: basis)
        draft = ""
    }

    // MARK: Permiso y solo lectura

    /// Permiso la primera vez (canvas `AsistentePermiso`; regla 5.1.2(i) de Apple): qué se envía, a quién y que no se guarda.
    private var consent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 8) {
                    AssistantMark(size: 52)
                    Text("Antes de empezar").font(.title2.bold())
                    Text("El asistente usa inteligencia artificial para contestar. Esto pasa con tus datos cada vez que preguntas:")
                        .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                RowGroup(dividerInset: 16 + 30 + 12) {
                    consentRow("paperplane", Palette.blue, "Qué se envía", "Tu pregunta y solo las cifras que el asistente pida para contestarla.")
                    consentRow("server.rack", Palette.indigo, "A quién", "A Anthropic, la empresa que hace el modelo de IA, a través del servidor de Chirogra.")
                    consentRow("checkmark.shield", Palette.green, "No se guarda", "Ni la pregunta ni las cifras se guardan después de contestarte.")
                }
                Link("Leer la política de privacidad", destination: URL(string: String(localized: "https://chirogra.com/privacidad/"))!)
                    .font(.subheadline).frame(maxWidth: .infinity)
                VStack(spacing: 8) {
                    Button("Aceptar y empezar") { withAnimation { assistant.consented = true } }.buttonStyle(PrimaryButtonStyle())
                    Button("Ahora no") { assistant.isOpen = false }.buttonStyle(.plain).foregroundStyle(Palette.brand).frame(minHeight: 44)
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func consentRow(_ symbol: String, _ color: Color, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: symbol, foreground: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.subheadline).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Libros en solo lectura (canvas `AsistenteSoloLectura`).
    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock").font(.system(size: 40)).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            Text("El asistente necesita una suscripción activa").font(.title3.bold()).multilineTextAlignment(.center)
            Text("Tus libros están en solo lectura: puedes verlos y exportarlos, pero no preguntar ni registrar con el asistente.")
                .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            Button("Reactivar suscripción") { assistant.isOpen = false; subscription.showsPaywall = true }
                .buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
            Button("Ahora no") { assistant.isOpen = false }.buttonStyle(.plain).foregroundStyle(Palette.brand).frame(minHeight: 44)
        }
        .padding(32)
        .frame(maxWidth: 520, maxHeight: .infinity)
    }
}

/// Un mensaje: la pregunta a la derecha en una burbuja de Tinta; la respuesta a la izquierda, en texto o en tarjeta.
private struct AssistantBubbleRow: View {
    let message: AssistantMessage

    var body: some View {
        switch message.role {
        case .user:
            if case .text(let text) = message.content {
                Text(text)
                    .foregroundStyle(Palette.onBrandFill)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.brandFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 48)
            }
        case .assistant:
            AssistantAnswer(content: message.content).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Las respuestas con cifras en el estilo de la app (canvas `AsistenteRespuesta`): cifra grande o tabla corta, e «Ir a…».
private struct AssistantAnswer: View {
    let content: AssistantContent

    var body: some View {
        switch content {
        case .text(let text):
            // Las respuestas del modelo traen negritas y listas cortas en Markdown.
            Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
        case let .profit(income, expenses, net, period):
            VStack(alignment: .leading, spacing: 8) {
                Text("Del \(period.start.dayMonth) al \(period.end.dayMonth) llevas:").foregroundStyle(Palette.ink)
                card {
                    Text("Ganancia").font(.subheadline).foregroundStyle(Palette.ink2)
                    Text(net.money).font(.amount(34)).foregroundStyle(net < 0 ? Palette.negative : Palette.brand)
                    HStack(spacing: 16) {
                        Text("Ingresos \(Text(income.money).foregroundStyle(Palette.income))")
                        Text("Gastos \(Text(expenses.money).foregroundStyle(Palette.expense))")
                    }
                    .font(.subheadline)
                    goTo(String(localized: "Ver estado de resultados"), item: .report(.income)) { ReportsView(fixedKind: .income) }
                }
            }
        case let .receivables(total, rows, count):
            let overdue = rows.filter(\.isOverdue).count
            VStack(alignment: .leading, spacing: 8) {
                Text(overdue > 0 ? String(localized: "Te deben \(total.money) en \(count) facturas. \(overdue) ya vencieron:")
                                 : String(localized: "Te deben \(total.money) en \(count) facturas."))
                    .foregroundStyle(Palette.ink)
                card {
                    ForEach(rows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.customer).foregroundStyle(Palette.ink)
                                StatusChip(text: row.status, foreground: row.isOverdue ? Palette.negative : Palette.ink2, compact: true,
                                           dot: row.isOverdue ? Palette.red : Palette.gray)
                            }
                            Spacer()
                            Text(row.amount.money).foregroundStyle(Palette.ink).monospacedDigit()
                        }
                        Divider()
                    }
                    HStack {
                        Text("Total por cobrar").fontWeight(.semibold)
                        Spacer()
                        Text(total.money).fontWeight(.semibold).monospacedDigit()
                    }
                    goTo(String(localized: "Ver Por cobrar"), item: .sales(.invoices)) { SalesView(fixedSegment: .invoices) }
                }
            }
        case .draft(let id):
            AssistantDraftCard(id: id)
        case .screen(let item):
            goTo(String(localized: "Ir a \(AssistantScreens.title(item))"), item: item) { item.destination }
                .padding(.horizontal, 14)
                .background(Palette.surface, in: Capsule())
        case .setAside(let summary):
            VStack(alignment: .leading, spacing: 8) {
                Text("Con tu \(summary.percent) %, para el pago del \(summary.focus.period.due.formatted(.appDateTime.day().month(.wide))):")
                    .foregroundStyle(Palette.ink)
                card {
                    Text("Aparta").font(.subheadline).foregroundStyle(Palette.ink2)
                    Text(summary.focus.toSetAside.money).font(.amount(34)).foregroundStyle(Palette.ink)
                    Text("\(summary.percent) % de \(summary.focus.profit.money) de ganancia este periodo").font(.subheadline).foregroundStyle(Palette.ink2)
                    Text(summary.daysLeft >= 0 ? String(localized: "Faltan \(summary.daysLeft) días. Es una guía, no asesoría fiscal.")
                                               : String(localized: "Es una guía, no asesoría fiscal."))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                    goTo(String(localized: "Ver impuestos estimados"), item: .taxes(.estimated)) { EstimatedTaxView() }
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    /// «Ir a…»: en el iPad y el Mac abre la sección en la pantalla de al lado; en el iPhone, encima del asistente.
    private func goTo<Destination: View>(_ title: String, item: SidebarItem, @ViewBuilder destination: () -> Destination) -> some View {
        SectionLink(item: item, destination: destination) {
            HStack(spacing: 4) { Text(title); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)) }
                .foregroundStyle(Palette.brand)
                .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
    }
}

/// La tarjeta de un borrador (canvas `AsistenteRespuesta`, «Gasto $85 · Adobe · Software · Tarjeta»): lo que entendió
/// el asistente, lo que falta y «Guardar» o «Editar». Nada se guarda sin pulsar «Guardar».
private struct AssistantDraftCard: View {
    let id: UUID
    @Environment(\.modelContext) private var context
    @State private var assistant = AssistantState.shared

    var body: some View {
        if let draft = assistant.drafts[id] {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: draft.systemImage).foregroundStyle(Palette.brand).accessibilityHidden(true)
                    Text(draft.title).font(.headline).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    if case .saved = draft.state {
                        StatusChip(text: String(localized: "Guardado"), foreground: Palette.positive, compact: true, dot: Palette.green)
                    }
                }
                VStack(spacing: 6) {
                    ForEach(Array(draft.rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label).foregroundStyle(Palette.ink2)
                            Spacer(minLength: 8)
                            Text(row.value).foregroundStyle(row.value == "—" ? Palette.ink2 : Palette.ink)
                                .multilineTextAlignment(.trailing).monospacedDigit()
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
                if !draft.missing.isEmpty, draft.state == .pending {
                    Text("Para guardar, falta: \(draft.missing.joined(separator: ", ")).")
                        .font(.footnote).foregroundStyle(Palette.warning)
                }
                if case .failed(let message) = draft.state {
                    Text(message).font(.footnote).foregroundStyle(Palette.negative)
                }
                buttons(draft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func buttons(_ draft: AssistantDraft) -> some View {
        switch draft.state {
        case .saved(let invoiceID):
            if let invoiceID {
                Button("Abrir el borrador") {
                    assistant.openingInvoice = try? Bookkeeper(context: context).fetch(Invoice.self).first { $0.id == invoiceID }
                }
                .buttonStyle(.bordered)
            }
        case .pending, .saving, .failed:
            HStack(spacing: 10) {
                Button {
                    assistant.save(draft: id, context: context)
                } label: {
                    Text(isInvoice(draft) ? "Guardar borrador" : "Guardar").frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
                .disabled(!draft.canSave)
                if canEdit(draft) {
                    Button("Editar") { assistant.editingDraft = id }.buttonStyle(.bordered)
                }
            }
            .padding(.top, 2)
        }
    }

    private func isInvoice(_ draft: AssistantDraft) -> Bool {
        if case .invoice = draft.payload { true } else { false }
    }

    /// La factura se corrige al abrir su borrador; un cobro sin factura no tiene dónde corregirse.
    private func canEdit(_ draft: AssistantDraft) -> Bool {
        switch draft.payload {
        case .expense, .appointment: true
        case .payment(let payment): payment.invoice != nil
        case .invoice: false
        }
    }
}

/// La burbuja y dónde se abre el asistente: en el iPhone, en una hoja, con la burbuja encima de la barra de pestañas;
/// en el iPad y el Mac, en el panel de la derecha (inspector).
struct AssistantPresentation: ViewModifier {
    let compact: Bool
    /// Solo uno de los dos sitios lo pone (la pestaña en el iPhone, la columna de detalle en el iPad y el Mac).
    var enabled = true
    @State private var assistant = AssistantState.shared

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if compact {
            content
                .overlay(alignment: .bottomTrailing) {
                    AssistantBubble().padding(.trailing, 20).padding(.bottom, 96)
                }
                .sheet(isPresented: $assistant.isOpen) { AssistantView() }
        } else {
            content
                #if os(iOS)
                .overlay(alignment: .bottomTrailing) {
                    AssistantBubble().padding(.trailing, 24).padding(.bottom, 24)
                }
                #else
                // En el Mac, un botón de la barra en vez de la burbuja: la burbuja tapaba los botones de abajo del
                // inspector que ya tienen muchas pantallas («Abrir factura» en Inicio).
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { assistant.isOpen.toggle() } label: { Label { Text("Asistente") } icon: { AssistantMark(size: 18) } }
                            .help(Text("Asistente (⌘K)"))
                    }
                }
                #endif
                // ⌘K abre y cierra el asistente (iPad con teclado y Mac; plan de la 1.4, decisión del 26-nov).
                .background {
                    Button("Asistente") { assistant.isOpen.toggle() }
                        .keyboardShortcut("k", modifiers: .command)
                        .hidden()
                }
                .inspector(isPresented: $assistant.isOpen) {
                    AssistantView(panel: true).inspectorColumnWidth(min: 340, ideal: 380, max: 480)
                }
        }
    }
}
