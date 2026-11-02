import ChirograCore
import ChirograData
import SwiftUI

// MARK: - Formato

extension Int64 {
    /// Centavos → "$1,250.00".
    var money: String { Money(minorUnits: self).formatted() }
    /// Centavos → "$1,250": cifras clave del canvas, sin centavos (redondeado).
    var moneyWhole: String {
        Money(minorUnits: self).decimalValue.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    /// Centavos → "1,250.00": columnas de importes del iPhone, donde el "$" de cada fila quitaba sitio al nombre.
    var amountOnly: String {
        Money(minorUnits: self).decimalValue.formatted(.number.precision(.fractionLength(2)))
    }
}

extension Locale {
    /// Locales de las fechas para un idioma y una región. `numeric` es el idioma con la región del dispositivo,
    /// así el orden de las fechas en cifras sigue la región (DISEÑO §7.4: en EE. UU., «11/16/2026» también en
    /// español). `text`, para fechas con el mes en letra, es igual salvo en español de EE. UU., donde se usa el de
    /// Latinoamérica: escribe «16 nov 2026» como el canvas (es_US escribe «nov 16, 2026»).
    nonisolated static func dateLocales(language: String, region: String) -> (numeric: Locale, text: Locale) {
        let numeric = Locale(identifier: "\(language)_\(region)")
        return (numeric, language == "es" && region == "US" ? Locale(identifier: "es_419") : numeric)
    }

    nonisolated private static let appDates: (numeric: Locale, text: Locale) = {
        let language = (Bundle.main.preferredLocalizations.first ?? Locale.current.language.languageCode?.identifier ?? "es")
            .prefix(2)
        return dateLocales(language: String(language), region: Locale.current.region?.identifier ?? "US")
    }()

    /// Fechas en cifras («11/16/2026»): idioma de la app y región del dispositivo.
    nonisolated static var app: Locale { appDates.numeric }
    /// Fechas con el mes en letra («16 nov 2026»). También va en el entorno de SwiftUI, para que los selectores de
    /// fecha salgan en el idioma de la app y no en el del sistema.
    nonisolated static var appText: Locale { appDates.text }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// Como `.dateTime`, pero con `Locale.appText` (las fechas de la app llevan el mes en letra).
    nonisolated static var appDateTime: Date.FormatStyle { Date.FormatStyle(locale: .appText) }
}

extension Date {
    /// Mes en tres letras como en el canvas («sep», «oct»; la abreviatura del sistema en español es «sept.»).
    var shortMonth: String { formatted(.appDateTime.month(.wide)).prefix(3).lowercased() }
}

extension Date {
    var shortDate: String { formatted(.appDateTime.day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(.appDateTime.day().month(.abbreviated)) }
    /// «Octubre de 2026»: solo la primera letra en mayúscula (`capitalized` daría «Octubre De 2026»).
    var monthYear: String { formatted(.appDateTime.month(.wide).year()).sentenceCased }
    /// «vence Oct 28» con espacios de no separación: en una fila estrecha se parte antes, nunca dentro.
    var dueLabel: String { String(localized: "vence \(dayMonth)").replacingOccurrences(of: " ", with: "\u{00A0}") }
}

extension RawRepresentable where RawValue == String {
    /// Texto visible de un enum cuyo `rawValue` es la etiqueta en español: se busca en el catálogo en tiempo de ejecución.
    /// El compilador no extrae estos textos; están añadidos a mano en `App/Localizable.xcstrings`.
    var localizedTitle: String { String(localized: String.LocalizationValue(rawValue)) }
}

extension String {
    /// Primera letra en mayúscula y el resto tal cual, como se escribe en español.
    nonisolated var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}

extension View {
    /// Hoja de un editor: con texto de accesibilidad, del tamaño de página (en el iPad la hoja de formulario se
    /// quedaba pequeña y solo cabían dos o tres campos).
    func editorSheetSizing() -> some View { modifier(EditorSheetSizing()) }
}

private struct EditorSheetSizing: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize { content.presentationSizing(.page) } else { content }
    }
}

/// Testigo de un editor abierto: vive en el estado de la vista, así que desaparece con ella.
final class EditorToken {}

/// Cambios sin guardar de los editores abiertos. Lo consulta la barra lateral antes de cambiar de pantalla: rehacer la
/// vista dividida cierra el editor y se perdería lo escrito. Cada editor se registra con su propio testigo, para que
/// una hoja abierta encima (p. ej. un cliente nuevo desde la factura) no borre el estado del editor de debajo. El
/// registro guarda el testigo de forma débil: si la vista del editor ya no existe, deja de contar aunque `onDisappear`
/// no haya llegado (o haya llegado antes que el último aviso de cambios).
@Observable
final class UnsavedChanges {
    private struct Entry {
        weak var token: EditorToken?
        let discard: () -> Void
    }

    @ObservationIgnored private var entries: [ObjectIdentifier: Entry] = [:]

    /// Solo cuentan los editores que siguen existiendo.
    var hasChanges: Bool { entries.values.contains { $0.token != nil } }

    /// `discard`: lo que hace el editor al descartar (p. ej. borrar el borrador que guardó la vista previa).
    func report(_ editor: EditorToken, hasChanges: Bool, discard: @escaping () -> Void = {}) {
        entries = entries.filter { $0.value.token != nil }
        entries[ObjectIdentifier(editor)] = hasChanges ? Entry(token: editor, discard: discard) : nil
    }

    func remove(_ editor: EditorToken) { entries[ObjectIdentifier(editor)] = nil }

    /// Hasta cuándo puede cambiar el registro por un aviso de «Cancelar»: en el iPad, un toque en la barra lateral
    /// llega antes que la acción de «Descartar», que se ejecuta mientras el aviso se cierra.
    @ObservationIgnored private(set) var settlingUntil: Date?

    /// Un aviso de «Cancelar» se abre (`isOpen`) o se cierra: mientras está abierto, y un momento después, su acción
    /// aún puede retirar el editor.
    func confirmation(isOpen: Bool, settleFor seconds: TimeInterval = 1.2, now: Date = .now) {
        settlingUntil = isOpen ? .distantFuture : now.addingTimeInterval(seconds)
    }

    func isSettling(at now: Date = .now) -> Bool { settlingUntil.map { now < $0 } ?? false }

    func removeAll() { entries = [:]; settlingUntil = nil }

    func discardAll() {
        entries.values.filter { $0.token != nil }.forEach { $0.discard() }
        entries = [:]
    }
}

extension View {
    /// Editor que se puede descartar: compara `value` (lo que escribe el usuario) con lo que había al abrirlo y, si
    /// hay cambios, «Cancelar» pregunta antes de cerrarlo (con el aviso anclado al botón), la hoja no se cierra
    /// deslizando y la barra lateral pregunta antes de cambiar de pantalla.
    ///
    /// `token` es el testigo del editor: al guardar, el editor lo retira de `UnsavedChanges` antes de cerrarse, porque
    /// durante la animación de salida seguiría contando y la barra lateral preguntaría sin ningún editor a la vista.
    func discardableEditor<Value: Equatable>(tracking value: Value, token: EditorToken,
                                             onDiscard: @escaping () -> Void = {}) -> some View {
        modifier(DiscardableEditor(value: value, token: token, onDiscard: onDiscard))
    }

    /// Informa de los cambios de un editor que pone su propio «Cancelar» (la factura, que además conserva borradores).
    func reportsUnsavedChanges(_ hasChanges: Bool, token: EditorToken, onDiscard: @escaping () -> Void = {}) -> some View {
        modifier(UnsavedChangesReporter(hasChanges: hasChanges, token: token, onDiscard: onDiscard))
    }
}

private struct DiscardableEditor<Value: Equatable>: ViewModifier {
    let value: Value
    let token: EditorToken
    let onDiscard: () -> Void
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// El cierre del editor, leído aquí y no dentro del botón de la barra: en una hoja del Mac, el `dismiss` de un
    /// ítem de la barra no cerraba la hoja («Cancelar», «Descartar» y Escape no hacían nada).
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: Value?
    /// Se toma la referencia tras el primer ciclo, cuando el editor ya cargó sus datos y valores por defecto.
    @State private var readyForBaseline = false

    private var hasChanges: Bool { baseline.map { $0 != value } ?? false }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelEditorButton(hasChanges: hasChanges, close: dismiss) { onDiscard(); unsavedChanges?.remove(token) }
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .reportsUnsavedChanges(hasChanges, token: token, onDiscard: onDiscard)
            .onAppear { if baseline == nil { Task { @MainActor in readyForBaseline = true } } }
            .onChange(of: readyForBaseline) { if baseline == nil { baseline = value } }
    }
}

private struct UnsavedChangesReporter: ViewModifier {
    let hasChanges: Bool
    let token: EditorToken
    let onDiscard: () -> Void
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Solo informa mientras el editor está en pantalla, sea cual sea el orden de los avisos.
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear { isVisible = true; report() }
            .onChange(of: hasChanges) { report() }
            .onDisappear { isVisible = false; unsavedChanges?.remove(token) }
    }

    private func report() {
        unsavedChanges?.report(token, hasChanges: hasChanges && isVisible, discard: onDiscard)
    }
}

/// «Cancelar» de un editor: con cambios, pregunta «¿Descartar los cambios?» antes de cerrarlo. `onDiscard` se llama
/// justo antes de cerrar (y retira el registro de cambios sin esperar a que termine la animación).
struct CancelEditorButton: View {
    let hasChanges: Bool
    /// El cierre del editor que lo pone (ver `DiscardableEditor`).
    let close: DismissAction
    var onDiscard: () -> Void = {}
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var confirming = false

    var body: some View {
        Button("Cancelar") { if hasChanges { confirming = true } else { close() } }
            .confirmationDialog("¿Descartar los cambios?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Descartar", role: .destructive) { onDiscard(); close() }
                Button("Seguir editando", role: .cancel) {}
            }
            .onChange(of: confirming) { unsavedChanges?.confirmation(isOpen: confirming) }
            .headerButton()
    }
}

extension EnvironmentValues {
    @Entry var unsavedChanges: UnsavedChanges?
}


// MARK: - Tipografía

extension Font {
    /// Cifras destacadas (tarjeta de efectivo, totales). El tamaño del canvas se traduce al estilo de texto
    /// más cercano para que escale con Dynamic Type.
    static func amount(_ size: CGFloat) -> Font {
        let style: Font.TextStyle = switch size {
        case 34...: .largeTitle
        case 26..<34: .title
        case 21..<26: .title2
        case 18..<21: .title3
        default: .headline
        }
        return .system(style, weight: .bold).monospacedDigit()
    }
    static let cardTitle = Font.headline
    static let label = Font.caption.weight(.semibold)
}

// MARK: - Superficies

extension EnvironmentValues {
    /// Las tarjetas ocupan todo el alto disponible: dos tarjetas lado a lado miden lo mismo (canvas `MacInicio`).
    @Entry var cardFillsHeight = false
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    @Environment(\.cardFillsHeight) private var fillsHeight
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Metrics.cardPadding) -> some View { modifier(CardModifier(padding: padding)) }

    /// Campo con borde de los tableros de Mac (`MacDiario`): alto 38, radio 10, fondo de superficie.
    func fieldBox() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
    }

    /// Fondo de pantalla del canvas, en listas y en vistas con scroll.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.background)
    }

    /// Título de pantalla (§7.4, decisión del usuario): en el iPad, grande dentro de la barra de vidrio del sistema,
    /// junto al botón de la barra lateral y a los botones, sin franja vacía encima; en el Mac, el de la ventana; en el
    /// iPhone, el título grande de siempre, que se pliega al desplazar. Va en cada pantalla: las que se abren encima no
    /// heredan el modo.
    func headerTitle() -> some View {
        modifier(HeaderTitle())
    }

    /// Título de una ficha (cliente, proveedor): su nombre, pequeño en la barra, y en el Mac la sección debajo, como
    /// las migas de los tableros («Clientes › Hotel Mirador»). Sin título, el botón de volver decía «Chirogra».
    func recordTitle(_ name: String, section: String) -> some View {
        #if os(macOS)
        navigationTitle(name).navigationSubtitle(section)
        #else
        navigationTitle(name).inlineTitle()
        #endif
    }

    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Botones

/// Botones de acción dentro del contenido (§7.4, decisión del usuario): vidrio del sistema (`glassEffect`), sin
/// relleno de marca. El primario se distingue del secundario por el peso del texto (semibold en `ink` frente a
/// regular en `ink2`); el destructivo, por el texto en `negative`. `ink` e `ink2` cumplen AA sobre el vidrio en claro
/// y en oscuro.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .padding(.horizontal, 22)
            .foregroundStyle(isEnabled ? Palette.ink : Palette.ink3)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .glassEffect(.regular.interactive(isEnabled), in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(destructive ? .body.weight(.semibold) : .body)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .padding(.horizontal, 22)
            .foregroundStyle(!isEnabled ? Palette.ink3 : destructive ? Palette.negative : Palette.ink2)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .glassEffect(.regular.interactive(isEnabled), in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var destructive: SecondaryButtonStyle { SecondaryButtonStyle(destructive: true) }
}

// MARK: - Chips de estado

struct StatusChip: View {
    let text: String
    let foreground: Color
    let background: Color
    var compact = false

    var body: some View {
        Text(text)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 2 : 5)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }
}

extension Invoice {
    /// Nombre del estado, igual que en su chip («Vencida», «Pago parcial»…).
    var statusTitle: String {
        if daysOverdue() != nil { return String(localized: "Vencida") }
        return switch status {
        case .draft: String(localized: "Borrador")
        case .sent: String(localized: "Enviada")
        case .partiallyPaid: String(localized: "Pago parcial")
        case .paid: String(localized: "Pagada")
        case .void: String(localized: "Anulada")
        }
    }
}

extension StatusChip {
    /// Estados de factura del canvas: Borrador, Enviada, Pago parcial, Vencida · N días, Pagada (+ Anulada).
    init(invoice: Invoice, compact: Bool = true) {
        if let days = invoice.daysOverdue() {
            self.init(text: String(localized: "Vencida · \(days) días"), foreground: Palette.negative, background: Palette.negativeWash, compact: compact)
            return
        }
        switch invoice.status {
        case .draft: self.init(text: String(localized: "Borrador"), foreground: Palette.ink2, background: Palette.surface2, compact: compact)
        case .sent: self.init(text: String(localized: "Enviada"), foreground: Palette.brand, background: Palette.brandWash, compact: compact)
        case .partiallyPaid: self.init(text: String(localized: "Pago parcial"), foreground: Palette.warning, background: Palette.warningWash, compact: compact)
        case .paid: self.init(text: String(localized: "Pagada"), foreground: Palette.positive, background: Palette.positiveWash, compact: compact)
        case .void: self.init(text: String(localized: "Anulada"), foreground: Palette.ink3, background: Palette.surface2, compact: compact)
        }
    }

    init(bill: Bill, compact: Bool = true) {
        switch bill.status {
        case .open: self.init(text: String(localized: "Por pagar"), foreground: Palette.brand, background: Palette.brandWash, compact: compact)
        case .partiallyPaid: self.init(text: String(localized: "Pago parcial"), foreground: Palette.warning, background: Palette.warningWash, compact: compact)
        case .paid: self.init(text: String(localized: "Pagada"), foreground: Palette.positive, background: Palette.positiveWash, compact: compact)
        case .void: self.init(text: String(localized: "Anulada"), foreground: Palette.ink3, background: Palette.surface2, compact: compact)
        }
    }
}

/// Chip de filtro o de tipo de reporte: área táctil de 44 pt como mínimo y rasgo de seleccionado.
struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).fontWeight(.semibold)
                if let count { Text("\(count)").foregroundStyle(isSelected ? Palette.background.opacity(0.8) : Palette.ink3) }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.target)
            .foregroundStyle(isSelected ? Palette.background : Palette.ink2)
            .background(isSelected ? Palette.ink : Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Palette.ink : Palette.separator))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Piezas de lista

/// Iniciales en un cuadrado redondeado o, para clientes (canvas `Clientes`), en un círculo.
struct InitialsTile: View {
    let text: String
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    var round = false
    @ScaledMetric(relativeTo: .subheadline) private var side = Metrics.iconTile

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .frame(width: side, height: side)
            .foregroundStyle(foreground)
            .background(background, in: round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
            .accessibilityHidden(true)
    }
}

struct IconTile: View {
    let systemImage: String
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    @ScaledMetric(relativeTo: .body) private var side = Metrics.iconTile

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .frame(width: side, height: side)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Fila del canvas: icono o iniciales, título, subtítulo e importe con chip opcional, sin chevron
/// (`navigationLinkIndicatorVisibility(.hidden)` en la lista). Con tamaños de accesibilidad icono, texto e
/// importe van en columna.
struct LedgerRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    /// Líneas del subtítulo: 2 para correos, que recortados por el medio no se leían.
    var subtitleLines = 1
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Todo en columna: el icono crece con el texto y, a su lado, partía el nombre en sílabas.
                VStack(alignment: .leading, spacing: 6) {
                    leading
                    texts
                    trailing
                }
            } else {
                HStack(spacing: 12) {
                    leading
                    texts.layoutPriority(1)
                    Spacer(minLength: 8)
                    trailing.fixedSize()
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Una línea por dato, como en el canvas («F-1047 · vence 12 nov»). Si no cabe, el subtítulo se encoge un poco
    /// antes de recortarse por el medio, así no se pierde el vencimiento del final. Con tamaños de accesibilidad
    /// se permiten varias líneas.
    private var texts: some View {
        let lines = dynamicTypeSize.isAccessibilitySize ? nil : 1 as Int?
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(lines)
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink3)
                .lineLimit(lines.map { _ in subtitleLines })
                .minimumScaleFactor(0.85)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: lines == nil)
        }
    }
}

/// Texto a la izquierda y valor a la derecha; con tamaños de accesibilidad, uno debajo del otro,
/// para que ni las palabras ni las cifras se partan en varias líneas.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                leading
                trailing
            }
        } else {
            HStack(alignment: alignment) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

extension DynamicTypeSize {
    /// Alineación de la columna de importe de una `LedgerRow`: a la derecha, o a la izquierda cuando la fila va en columna.
    var amountAlignment: HorizontalAlignment { isAccessibilitySize ? .leading : .trailing }
}

/// Encabezado de sección del canvas: mayúsculas 12/600 con espaciado, en `ink3` («CONTABILIDAD»).
struct SectionLabel: View {
    let text: String
    var body: some View {
        // `textCase` y no `uppercased()`: se ve igual, pero VoiceOver lee el texto original (no deletrea «MÁS»).
        Text(text)
            .textCase(.uppercase)
            .font(.label)
            .tracking(0.6)
            .foregroundStyle(Palette.ink3)
    }
}

extension Section where Parent == SectionLabel, Footer == EmptyView, Content: View {
    /// Sección de lista con el encabezado del canvas en vez del de iOS (tipo oración, 17 pt).
    init(title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SectionLabel(text: String(localized: title)) }
    }

    /// Igual, para títulos que vienen de los datos (tipo de cuenta, agencia).
    init(heading: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SectionLabel(text: heading) }
    }
}

/// Fila «etiqueta · valor» con el valor en `ink`, como en el canvas (iOS lo pinta en gris secundario).
/// Los selectores de menú y los interruptores de los formularios también pasan por este estilo, así que nunca
/// se recorta nada: si etiqueta y valor no caben en una línea, el valor baja a la siguiente (siempre, con
/// tamaños de accesibilidad).
struct InkValueLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: LabeledContentStyleConfiguration
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    // Centrado: los interruptores y selectores no tienen línea base.
                    HStack(alignment: .center, spacing: 12) {
                        configuration.label.fixedSize()
                        Spacer(minLength: 0)
                        configuration.content.foregroundStyle(Palette.ink).fixedSize()
                    }
                    stacked
                }
            }
        }

        private var stacked: some View {
            VStack(alignment: .leading, spacing: 4) {
                configuration.label
                configuration.content.foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pestañas de texto subrayadas (canvas `Ventas`): la activa en color de marca con un subrayado de 2.5 pt,
/// el resto en `ink2`, y una línea fina debajo de todas.
struct UnderlineTabs<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Button { selection = option } label: {
                        Text(title(option))
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Palette.brand : Palette.ink2)
                            .frame(minHeight: Metrics.target)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(isSelected ? Palette.brand : .clear).frame(height: 2.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }
}

/// Barra de acciones fija abajo (canvas `FacturaNueva`, `FacturaEnviar`): fondo de superficie con una línea
/// arriba, botones uno al lado del otro; con tamaños de accesibilidad, uno debajo del otro.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout { content }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.surface)
            .overlay(alignment: .top) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }
}

extension View {
    /// Fija `BottomActionBar` sobre el borde inferior: los botones no se van con el scroll.
    func bottomActionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { BottomActionBar(content: content) }
    }
}

// MARK: - Fichas (canvas `ClienteFicha`, `ProveedorFicha`)

/// Cabecera de ficha: avatar de 56 pt (círculo para clientes, cuadrado para proveedores), nombre grande y detalle.
struct ProfileHeader: View {
    var initials: String? = nil
    var systemImage: String? = nil
    let name: String
    let detail: String
    var round = false
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 56

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let systemImage { Image(systemName: systemImage).font(.title2) } else { Text(initials ?? "").font(.title3.weight(.bold)) }
            }
            .foregroundStyle(foreground)
            .frame(width: side, height: side)
            .background(background, in: round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.title.weight(.bold)).foregroundStyle(Palette.ink).lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Text(detail).font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
    }
}

/// Acción de la ficha (Llamar, Correo, Factura): icono sobre el texto, en tarjeta.
struct ProfileAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3).accessibilityHidden(true)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isEnabled ? Palette.brand : Palette.ink3)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Cifra pequeña de ficha: etiqueta y valor en una tarjeta (canvas `ProveedorFicha`).
struct MiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.body.weight(.bold)).foregroundStyle(Palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Botón «+» de las pantallas de lista: círculo relleno en color de marca (canvas `Ventas`, `Clientes`).
extension View {
    /// Botón de la cabecera (§7.4, decisión del usuario): el vidrio que la barra del sistema ya pone a sus ítems, con el
    /// texto en tinta y no en el color de marca. `ink` se lee sobre el vidrio en claro y en oscuro.
    func headerButton() -> some View {
        tint(Palette.ink)
    }

    /// Botón de vidrio compacto dentro de filas y tarjetas (por ejemplo «Pagar» en una tabla): el `.glass` del sistema
    /// con el texto en tinta, como los de la cabecera.
    func glassActionButton() -> some View {
        buttonStyle(.glass).tint(Palette.ink).fontWeight(.semibold)
    }
}

private struct HeaderTitle: ViewModifier {
    #if os(iOS)
    // El del sistema y no `LayoutSizeClass`: también con la columna estrecha del iPad el título va en la barra.
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbarTitleDisplayMode(sizeClass == .regular ? .inlineLarge : .automatic)
        #else
        // En el Mac, el título de la ventana, con el tamaño que le da el sistema (`.inlineLarge` no lo agranda), en la
        // fila de las acciones y una sola vez: ya no se repite en grande en el contenido.
        content
        #endif
    }
}

struct AddButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: title), systemImage: "plus").labelStyle(.iconOnly)
        }
        .headerButton()
    }
}

/// Cifra clave de iPad y Mac (canvas `MacInicio`, `MacPyG`): etiqueta, importe y pie; la destacada en color de marca.
struct KPIItem: Identifiable {
    let title: String
    let value: String
    var foot: String? = nil
    var footColor: Color = Palette.ink3
    var isBrand = false
    var id: String { title }
}

/// Rejilla de cifras clave a todo el ancho, como `auto-fit minmax(…, 1fr)` del canvas: todas en una fila si caben
/// al ancho mínimo; si no, cuatro tarjetas van en 2×2 (nunca 3 + 1 sola). `large` usa las medidas de `MacInicio`.
struct KPIGrid: View {
    let items: [KPIItem]
    var large = false
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .title2) private var minimumWidth: CGFloat = 160

    private var spacing: CGFloat { large ? 14 : 12 }

    /// Cifra de las tarjetas grandes: 24 pt en iPad (`iPadInicio`), 28 en Mac (`MacInicio`).
    #if os(macOS)
    private static let largeAmount: CGFloat = 28
    #else
    private static let largeAmount: CGFloat = 24
    #endif

    private var columns: Int {
        let available = width + spacing
        let minimum = (large ? minimumWidth * 1.25 : minimumWidth) + spacing
        if available >= CGFloat(items.count) * minimum { return items.count }
        if items.count == 4 { return 2 }
        return max(1, min(items.count, Int(available / minimum)))
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: large ? 6 : 4) {
                    Text(item.title).font((large ? Font.footnote : .caption).weight(.semibold))
                        .foregroundStyle(item.isBrand ? Palette.onBrand.opacity(0.85) : Palette.ink3)
                    Text(item.value).font(.amount(large ? Self.largeAmount : 22)).minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(item.isBrand ? Palette.onBrand : Palette.ink)
                    // Siempre una línea de pie, aunque esté vacía, para que todas las tarjetas midan lo mismo.
                    Text(item.foot ?? " ").font((large ? Font.footnote : .caption).weight(.semibold)).lineLimit(1)
                        .foregroundStyle(item.isBrand ? Palette.onBrand.opacity(0.9) : item.footColor)
                }
                .padding(.horizontal, large ? 18 : 16)
                .padding(.vertical, large ? 16 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(item.isBrand ? Palette.brand : Palette.surface,
                            in: RoundedRectangle(cornerRadius: large ? 16 : 14, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue([item.value, item.foot].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

struct KPITile: View {
    let title: String
    let value: String
    var note: String? = nil
    var noteColor: Color = Palette.ink3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
            Text(value).font(.amount(17)).foregroundStyle(Palette.ink).minimumScaleFactor(0.7).lineLimit(2)
            // Una línea, como en el canvas («↑ 12% vs. sep»); se encoge un poco antes de cortarse.
            if let note { Text(note).font(.caption.weight(.semibold)).foregroundStyle(noteColor).lineLimit(1).minimumScaleFactor(0.75) }
        }
        .card(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, note.map(Self.spoken)].compactMap { $0 }.joined(separator: ", "))
    }

    /// Las flechas de variación se leen como palabras («sube», «baja»), no como símbolos.
    static func spoken(_ note: String) -> String {
        note.replacingOccurrences(of: "↑", with: String(localized: "sube")).replacingOccurrences(of: "↓", with: String(localized: "baja"))
    }
}

/// Tarjeta destacada en color de marca (efectivo disponible, ganancia neta).
struct HeroCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    /// Insignia azafrán junto a la cifra («+34% vs. sep», canvas `ReportePyG`).
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).opacity(0.85)
            Text(value).font(.amount(38)).tracking(-0.5).minimumScaleFactor(0.6).lineLimit(2)
            if let badge {
                Text(badge).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.accent, in: Capsule())
            }
            if let detail {
                HStack(spacing: 8) {
                    Circle().fill(Palette.accent).frame(width: 8, height: 8)
                    Text(detail).font(.subheadline)
                }
                .opacity(0.9)
            }
        }
        .foregroundStyle(Palette.onBrand)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brand, in: RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Estado vacío / primera vez del canvas.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .accessibilityHidden(true)
                .foregroundStyle(Palette.ink3)
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text(message).font(.subheadline).foregroundStyle(Palette.ink3).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.secondary).fixedSize()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Logotipo de Chirogra: cuadrado en tinta, "C" abierta y punto de azafrán.
struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 11 / 40, style: .continuous).fill(Palette.brand)
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Palette.onBrand, style: StrokeStyle(lineWidth: size * 3.4 / 40, lineCap: .round))
                .frame(width: size * 18 / 40, height: size * 18 / 40)
            Circle().fill(Palette.accent)
                .frame(width: size * 5.4 / 40, height: size * 5.4 / 40)
                .offset(x: size * 8.6 / 40)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Chirogra")
    }
}

// MARK: - Campos

/// Campo de importe en dólares enlazado a centavos.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int64

    var body: some View {
        TextField(title, value: decimal, format: .currency(code: "USD"))
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private var decimal: Binding<Decimal> {
        Binding(
            get: { Money(minorUnits: minorUnits).decimalValue },
            set: { minorUnits = Money(decimal: $0).minorUnits }
        )
    }
}

/// Selector de cuenta filtrado (p. ej. solo cuentas de dinero o de gasto).
struct AccountPicker: View {
    let title: String
    let accounts: [Account]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Elegir…").tag(UUID?.none)
            ForEach(accounts) { account in
                Text(account.displayName).tag(Optional(account.id))
            }
        }
    }
}

/// Mensaje de error recuperable con texto claro.
struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.negative)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.negativeWash, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
    }
}
